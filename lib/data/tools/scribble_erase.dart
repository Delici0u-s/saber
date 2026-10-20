import 'dart:math';
import 'dart:ui';

import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/select_lasso.dart';

/// Scribbling back and forth over strokes erases them, like in Samsung Notes
/// or OneNote (see [Stows.scribbleToErase]).
abstract final class ScribbleErase {
  /// A scribble turns back at least this many times along its main
  /// direction.
  static const minReversals = 4;

  /// Each stretch between two turns has to be at least this fraction of
  /// the scribble's length along its main direction, so loopy handwriting
  /// (e.g. "eeee") doesn't count...
  static const minLegFraction = 0.5;

  /// ...and at least this many stroke widths, so jitter doesn't count.
  static const minLegWidths = 2.0;

  /// The strokes of [strokes] that [scribble] erases: those it mostly
  /// covers (as much as a lasso needs, see [SelectLasso.minPercentInside]),
  /// if it's a scribble (see [isScribble]). Empty otherwise.
  static List<Stroke> erasedBy(Stroke scribble, Iterable<Stroke> strokes) {
    final points = scribble.pointVectors;
    if (!isScribble(points, scribble.options.size)) return const [];
    final area = Path()..addPolygon(_convexHull(points), true);
    return [
      for (final stroke in strokes)
        if (!identical(stroke, scribble) &&
            stroke.lowQualityPolygon.isNotEmpty &&
            SelectLasso.polygonPercentInside(area, stroke.lowQualityPolygon) >=
                SelectLasso.minPercentInside)
          stroke,
    ];
  }

  /// Whether [points], drawn [strokeSize] wide, go back and forth: at least
  /// [minReversals] times along their main direction, in long stretches.
  static bool isScribble(List<Offset> points, double strokeSize) {
    if (points.length < 2 * minReversals) return false;
    final along = _alongMainDirection(points);
    final extent = along.reduce(max) - along.reduce(min);
    final minLeg = max(extent * minLegFraction, strokeSize * minLegWidths);
    if (!(minLeg > 0)) return false;

    // Count the turns, ignoring wobbles shorter than a leg.
    var direction = 0; // 1 or -1 once moving
    var extreme = along.first;
    var reversals = 0;
    for (final position in along) {
      if (direction == 0) {
        if ((position - extreme).abs() >= minLeg) {
          direction = (position - extreme).sign.toInt();
          extreme = position;
        }
      } else if ((position - extreme) * direction > 0) {
        extreme = position;
      } else if ((extreme - position) * direction >= minLeg) {
        reversals++;
        direction = -direction;
        extreme = position;
      }
    }
    return reversals >= minReversals;
  }

  /// How far along their main direction (the one they spread out most in)
  /// each of [points] is.
  static List<double> _alongMainDirection(List<Offset> points) {
    final mean =
        points.fold(Offset.zero, (sum, point) => sum + point) /
        points.length.toDouble();
    var xx = 0.0, yy = 0.0, xy = 0.0;
    for (final point in points) {
      final d = point - mean;
      xx += d.dx * d.dx;
      yy += d.dy * d.dy;
      xy += d.dx * d.dy;
    }
    final angle = atan2(2 * xy, xx - yy) / 2;
    final direction = Offset(cos(angle), sin(angle));
    return [
      for (final point in points)
        point.dx * direction.dx + point.dy * direction.dy,
    ];
  }

  /// The convex hull of [points] (Andrew's monotone chain).
  static List<Offset> _convexHull(List<Offset> points) {
    final sorted = [...points]
      ..sort(
        (a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy),
      );
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    List<Offset> half(Iterable<Offset> points) {
      final hull = <Offset>[];
      for (final point in points) {
        while (hull.length >= 2 &&
            cross(hull[hull.length - 2], hull.last, point) <= 0) {
          hull.removeLast();
        }
        hull.add(point);
      }
      return hull..removeLast();
    }

    return [...half(sorted), ...half(sorted.reversed)];
  }
}
