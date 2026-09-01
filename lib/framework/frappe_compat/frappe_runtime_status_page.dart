import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'frappe_runtime.dart';

class WmnFrappeRuntimeStatusPage extends StatelessWidget {
  const WmnFrappeRuntimeStatusPage({super.key, required this.runtime});

  final WmnFrappeRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final t = context.wmnT;
    final coverage = runtime.apiCoverage();
    final roles = runtime.getRoles();
    final statusCounts = <String, int>{};
    var totalHits = 0;
    var coveredHits = 0;
    for (final row in coverage) {
      final status = '${row['status']}';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      final hits = row['source_hits'] as int? ?? 0;
      totalHits += hits;
      if (status == 'NATIVE' || status == 'COMPAT') coveredHits += hits;
    }
    final weighted = totalHits == 0 ? 0 : (coveredHits * 100 / totalHits).round();
    final jobRows = runtime.jobs.jobs(limit: 20);
    final queued = jobRows.where((row) => row['status'] == 'QUEUED').length;
    final failed = jobRows.where((row) => row['status'] == 'FAILED').length;

    return Scaffold(
      appBar: AppBar(title: Text(t('frappe_runtime'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('frappe_runtime_native_help'), style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('${t('current_user')}: ${runtime.session.user}')),
                      Chip(label: Text('${t('roles')}: ${roles.length}')),
                      Chip(label: Text('${t('api_weighted_coverage')}: $weighted%')),
                      Chip(label: Text('${t('queued_jobs')}: $queued')),
                      Chip(label: Text('${t('failed_jobs')}: $failed')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('runtime_engines'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      Chip(label: Text('Document')),
                      Chip(label: Text('DB API')),
                      Chip(label: Text('Meta')),
                      Chip(label: Text('Permissions')),
                      Chip(label: Text('Session / Boot')),
                      Chip(label: Text('Naming')),
                      Chip(label: Text('Workflow')),
                      Chip(label: Text('Hooks')),
                      Chip(label: Text('RPC')),
                      Chip(label: Text('Cache')),
                      Chip(label: Text('Jobs')),
                      Chip(label: Text('Realtime')),
                      Chip(label: Text('Query')),
                      Chip(label: Text('Comments / Share / Assignments / Files')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('frappe_api_compatibility'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: statusCounts.entries.map((entry) => Chip(label: Text('${entry.key}: ${entry.value}'))).toList(growable: false),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(t('source_api'))),
                        DataColumn(label: Text(t('target_api'))),
                        DataColumn(label: Text(t('status'))),
                        DataColumn(label: Text(t('uses'))),
                      ],
                      rows: coverage.take(40).map((row) => DataRow(cells: [
                            DataCell(SelectableText('${row['source_api']}')),
                            DataCell(SelectableText('${row['target_api']}')),
                            DataCell(Text('${row['status']}')),
                            DataCell(Text('${row['source_hits']}')),
                          ])).toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
