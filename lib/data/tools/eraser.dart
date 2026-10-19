import 'dart:math';
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

double square(double x) => x * x;

double sqrDistanceBetween(Offset p1, Offset p2) =>
    square(p1.dx - p2.dx) + square(p1.dy - p2.dy);

// Return true when `point` lies within the eraser's circular area.
// Uses squared distances to avoid unnecessary `sqrt` calls for speed.
bool _isPointInsideEraser(Offset point, Offset eraserPos, double sqrSize) {
  return sqrDistanceBetween(point, eraserPos) <= sqrSize;
}

class Eraser extends Tool {
  static var currentEraser = Eraser(
    size: stows.lastEraserSize.value,
    areaEraser: stows.lastEraserAreaMode.value,
  );

  final double sizeMin = 1;
  final double sizeMax = 25;
  final double sizeStep = 1;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();

  double _size;
  bool _areaErase;

  double get size => _size;
  set size(double value) {
    if (_size == value) return;
    _size = value;
    stows.lastEraserSize.value = value;
  }

  bool get areaEraser => _areaErase;
  set areaEraser(bool value) {
    if (_areaErase == value) return;
    _areaErase = value;
    stows.lastEraserAreaMode.value = value;
  }

  double get sqrSize => square(size);

  /// Icons (SVG assets) for the stroke and area eraser modes.
  static const strokeEraserIcon = 'assets/images/eraser-stroke.svg';
  static const areaEraserIcon = 'assets/images/eraser-area.svg';

  /// The icon for this eraser's current mode.
  String get icon => areaEraser ? areaEraserIcon : strokeEraserIcon;

  final List<Stroke> _erased = [];
  final List<Stroke> _replacementStrokes = [];
  final Set<Stroke> _processedStrokes = {};

  Eraser({double size = 10, bool areaEraser = false})
    : _size = size,
      _areaErase = areaEraser;

  @override
  ToolId get toolId => .eraser;

  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double sqrSize,
  ) {
    if (stroke.lowQualityPath.contains(eraserPos)) return true;

    /// skip checking every few vertices for performance
    final int verticesToSkip = switch (stroke.lowQualityPolygon.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };

    for (
      int i = 0;
      i < stroke.lowQualityPolygon.length;
      i += verticesToSkip + 1
    ) {
      final Offset strokeVertex = stroke.lowQualityPolygon[i];
      if (sqrDistanceBetween(strokeVertex, eraserPos) <= sqrSize) return true;
    }
    return false;
  }

  /// Returns any strokes that are fully removed by the eraser.
  List<Stroke> checkForOverlappingStrokes(
    Offset eraserPos,
    List<Stroke> strokes,
  ) {
    // The returned list contains strokes that should be removed entirely.
    // During a drag this method also updates internal replacement lists for
    // partial erases so the caller can apply point-replacements afterwards.
    final List<Stroke> erased = [];
    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (!_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) continue;

      if (!areaEraser) {
        // Stroke (normal) eraser: mark and return stroke for removal.
        _trackErasedStroke(stroke);
        erased.add(stroke);
        continue;
      }

      // Area eraser: remember original stroke snapshot and compute
      // remaining segments after removing points inside the eraser.
      _trackPartialEraseStroke(stroke);

      final remainingSegments = _remainingSegmentsAfterErase(
        stroke,
        eraserPos,
        sqrSize,
      );
      if (remainingSegments.isEmpty) {
        erased.add(stroke);
        _removeReplacementStroke(stroke);
        continue;
      }

      if (remainingSegments.length == 1 &&
          _isSameSegmentAsStroke(remainingSegments.first.points, stroke)) {
        _trackReplacementStroke(stroke);
        continue;
      }

      // Each part keeps its place in the dash pattern, see [Stroke.lineStyleOffset].
      final strokeOffset = stroke.lineStyleOffset;
      stroke
        ..lineStyleOffset = strokeOffset + remainingSegments.first.start
        ..replacePoints(remainingSegments.first.points);
      _trackReplacementStroke(stroke);

      for (final segment in remainingSegments.skip(1)) {
        final replacement = _strokeFromSegment(
          stroke,
          segment.points,
          lineStyleOffset: strokeOffset + segment.start,
        );
        strokes.insert(i + 1, replacement);
        _trackReplacementStroke(replacement);
      }
    }
    return erased;
  }

  EraserResult onDragEnd() {
    final result = EraserResult(
      erasedStrokes: List.of(_erased),
      replacementStrokes: List.of(_replacementStrokes),
    );
    _erased.clear();
    _replacementStrokes.clear();
    _processedStrokes.clear();
    return result;
  }

  /// The parts of [stroke] outside the eraser, each with how far along the
  /// stroke it starts. The stroke is cut where it crosses the eraser's edge,
  /// so long segments (e.g. of a straight line) aren't removed whole.
  static List<({List<PointVector> points, double start})>
  _remainingSegmentsAfterErase(
    Stroke stroke,
    Offset eraserPos,
    double sqrSize,
  ) {
    final radius = sqrt(sqrSize);
    final points = stroke.pointVectors;
    final segments = <({List<PointVector> points, double start})>[];
    if (points.isEmpty) return segments;

    bool isInside(PointVector point) =>
        _isPointInsideEraser(Offset(point.x, point.y), eraserPos, sqrSize);

    List<PointVector>? current;
    var currentStart = 0.0;
    void startAt(PointVector point, double start) {
      current = [point];
      currentStart = start;
    }

    void endAt(PointVector point) {
      segments.add((points: current!..add(point), start: currentStart));
      current = null;
    }

    var length = 0.0;
    if (!isInside(points.first)) startAt(points.first, 0);
    for (var i = 1; i < points.length; i++) {
      final from = points[i - 1], to = points[i];
      final segmentLength = (to - from).distance;
      final fromInside = isInside(from), toInside = isInside(to);
      final crossings = _circleCrossings(from, to, eraserPos, radius);
      PointVector at(double t) => from.lerp(t, to);

      if (!fromInside && toInside) {
        // entering the eraser
        endAt(at(crossings?.enter ?? 1));
      } else if (fromInside && !toInside) {
        // leaving the eraser
        final t = crossings?.leave ?? 0;
        startAt(at(t), length + t * segmentLength);
      } else if (!fromInside && !toInside && crossings != null) {
        // passing through the eraser
        endAt(at(crossings.enter));
        startAt(at(crossings.leave), length + crossings.leave * segmentLength);
      }
      if (!toInside) current!.add(to);
      length += segmentLength;
    }

    if (current != null) {
      segments.add((points: current!, start: currentStart));
    }
    return segments;
  }

  /// Where the line from [from] to [to] enters and leaves the circle,
  /// as fractions of the way from [from] to [to], or null if the line
  /// doesn't pass through the circle between them.
  static ({double enter, double leave})? _circleCrossings(
    Offset from,
    Offset to,
    Offset center,
    double radius,
  ) {
    final d = to - from;
    final f = from - center;
    final a = d.dx * d.dx + d.dy * d.dy;
    if (a == 0) return null;
    final b = 2 * (f.dx * d.dx + f.dy * d.dy);
    final c = f.dx * f.dx + f.dy * f.dy - radius * radius;
    final discriminant = b * b - 4 * a * c;
    if (discriminant <= 0) return null;
    final root = sqrt(discriminant);
    final enter = (-b - root) / (2 * a), leave = (-b + root) / (2 * a);
    if (leave < 0 || enter > 1) return null;
    return (enter: enter.clamp(0.0, 1.0), leave: leave.clamp(0.0, 1.0));
  }

  static bool _isSameSegmentAsStroke(List<PointVector> segment, Stroke stroke) {
    if (segment.length != stroke.length) return false;
    final points = stroke.pointVectors;
    for (int i = 0; i < segment.length; i++) {
      if (!_isSamePoint(segment[i], points[i])) return false;
    }
    return true;
  }

  static bool _isSamePoint(PointVector a, PointVector b) {
    return a.x == b.x && a.y == b.y && a.pressure == b.pressure;
  }

  static Stroke _strokeFromSegment(
    Stroke source,
    List<PointVector> segment, {
    required double lineStyleOffset,
  }) {
    final replacement = Stroke(
      color: source.color,
      pressureEnabled: source.pressureEnabled,
      options: source.options.copyWith(isComplete: true),
      pageIndex: source.pageIndex,
      page: source.page,
      toolId: source.toolId,
      lineStyle: source.lineStyle,
      lineStyleOffset: lineStyleOffset,
    );
    for (final point in segment) {
      replacement.addPoint(Offset(point.x, point.y), point.pressure);
    }
    replacement.markPolygonNeedsUpdating();
    return replacement;
  }

  void _trackErasedStroke(Stroke stroke) {
    if (_processedStrokes.add(stroke)) {
      _erased.add(stroke);
    }
  }

  void _trackPartialEraseStroke(Stroke stroke) {
    if (_processedStrokes.add(stroke)) {
      _erased.add(stroke.copy());
    }
  }

  void _trackReplacementStroke(Stroke stroke) {
    if (!_replacementStrokes.contains(stroke)) {
      _replacementStrokes.add(stroke);
    }
  }

  void _removeReplacementStroke(Stroke stroke) {
    _replacementStrokes.remove(stroke);
  }
}

class EraserResult {
  EraserResult({required this.erasedStrokes, required this.replacementStrokes});

  final List<Stroke> erasedStrokes;
  final List<Stroke> replacementStrokes;
}
