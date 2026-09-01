import 'package:flutter/material.dart';

import 'settings_repository.dart';

class WmnThemeController extends ChangeNotifier {
  WmnThemeController(this.settings)
      : _mode = _decodeMode(settings.getString('theme_mode', fallback: 'dark')),
        _accent = _decodeAccent(settings.getString('theme_accent', fallback: 'teal'));

  final SettingsRepository settings;
  ThemeMode _mode;
  String _accent;

  ThemeMode get mode => _mode;
  String get accent => _accent;
  Color get seedColor => accentColors[_accent] ?? accentColors['teal']!;

  static const Map<String, Color> accentColors = <String, Color>{
    'teal': Color(0xff236a63),
    'blue': Color(0xff3566a8),
    'indigo': Color(0xff5555a5),
    'purple': Color(0xff76518e),
    'orange': Color(0xff9a5a28),
  };

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    settings.setString(
      'theme_mode',
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    notifyListeners();
  }

  void setAccent(String accent) {
    final normalized = accent.toLowerCase().trim();
    if (!accentColors.containsKey(normalized) || normalized == _accent) return;
    _accent = normalized;
    settings.setString('theme_accent', normalized);
    notifyListeners();
  }

  static ThemeMode _decodeMode(String value) => switch (value.toLowerCase()) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  static String _decodeAccent(String value) => accentColors.containsKey(value.toLowerCase()) ? value.toLowerCase() : 'teal';
}
