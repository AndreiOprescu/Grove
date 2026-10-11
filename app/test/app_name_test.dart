// The name a person sees is "Grove" on each system. The id of the app and
// the names that make the data folder do not change: a change there would
// start the app with an empty folder.
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
      final project = read('macos/Runner.xcodeproj/project.pbxproj');
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
            r'^PRODUCT_BUNDLE_IDENTIFIER = local\.grove\.grove$',
            multiLine: true,
          ),
        ),
      );
      final ids = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]*);')
          .allMatches(read('ios/Runner.xcodeproj/project.pbxproj'))
          .map((m) => m[1])
          .toSet();
      expect(ids, {'local.grove.grove', 'local.grove.grove.RunnerTests'});
    });

    test('Android: the application id', () {
      final gradle = Directory('android/app')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.uri.pathSegments.last.startsWith('build.gradle'))
          .readAsStringSync();
      expect(gradle, contains('applicationId = "local.grove.grove"'));
      expect(gradle, contains('namespace = "local.grove.grove"'));
    });

    // path_provider_windows makes the data folder from these two texts:
    // %APPDATA%\<CompanyName>\<ProductName>.
    test('Windows: the two names of the data folder, and the file name', () {
      final rc = read('windows/runner/Runner.rc');
      expect(resourceValue(rc, 'CompanyName'), 'local.grove');
      expect(resourceValue(rc, 'ProductName'), 'grove');
      expect(resourceValue(rc, 'OriginalFilename'), 'grove.exe');
      expect(
        read('windows/CMakeLists.txt'),
        contains('set(BINARY_NAME "grove")'),
      );
    });
  });
}
