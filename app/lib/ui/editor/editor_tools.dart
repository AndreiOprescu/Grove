// What the editor needs from the system: a window to pick pictures, and
// the browser for a web link. The app gives the real ones (`main.dart`); a
// test gives fakes, or none.
import 'package:flutter/widgets.dart';

import 'markdown_controller.dart';

/// Lets the user pick pictures. The result goes into the text.
typedef ImagePicker = Future<List<PickedImage>> Function();

/// Opens a web address in the browser. False when the system could not.
typedef LinkOpener = Future<bool> Function(Uri url);

/// The web address of a link in a text. null when Grove must not open it:
/// only `http` and `https` addresses with a host open (Q-16 of
/// `docs/questions.md`). A `file:`, `mailto:` or `javascript:` link does
/// nothing.
Uri? webLink(String text) {
  final trimmed = text.trim();
  // An address has no blank in it.
  if (trimmed.contains(RegExp(r'\s'))) return null;
  final url = Uri.tryParse(trimmed);
  if (url == null || url.host.isEmpty) return null;
  return url.isScheme('http') || url.isScheme('https') ? url : null;
}

/// Gives the picker and the browser to each editor under it.
class EditorTools extends InheritedWidget {
  const EditorTools({
    super.key,
    this.pickImages,
    this.openLink,
    required super.child,
  });

  /// With null no editor shows "Add an image".
  final ImagePicker? pickImages;

  /// With null a click on a web link does nothing.
  final LinkOpener? openLink;

  static EditorTools? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditorTools>();

  @override
  bool updateShouldNotify(EditorTools oldWidget) =>
      oldWidget.pickImages != pickImages || oldWidget.openLink != openLink;
}
