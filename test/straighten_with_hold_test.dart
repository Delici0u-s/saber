import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

/// "Auto straighten lines" used to turn a straight-looking stroke into a line
/// as soon as the pen was lifted, before "hold to shape" could wait for the
/// hold, preview the shape and form it on release. It now only applies when
/// hold to shape is off.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupMockPathProvider();
    setupMockPrinting();
    setupMockWindowManager();
    FlavorConfig.setup();
    await FileManager.init();
  });

  late int holdDelay;
  late bool straighten;
  setUp(() {
    holdDelay = stows.holdToShapeDelay.value;
    straighten = stows.autoStraightenLines.value;
  });
  tearDown(() {
    stows.holdToShapeDelay.value = holdDelay;
    stows.autoStraightenLines.value = straighten;
  });

  /// Draws a nearly straight stroke and lifts the pen straight away.
  Future<Stroke> drawQuickLine(WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(child: MaterialApp(home: Editor())),
    );
    final editor = tester.state<EditorState>(find.byType(Editor));
    addTearDown(editor.cancelAutosaveAndMarkSaved);
    final pen = Pen.currentPen;
    editor
      ..currentTool = pen
      ..dragPageIndex = 0;
    final page = editor.coreInfo.pages.first;
    pen.onDragStart(const Offset(100, 100), page, 0, null);
    for (var x = 104.0; x <= 400; x += 4) {
      pen.onDragUpdate(Offset(x, 100 + x * 0.05), null);
    }
    editor.onDrawEnd(ScaleEndDetails());
    await tester.pump();
    return page.strokes.last;
  }

  testWidgets('with hold to shape on, a quick stroke stays as drawn', (
    tester,
  ) async {
    stows.autoStraightenLines.value = true;
    stows.holdToShapeDelay.value = 1000;
    final stroke = await drawQuickLine(tester);
    expect(stroke.shape, isNull);
  });

  testWidgets('with hold to shape off, auto straighten still works', (
    tester,
  ) async {
    stows.autoStraightenLines.value = true;
    stows.holdToShapeDelay.value = -1;
    final stroke = await drawQuickLine(tester);
    expect(stroke.shape, isNotNull);
  });
}
