import 'package:flutter/material.dart';

import '../../app/wmn_runtime.dart';
import '../../core/localization/wmn_localization.dart';
import '../configuration/wmn_configuration_service.dart';
import '../files/wmn_file_adapter.dart';
import '../files/wmn_file_service.dart';
import '../diagnostics/wmn_diagnostics_service.dart';

class WmnSystemServicesPage extends StatefulWidget {
  const WmnSystemServicesPage({super.key, required this.runtime});

  final WmnRuntime runtime;

  @override
  State<WmnSystemServicesPage> createState() => _WmnSystemServicesPageState();
}

class _WmnSystemServicesPageState extends State<WmnSystemServicesPage> {
  WmnRuntime get r => widget.runtime;

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final snapshot = r.diagnostics.snapshot();
    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.wmnT('system_services'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(context.wmnT('system_services_help'), style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: context.wmnT('refresh'),
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: context.wmnT('overview')),
                  Tab(text: context.wmnT('files')),
                  Tab(text: context.wmnT('jobs')),
                  Tab(text: context.wmnT('notifications')),
                  Tab(text: context.wmnT('logs')),
                  Tab(text: context.wmnT('audit')),
                  Tab(text: context.wmnT('configuration')),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                _overview(context, snapshot),
                _files(context),
                _jobs(context),
                _notifications(context),
                _logs(context),
                _audit(context),
                _configuration(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview(BuildContext context, WmnDiagnosticsSnapshot snapshot) {
    final pendingPrintJobs = r.printing.jobs(status: 'PENDING').length;
    final configurationCount = r.configuration.entries().length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric(context, context.wmnT('files'), '${snapshot.counts['files'] ?? 0}', Icons.folder_outlined),
            _metric(context, context.wmnT('queued_jobs'), '${snapshot.counts['queued_jobs'] ?? 0}', Icons.schedule_outlined),
            _metric(context, context.wmnT('failed_jobs'), '${snapshot.counts['failed_jobs'] ?? 0}', Icons.error_outline),
            _metric(context, context.wmnT('unread_notifications'), '${snapshot.counts['unread_notifications'] ?? 0}', Icons.notifications_none),
            _metric(context, context.wmnT('error_logs'), '${snapshot.counts['error_logs'] ?? 0}', Icons.monitor_heart_outlined),
            _metric(context, context.wmnT('pending_print_jobs'), '$pendingPrintJobs', Icons.print_outlined),
            _metric(context, context.wmnT('configuration_entries'), '$configurationCount', Icons.tune_outlined),
            _metric(context, context.wmnT('audit_entries'), '${r.audit.count}', Icons.fact_check_outlined),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.wmnT('runtime_health'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _kv(context, context.wmnT('kernel_state'), '${snapshot.kernel['state']}'),
                _kv(context, context.wmnT('schema_version'), '${snapshot.database['schema_version']}'),
                _kv(context, context.wmnT('storage_kind'), '${snapshot.database['storage_kind']}'),
                _kv(context, context.wmnT('registered_services'), '${snapshot.kernel['registered_services']}'),
                _kv(context, context.wmnT('available_capabilities'), '${snapshot.kernel['available_capabilities']}'),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () {
                    r.diagnostics.recordSnapshot();
                    _refresh();
                  },
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: Text(context.wmnT('capture_diagnostics')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _files(BuildContext context) {
    final items = r.files.files();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: () async {
              final mode = await _chooseFileContentMode(context);
              if (mode == null || !context.mounted) return;
              try {
                final stored = await r.fileInteractions.importFile(
                  contentMode: mode,
                );
                if (stored == null || !context.mounted) return;
                _refresh();
              } on UnsupportedError catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$error')),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: Text(context.wmnT('add_file')),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _empty(context, context.wmnT('no_files'))
        else
          ...items.map((item) => Card(
            child: ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(item.fileName),
              subtitle: Text([
                if (item.attachedToDoctype != null) '${item.attachedToDoctype} / ${item.attachedToName}',
                '${item.fileSize} B',
                item.isManagedStorage
                    ? context.wmnT('managed_storage')
                    : context.wmnT('external_reference'),
              ].join(' • ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.state),
                  IconButton(
                    tooltip: context.wmnT('export_file'),
                    onPressed: () async {
                      final result = await r.fileInteractions.exportStoredFile(item.id);
                      if (!context.mounted || result.status == WmnFileSaveStatus.canceled) return;
                      if (result.status == WmnFileSaveStatus.unsupported) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result.message ?? context.wmnT('file_export_unsupported'))),
                        );
                      }
                    },
                    icon: const Icon(Icons.download_outlined),
                  ),
                ],
              ),
            ),
          )),
      ],
    );
  }

  Future<WmnFileContentMode?> _chooseFileContentMode(
    BuildContext context,
  ) async {
    final canReference = r.fileInteractions.canReferenceExternal;
    final current = r.fileInteractions.defaultContentMode;
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

  Widget _jobs(BuildContext context) {
    final jobs = r.jobs.jobs(limit: 200);
    final schedules = r.jobs.schedules();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text(context.wmnT('scheduler_jobs'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            OutlinedButton.icon(
              onPressed: () {
                r.jobs.enqueueDueSchedules();
                _refresh();
              },
              icon: const Icon(Icons.playlist_add_check),
              label: Text(context.wmnT('enqueue_due_schedules')),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () {
                r.jobs.runNext();
                _refresh();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(context.wmnT('run_next_job')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('${context.wmnT('schedules')}: ${schedules.length}'),
        const SizedBox(height: 8),
        if (jobs.isEmpty)
          _empty(context, context.wmnT('no_jobs'))
        else
          ...jobs.map((row) => Card(
            child: ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: Text('${row['method_name']}'),
              subtitle: Text('${row['queue_name']} • ${row['created_at']}'),
              trailing: Text('${row['status']}'),
            ),
          )),
      ],
    );
  }

  Widget _notifications(BuildContext context) {
    final items = r.notifications.notifications(limit: 200);
    return _tableList(
      context,
      emptyText: context.wmnT('no_notifications'),
      children: items.map((item) => Card(
        child: ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: Text(item.title),
          subtitle: Text('${item.body}\n${item.channel.name} • ${item.createdAt.toLocal()}'),
          isThreeLine: true,
          trailing: item.readAt == null
              ? IconButton(
                  tooltip: context.wmnT('mark_read'),
                  onPressed: () {
                    r.notifications.markRead(item.id);
                    _refresh();
                  },
                  icon: const Icon(Icons.mark_email_read_outlined),
                )
              : const Icon(Icons.done),
        ),
      )).toList(growable: false),
    );
  }

  Widget _logs(BuildContext context) {
    final items = r.logs.entries(limit: 200);
    return _tableList(
      context,
      emptyText: context.wmnT('no_logs'),
      children: items.map((item) => Card(
        child: ListTile(
          leading: Icon(
            item.level.name == 'critical' || item.level.name == 'error'
                ? Icons.error_outline
                : item.level.name == 'warning'
                    ? Icons.warning_amber_outlined
                    : Icons.info_outline,
          ),
          title: Text(item.message),
          subtitle: Text('${item.source}${item.eventName == null ? '' : ' • ${item.eventName}'}\n${item.createdAt.toLocal()}'),
          isThreeLine: true,
          trailing: Text(item.level.name.toUpperCase()),
        ),
      )).toList(growable: false),
    );
  }

  Widget _audit(BuildContext context) {
    final items = r.audit.entries(limit: 200);
    return _tableList(
      context,
      emptyText: context.wmnT('no_audit_entries'),
      children: items.map((item) => Card(
        child: ListTile(
          leading: const Icon(Icons.history_outlined),
          title: Text('${item.entityType} • ${item.action}'),
          subtitle: Text('${item.entityId}\n${item.createdAt.toLocal()}'),
          isThreeLine: true,
        ),
      )).toList(growable: false),
    );
  }

  Widget _configuration(BuildContext context) {
    final items = r.configuration.entries();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: () => _showConfigurationDialog(context),
            icon: const Icon(Icons.add),
            label: Text(context.wmnT('add_setting')),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _empty(context, context.wmnT('no_configuration_entries'))
        else
          ...items.map((item) => Card(
            child: ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: Text(item.key),
              subtitle: Text('${item.scope.name}${item.scopeKey.isEmpty ? '' : ' / ${item.scopeKey}'}'),
              trailing: item.isSecret ? const Icon(Icons.lock_outline) : Text('${item.value}'),
            ),
          )),
      ],
    );
  }

  Future<void> _showConfigurationDialog(BuildContext context) async {
    var scope = WmnConfigurationScope.system;
    final scopeKey = TextEditingController();
    final key = TextEditingController();
    final value = TextEditingController();
    var secret = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(context.wmnT('add_setting')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<WmnConfigurationScope>(
                    initialValue: scope,
                    decoration: InputDecoration(labelText: context.wmnT('scope')),
                    items: WmnConfigurationScope.values
                        .map((entry) => DropdownMenuItem(value: entry, child: Text(entry.name)))
                        .toList(growable: false),
                    onChanged: (entry) {
                      if (entry != null) setDialogState(() => scope = entry);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: scopeKey, decoration: InputDecoration(labelText: context.wmnT('scope_key'))),
                  const SizedBox(height: 10),
                  TextField(controller: key, decoration: InputDecoration(labelText: context.wmnT('setting_key'))),
                  const SizedBox(height: 10),
                  TextField(controller: value, decoration: InputDecoration(labelText: context.wmnT('setting_value'))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: secret,
                    title: Text(context.wmnT('secret')),
                    onChanged: (entry) => setDialogState(() => secret = entry),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.wmnT('cancel'))),
            FilledButton(
              onPressed: () {
                if (key.text.trim().isEmpty) return;
                r.configuration.setValue(
                  scope,
                  key.text.trim(),
                  value.text,
                  scopeKey: scopeKey.text.trim(),
                  isSecret: secret,
                );
                Navigator.pop(dialogContext, true);
              },
              child: Text(context.wmnT('save')),
            ),
          ],
        ),
      ),
    );
    scopeKey.dispose();
    key.dispose();
    value.dispose();
    if (saved == true && mounted) _refresh();
  }

  Widget _metric(BuildContext context, String label, String value, IconData icon) => SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _kv(BuildContext context, String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 190, child: Text(key, style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(value)),
          ],
        ),
      );

  Widget _tableList(BuildContext context, {required String emptyText, required List<Widget> children}) =>
      ListView(padding: const EdgeInsets.all(20), children: children.isEmpty ? <Widget>[_empty(context, emptyText)] : children);

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
      );
}
