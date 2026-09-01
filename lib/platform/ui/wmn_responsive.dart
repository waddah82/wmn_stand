import 'package:flutter/widgets.dart';

/// Width-driven WMN responsive contract.
///
/// Layout never branches on operating system. A narrow Windows window and a
/// phone with the same available width receive the same compact composition.
abstract final class WmnResponsive {
  static const double compactShellMaxWidth = 920;
  static const double compactPageMaxWidth = 640;
  static const double inlineSearchMinWidth = 760;
  static const double fullToolbarMinWidth = 1100;

  static bool compactShell(double width) => width < compactShellMaxWidth;
  static bool compactPage(double width) => width < compactPageMaxWidth;

  static EdgeInsets pagePadding(double width) => compactPage(width)
      ? const EdgeInsets.all(12)
      : const EdgeInsets.all(18);
}
