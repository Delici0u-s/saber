import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/opacity_picker.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();

  setUp(() {
    stows.lastFountainPenOpacity.value = 1;
    stows.lastPencilOpacity.value = 1;
  });

  /// The colour of a stroke drawn with [pen].
  Color strokeColor(Pen pen) {
    pen.onDragStart(const Offset(10, 10), EditorPage(), 0, null);
    pen.onDragUpdate(const Offset(50, 50), null);
    return pen.onDragEnd()!.color;
  }

  test('strokes are as opaque as their pen', () {
    final pen = Pen.fountainPen()..color = Colors.blue;
    expect(strokeColor(pen).a, 1);
    pen.opacity = 0.4;
    expect(strokeColor(pen).a, closeTo(0.4, 0.01));
    expect(
      strokeColor(pen).withValues(alpha: 1).toARGB32(),
      Colors.blue.toARGB32(),
    );
    // Remembered per pen.
    expect(Pen.fountainPen().opacity, 0.4);
    expect(Pencil().opacity, 1);
  });

  test('the highlighter keeps its own transparency', () {
    final highlighter = Highlighter();
    expect(highlighter.opacityStow, isNull);
    expect(strokeColor(highlighter).a, highlighter.color.a);
  });

  testWidgets('the slider sets the opacity in steps', (tester) async {
    final pen = Pen.fountainPen();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: OpacityPicker(axis: Axis.horizontal, pen: pen),
          ),
        ),
      ),
    );
    final slider = find.byType(CustomPaint).last;
    await tester.tapAt(tester.getTopLeft(slider) + const Offset(1, 5));
    expect(pen.opacity, closeTo(OpacityPicker.minOpacity, 1e-9));
    await tester.tapAt(tester.getCenter(slider));
    await tester.pump();
    expect(pen.opacity, closeTo(0.55, 1e-9));
    expect(find.text('55%'), findsOneWidget);
  });
}
