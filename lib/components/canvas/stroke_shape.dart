import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// The shape a [Stroke] keeps (see [Stroke.shape]), so it can be edited as
/// one: by its anchors, see [anchors].
///
/// The stroke's points are drawn along the shape (see [outline]) and saved
/// too, so Saber versions that don't know the shape show it as a plain
/// stroke.
@immutable
sealed class StrokeShape {
  const new();

  /// The shape saved in [json] (a stroke's), or null if it has none this
  /// version knows.
  static StrokeShape? fromJson(Map<String, dynamic> json) =>
      switch (json['shape']) {
        PathShape.jsonName => PathShape.fromJson(json),
        EllipseShape.jsonName => EllipseShape.fromJson(json),
        _ => null,
      };

  /// The shape of [stroke]: its [Stroke.shape], or the shape of a rectangle
  /// or circle from before shapes could be edited.
  static StrokeShape? of(Stroke stroke) => switch (stroke) {
    RectangleStroke(:final rect) => PathShape.polygon([
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]),
    CircleStroke(:final center, :final radius) => EllipseShape(
      center: center,
      u: Offset(radius, 0),
      v: Offset(0, radius),
    ),
    _ => stroke.shape,
  };

  /// What [Stroke.toJson] saves of this shape, with `shape` naming it.
  Map<String, dynamic> toJson();

  /// The points of a stroke [strokeSize] wide along the shape, about that
  /// far apart, through its corners. A closed shape ends where it starts.
  List<Offset> outline(double strokeSize);

  /// This shape moved by the affine map [map] (e.g. a selection's resize or
  /// rotation).
  StrokeShape map(Offset Function(Offset) map);

  StrokeShape shift(Offset offset) => map((point) => point + offset);

  /// Where the shape can be grabbed and reshaped (see [moveAnchor]): its
  /// corners and ends, or an ellipse's axis ends.
  List<Offset> get anchors;

  /// Anchors a dragged anchor at [index] snaps to angles from, see
  /// [moveAnchor].
  List<Offset> neighboursOf(int index);

  /// This shape with the anchor at [index] moved to [position].
  StrokeShape moveAnchor(int index, Offset position);
}

/// A point of a [PathShape]: a corner, or [smooth] (the shape curves
/// through it).
@immutable
class ShapeAnchor {
  const new(this.position, {this.smooth = false});

  final Offset position;
  final bool smooth;

  ShapeAnchor copyWith({Offset? position, bool? smooth}) =>
      ShapeAnchor(position ?? this.position, smooth: smooth ?? this.smooth);

  @override
  bool operator ==(Object other) =>
      other is ShapeAnchor &&
      other.position == position &&
      other.smooth == smooth;

  @override
  int get hashCode => Object.hash(position, smooth);
}

/// A line through [anchors] one after another: straight between corners,
/// curving through smooth ones. [closed] joins the last anchor back to the
/// first (a polygon); an open one can have arrow heads at its ends.
class PathShape extends StrokeShape {
  const new(
    this.points, {
    this.closed = false,
    this.startHead = false,
    this.endHead = false,
  });

  /// A polygon with corners at [corners].
  new polygon(List<Offset> corners)
    : this([for (final corner in corners) ShapeAnchor(corner)], closed: true);

  /// A straight line from [start] to [end].
  new line(Offset start, Offset end)
    : this([ShapeAnchor(start), ShapeAnchor(end)]);

  static const jsonName = 'path';

  factory fromJson(Map<String, dynamic> json) {
    final coordinates = (json['sa'] as List).cast<num>();
    final smooth = {...?(json['ss'] as List?)?.cast<int>()};
    final heads = json['sh'] as int? ?? 0;
    return PathShape(
      [
        for (var i = 0; i < coordinates.length ~/ 2; i++)
          ShapeAnchor(
            Offset(
              coordinates[2 * i].toDouble(),
              coordinates[2 * i + 1].toDouble(),
            ),
            smooth: smooth.contains(i),
          ),
      ],
      closed: json['sc'] == true,
      startHead: heads & _startHeadBit != 0,
      endHead: heads & _endHeadBit != 0,
    );
  }

  static const _startHeadBit = 1, _endHeadBit = 2;

  @override
  Map<String, dynamic> toJson() => {
    'shape': jsonName,
    'sa': [
      for (final anchor in points) ...[anchor.position.dx, anchor.position.dy],
    ],
    if (points.any((anchor) => anchor.smooth))
      'ss': [
        for (var i = 0; i < points.length; i++)
          if (points[i].smooth) i,
      ],
    if (closed) 'sc': true,
    if (startHead || endHead)
      'sh': (startHead ? _startHeadBit : 0) | (endHead ? _endHeadBit : 0),
  };

  /// The shape's anchors (at least two), see [StrokeShape.anchors] for their
  /// positions.
  final List<ShapeAnchor> points;
  final bool closed;

  /// Whether an arrow head points out of the first or the last anchor.
  final bool startHead, endHead;

  /// How long an arrow head's sides are, in stroke widths.
  static const headLength = 4.0;

  /// The angle between an arrow head's sides and its line.
  static const headAngle = pi / 6;

  /// A curved side is drawn with at least this many points, so a short one
  /// still curves.
  static const _minCurvePoints = 8;

  PathShape copyWith({List<ShapeAnchor>? points, bool? closed}) => PathShape(
    points ?? this.points,
    closed: closed ?? this.closed,
    startHead: startHead,
    endHead: endHead,
  );

  int get segmentCount => closed ? points.length : points.length - 1;

  /// The direction the line passes through the anchor at [index], scaled
  /// for [_segment]'s control points; zero at a corner and at an open
  /// shape's ends.
  Offset _tangent(int index) {
    if (!points[index].smooth) return .zero;
    if (!closed && (index == 0 || index == points.length - 1)) return .zero;
    final previous = points[(index - 1) % points.length].position;
    final next = points[(index + 1) % points.length].position;
    return (next - previous) / 2;
  }

  /// The side from anchor [index] to the next as a cubic Bézier curve: its
  /// start, two control points and end.
  (Offset, Offset, Offset, Offset) _segment(int index) {
    final next = (index + 1) % points.length;
    final start = points[index].position, end = points[next].position;
    return (start, start + _tangent(index) / 3, end - _tangent(next) / 3, end);
  }

  bool _isStraight(int index) =>
      _tangent(index) == .zero &&
      _tangent((index + 1) % points.length) == .zero;

  static Offset _bezier((Offset, Offset, Offset, Offset) curve, double t) {
    final (p0, p1, p2, p3) = curve;
    final s = 1 - t;
    return p0 * (s * s * s) +
        p1 * (3 * s * s * t) +
        p2 * (3 * s * t * t) +
        p3 * (t * t * t);
  }

  /// The middle of each side, where dragging adds an anchor (see
  /// [insertAnchor]).
  List<Offset> get middles => [
    for (var i = 0; i < segmentCount; i++) _bezier(_segment(i), 0.5),
  ];

  /// This shape with a smooth anchor at [position] in the middle of side
  /// [segment] (the one after anchor [segment]), and that anchor's index.
  (PathShape, int) insertAnchor(int segment, Offset position) {
    final index = segment + 1;
    return (
      copyWith(
        points: [...points]..insert(index, ShapeAnchor(position, smooth: true)),
      ),
      index,
    );
  }

  /// Whether the anchor at [index] can be smooth: not an open shape's ends,
  /// which have nothing to curve between.
  bool canBeSmooth(int index) =>
      closed || (index != 0 && index != points.length - 1);

  PathShape withSmooth(int index, bool smooth) => copyWith(
    points: [...points]..[index] = points[index].copyWith(smooth: smooth),
  );

  /// Whether the anchor at [index] can be removed: a line needs two, a
  /// polygon three.
  bool get canRemoveAnchor => points.length > (closed ? 3 : 2);

  PathShape withoutAnchor(int index) {
    assert(canRemoveAnchor);
    return copyWith(points: [...points]..removeAt(index));
  }

  @override
  List<Offset> outline(double strokeSize) {
    final line = [points.first.position];
    for (var i = 0; i < segmentCount; i++) {
      final curve = _segment(i);
      if (_isStraight(i)) {
        line.add(curve.$4);
        continue;
      }
      final (p0, p1, p2, p3) = curve;
      // The control polygon is at least as long as the curve.
      final length =
          (p1 - p0).distance + (p2 - p1).distance + (p3 - p2).distance;
      final count = max(_minCurvePoints, (length / strokeSize).ceil());
      for (var j = 1; j <= count; j++) {
        line.add(_bezier(curve, j / count));
      }
    }
    // Without the head's last tip, which the line starts from.
    return _evenlySpaced([
      if (startHead) ..._head(line[0], line[1], strokeSize).take(3),
      ...line,
      if (endHead)
        ..._head(line.last, line[line.length - 2], strokeSize).reversed.skip(1),
    ], strokeSize);
  }

  /// [corners] with points added between them, so none are further apart
  /// than [spacing]: a stroke's outline (see [Stroke.getPolygon]) only keeps
  /// an even width where its points are close.
  static List<Offset> _evenlySpaced(List<Offset> corners, double spacing) => [
    corners.first,
    for (var i = 1; i < corners.length; i++) ...[
      for (
        var j = 1,
            count = max(
              1,
              ((corners[i] - corners[i - 1]).distance / spacing).ceil(),
            );
        j <= count;
        j++
      )
        Offset.lerp(corners[i - 1], corners[i], j / count)!,
    ],
  ];

  /// An arrow head at [tip], pointing away from [from], for a stroke [size]
  /// wide: one side, the tip, the other side and the tip again, so the line
  /// goes on from the tip.
  static List<Offset> _head(Offset tip, Offset from, double size) {
    final back = from - tip;
    if (back == .zero) return const [];
    final side = Offset.fromDirection(back.direction, headLength * size);
    Offset rotated(double angle) =>
        Offset.fromDirection(side.direction + angle, side.distance);
    return [tip + rotated(headAngle), tip, tip + rotated(-headAngle), tip];
  }

  @override
  PathShape map(Offset Function(Offset) map) => copyWith(
    points: [
      for (final anchor in points)
        anchor.copyWith(position: map(anchor.position)),
    ],
  );

  @override
  List<Offset> get anchors => [for (final anchor in points) anchor.position];

  @override
  List<Offset> neighboursOf(int index) => [
    if (closed || index > 0) points[(index - 1) % points.length].position,
    if (closed || index < points.length - 1)
      points[(index + 1) % points.length].position,
  ];

  @override
  PathShape moveAnchor(int index, Offset position) => copyWith(
    points: [...points]..[index] = points[index].copyWith(position: position),
  );

  @override
  bool operator ==(Object other) =>
      other is PathShape &&
      _listEquals(other.points, points) &&
      other.closed == closed &&
      other.startHead == startHead &&
      other.endHead == endHead;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(points), closed, startHead, endHead);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// An ellipse around [center], with semi-axes [u] and [v] (perpendicular;
/// a circle when they're as long).
class EllipseShape extends StrokeShape {
  const new({required this.center, required this.u, required this.v});

  static const jsonName = 'ellipse';

  factory fromJson(Map<String, dynamic> json) {
    final [cx, cy, ux, uy, vx, vy] = [
      for (final value in (json['se'] as List).cast<num>()) value.toDouble(),
    ];
    return EllipseShape(
      center: Offset(cx, cy),
      u: Offset(ux, uy),
      v: Offset(vx, vy),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'shape': jsonName,
    'se': [center.dx, center.dy, u.dx, u.dy, v.dx, v.dy],
  };

  final Offset center, u, v;

  /// An ellipse is drawn with at least this many points, so a small one
  /// stays round.
  static const _minPoints = 16;

  @override
  List<Offset> outline(double strokeSize) {
    // Ramanujan's approximation of the circumference.
    final a = u.distance, b = v.distance;
    final circumference = pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)));
    final count = max(_minPoints, (circumference / strokeSize).ceil());
    return [
      for (var i = 0; i <= count; i++)
        center + u * cos(2 * pi * i / count) + v * sin(2 * pi * i / count),
    ];
  }

  /// An affine map takes an ellipse to an ellipse, but its axes to a pair
  /// that may not be perpendicular any more, so the new axes are worked out
  /// (from the eigenvectors of `M Mᵀ`, where `M`'s columns are the pair).
  @override
  EllipseShape map(Offset Function(Offset) map) {
    final c = map(center);
    final mu = map(center + u) - c, mv = map(center + v) - c;
    final a = mu.dx * mu.dx + mv.dx * mv.dx;
    final b = mu.dx * mu.dy + mv.dx * mv.dy;
    final d = mu.dy * mu.dy + mv.dy * mv.dy;
    final angle = atan2(2 * b, a - d) / 2;
    final mean = (a + d) / 2;
    final spread = sqrt(pow((a - d) / 2, 2) + b * b);
    final major = sqrt(mean + spread), minor = sqrt(max(0, mean - spread));
    return EllipseShape(
      center: c,
      u: Offset.fromDirection(angle, major),
      v: Offset.fromDirection(angle + pi / 2, minor),
    );
  }

  /// The ends of the axes: [u]'s, [v]'s, then the opposite ones.
  @override
  List<Offset> get anchors => [center + u, center + v, center - u, center - v];

  @override
  List<Offset> neighboursOf(int index) => [anchors[(index + 2) % 4]];

  /// Moves an axis end, keeping the opposite end: the axis turns with it,
  /// and the other axis keeps its length, perpendicular to it.
  @override
  EllipseShape moveAnchor(int index, Offset position) {
    final opposite = anchors[(index + 2) % 4];
    final newCenter = (position + opposite) / 2;
    final axis = (position - opposite) / 2;
    if (axis == .zero) return this;
    final isU = index.isEven;
    final moved = index < 2 ? axis : -axis;
    final other = isU ? v : u;
    // Turned a quarter, on the same side as the other axis was.
    final turnedSide = (u.dx * v.dy - u.dy * v.dx).sign;
    final perpendicular = Offset(-moved.dy, moved.dx) / moved.distance;
    final otherAxis =
        perpendicular * other.distance * (isU ? turnedSide : -turnedSide);
    return EllipseShape(
      center: newCenter,
      u: isU ? moved : otherAxis,
      v: isU ? otherAxis : moved,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EllipseShape &&
      other.center == center &&
      other.u == u &&
      other.v == v;

  @override
  int get hashCode => Object.hash(center, u, v);
}
