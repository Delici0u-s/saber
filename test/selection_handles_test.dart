import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/selection_transform.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  testGoldens('resizing, rotating and thickening a selection, with undo', (
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

    // A line on the page, then a box selection around it.
    await drag(
      onScreen(const Offset(300, 400)),
      onScreen(const Offset(600, 400)),
    );
    expect(strokes(), hasLength(1));
    final original = strokes().single;
    final originalBounds = original.lowQualityPath.getBounds();

    state.currentTool = SelectBox.currentSelect;
    await drag(
      onScreen(const Offset(250, 300)),
      onScreen(const Offset(650, 500)),
    );
    final select = SelectBox.currentSelect;
    SelectionBox box() => select.selectResult.box!;
    expect(select.selectResult.strokes, [original]);

    // A corner: bigger, keeping proportions.
    final corner = box().handlePosition(.bottomRight);
    await drag(onScreen(corner), onScreen(corner + const Offset(150, 0)));
    final resized = strokes().single;
    expect(resized, isNot(same(original)));
    final resizedBounds = resized.lowQualityPath.getBounds();
    expect(resizedBounds.width, greaterThan(originalBounds.width * 1.3));
    expect(resized.options.size, greaterThan(original.options.size));
    expect(box().rect.contains(resizedBounds.topLeft), isTrue);
    expect(box().rect.contains(resizedBounds.bottomRight), isTrue);

    // Rotating a quarter turn makes the line stand up.
    final rotateHandle = box().handlePosition(.rotate);
    final center = box().rect.center;
    final quarterTurn =
        center +
        Offset(-(rotateHandle - center).dy, (rotateHandle - center).dx);
    await drag(onScreen(rotateHandle), onScreen(quarterTurn));
    final rotatedBounds = strokes().single.lowQualityPath.getBounds();
    expect(rotatedBounds.height, greaterThan(rotatedBounds.width * 3));

    // The thickness slider.
    final sizeBefore = strokes().single.options.size;
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(strokes().single.options.size, greaterThan(sizeBefore));

    // Each was one step: undo them all and the original is back.
    for (var i = 0; i < 3; i++) {
      state.undo();
      await tester.pump();
    }
    expect(strokes().single, same(original));

    // Grabbing a handle without moving changes nothing.
    state.currentTool = SelectBox.currentSelect;
    await drag(
      onScreen(const Offset(250, 300)),
      onScreen(const Offset(650, 500)),
    );
    final still = box().handlePosition(.topLeft);
    await drag(onScreen(still), onScreen(still));
    expect(strokes().single, same(original));
  });
}
