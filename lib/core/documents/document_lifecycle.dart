import '../database/wmn_database.dart';
import 'document_event_bus.dart';

enum DocumentLifecycleStatus {
  draft('DRAFT'),
  submitted('SUBMITTED'),
  cancelled('CANCELLED');

  const DocumentLifecycleStatus(this.databaseValue);
  final String databaseValue;
}

enum WmnDocumentLifecycleOperation {
  insert('insert'),
  update('update'),
  updateAfterSubmit('update_after_submit'),
  submit('submit'),
  cancel('cancel'),
  delete('delete');

  const WmnDocumentLifecycleOperation(this.id);
  final String id;
}

class DocumentLifecycleEngine {
  const DocumentLifecycleEngine();

  void ensureTransition({
    required DocumentLifecycleStatus from,
    required DocumentLifecycleStatus to,
  }) {
    if (from == DocumentLifecycleStatus.draft &&
        to == DocumentLifecycleStatus.submitted) {
      return;
    }
    if (from == DocumentLifecycleStatus.submitted &&
        to == DocumentLifecycleStatus.cancelled) {
      return;
    }
    throw StateError(
      'Invalid document lifecycle transition: ${from.databaseValue} -> ${to.databaseValue}.',
    );
  }
}

typedef WmnDocumentIdentityCallback = void Function(
  Map<String, Object?> document,
);
typedef WmnDocumentPersistCallback = Map<String, Object?> Function(
  Map<String, Object?> document,
);
typedef WmnDocumentNormalizeCallback = Map<String, Object?> Function(
  Map<String, Object?> document,
);
typedef WmnDocumentDeleteCallback = void Function();

/// Canonical transactional lifecycle for WMN documents.
///
/// All before/after events execute inside the same database transaction as the
/// persistence operation. If validation, an extension, versioning or an
/// after-event throws, SQLite rolls the whole operation back.
class WmnDocumentLifecycleRuntime {
  WmnDocumentLifecycleRuntime({
    required this.database,
    WmnDocumentEventBus? events,
    DocumentLifecycleEngine? transitionEngine,
  })  : events = events ?? WmnDocumentEventBus(),
        transitionEngine = transitionEngine ?? const DocumentLifecycleEngine();

  final WmnDatabase database;
  final WmnDocumentEventBus events;
  final DocumentLifecycleEngine transitionEngine;

  Map<String, Object?> insert({
    required String doctype,
    required Map<String, Object?> document,
    String? actor,
    WmnDocumentIdentityCallback? assignIdentity,
    required WmnDocumentPersistCallback persist,
    WmnDocumentNormalizeCallback? normalize,
  }) {
    return database.transaction(() {
      final working = Map<String, Object?>.from(document);
      _emit(
        doctype: doctype,
        event: 'before_insert',
        operation: WmnDocumentLifecycleOperation.insert,
        document: working,
        actor: actor,
      );
      assignIdentity?.call(working);
      for (final event in const <String>[
        'before_validate',
        'validate',
        'before_save',
      ]) {
        _emit(
          doctype: doctype,
          event: event,
          operation: WmnDocumentLifecycleOperation.insert,
          document: working,
          actor: actor,
        );
      }
      var saved = persist(working);
      if (normalize != null) saved = normalize(saved);
      for (final event in const <String>[
        'after_insert',
        'on_update',
        'after_save',
      ]) {
        _emit(
          doctype: doctype,
          event: event,
          operation: WmnDocumentLifecycleOperation.insert,
          document: saved,
          actor: actor,
        );
      }
      return saved;
    });
  }

  Map<String, Object?> update({
    required String doctype,
    required Map<String, Object?> document,
    required Map<String, Object?> previous,
    required bool afterSubmit,
    String? actor,
    required WmnDocumentPersistCallback persist,
    WmnDocumentNormalizeCallback? normalize,
  }) {
    final operation = afterSubmit
        ? WmnDocumentLifecycleOperation.updateAfterSubmit
        : WmnDocumentLifecycleOperation.update;
    return database.transaction(() {
      final working = Map<String, Object?>.from(document);
      final beforeEvents = afterSubmit
          ? const <String>['before_update_after_submit']
          : const <String>['before_validate', 'validate', 'before_save'];
      for (final event in beforeEvents) {
        _emit(
          doctype: doctype,
          event: event,
          operation: operation,
          document: working,
          previous: previous,
          actor: actor,
        );
      }
      var saved = persist(working);
      if (normalize != null) saved = normalize(saved);
      final afterEvents = afterSubmit
          ? const <String>['on_update_after_submit']
          : const <String>['on_update', 'after_save'];
      for (final event in afterEvents) {
        _emit(
          doctype: doctype,
          event: event,
          operation: operation,
          document: saved,
          previous: previous,
          actor: actor,
        );
      }
      return saved;
    });
  }

  Map<String, Object?> submit({
    required String doctype,
    required Map<String, Object?> document,
    String? actor,
    required WmnDocumentPersistCallback persist,
    WmnDocumentNormalizeCallback? normalize,
  }) {
    transitionEngine.ensureTransition(
      from: DocumentLifecycleStatus.draft,
      to: DocumentLifecycleStatus.submitted,
    );
    return database.transaction(() {
      final working = Map<String, Object?>.from(document);
      for (final event in const <String>[
        'before_validate',
        'validate',
        'before_submit',
      ]) {
        _emit(
          doctype: doctype,
          event: event,
          operation: WmnDocumentLifecycleOperation.submit,
          document: working,
          actor: actor,
        );
      }
      var saved = persist(working);
      if (normalize != null) saved = normalize(saved);
      for (final event in const <String>['on_update', 'on_submit']) {
        _emit(
          doctype: doctype,
          event: event,
          operation: WmnDocumentLifecycleOperation.submit,
          document: saved,
          actor: actor,
        );
      }
      return saved;
    });
  }

  Map<String, Object?> cancel({
    required String doctype,
    required Map<String, Object?> document,
    String? actor,
    required WmnDocumentPersistCallback persist,
    WmnDocumentNormalizeCallback? normalize,
  }) {
    transitionEngine.ensureTransition(
      from: DocumentLifecycleStatus.submitted,
      to: DocumentLifecycleStatus.cancelled,
    );
    return database.transaction(() {
      final working = Map<String, Object?>.from(document);
      _emit(
        doctype: doctype,
        event: 'before_cancel',
        operation: WmnDocumentLifecycleOperation.cancel,
        document: working,
        actor: actor,
      );
      var saved = persist(working);
      if (normalize != null) saved = normalize(saved);
      _emit(
        doctype: doctype,
        event: 'on_cancel',
        operation: WmnDocumentLifecycleOperation.cancel,
        document: saved,
        actor: actor,
      );
      return saved;
    });
  }

  void delete({
    required String doctype,
    required Map<String, Object?> document,
    String? actor,
    required WmnDocumentDeleteCallback persist,
  }) {
    database.transaction(() {
      final working = Map<String, Object?>.from(document);
      for (final event in const <String>['before_delete', 'on_trash']) {
        _emit(
          doctype: doctype,
          event: event,
          operation: WmnDocumentLifecycleOperation.delete,
          document: working,
          actor: actor,
        );
      }
      persist();
      _emit(
        doctype: doctype,
        event: 'after_delete',
        operation: WmnDocumentLifecycleOperation.delete,
        document: working,
        actor: actor,
      );
    });
  }

  void _emit({
    required String doctype,
    required String event,
    required WmnDocumentLifecycleOperation operation,
    required Map<String, Object?> document,
    Map<String, Object?>? previous,
    String? actor,
  }) {
    events.emit(
      WmnDocumentEvent(
        doctype: doctype,
        event: event,
        operation: operation.id,
        document: document,
        previous: previous,
        actor: actor,
      ),
    );
  }
}
