// A picture is checked and made smaller before the store keeps it.
// Swift: GroveCore/Services/ImageTools.swift.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/editor/image_prepare.dart';

/// A JPEG of 4 by 3 pixels.
final _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAA'
  'AAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABKADAAQAAAABAAAAAwAAAAD/7QA4UGhvdG9z'
  'aG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgA'
  'AwAEAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIB'
  'AwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYX'
  'GBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeI'
  'iYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn'
  '6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIB'
  'AgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDTh'
  'JfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWG'
  'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm'
  '5+jp6vLz9PX29/j5+v/bAEMABgYGBgYGCgYGCg4KCgoOEg4ODg4SFxISEhISFxwXFxcXFxcc'
  'HBwcHBwcHCIiIiIiIicnJycnLCwsLCwsLCwsLP/bAEMBBwcHCwoLEwoKEy4fGh8uLi4uLi4u'
  'Li4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLi4uLv/dAAQAAf/aAAwD'
  'AQACEQMRAD8Ap+JNL0yQ6aZLWFj/AGbanJjUnLJuPOO5JP41zf8AY+kf8+cH/fpf8K7LxB10'
  '3/sG2f8A6KFc9X2OAy7Cyw1KUqUW3FdF29CsfOX1mrr9p/mf/9k=',
);

/// A GIF of 4 by 3 pixels.
final _gif = base64Decode(
  'R0lGODdhBAADAKIAAAAAAP8AAP8A/wD/AAD/////AP///wAAACH5BAQAAAAALAAAAAAEAAMA'
  'AAMIGDIQVSIYIhIAOw==',
);

/// A PNG of one colour.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF2E7D32),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// The width and the height of a stored picture, read from its data.
Future<(int, int)> _size(Uint8List data) async {
  final codec = await ui.instantiateImageCodec(data);
  final image = (await codec.getNextFrame()).image;
  final size = (image.width, image.height);
  image.dispose();
  codec.dispose();
  return size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the name of a picture', () {
    test('the name of the file with no ending', () {
      expect(imageName('door.png'), 'door');
      expect(imageName('door.final.JPG'), 'door.final');
      expect(imageName('photo'), 'photo');
      expect(imageName('.hidden'), '.hidden');
    });

    test('a folder in front of the name is not a part of it', () {
      expect(imageName('/Users/me/Pictures/door.png'), 'door');
      expect(imageName(r'C:\Users\me\door.png'), 'door');
    });
  });

  group('a picture that fits', () {
    test('a PNG is kept byte for byte', () async {
      final raw = await _png(40, 30);
      final image = (await prepareImage(raw))!;
      expect(image.mime, 'image/png');
      expect(image.data, same(raw));
      expect((image.width, image.height), (40, 30));
    });

    test('a JPEG is kept byte for byte', () async {
      final image = (await prepareImage(_jpeg))!;
      expect(image.mime, 'image/jpeg');
      expect(image.data, same(_jpeg));
      expect((image.width, image.height), (4, 3));
    });

    test('a picture of exactly the limit is kept', () async {
      final raw = await _png(20, 10);
      final image = (await prepareImage(raw, maxSide: 20))!;
      expect(image.data, same(raw));
    });

    test('a GIF is written again as a PNG of the same size', () async {
      final image = (await prepareImage(_gif))!;
      expect(image.mime, 'image/png');
      expect(image.data, isNot(_gif));
      expect((image.width, image.height), (4, 3));
      expect(await _size(image.data), (4, 3));
    });
  });

  group('a large picture', () {
    test('the limit of the Mac app: 1600 pixels on the long side', () {
      expect(imageMaxSide, 1600);
    });

    test('a wide PNG gets 1600 pixels of width, in the same shape', () async {
      final raw = await _png(2000, 1000);
      final image = (await prepareImage(raw))!;
      expect(image.mime, 'image/png');
      expect((image.width, image.height), (1600, 800));
      expect(await _size(image.data), (1600, 800));
    });

    test('a high PNG gets the limit as its height', () async {
      final raw = await _png(30, 90);
      final image = (await prepareImage(raw, maxSide: 30))!;
      expect((image.width, image.height), (10, 30));
      expect(await _size(image.data), (10, 30));
    });

    test('a large JPEG is made smaller too', () async {
      final image = (await prepareImage(_jpeg, maxSide: 2))!;
      expect(image.mime, 'image/png');
      expect((image.width, image.height), (2, 2));
    });
  });

  group('not a picture', () {
    test('no data', () async {
      expect(await prepareImage(Uint8List(0)), isNull);
    });

    test('a text file', () async {
      final text = Uint8List.fromList(utf8.encode('{"tasks": []}'));
      expect(await prepareImage(text), isNull);
    });

    test('a file that only starts as a PNG', () async {
      final raw = (await _png(8, 8)).sublist(0, 12);
      expect(await prepareImage(raw), isNull);
    });
  });

  test('a picked file gets its name and its checked picture', () async {
    final raw = await _png(8, 6);
    final good = await pickedImage('garden gate.png', raw);
    expect(good.name, 'garden gate');
    expect(good.image!.data, same(raw));
    final bad = await pickedImage('notes.txt', Uint8List.fromList([1, 2, 3]));
    expect(bad.name, 'notes');
    expect(bad.image, isNull);
  });
}
