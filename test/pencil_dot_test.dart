import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/pen.dart';

Stroke _pencilStroke(List<(Offset, double)> points) {
  final stroke = Stroke(
    color: Colors.black,
    pressureEnabled: true,
    options: Pen.pencilOptions,
    pageIndex: 0,
    page: EditorPage(),
    toolId: .pencil,
  );
  for (final (point, pressure) in points) {
    stroke.addPoint(point, pressure);
  }
  stroke.options.isComplete = true;
  return stroke;
}

void main() {
  group('pencil dots', () {
    // The narrowest a stroke can be (at zero pressure), as a radius.
    final options = Pen.pencilOptions;
    final minRadius = options.size * (1 - options.thinning) / 2;
    const center = Offset(100, 100);

    final taps = {
      'one point': [(center, 0.5)],
      'stationary points': [(center, 0.7), (center, 0.3), (center, 0.1)],
      'jitter within the stroke width': [
        (center, 0.5),
        (center + Offset(options.size / 2, 0), 0.5),
        (center + Offset(0, options.size / 2), 0.5),
      ],
    };
    for (final MapEntry(key: name, value: points) in taps.entries) {
      test('$name draws a visible dot', () {
        final stroke = _pencilStroke(points);
        expect(stroke.isDot, true);
        final bounds = stroke.highQualityPath.getBounds();
        expect(bounds.width, greaterThanOrEqualTo(minRadius));
        expect(bounds.height, greaterThanOrEqualTo(minRadius));
      });
    }

    test('a line is not a dot and stays tapered', () {
      final stroke = _pencilStroke([
        for (var x = 0.0; x <= 200; x += 10) (Offset(x, 100), 0.5),
      ]);
      expect(stroke.isDot, false);
      expect(stroke.options.start.taperEnabled, true);
    });
  });
}
