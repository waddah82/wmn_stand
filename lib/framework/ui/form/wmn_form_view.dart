import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/localization/wmn_localization.dart';
import '../../../modules/customization/application/customization_service.dart';
import '../../../platform/storage/wmn_storage_service.dart';
import '../../../platform/files/wmn_file_adapter.dart';
import '../../../platform/files/wmn_file_interaction_service.dart';
import '../../../platform/files/wmn_file_service.dart';
import '../../../platform/printing/wmn_print_preview_dialog.dart';
import '../../../platform/printing/wmn_print_template_engine.dart';
import '../../../platform/printing/wmn_printing_service.dart';
import '../../frappe_compat/frappe_runtime.dart';
import '../../frappe_compat/frappe_workflow.dart';
import '../../meta/doctype_meta.dart';
import '../../meta/field_control_resolver.dart';
import '../../meta/meta_service.dart';
import '../../model/document_service.dart';

enum WmnFormPresentation { page, dialog }

typedef WmnQuickCreateLinkCallback = Future<String?> Function(String doctype);
typedef WmnManageLinkCallback = Future<void> Function(String doctype);
typedef WmnOpenReportCallback = Future<void> Function(String reportName);

class WmnFormView extends StatefulWidget {
  const WmnFormView({
    super.key,
    required this.doctype,
    required this.meta,
    required this.documents,
    required this.customization,
    this.documentName,
    this.presentation = WmnFormPresentation.page,
    this.onSaved,
    this.onManageLinkRecords,
    this.onOpenReport,
    this.fileInteractions,
  });

  final String doctype;
  final String? documentName;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final CustomizationService customization;
  final WmnFormPresentation presentation;
  final ValueChanged<Map<String, Object?>>? onSaved;
  final WmnManageLinkCallback? onManageLinkRecords;
  final WmnOpenReportCallback? onOpenReport;
  final WmnFileInteractionService? fileInteractions;

  static Future<Map<String, Object?>?> showQuickCreateDialog(
    BuildContext context, {
    required String doctype,
    required WmnMetaService meta,
    required WmnDocumentService documents,
    required CustomizationService customization,
    WmnManageLinkCallback? onManageLinkRecords,
    WmnFileInteractionService? fileInteractions,
  }) async {
    Map<String, Object?>? savedDocument;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WmnFormView(
        doctype: doctype,
        meta: meta,
        documents: documents,
        customization: customization,
        presentation: WmnFormPresentation.dialog,
        onSaved: (document) => savedDocument = Map<String, Object?>.from(document),
        onManageLinkRecords: onManageLinkRecords,
        fileInteractions: fileInteractions,
      ),
    );
    return changed == true ? savedDocument : null;
  }

  @override
  State<WmnFormView> createState() => _WmnFormViewState();
}

class _WmnFormViewState extends State<WmnFormView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final TextEditingController _reportSourceController = TextEditingController();
  final Map<String, Object?> _values = {};
  WmnDocTypeMeta? _meta;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.documentName == null;

  bool _hasPermission(String action) {
    final runtime = widget.customization.scriptEngine.frappeRuntime;
    final dt = _meta;
    if (dt == null) return false;
    if (runtime == null) {
      return switch (action) {
        'create' => dt.allowCreate,
        'write' => dt.allowEdit,
        'delete' => dt.allowDelete,
        'submit' || 'cancel' => dt.isSubmittable && dt.allowEdit,
        _ => true,
      };
    }
    final allowed = runtime.permissions.hasPermission(
      widget.doctype,
      action,
      docname: widget.documentName,
      document: _creating ? null : Map<String, Object?>.from(_values),
    );
    if (!allowed || _creating || action != 'write') return allowed;
    return runtime.workflow.runtime.canEdit(
      widget.doctype,
      Map<String, Object?>.from(_values),
    );
  }

  int get _docStatus {
    final value = _values['docstatus'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _reportSourceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dt = widget.meta.doctype(widget.doctype);
      if (dt == null) throw StateError('Unknown DocType: ${widget.doctype}');
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final source = widget.documentName == null
          ? (runtime?.documents.newDoc(widget.doctype) ?? <String, Object?>{})
          : (runtime?.documents.getDoc(widget.doctype, widget.documentName!) ??
              widget.documents.get(widget.doctype, widget.documentName!) ??
              <String, Object?>{});
      for (final field in dt.fields) {
        if (field.isLayout) continue;
        _values[field.fieldName] = source.containsKey(field.fieldName) ? source[field.fieldName] : field.defaultValue;
      }
      for (final systemField in const [
        'docstatus',
        'owner',
        'creation',
        'modified',
        'modified_by',
        'idx',
        'parent',
        'parentfield',
        'parenttype',
      ]) {
        if (source.containsKey(systemField)) _values[systemField] = source[systemField];
      }
      if (widget.documentName != null) {
        _values[dt.idField] = source[dt.idField] ?? widget.documentName;
        _values['name'] = source['name'] ?? widget.documentName;
      }
      _meta = dt;
      _syncControllers();
      if (widget.doctype == 'Report') {
        _loadReportSourceEditor();
      }
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _syncControllers() {
    final dt = _meta;
    if (dt == null) return;
    for (final field in dt.fields) {
      if (field.isLayout) continue;
      final control = WmnFieldControlResolver.resolve(
        field,
        doctypeExists: (name) => widget.meta.doctype(name, includeFields: false) != null,
      );
      if (const <WmnFieldControlType>{
        WmnFieldControlType.checkbox,
        WmnFieldControlType.select,
        WmnFieldControlType.link,
        WmnFieldControlType.dynamicLink,
        WmnFieldControlType.childTable,
      }.contains(control.type)) {
        continue;
      }
      final text = _textValue(_values[field.fieldName], field);
      final controller = _controllers.putIfAbsent(field.fieldName, () => TextEditingController());
      if (controller.text != text) {
        controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _formKey.currentState?.save();
      if (widget.doctype == 'Report') {
        _prepareReportSourceForSave();
      }
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final Map<String, Object?> saved;
      if (runtime != null) {
        saved = _creating
            ? runtime.documents.insert(
                widget.doctype,
                Map<String, Object?>.from(_values),
              )
            : runtime.documents.save(
                widget.doctype,
                widget.documentName!,
                Map<String, Object?>.from(_values),
              );
      } else {
        saved = widget.documents.save(
          widget.doctype,
          Map<String, Object?>.from(_values),
          existingName: widget.documentName,
        );
      }
      widget.onSaved?.call(Map<String, Object?>.from(saved));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    final dt = _meta;
    final name = widget.documentName;
    if (dt == null || name == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      _formKey.currentState?.save();
      if (widget.doctype == 'Report') {
        _prepareReportSourceForSave();
      }
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final saved = runtime != null
          ? (() {
              runtime.documents.save(widget.doctype, name, Map<String, Object?>.from(_values));
              return runtime.documents.submit(widget.doctype, name);
            })()
          : (() {
              widget.documents.save(widget.doctype, Map<String, Object?>.from(_values), existingName: name);
              return widget.documents.submit(widget.doctype, name);
            })();
      _values
        ..clear()
        ..addAll(saved);
      _syncControllers();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('submitted'))));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelDocument() async {
    final dt = _meta;
    final name = widget.documentName;
    if (dt == null || name == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.wmnT('cancel_document')),
        content: Text('${context.wmnT('cancel_document_confirm')}\n$name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('close'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('cancel_document'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final saved = runtime != null
          ? runtime.documents.cancel(widget.doctype, name)
          : widget.documents.cancel(widget.doctype, name);
      _values
        ..clear()
        ..addAll(saved);
      _syncControllers();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('cancelled'))));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<WmnFrappeWorkflowAction> _workflowActions() {
    if (_creating) return const <WmnFrappeWorkflowAction>[];
    final runtime = widget.customization.scriptEngine.frappeRuntime;
    if (runtime == null) return const <WmnFrappeWorkflowAction>[];
    return runtime.workflow.availableActions(
      widget.doctype,
      Map<String, Object?>.from(_values),
    );
  }

  bool _hasActiveWorkflow() {
    if (_creating) return false;
    final runtime = widget.customization.scriptEngine.frappeRuntime;
    return runtime?.workflow.workflowFor(widget.doctype) != null;
  }

  Future<void> _applyWorkflowAction(String action) async {
    final name = widget.documentName;
    final runtime = widget.customization.scriptEngine.frappeRuntime;
    if (name == null || runtime == null || _saving) return;
    final commentController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action • ${context.wmnT('workflow_action')}'),
        content: TextField(
          controller: commentController,
          decoration: InputDecoration(labelText: context.wmnT('workflow_comment')),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.wmnT('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.wmnT('workflow_apply')),
          ),
        ],
      ),
    );
    final comment = commentController.text.trim();
    commentController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = runtime.workflow.applyAction(
        widget.doctype,
        name,
        action,
        comment: comment.isEmpty ? null : comment,
      );
      _values
        ..clear()
        ..addAll(saved);
      _syncControllers();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteDocument() async {
    final name = widget.documentName;
    if (name == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.wmnT('delete')),
        content: Text('${context.wmnT('delete_record_confirm')}\n$name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      if (runtime != null) {
        runtime.documents.deleteDoc(widget.doctype, name);
      } else {
        widget.documents.delete(widget.doctype, name);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _printDocument() async {
    final name = widget.documentName;
    if (name == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final printing = WmnPrintingService(
        widget.documents.database,
        documents: widget.documents,
      );
      final request = printing.documentRequest(
        documentType: widget.doctype,
        documentName: name,
        document: Map<String, Object?>.from(_values),
        languageCode: WmnL10nScope.controllerOf(context).languageCode,
      );
      if (!mounted) return;
      await WmnPrintPreviewDialog.show(
        context,
        printing: printing,
        request: request,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showAttachments() async {
    final interactions = widget.fileInteractions;
    final documentName = widget.documentName;
    if (interactions == null || documentName == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final items = interactions.files.attachments(
            widget.doctype,
            documentName,
          );
          return AlertDialog(
            title: Text(context.wmnT('attachments')),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasPermission('write'))
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final mode = await _chooseAttachmentMode(dialogContext);
                          if (mode == null || !dialogContext.mounted) return;
                          try {
                            final stored = await interactions.importFile(
                              contentMode: mode,
                              attachedToDoctype: widget.doctype,
                              attachedToName: documentName,
                            );
                            if (stored != null && dialogContext.mounted) {
                              setDialogState(() {});
                            }
                          } on UnsupportedError catch (error) {
                            if (!dialogContext.mounted) return;
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('$error')),
                            );
                          }
                        },
                        icon: const Icon(Icons.attach_file),
                        label: Text(context.wmnT('add_attachment')),
                      ),
                    ),
                  if (_hasPermission('write')) const SizedBox(height: 12),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(context.wmnT('no_attachments')),
                    )
                  else
                    SizedBox(
                      height: math.min(360.0, items.length * 72.0),
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final item = items[index];
                          return ListTile(
                            leading: Icon(
                              item.isManagedStorage
                                  ? Icons.cloud_done_outlined
                                  : Icons.link_outlined,
                            ),
                            title: Text(item.fileName),
                            subtitle: Text([
                              '${item.fileSize} B',
                              item.isManagedStorage
                                  ? context.wmnT('managed_storage')
                                  : context.wmnT('external_reference'),
                              item.state,
                            ].join(' • ')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: context.wmnT('export_file'),
                                  onPressed: () async {
                                    final result = await interactions.exportStoredFile(item.id);
                                    if (!dialogContext.mounted ||
                                        result.status == WmnFileSaveStatus.canceled) {
                                      return;
                                    }
                                    if (result.status == WmnFileSaveStatus.unsupported) {
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result.message ??
                                                dialogContext.wmnT('file_export_unsupported'),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.download_outlined),
                                ),
                                if (_hasPermission('write'))
                                  IconButton(
                                    tooltip: context.wmnT('detach_attachment'),
                                    onPressed: () {
                                      interactions.files.detach(item.id);
                                      setDialogState(() {});
                                    },
                                    icon: const Icon(Icons.link_off_outlined),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.wmnT('close')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<WmnFileContentMode?> _chooseAttachmentMode(BuildContext context) {
    final interactions = widget.fileInteractions;
    if (interactions == null) return Future<WmnFileContentMode?>.value(null);
    final canReference = interactions.canReferenceExternal;
    final current = interactions.defaultContentMode;
    return showDialog<WmnFileContentMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.wmnT('file_content_mode')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  current == WmnFileContentMode.managedStorage
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(context.wmnT('managed_storage')),
                subtitle: Text(context.wmnT('managed_storage_help')),
                onTap: () => Navigator.of(dialogContext).pop(
                  WmnFileContentMode.managedStorage,
                ),
              ),
              ListTile(
                enabled: canReference,
                leading: Icon(
                  current == WmnFileContentMode.externalReference
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(context.wmnT('external_reference')),
                subtitle: Text(
                  canReference
                      ? context.wmnT('external_reference_help')
                      : context.wmnT('external_reference_unavailable'),
                ),
                onTap: canReference
                    ? () => Navigator.of(dialogContext).pop(
                          WmnFileContentMode.externalReference,
                        )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReport() async {
    if (widget.doctype != 'Report' || _creating) return;
    final callback = widget.onOpenReport;
    if (callback == null) return;
    final reportName = '${_values['report_name'] ?? widget.documentName ?? ''}'.trim();
    if (reportName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.wmnT('report_name_required'))),
        );
      }
      return;
    }
    await callback(reportName);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _present(
        const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final dt = _meta;
    if (dt == null) {
      return _present(
        Scaffold(
          appBar: AppBar(title: Text(widget.doctype)),
          body: Center(child: Text(_error ?? 'Unknown DocType')),
        ),
      );
    }
    final titleField = dt.titleField == null ? null : _values[dt.titleField];
    final title = _creating
        ? '${context.wmnT('new_record')} • ${widget.doctype}'
        : '${titleField ?? widget.documentName}';
    return _present(
      Scaffold(
        appBar: AppBar(
          leading: widget.presentation == WmnFormPresentation.dialog
              ? IconButton(
                  tooltip: context.wmnT('close'),
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                )
              : null,
          title: Text(title),
          actions: [
            if (!_creating && widget.fileInteractions != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _showAttachments,
                  icon: const Icon(Icons.attach_file),
                  label: Text(context.wmnT('attachments')),
                ),
              ),
            if (!_creating && widget.doctype != 'Print Job' && _hasPermission('print'))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _printDocument,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(context.wmnT('print_preview')),
                ),
              ),
            if (widget.doctype == 'Report' && !_creating && widget.onOpenReport != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _showReport,
                  icon: const Icon(Icons.assessment_outlined),
                  label: Text(context.wmnT('show_report')),
                ),
              ),
            if (dt.genericWrite &&
                _docStatus != 2 &&
                ((_creating && _hasPermission('create')) ||
                    (!_creating && _hasPermission('write'))))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(context.wmnT('save')),
                ),
              ),
            if (!_creating && dt.genericWrite)
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action.startsWith('workflow:')) {
                    _applyWorkflowAction(action.substring('workflow:'.length));
                  }
                  if (action == 'submit') _submit();
                  if (action == 'cancel_document') _cancelDocument();
                  if (action == 'delete') _deleteDocument();
                },
                itemBuilder: (context) {
                  final workflowActions = _workflowActions();
                  final hasWorkflow = _hasActiveWorkflow();
                  return <PopupMenuEntry<String>>[
                    for (final workflowAction in workflowActions)
                      PopupMenuItem(
                        value: 'workflow:${workflowAction.action}',
                        child: Text(workflowAction.action),
                      ),
                    if (!hasWorkflow &&
                        dt.isSubmittable &&
                        _docStatus == 0 &&
                        _hasPermission('submit'))
                      PopupMenuItem(
                        value: 'submit',
                        child: Text(context.wmnT('submit_document')),
                      ),
                    if (!hasWorkflow &&
                        dt.isSubmittable &&
                        _docStatus == 1 &&
                        _hasPermission('cancel'))
                      PopupMenuItem(
                        value: 'cancel_document',
                        child: Text(context.wmnT('cancel_document')),
                      ),
                    if (_hasPermission('delete') &&
                        (!dt.isSubmittable || _docStatus != 1))
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.wmnT('delete')),
                      ),
                  ];
                },
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MaterialBanner(
                    content: Text(_error!),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _error = null),
                        child: Text(context.wmnT('close')),
                      ),
                    ],
                  ),
                ),
              _HeaderCard(meta: dt, documentName: widget.documentName),
              if (widget.doctype == 'Print Format') ...[
                const SizedBox(height: 12),
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.code_outlined),
                    title: Text(context.wmnT('print_template_help')),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: const [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SelectableText(
                          WmnPrintTemplateEngine.tokenHelp,
                          style: TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.doctype == 'Report') ...[
                const SizedBox(height: 12),
                _reportCreationGuide(context),
              ],
              const SizedBox(height: 12),
              ..._formWidgets(dt),
              if (widget.doctype == 'Report') ...[
                const SizedBox(height: 12),
                _reportSourceEditor(context),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _present(Widget child) {
    if (widget.presentation == WmnFormPresentation.page) return child;
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = size.width < 700 ? 10.0 : 36.0;
    final verticalInset = size.height < 700 ? 10.0 : 28.0;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(920.0, size.width - (horizontalInset * 2)),
        height: math.min(820.0, size.height - (verticalInset * 2)),
        child: child,
      ),
    );
  }

  Future<String?> _quickCreateTarget(String doctype) async {
    final saved = await WmnFormView.showQuickCreateDialog(
      context,
      doctype: doctype,
      meta: widget.meta,
      documents: widget.documents,
      customization: widget.customization,
      onManageLinkRecords: widget.onManageLinkRecords,
      fileInteractions: widget.fileInteractions,
    );
    if (saved == null) return null;
    final targetMeta = widget.meta.doctype(doctype, includeFields: false);
    if (targetMeta == null) return null;
    final name = '${saved[targetMeta.idField] ?? saved['name'] ?? ''}'.trim();
    return name.isEmpty ? null : name;
  }


  void _loadReportSourceEditor() {
    final type = '${_values['report_type'] ?? ''}'.trim();
    var source = '';
    try {
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final database = runtime?.db.database;
      final storage = database == null ? null : WmnStorageService.forDatabase(database);
      if (type == 'Query Report') {
        final path = '${_values['query_source_path'] ?? ''}'.trim();
        if (path.isNotEmpty && storage != null && storage.exists(path)) {
          source = storage.readText(path);
        } else {
          final raw = '${_values['query_definition_json'] ?? ''}'.trim();
          if (raw.isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              source = '${decoded['sql'] ?? decoded['query'] ?? decoded['raw_sql'] ?? ''}';
            }
          }
        }
      } else if (type == 'Script Report') {
        final sourceType = '${_values['script_source_type'] ?? 'NATIVE_HANDLER'}'.trim();
        if (sourceType == 'STORAGE_FILE') {
          final path = '${_values['script_source_path'] ?? ''}'.trim();
          if (path.isNotEmpty && storage != null && storage.exists(path)) {
            source = storage.readText(path);
          }
        } else {
          final raw = '${_values['metadata_json'] ?? ''}'.trim();
          if (raw.isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is Map) source = '${decoded['source_preview'] ?? ''}';
          }
        }
      }
    } catch (_) {
      // The form remains usable; source validation will surface on save/run.
    }
    _reportSourceController.text = source;
  }

  void _prepareReportSourceForSave() {
    final type = '${_values['report_type'] ?? ''}'.trim();
    if (type == 'Report Builder') {
      final reference = '${_values['ref_doctype'] ?? ''}'.trim();
      if (reference.isEmpty) throw StateError(context.wmnT('report_reference_doctype_required'));
      final filters = (_values['filters'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((row) => <String, Object?>{for (final entry in row.entries) '${entry.key}': entry.value})
          .toList(growable: false);
      final columns = (_values['columns'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((row) => <String, Object?>{for (final entry in row.entries) '${entry.key}': entry.value})
          .toList(growable: false);
      if (columns.isEmpty) throw StateError(context.wmnT('report_columns_required'));

      Map<String, Object?> definition = <String, Object?>{};
      final raw = '${_values['query_definition_json'] ?? ''}'.trim();
      if (raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            definition = <String, Object?>{for (final entry in decoded.entries) '${entry.key}': entry.value};
          }
        } catch (_) {
          // The structured definition is runtime-owned; rebuild it from the visible tables.
          definition = <String, Object?>{};
        }
      }
      definition['source_key'] = 'doctype:$reference';
      definition['columns'] = <Map<String, Object?>>[
        for (final row in columns)
          <String, Object?>{
            'field': row['fieldname'],
            'label': row['label'] ?? row['fieldname'],
            'aggregate': row['aggregate'] ?? 'NONE',
          },
      ];
      definition['filters'] = <Map<String, Object?>>[
        for (final row in filters)
          <String, Object?>{
            'field': row['source_field'] ?? row['fieldname'],
            'operator': row['operator'] ?? 'EQ',
            'value': row['default'],
            'parameter_name': row['fieldname'],
            'label': row['label'] ?? row['fieldname'],
            'field_type': row['fieldtype'] ?? 'Data',
            'options': row['options'],
            'required': row['required'] == true || row['required'] == 1,
            'user_editable': row['user_editable'] != false && row['user_editable'] != 0,
          },
      ];
      definition['sorts'] ??= const <Map<String, Object?>>[];
      definition['limit'] ??= 500;
      _values['query_definition_json'] = jsonEncode(definition);
      _values['query_source_type'] = 'STRUCTURED';
      return;
    }
    if (type == 'Query Report') {
      final sql = _reportSourceController.text.trim();
      if (sql.isEmpty) {
        throw StateError(context.wmnT('query_sql_required'));
      }
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final database = runtime?.db.database;
      if (database == null) throw StateError(context.wmnT('script_storage_unavailable'));
      final storage = WmnStorageService.forDatabase(database);
      String slug(String value) => value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      var path = '${_values['query_source_path'] ?? ''}'.trim();
      if (path.isEmpty) {
        final module = slug('${_values['module'] ?? 'custom'}');
        final report = slug('${_values['report_name'] ?? 'report'}');
        path = 'apps/${module.isEmpty ? 'custom' : module}/reports/${report.isEmpty ? 'report' : report}/query.sql';
      }
      storage.writeText(path, sql);
      _values['query_source_type'] = 'STORAGE_FILE';
      _values['query_source_path'] = path;

      final raw = '${_values['query_definition_json'] ?? ''}'.trim();
      Map<String, Object?> definition = <String, Object?>{};
      if (raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            definition = <String, Object?>{for (final entry in decoded.entries) '${entry.key}': entry.value};
          }
        } catch (_) {
          throw StateError(context.wmnT('invalid_json'));
        }
      }
      definition
        ..remove('sql')
        ..remove('query')
        ..remove('raw_sql');
      _values['query_definition_json'] = jsonEncode(definition);
      final pathController = _controllers['query_source_path'];
      if (pathController != null) pathController.text = path;
      final definitionController = _controllers['query_definition_json'];
      if (definitionController != null) definitionController.text = jsonEncode(definition);
      return;
    }
    if (type == 'Script Report' &&
        '${_values['script_source_type'] ?? 'NATIVE_HANDLER'}'.trim() == 'STORAGE_FILE') {
      final source = _reportSourceController.text.trim();
      if (source.isEmpty) throw StateError(context.wmnT('script_source_required'));
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      final database = runtime?.db.database;
      if (database == null) throw StateError(context.wmnT('script_storage_unavailable'));
      final storage = WmnStorageService.forDatabase(database);
      var path = '${_values['script_source_path'] ?? ''}'.trim();
      if (path.isEmpty) {
        String slug(String value) => value
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
        final module = slug('${_values['module'] ?? 'custom'}');
        final report = slug('${_values['report_name'] ?? 'report'}');
        final language = slug('${_values['script_language'] ?? 'wmn'}');
        path = 'apps/${module.isEmpty ? 'custom' : module}/reports/${report.isEmpty ? 'report' : report}/script.${language.isEmpty ? 'wmn' : language}';
        _values['script_source_path'] = path;
        final controller = _controllers['script_source_path'];
        if (controller != null) controller.text = path;
      }
      storage.writeText(path, source);
    }
  }

  Widget _reportSourceEditor(BuildContext context) {
    final type = '${_values['report_type'] ?? ''}'.trim();
    if (type == 'Query Report') {
      final path = '${_values['query_source_path'] ?? ''}'.trim();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.wmnT('query_sql_code'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(context.wmnT('query_sql_code_help')),
              if (path.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText('${context.wmnT('source_path')}: $path'),
              ],
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('report-query-sql-source'),
                controller: _reportSourceController,
                minLines: 10,
                maxLines: 18,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: context.wmnT('query_sql_code'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? context.wmnT('query_sql_required')
                    : null,
              ),
            ],
          ),
        ),
      );
    }
    if (type == 'Script Report') {
      final sourceType = '${_values['script_source_type'] ?? 'NATIVE_HANDLER'}'.trim();
      final editable = sourceType == 'STORAGE_FILE';
      final key = '${_values['script_key'] ?? ''}'.trim();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.wmnT('script_source_code'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(editable ? context.wmnT('managed_script_source_help') : context.wmnT('native_handler_source_help')),
              if (key.isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText('${context.wmnT('native_handler_key')}: $key'),
              ],
              if (editable && '${_values['script_source_path'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                SelectableText('${context.wmnT('source_path')}: ${_values['script_source_path']}'),
              ],
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('report-script-source'),
                controller: _reportSourceController,
                readOnly: !editable,
                minLines: 10,
                maxLines: 18,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: editable ? context.wmnT('managed_script_source') : context.wmnT('native_handler_source_preview'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _reportCreationGuide(BuildContext context) {
    final type = '${_values['report_type'] ?? ''}'.trim();
    final detailKey = switch (type) {
      'Report Builder' => 'report_builder_creation_help',
      'Query Report' => 'query_report_creation_help',
      'Script Report' => 'script_report_creation_help',
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.wmnT('report_creation_guide'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.wmnT('report_creation_intro')),
            if (detailKey != null) ...[
              const SizedBox(height: 8),
              Text(
                context.wmnT(detailKey),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _formWidgets(WmnDocTypeMeta dt) {
    final widgets = <Widget>[];
    for (final field in dt.fields) {
      if (_hidden(field)) continue;
      if (field.fieldType == 'Section Break' || field.fieldType == 'Tab Break') {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(field.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ));
        widgets.add(const Divider(height: 1));
        continue;
      }
      if (field.fieldType == 'Column Break') continue;
      widgets.add(Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: _field(field)));
    }
    return widgets;
  }

  Widget _field(WmnFieldMeta field) {
    final readOnly = _readOnly(field);
    final required = _required(field);
    final label = '${field.label}${required ? ' *' : ''}';
    final control = WmnFieldControlResolver.resolve(
      field,
      doctypeExists: (name) => widget.meta.doctype(name, includeFields: false) != null,
    );
    if (control.type == WmnFieldControlType.checkbox) {
      final value = _bool(_values[field.fieldName]);
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(label),
        subtitle: field.metadata['description'] == null ? null : Text('${field.metadata['description']}'),
        value: value,
        onChanged: readOnly ? null : (next) => _changed(field, next ? 1 : 0),
      );
    }
    if (control.type == WmnFieldControlType.select) {
      final options = control.options;
      final current = _values[field.fieldName]?.toString();
      return DropdownButtonFormField<String>(
        initialValue: current != null && options.contains(current) ? current : null,
        decoration: InputDecoration(labelText: label, helperText: field.metadata['description']?.toString()),
        items: options.map((entry) => DropdownMenuItem(value: entry, child: Text(entry))).toList(growable: false),
        onChanged: readOnly ? null : (value) => _changed(field, value),
        validator: required ? (value) => value == null || value.trim().isEmpty ? '${field.label} ${context.wmnT('required').toLowerCase()}' : null : null,
      );
    }
    if (control.type == WmnFieldControlType.childTable && (field.options?.trim().isNotEmpty ?? false)) {
      return _ChildTableField(
        field: field,
        label: label,
        targetDoctype: field.options!.trim(),
        value: _values[field.fieldName],
        readOnly: readOnly,
        required: required,
        meta: widget.meta,
        documents: widget.documents,
        runtime: widget.customization.scriptEngine.frappeRuntime,
        onQuickCreateLink: _quickCreateTarget,
        onManageLinkRecords: widget.onManageLinkRecords,
        onChanged: (value) => _changed(field, value),
      );
    }
    if (control.type == WmnFieldControlType.dynamicLink) {
      final targetField = field.options?.trim();
      final target = targetField == null || targetField.isEmpty ? null : _values[targetField]?.toString().trim();
      if (target != null && target.isNotEmpty && widget.meta.doctype(target, includeFields: false) != null) {
        return _LinkField(
          key: ValueKey('${field.fieldName}:$target'),
          field: field,
          label: label,
          targetDoctype: target,
          value: _values[field.fieldName]?.toString(),
          readOnly: readOnly,
          required: required,
          documents: widget.documents,
          runtime: widget.customization.scriptEngine.frappeRuntime,
          querySpec: null,
          onQuickCreate: readOnly ? null : () => _quickCreateTarget(target),
          onManageRecords: widget.onManageLinkRecords == null ? null : () => widget.onManageLinkRecords!(target),
          onChanged: (value) => _changed(field, value),
        );
      }
    }
    if (control.type == WmnFieldControlType.link && control.targetDoctype != null) {
      final target = control.targetDoctype!;
      return _LinkField(
        key: ValueKey('${field.fieldName}:$target'),
        field: field,
        label: label,
        targetDoctype: target,
        value: _values[field.fieldName]?.toString(),
        readOnly: readOnly,
        required: required,
        documents: widget.documents,
        runtime: widget.customization.scriptEngine.frappeRuntime,
        querySpec: null,
        onQuickCreate: readOnly ? null : () => _quickCreateTarget(target),
        onManageRecords: widget.onManageLinkRecords == null ? null : () => widget.onManageLinkRecords!(target),
        onChanged: (value) => _changed(field, value),
      );
    }
    final controller = _controllers.putIfAbsent(field.fieldName, () => TextEditingController(text: _textValue(_values[field.fieldName], field)));
    final multiline = control.type == WmnFieldControlType.multiline;
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? (field.fieldType == 'Code' || field.fieldType == 'JSON' ? 10 : 6) : 1,
      keyboardType: control.type == WmnFieldControlType.number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: field.metadata['description']?.toString(),
        suffixIcon: control.type == WmnFieldControlType.date
            ? IconButton(onPressed: readOnly ? null : () => _pickDate(field, controller), icon: const Icon(Icons.calendar_month_outlined))
            : null,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) return '${field.label} ${context.wmnT('required').toLowerCase()}';
        if (value != null && value.trim().isNotEmpty && field.fieldType == 'Int' && int.tryParse(value.trim()) == null) return context.wmnT('invalid_number');
        if (value != null && value.trim().isNotEmpty && field.isNumeric && num.tryParse(value.trim()) == null) return context.wmnT('invalid_number');
        if (value != null && value.trim().isNotEmpty && field.fieldType == 'JSON') {
          try {
            jsonDecode(value);
          } catch (_) {
            return context.wmnT('invalid_json');
          }
        }
        return null;
      },
      onChanged: (value) => _changed(field, _parse(field, value), updateController: false),
      onSaved: (value) => _values[field.fieldName] = _parse(field, value),
    );
  }

  Future<void> _pickDate(WmnFieldMeta field, TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDate: current ?? DateTime.now(),
    );
    if (picked == null) return;
    final value = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    controller.text = value;
    _changed(field, value, updateController: false);
  }

  void _changed(WmnFieldMeta field, Object? value, {bool updateController = true}) {
    final previous = _values[field.fieldName];
    _values[field.fieldName] = value;
    if ('$previous' != '$value') {
      final dt = _meta;
      if (dt != null) {
        for (final dependent in dt.fields) {
          if (dependent.options?.trim() != field.fieldName) continue;
          final dependentControl = WmnFieldControlResolver.resolve(
            dependent,
            doctypeExists: (name) => widget.meta.doctype(name, includeFields: false) != null,
          );
          if (dependentControl.type == WmnFieldControlType.dynamicLink) {
            _values[dependent.fieldName] = null;
          }
        }
      }
    }
    if (updateController && _controllers.containsKey(field.fieldName)) {
      final text = _textValue(value, field);
      if (_controllers[field.fieldName]!.text != text) _controllers[field.fieldName]!.text = text;
    }
    final effective = WmnFieldControlResolver.resolve(
      field,
      doctypeExists: (name) => widget.meta.doctype(name, includeFields: false) != null,
    );
    if (effective.type == WmnFieldControlType.link || effective.type == WmnFieldControlType.dynamicLink) {
      _applyFetchFrom(field, value);
    }
    if (widget.doctype == 'Report' &&
        (field.fieldName == 'report_type' || field.fieldName == 'script_source_type')) {
      _loadReportSourceEditor();
    }
    if (mounted) setState(() {});
  }

  void _applyFetchFrom(WmnFieldMeta linkField, Object? linkValue) {
    final dt = _meta;
    if (dt == null) return;
    final value = linkValue?.toString().trim() ?? '';
    String? target;
    final effective = WmnFieldControlResolver.resolve(
      linkField,
      doctypeExists: (name) => widget.meta.doctype(name, includeFields: false) != null,
    );
    if (effective.type == WmnFieldControlType.link) {
      target = effective.targetDoctype;
    } else if (effective.type == WmnFieldControlType.dynamicLink) {
      final targetField = linkField.options?.trim();
      if (targetField != null && targetField.isNotEmpty) target = _values[targetField]?.toString().trim();
    }
    for (final dependent in dt.fields) {
      final fetch = dependent.fetchFrom?.trim();
      if (fetch == null || fetch.isEmpty) continue;
      final prefix = '${linkField.fieldName}.';
      if (!fetch.startsWith(prefix)) continue;
      final sourceField = fetch.substring(prefix.length).trim();
      if (sourceField.isEmpty || value.isEmpty || target == null || target.isEmpty) {
        _values[dependent.fieldName] = null;
        continue;
      }
      try {
        final runtime = widget.customization.scriptEngine.frappeRuntime;
        final source = runtime?.documents.getDoc(target, value) ?? widget.documents.get(target, value);
        if (source != null) _values[dependent.fieldName] = source[sourceField];
      } catch (_) {
        // Link validation will surface invalid/missing targets during form validation.
      }
    }
    _syncControllers();
  }

  bool _hidden(WmnFieldMeta field) {
    if (field.hidden) return true;
    final depends = field.dependsOn?.trim();
    if (depends == null || depends.isEmpty) return false;
    return !_condition(depends);
  }

  bool _readOnly(WmnFieldMeta field) {
    if (!_creating && _docStatus == 2) return true;
    if (!_creating && _docStatus == 1 && !field.allowOnSubmit) return true;
    final fallback = field.readOnly || (!_creating && !(_meta?.allowEdit ?? false));
    if (fallback) return true;
    final depends = field.readOnlyDependsOn?.trim();
    return depends != null && depends.isNotEmpty && _condition(depends);
  }

  bool _required(WmnFieldMeta field) {
    if (field.required) return true;
    final depends = field.mandatoryDependsOn?.trim();
    return depends != null && depends.isNotEmpty && _condition(depends);
  }

  bool _condition(String expression) {
    try {
      return widget.customization.scriptEngine.evaluateCondition(
        expression: expression,
        document: Map<String, Object?>.from(_values),
      );
    } catch (_) {
      return false;
    }
  }

  bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on'}.contains('${value ?? ''}'.toLowerCase());
  }

  Object? _parse(WmnFieldMeta field, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (field.fieldType == 'Int') return int.tryParse(text) ?? text;
    if (field.isNumeric) return num.tryParse(text) ?? text;
    if (field.fieldType == 'JSON') return jsonDecode(text);
    return text;
  }

  String _textValue(Object? value, WmnFieldMeta field) {
    if (value == null) return '';
    if (field.fieldType == 'JSON' && value is! String) return const JsonEncoder.withIndent('  ').convert(value);
    return '$value';
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.meta, required this.documentName});
  final WmnDocTypeMeta meta;
  final String? documentName;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(label: Text(meta.module)),
              Chip(label: Text(meta.isSystem ? 'Core DocType' : 'Physical DocType')),
              if (documentName != null) SelectableText(documentName!),
              if (meta.isSubmittable) Chip(label: Text(context.wmnT('submittable'))),
            ],
          ),
        ),
      );
}

class _ChildTableField extends StatefulWidget {
  const _ChildTableField({
    required this.field,
    required this.label,
    required this.targetDoctype,
    required this.value,
    required this.readOnly,
    required this.required,
    required this.meta,
    required this.documents,
    required this.runtime,
    required this.onQuickCreateLink,
    this.onManageLinkRecords,
    required this.onChanged,
  });

  final WmnFieldMeta field;
  final String label;
  final String targetDoctype;
  final Object? value;
  final bool readOnly;
  final bool required;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final WmnFrappeRuntime? runtime;
  final WmnQuickCreateLinkCallback onQuickCreateLink;
  final WmnManageLinkCallback? onManageLinkRecords;
  final ValueChanged<List<Map<String, Object?>>> onChanged;

  @override
  State<_ChildTableField> createState() => _ChildTableFieldState();
}

class _ChildTableFieldState extends State<_ChildTableField> {
  final _formFieldKey = GlobalKey<FormFieldState<List<Map<String, Object?>>>>();
  late List<Map<String, Object?>> _rows = _normalizeRows(widget.value);

  @override
  void didUpdateWidget(covariant _ChildTableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) {
      _rows = _normalizeRows(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final childMeta = widget.meta.doctype(widget.targetDoctype);
    final displayFields = childMeta?.listFields.take(5).toList(growable: false) ?? const <WmnFieldMeta>[];
    return FormField<List<Map<String, Object?>>>(
      key: _formFieldKey,
      initialValue: _rows,
      validator: (_) => widget.required && _rows.isEmpty ? '${widget.field.label} ${context.wmnT('required').toLowerCase()}' : null,
      builder: (state) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(widget.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              Chip(label: Text(widget.targetDoctype)),
              const SizedBox(width: 6),
              if (!widget.readOnly)
                IconButton(
                  tooltip: context.wmnT('add_row'),
                  onPressed: childMeta == null ? null : () => _editRow(childMeta),
                  icon: const Icon(Icons.add_circle_outline),
                ),
            ]),
            if (state.hasError) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(state.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (_rows.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(context.wmnT('no_data')))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('#')),
                    ...displayFields.map((field) => DataColumn(label: Text(field.label))),
                    if (!widget.readOnly) const DataColumn(label: SizedBox.shrink()),
                  ],
                  rows: [
                    for (var index = 0; index < _rows.length; index++)
                      DataRow(cells: [
                        DataCell(Text('${index + 1}')),
                        ...displayFields.map((field) => DataCell(Text('${_rows[index][field.fieldName] ?? ''}'))),
                        if (!widget.readOnly)
                          DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: context.wmnT('move_up'),
                              onPressed: index == 0 ? null : () => _move(index, index - 1),
                              icon: const Icon(Icons.arrow_upward_outlined),
                            ),
                            IconButton(
                              tooltip: context.wmnT('move_down'),
                              onPressed: index >= _rows.length - 1 ? null : () => _move(index, index + 1),
                              icon: const Icon(Icons.arrow_downward_outlined),
                            ),
                            IconButton(onPressed: childMeta == null ? null : () => _editRow(childMeta, index: index), icon: const Icon(Icons.edit_outlined)),
                            IconButton(onPressed: () => _remove(index), icon: const Icon(Icons.delete_outline)),
                          ])),
                      ]),
                  ],
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editRow(WmnDocTypeMeta meta, {int? index}) async {
    final current = index == null ? <String, Object?>{} : Map<String, Object?>.from(_rows[index]);
    try {
      final result = await showDialog<Map<String, Object?>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _ChildRowEditorDialog(
          meta: meta,
          initialValue: current,
          documents: widget.documents,
          runtime: widget.runtime,
          onQuickCreateLink: widget.onQuickCreateLink,
          onManageLinkRecords: widget.onManageLinkRecords,
          title: '${index == null ? context.wmnT('add_row') : context.wmnT('edit')} • ${meta.name}',
        ),
      );
      if (result == null || !mounted) return;
      setState(() {
        if (index == null) {
          _rows.add(result);
        } else {
          _rows[index] = result;
        }
        _reindex();
      });
      _emitChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _move(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= _rows.length || to >= _rows.length) return;
    setState(() {
      final row = _rows.removeAt(from);
      _rows.insert(to, row);
      _reindex();
    });
    _emitChanged();
  }

  void _remove(int index) {
    setState(() {
      _rows.removeAt(index);
      _reindex();
    });
    _emitChanged();
  }

  void _emitChanged() {
    final snapshot = _rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
    _formFieldKey.currentState?.didChange(snapshot);
    widget.onChanged(snapshot);
  }

  void _reindex() {
    for (var i = 0; i < _rows.length; i++) {
      _rows[i]['idx'] = i + 1;
      _rows[i]['doctype'] ??= widget.targetDoctype;
    }
  }

  static List<Map<String, Object?>> _normalizeRows(Object? value) {
    if (value is! List) return <Map<String, Object?>>[];
    return value.whereType<Map>().map((row) => Map<String, Object?>.from(row)).toList(growable: true);
  }
}

class _ChildRowEditorDialog extends StatefulWidget {
  const _ChildRowEditorDialog({
    required this.meta,
    required this.initialValue,
    required this.documents,
    required this.runtime,
    required this.onQuickCreateLink,
    this.onManageLinkRecords,
    required this.title,
  });

  final WmnDocTypeMeta meta;
  final Map<String, Object?> initialValue;
  final WmnDocumentService documents;
  final WmnFrappeRuntime? runtime;
  final WmnQuickCreateLinkCallback onQuickCreateLink;
  final WmnManageLinkCallback? onManageLinkRecords;
  final String title;

  @override
  State<_ChildRowEditorDialog> createState() => _ChildRowEditorDialogState();
}

class _ChildRowEditorDialogState extends State<_ChildRowEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final TextEditingController _reportSourceController = TextEditingController();
  late Map<String, Object?> _values;
  late List<WmnFieldMeta> _fields;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _values = Map<String, Object?>.from(widget.initialValue);
    _fields = widget.meta.visibleFields
        .where((field) => !const {'Table', 'Table MultiSelect', 'Button', 'HTML', 'Image'}.contains(field.fieldType))
        .take(60)
        .toList(growable: false);
    for (final field in _fields) {
      if (!_values.containsKey(field.fieldName) && field.defaultValue != null) {
        _values[field.fieldName] = field.defaultValue;
      }
      final control = WmnFieldControlResolver.resolve(
        field,
        doctypeExists: (name) => widget.documents.meta.doctype(name, includeFields: false) != null,
      );
      if (const <WmnFieldControlType>{
        WmnFieldControlType.checkbox,
        WmnFieldControlType.select,
        WmnFieldControlType.link,
        WmnFieldControlType.dynamicLink,
        WmnFieldControlType.childTable,
      }.contains(control.type)) {
        continue;
      }
      _controllers[field.fieldName] = TextEditingController(text: _textValue(_values[field.fieldName], field));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _reportSourceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in _fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: _fieldEditor(field),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closing ? null : _cancel,
          child: Text(context.wmnT('cancel')),
        ),
        FilledButton(
          onPressed: _closing ? null : _save,
          child: Text(context.wmnT('save')),
        ),
      ],
    );
  }

  Widget _fieldEditor(WmnFieldMeta field) {
    final label = '${field.label}${field.required ? ' *' : ''}';
    final control = WmnFieldControlResolver.resolve(
      field,
      doctypeExists: (name) => widget.documents.meta.doctype(name, includeFields: false) != null,
    );
    if (control.type == WmnFieldControlType.checkbox) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: _bool(_values[field.fieldName]),
        onChanged: field.readOnly ? null : (value) => _setValue(field, value ? 1 : 0),
      );
    }
    if (control.type == WmnFieldControlType.select) {
      final options = control.options;
      final current = _values[field.fieldName]?.toString();
      return DropdownButtonFormField<String>(
        initialValue: current != null && options.contains(current) ? current : null,
        decoration: InputDecoration(labelText: label, helperText: field.metadata['description']?.toString()),
        items: options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(growable: false),
        onChanged: field.readOnly ? null : (value) => _setValue(field, value),
        validator: field.required ? (value) => value == null || value.trim().isEmpty ? context.wmnT('required') : null : null,
      );
    }
    if (control.type == WmnFieldControlType.link && control.targetDoctype != null) {
      final target = control.targetDoctype!;
      return _LinkField(
        key: ValueKey('child:${widget.meta.name}:${field.fieldName}:$target'),
        field: field,
        label: label,
        targetDoctype: target,
        value: _values[field.fieldName]?.toString(),
        readOnly: field.readOnly,
        required: field.required,
        documents: widget.documents,
        runtime: widget.runtime,
        querySpec: null,
        onQuickCreate: field.readOnly ? null : () => widget.onQuickCreateLink(target),
        onManageRecords: widget.onManageLinkRecords == null ? null : () => widget.onManageLinkRecords!(target),
        onChanged: (value) => _setValue(field, value),
      );
    }
    if (control.type == WmnFieldControlType.dynamicLink) {
      final pointerField = field.options?.trim();
      final target = pointerField == null || pointerField.isEmpty ? null : _values[pointerField]?.toString().trim();
      if (target != null && target.isNotEmpty && widget.documents.meta.doctype(target, includeFields: false) != null) {
        return _LinkField(
          key: ValueKey('child:${widget.meta.name}:${field.fieldName}:$target'),
          field: field,
          label: label,
          targetDoctype: target,
          value: _values[field.fieldName]?.toString(),
          readOnly: field.readOnly,
          required: field.required,
          documents: widget.documents,
          runtime: widget.runtime,
          querySpec: null,
          onQuickCreate: field.readOnly ? null : () => widget.onQuickCreateLink(target),
          onManageRecords: widget.onManageLinkRecords == null ? null : () => widget.onManageLinkRecords!(target),
          onChanged: (value) => _setValue(field, value),
        );
      }
    }
    final controller = _controllers.putIfAbsent(
      field.fieldName,
      () => TextEditingController(text: _textValue(_values[field.fieldName], field)),
    );
    final multiline = control.type == WmnFieldControlType.multiline;
    return TextFormField(
      controller: controller,
      readOnly: field.readOnly,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? (field.fieldType == 'Code' || field.fieldType == 'JSON' ? 10 : 6) : 1,
      keyboardType: control.type == WmnFieldControlType.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: field.metadata['description']?.toString(),
        suffixIcon: control.type == WmnFieldControlType.date
            ? IconButton(
                onPressed: field.readOnly ? null : () => _pickDate(field, controller),
                icon: const Icon(Icons.calendar_month_outlined),
              )
            : null,
      ),
      validator: (value) {
        if (field.required && (value == null || value.trim().isEmpty)) return context.wmnT('required');
        if (value != null && value.trim().isNotEmpty && field.fieldType == 'Int' && int.tryParse(value.trim()) == null) {
          return context.wmnT('invalid_number');
        }
        if (value != null && value.trim().isNotEmpty && field.isNumeric && num.tryParse(value.trim()) == null) {
          return context.wmnT('invalid_number');
        }
        if (value != null && value.trim().isNotEmpty && field.fieldType == 'JSON') {
          try {
            jsonDecode(value);
          } catch (_) {
            return context.wmnT('invalid_json');
          }
        }
        return null;
      },
      onChanged: (value) => _setValue(field, _parse(field, value), rebuild: false),
    );
  }

  void _setValue(WmnFieldMeta field, Object? value, {bool rebuild = true}) {
    final oldValue = _values[field.fieldName];
    _values[field.fieldName] = value;
    if ('$oldValue' != '$value') {
      for (final dependent in _fields) {
        if (dependent.options?.trim() != field.fieldName) continue;
        final dependentControl = WmnFieldControlResolver.resolve(
          dependent,
          doctypeExists: (name) => widget.documents.meta.doctype(name, includeFields: false) != null,
        );
        if (dependentControl.type == WmnFieldControlType.dynamicLink) {
          _values[dependent.fieldName] = null;
        }
      }
    }
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _pickDate(WmnFieldMeta field, TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDate: current ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final value = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    controller.text = value;
    _setValue(field, value, rebuild: false);
  }

  Future<void> _cancel() async {
    if (_closing) return;
    setState(() => _closing = true);
    FocusManager.instance.primaryFocus?.unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_closing || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _closing = true);
    for (final field in _fields) {
      final control = WmnFieldControlResolver.resolve(
        field,
        doctypeExists: (name) => widget.documents.meta.doctype(name, includeFields: false) != null,
      );
      if (const <WmnFieldControlType>{
        WmnFieldControlType.checkbox,
        WmnFieldControlType.select,
        WmnFieldControlType.link,
        WmnFieldControlType.dynamicLink,
        WmnFieldControlType.childTable,
      }.contains(control.type)) {
        continue;
      }
      final text = _controllers[field.fieldName]?.text.trim() ?? '';
      _values[field.fieldName] = text.isEmpty ? null : _parse(field, text);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    // RawAutocomplete/Dropdown controls use Overlay entries. Give them one
    // frame to detach before the dialog route is removed; otherwise Flutter
    // can assert in InheritedElement.debugDeactivated (_dependents.isEmpty).
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop(Map<String, Object?>.from(_values));
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on'}.contains('${value ?? ''}'.toLowerCase());
  }

  static Object? _parse(WmnFieldMeta field, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    if (field.fieldType == 'Int') return int.tryParse(text) ?? text;
    if (field.isNumeric) return num.tryParse(text) ?? text;
    if (field.fieldType == 'JSON') return jsonDecode(text);
    return text;
  }

  static String _textValue(Object? value, WmnFieldMeta field) {
    if (value == null) return '';
    if (field.fieldType == 'JSON' && value is! String) return const JsonEncoder.withIndent('  ').convert(value);
    return '$value';
  }
}

class _LinkOption {
  const _LinkOption({required this.value, required this.label, this.description});

  final String value;
  final String label;
  final String? description;
}

class _LinkField extends StatefulWidget {
  const _LinkField({
    super.key,
    required this.field,
    required this.label,
    required this.targetDoctype,
    required this.value,
    required this.readOnly,
    required this.required,
    required this.documents,
    required this.runtime,
    required this.querySpec,
    this.onQuickCreate,
    this.onManageRecords,
    required this.onChanged,
  });

  final WmnFieldMeta field;
  final String label;
  final String targetDoctype;
  final String? value;
  final bool readOnly;
  final bool required;
  final WmnDocumentService documents;
  final WmnFrappeRuntime? runtime;
  final Map<String, Object?>? querySpec;
  final Future<String?> Function()? onQuickCreate;
  final Future<void> Function()? onManageRecords;
  final ValueChanged<String?> onChanged;

  @override
  State<_LinkField> createState() => _LinkFieldState();
}

class _LinkFieldState extends State<_LinkField> {
  TextEditingController? _fieldController;
  FocusNode? _focusNode;

  @override
  void didUpdateWidget(covariant _LinkField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    final controller = _fieldController;
    if (controller == null || (_focusNode?.hasFocus ?? false)) return;
    final text = widget.value ?? '';
    if (controller.text != text) {
      controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  List<List<Object?>> _filters(Object? raw) {
    if (raw == null) return const [];
    if (raw is Map) {
      return raw.entries.map((entry) => <Object?>['${entry.key}', '=', entry.value]).toList(growable: false);
    }
    if (raw is List) {
      return raw.whereType<List>().where((entry) => entry.length >= 3).map((entry) => List<Object?>.from(entry)).toList(growable: false);
    }
    return const [];
  }

  Object? _metadataLinkFilters() {
    final rawField = widget.field.metadata['frappe_field'];
    Object? value;
    if (rawField is Map) value = rawField['link_filters'];
    value ??= widget.field.metadata['link_filters'];
    if (value is String && value.trim().isNotEmpty) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    return value;
  }

  List<_LinkOption> _normalizeCustomResult(Object? result) {
    Object? value = result;
    if (value is Map && value.containsKey('message')) value = value['message'];
    if (value is! List) return const [];
    final options = <_LinkOption>[];
    for (final entry in value) {
      if (entry is Map) {
        final map = Map<String, Object?>.from(entry);
        final optionValue = '${map['value'] ?? map['name'] ?? map['id'] ?? ''}'.trim();
        if (optionValue.isEmpty) continue;
        final description = '${map['description'] ?? map['label'] ?? map['title'] ?? ''}'.trim();
        options.add(_LinkOption(value: optionValue, label: description.isEmpty ? optionValue : description, description: description.isEmpty ? null : description));
      } else if (entry is List && entry.isNotEmpty) {
        final optionValue = '${entry.first ?? ''}'.trim();
        if (optionValue.isEmpty) continue;
        final description = entry.length > 1 ? '${entry[1] ?? ''}'.trim() : '';
        options.add(_LinkOption(value: optionValue, label: description.isEmpty ? optionValue : description, description: description.isEmpty ? null : description));
      } else {
        final optionValue = '$entry'.trim();
        if (optionValue.isNotEmpty) options.add(_LinkOption(value: optionValue, label: optionValue));
      }
    }
    return options;
  }

  Iterable<_LinkOption> _search(TextEditingValue input) {
    if (widget.readOnly) return const <_LinkOption>[];
    final targetMeta = widget.documents.meta.doctype(widget.targetDoctype, includeFields: false);
    if (targetMeta == null) return const <_LinkOption>[];
    final text = input.text.trim();
    final spec = widget.querySpec ?? const <String, Object?>{};
    final filters = <List<Object?>>[
      ..._filters(_metadataLinkFilters()),
      ..._filters(spec['filters']),
    ];
    final customQuery = spec['query']?.toString().trim();

    final runtime = widget.runtime;
    if (customQuery != null && customQuery.isNotEmpty && runtime != null) {
      try {
        final result = runtime.call(customQuery, <String, Object?>{
          'doctype': widget.targetDoctype,
          'txt': text,
          'searchfield': targetMeta.titleField ?? targetMeta.idField,
          'filters': spec['filters'] ?? const <Object?>[],
          'page_len': 25,
        });
        final custom = _normalizeCustomResult(result);
        if (custom.isNotEmpty) return custom;
      } catch (_) {
        // Fall back to the native permission-aware Link search below.
      }
    }

    final titleField = targetMeta.titleField?.trim();
    final fields = <String>{targetMeta.idField, 'name'};
    if (titleField != null && titleField.isNotEmpty) fields.add(titleField);
    final rows = widget.runtime != null
        ? widget.runtime!.db.getList(
            widget.targetDoctype,
            fields: fields.toList(growable: false),
            filters: filters,
            search: text,
            limit: 25,
          )
        : widget.documents.list(
            widget.targetDoctype,
            fields: fields.toList(growable: false),
            filters: filters,
            search: text,
            limit: 25,
          ).rows;
    final seen = <String>{};
    final options = <_LinkOption>[];
    for (final row in rows) {
      final value = '${row['name'] ?? row[targetMeta.idField] ?? row['id'] ?? ''}'.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      final title = titleField == null || titleField.isEmpty ? '' : '${row[titleField] ?? ''}'.trim();
      options.add(_LinkOption(value: value, label: title.isEmpty ? value : title, description: title.isEmpty || title == value ? null : value));
    }
    return options;
  }

  String? _validate(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return widget.required ? '${widget.field.label} ${context.wmnT('required').toLowerCase()}' : null;
    }
    final targetMeta = widget.documents.meta.doctype(widget.targetDoctype, includeFields: false);
    if (targetMeta == null) return '${context.wmnT('unknown_doctype')}: ${widget.targetDoctype}';
    final exists = widget.runtime != null
        ? widget.runtime!.db.exists(widget.targetDoctype, value)
        : widget.documents.exists(widget.targetDoctype, value);
    if (!exists) return '${context.wmnT('invalid_link')}: $value';
    return null;
  }

  bool get _canManageRecords {
    if (widget.onManageRecords == null) return false;
    return widget.runtime?.permissions.hasPermission(
          widget.targetDoctype,
          'read',
        ) ??
        true;
  }

  Future<void> _manageRecords() async {
    final callback = widget.onManageRecords;
    if (callback == null || !_canManageRecords) return;
    await callback();
    if (!mounted) return;
    setState(() {});
  }

  bool get _canQuickCreate {
    if (widget.readOnly || widget.onQuickCreate == null) return false;
    final targetMeta = widget.documents.meta.doctype(
      widget.targetDoctype,
      includeFields: false,
    );
    if (targetMeta == null || targetMeta.isSingle || !targetMeta.genericWrite || !targetMeta.allowCreate) {
      return false;
    }
    return widget.runtime?.permissions.hasPermission(
          widget.targetDoctype,
          'create',
        ) ??
        true;
  }

  Future<void> _quickCreate() async {
    final callback = widget.onQuickCreate;
    if (callback == null || !_canQuickCreate) return;
    final createdName = await callback();
    if (!mounted || createdName == null || createdName.trim().isEmpty) return;
    final value = createdName.trim();
    _fieldController?.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_LinkOption>(
      initialValue: TextEditingValue(text: widget.value ?? ''),
      displayStringForOption: (option) => option.value,
      optionsBuilder: _search,
      onSelected: (option) {
        _fieldController?.text = option.value;
        widget.onChanged(option.value);
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, minWidth: 280, maxWidth: 560),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options.elementAt(index);
                return ListTile(
                  dense: true,
                  title: Text(option.label),
                  subtitle: option.description == null ? null : Text(option.description!),
                  onTap: () => onSelected(option),
                );
              },
            ),
          ),
        ),
      ),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        _fieldController = controller;
        _focusNode = focusNode;
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          readOnly: widget.readOnly,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.targetDoctype,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link, size: 18),
                if (_canManageRecords)
                  IconButton(
                    tooltip: context.wmnT('manage_records'),
                    onPressed: _manageRecords,
                    icon: const Icon(Icons.list_alt_outlined),
                  ),
                if (_canQuickCreate)
                  IconButton(
                    tooltip: context.wmnT('quick_create'),
                    onPressed: _quickCreate,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
              ],
            ),
          ),
          validator: _validate,
          onChanged: widget.onChanged,
          onFieldSubmitted: (_) => onSubmitted(),
        );
      },
    );
  }
}

