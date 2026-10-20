import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/shape_placer.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/tool_id.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  group('samples', () {
    const start = Offset(100, 100), end = Offset(300, 200);
    final box = Rect.fromPoints(start, end);

    for (final sample in ShapeSample.values) {
      test('${sample.name} fits the dragged box', () {
        final shape = sample.build(start, end);
        for (final anchor in shape.anchors) {
          expect(box.inflate(1e-9).contains(anchor), isTrue, reason: '$anchor');
        }
      });
    }

    test('lines end where the drag does, arrows with heads', () {
      final line = ShapeSample.line.build(start, end) as PathShape;
      expect(line.anchors, [start, end]);
      expect((line.startHead, line.endHead), (false, false));
      final arrow = ShapeSample.arrow.build(start, end) as PathShape;
      expect((arrow.startHead, arrow.endHead), (false, true));
      final both = ShapeSample.doubleArrow.build(start, end) as PathShape;
      expect((both.startHead, both.endHead), (true, true));
    });

    test('proportional: square boxes, lines at 15° steps', () {
      final square = ShapeSample.rectangle.build(
        start,
        end,
        proportional: true,
      ) as PathShape;
      final bounds = Rect.fromPoints(square.anchors[0], square.anchors[2]);
      expect(bounds.width, bounds.height);
      final circle = ShapeSample.ellipse.build(
        start,
        end,
        proportional: true,
      ) as EllipseShape;
      expect(circle.u.distance, circle.v.distance);
      final line =
          ShapeSample.line.build(start, end, proportional: true) as PathShape;
      final angle = (line.anchors[1] - line.anchors[0]).direction;
      expect(
        (angle / (pi / 12) - (angle / (pi / 12)).round()).abs(),
        lessThan(1e-9),
      );
    });

    test('polygons and stars get their corners', () {
      for (final corners in [3, 6, 12]) {
        final polygon = ShapeSample.polygon.build(
          start,
          end,
          corners: corners,
        ) as PathShape;
        expect(polygon.points, hasLength(corners));
        expect(polygon.closed, isTrue);
        final star =
            ShapeSample.star.build(start, end, corners: corners) as PathShape;
        expect(star.points, hasLength(2 * corners));
      }
    });
  });

  testGoldens('placing shapes from the toolbar, with undo', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlavorConfig.setup();
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
      for (var t = 1; t <= 10; t++) {
        await gesture.moveTo(onScreen(Offset.lerp(from, to, t / 10)!));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // The Shapes button picks the placer and shows the shapes.
    await tester.tap(find.byTooltip(t.editor.toolbar.shapes).first);
    await tester.pumpAndSettle();
    expect(state.currentTool, same(ShapePlacer.currentPlacer));
    // Notes still open with the pen, not the shape pen.
    expect(stows.lastTool.value, isNot(ToolId.shapePen));
    await tester.tap(find.byTooltip(t.editor.shapes.ellipse));
    await tester.pumpAndSettle();
    expect(stows.lastShapeSample.value, ShapeSample.ellipse.name);

    await drag(const Offset(200, 200), const Offset(500, 400));
    final ellipse = page.strokes.single.shape! as EllipseShape;
    expect(ellipse.center.dx, closeTo(350, 1e-6));
    expect(ellipse.center.dy, closeTo(300, 1e-6));

    // Another shape; a tap places nothing.
    await tester.tap(find.byTooltip(t.editor.shapes.arrow));
    await tester.pumpAndSettle();
    await drag(const Offset(200, 450), const Offset(600, 480));
    expect(page.strokes, hasLength(2));
    expect((page.strokes.last.shape! as PathShape).endHead, isTrue);
    await tester.tapAt(onScreen(const Offset(700, 150)));
    await tester.pumpAndSettle();
    expect(page.strokes, hasLength(2));

    state.undo();
    await tester.pump();
    expect(page.strokes, hasLength(1));
  });
}
