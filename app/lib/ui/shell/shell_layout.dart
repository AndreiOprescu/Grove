// The size rules of the app shell: phone or desktop, and how big the
// buttons are.
import 'dart:ui' show Size;

/// The two shapes of the shell.
enum ShellLayout {
  /// Narrow: the screens are in a bar at the bottom, and an open panel
  /// takes the place of the screen.
  phone,

  /// Wide: the screen switch is at the top, and an open panel sits beside
  /// the screen.
  desktop,
}

abstract final class ShellRules {
  /// A window narrower than this is a phone.
  static const phoneBreakpoint = 700.0;

  /// From this width the screen switch shows a word beside each picture.
  static const labelsBreakpoint = 960.0;

  /// Height of the strip at the top of a desktop window. The Mac app keeps
  /// the same 34 pt free above every screen.
  static const desktopTopStrip = 34.0;

  /// Height of the strip at the top of a phone.
  static const phoneTopStrip = 48.0;

  /// Height of the bar at the bottom of a phone.
  static const phoneNavBar = 56.0;

  static ShellLayout layoutFor(double width) =>
      width < phoneBreakpoint ? ShellLayout.phone : ShellLayout.desktop;

  static bool switchShowsLabels(double width) => width >= labelsBreakpoint;

  /// The size of one button of the left dock. A finger needs more room
  /// than a mouse pointer.
  static Size dockButton(ShellLayout layout) => switch (layout) {
    ShellLayout.desktop => const Size(28, 22),
    ShellLayout.phone => const Size(44, 40),
  };
}
