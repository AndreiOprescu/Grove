import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'tray_gateway.dart';

/// The real tray: the menu bar of the Mac and the notification area of Windows.
///
/// A click on the icon opens the menu on the Mac, as every menu bar app does.
/// On Windows a click shows the window and a right click opens the menu.
class TrayManagerGateway implements TrayGateway {
  /// A black shape. The Mac colours it for a light or a dark menu bar.
  static const macIcon = 'assets/tray/leaf_template.png';
  static const windowsIcon = 'assets/tray/leaf.png';

  static bool get _onMac => defaultTargetPlatform == TargetPlatform.macOS;
  static bool get _onWindows => defaultTargetPlatform == TargetPlatform.windows;

  // The native side frees an object that Dart forgets, so these stay here.
  TrayIcon? _icon;
  Menu? _menu;
  List<MenuItem?> _items = const [];
  List<TrayEntry> _entries = const [];
  void Function()? _onClick;

  @override
  bool show({required String tooltip, void Function()? onClick}) {
    if (kIsWeb || !(_onMac || _onWindows)) return false;
    if (_icon != null) return true;
    return _safe(() {
          if (!TrayManager.instance.isSupported()) return false;
          final icon = TrayIcon.create();
          if (icon == null) return false;
          icon.icon = ImageAsset.fromAsset(_onMac ? macIcon : windowsIcon);
          if (_onMac) icon.isIconTemplate = true;
          icon.setTooltip(tooltip);
          icon.setContextMenuTrigger(
            _onMac
                ? ContextMenuTrigger.clicked
                : ContextMenuTrigger.rightClicked,
          );
          icon.addListener((event) {
            if (event is TrayIconClickedEvent && !_onMac) _onClick?.call();
          });
          icon.setVisible(true);
          _onClick = onClick;
          _icon = icon;
          return true;
        }) ??
        false;
  }

  @override
  void setMenu(List<TrayEntry> entries) {
    final icon = _icon;
    if (icon == null) return;
    _safe(() {
      if (_sameShape(entries, _entries) && _menu != null) {
        // Only the text is new. The open menu does not jump.
        for (var i = 0; i < entries.length; i++) {
          final item = _items[i];
          if (item == null) continue;
          if (item.label != entries[i].label) item.label = entries[i].label;
        }
        _entries = entries;
        return;
      }
      final menu = Menu.create();
      if (menu == null) return;
      final items = <MenuItem?>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        if (entry.isSeparator) {
          menu.addSeparator();
          items.add(null);
          continue;
        }
        final item = MenuItem.createWithLabelAndType(
          entry.label,
          MenuItemType.normal,
        );
        if (item != null) {
          item.isEnabled = entry.onTap != null;
          item.addListener((event) {
            // The entry of now, not the entry of the day the menu was made.
            if (event is MenuItemClickedEvent && i < _entries.length) {
              _entries[i].onTap?.call();
            }
          });
          menu.addItem(item);
        }
        items.add(item);
      }
      icon.setContextMenu(menu);
      _menu = menu;
      _items = items;
      _entries = entries;
    });
  }

  /// The same lines of the same kind in the same places.
  static bool _sameShape(List<TrayEntry> a, List<TrayEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].isSeparator != b[i].isSeparator) return false;
      if ((a[i].onTap == null) != (b[i].onTap == null)) return false;
    }
    return true;
  }

  @override
  void setTooltip(String text) => _safe(() => _icon?.setTooltip(text));

  @override
  void dispose() {
    _safe(() {
      _icon?.setVisible(false);
      _icon?.dispose();
    });
    _icon = null;
    _menu = null;
    _items = const [];
    _entries = const [];
    _onClick = null;
  }

  /// A tray that fails must never stop Grove.
  static T? _safe<T>(T Function() body) {
    try {
      return body();
    } catch (error) {
      assert(() {
        debugPrint('Grove tray: $error');
        return true;
      }());
      return null;
    }
  }
}
