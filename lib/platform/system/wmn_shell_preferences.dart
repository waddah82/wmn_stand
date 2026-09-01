import 'package:flutter/foundation.dart';

import '../../core/settings/settings_repository.dart';

class WmnShellPreferences extends ChangeNotifier {
  WmnShellPreferences(this.settings)
      : _sidebarCollapsed = settings.getBool('shell.sidebar_collapsed', fallback: false),
        _compact = settings.getBool('shell.compact', fallback: false),
        _showWorkspaceLabels = settings.getBool('shell.workspace_labels', fallback: true);

  final SettingsRepository settings;

  bool _sidebarCollapsed;
  bool _compact;
  bool _showWorkspaceLabels;

  bool get sidebarCollapsed => _sidebarCollapsed;
  bool get compact => _compact;
  bool get showWorkspaceLabels => _showWorkspaceLabels;

  void setSidebarCollapsed(bool value) {
    if (_sidebarCollapsed == value) return;
    _sidebarCollapsed = value;
    settings.setBool('shell.sidebar_collapsed', value);
    notifyListeners();
  }

  void toggleSidebar() => setSidebarCollapsed(!_sidebarCollapsed);

  void setCompact(bool value) {
    if (_compact == value) return;
    _compact = value;
    settings.setBool('shell.compact', value);
    notifyListeners();
  }

  void setShowWorkspaceLabels(bool value) {
    if (_showWorkspaceLabels == value) return;
    _showWorkspaceLabels = value;
    settings.setBool('shell.workspace_labels', value);
    notifyListeners();
  }
}
