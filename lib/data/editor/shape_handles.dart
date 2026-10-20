import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/editor/selection_transform.dart';

/// A handle of [ShapeHandles]: on the anchor at [index], or, if [middle],
/// in the middle of the side after it (dragging it adds an anchor there).
typedef ShapeHandle = ({int index, bool middle});

/// The handles on a selected [shape], which reshape it: one on each of its
/// anchors, and one in the middle of each side of a [PathShape].
///
/// Like [SelectionBox]'s, they keep their size on screen ([pixel]).
@immutable
class ShapeHandles {
  const new({required this.shape, required this.pixel});

  final StrokeShape shape;

  /// How long a screen pixel is on the page.
  final double pixel;

  /// How big an anchor's handle is drawn (half its width), in screen pixels;
  /// the middle handles are smaller. They're grabbed like the box's.
  static const anchorRadius = SelectionBox.handleRadius,
      middleRadius = SelectionBox.handleRadius * 2 / 3;

  /// How close a dragged anchor has to come to something to snap to it, in
  /// screen pixels.
  static const snapDistance = SelectionBox.grabRadius / 2;

  /// The angles a dragged anchor snaps to from its neighbours.
  static const snapAngle = pi / 12;

  /// The middle handle of a side shorter than this on screen is hidden, so
  /// it doesn't crowd the anchors' (where they're grabbed, the nearest wins,
  /// so each keeps a finger's width of its own).
  static const _minSideForMiddle = SelectionBox.grabRadius * 2;

  /// The handles and where they are, anchors first.
  List<(ShapeHandle, Offset)> get handles {
    final anchors = shape.anchors;
    return [
      for (var i = 0; i < anchors.length; i++)
        ((index: i, middle: false), anchors[i]),
      if (shape case final PathShape path)
        for (final (i, middle) in path.middles.indexed)
          if ((anchors[(i + 1) % anchors.length] - anchors[i]).distance >=
              _minSideForMiddle * pixel)
            ((index: i, middle: true), middle),
    ];
  }

  /// Where [handle] is.
  Offset positionOf(ShapeHandle handle) => handle.middle
      ? (shape as PathShape).middles[handle.index]
      : shape.anchors[handle.index];

  /// The handle at [point] and how far it is from it, if any is within
  /// [SelectionBox.grabRadius] (the nearest, where they're close).
  (ShapeHandle, double)? handleAt(Offset point) {
    (ShapeHandle, double)? nearest;
    for (final (handle, position) in handles) {
      final distance = (position - point).distance;
      if (distance > SelectionBox.grabRadius * pixel) continue;
      if (nearest != null && distance >= nearest.$2) continue;
      nearest = (handle, distance);
    }
    return nearest;
  }

  /// The shape after dragging [handle] to [position], snapped (see [snap])
  /// to [targets] (anchors elsewhere on the page), unless [snapped] (e.g. to
  /// the ruler) already; and the index of the anchor dragged, which for a
  /// middle handle is the one it adds.
  (StrokeShape, int) drag(
    ShapeHandle handle,
    Offset position, {
    List<Offset> targets = const [],
    bool snapped = false,
  }) {
    var shape = this.shape;
    var index = handle.index;
    if (handle.middle) {
      (shape, index) = (shape as PathShape).insertAnchor(index, position);
    }
    final neighbours = shape.neighboursOf(index);
    if (!snapped) {
      final anchors = shape.anchors;
      position = snap(
        position,
        neighbours: neighbours,
        targets: [
          ...targets,
          // Not onto itself or its neighbours, which would fold a side away.
          for (var i = 0; i < anchors.length; i++)
            if (i != index && !neighbours.contains(anchors[i])) anchors[i],
        ],
        distance: snapDistance * pixel,
      );
    }
    return (shape.moveAnchor(index, position), index);
  }

  /// [position] snapped onto the nearest of [targets] within [distance],
  /// else onto a line at a multiple of [snapAngle] from one of
  /// [neighbours] (onto where two such lines cross, if it's near both),
  /// else as it is.
  static Offset snap(
    Offset position, {
    required List<Offset> neighbours,
    required List<Offset> targets,
    required double distance,
  }) {
    Offset? nearest;
    for (final target in targets) {
      if ((target - position).distance > distance) continue;
      if (nearest != null &&
          (target - position).distance >= (nearest - position).distance) {
        continue;
      }
      nearest = target;
    }
    if (nearest != null) return nearest;

    // The snapped line from each neighbour that passes close by: its
    // start and direction.
    final lines = <(Offset, Offset)>[];
    for (final neighbour in neighbours) {
      final from = position - neighbour;
      if (from == .zero) continue;
      final angle = (from.direction / snapAngle).round() * snapAngle;
      final direction = Offset.fromDirection(angle);
      final along = from.dx * direction.dx + from.dy * direction.dy;
      final onLine = neighbour + direction * along;
      if ((onLine - position).distance <= distance) {
        lines.add((neighbour, direction));
      }
    }
    if (lines.length >= 2) {
      final crossing = _crossing(lines[0], lines[1]);
      if (crossing != null && (crossing - position).distance <= distance * 2) {
        return crossing;
      }
    }
    if (lines.isEmpty) return position;
    final (start, direction) = lines.first;
    final from = position - start;
    return start +
        direction * (from.dx * direction.dx + from.dy * direction.dy);
  }

  /// Where two lines (a point and a direction each) cross, or null if
  /// they're parallel.
  static Offset? _crossing((Offset, Offset) a, (Offset, Offset) b) {
    final (p, r) = a;
    final (q, s) = b;
    final cross = r.dx * s.dy - r.dy * s.dx;
    if (cross.abs() < 1e-9) return null;
    final t = ((q - p).dx * s.dy - (q - p).dy * s.dx) / cross;
    return p + r * t;
  }
}
