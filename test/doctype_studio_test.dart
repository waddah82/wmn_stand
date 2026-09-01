import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/framework/doctype_studio/doctype_studio_models.dart';
import 'package:wmn_standalone/framework/doctype_studio/doctype_studio_service.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';

void main() {
  late WmnDatabase database;
  late WmnMetaService meta;
  late WmnDocTypeStudioService studio;

  setUp(() {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    meta = WmnMetaService(database: database, registry: registry, customization: customization);
    studio = WmnDocTypeStudioService(meta: meta);

    meta.saveDocType(name: 'Studio Target', module: 'Studio Module', titleField: 'title');
    meta.saveField(doctype: 'Studio Target', fieldName: 'title', label: 'Title', fieldType: 'Data', required: true);
    meta.saveDocType(name: 'Studio Demo', module: 'Studio Module', titleField: 'title');
    meta.saveField(
      doctype: 'Studio Demo',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
      inListView: true,
    );
    meta.saveField(
      doctype: 'Studio Demo',
      fieldName: 'customer',
      label: 'Target',
      fieldType: 'Link',
      options: 'Studio Target',
    );
  });

  tearDown(() => database.close());

  test('DocType module is registered and available as a real option', () {
    expect(meta.modules(), contains('Studio Module'));
    final module = database.db.select("SELECT name FROM wmn_modules WHERE name='Studio Module';");
    expect(module, isNotEmpty);
  });

  test('client code validates known fields while metadata stores only Storage revision paths', () {
    final source = '''frappe.ui.form.on('Studio Demo', {
  validate(frm) {
    frm.set_value('title', 'Validated');
  }
});''';
    final validation = studio.validate('Studio Demo', WmnStudioArtifactKind.clientCode, source);
    expect(validation.isValid, isTrue);

    final saved = studio.validateAndSave('Studio Demo', WmnStudioArtifactKind.clientCode, source);
    expect(saved.status, WmnStudioArtifactStatus.validated);
    expect(saved.revision, 1);

    final snapshot = studio.snapshot('Studio Demo');
    expect(snapshot.artifact(WmnStudioArtifactKind.clientCode).source, source);
    expect(snapshot.revisions, hasLength(1));
    expect(snapshot.revisions.single.source, isEmpty);
    expect(studio.revisionSource(snapshot.revisions.single), source);
    final metadataJson = '${database.db.select("SELECT metadata_json FROM wmn_doctypes WHERE name='Studio Demo';").single['metadata_json']}';
    expect(metadataJson, contains('source_path'));
    expect(metadataJson, isNot(contains('frm.set_value')));
    expect(studio.storage.exists(saved.sourcePath!), isTrue);
    expect(

      database.db.select("SELECT COUNT(*) AS value FROM client_scripts WHERE document_type='Studio Demo';").first['value'],
      0,
    );
  });

  test('unknown client field fails validation before activation', () {
    final result = studio.validate(
      'Studio Demo',
      WmnStudioArtifactKind.clientCode,
      "frappe.ui.form.on('Studio Demo', { validate(frm) { frm.set_value('missing_field', 1); } });",
    );
    expect(result.isValid, isFalse);
    expect(result.diagnostics.any((entry) => entry.code == 'UNKNOWN_FIELD'), isTrue);
  });

  test('server source blocks raw SQL and direct GL access', () {
    final result = studio.validate(
      'Studio Demo',
      WmnStudioArtifactKind.serverCode,
      "frappe.db.sql('select * from tabGL Entry')",
    );
    expect(result.isValid, isFalse);
    expect(result.diagnostics.any((entry) => entry.code == 'BLOCKED_SERVER_API'), isTrue);
  });

  test('native styles are scoped and validate field selectors', () {
    final valid = studio.validate(
      'Studio Demo',
      WmnStudioArtifactKind.formStyle,
      'field(title) { font-weight: bold; text-color: primary; }',
    );
    expect(valid.isValid, isTrue);

    final invalid = studio.validate(
      'Studio Demo',
      WmnStudioArtifactKind.formStyle,
      'field(does_not_exist) { font-weight: bold; }',
    );
    expect(invalid.isValid, isFalse);
    expect(invalid.diagnostics.any((entry) => entry.code == 'UNKNOWN_FIELD'), isTrue);
  });

  test('revision rollback creates a new draft without mutating old revision', () {
    final one = studio.validateAndSave(
      'Studio Demo',
      WmnStudioArtifactKind.clientCode,
      "frappe.ui.form.on('Studio Demo', { refresh(frm) { frm.set_value('title', 'One'); } });",
    );
    expect(one.revision, 1);
    final two = studio.validateAndSave(
      'Studio Demo',
      WmnStudioArtifactKind.clientCode,
      "frappe.ui.form.on('Studio Demo', { refresh(frm) { frm.set_value('title', 'Two'); } });",
    );
    expect(two.revision, 2);

    final revisionOne = studio.snapshot('Studio Demo').revisions.firstWhere((entry) => entry.revision == 1);
    final restored = studio.restoreRevision('Studio Demo', revisionOne);
    expect(restored.revision, 3);
    expect(restored.status, WmnStudioArtifactStatus.draft);
    expect(restored.source, contains("'One'"));
  });
}
