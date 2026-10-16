// The app gives its editors the window to pick pictures and the browser
// (Q-15 and Q-16 of `docs/questions.md`). The tests give fakes: no test
// opens a real file window or a real browser.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/editor/editor_tools.dart';
import 'package:grove/ui/editor/image_prepare.dart';
import 'package:grove/ui/editor/markdown_controller.dart';
import 'package:grove/ui/notes/note_editor_pane.dart';
import 'package:grove/ui/store_app.dart';

import 'planner/planner_support.dart';

final _addImage = find.bySemanticsLabel('Add an image');

Finder _field(String name) => find.descendant(
  of: find.byKey(ValueKey(name)),
  matching: find.byType(EditableText),
);

String _shown(WidgetTester tester, String name) =>
    tester.widget<EditableText>(_field(name)).controller.text;

Future<void> _pump(
  WidgetTester tester,
  AppStore store, {
  ImagePicker? pickImages,
  LinkOpener? openLink,
  Size size = desktopSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreApp(
      key: UniqueKey(),
      store: store,
      pickImages: pickImages,
      openLink: openLink,
    ),
  );
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

/// A real PNG file, as a file window gives it.
Future<Uint8List> _png(WidgetTester tester) async {
  final data = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 8, 6),
      ui.Paint()..color = const ui.Color(0xFF2E7D32),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 6);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  });
  return data!;
}

/// What the file window of the test gives: the file `door.png`.
Future<PickedImage> _door(WidgetTester tester) async {
  final raw = await _png(tester);
  final picked = await tester.runAsync(() => pickedImage('door.png', raw));
  return picked!;
}

AppStore _noteStore(String body) {
  final store = plannerStore();
  store.newNote(title: 'Trip', body: body);
  return store;
}

AppStore _eventStore() {
  final store = plannerStore()..screen = Screen.calendar;
  store.createFromDraft(
    title: 'Stand-up',
    day: wednesday,
    start: 9 * 60,
    end: 10 * 60,
    asEvent: true,
  );
  return store;
}

Future<void> _openEvent(WidgetTester tester, AppStore store) async {
  store.editEvent(
    store
        .eventItems(DayRange(wednesday, wednesday))
        .firstWhere((e) => e.title == 'Stand-up'),
  );
  await tester.pumpAndSettle();
}

/// Taps "Add an image" in the row of the text, or in its "…" menu when the
/// box is too narrow for every tool.
Future<void> _tapAddImage(WidgetTester tester) async {
  if (_addImage.evaluate().isEmpty) {
    final more = find.byTooltip('More tools');
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an image').last);
    return;
  }
  await tester.ensureVisible(_addImage);
  await tester.pumpAndSettle();
  await tester.tap(_addImage);
}

final _markup = RegExp(r'!\[door\]\(grove-image:([0-9A-Fa-f-]+)\)');

void main() {
  group('"Add an image"', () {
    testWidgets('in a note: the picture is stored and goes in the text', (
      tester,
    ) async {
      final store = _noteStore('see');
      final door = await _door(tester);
      var asked = 0;
      await _pump(
        tester,
        store,
        pickImages: () async {
          asked += 1;
          return [door];
        },
      );
      expect(_addImage, findsOneWidget);
      await _tapAddImage(tester);
      await tester.pump();
      await tester.pump();
      expect(asked, 1);
      final match = _markup.firstMatch(_shown(tester, 'note-text'));
      expect(match, isNotNull);
      // The store holds the file, byte for byte.
      expect(store.image(match!.group(1)!), door.image!.data);

      await tester.pump(NoteEditorPane.saveDelay);
      await tester.pumpAndSettle();
      expect(store.note(store.selectedNoteId!)!.body, contains(match[0]!));
    });

    testWidgets('in the notes of an event', (tester) async {
      final store = _eventStore();
      final door = await _door(tester);
      await _pump(tester, store, pickImages: () async => [door]);
      // The planner has no text with buttons.
      expect(_addImage, findsNothing);
      await _openEvent(tester, store);
      await _tapAddImage(tester);
      await tester.pump();
      await tester.pump();
      final match = _markup.firstMatch(_shown(tester, 'event-notes'));
      expect(match, isNotNull);
      expect(store.image(match!.group(1)!), door.image!.data);
    });

    testWidgets('on a phone too', (tester) async {
      final store = _noteStore('see');
      final door = await _door(tester);
      await _pump(
        tester,
        store,
        size: phoneSize,
        pickImages: () async => [door],
      );
      await _tapAddImage(tester);
      await tester.pump();
      await tester.pump();
      expect(_markup.hasMatch(_shown(tester, 'note-text')), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pump(NoteEditorPane.saveDelay);
      await tester.pumpAndSettle();
    });

    testWidgets('a file that is not a picture: a message, and no change', (
      tester,
    ) async {
      final store = _noteStore('see');
      final bad = (await tester.runAsync(
        () => pickedImage('list.txt', Uint8List.fromList([1, 2, 3])),
      ))!;
      await _pump(tester, store, pickImages: () async => [bad]);
      await _tapAddImage(tester);
      await tester.pump();
      await tester.pump();
      expect(_shown(tester, 'note-text'), 'see');
      expect(store.toast, 'list is not an image Grove can read.');
      await endToast(tester);
    });

    testWidgets('an app with no picker has no button', (tester) async {
      final note = _noteStore('see');
      await _pump(tester, note);
      expect(_field('note-text'), findsOneWidget);
      expect(_addImage, findsNothing);

      final event = _eventStore();
      await _pump(tester, event);
      await _openEvent(tester, event);
      expect(_field('event-notes'), findsOneWidget);
      expect(_addImage, findsNothing);
    });
  });

  group('a web link in a note', () {
    const body = 'see https://grove.example/a now';

    Future<void> clickLink(WidgetTester tester, String name) async {
      final state = tester.state<EditableTextState>(_field(name));
      final box = state.renderEditable
          .getBoxesForSelection(
            const TextSelection(baseOffset: 4, extentOffset: 27),
          )
          .first
          .toRect();
      await tester.tapAt(
        state.renderEditable.localToGlobal(box.center),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
    }

    testWidgets('a click opens the browser', (tester) async {
      final store = _noteStore(body);
      final links = <Uri>[];
      await _pump(
        tester,
        store,
        openLink: (url) async {
          links.add(url);
          return true;
        },
      );
      await clickLink(tester, 'note-text');
      expect(links, [Uri.parse('https://grove.example/a')]);
      expect(store.toast, isNull);
      await tester.pump(NoteEditorPane.saveDelay);
      await tester.pumpAndSettle();
    });

    testWidgets('a browser that cannot open it: a message', (tester) async {
      final store = _noteStore(body);
      await _pump(tester, store, openLink: (url) async => false);
      await clickLink(tester, 'note-text');
      await tester.pump();
      expect(store.toast, 'Grove could not open the link.');
      await endToast(tester);
    });

    testWidgets('an app with no browser: a click does nothing', (tester) async {
      final store = _noteStore(body);
      await _pump(tester, store);
      await clickLink(tester, 'note-text');
      expect(store.toast, isNull);
      expect(tester.takeException(), isNull);
      await tester.pump(NoteEditorPane.saveDelay);
      await tester.pumpAndSettle();
    });
  });
}
