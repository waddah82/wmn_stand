import 'package:flutter/material.dart';

import '../../../core/localization/wmn_localization.dart';
import '../../doctype_studio/doctype_code_validator.dart';
import '../../doctype_studio/doctype_studio_models.dart';
import '../../doctype_studio/doctype_studio_service.dart';
import '../../meta/doctype_meta.dart';
import '../../meta/meta_service.dart';

class WmnDocTypeStudioPage extends StatefulWidget {
  const WmnDocTypeStudioPage({
    super.key,
    required this.meta,
    required this.doctypeName,
  });

  final WmnMetaService meta;
  final String doctypeName;

  @override
  State<WmnDocTypeStudioPage> createState() => _WmnDocTypeStudioPageState();
}

class _WmnDocTypeStudioPageState extends State<WmnDocTypeStudioPage> {
  late final WmnDocTypeStudioService _studio = WmnDocTypeStudioService(meta: widget.meta);
  String? _error;

  WmnDocTypeMeta? get _doctype => widget.meta.doctype(widget.doctypeName);

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _error = error.toString());
  }

  void _clearError() {
    if (mounted && _error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final dt = _doctype;
    if (dt == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.wmnT('doctype_studio'))),
        body: Center(child: Text('${context.wmnT('unknown_doctype')}: ${widget.doctypeName}')),
      );
    }
    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${context.wmnT('doctype_studio')} • ${dt.name}'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.wmnT('definition')),
              Tab(text: context.wmnT('fields')),
              Tab(text: context.wmnT('client_code')),
              Tab(text: context.wmnT('server_logic')),
              Tab(text: context.wmnT('styles')),
              Tab(text: context.wmnT('events_hooks')),
              Tab(text: context.wmnT('permissions')),
              Tab(text: context.wmnT('source_parity')),
              Tab(text: context.wmnT('revisions')),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(onPressed: _clearError, child: Text(context.wmnT('close'))),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _definition(dt),
                  _fields(dt),
                  _CodeEditorTab(
                    key: ValueKey('${dt.name}:client'),
                    studio: _studio,
                    doctype: dt,
                    kind: WmnStudioArtifactKind.clientCode,
                    title: context.wmnT('client_code'),
                    language: 'JavaScript / Frappe-compatible client source',
                    help: context.wmnT('client_code_help'),
                    onError: _showError,
                  ),
                  _CodeEditorTab(
                    key: ValueKey('${dt.name}:server'),
                    studio: _studio,
                    doctype: dt,
                    kind: WmnStudioArtifactKind.serverCode,
                    title: context.wmnT('server_logic'),
                    language: 'Python-compatible reference / WMN server hook source',
                    help: context.wmnT('server_logic_help'),
                    onError: _showError,
                  ),
                  _StylesTab(
                    key: ValueKey('${dt.name}:styles'),
                    studio: _studio,
                    doctype: dt,
                    onError: _showError,
                  ),
                  _events(dt),
                  _permissions(dt),
                  _SourceParityTab(
                    key: ValueKey('${dt.name}:source'),
                    studio: _studio,
                    doctype: dt,
                    onError: _showError,
                  ),
                  _RevisionsTab(
                    key: ValueKey('${dt.name}:revisions'),
                    studio: _studio,
                    doctype: dt,
                    onError: _showError,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _definition(WmnDocTypeMeta dt) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(dt.module)),
              Chip(label: Text(dt.isSystem ? context.wmnT('system_doctype') : context.wmnT('custom'))),
              if (dt.isSingle) Chip(label: Text(context.wmnT('single_doctype'))),
              if (dt.isChild) Chip(label: Text(context.wmnT('child_doctype'))),
              if (dt.isSubmittable) Chip(label: Text(context.wmnT('submittable'))),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  _StudioPair(label: context.wmnT('doctype_name'), value: dt.name),
                  _StudioPair(label: context.wmnT('module_label'), value: dt.module),
                  _StudioPair(label: context.wmnT('physical_table'), value: dt.tableName ?? '-'),
                  _StudioPair(label: 'ID Field', value: dt.idField),
                  _StudioPair(label: context.wmnT('title_field'), value: dt.titleField ?? '-'),
                  _StudioPair(label: context.wmnT('autoname'), value: dt.autoname ?? '-'),
                  _StudioPair(label: 'WMN Controller', value: _studio.nativeControllerSummary(dt.name), width: 420),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.wmnT('doctype_studio_safety_help')),
            ),
          ),
        ],
      );

  Widget _fields(WmnDocTypeMeta dt) {
    final fields = [...dt.fields]..sort((a, b) => a.index.compareTo(b.index));
    if (fields.isEmpty) return Center(child: Text(context.wmnT('no_data')));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: fields.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final field = fields[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text('${field.index}')),
            title: Text('${field.label} • ${field.fieldName}'),
            subtitle: Text([
              field.fieldType,
              if (field.options?.trim().isNotEmpty == true) '${context.wmnT('options')}: ${field.options}',
              if (field.required) context.wmnT('required'),
              if (field.readOnly) context.wmnT('read_only'),
              if (field.inListView) context.wmnT('in_list_view'),
            ].join(' • ')),
          ),
        );
      },
    );
  }

  Widget _events(WmnDocTypeMeta dt) {
    final serverEvents = WmnDocTypeCodeValidator.supportedDocumentEvents.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(context.wmnT('events_hooks_help')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: serverEvents.map((entry) => Chip(label: Text(entry))).toList(growable: false),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              '''// Client example\nfrappe.ui.form.on('${dt.name}', {\n  validate(frm) {\n    // frm.set_value('fieldname', value);\n  }\n});\n\n# Server reference example\ndef validate(doc):\n    # use mapped WMN/Frappe-compatible APIs only\n    pass''',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _permissions(WmnDocTypeMeta dt) {
    final rows = widget.meta.database.db.select('''
      SELECT role,permlevel,can_read,can_write,can_create,can_delete,can_submit,can_cancel,can_report,can_import,can_export
      FROM wmn_doctype_permissions
      WHERE doctype=?
      ORDER BY permlevel, role COLLATE NOCASE;
    ''', [dt.name]);
    if (rows.isEmpty) {
      return Center(child: Text(context.wmnT('no_permissions_defined')));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final allowed = <String>[];
        for (final entry in const <(String, String)>[
          ('can_read', 'Read'),
          ('can_write', 'Write'),
          ('can_create', 'Create'),
          ('can_delete', 'Delete'),
          ('can_submit', 'Submit'),
          ('can_cancel', 'Cancel'),
          ('can_report', 'Report'),
          ('can_import', 'Import'),
          ('can_export', 'Export'),
        ]) {
          if ((row[entry.$1] as int? ?? 0) == 1) allowed.add(entry.$2);
        }
        return Card(
          child: ListTile(
            title: Text('${row['role']}'),
            subtitle: Text('Permlevel ${row['permlevel']} • ${allowed.join(', ')}'),
          ),
        );
      },
    );
  }
}

class _CodeEditorTab extends StatefulWidget {
  const _CodeEditorTab({
    super.key,
    required this.studio,
    required this.doctype,
    required this.kind,
    required this.title,
    required this.language,
    required this.help,
    required this.onError,
  });

  final WmnDocTypeStudioService studio;
  final WmnDocTypeMeta doctype;
  final WmnStudioArtifactKind kind;
  final String title;
  final String language;
  final String help;
  final ValueChanged<Object> onError;

  @override
  State<_CodeEditorTab> createState() => _CodeEditorTabState();
}

class _CodeEditorTabState extends State<_CodeEditorTab> {
  late final TextEditingController _controller;
  WmnCodeValidationResult? _validation;
  late WmnStudioArtifact _artifact;

  @override
  void initState() {
    super.initState();
    _artifact = widget.studio.snapshot(widget.doctype.name).artifact(widget.kind);
    _controller = TextEditingController(text: _artifact.source);
    if (_artifact.diagnostics.isNotEmpty) {
      _validation = WmnCodeValidationResult(diagnostics: _artifact.diagnostics);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reloadFromStorage() {
    final stored = widget.studio.snapshot(widget.doctype.name).artifact(widget.kind);
    setState(() {
      _artifact = stored;
      _controller.text = stored.source;
      _validation = stored.diagnostics.isEmpty ? null : WmnCodeValidationResult(diagnostics: stored.diagnostics);
    });
  }

  void _validate() {
    try {
      final result = widget.studio.validate(widget.doctype.name, widget.kind, _controller.text);
      setState(() => _validation = result);
    } catch (error) {
      widget.onError(error);
    }
  }

  void _save({required bool validateFirst}) {
    try {
      final saved = validateFirst
          ? widget.studio.validateAndSave(widget.doctype.name, widget.kind, _controller.text)
          : widget.studio.saveDraft(widget.doctype.name, widget.kind, _controller.text);
      setState(() {
        _artifact = saved;
        _validation = WmnCodeValidationResult(diagnostics: saved.diagnostics);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} • ${saved.status.code} • r${saved.revision}')),
      );
    } catch (error) {
      widget.onError(error);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(widget.language)),
                Chip(label: Text('${_artifact.status.code} • r${_artifact.revision}')),
                IconButton(
                  tooltip: context.wmnT('reload'),
                  onPressed: _reloadFromStorage,
                  icon: const Icon(Icons.refresh),
                ),
                OutlinedButton.icon(
                  onPressed: _validate,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(context.wmnT('validate_code')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _save(validateFirst: false),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(context.wmnT('save_draft')),
                ),
                FilledButton.icon(
                  onPressed: () => _save(validateFirst: true),
                  icon: const Icon(Icons.rule_outlined),
                  label: Text(context.wmnT('validate_and_save')),
                ),
                Tooltip(
                  message: context.wmnT('activation_gated_help'),
                  child: FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Activate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.help, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (_validation != null) _DiagnosticsPanel(result: _validation!),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: widget.title,
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      );
}

class _StylesTab extends StatefulWidget {
  const _StylesTab({
    super.key,
    required this.studio,
    required this.doctype,
    required this.onError,
  });

  final WmnDocTypeStudioService studio;
  final WmnDocTypeMeta doctype;
  final ValueChanged<Object> onError;

  @override
  State<_StylesTab> createState() => _StylesTabState();
}

class _StylesTabState extends State<_StylesTab> {
  WmnStudioArtifactKind _kind = WmnStudioArtifactKind.formStyle;
  late final Map<WmnStudioArtifactKind, TextEditingController> _controllers;
  WmnCodeValidationResult? _validation;

  @override
  void initState() {
    super.initState();
    final snapshot = widget.studio.snapshot(widget.doctype.name);
    _controllers = {
      for (final kind in const [
        WmnStudioArtifactKind.formStyle,
        WmnStudioArtifactKind.listStyle,
        WmnStudioArtifactKind.webStyle,
      ])
        kind: TextEditingController(text: snapshot.artifact(kind).source),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _label(WmnStudioArtifactKind kind) => switch (kind) {
        WmnStudioArtifactKind.formStyle => context.wmnT('form_style'),
        WmnStudioArtifactKind.listStyle => context.wmnT('list_style'),
        WmnStudioArtifactKind.webStyle => context.wmnT('web_style'),
        _ => kind.code,
      };

  void _validate() {
    try {
      setState(() => _validation = widget.studio.validate(
            widget.doctype.name,
            _kind,
            _controllers[_kind]!.text,
          ));
    } catch (error) {
      widget.onError(error);
    }
  }

  void _save() {
    try {
      final saved = widget.studio.validateAndSave(
        widget.doctype.name,
        _kind,
        _controllers[_kind]!.text,
      );
      setState(() => _validation = WmnCodeValidationResult(diagnostics: saved.diagnostics));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_label(_kind)} • ${saved.status.code} • r${saved.revision}')),
      );
    } catch (error) {
      widget.onError(error);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SegmentedButton<WmnStudioArtifactKind>(
                  segments: const [
                    ButtonSegment(value: WmnStudioArtifactKind.formStyle, label: Text('Form Style')),
                    ButtonSegment(value: WmnStudioArtifactKind.listStyle, label: Text('List Style')),
                    ButtonSegment(value: WmnStudioArtifactKind.webStyle, label: Text('Web CSS')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (value) => setState(() {
                    _kind = value.first;
                    _validation = null;
                  }),
                ),
                OutlinedButton.icon(
                  onPressed: _validate,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(context.wmnT('validate_style')),
                ),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.rule_outlined),
                  label: Text(context.wmnT('validate_and_save')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _kind == WmnStudioArtifactKind.webStyle
                  ? context.wmnT('web_style_help')
                  : context.wmnT('native_style_help'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_validation != null) _DiagnosticsPanel(result: _validation!),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controllers[_kind],
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _label(_kind),
                  alignLabelWithHint: true,
                  hintText: _kind == WmnStudioArtifactKind.webStyle
                      ? '.my-class { font-weight: 700; }'
                      : 'field(customer_name) {\n  font-weight: bold;\n  text-color: primary;\n}',
                ),
              ),
            ),
          ],
        ),
      );
}

class _SourceParityTab extends StatefulWidget {
  const _SourceParityTab({
    super.key,
    required this.studio,
    required this.doctype,
    required this.onError,
  });

  final WmnDocTypeStudioService studio;
  final WmnDocTypeMeta doctype;
  final ValueChanged<Object> onError;

  @override
  State<_SourceParityTab> createState() => _SourceParityTabState();
}

class _SourceParityTabState extends State<_SourceParityTab> {
  List<WmnReferenceSource> _sources = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _sources = widget.studio.importedReferenceSources(widget.doctype.name);
  }

  Future<void> _refreshReferences() async {
    setState(() => _loading = true);
    try {
      final result = await widget.studio.loadReferenceSources(widget.doctype.name);
      if (mounted) setState(() => _sources = result);
    } catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(label: Text(widget.studio.nativeControllerSummary(widget.doctype.name))),
            OutlinedButton.icon(
              onPressed: _refreshReferences,
              icon: const Icon(Icons.refresh_outlined),
              label: Text(context.wmnT('refresh_reference_source')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(context.wmnT('source_parity_help')),
        const SizedBox(height: 12),
        if (_sources.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.wmnT('no_reference_source_loaded')),
            ),
          )
        else
          ..._sources.map((source) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text('${source.framework} • ${source.language}'),
                  subtitle: Text(source.path, maxLines: 2, overflow: TextOverflow.ellipsis),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            try {
                              final kind = source.language == 'JAVASCRIPT'
                                  ? WmnStudioArtifactKind.clientCode
                                  : WmnStudioArtifactKind.serverCode;
                              final saved = widget.studio.saveDraft(
                                widget.doctype.name,
                                kind,
                                source.source,
                                origin: 'REFERENCE:${source.framework}',
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('${context.wmnT('reference_copied_to_draft')} • r${saved.revision}')),
                              );
                            } catch (error) {
                              widget.onError(error);
                            }
                          },
                          icon: const Icon(Icons.content_copy_outlined),
                          label: Text(source.language == 'JAVASCRIPT'
                              ? context.wmnT('copy_to_client_draft')
                              : context.wmnT('copy_to_server_draft')),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 420,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(source.source, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

class _RevisionsTab extends StatefulWidget {
  const _RevisionsTab({
    super.key,
    required this.studio,
    required this.doctype,
    required this.onError,
  });

  final WmnDocTypeStudioService studio;
  final WmnDocTypeMeta doctype;
  final ValueChanged<Object> onError;

  @override
  State<_RevisionsTab> createState() => _RevisionsTabState();
}

class _RevisionsTabState extends State<_RevisionsTab> {
  final Map<String, String> _loadedSources = <String, String>{};

  String _revisionKey(WmnStudioRevision revision) =>
      '${revision.kind.code}:${revision.revision}:${revision.sourceHash}';

  void _loadRevision(WmnStudioRevision revision) {
    final key = _revisionKey(revision);
    if (_loadedSources.containsKey(key)) return;
    final source = widget.studio.revisionSource(revision);
    if (!mounted) return;
    setState(() => _loadedSources[key] = source);
  }

  @override
  Widget build(BuildContext context) {
    final revisions = widget.studio.snapshot(widget.doctype.name).revisions;
    if (revisions.isEmpty) return Center(child: Text(context.wmnT('no_revisions')));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: revisions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final revision = revisions[index];
        final revisionKey = _revisionKey(revision);
        final loadedSource = _loadedSources[revisionKey];
        return Card(
          child: ExpansionTile(
            onExpansionChanged: (expanded) {
              if (expanded) _loadRevision(revision);
            },
            title: Text('${revision.kind.code} • r${revision.revision} • ${revision.status.code}'),
            subtitle: Text('${revision.createdAt} • ${revision.sourceHash.substring(0, revision.sourceHash.length.clamp(0, 12).toInt())}'),
            trailing: IconButton(
              tooltip: context.wmnT('restore_revision'),
              onPressed: () {
                try {
                  widget.studio.restoreRevision(widget.doctype.name, revision);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('revision_restored_as_draft'))));
                } catch (error) {
                  widget.onError(error);
                }
              },
              icon: const Icon(Icons.restore),
            ),
            children: [
              SizedBox(
                height: 260,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(loadedSource ?? '…', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.result});

  final WmnCodeValidationResult result;

  @override
  Widget build(BuildContext context) {
    final title = result.isValid
        ? '✓ ${context.wmnT('validation_passed')}'
        : '✕ ${context.wmnT('validation_failed')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title • ${result.errors} errors • ${result.warnings} warnings', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (result.diagnostics.isNotEmpty) const SizedBox(height: 6),
            ...result.diagnostics.take(8).map((entry) => Text(
                  '${entry.severity}${entry.line == null ? '' : ' L${entry.line}'}: ${entry.message}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
          ],
        ),
      ),
    );
  }
}

class _StudioPair extends StatelessWidget {
  const _StudioPair({required this.label, required this.value, this.width = 240});

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 3),
            SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
