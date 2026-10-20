import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  Future<EditorState> pumpEditor(WidgetTester tester, double width) async {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/toolbarNarrow/${FileManager.appRootDirectoryPrefix}';
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    // A frame to measure the toolbar's buttons, and one to use it.
    await tester.pumpAndSettle();
    return state;
  }

  for (final width in const [360.0, 700.0, 1400.0]) {
    testWidgets('the pen options fit a ${width}px wide screen', (tester) async {
      await pumpEditor(tester, width);
      // The selected pen's button opens its options.
      await tester.tap(find.byTooltip(t.editor.pens.fountainPen));
      await tester.pumpAndSettle();
      expect(find.text(t.editor.penOptions.opacity), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a wide toolbar shows every group inline', (tester) async {
    await pumpEditor(tester, 1400);
    expect(find.byTooltip(t.editor.toolbar.insert), findsNothing);
    expect(find.byTooltip(t.editor.toolbar.tools), findsNothing);
    for (final name in [
      t.editor.toolbar.photo,
      t.editor.toolbar.ruler,
      t.editor.zoomWindow.title,
      t.editor.pens.laserPointer,
    ]) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('a narrow toolbar opens its groups as named buttons', (
    tester,
  ) async {
    await pumpEditor(tester, 360);
    expect(find.byTooltip(t.editor.toolbar.ruler), findsNothing);
    for (final (group, names) in [
      (
        t.editor.toolbar.insert,
        [t.editor.toolbar.photo, t.editor.toolbar.text],
      ),
      (
        t.editor.toolbar.tools,
        [
          t.editor.toolbar.ruler,
          t.editor.zoomWindow.title,
          t.editor.pens.laserPointer,
        ],
      ),
    ]) {
      await tester.tap(find.byTooltip(group));
      await tester.pumpAndSettle();
      for (final name in names) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    }
    // Opening the ruler from Tools shows it and its options.
    await tester.tap(find.text(t.editor.toolbar.ruler));
    await tester.pumpAndSettle();
    expect(find.text(t.editor.rulerOptions.angleUnits.degrees), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
