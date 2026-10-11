// Port of Sources/GroveCore/Services/ImageTools.swift: checks that a file is
// a picture and makes a large one smaller, before the store keeps it.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:grove/state/state.dart' show ImageToStore;

import 'markdown_controller.dart';

/// The most pixels on the long side of a stored picture. Swift:
/// `ImageTools.maxSide`.
const imageMaxSide = 1600;

/// The name a picture gets in the text: the name of its file with no
/// ending. Swift: `url.deletingPathExtension().lastPathComponent`.
String imageName(String fileName) {
  final slash = math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf(r'\'));
  final name = fileName.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// "image/png" or "image/jpeg" when the data starts as such a file.
String? _keptMime(Uint8List raw) {
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  bool starts(List<int> head) {
    if (raw.length < head.length) return false;
    for (var i = 0; i < head.length; i++) {
      if (raw[i] != head[i]) return false;
    }
    return true;
  }

  if (starts(png)) return 'image/png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  return null;
}

/// Checks that `raw` is a picture and makes it smaller when it is large.
/// A PNG or JPEG that fits is kept byte for byte. Anything else is written
/// again as a PNG (Flutter has no writer for JPEG). null when `raw` is not
/// a picture this device can read.
Future<ImageToStore?> prepareImage(
  Uint8List raw, {
  int maxSide = imageMaxSide,
}) async {
  if (raw.isEmpty) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(raw);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0) return null;
    final long = math.max(width, height);
    final mime = _keptMime(raw);
    if (long <= maxSide && mime != null) {
      return (mime: mime, data: raw, width: width, height: height);
    }
    final scale = long > maxSide ? maxSide / long : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (width * scale).round()),
      targetHeight: math.max(1, (height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return (
      mime: 'image/png',
      data: png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      width: image.width,
      height: image.height,
    );
  } on Object {
    // Not a picture, or a kind this device cannot read.
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// One file the user picked, ready for `MarkdownController.importImages`.
Future<PickedImage> pickedImage(String fileName, Uint8List data) async =>
    (name: imageName(fileName), image: await prepareImage(data));
