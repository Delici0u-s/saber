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
import 'package:saber/data/tools/select_lasso.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

/// Tapping a selected shape's corner opens its menu after reshaping it, with
/// each way of pointing: also a finger while finger drawing is off, whose
/// taps don't start a drawing gesture.
void main() {
  for (final (device, dragKind, tapKind, fingerDrawing) in [
    (
      GoldenScreenshotDevices.flathub,
      PointerDeviceKind.mouse,
      PointerDeviceKind.mouse,
      true,
    ),
    (
      GoldenScreenshotDevices.androidPhone,
      PointerDeviceKind.stylus,
      PointerDeviceKind.stylus,
      false,
    ),
    (
      GoldenScreenshotDevices.androidPhone,
      PointerDeviceKind.stylus,
      PointerDeviceKind.touch,
      false,
    ),
    (
      GoldenScreenshotDevices.androidPhone,
      PointerDeviceKind.touch,
      PointerDeviceKind.touch,
      true,
    ),
  ]) {
    testGoldens('dragging with $dragKind, then tapping with $tapKind '
        '(finger drawing ${fingerDrawing ? 'on' : 'off'})', (tester) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlavorConfig.setup();
      setupMockPathProvider();
      setupMockPrinting();
      await tester.runAsync(FileManager.init);
      await tester.pumpWidget(
        TranslationProvider(
          child: ScreenshotApp(device: device.device, home: Editor()),
        ),
      );
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);
      await tester.pumpAndSettle();
      stows.editorFingerDrawing.value = fingerDrawing;

      final page = state.coreInfo.pages.first;
      Offset onScreen(Offset onPage) => page.renderBox!.localToGlobal(onPage);
      page.insertStroke(
        Pen.shapeStroke(
          Stroke(
            color: Colors.black,
            pressureEnabled: true,
            options: StrokeOptions(size: 4),
            pageIndex: 0,
            page: page,
            toolId: .fountainPen,
          ),
          PathShape.polygon(const [
            Offset(300, 300),
            Offset(500, 300),
            Offset(500, 500),
            Offset(300, 500),
          ]),
        ),
      );
      await tester.pump();

      Future<void> tap(Offset position, PointerDeviceKind kind) async {
        final gesture = await tester.startGesture(position, kind: kind);
        await tester.pump(const Duration(milliseconds: 80));
        await gesture.up();
        await tester.pumpAndSettle();
      }

      state.currentTool = SelectLasso.currentSelect;
      await tap(onScreen(const Offset(400, 300)), dragKind);
      final select = SelectLasso.currentSelect;
      expect(select.selectResult.shape, isNotNull);

      final from = onScreen(const Offset(500, 500));
      final to = onScreen(const Offset(560, 600));
      final drag = await tester.startGesture(from, kind: dragKind);
      for (var t = 1; t <= 10; t++) {
        await drag.moveTo(Offset.lerp(from, to, t / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pumpAndSettle(kDoubleTapTimeout * 2);
      expect(
        select.selectResult.shape!.anchors[2],
        isNot(const Offset(500, 500)),
      );

      await tap(onScreen(const Offset(300, 300)), tapKind);
      expect(find.text(t.editor.shapes.deletePoint), findsOneWidget);
    });
  }
}
