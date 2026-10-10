import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grove/services/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:path_provider/path_provider.dart';

import 'ui/store_app.dart';
import 'ui/theme/fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // The folder of this app for its own files. The database, the backups and
  // the settings of this device live there.
  final dir = (await getApplicationSupportDirectory()).path;
  final prefs = FilePrefs('$dir${Platform.pathSeparator}prefs.json');
  final notifier = AppServices.notifier(prefs);
  final store = AppStore.open(dataDir: dir, notifier: notifier, prefs: prefs);
  AppServices.forThisDevice(store).start();
  runApp(StoreApp(store: store));
}
