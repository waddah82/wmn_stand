import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/localization/wmn_localization.dart';
import '../platform/ui/wmn_platform_shell.dart';
import 'wmn_runtime.dart';

class WmnApp extends StatelessWidget {
  const WmnApp({super.key, required this.runtime});

  final WmnRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([runtime.locale, runtime.theme]),
      builder: (context, _) => WmnL10nScope(
        controller: runtime.locale,
        child: MaterialApp(
          title: 'WMN Application Platform',
          debugShowCheckedModeBanner: false,
          locale: runtime.locale.locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: runtime.theme.mode,
          theme: _theme(Brightness.light, runtime.theme.seedColor),
          darkTheme: _theme(Brightness.dark, runtime.theme.seedColor),
          home: WmnPlatformShell(runtime: runtime),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness, Color seed) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: isDark ? const Color(0xff111614) : const Color(0xfffafcfb),
    );
    final outline = isDark ? const Color(0xff33413d) : const Color(0xffd9e4e0);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? const Color(0xff0d1210) : const Color(0xfff3f7f5),
      dividerColor: outline,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 54,
        backgroundColor: isDark ? const Color(0xff111714) : const Color(0xfffbfdfc),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: isDark ? const Color(0xff151c19) : Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xff151c19) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(isDark ? const Color(0xff151c19) : const Color(0xfff2f6f4)),
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          iconSize: 20,
          padding: const EdgeInsets.all(8),
          visualDensity: VisualDensity.compact,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: outline),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xff111714) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
