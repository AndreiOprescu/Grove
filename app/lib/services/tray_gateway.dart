/// One line of the tray menu.
class TrayEntry {
  /// A line with text. The user cannot click it when [onTap] is null.
  const TrayEntry(this.label, {this.onTap}) : isSeparator = false;

  const TrayEntry.separator() : label = '', onTap = null, isSeparator = true;

  final String label;
  final void Function()? onTap;
  final bool isSeparator;
}

/// The small part of the system tray (the menu bar on a Mac) that Grove uses.
/// The real one is `TrayManagerGateway`. A test uses a fake one.
abstract class TrayGateway {
  /// Shows the icon. False when this system has no tray. [onClick] is for a
  /// system where a click on the icon does not open the menu (Windows).
  bool show({required String tooltip, void Function()? onClick});
  void setMenu(List<TrayEntry> entries);
  void setTooltip(String text);
  void dispose();
}
