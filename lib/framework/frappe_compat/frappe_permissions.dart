import '../../platform/security/wmn_permission_service.dart';

/// Frappe-compatible facade over the native WMN authorization runtime.
class WmnFrappePermissionEngine {
  WmnFrappePermissionEngine({required this.service});

  final WmnPermissionService service;

  List<String> rolesFor([String? user]) => service.rolesFor(user);
  bool hasRole(String role, {String? user}) => service.hasRole(role, user: user);
  bool hasSystemPermission(String code, {String? user}) =>
      service.hasSystemPermission(code, user: user);

  bool hasPermission(
    String doctype,
    String action, {
    String? docname,
    Map<String, Object?>? document,
    String? user,
  }) =>
      service.hasPermission(
        doctype,
        action,
        docname: docname,
        document: document,
        user: user,
      );

  Map<String, List<String>> capabilities({String? user}) =>
      service.capabilities(user: user);

  List<String> allowedValues(
    String allowDoctype, {
    String? applicableFor,
    String? user,
  }) =>
      service.allowedValues(
        allowDoctype,
        applicableFor: applicableFor,
        user: user,
      );

  void addUserPermission({
    required String id,
    required String userId,
    required String allowDoctype,
    required String value,
    String? applicableFor,
    bool isDefault = false,
  }) =>
      service.addUserPermission(
        id: id,
        userId: userId,
        allowDoctype: allowDoctype,
        value: value,
        applicableFor: applicableFor,
        isDefault: isDefault,
      );

  void invalidate({String? user}) => service.invalidate(user: user);

  void invalidateMetadata({String? doctype}) =>
      service.invalidateMetadata(doctype: doctype);
}
