// The real windows of the system: the file windows (the package
// `file_selector`, Q-15 and Q-18 of `docs/questions.md`) and the browser
// (the package `url_launcher`, Q-16). Only `main.dart` uses this file. A
// test gives fakes to `StoreApp`, so no test opens a real window.
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../editor/editor_tools.dart';
import '../editor/image_prepare.dart';
import '../editor/markdown_controller.dart';
import '../settings/settings_view.dart';

/// The pictures Flutter can read on each of the 4 systems. Windows picks
/// by the ending of the name, Android by the kind, Apple by its own name
/// for "any picture".
const _images = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  mimeTypes: ['image/*'],
  uniformTypeIdentifiers: ['public.image'],
);

const _json = XTypeGroup(
  label: 'JSON',
  extensions: ['json'],
  mimeTypes: ['application/json'],
  uniformTypeIdentifiers: ['public.json'],
);

/// The window of "Add an image": the user picks one picture or more. Each
/// one is checked and made smaller (`prepareImage`). A closed window gives
/// an empty list. Swift: `EditorController.addImage`.
Future<List<PickedImage>> pickImageFiles() async {
  final files = await openFiles(acceptedTypeGroups: const [_images]);
  return [
    for (final file in files)
      await pickedImage(file.name, await file.readAsBytes()),
  ];
}

/// Opens a web address in the browser of the system. Only `http` and
/// `https`; false for any other address, and when the system cannot.
Future<bool> openInBrowser(Uri url) async {
  if (webLink('$url') == null) return false;
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// The save window and the open window of "Export" and "Import".
class SystemFiles extends SettingsFiles {
  /// `file_selector` has a save window on macOS, Windows and Linux only.
  @override
  bool get canSave => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  @override
  Future<String?> save({
    required String suggestedName,
    required String text,
  }) async {
    final place = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_json],
    );
    if (place == null) return null;
    final file = File(place.path);
    await file.writeAsString(text, flush: true);
    return file.uri.pathSegments.last;
  }

  @override
  Future<({String name, String text})?> open() async {
    final file = await openFile(acceptedTypeGroups: const [_json]);
    if (file == null) return null;
    // A file that is not text gives broken letters here, and the import
    // then says that it is not a Grove file.
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    return (name: file.name, text: text);
  }

  /// Finder and Explorer. Swift: `NSWorkspace.shared.open(folder)`.
  @override
  bool get canShowFolder => switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.windows => true,
    _ => false,
  };

  @override
  Future<bool> showFolder(String path) async {
    try {
      return await launchUrl(Uri.directory(path));
    } on Object {
      return false;
    }
  }
}
