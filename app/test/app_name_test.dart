// The name a person sees is "Grove" on each system. The id of the app and
// the names that make the data folder do not change: a change there would
// start the app with an empty folder. Two exceptions. The owner's answer to
// Q-40: the Windows product name got a capital G. The owner's answers to
// Q-26 and Q-30: the id is `local.grove.app` since 2026-10-12, the day the
// Swift app was retired. The old id is in docs/acceptance/retire-swift.md.
//
// These are the files of the native projects. The tests read them from the
// folder `app/`, where `flutter test` runs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

/// The value of `key` in a property list, when it is a string.
String? plistString(String plist, String key) =>
    RegExp('<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>')
        .firstMatch(plist)
        ?.group(1);

/// The value of `VALUE "name", "value"` in a Windows resource file.
String? resourceValue(String rc, String name) =>
    RegExp('VALUE "${RegExp.escape(name)}", "([^"]*)"')
        .firstMatch(rc)
        ?.group(1);

void main() {
  group('the name on the screen is Grove', () {
    test('macOS: the app in the Applications folder, the menu bar and '
        'the Dock', () {
      final config = read('macos/Runner/Configs/AppInfo.xcconfig');
      expect(
        config,
        contains(RegExp(r'^PRODUCT_NAME = Grove$', multiLine: true)),
      );
      // The name in the menu bar is the product name.
      expect(
        plistString(read('macos/Runner/Info.plist'), 'CFBundleName'),
        r'$(PRODUCT_NAME)',
      );
    });

    test('macOS: the Xcode project names the same app', () {
      // The id `local.grove.app` has the text "grove.app" in it. It is not
      // a file name, so it is taken out before the check.
      final project = read('macos/Runner.xcodeproj/project.pbxproj')
          .replaceAll('local.grove.app', '');
      expect(project, isNot(contains('grove.app')));
      expect(project, contains('Grove.app'));
      // The unit tests of the runner start inside the app.
      expect(
        RegExp(r'TEST_HOST = "([^"]*)"').allMatches(project).map((m) => m[1]),
        everyElement(
          r'$(BUILT_PRODUCTS_DIR)/Grove.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/'
          'Grove',
        ),
      );
      final scheme = read(
        'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
      );
      expect(scheme, isNot(contains('grove.app')));
      expect(scheme, contains('BuildableName = "Grove.app"'));
    });

    // The release build and the speed check take the app out of the build
    // folder by its name. A Mac disk that tells capital letters apart finds
    // only the right name.
    test('macOS: the scripts name the same app and the same program', () {
      final release = read('../scripts/flutter_release.sh');
      expect(release, isNot(contains('grove.app')));
      expect(release, contains('build/macos/Build/Products/Release/Grove.app'));
      final perf = read('../scripts/flutter_perf.sh');
      expect(perf, isNot(contains('grove.app')));
      expect(perf, contains(r'build/macos/Build/Products/$mode_dir/Grove.app'));
      expect(perf, isNot(contains('Contents/MacOS/grove')));
      expect(perf, contains('Contents/MacOS/Grove'));
      // The install script takes the app that the release script built.
      // It names the data folder, which has the id in it; see above.
      final install = read('../scripts/flutter_install.sh')
          .replaceAll('local.grove.app', '');
      expect(install, isNot(contains('grove.app')));
      expect(
        install,
        contains('BUILT="app/build/macos/Build/Products/Release/Grove.app"'),
      );
      expect(install, contains('./scripts/flutter_release.sh macos'));
    });

    test('iOS: the name under the icon and the name of the bundle', () {
      final plist = read('ios/Runner/Info.plist');
      expect(plistString(plist, 'CFBundleDisplayName'), 'Grove');
      expect(plistString(plist, 'CFBundleName'), 'Grove');
    });

    test('Android: the name under the icon', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:label="Grove"'));
    });

    test('Windows: the title of the window and the name in Task Manager', () {
      expect(
        read('windows/runner/main.cpp'),
        contains('window.Create(L"Grove"'),
      );
      expect(
        resourceValue(read('windows/runner/Runner.rc'), 'FileDescription'),
        'Grove',
      );
    });

    test('the app itself: the title of the window in the app switcher', () {
      expect(read('lib/ui/app.dart'), contains("title: 'Grove'"));
    });
  });

  group('the id and the data folder stay', () {
    test('macOS and iOS: the bundle id', () {
      expect(
        read('macos/Runner/Configs/AppInfo.xcconfig'),
        contains(
          RegExp(
            r'^PRODUCT_BUNDLE_IDENTIFIER = local\.grove\.app$',
            multiLine: true,
          ),
        ),
      );
      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]*);')
          .allMatches(read('ios/Runner.xcodeproj/project.pbxproj'))
          .map((m) => m[1])
          .toSet();
      expect(ids, {'local.grove.app', 'local.grove.app.RunnerTests'});
      // On the Mac the id of the app is in AppInfo.xcconfig; the project
      // file has only the ids of the unit tests of the runner.
      final macIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]*);')
          .allMatches(read('macos/Runner.xcodeproj/project.pbxproj'))
          .map((m) => m[1])
          .toSet();
      expect(macIds, {'local.grove.app.RunnerTests'});
    });

    test('Android: the application id', () {
      final gradle = Directory('android/app')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.uri.pathSegments.last.startsWith('build.gradle'))
          .readAsStringSync();
      expect(gradle, contains('applicationId = "local.grove.app"'));
      expect(gradle, contains('namespace = "local.grove.app"'));
      // The start class is in the folder and the package of the id. A line
      // ends with "\r\n" in a Windows checkout, so the test reads a line.
      expect(
        read('android/app/src/main/kotlin/local/grove/app/MainActivity.kt'),
        contains(RegExp(r'^package local\.grove\.app$', multiLine: true)),
      );
      // No folder of an older id is left beside it.
      expect(
        Directory('android/app/src/main/kotlin/local/grove')
            .listSync()
            .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
            // Finder can put a hidden file here on a Mac.
            .where((name) => !name.startsWith('.')),
        ['app'],
      );
    });

    // path_provider_windows makes the data folder from these two texts:
    // %APPDATA%\<CompanyName>\<ProductName>.
    // The product name is "Grove" since the answer to Q-40 (2026-10-12). A
    // normal Windows disk does not tell "grove" and "Grove" apart, so the
    // folder is the same one there. The other names did not change.
    test('Windows: the two names of the data folder, and the file name', () {
      final rc = read('windows/runner/Runner.rc');
      expect(resourceValue(rc, 'CompanyName'), 'local.grove');
      expect(resourceValue(rc, 'ProductName'), 'Grove');
      expect(resourceValue(rc, 'InternalName'), 'grove');
      expect(resourceValue(rc, 'OriginalFilename'), 'grove.exe');
      expect(
        read('windows/CMakeLists.txt'),
        contains('set(BINARY_NAME "grove")'),
      );
    });
  });
}
