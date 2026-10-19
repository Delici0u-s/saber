import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/ruler.dart';
import 'package:saber/components/toolbar/ruler_modal.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();

  late Ruler ruler;
  var hidden = false;

  Future<void> pumpModal(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RulerModal(ruler: ruler, hide: () => hidden = true),
      ),
    ),
  );

  setUp(() {
    stows.lastRulerShape.value = RulerShape.ruler.name;
    stows.rulerMarkSpacingMm.value = 1;
    ruler = Ruler()..visible = true;
    hidden = false;
  });

  testWidgets('picks a shape', (tester) async {
    await pumpModal(tester);
    final shapes = t.editor.rulerOptions.shapes;
    for (final (tooltip, shape) in [
      (shapes.setSquare, RulerShape.setSquare),
      (shapes.trySquare, RulerShape.trySquare),
      (shapes.ruler, RulerShape.ruler),
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      expect(ruler.shape, shape);
      expect(stows.lastRulerShape.value, shape.name);
    }
  });

  testWidgets('sets the mark spacing, ignoring invalid input', (tester) async {
    await pumpModal(tester);
    final field = find.byType(TextField);
    expect(find.text('1'), findsOneWidget);

    await tester.enterText(field, '2,5');
    expect(stows.rulerMarkSpacingMm.value, 2.5);
    await tester.enterText(field, '0');
    expect(stows.rulerMarkSpacingMm.value, 2.5);
    await tester.enterText(field, '');
    expect(stows.rulerMarkSpacingMm.value, 2.5);
    await tester.enterText(field, '12.75');
    expect(stows.rulerMarkSpacingMm.value, 12.75);
  });

  testWidgets('hides the ruler', (tester) async {
    await pumpModal(tester);
    await tester.tap(find.byTooltip(t.editor.rulerOptions.hide));
    expect(hidden, isTrue);
  });
}
