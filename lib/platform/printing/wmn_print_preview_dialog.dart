import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'adapters/wmn_pdf_preview_widget.dart';
import 'wmn_print_models.dart';
import 'wmn_printing_service.dart';

/// Frappe-like Print Preview surface.
///
/// Preview is intentionally non-destructive: switching Print Format, Letter
/// Head, or language re-renders the same request without queuing a Print Job.
/// The same canonical HTML is then used by the PDF backend.
class WmnPrintPreviewDialog extends StatefulWidget {
  const WmnPrintPreviewDialog({
    super.key,
    required this.printing,
    required this.request,
  });

  final WmnPrintingService printing;
  final WmnPrintRequest request;

  static Future<void> show(
    BuildContext context, {
    required WmnPrintingService printing,
    required WmnPrintRequest request,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WmnPrintPreviewDialog(
          printing: printing,
          request: request,
        ),
      );

  @override
  State<WmnPrintPreviewDialog> createState() =>
      _WmnPrintPreviewDialogState();
}

class _WmnPrintPreviewDialogState extends State<WmnPrintPreviewDialog> {
  static const String _automaticLetterHead = '__automatic__';
  static const String _noLetterHead = '__none__';

  List<WmnPrintFormat> _formats = const <WmnPrintFormat>[];
  List<WmnLetterHead> _letterHeads = const <WmnLetterHead>[];
  String? _formatId;
  String _letterHeadSelection = _automaticLetterHead;
  String _languageCode = 'en';
  WmnPrintPreviewResult? _preview;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final formats = widget.printing.formatsForRequest(widget.request);
      final letterHeads = widget.printing.letterHeads();
      final resolved = widget.printing.resolveFormat(
        sourceType: widget.request.sourceType,
        documentType: widget.request.documentType,
        reportName: widget.request.reportName,
        explicitFormatId: widget.request.explicitFormatId,
      );
      final language = _normalizeLanguage(
        widget.request.languageCode ??
            resolved.defaultPrintLanguage ??
            widget.printing.settings().defaultPrintLanguage ??
            'en',
      );
      if (!mounted) return;
      setState(() {
        _formats = formats;
        _letterHeads = letterHeads;
        _formatId = resolved.id;
        _letterHeadSelection = widget.request.suppressLetterHead
            ? _noLetterHead
            : (widget.request.explicitLetterHeadId?.trim().isNotEmpty == true
                ? widget.request.explicitLetterHeadId!.trim()
                : _automaticLetterHead);
        _languageCode = language;
      });
      await _refreshPreview();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  WmnPrintRequest _currentRequest() {
    final selectedHead = _letterHeadSelection;
    return widget.request.copyWith(
      explicitFormatId: _formatId,
      rendererId: 'pdf',
      explicitLetterHeadId:
          selectedHead == _automaticLetterHead || selectedHead == _noLetterHead
              ? null
              : selectedHead,
      clearExplicitLetterHeadId:
          selectedHead == _automaticLetterHead || selectedHead == _noLetterHead,
      suppressLetterHead: selectedHead == _noLetterHead,
      languageCode: _languageCode,
    );
  }

  Future<void> _refreshPreview() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final preview = await widget.printing.preview(_currentRequest());
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    final width = compact ? size.width : math.min(size.width - 36, 1180.0);
    final height = compact ? size.height : math.min(size.height - 36, 860.0);
    return Dialog(
      insetPadding: compact ? EdgeInsets.zero : const EdgeInsets.all(18),
      shape: compact
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: SafeArea(
          child: Column(
            children: [
              _header(context, compact: compact),
              const Divider(height: 1),
              _selectors(context, compact: compact),
              const Divider(height: 1),
              Expanded(child: _previewBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, {required bool compact}) {
    final preview = _preview;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        compact ? 12 : 16,
        compact ? 8 : 10,
        compact ? 6 : 8,
        compact ? 8 : 10,
      ),
      child: Row(
        children: [
          const Icon(Icons.print_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.wmnT('print_preview'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  preview == null
                      ? widget.request.sourceName
                      : '${preview.format.name} • ${preview.languageCode.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.wmnT('refresh_preview'),
            onPressed: _loading ? null : _refreshPreview,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _selectors(BuildContext context, {required bool compact}) {
    final controls = <Widget>[
      _selectorBox(
        context,
        compact: compact,
        child: DropdownButtonFormField<String>(
          key: ValueKey<String>('print-format:${_formatId ?? ''}'),
          initialValue: _formats.any((item) => item.id == _formatId)
              ? _formatId
              : null,
          decoration: InputDecoration(
            labelText: context.wmnT('print_format'),
            prefixIcon: const Icon(Icons.description_outlined),
          ),
          items: _formats
              .map(
                (format) => DropdownMenuItem<String>(
                  value: format.id,
                  child: Text(
                    format.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _loading
              ? null
              : (value) {
                  if (value == null || value == _formatId) return;
                  setState(() => _formatId = value);
                  _refreshPreview();
                },
        ),
      ),
      _selectorBox(
        context,
        compact: compact,
        child: DropdownButtonFormField<String>(
          key: ValueKey<String>('letter-head:$_letterHeadSelection'),
          initialValue: _letterHeadValue(),
          decoration: InputDecoration(
            labelText: context.wmnT('letter_head'),
            prefixIcon: const Icon(Icons.branding_watermark_outlined),
          ),
          items: <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: _automaticLetterHead,
              child: Text(context.wmnT('default_letter_head')),
            ),
            DropdownMenuItem<String>(
              value: _noLetterHead,
              child: Text(context.wmnT('no_letter_head')),
            ),
            ..._letterHeads.map(
              (head) => DropdownMenuItem<String>(
                value: head.id,
                child: Text(
                  head.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: _loading
              ? null
              : (value) {
                  if (value == null || value == _letterHeadSelection) return;
                  setState(() => _letterHeadSelection = value);
                  _refreshPreview();
                },
        ),
      ),
      _selectorBox(
        context,
        compact: compact,
        child: DropdownButtonFormField<String>(
          key: ValueKey<String>('print-language:$_languageCode'),
          initialValue: _languageOptions().contains(_languageCode)
              ? _languageCode
              : null,
          decoration: InputDecoration(
            labelText: context.wmnT('print_language'),
            prefixIcon: const Icon(Icons.translate_outlined),
          ),
          items: _languageOptions()
              .map(
                (language) => DropdownMenuItem<String>(
                  value: language,
                  child: Text(_languageLabel(context, language)),
                ),
              )
              .toList(growable: false),
          onChanged: _loading
              ? null
              : (value) {
                  if (value == null || value == _languageCode) return;
                  setState(() => _languageCode = value);
                  _refreshPreview();
                },
        ),
      ),
    ];

    return Padding(
      padding: EdgeInsets.all(compact ? 10 : 12),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < controls.length; index++) ...[
                  controls[index],
                  if (index != controls.length - 1) const SizedBox(height: 8),
                ],
              ],
            )
          : Row(
              children: [
                for (var index = 0; index < controls.length; index++) ...[
                  Expanded(child: controls[index]),
                  if (index != controls.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
    );
  }

  Widget _selectorBox(
    BuildContext context, {
    required bool compact,
    required Widget child,
  }) =>
      SizedBox(
        width: compact ? double.infinity : null,
        child: child,
      );

  String _letterHeadValue() {
    if (_letterHeadSelection == _automaticLetterHead ||
        _letterHeadSelection == _noLetterHead) {
      return _letterHeadSelection;
    }
    return _letterHeads.any((head) => head.id == _letterHeadSelection)
        ? _letterHeadSelection
        : _automaticLetterHead;
  }

  List<String> _languageOptions() {
    final result = <String>{'ar', 'en', _normalizeLanguage(_languageCode)};
    final format = _formats.where((item) => item.id == _formatId).firstOrNull;
    if (format?.defaultPrintLanguage?.trim().isNotEmpty == true) {
      result.add(_normalizeLanguage(format!.defaultPrintLanguage!));
    }
    return result.toList(growable: false)..sort();
  }

  String _languageLabel(BuildContext context, String language) {
    final primary = language.split(RegExp(r'[-_]')).first.toLowerCase();
    return switch (primary) {
      'ar' => context.wmnT('arabic'),
      'en' => context.wmnT('english'),
      _ => language,
    };
  }

  Widget _previewBody(BuildContext context) {
    if (_loading && _preview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      );
    }
    final rendered = _preview?.rendered;
    if (rendered == null) return const SizedBox.shrink();
    if (rendered.mimeType == 'application/pdf') {
      return Stack(
        children: [
          Positioned.fill(
            child: WmnPdfPreviewWidget(
              bytes: rendered.bytes,
              fileName: '${_preview!.format.code}.pdf',
            ),
          ),
          if (_loading)
            const PositionedDirectional(
              top: 10,
              end: 10,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
        ],
      );
    }
    final text = rendered.mimeType.startsWith('text/html')
        ? utf8.decode(rendered.bytes, allowMalformed: true)
        : rendered.debugText;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: SelectableText(text),
      ),
    );
  }

  String _normalizeLanguage(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('_', '-');
    return normalized.isEmpty ? 'en' : normalized;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
