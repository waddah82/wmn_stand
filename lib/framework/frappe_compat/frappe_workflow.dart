import '../../platform/workflow/wmn_workflow_runtime.dart';
import 'frappe_documents.dart';

/// Frappe-compatible workflow action name retained for source parity.
typedef WmnFrappeWorkflowAction = WmnWorkflowAction;

class WmnFrappeWorkflowDocumentGateway implements WmnWorkflowDocumentGateway {
  const WmnFrappeWorkflowDocumentGateway(this.documents);

  final WmnFrappeDocumentApi documents;

  @override
  Map<String, Object?>? get(String doctype, String name) =>
      documents.getDoc(doctype, name);

  @override
  Map<String, Object?> save(
    String doctype,
    String name,
    Map<String, Object?> values,
  ) =>
      documents.save(doctype, name, values);

  @override
  Map<String, Object?> submit(String doctype, String name) =>
      documents.submit(doctype, name);

  @override
  Map<String, Object?> cancel(String doctype, String name) =>
      documents.cancel(doctype, name);
}

/// Compatibility facade over the native WMN workflow runtime.
///
/// Frappe-facing APIs do not own a second workflow engine. They delegate to
/// the platform runtime so state rules, permissions, history and lifecycle
/// transactions stay identical for native and converted applications.
class WmnFrappeWorkflowEngine {
  const WmnFrappeWorkflowEngine(this.runtime);

  final WmnWorkflowRuntime runtime;

  Map<String, Object?>? workflowFor(String doctype) {
    final workflow = runtime.workflowFor(doctype);
    if (workflow == null) return null;
    return <String, Object?>{
      'id': workflow.id,
      'name': workflow.name,
      'doctype': workflow.doctype,
      'state_field': workflow.stateField,
      'enabled': workflow.enabled ? 1 : 0,
      'send_email': workflow.sendEmail ? 1 : 0,
      'metadata_json': workflow.metadata,
    };
  }

  List<WmnFrappeWorkflowAction> availableActions(
    String doctype,
    Map<String, Object?> document,
  ) =>
      runtime.availableActions(doctype, document);

  Map<String, Object?> applyAction(
    String doctype,
    String docname,
    String action, {
    String? comment,
  }) =>
      runtime.applyAction(doctype, docname, action, comment: comment);

  void saveWorkflow({
    required String id,
    required String name,
    required String doctype,
    String stateField = 'workflow_state',
    bool enabled = true,
    bool sendEmail = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      runtime.saveWorkflow(
        id: id,
        name: name,
        doctype: doctype,
        stateField: stateField,
        enabled: enabled,
        sendEmail: sendEmail,
        metadata: metadata,
      );

  void saveState({
    required String id,
    required String workflowId,
    required String stateName,
    int docStatus = 0,
    String? allowEditRole,
    int index = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      runtime.saveState(
        id: id,
        workflowId: workflowId,
        stateName: stateName,
        docStatus: docStatus,
        allowEditRole: allowEditRole,
        index: index,
        metadata: metadata,
      );

  void saveTransition({
    required String id,
    required String workflowId,
    required String stateName,
    required String action,
    required String nextState,
    String? allowedRole,
    String? condition,
    int index = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) =>
      runtime.saveTransition(
        id: id,
        workflowId: workflowId,
        stateName: stateName,
        action: action,
        nextState: nextState,
        allowedRole: allowedRole,
        condition: condition,
        index: index,
        metadata: metadata,
      );

  List<Map<String, Object?>> history(String doctype, String docname) =>
      runtime.history(doctype, docname);
}
