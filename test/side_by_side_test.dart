import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/editor/side_by_side.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  testGoldens('a second note side by side, written in on its own', (
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
          device: GoldenScreenshotDevices.flathub.device,
          home: Editor(),
        ),
      ),
    );
    final main = tester.state<EditorState>(find.byType(Editor));
    addTearDown(main.cancelAutosaveAndMarkSaved);
    await tester.pumpAndSettle();

    main.sideBySide.openNote('/side by side test');
    await tester.pumpAndSettle();
    expect(find.byType(SideBySidePane), findsOneWidget);
    final side = tester.state<EditorState>(find.byType(Editor).last);
    addTearDown(side.cancelAutosaveAndMarkSaved);
    expect(side, isNot(same(main)));
    // Let its note load.
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    Future<void> drawIn(EditorState editor, Offset offset) async {
      final page = editor.coreInfo.pages.first;
      final from = page.renderBox!.localToGlobal(const Offset(300, 300));
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(from + offset * (i / 10));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    int strokesIn(EditorState editor) =>
        editor.coreInfo.pages.first.strokes.length;

    // Read-only until writing is turned on.
    main.currentTool = Pen.currentPen;
    await drawIn(side, const Offset(60, 0));
    expect(strokesIn(side), 0);

    main.sideBySide.writable = true;
    await tester.pumpAndSettle();
    await drawIn(side, const Offset(60, 0));
    expect(strokesIn(side), 1);
    expect(strokesIn(main), 0);

    await drawIn(main, const Offset(60, 0));
    expect(strokesIn(main), 1);
    expect(strokesIn(side), 1);

    // Shortcuts go to the note last drawn in: the main one.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(strokesIn(main), 0);
    expect(strokesIn(side), 1);

    // A selection made in the second note is deleted there by the toolbar.
    main.currentTool = SelectBox.currentSelect;
    await tester.pumpAndSettle();
    final page = side.coreInfo.pages.first;
    final from = page.renderBox!.localToGlobal(const Offset(250, 250));
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(from + const Offset(80, 30) * (i / 10));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(SelectBox.currentSelect.selectResult.strokes, hasLength(1));
    await tester.tap(find.byTooltip(t.editor.selectionBar.delete));
    await tester.pumpAndSettle();
    expect(strokesIn(side), 0);

    main.sideBySide.close();
    await tester.pumpAndSettle();
    expect(find.byType(SideBySidePane), findsNothing);
  });
}
