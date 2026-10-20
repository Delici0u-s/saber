import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/tape.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();

  test('tape is drawn as drawn, as a shape pen stroke with a flag', () {
    final tape = Tape();
    tape.onDragStart(const Offset(10, 10), EditorPage(), 0, null);
    for (var x = 20.0; x <= 200; x += 10) {
      tape.onDragUpdate(Offset(x, 10 + (x % 30) / 3), null);
    }
    final stroke = tape.onDragEnd()!;
    expect(stroke.isTape, isTrue);
    expect(stroke.toolId.id, 'ShapePen');
    expect(stroke.options.size, Highlighter.currentHighlighter.options.size);
    expect(stroke.color.a, 1);
    expect(stroke.pointVectors.length, greaterThan(2), reason: 'as drawn');

    // A tap isn't tape.
    tape.onDragStart(const Offset(10, 10), EditorPage(), 0, null);
    expect(tape.onDragEnd(), isNull);
  });

  test('held still, tape becomes a shape, and stays tape', () {
    fakeAsync((async) {
      final tape = Tape();
      const center = Offset(500, 500), radius = 200.0;
      final circle = [
        for (var i = 0; i <= 64; i++)
          center + Offset.fromDirection(2 * pi * i / 64, radius),
      ];
      tape.onDragStart(circle.first, EditorPage(), 0, null);
      for (final point in circle.skip(1)) {
        tape.onDragUpdate(point, null);
      }
      async.elapse(Duration(milliseconds: stows.holdToShapeDelay.value * 2));
      expect(Pen.detectedShape?.name, isNotNull, reason: 'held into a shape');
      final stroke = tape.onDragEnd()!;
      expect(stroke.isTape, isTrue);
      // Recognised: a perfect circle, not the points drawn.
      for (final point in stroke.pointVectors) {
        expect((point - center).distance, closeTo(radius, radius * 0.1));
      }
    });
  });

  test('saved as tape, and hidden again when loaded', () {
    final stroke =
        Stroke(
            color: Colors.orange,
            pressureEnabled: false,
            options: .new(size: 20),
            pageIndex: 0,
            page: const HasSize(Size(1000, 1400)),
            toolId: .shapePen,
            isTape: true,
          )
          ..addPoint(Offset.zero)
          ..addPoint(const Offset(100, 0))
          ..tapeRevealed = true;
    final json = stroke.toJson();
    expect(json['tape'], isTrue);
    final loaded = Stroke.fromJson(
      json,
      fileVersion: EditorCoreInfo.sbnVersion,
      pageIndex: 0,
      page: const HasSize(Size(1000, 1400)),
    );
    expect(loaded.isTape, isTrue);
    expect(loaded.tapeRevealed, isFalse);
    expect(stroke.copy().isTape, isTrue);
    expect(
      (Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: .new(),
        pageIndex: 0,
        page: const HasSize(Size(1000, 1400)),
        toolId: .ballpointPen,
      )..addPoint(Offset.zero)).toJson().containsKey('tape'),
      isFalse,
    );
  });

  test('the highlighter tab remembers tape', () {
    addTearDown(() => stows.lastHighlighterTabIsTape.value = false);
    stows.lastHighlighterTabIsTape.value = true;
    expect(Tape.highlighterTab, same(Tape.currentTape));
    stows.lastHighlighterTabIsTape.value = false;
    expect(Tape.highlighterTab, same(Highlighter.currentHighlighter));
  });

  testGoldens('tapping tape shows what\'s under it, without a dot', (
    tester,
  ) async {
    setupMockPathProvider();
    setupMockPrinting();
    await tester.runAsync(FileManager.init);
    await tester.pumpWidget(
      TranslationProvider(
        child: ScreenshotApp(
          device: GoldenScreenshotDevices.flathub.device,
          home: Editor(),
        ),
      ),
    );
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pumpAndSettle();
    final page = state.coreInfo.pages.first;
    Offset onScreen(Offset onPage) => page.renderBox!.localToGlobal(onPage);

    Future<void> drag(Offset from, Offset to) async {
      final gesture = await tester.startGesture(onScreen(from));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(onScreen(Offset.lerp(from, to, i / 10)!));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    state.currentTool = Pen.currentPen;
    await drag(const Offset(300, 400), const Offset(500, 400));
    state.currentTool = Tape.currentTape;
    await drag(const Offset(280, 400), const Offset(520, 400));
    expect(page.strokes, hasLength(2));
    final tape = page.strokes.singleWhere((stroke) => stroke.isTape);
    expect(tape.tapeRevealed, isFalse);

    // With the pen, like a real tap: no dot is left on the tape.
    state.currentTool = Pen.currentPen;
    await tester.tapAt(
      onScreen(const Offset(400, 400)),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pumpAndSettle();
    expect(tape.tapeRevealed, isTrue);
    expect(page.strokes, hasLength(2));

    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(onScreen(const Offset(400, 400)));
    await tester.pumpAndSettle();
    expect(tape.tapeRevealed, isFalse);

    // Double-tapping tape opens and closes it, without switching to the
    // eraser.
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAt(onScreen(const Offset(400, 400)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(onScreen(const Offset(400, 400)));
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());
  });
}
