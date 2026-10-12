import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// The folder `app/` of the repo.
Directory appFolder() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('No pubspec.yaml above the tests.');
    dir = parent;
  }
  return dir;
}

Uint8List bytesOf(String path) {
  final file = File('${appFolder().path}/$path');
  if (!file.existsSync()) fail('No file $path.');
  return file.readAsBytesSync();
}

/// The picture as RGBA bytes, with the alpha apart from the colours.
Future<({int width, int height, ByteData rgba})> decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;
  final rgba = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final result = (width: image.width, height: image.height, rgba: rgba!);
  image.dispose();
  return result;
}

/// The colour type of a PNG file: 2 is RGB, 6 is RGB with alpha.
int colourType(Uint8List png) => png[25];

/// The colour at a place given as parts of the width and the height.
({int r, int g, int b, int a}) colourAt(
  ({int width, int height, ByteData rgba}) image,
  double x,
  double y,
) {
  final column = (image.width * x).floor().clamp(0, image.width - 1);
  final row = (image.height * y).floor().clamp(0, image.height - 1);
  final at = (row * image.width + column) * 4;
  return (
    r: image.rgba.getUint8(at),
    g: image.rgba.getUint8(at + 1),
    b: image.rgba.getUint8(at + 2),
    a: image.rgba.getUint8(at + 3),
  );
}

/// The logo is "Night sprout": a cream sprout on a dark green tile.
Future<void> expectGroveLogo(Uint8List png, int size, String name) async {
  final image = await decode(png);
  expect(image.width, size, reason: '$name: width');
  expect(image.height, size, reason: '$name: height');

  // Above the leaves there is only the tile.
  final tile = colourAt(image, 0.5, 0.15);
  expect(tile.a, 255, reason: '$name: the tile hides what is behind it');
  expect(tile.g, greaterThan(tile.r), reason: '$name: the tile is green');
  expect(tile.g, greaterThan(tile.b), reason: '$name: the tile is green');
  expect(tile.g, lessThan(160), reason: '$name: the tile is dark');

  // The stem goes through the middle. On a small picture it is too thin
  // to give a clean colour.
  if (size >= 128) {
    final stem = colourAt(image, 0.5, 0.5);
    expect(stem.r, greaterThan(200), reason: '$name: the stem is cream');
    expect(stem.g, greaterThan(200), reason: '$name: the stem is cream');
    expect(stem.b, greaterThan(190), reason: '$name: the stem is cream');
  }
}

/// The files and pixel sizes that an `AppIcon.appiconset` names.
Map<String, int> namedIn(String folder) {
  final contents = jsonDecode(
    utf8.decode(bytesOf('$folder/Contents.json')),
  ) as Map<String, Object?>;
  final sizes = <String, int>{};
  for (final image
      in (contents['images']! as List).cast<Map<String, Object?>>()) {
    final points = double.parse((image['size']! as String).split('x').first);
    final scale = int.parse((image['scale']! as String).replaceAll('x', ''));
    sizes['$folder/${image['filename']}'] = (points * scale).round();
  }
  return sizes;
}

void main() {
  test(
    'macOS: each icon is the Grove logo at the size its slot needs',
    () async {
      final files = namedIn('macos/Runner/Assets.xcassets/AppIcon.appiconset');
      expect(files, hasLength(7));
      for (final MapEntry(key: path, value: size) in files.entries) {
        final png = bytesOf(path);
        await expectGroveLogo(png, size, path);
        // The tile has a clear edge around it, as each Mac icon has.
        final corner = colourAt(await decode(png), 0, 0);
        expect(corner.a, 0, reason: '$path: the corner is clear');
      }
    },
  );

  test(
    'iOS: each icon is the Grove logo, a full square with no alpha',
    () async {
      final files = namedIn('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      expect(files, hasLength(15));
      for (final MapEntry(key: path, value: size) in files.entries) {
        final png = bytesOf(path);
        await expectGroveLogo(png, size, path);
        expect(colourType(png), 2, reason: '$path: no alpha in the file');
        final corner = colourAt(await decode(png), 0, 0);
        expect(corner.g, greaterThan(corner.r), reason: '$path: green corner');
      }
    },
  );

  test('Android: each launcher icon is the Grove logo', () async {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final MapEntry(key: density, value: size) in sizes.entries) {
      final path = 'android/app/src/main/res/mipmap-$density/ic_launcher.png';
      await expectGroveLogo(bytesOf(path), size, path);
    }
  });

  test('Windows: the icon file holds the Grove logo at each size', () async {
    final ico = bytesOf('windows/runner/resources/app_icon.ico');
    final data = ByteData.sublistView(ico);
    expect(data.getUint16(0, Endian.little), 0);
    expect(data.getUint16(2, Endian.little), 1, reason: 'an icon file');
    final count = data.getUint16(4, Endian.little);
    final sizes = <int>[];
    for (var i = 0; i < count; i++) {
      final entry = 6 + i * 16;
      final size = ico[entry] == 0 ? 256 : ico[entry];
      expect(ico[entry + 1] == 0 ? 256 : ico[entry + 1], size);
      expect(
        data.getUint16(entry + 6, Endian.little),
        32,
        reason: '$size: 32 bits',
      );
      final length = data.getUint32(entry + 8, Endian.little);
      final start = data.getUint32(entry + 12, Endian.little);
      expect(start + length, lessThanOrEqualTo(ico.length));
      sizes.add(size);
      if (size == 256) {
        final png = Uint8List.sublistView(ico, start, start + length);
        await expectGroveLogo(png, 256, 'app_icon.ico at 256');
      } else {
        // A bitmap: its header gives the width, and two times the height.
        expect(data.getUint32(start, Endian.little), 40);
        expect(data.getInt32(start + 4, Endian.little), size);
        expect(data.getInt32(start + 8, Endian.little), size * 2);
        // The middle of the top part is the tile: opaque, green, dark.
        // Rows go from the bottom up, and a pixel is blue, green, red, alpha.
        final row = size - 1 - (size * 0.15).floor();
        final at = start + 40 + (row * size + size ~/ 2) * 4;
        expect(ico[at + 3], 255, reason: '$size: the tile is opaque');
        expect(ico[at + 1], greaterThan(ico[at]), reason: '$size: green');
        expect(ico[at + 1], greaterThan(ico[at + 2]), reason: '$size: green');
      }
    }
    expect(sizes, containsAll([16, 32, 48, 256]));
  });
}
