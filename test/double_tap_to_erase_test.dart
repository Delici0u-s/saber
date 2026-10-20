import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/double_tap_to_erase.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  test('which input double-tapping accepts', () {
    expect(DoubleTapToErase.finger.accepts(.touch), isTrue);
    expect(DoubleTapToErase.finger.accepts(.stylus), isFalse);
    expect(DoubleTapToErase.pen.accepts(.stylus), isTrue);
    expect(DoubleTapToErase.both.accepts(.invertedStylus), isTrue);
    expect(DoubleTapToErase.off.accepts(.touch), isFalse);
    expect(DoubleTapToErase.finger.accepts(.mouse), isTrue);
    expect(DoubleTapToErase.pen.accepts(.mouse), isFalse);
    expect(DoubleTapToErase.fromJson('nonsense'), DoubleTapToErase.finger);
  });

  testGoldens('double-tapping switches to the eraser and takes back its dots', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlavorConfig.setup();
    setupMockPathProvider();
    setupMockPrinting();
    await tester.runAsync(FileManager.init);
    stows.editorFingerDrawing.value = true;
    addTearDown(
      () => stows.doubleTapToErase.value = DoubleTapToErase.finger.name,
    );

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
    state.currentTool = Pen.currentPen;
    final page = state.coreInfo.pages.first;
    final spot = page.renderBox!.localToGlobal(const Offset(300, 300));
    int dots() => state.coreInfo.pages.first.strokes.length;

    var clock = Duration.zero;
    Future<void> tap({
      PointerDeviceKind kind = .touch,
      Duration after = const Duration(milliseconds: 100),
      Offset shift = Offset.zero,
    }) async {
      clock += after;
      final gesture = await tester.createGesture(kind: kind);
      await gesture.down(spot + shift, timeStamp: clock);
      clock += const Duration(milliseconds: 30);
      await gesture.up(timeStamp: clock);
      await tester.pump(const Duration(milliseconds: 50));
    }

    // An earlier dot stays.
    await tap();
    expect(dots(), 1);

    await tap(after: const Duration(seconds: 2));
    await tap();
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Eraser>());
    expect(dots(), 1, reason: 'only the double tap\'s dots go');

    await tap(after: const Duration(seconds: 2));
    await tap();
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());

    // Switching back with the eraser didn't erase the dot under the taps.
    expect(dots(), 1);

    // Slow taps aren't a double tap.
    await tap(after: const Duration(seconds: 2));
    await tap(after: const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());
    expect(dots(), 3);

    // The pen doesn't, by default.
    await tap(kind: .stylus, after: const Duration(seconds: 2));
    await tap(kind: .stylus);
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());

    // Fingers may land a bit apart; a pen may not (its taps are dots).
    await tap(after: const Duration(seconds: 2));
    await tap(shift: const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Eraser>());
    await tap(after: const Duration(seconds: 2));
    await tap();
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());
    stows.doubleTapToErase.value = DoubleTapToErase.pen.name;
    await tap(kind: .stylus, after: const Duration(seconds: 2));
    await tap(kind: .stylus, shift: const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());
    stows.doubleTapToErase.value = DoubleTapToErase.finger.name;

    // A mouse double click, e.g. on a PC.
    await tap(kind: .mouse, after: const Duration(seconds: 2));
    await tap(kind: .mouse);
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Eraser>());
    await tap(kind: .mouse, after: const Duration(seconds: 2));
    await tap(kind: .mouse);
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());

    // Nor does anything when it's off.
    stows.doubleTapToErase.value = DoubleTapToErase.off.name;
    await tap(after: const Duration(seconds: 2));
    await tap();
    await tester.pumpAndSettle();
    expect(state.currentTool, isA<Pen>());
  });
}
