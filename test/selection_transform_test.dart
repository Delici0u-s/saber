import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/editor/selection_transform.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:sbn/has_size.dart';

const _page = HasSize(Size(1000, 1400));

Stroke _line({double size = 4}) =>
    Stroke(
        color: Colors.black,
        pressureEnabled: true,
        options: StrokeOptions(size: size, isComplete: true),
        pageIndex: 0,
        page: _page,
        toolId: .fountainPen,
      )
      ..addPoint(const Offset(100, 100), 0.2)
      ..addPoint(const Offset(200, 150), 0.8);

Matcher _near(Offset expected) => isA<Offset>().having(
  (offset) => (offset - expected).distance,
  'distance from $expected',
  closeTo(0, 1e-6),
);

void main() {
  FlavorConfig.setup();
  const rect = Rect.fromLTWH(100, 100, 200, 100);
  const box = SelectionBox(rect: rect, pixel: 0.5);

  group('dragging a handle', () {
    test('a corner resizes keeping proportions, the opposite one stays', () {
      final transform = box.drag(
        .bottomRight,
        rect.bottomRight,
        rect.bottomRight + const Offset(200, 0),
      );
      expect(transform.scaleX, transform.scaleY);
      expect(transform.map(rect.topLeft), _near(rect.topLeft));
      // Projected onto the diagonal: (200, 0) along (200, 100) is 0.8 of it.
      expect(transform.scaleX, closeTo(1.8, 1e-9));
    });

    test('a side stretches one way only', () {
      final transform = box.drag(
        .left,
        rect.centerLeft,
        rect.centerLeft - const Offset(100, 30),
      );
      expect(transform.scaleX, closeTo(1.5, 1e-9));
      expect(transform.scaleY, 1);
      expect(transform.map(rect.centerRight), _near(rect.centerRight));
    });

    test('never smaller than the minimum or flipped', () {
      final transform = box.drag(
        .right,
        rect.centerRight,
        rect.centerLeft - const Offset(500, 0),
      );
      expect(
        transform.scaleX * rect.width,
        closeTo(SelectionBox.minSize * box.pixel, 1e-9),
      );
    });

    test('rotating snaps to 15° and turns around the middle', () {
      final start = box.handlePosition(.rotate);
      final center = rect.center;
      final turned =
          center +
          Offset.fromDirection(
            (start - center).direction + 44.5 * pi / 180,
            (start - center).distance,
          );
      final transform = box.drag(.rotate, start, turned);
      expect(transform.rotation, closeTo(45 * pi / 180, 1e-9));
      expect(transform.map(center), _near(center));
    });

    test('handles are found near where they are drawn', () {
      expect(
        box.handleAt(rect.topLeft + const Offset(3, 3)),
        SelectionHandle.topLeft,
      );
      expect(box.handleAt(rect.center), isNull);
      const noRotate = SelectionBox(rect: rect, pixel: 0.5, rotatable: false);
      expect(noRotate.handleAt(box.handlePosition(.rotate)), isNull);
    });
  });

  group('transforming', () {
    const transform = SelectionTransform(
      origin: Offset(50, 60),
      scaleX: 2,
      scaleY: 0.5,
      rotation: pi / 6,
    );

    test('the matrix matches map', () {
      for (final point in const [Offset.zero, Offset(130, -20)]) {
        final path = Path()
          ..moveTo(point.dx, point.dy)
          ..lineTo(point.dx, point.dy);
        final moved = path.transform(transform.matrix).getBounds().topLeft;
        // Paths keep 32-bit floats.
        expect((moved - transform.map(point)).distance, lessThan(1e-3));
      }
    });

    test('strokes keep their pressure and scale their width', () {
      final line = _line();
      final moved = const SelectionTransform(
        origin: Offset(100, 100),
        scaleX: 2,
        scaleY: 2,
      ).apply(line);
      expect(moved.options.size, 8);
      expect(moved.pointVectors.map((p) => p.pressure), [0.2, 0.8]);
      expect(moved.pointVectors.last, _near(const Offset(300, 200)));
      // The original is untouched.
      expect(line.options.size, 4);
      expect(line.pointVectors.last, _near(const Offset(200, 150)));
    });

    test('shapes stay shapes, also rotated or stretched', () {
      final rectangle = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        rect: rect,
      );
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        center: const Offset(100, 100),
        radius: 50,
      );
      const stretch = SelectionTransform(scaleX: 2);
      const turn = SelectionTransform(rotation: 0.3);
      for (final transform in [stretch, turn]) {
        expect((transform.apply(rectangle).shape! as PathShape).anchors, [
          for (final corner in [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ])
            _near(transform.map(corner)),
        ]);
      }
      final stretched = stretch.apply(circle).shape! as EllipseShape;
      expect(stretched.center, _near(stretch.map(const Offset(100, 100))));
      expect(stretched.u.distance, closeTo(100, 1e-9));
      expect(stretched.v.distance, closeTo(50, 1e-9));
      final turned = turn.apply(circle).shape! as EllipseShape;
      expect(turned.u.distance, closeTo(50, 1e-9));
      expect(turned.v.distance, closeTo(50, 1e-9));
    });

    test('a thickness change only scales widths', () {
      const thicker = SelectionTransform(widthScale: 1.5);
      final moved = thicker.apply(_line());
      expect(moved.options.size, 6);
      expect(moved.pointVectors.last, _near(const Offset(200, 150)));
      expect(thicker.isIdentity, isFalse);
      expect(SelectionTransform.identity.isIdentity, isTrue);
    });
  });
}
