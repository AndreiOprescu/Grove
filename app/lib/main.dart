import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grove/services/services.dart';
import 'package:grove/state/state.dart' hide MotionRules;
import 'package:path_provider/path_provider.dart';

import 'ui/store_app.dart';
import 'ui/system/system_tools.dart';
import 'ui/theme/fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // The folder of this app for its own files. The database, the backups and
  // the settings of this device live there.
  final dir = (await getApplicationSupportDirectory()).path;
  // Grove for Mac left the sandbox (ADR 0004). The first start copies the
  // data of the sandboxed Grove, before the database opens. The old folder
  // stays.
  final home = Platform.environment['HOME'];
  if (Platform.isMacOS && home != null && home.isNotEmpty) {
    SandboxDataCopy.copyOnce(from: SandboxDataCopy.oldFolder(home), to: dir);
  }
  final prefs = FilePrefs('$dir${Platform.pathSeparator}prefs.json');
  final notifier = AppServices.notifier(prefs);
  // Null when the build has no keys for a Supabase project: no sync then.
  final sync = await SupabaseBackend.start(SyncConfig.fromEnvironment);
  final store = AppStore.open(
    dataDir: dir,
    notifier: notifier,
    prefs: prefs,
    sync: sync,
    // Null on a phone: it makes jobs, a computer runs them.
    agentRunner: AppServices.agentRunner(),
  );
  AppServices.forThisDevice(store).start();
  runApp(
    StoreApp(
      store: store,
      // The real windows of the system. A test starts `StoreApp` with none.
      files: SystemFiles(),
      pickImages: pickImageFiles,
      openLink: openInBrowser,
      openDraft: openDraftApp,
    ),
  );
}
