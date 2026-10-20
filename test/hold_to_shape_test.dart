import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/line_style.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_pen.dart';

/// Points around a circle, ending where it started.
List<Offset> _circle({int steps = 64}) => [
  for (var i = 0; i <= steps; i++)
    const Offset(500, 500) + Offset.fromDirection(2 * pi * i / steps, 200),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup();
  final delay = Duration(milliseconds: stows.holdToShapeDelay.value);

  /// Draws [points] with [pen], then runs [afterDrawing], and ends the stroke.
  Stroke? draw(
    Pen pen,
    List<Offset> points, {
    required void Function(FakeAsync async) afterDrawing,
  }) {
    late Stroke? stroke;
    fakeAsync((async) {
      pen.onDragStart(points.first, EditorPage(), 0, null);
      for (final point in points.skip(1)) {
        pen.onDragUpdate(point, null);
      }
      afterDrawing(async);
      stroke = pen.onDragEnd();
    });
    return stroke;
  }

  group('hold to shape', () {
    setUp(() => stows.holdToShapeDelay.value = delay.inMilliseconds);
    tearDown(() => Pen.detectedShape = null);

    test('holding still at the end turns a circle into a shape', () {
      final stroke = draw(
        Pen.fountainPen(),
        _circle(),
        afterDrawing: (async) => async.elapse(delay * 2),
      );
      expect(stroke, isA<CircleStroke>());
    });

    test('a styled shape keeps its style, without changing the pen', () {
      final pen = Pen.fountainPen();
      final previousStyle = pen.lineStyle;
      addTearDown(() => pen.lineStyle = previousStyle);
      pen.lineStyle = .dotted;
      final taper = pen.options.start.taperEnabled;
      final stroke = draw(
        pen,
        _circle(),
        afterDrawing: (async) => async.elapse(delay * 2),
      )!;
      expect(stroke.lineStyle, LineStyle.dotted);
      expect(stroke.isInPieces, isTrue);
      expect(stroke.highQualityPieces.length, greaterThan(10));
      // Still round: every point on the circle the drawing was close to.
      for (final point in stroke.points) {
        expect((point - const Offset(500, 500)).distance, closeTo(200, 20));
      }
      expect(pen.options.start.taperEnabled, taper);
    });

    test('releasing before the delay keeps the drawn stroke', () {
      final stroke = draw(
        Pen.fountainPen(),
        _circle(),
        afterDrawing: (async) => async.elapse(delay ~/ 2),
      );
      expect(stroke, isNot(isA<CircleStroke>()));
    });

    test('jitter within the stroke width still counts as holding', () {
      final pen = Pen.fountainPen();
      final end = _circle().last;
      final stroke = draw(
        pen,
        _circle(),
        afterDrawing: (async) {
          for (var i = 0; i < 4; i++) {
            async.elapse(delay ~/ 4);
            pen.onDragUpdate(end + Offset(pen.options.size / 2, 0), null);
          }
          async.elapse(delay ~/ 4);
        },
      );
      expect(stroke, isA<CircleStroke>());
    });

    test('moving on after a shape was recognized cancels it', () {
      final pen = Pen.fountainPen();
      final stroke = draw(
        pen,
        _circle(),
        afterDrawing: (async) {
          async.elapse(delay * 2);
          expect(Pen.detectedShape, isNotNull);
          pen.onDragUpdate(_circle().last + const Offset(300, 300), null);
          expect(Pen.detectedShape, isNull);
        },
      );
      expect(stroke, isNot(isA<CircleStroke>()));
    });

    test('does nothing when disabled', () {
      stows.holdToShapeDelay.value = -1;
      final stroke = draw(
        Pen.fountainPen(),
        _circle(),
        afterDrawing: (async) => async.elapse(const Duration(hours: 1)),
      );
      expect(stroke, isNot(isA<CircleStroke>()));
    });
  });

  test('the shape pen still turns a circle into a shape on release', () {
    stows.holdToShapeDelay.value = -1;
    final stroke = draw(ShapePen(), _circle(), afterDrawing: (_) {});
    expect(stroke, isA<CircleStroke>());
  });
}
