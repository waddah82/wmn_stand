import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/configuration/wmn_configuration_service.dart';
import 'package:wmn_standalone/platform/diagnostics/wmn_diagnostics_service.dart';
import 'package:wmn_standalone/platform/diagnostics/wmn_log_service.dart';
import 'package:wmn_standalone/platform/files/wmn_file_service.dart';
import 'package:wmn_standalone/platform/jobs/wmn_job_service.dart';
import 'package:wmn_standalone/platform/kernel/wmn_kernel.dart';
import 'package:wmn_standalone/platform/notifications/wmn_notification_service.dart';
import 'package:wmn_standalone/platform/printing/wmn_printing_service.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('files store portable bytes and generic document attachments', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final files = WmnFileService(database);

    final stored = files.storeBytes(
      fileName: 'example.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      attachedToDoctype: 'Demo Entity',
      attachedToName: 'DEMO-0001',
    );

    expect(stored.fileSize, 4);
    expect(stored.storageKey, startsWith('files/private/'));
    expect(database.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wmn_file_contents';"), isEmpty);
    expect(files.readBytes(stored.id), orderedEquals(<int>[1, 2, 3, 4]));
    expect(files.attachments('Demo Entity', 'DEMO-0001'), hasLength(1));

    files.delete(stored.id);
    expect(files.file(stored.id), isNull);
  });

  test('large file API exposes asynchronous storage path without database blobs', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final files = WmnFileService(database);
    final payload = Uint8List.fromList(List<int>.generate(256 * 1024, (index) => index % 251));

    final stored = await files.storeBytesAsync(
      fileName: 'large.bin',
      bytes: payload,
      attachedToDoctype: 'Demo Entity',
      attachedToName: 'DEMO-ASYNC',
    );

    expect(await files.readBytesAsync(stored.id), orderedEquals(payload));
    expect(database.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wmn_file_contents';"), isEmpty);
    await files.deleteAsync(stored.id);
    expect(files.file(stored.id), isNull);
  });

  test('scoped configuration remains independent between system and application scopes', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final audit = AuditService(database);
    final config = WmnConfigurationService(database: database, audit: audit);

    config.setValue(WmnConfigurationScope.system, 'locale', 'ar');
    config.setValue(WmnConfigurationScope.application, 'locale', 'en', scopeKey: 'sample_app');

    expect(config.getString(WmnConfigurationScope.system, 'locale', fallback: 'en'), 'ar');
    expect(
      config.getString(WmnConfigurationScope.application, 'locale', scopeKey: 'sample_app', fallback: 'ar'),
      'en',
    );
    expect(audit.count, 2);
  });

  test('job foundation schedules due work and runs registered handlers', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final logs = WmnLogService(database);
    final jobs = WmnJobService(database: database, logs: logs);
    jobs.registerHandler('test.add', (args) => (args['a'] as int) + (args['b'] as int));

    final now = DateTime.now().toUtc();
    jobs.scheduleEvery(
      name: 'test schedule',
      handlerName: 'test.add',
      interval: const Duration(minutes: 5),
      firstRunAt: now.subtract(const Duration(seconds: 1)),
      args: const <String, Object?>{'a': 2, 'b': 3},
    );

    expect(jobs.enqueueDueSchedules(now: now), 1);
    final result = jobs.runNext();
    expect(result?.status, 'SUCCESS');
    expect(result?.result, 5);
  });

  test('notifications deliver in-app and keep external channels in an outbox', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final notifications = WmnNotificationService(database);

    final inApp = notifications.notifyInApp(title: 'Ready', body: 'Platform ready');
    final sms = notifications.queue(
      channel: WmnNotificationChannel.sms,
      title: 'Queued',
      body: 'Adapter will deliver this later',
      recipient: 'recipient',
    );

    final rows = notifications.notifications(limit: 10);
    expect(rows.firstWhere((entry) => entry.id == inApp).status, 'SENT');
    expect(rows.firstWhere((entry) => entry.id == sms).status, 'QUEUED');
  });

  test('diagnostics snapshot is platform-only and logging is persistent', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);
    final applications = WmnApplicationRegistry(database, modules, capabilities);
    addTearDown(applications.dispose);
    final kernel = WmnKernel(modules: modules, capabilities: capabilities, applications: applications);
    addTearDown(kernel.dispose);
    kernel.start();

    final logs = WmnLogService(database);
    final diagnostics = WmnDiagnosticsService(database: database, kernel: kernel, logs: logs);
    final snapshot = diagnostics.snapshot();

    expect(snapshot.database['schema_version'], WmnDatabase.schemaVersion);
    expect(snapshot.kernel['healthy'], isTrue);
    diagnostics.recordSnapshot();
    expect(logs.entries(), isNotEmpty);
  });

  test('printing foundation queues generic document jobs without business assumptions', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final printing = WmnPrintingService(database);

    final id = printing.queueDocument(documentType: 'Any Document', documentName: 'DOC-0001');
    expect(printing.jobs(status: 'PENDING').single.id, id);
    printing.markSent(id);
    expect(printing.jobs(status: 'SENT').single.documentType, 'Any Document');
  });
}
