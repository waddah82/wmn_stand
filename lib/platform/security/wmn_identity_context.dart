class WmnIdentityContext {
  const WmnIdentityContext({
    required this.user,
    required this.userId,
    required this.displayName,
    required this.roles,
    required this.revision,
  });

  final String user;
  final String? userId;
  final String displayName;
  final List<String> roles;
  final int revision;

  bool get isGuest => user == 'Guest';

  bool get isSystemUser =>
      roles.contains('Administrator') ||
      roles.contains('System Manager') ||
      roles.contains('SYSTEM_ADMIN');

  bool hasRole(String role) => roles.contains(role);
}
