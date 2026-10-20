import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/editor/shape_handles.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/line_style.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:sbn/has_size.dart';

const _page = HasSize(Size(1000, 1400));

Stroke _stroke({double size = 4, LineStyle lineStyle = .solid}) => Stroke(
  color: Colors.blue,
  pressureEnabled: true,
  options: StrokeOptions(size: size),
  pageIndex: 0,
  page: _page,
  toolId: .fountainPen,
  lineStyle: lineStyle,
);

Stroke _shaped(StrokeShape shape, {LineStyle lineStyle = .solid}) =>
    Pen.shapeStroke(_stroke(lineStyle: lineStyle), shape);

/// Saves and loads [stroke] (as a note of the current version does).
Stroke _reload(Stroke stroke, {String? shapeName}) {
  final json = stroke.toJson();
  if (shapeName != null) json['shape'] = shapeName;
  return Stroke.fromJson(json, fileVersion: 19, pageIndex: 0, page: _page);
}

Matcher _near(Offset expected, [double tolerance = 1e-6]) =>
    isA<Offset>().having(
      (offset) => (offset - expected).distance,
      'distance from $expected',
      closeTo(0, tolerance),
    );

final _square = PathShape.polygon(const [
  Offset(100, 100),
  Offset(200, 100),
  Offset(200, 200),
  Offset(100, 200),
]);

void main() {
  FlavorConfig.setup();

  group('saving', () {
    final shapes = <String, StrokeShape>{
      'a polygon': _square,
      'a line with arrow heads': const PathShape(
        [ShapeAnchor(Offset(10, 20)), ShapeAnchor(Offset(300, 40))],
        startHead: true,
        endHead: true,
      ),
      'a curve': const PathShape([
        ShapeAnchor(Offset.zero),
        ShapeAnchor(Offset(50, 80), smooth: true),
        ShapeAnchor(Offset(100, 0), smooth: true),
        ShapeAnchor(Offset(150, 60)),
      ]),
      'an ellipse': const EllipseShape(
        center: Offset(300, 300),
        u: Offset(80, 10),
        v: Offset(-5, 40),
      ),
    };
    for (final MapEntry(key: name, value: shape) in shapes.entries) {
      test('$name keeps its shape and points', () {
        final stroke = _shaped(shape, lineStyle: .dashed);
        final loaded = _reload(stroke);
        expect(loaded.shape, shape);
        expect(loaded.lineStyle, LineStyle.dashed);
        expect(loaded.pointVectors.length, stroke.pointVectors.length);
      });

      test('$name opens as a plain stroke where the shape is unknown', () {
        final stroke = _shaped(shape);
        final loaded = _reload(stroke, shapeName: 'a shape from the future');
        expect(loaded.shape, isNull);
        expect(loaded, isNot(isA<RectangleStroke>()));
        expect(
          loaded.pointVectors.map((p) => Offset(p.x, p.y)),
          // Saved as 32-bit floats.
          [for (final p in stroke.pointVectors) _near(p, 1e-3)],
        );
      });
    }

    test('an ordinary stroke has no shape', () {
      final stroke = _stroke()
        ..addPoint(const Offset(1, 2))
        ..addPoint(const Offset(3, 4));
      expect(_reload(stroke).shape, isNull);
    });
  });

  group('a shaped stroke', () {
    test('goes along its shape, ending where it starts if closed', () {
      final stroke = _shaped(_square);
      final points = [for (final p in stroke.pointVectors) Offset(p.x, p.y)];
      expect(points, containsAllInOrder(_square.anchors));
      expect(points.first, points.last);
      // Close together, for an even width.
      for (var i = 1; i < points.length; i++) {
        expect(
          (points[i] - points[i - 1]).distance,
          lessThanOrEqualTo(stroke.options.size + 1e-9),
        );
      }
      // Along the square's sides only.
      for (final point in points) {
        final onSide =
            point.dx == 100 ||
            point.dx == 200 ||
            point.dy == 100 ||
            point.dy == 200;
        expect(onSide, isTrue, reason: '$point');
      }
    });

    test('has an even width and no tapers', () {
      final pen = _stroke();
      final stroke = Pen.shapeStroke(pen, _square);
      expect(stroke.pressureEnabled, isFalse);
      expect(stroke.options.start.taperEnabled, isFalse);
      expect(stroke.options.end.taperEnabled, isFalse);
      // The pen's options are untouched.
      expect(identical(stroke.options.start, pen.options.start), isFalse);
    });

    test('moves its shape with it, and copies keep it', () {
      final stroke = _shaped(_square)..shift(const Offset(10, 5));
      expect(stroke.shape!.anchors.first, const Offset(110, 105));
      expect(stroke.copy().shape, stroke.shape);
    });

    test('becomes an ordinary stroke when its points change', () {
      // E.g. the area eraser cutting it.
      final stroke = _shaped(_square)
        ..replacePoints([PointVector.zero, const PointVector(5, 5)]);
      expect(stroke.shape, isNull);
    });

    test('a straightened line is a line shape', () {
      final stroke = _stroke()
        ..addPoint(Offset.zero)
        ..addPoint(const Offset(50, 1))
        ..addPoint(const Offset(100, 2));
      stroke.convertToLine();
      // Nearly horizontal, so made horizontal.
      expect(stroke.shape, PathShape.line(Offset.zero, const Offset(100, 0)));
    });

    test('rectangles and circles from older notes are shapes', () {
      final rectangle = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(100, 100, 100, 100),
      );
      expect(StrokeShape.of(rectangle), _square);
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(),
        pageIndex: 0,
        page: _page,
        toolId: .shapePen,
        center: const Offset(50, 50),
        radius: 20,
      );
      expect(
        StrokeShape.of(circle),
        const EllipseShape(
          center: Offset(50, 50),
          u: Offset(20, 0),
          v: Offset(0, 20),
        ),
      );
    });
  });

  group('paths', () {
    test('a curve goes through its smooth anchors', () {
      const curve = PathShape([
        ShapeAnchor(Offset.zero),
        ShapeAnchor(Offset(50, 80), smooth: true),
        ShapeAnchor(Offset(100, 0)),
      ]);
      final outline = curve.outline(2);
      expect(outline, contains(const Offset(50, 80)));
      // Curving, so more than its three anchors.
      expect(outline.length, greaterThan(3));
      expect(outline.first, Offset.zero);
      expect(outline.last, const Offset(100, 0));
    });

    test('a middle handle adds a smooth anchor', () {
      final (shape, index) = _square.insertAnchor(3, const Offset(80, 150));
      expect(index, 4);
      expect(shape.points.length, 5);
      expect(shape.points[4], const ShapeAnchor(Offset(80, 150), smooth: true));
    });

    test('an open path\'s ends can\'t be smooth', () {
      const line = PathShape([
        ShapeAnchor(Offset.zero),
        ShapeAnchor(Offset(10, 0)),
        ShapeAnchor(Offset(20, 0)),
      ]);
      expect([0, 1, 2].map(line.canBeSmooth), [false, true, false]);
      expect([0, 3].map(_square.canBeSmooth), [true, true]);
    });

    test('anchors can be removed down to a line or a triangle', () {
      expect(_square.canRemoveAnchor, isTrue);
      expect(_square.withoutAnchor(0).canRemoveAnchor, isFalse);
      expect(
        PathShape.line(Offset.zero, const Offset(1, 1)).canRemoveAnchor,
        isFalse,
      );
    });

    test('an arrow head points out of the line\'s end', () {
      const arrow = PathShape([
        ShapeAnchor(Offset.zero),
        ShapeAnchor(Offset(100, 0)),
      ], endHead: true);
      const tip = Offset(100, 0);
      final outline = arrow.outline(2);
      expect(outline.where((p) => p == tip).length, 2);
      // Its two sides' ends, the furthest points from the tip after it.
      final afterTip = outline.skip(outline.indexOf(tip));
      final ends = afterTip
          .where(
            (p) => ((p - tip).distance - PathShape.headLength * 2).abs() < 1e-9,
          )
          .toList();
      expect(ends, hasLength(2));
      for (final end in ends) {
        expect(end.dx, lessThan(100));
      }
      expect(ends[0].dy, closeTo(-ends[1].dy, 1e-9));
    });
  });

  group('ellipses', () {
    const ellipse = EllipseShape(
      center: Offset(100, 100),
      u: Offset(60, 0),
      v: Offset(0, 30),
    );

    test('stay ellipses with perpendicular axes when sheared', () {
      // A rotated ellipse, stretched sideways.
      final turned = ellipse.map(
        (p) =>
            const Offset(100, 100) + _rotate(p - const Offset(100, 100), 0.5),
      );
      final stretched = turned.map((p) => Offset(100 + (p.dx - 100) * 2, p.dy));
      final dot =
          stretched.u.dx * stretched.v.dx + stretched.u.dy * stretched.v.dy;
      expect(dot, closeTo(0, 1e-6));
      // Every point of the old outline, mapped, is on the new one.
      for (final point in turned.outline(10)) {
        final mapped = Offset(100 + (point.dx - 100) * 2, point.dy);
        expect(_onEllipse(stretched, mapped), closeTo(1, 1e-6));
      }
    });

    test('moving an axis end keeps the opposite end', () {
      final moved = ellipse.moveAnchor(0, const Offset(180, 100));
      expect(moved.anchors[2], _near(const Offset(40, 100)));
      expect(moved.anchors[0], _near(const Offset(180, 100)));
      expect(moved.v.distance, closeTo(30, 1e-9));
      // The other axis stays on its side.
      expect(moved.v.dy, greaterThan(0));
    });

    test('moving the other axis keeps the first one\'s length', () {
      final moved = ellipse.moveAnchor(3, const Offset(100, 50));
      expect(moved.anchors[1], _near(const Offset(100, 130)));
      expect(moved.u.distance, closeTo(60, 1e-9));
      expect(moved.u.dx, greaterThan(0));
    });
  });

  group('snapping a dragged anchor', () {
    test('onto a nearby anchor first', () {
      expect(
        ShapeHandles.snap(
          const Offset(103, 98),
          neighbours: const [Offset.zero],
          targets: const [Offset(100, 100), Offset(104, 98)],
          distance: 5,
        ),
        const Offset(104, 98),
      );
    });

    test('onto a 15° line from a neighbour', () {
      final snapped = ShapeHandles.snap(
        const Offset(100, 3),
        neighbours: const [Offset.zero],
        targets: const [],
        distance: 5,
      );
      expect(snapped, _near(const Offset(100, 0)));
    });

    test('onto where the lines from two neighbours cross', () {
      // A rectangle's corner, between its neighbours.
      final snapped = ShapeHandles.snap(
        const Offset(198, 103),
        neighbours: const [Offset(100, 100), Offset(200, 200)],
        targets: const [],
        distance: 5,
      );
      expect(snapped, _near(const Offset(200, 100)));
    });

    test('not when nothing is near', () {
      const position = Offset(100, 37);
      expect(
        ShapeHandles.snap(
          position,
          neighbours: const [Offset.zero],
          targets: const [Offset(0, 100)],
          distance: 2,
        ),
        position,
      );
    });
  });

  group('handles', () {
    test('a middle handle is hidden where a side is short on screen', () {
      // Zoomed in, every side has room; zoomed far out, none has.
      ShapeHandles at(double pixel) =>
          ShapeHandles(shape: _square, pixel: pixel);
      expect(at(0.1).handles.where((h) => h.$1.middle), hasLength(4));
      expect(at(10).handles.where((h) => h.$1.middle), isEmpty);
      expect(at(10).handles.where((h) => !h.$1.middle), hasLength(4));
    });

    test('dragging a middle handle bends that side', () {
      final handles = ShapeHandles(shape: _square, pixel: 0.1);
      final (shape, index) = handles.drag((
        index: 0,
        middle: true,
      ), const Offset(150, 60));
      expect(index, 1);
      expect(
        (shape as PathShape).points[1],
        const ShapeAnchor(Offset(150, 60), smooth: true),
      );
    });

    test('an anchor isn\'t snapped onto its own neighbours', () {
      final handles = ShapeHandles(shape: _square, pixel: 10);
      final (shape, _) = handles.drag((
        index: 0,
        middle: false,
      ), const Offset(196, 103));
      expect(shape.anchors.first, isNot(const Offset(200, 100)));
    });
  });
}

Offset _rotate(Offset point, double angle) => Offset(
  point.dx * cos(angle) - point.dy * sin(angle),
  point.dx * sin(angle) + point.dy * cos(angle),
);

/// 1 if [point] is on [ellipse], in its axes' coordinates.
double _onEllipse(EllipseShape ellipse, Offset point) {
  final from = point - ellipse.center;
  double along(Offset axis) =>
      (from.dx * axis.dx + from.dy * axis.dy) / axis.distanceSquared;
  return pow(along(ellipse.u), 2) + pow(along(ellipse.v), 2).toDouble();
}
