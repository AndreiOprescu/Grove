// Shared helpers for the widget and golden tests of the screens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/app.dart';
import 'package:grove/ui/shell/root_view.dart';
import 'package:grove/ui/shell/shell_model.dart';
import 'package:grove/ui/theme/theme_spec.dart';

/// The smallest window of the Mac app.
const desktopSize = Size(1100, 620);

/// A common phone, upright.
const phoneSize = Size(390, 844);

/// A model with motion off, so `pumpAndSettle` can finish and a golden is
/// one still frame.
LocalShellModel still({
  Screen screen = Screen.today,
  ThemeId themeId = ThemeId.grove,
  AppearanceMode appearance = AppearanceMode.light,
  LeftPane? leftPane,
}) => LocalShellModel(
  screen: screen,
  themeId: themeId,
  appearance: appearance,
  leftPane: leftPane,
  motion: false,
);

/// Shows the app in a window of `size` points and waits until it is still
/// when motion is off.
Future<void> pumpApp(
  WidgetTester tester,
  LocalShellModel model, {
  required Size size,
  ScreenBuilder? screenBuilder,
  PaneBuilder? paneBuilder,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(model.dispose);
  // A new key each time: the app starts fresh, with no cross-fade from the
  // theme of the app pumped before.
  await tester.pumpWidget(
    GroveApp(
      key: UniqueKey(),
      model: model,
      screenBuilder: screenBuilder,
      paneBuilder: paneBuilder,
    ),
  );
  // Take the tree down at the end, before the model is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  if (model.motionSetting) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

/// Loads the Material icon font of the Flutter SDK. Without it a test
/// draws every icon as an empty box.
Future<void> loadIconFont() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    throw StateError('FLUTTER_ROOT is not set. Run the tests with flutter.');
  }
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Runs `body` with real, soft shadows. A test draws shadows as hard
/// blocks unless it asks for the real ones. Pump the widgets inside `body`.
Future<void> withRealShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Compares a screenshot with its golden file, with a small allowance.
///
/// The same widgets drawn on macOS, Windows and Linux differ by a hair:
/// each system makes the edges of icon and text shapes a little softer or
/// harder. Nothing moves. Measured on CI (F6): up to 0.86 % of the pixels
/// of a phone picture, all on such edges.
///
/// So a pixel counts as different only when both are true:
/// - a channel is off by more than [channelTolerance] (of 255), and
/// - it is not a soft edge: its colour is not between the colours around
///   the same place (up to [edgeRadius] pixels away) in the other picture.
///   The check runs both ways, so a thin shape that is missing still counts.
///
/// The test fails when more than [pixelBudget] of the pixels are different,
/// or when the size is not the same.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile);

  static const channelTolerance = 12;
  static const edgeRadius = 1;
  static const pixelBudget = 0.002;

  /// Makes this the comparator of the test file that calls it.
  static void install() {
    final current = goldenFileComparator;
    if (current is TolerantGoldenComparator) return;
    if (current is LocalFileComparator) {
      goldenFileComparator = TolerantGoldenComparator(
        current.basedir.resolve('placeholder_test.dart'),
      );
    }
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed) {
      result.dispose();
      return true;
    }
    final share = await differentShare(
      imageBytes,
      Uint8List.fromList(await getGoldenBytes(golden)),
    );
    if (share != null && share <= pixelBudget) {
      // Printed so a CI log shows how close each OS is.
      debugPrint(
        'golden $golden: ${(share * 100).toStringAsFixed(3)}% of the pixels '
        'differ by more than $channelTolerance/255 away from a soft edge '
        '(allowed: ${pixelBudget * 100}%)',
      );
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(
      '$error\nShare of pixels off by more than $channelTolerance/255 away '
      'from a soft edge: '
      '${share == null ? 'sizes differ' : (share * 100).toStringAsFixed(3)}% '
      '(allowed: ${pixelBudget * 100}%)',
    );
  }

  /// The share of pixels that are different (see the class comment), or
  /// null when the two pictures do not have the same size.
  static Future<double?> differentShare(Uint8List a, Uint8List b) async {
    final imageA = await _decode(a);
    final imageB = await _decode(b);
    try {
      if (imageA.width != imageB.width || imageA.height != imageB.height) {
        return null;
      }
      final width = imageA.width;
      final height = imageA.height;
      final bytesA = (await imageA.toByteData())!.buffer.asUint8List();
      final bytesB = (await imageB.toByteData())!.buffer.asUint8List();
      var different = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          if (_near(bytesA, bytesB, i)) continue;
          if (_between(bytesA, i, bytesB, x, y, width, height) &&
              _between(bytesB, i, bytesA, x, y, width, height)) {
            continue;
          }
          different++;
        }
      }
      return different / (width * height);
    } finally {
      imageA.dispose();
      imageB.dispose();
    }
  }

  /// True when the pixel at byte `i` is the same in both, within the
  /// tolerance.
  static bool _near(Uint8List a, Uint8List b, int i) {
    for (var c = 0; c < 4; c++) {
      if ((a[i + c] - b[i + c]).abs() > channelTolerance) return false;
    }
    return true;
  }

  /// True when the pixel at byte `i` of `from` (place x, y) has a colour
  /// between the darkest and the lightest pixel around the same place in
  /// `around`, within the tolerance. That is what a soft edge looks like.
  static bool _between(
    Uint8List from,
    int i,
    Uint8List around,
    int x,
    int y,
    int width,
    int height,
  ) {
    for (var c = 0; c < 4; c++) {
      var low = 255;
      var high = 0;
      for (var dy = -edgeRadius; dy <= edgeRadius; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -edgeRadius; dx <= edgeRadius; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          final value = around[(ny * width + nx) * 4 + c];
          if (value < low) low = value;
          if (value > high) high = value;
        }
      }
      final value = from[i + c];
      if (value < low - channelTolerance || value > high + channelTolerance) {
        return false;
      }
    }
    return true;
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
