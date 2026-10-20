import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/scribble_erase.dart';
import 'package:saber/data/tools/tape.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/has_size.dart';

import 'utils/test_mock_channel_handlers.dart';

/// Back and forth [times] times between x = [left] and [right], moving
/// down [step] each time, starting at [top].
List<Offset> _zigzag({
  int times = 6,
  double left = 100,
  double right = 300,
  double top = 100,
  double step = 8,
}) => [
  for (var i = 0; i <= times; i++)
    for (var j = 0; j <= 10; j++)
      Offset(
        i.isEven
            ? left + (right - left) * j / 10
            : right - (right - left) * j / 10,
        top + step * (i + j / 10),
      ),
];

Stroke _stroke(List<Offset> points) => Stroke(
  color: Colors.black,
  pressureEnabled: false,
  options: .new(size: 3),
  pageIndex: 0,
  page: const HasSize(Size(1000, 1400)),
  toolId: .ballpointPen,
)..addPoints(points);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();

  group('what counts as a scribble', () {
    test('going back and forth', () {
      expect(ScribbleErase.isScribble(_zigzag(), 3), isTrue);
      // Also diagonally.
      final diagonal = [
        for (final p in _zigzag()) Offset(p.dx + p.dy, p.dy - p.dx),
      ];
      expect(ScribbleErase.isScribble(diagonal, 3), isTrue);
    });

    test('not too few turns', () {
      expect(ScribbleErase.isScribble(_zigzag(times: 3), 3), isFalse);
    });

    test('not handwriting', () {
      // Loops moving right, like "eeeeee".
      final loops = [
        for (var i = 0; i < 300; i++)
          Offset(i + 10 * cos(i / 5), 100 + 10 * sin(i / 5)),
      ];
      expect(ScribbleErase.isScribble(loops, 3), isFalse);
      // A "w" and a straight line.
      expect(
        ScribbleErase.isScribble([
          for (var i = 0; i <= 40; i++)
            Offset(i * 5.0, 100 + 40 * (((i % 10) - 5).abs() / 5)),
        ], 3),
        isFalse,
      );
      expect(
        ScribbleErase.isScribble([
          for (var i = 0; i < 50; i++) Offset(i * 4.0, 100),
        ], 3),
        isFalse,
      );
    });

    test('not a wobble smaller than the stroke', () {
      final wobble = _zigzag(left: 100, right: 103, step: 0.5);
      expect(ScribbleErase.isScribble(wobble, 3), isFalse);
    });
  });

  test('erases only the strokes it mostly covers', () {
    final covered = _stroke([const Offset(150, 120), const Offset(250, 130)]);
    final half = _stroke([const Offset(250, 120), const Offset(450, 130)]);
    final away = _stroke([const Offset(150, 400), const Offset(250, 400)]);
    final erased = ScribbleErase.erasedBy(_stroke(_zigzag()), [
      covered,
      half,
      away,
    ]);
    expect(erased, [covered]);
    // Not a scribble: erases nothing.
    expect(
      ScribbleErase.erasedBy(_stroke(_zigzag(times: 2)), [covered]),
      isEmpty,
    );
  });

  testGoldens('in the editor, only when turned on, and undoable', (
    tester,
  ) async {
    setupMockPathProvider();
    setupMockPrinting();
    await tester.runAsync(FileManager.init);
    addTearDown(() => stows.scribbleToErase.value = false);

    await tester.pumpWidget(
      TranslationProvider(
        child: ScreenshotApp(
          device: GoldenScreenshotDevices.androidPhone.device,
          home: Editor(),
        ),
      ),
    );
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    // Let the new note finish loading.
    await tester.pumpAndSettle();
    List<Stroke> strokes() => state.coreInfo.pages.first.strokes;

    // Around the middle of the editor (which the device frame shows scaled
    // down), on the page.
    final center = tester.getCenter(find.byType(Editor));
    Offset onScreen(Offset point) =>
        center + (point - const Offset(200, 300)) / 2;
    Future<void> draw(List<Offset> points) async {
      // In small moves, like a real pen.
      points = [
        for (var i = 0; i < points.length; i++)
          if (i == 0)
            onScreen(points.first)
          else
            for (var t = 1; t <= 4; t++)
              onScreen(Offset.lerp(points[i - 1], points[i], t / 4)!),
      ];
      final gesture = await tester.startGesture(points.first);
      for (final point in points.skip(1)) {
        await gesture.moveTo(point);
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump();
    }

    await draw([const Offset(150, 300), const Offset(250, 310)]);
    expect(strokes(), hasLength(1));

    // Off: the scribble is just drawn.
    final scribble = _zigzag(top: 280, step: 6);
    await draw(scribble);
    expect(strokes(), hasLength(2));
    state.undo();
    await tester.pump();
    expect(strokes(), hasLength(1));

    stows.scribbleToErase.value = true;
    // Not with tape, which covers things up.
    state.currentTool = Tape.currentTape;
    await draw(scribble);
    expect(strokes(), hasLength(2));
    state.undo();
    await tester.pump();
    state.currentTool = Pen.currentPen;

    await draw(scribble);
    expect(strokes(), isEmpty);
    state.undo();
    await tester.pump();
    expect(strokes(), hasLength(1));
  });
}
