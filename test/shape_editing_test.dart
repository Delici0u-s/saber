import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  testGoldens('reshaping a selected shape by its handles, with undo', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlavorConfig.setup();
    setupMockPathProvider();
    setupMockPrinting();
    await tester.runAsync(FileManager.init);

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
    await tester.pumpAndSettle();

    final page = state.coreInfo.pages.first;
    List<Stroke> strokes() => state.coreInfo.pages.first.strokes;
    Offset onScreen(Offset onPage) => page.renderBox!.localToGlobal(onPage);
    Future<void> drag(Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      for (var t = 1; t <= 10; t++) {
        await gesture.moveTo(Offset.lerp(from, to, t / 10)!);
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // A square, and a line whose end a corner can snap to.
    Stroke shaped(StrokeShape shape) => Pen.shapeStroke(
      Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .fountainPen,
      ),
      shape,
    );
    final square = PathShape.polygon(const [
      Offset(300, 300),
      Offset(500, 300),
      Offset(500, 500),
      Offset(300, 500),
    ]);
    const lineEnd = Offset(620, 640);
    final original = shaped(square);
    page.insertStroke(shaped(PathShape.line(const Offset(800, 800), lineEnd)));
    page.insertStroke(original);
    await tester.pump();

    // Tapping the square's side selects it (not the line).
    state.currentTool = SelectBox.currentSelect;
    await tester.tapAt(onScreen(const Offset(400, 501)));
    await tester.pumpAndSettle();
    final select = SelectBox.currentSelect;
    expect(select.doneSelecting, isTrue);
    expect(select.selectResult.strokes, [original]);
    PathShape shape() => select.selectResult.shape! as PathShape;
    expect(strokes().last.shape, square);

    // A corner follows the pen, wherever on it it was grabbed, and snaps
    // onto the line's end nearby.
    const grabbedAt = Offset(5, 4);
    await drag(
      onScreen(const Offset(500, 500) + grabbedAt),
      onScreen(lineEnd + grabbedAt + const Offset(3, -2)),
    );
    expect(shape().anchors[2], lineEnd);
    expect(strokes().last, isNot(same(original)));
    // The box fits the new shape.
    expect(select.selectResult.box!.rect.contains(lineEnd), isTrue);

    // Dragging the middle of the top side bends it through a new anchor.
    final middle = shape().middles.first;
    await drag(onScreen(middle), onScreen(middle + const Offset(0, -120)));
    expect(shape().points, hasLength(5));
    expect(shape().points[1].smooth, isTrue);

    // Tapping a corner offers its actions, also if the pen wobbles a bit;
    // deleting it leaves four.
    final tap = await tester.startGesture(
      onScreen(shape().anchors[0]),
      kind: PointerDeviceKind.stylus,
    );
    await tap.moveBy(const Offset(2, 1));
    await tester.pump(const Duration(milliseconds: 8));
    await tap.moveBy(const Offset(-1, 2));
    await tester.pump(const Duration(milliseconds: 8));
    await tap.up();
    await tester.pumpAndSettle();
    // The stylus turned finger drawing off, which the rest uses.
    stows.editorFingerDrawing.value = true;
    expect(find.text(t.editor.shapes.smooth), findsOneWidget);
    expect(shape().points, hasLength(5));
    await tester.tap(find.text(t.editor.shapes.deletePoint));
    await tester.pumpAndSettle();
    expect(shape().points, hasLength(4));

    // A smooth anchor offers to become a corner again.
    final smooth = shape().points.indexWhere((anchor) => anchor.smooth);
    await tester.tapAt(onScreen(shape().anchors[smooth]));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.editor.shapes.corner));
    await tester.pumpAndSettle();
    expect(shape().points.any((anchor) => anchor.smooth), isFalse);

    // Each was one step: undo them all and the square is back.
    for (var i = 0; i < 4; i++) {
      state.undo();
      await tester.pump();
    }
    expect(strokes().last, same(original));

    // Grabbing an anchor without moving changes nothing.
    state.currentTool = SelectBox.currentSelect;
    await drag(
      onScreen(const Offset(250, 250)),
      onScreen(const Offset(550, 550)),
    );
    await drag(
      onScreen(const Offset(300, 300)),
      onScreen(const Offset(300, 300)),
    );
    expect(strokes().last, same(original));
    // Wait, so the next taps aren't a double tap with it (see
    // [Stows.doubleTapToErase]).
    await tester.pumpAndSettle(kDoubleTapTimeout * 2);

    // Tapping inside the selection keeps it; tapping nothing unselects.
    await tester.tapAt(onScreen(const Offset(400, 400)));
    await tester.pumpAndSettle(kDoubleTapTimeout * 2);
    expect(select.doneSelecting, isTrue);
    await tester.tapAt(onScreen(const Offset(150, 1000)));
    await tester.pumpAndSettle();
    expect(select.doneSelecting, isFalse);
  });
}
