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
  // stays. A copy that failed is tried again on the next start.
  final home = Platform.environment['HOME'];
  var copy = SandboxCopyResult.skipped;
  if (Platform.isMacOS && home != null && home.isNotEmpty) {
    copy = SandboxDataCopy.copyOnce(
      from: SandboxDataCopy.oldFolder(home),
      to: dir,
    );
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
    // GitHub tells Grove when a newer version is out.
    releases: GitHubReleaseSource(),
    // The weather at the top of each day.
    weather: OpenMeteoSource(),
    location: const DeviceLocationSource(),
    // Null on a phone: it makes jobs, a computer runs them.
    agentRunner: AppServices.agentRunner(),
    // When the owner falls asleep, from the use of the phone and the Mac.
    activity: AppServices.activitySource(),
    loginItem: AppServices.loginItem(),
  );
  if (copy == SandboxCopyResult.failed && store.errorMessage == null) {
    store.errorMessage = SandboxDataCopy.failedMessage;
  }
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
