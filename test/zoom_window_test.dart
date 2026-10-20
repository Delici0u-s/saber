import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/zoom_window.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();
  const pageSize = Size(1000, 1400);
  const lineHeight = 40.0;

  ZoomWindow shown({Rect onScreen = const Rect.fromLTWH(100, 210, 800, 600)}) =>
      ZoomWindow()
        ..setAspect(4)
        ..show(
          pageIndex: 0,
          pageSize: pageSize,
          onScreen: onScreen,
          lineHeight: lineHeight,
        );

  group('the box', () {
    test('starts at the top left of the screen, on a line', () {
      final zoom = shown();
      expect(zoom.visible, isTrue);
      expect(zoom.rect.topLeft, const Offset(100, 200));
      expect(zoom.rect.width, pageSize.width * ZoomWindow.startWidthFraction);
      expect(zoom.rect.width / zoom.rect.height, closeTo(4, 1e-9));
    });

    test('takes the panel\'s proportions', () {
      final zoom = shown()..setAspect(2);
      expect(zoom.rect.width / zoom.rect.height, closeTo(2, 1e-9));
    });

    test('moves on along the line, then to the next line', () {
      final zoom = shown();
      final start = zoom.rect;
      zoom.forward(lineHeight);
      expect(
        zoom.rect.left - start.left,
        closeTo(start.width * (1 - ZoomWindow.marginFraction), 1e-9),
      );
      zoom.back();
      expect(zoom.rect, start);
      // To the page's right edge, then the next line from where it started.
      for (var i = 0; i < 10 && zoom.rect.top == start.top; i++) {
        zoom.forward(lineHeight);
      }
      expect(zoom.rect.left, start.left);
      expect(zoom.rect.top, greaterThan(start.top));
      expect((zoom.rect.top - start.top) % lineHeight, closeTo(0, 1e-9));
    });

    test('a new line starts where the box was last put by hand', () {
      final zoom = shown()..moveBy(const Offset(50, 0));
      final left = zoom.rect.left;
      zoom
        ..forward(lineHeight)
        ..newLine(lineHeight);
      expect(zoom.rect.left, left);
    });

    test('stays on the page and is never too small', () {
      final zoom = shown()
        ..moveBy(const Offset(5000, 5000))
        ..resizeBy(-5000);
      expect(zoom.rect.right, lessThanOrEqualTo(pageSize.width));
      expect(zoom.rect.bottom, lessThanOrEqualTo(pageSize.height));
      expect(
        zoom.rect.width,
        closeTo(pageSize.width * ZoomWindow.minWidthFraction, 1e-9),
      );
      zoom.resizeBy(5000);
      expect(zoom.rect.width, pageSize.width);
    });

    test('the margin is the right of the panel', () {
      expect(ZoomWindow.isInMargin(0.5), isFalse);
      expect(ZoomWindow.isInMargin(1 - ZoomWindow.marginFraction / 2), isTrue);
    });
  });

  testGoldens('writing in the panel draws on the page, small', (tester) async {
    setupMockPathProvider();
    setupMockPrinting();
    await tester.runAsync(FileManager.init);
    stows.zoomWindowAutoAdvance.value = true;
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

    await tester.tap(find.byTooltip(t.editor.zoomWindow.title));
    await tester.pumpAndSettle();
    final zoom = state.zoomWindow;
    expect(zoom.visible, isTrue);
    final panel = find.byType(ZoomWindowPanel);
    expect(panel, findsOneWidget);

    // A stroke across the middle of the view, ending before the margin.
    final view = tester.getRect(
      find.descendant(of: panel, matching: find.byType(ClipRect)),
    );
    Future<void> write(double from, double to) async {
      final gesture = await tester.startGesture(
        view.centerLeft + Offset(view.width * from, 0),
      );
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(
          view.centerLeft +
              Offset(view.width * (from + (to - from) * i / 10), 0),
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    final box = zoom.rect;
    await write(0.1, 0.5);
    final strokes = state.coreInfo.pages[zoom.pageIndex].strokes;
    expect(strokes, hasLength(1));
    final bounds = strokes.single.lowQualityPath.getBounds();
    expect(box.inflate(10).contains(bounds.center), isTrue);
    // Small on the page: as wide as the box's middle 40%.
    expect(bounds.width, closeTo(box.width * 0.4, box.width * 0.1));
    expect(zoom.rect, box);

    // Ending in the margin moves the box on.
    await write(0.6, 0.95);
    expect(zoom.rect.left, greaterThan(box.left));

    state.undo();
    await tester.pump();
    expect(state.coreInfo.pages[zoom.pageIndex].strokes, hasLength(1));

    // The handle moves the box.
    final before = zoom.rect;
    await tester.drag(find.byIcon(Icons.open_with), const Offset(30, 40));
    await tester.pumpAndSettle();
    expect(zoom.rect.left, greaterThan(before.left));
    expect(zoom.rect.top, greaterThan(before.top));

    // Going down the page, the view follows the box.
    final page = state.coreInfo.pages[zoom.pageIndex];
    final canvas = tester.getRect(find.byType(CanvasGestureDetector));
    for (var i = 0; i < 25; i++) {
      zoom.newLine(state.coreInfo.lineHeight.toDouble());
      await tester.pumpAndSettle();
    }
    final onScreen = page.renderBox!.localToGlobal(zoom.rect.center);
    expect(canvas.contains(onScreen), isTrue);
    // Scrolling showed the HUD, which hides itself after a while.
    await tester.pump(const Duration(minutes: 1));
  });
}
