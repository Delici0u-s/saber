import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/extensions/point_extensions.dart';
import 'package:saber/data/tools/line_style.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

class Stroke {
  static final log = Logger('Stroke');

  @visibleForTesting
  @protected
  final List<PointVector> points = [];

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  int pageIndex;
  HasSize page;
  final ToolId toolId;

  static const defaultColor = Colors.black;
  static const defaultPressureEnabled = true;

  Color color;
  bool pressureEnabled;
  final StrokeOptions options;
  final LineStyle lineStyle;

  /// How far into [lineStyle]'s pattern this stroke starts, in page units:
  /// the length of the stroke the eraser cut off its start, so the dashes
  /// that are left don't move.
  double lineStyleOffset;

  /// Whether this stroke is drawn in pieces (dashes or dots), see [lineStyle].
  /// A dot stays a dot.
  bool get isInPieces => lineStyle != .solid && !isDot;

  /// The outline of each piece of a stroke that [isInPieces].
  List<List<Offset>>? _lowQualityPieces, _highQualityPieces;
  List<List<Offset>> get lowQualityPieces =>
      _lowQualityPieces ??= getPieces(quality: .low);
  List<List<Offset>> get highQualityPieces =>
      _highQualityPieces ??= getPieces(quality: .high);

  /// The stroke's outline. For a stroke in pieces, the outlines of all pieces
  /// one after another: fine for hit testing, not for drawing.
  List<Offset>? _lowQualityPolygon, _highQualityPolygon;
  List<Offset> get lowQualityPolygon => _lowQualityPolygon ??= isInPieces
      ? lowQualityPieces.flattened.toList()
      : getPolygon(quality: .low);
  List<Offset> get highQualityPolygon => _highQualityPolygon ??= isInPieces
      ? highQualityPieces.flattened.toList()
      : getPolygon(quality: .high);

  Path? _lowQualityPath, _highQualityPath;
  Path get lowQualityPath => _lowQualityPath ??= isInPieces
      ? _piecesPath(lowQualityPieces, smooth: false)
      : getPath(lowQualityPolygon, smooth: false);
  Path get highQualityPath => _highQualityPath ??= isInPieces
      ? _piecesPath(highQualityPieces)
      : getPath(highQualityPolygon);

  void shift(Offset offset) {
    if (offset == .zero) return;

    points.shift(offset);
    _lowQualityPieces?.forEach((piece) => piece.shift(offset));
    _highQualityPieces?.forEach((piece) => piece.shift(offset));
    _lowQualityPolygon?.shift(offset);
    _highQualityPolygon?.shift(offset);
    _lowQualityPath = _lowQualityPath?.shift(offset);
    _highQualityPath = _highQualityPath?.shift(offset);
  }

  void markPolygonNeedsUpdating() {
    _lowQualityPieces = null;
    _highQualityPieces = null;
    _lowQualityPolygon = null;
    _highQualityPolygon = null;
    _lowQualityPath = null;
    _highQualityPath = null;
  }

  new({
    required this.color,
    required this.pressureEnabled,
    required this.options,
    required this.pageIndex,
    required this.page,
    required this.toolId,
    this.lineStyle = .solid,
    this.lineStyleOffset = 0,
  });

  factory fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['i'] == pageIndex || json['i'] == null);
    switch (json['shape'] as String?) {
      case null:
        break;
      case 'circle':
        return CircleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'rect':
        return RectangleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      default:
        log.severe('Unknown shape: ${json['shape']}');
    }

    final ToolId toolId = .parsePenType(json['ty'], fallback: .fountainPen);

    final options = StrokeOptions.fromJson(json);
    final pressureEnabled = json['pe'] ?? defaultPressureEnabled;
    if (toolId == .shapePen) {
      // Set smoothing and streamline to 0 for ShapePen
      // to mitigate https://github.com/saber-notes/saber/issues/1587
      options.smoothing = 0;
      options.streamline = 0;
    }

    final Color color;
    switch (json['c']) {
      case (final int value):
        color = Color(value);
      case (final Int64 value):
        color = Color(value.toInt());
      case null:
        color = defaultColor;
      default:
        throw Exception(
          'Invalid color value: (${json['c'].runtimeType}) ${json['c']}',
        );
    }

    final offset = Offset(json['ox'] ?? 0, json['oy'] ?? 0);
    final pointsJson = json['p'] as List<dynamic>;
    final Iterable<PointVector> points;
    if (fileVersion >= 13) {
      points = pointsJson.map(
        (point) => PointExtensions.fromBsonBinary(json: point, offset: offset),
      );
    } else {
      points = pointsJson.map(
        // ignore: deprecated_member_use_from_same_package
        (point) => PointExtensions.fromJson(
          json: Map<String, dynamic>.from(point),
          offset: offset,
        ),
      );
    }

    return Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options,
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      lineStyle: .fromJson(json['ls']),
      lineStyleOffset: (json['lo'] as num?)?.toDouble() ?? 0,
    )..points.addAll(points);
  }
  Map<String, dynamic> toJson() {
    // these json keys should not be the same as the ones in [StrokeOptions.toJson]
    return {
      'shape': null,
      'p': points
          .where((point) => point.isFinite)
          .map((PointVector point) => point.toBsonBinary())
          .toList(),
      'i': pageIndex,
      'ty': toolId.id,
      'pe': pressureEnabled,
      'c': color.toARGB32(),
      if (lineStyle != .solid) 'ls': lineStyle.name,
      if (lineStyle != .solid && lineStyleOffset != 0) 'lo': lineStyleOffset,
    }..addAll(options.toJson());
  }

  void addPoint(Offset point, [double? pressure]) {
    if (!pressureEnabled) {
      pressure = null;
    } else if (pressure != null) {
      options.simulatePressure = false;
    }

    points.add(PointVector(point.dx, point.dy, pressure));
    markPolygonNeedsUpdating();
  }

  void addPoints(List<Offset> points) {
    for (final point in points) {
      addPoint(point);
    }
  }

  List<PointVector> get pointVectors => List.unmodifiable(points);

  void replacePoints(List<PointVector> newPoints) {
    points
      ..clear()
      ..addAll(newPoints);
    markPolygonNeedsUpdating();
  }

  void popFirstPoint() {
    points.removeAt(0);
    markPolygonNeedsUpdating();
  }

  /// Points that are closer than this
  /// threshold multiplied by the stroke's size
  /// will be counted as duplicates.
  static const _optimisePointsThreshold = 0.1;

  /// Removes points that are too close together. See [_optimisePointsThreshold].
  ///
  /// This function is idempotent, so running it multiple times
  /// will not change the result.
  ///
  /// This function does not change [_polygonNeedsUpdating].
  void optimisePoints({double thresholdMultiplier = _optimisePointsThreshold}) {
    if (points.length <= 3) return;

    final minDistance = options.size * thresholdMultiplier;

    // Remove points with null pressure because they were duplicates
    points.removeWhere((point) => point.pressure == null);

    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final prev = points[i - 1];
      final next = points[i + 1];

      if (prev.distanceSquaredTo(point) < minDistance * minDistance &&
          point.distanceSquaredTo(next) < minDistance * minDistance) {
        points.removeAt(i);
        i--;
      }
    }
  }

  /// Whether this stroke never leaves its own width, i.e. it's a dot.
  bool get isDot =>
      points.isNotEmpty &&
      points.every((point) => (point - points.first).distance <= options.size);

  /// [options] without tapering, e.g. for a dot, which a taper (e.g. the
  /// pencil's) would shrink to nothing.
  StrokeOptions get _untaperedOptions => options.copyWith(
    start: options.start.copyWith(taperEnabled: false, customTaper: null),
    end: options.end.copyWith(taperEnabled: false, customTaper: null),
  );

  static StrokeOptions _optionsForQuality(
    StrokeOptions options,
    StrokeQuality quality,
  ) => switch (quality) {
    .low => options.copyWith(
      simulatePressure: false,
      smoothing: 0,
      streamline: 0,
    ),
    .high => options,
  };

  @protected
  List<Offset> getPolygon({required StrokeQuality quality}) {
    if (!pressureEnabled) {
      options.simulatePressure = false;
    }
    final rememberSimulatedPressure =
        quality == .high && options.simulatePressure && options.isComplete;

    final polygon = getStroke(
      skipPoints(points, quality.N),
      options: _optionsForQuality(isDot ? _untaperedOptions : options, quality),
      rememberSimulatedPressure: rememberSimulatedPressure,
    );

    if (rememberSimulatedPressure) {
      // Ensure we don't simulate pressure again
      options.simulatePressure = false;
      // Remove points that are too close together
      optimisePoints();
    }

    return polygon;
  }

  /// The outline of each dash or dot of this stroke, see [lineStyle].
  @protected
  List<List<Offset>> getPieces({required StrokeQuality quality}) {
    if (!pressureEnabled) {
      options.simulatePressure = false;
    }
    // Each piece is drawn like a short, finished stroke without tapers.
    final pieceOptions = _optionsForQuality(
      _untaperedOptions,
      quality,
    ).copyWith(isComplete: true);

    // Pressure is simulated along the whole stroke, like for a solid one:
    // per piece, each would get its own, which changes once it's finished.
    var line = skipPoints(points, quality.N);
    if (pieceOptions.simulatePressure) {
      if (quality == .high && options.isComplete) {
        getPolygon(quality: quality); // remembers it in [points]
        line = skipPoints(points, quality.N);
      } else {
        line = List.of(line);
        getStroke(line, options: pieceOptions, rememberSimulatedPressure: true);
      }
    }

    return [
      for (final piece in splitIntoPieces(line, [
        for (final length in lineStyle.pattern) length * options.size,
      ], offset: lineStyleOffset))
        getStroke(
          piece,
          options: pieceOptions.copyWith(simulatePressure: false),
        ),
    ];
  }

  /// Splits the line through [points] into the pieces that [pattern] draws:
  /// lengths alternately drawn and skipped, starting with a drawn one, from
  /// [offset] into the pattern. A drawn length of 0 gives a dot (two equal
  /// points).
  @visibleForTesting
  static List<List<PointVector>> splitIntoPieces(
    List<PointVector> points,
    List<double> pattern, {
    double offset = 0,
  }) {
    assert(pattern.length.isEven, 'pattern must end with a skipped length');
    assert(
      [for (var i = 1; i < pattern.length; i += 2) pattern[i]]
          .every((gap) => gap > 0),
      'skipped lengths must be positive',
    );
    if (points.isEmpty || pattern.isEmpty) return [points];

    final pieces = <List<PointVector>>[];
    var patternIndex = 0;
    var remaining = pattern[0];
    bool isDrawing() => patternIndex.isEven;

    // Skip [offset] into the pattern.
    var skip = offset % pattern.sum;
    while (skip > 0 && skip >= remaining) {
      skip -= remaining;
      patternIndex = (patternIndex + 1) % pattern.length;
      remaining = pattern[patternIndex];
    }
    remaining -= skip;
    var piece = <PointVector>[if (isDrawing()) points.first];

    for (var i = 1; i < points.length; i++) {
      var from = points[i - 1];
      final to = points[i];
      var segmentLength = (to - from).distance;

      while (segmentLength > remaining) {
        final split = from.lerp(remaining / segmentLength, to);
        if (isDrawing()) {
          // A dash that ended exactly on a point already has its end;
          // a dot (one point so far) needs its second one.
          if (remaining > 0 || piece.length < 2) piece.add(split);
          pieces.add(piece);
        } else {
          piece = [split];
        }
        segmentLength -= remaining;
        from = split;
        patternIndex = (patternIndex + 1) % pattern.length;
        remaining = pattern[patternIndex];
      }

      remaining -= segmentLength;
      if (isDrawing()) piece.add(to);
    }
    // The last dash, unless it only just started.
    if (isDrawing() && piece.length >= 2) pieces.add(piece);
    return pieces;
  }

  /// One path with each of [pieces], see [getPath].
  Path _piecesPath(List<List<Offset>> pieces, {bool smooth = true}) {
    final path = Path();
    for (final piece in pieces) {
      if (piece.isEmpty) continue;
      path.addPath(getPath(piece, smooth: smooth), .zero);
    }
    return path;
  }

  /// Returns a [Path] that represents the stroke.
  ///
  /// If [smooth] is true, and the stroke is complete,
  /// the path will be a smooth curve between the points in [polygon].
  ///
  /// Otherwise, the path will use straight lines between each point
  /// in [polygon] for performance.
  @protected
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    if (smooth && options.isComplete) {
      return smoothPathFromPolygon(polygon);
    }

    return Path()..addPolygon(polygon, true);
  }

  /// Returns a list with every Nth point in [points].
  static List<PointVector> skipPoints(List<PointVector> points, int N) {
    // Nothing is being skipped, just return [points].
    if (N <= 1) return points;

    // If we have too few points, skip less points
    final divided = points.length / N;
    const minDivided = 8;
    if (divided < minDivided) {
      N = (N * divided / minDivided).floor();
      if (N <= 1) return points;
    }

    return [
      for (int i = 0; i < points.length - 1; i += N) points[i],
      points.last,
    ];
  }

  static Path smoothPathFromPolygon(List<Offset> polygon) {
    final path = Path();
    path.moveTo(polygon.first.dx, polygon.first.dy);
    for (int i = 1; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      final mid = (p1 + p2) / 2;
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  String toSvgPath() {
    String toSvgPoint(Offset point) {
      return '${point.dx} '
          '${page.size.height - point.dy}';
    }

    String toSvgOutline(List<Offset> polygon) {
      // Remove NaN points, and convert to SVG coordinates
      final svgPoints = polygon
          .where((offset) => offset.isFinite)
          .map(toSvgPoint);
      return svgPoints.isNotEmpty ? 'M${svgPoints.join('L')}' : '';
    }

    if (isInPieces) {
      return highQualityPieces
          .map(toSvgOutline)
          .where((p) => p.isNotEmpty)
          .join(' ');
    }
    return toSvgOutline(highQualityPolygon);
  }

  double get maxY {
    return points.isEmpty ? 0 : points.map((point) => point.y).reduce(max);
  }

  RecognizedUnistroke? detectShape() {
    if (points.length < 3) return null;
    return recognizeUnistroke(points);
  }

  /// Uses the one_dollar_unistroke_recognizer package
  /// only to recognize straight lines.
  ///
  /// In addition, the line must be sufficiently long
  /// relative to [options.size].
  bool isStraightLine([int minLength = 5]) {
    if (points.length < 3) return false;

    final recognized = recognizeUnistroke(
      points,
      overrideReferenceUnistrokes: default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(),
    );
    if (recognized == null) return false;
    assert(recognized.name == DefaultUnistrokeNames.line);
    if (recognized.score < 0.7) return false;

    final sqrLength = points.first.distanceSquaredTo(points.last);
    final sqrMinLength = minLength * minLength * options.size * options.size;
    return sqrLength >= sqrMinLength;
  }

  /// Replaces the points in this stroke with a straight line.
  ///
  /// If the resulting line is close to horizontal or vertical,
  /// it will be snapped to be exactly horizontal or vertical.
  void convertToLine() {
    assert(points.length >= 2);

    // Use the average pressure
    final pressure = points.map((point) => point.pressure ?? 0.5).average;
    var firstPoint = PointVector.fromOffset(
      offset: points.first,
      pressure: pressure,
    );
    var lastPoint = PointVector.fromOffset(
      offset: points.last,
      pressure: pressure,
    );

    // Snap to the horizontal or vertical axis
    (firstPoint, lastPoint) = snapLine(firstPoint, lastPoint);

    points.clear();
    points.add(firstPoint);
    points.add(lastPoint);
    points.add(lastPoint);
    options.isComplete = true;
    options.start.taperEnabled = false;
    options.end.taperEnabled = false;
  }

  /// Snaps a line to either horizontal or vertical
  /// if the angle is close enough.
  static (PointVector firstPoint, PointVector lastPoint) snapLine(
    PointVector firstPoint,
    PointVector lastPoint,
  ) {
    final dx = (lastPoint.dx - firstPoint.dx).abs();
    final dy = (lastPoint.dy - firstPoint.dy).abs();
    final angle = atan2(dy, dx);

    const snapAngle = 5 * pi / 180; // 5 degrees
    if (angle < snapAngle) {
      // snap to horizontal
      return (
        firstPoint,
        PointVector(lastPoint.dx, firstPoint.dy, lastPoint.pressure),
      );
    } else if (angle > pi / 2 - snapAngle) {
      // snap to vertical
      return (
        firstPoint,
        PointVector(firstPoint.dx, lastPoint.dy, lastPoint.pressure),
      );
    } else {
      return (firstPoint, lastPoint);
    }
  }

  Stroke copy() => Stroke(
    color: color,
    pressureEnabled: pressureEnabled,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
    lineStyle: lineStyle,
    lineStyleOffset: lineStyleOffset,
  )..points.addAll(points);
}

enum StrokeQuality(
  /// We use every Nth point for this quality level.
  final int N,
) {
  low(4),
  high(1),
}
