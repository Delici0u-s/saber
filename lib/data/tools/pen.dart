import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/line_style.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';
import 'package:stow_plain/stow_plain.dart';

class Pen extends Tool {
  @protected
  @visibleForTesting
  new({
    required this.name,
    required this.sizeMin,
    required this.sizeMax,
    required this.sizeStep,
    required this.icon,
    required this.options,
    required this.pressureEnabled,
    required this.color,
    required this.toolId,
    this.lineStyleStow,
    this.opacityStow,
  });

  new fountainPen()
    : name = t.editor.pens.fountainPen,
      sizeMin = 1,
      sizeMax = 25,
      sizeStep = 1,
      icon = fountainPenIcon,
      options = stows.lastFountainPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastFountainPenColor.value),
      toolId = .fountainPen,
      lineStyleStow = stows.lastFountainPenLineStyle,
      opacityStow = stows.lastFountainPenOpacity;

  new ballpointPen()
    : name = t.editor.pens.ballpointPen,
      sizeMin = 1,
      sizeMax = 25,
      sizeStep = 1,
      icon = ballpointPenIcon,
      options = stows.lastBallpointPenOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastBallpointPenColor.value),
      toolId = .ballpointPen,
      lineStyleStow = stows.lastBallpointPenLineStyle,
      opacityStow = stows.lastBallpointPenOpacity;

  final String name;
  final double sizeMin, sizeMax, sizeStep;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();
  final Object icon;

  @override
  final ToolId toolId;

  static const fountainPenIcon = FontAwesomeIcons.penFancy;
  static const ballpointPenIcon = FontAwesomeIcons.pen;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;

  /// Where this pen's [lineStyle] is saved,
  /// or null if this pen only draws solid lines.
  final PlainStow<String>? lineStyleStow;

  /// How this pen's strokes are drawn along their length.
  LineStyle get lineStyle => .fromJson(lineStyleStow?.value);
  set lineStyle(LineStyle lineStyle) => lineStyleStow?.value = lineStyle.name;

  /// Where this pen's [opacity] is saved,
  /// or null if this pen's strokes are as opaque as its [color].
  final PlainStow<double>? opacityStow;

  /// How opaque this pen's strokes are, from 0 to 1, on top of [color]'s
  /// own opacity (e.g. the highlighter's).
  double get opacity => opacityStow?.value ?? 1;
  set opacity(double opacity) => opacityStow?.value = opacity;

  static var _currentPen = Pen.fountainPen();
  static Pen get currentPen => _currentPen;
  static set currentPen(Pen currentPen) {
    assert(
      currentPen is! Highlighter,
      'Use Highlighter.currentHighlighter instead',
    );
    assert(currentPen is! Pencil, 'Use Pencil.currentPencil instead');
    _currentPen = currentPen;
  }

  static final log = Logger('Pen');

  /// The shape recognized in [currentStroke], previewed while drawing and
  /// applied when the stroke ends. Set by the shape pen, or by holding any
  /// other pen still for [Stows.holdToShapeDelay] ("hold to shape").
  static RecognizedUnistroke? detectedShape;

  /// Called when [detectedShape] changes while the pen isn't moving,
  /// so the preview can be redrawn.
  static VoidCallback? onDetectedShapeChanged;

  /// Whether holding this pen still turns the stroke into a shape.
  @protected
  bool get holdsToShape => true;

  /// The tool the strokes drawn are saved as, usually this one.
  ToolId get strokeToolId => toolId;

  static Timer? _holdTimer;

  /// Where the pen has been held since the hold timer started.
  static Offset? _holdPosition;

  /// Restarts the hold-to-shape timer unless the pen stayed within the stroke
  /// width of where it's held. Moving again cancels a recognized shape.
  void _watchForHold(Offset position) {
    final delay = stows.holdToShapeDelay.value;
    if (!holdsToShape || delay < 0) return;

    final holdPosition = _holdPosition;
    if (holdPosition != null &&
        (position - holdPosition).distance <= options.size) {
      return;
    }

    if (detectedShape != null) {
      detectedShape = null;
      onDetectedShapeChanged?.call();
    }
    _holdPosition = position;
    _holdTimer?.cancel();
    _holdTimer = Timer(Duration(milliseconds: delay), () {
      final shape = currentStroke?.detectShape();
      if (shape?.name == null) return;
      detectedShape = shape;
      onDetectedShapeChanged?.call();
    });
  }

  static void _stopWatchingForHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdPosition = null;
  }

  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    _stopWatchingForHold();
    detectedShape = null;
    currentStroke = Stroke(
      color: color.withValues(alpha: color.a * opacity),
      pressureEnabled: pressureEnabled,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: strokeToolId,
      lineStyle: lineStyle,
    );
    onDragUpdate(position, pressure);
  }

  void onDragUpdate(Offset position, double? pressure) {
    currentStroke?.addPoint(position, pressure);
    _watchForHold(position);
  }

  Stroke? onDragEnd() {
    _stopWatchingForHold();
    final shape = detectedShape;
    detectedShape = null;

    final stroke = currentStroke;
    currentStroke = null;
    if (stroke == null) return null;

    stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();
    return shape == null ? stroke : toShape(stroke, shape);
  }

  /// Replaces [rawStroke] with the recognized [shape],
  /// keeping the stroke's color, options, tool and line style.
  static Stroke toShape(Stroke rawStroke, RecognizedUnistroke shape) {
    final lineStyle = rawStroke.lineStyle;
    switch (shape.name) {
      case null:
        log.info('Detected unknown shape');
        return rawStroke;
      case DefaultUnistrokeNames.line:
        log.info('Detected line');
        return rawStroke..convertToLine();
      case DefaultUnistrokeNames.rectangle:
        final rect = shape.convertToRect();
        log.info('Detected rectangle: $rect');
        // A styled one (or tape) is drawn along its outline, in dashes or
        // dots.
        if (lineStyle != .solid || rawStroke.isTape) {
          return outlineStroke(rawStroke, [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
            rect.topLeft,
          ]);
        }
        return RectangleStroke(
          color: rawStroke.color,
          pressureEnabled: rawStroke.pressureEnabled,
          options: rawStroke.options,
          pageIndex: rawStroke.pageIndex,
          page: rawStroke.page,
          toolId: rawStroke.toolId,
          rect: rect,
        );
      case DefaultUnistrokeNames.circle:
        final (center, radius) = shape.convertToCircle();
        log.info('Detected circle: c=$center, r=$radius');
        if (lineStyle != .solid || rawStroke.isTape) {
          return outlineStroke(
            rawStroke,
            circleOutline(center, radius, rawStroke.options.size),
          );
        }
        return CircleStroke(
          color: rawStroke.color,
          pressureEnabled: rawStroke.pressureEnabled,
          options: rawStroke.options,
          pageIndex: rawStroke.pageIndex,
          page: rawStroke.page,
          toolId: rawStroke.toolId,
          radius: radius,
          center: center,
        );
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        final polygon = shape.convertToCanonicalPolygon();
        log.info('Detected ${shape.name}');
        return outlineStroke(rawStroke, polygon);
    }
  }

  /// A circle drawn along its outline has at least this many points, so
  /// a small one stays round.
  static const _minCirclePoints = 16;

  /// Points around a circle, about [strokeSize] apart like a drawn circle's,
  /// ending where they start.
  static List<Offset> circleOutline(
    Offset center,
    double radius,
    double strokeSize,
  ) {
    final count = max(_minCirclePoints, (2 * pi * radius / strokeSize).ceil());
    return [
      for (var i = 0; i <= count; i++)
        center + Offset.fromDirection(2 * pi * i / count, radius),
    ];
  }

  /// A stroke through [outline], like [rawStroke] (with its line style),
  /// but without tapers or streamlining, which would round its corners.
  static Stroke outlineStroke(Stroke rawStroke, List<Offset> outline) {
    final StrokeOptions(:start, :end) = rawStroke.options;
    final options = rawStroke.options.copyWith(
      streamline: 0,
      // Copies: the ends are shared with the pen's options.
      start: start.copyWith(
        taperEnabled: false,
        customTaper: start.customTaper,
      ),
      end: end.copyWith(taperEnabled: false, customTaper: end.customTaper),
    );
    return Stroke(
      color: rawStroke.color,
      pressureEnabled: rawStroke.pressureEnabled,
      options: options,
      pageIndex: rawStroke.pageIndex,
      page: rawStroke.page,
      toolId: rawStroke.toolId,
      lineStyle: rawStroke.lineStyle,
      isTape: rawStroke.isTape,
    )..addPoints(outline);
  }

  /// The default stroke options.
  ///
  /// Note that these are different to the default options in [StrokeOptions]
  /// e.g. [StrokeOptions.defaultSize] for historical reasons
  /// (i.e. [StrokeOptions.toJson] does not include default values.)
  static final defaultOptions = StrokeOptions(size: 5);

  static StrokeOptions get fountainPenOptions => defaultOptions.copyWith();
  static StrokeOptions get ballpointPenOptions => defaultOptions.copyWith();
  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get highlighterOptions =>
      defaultOptions.copyWith(size: 50);
  static StrokeOptions get pencilOptions => defaultOptions.copyWith(
    streamline: 0.1,
    start: StrokeEndOptions.start(taperEnabled: true, customTaper: 1),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 1),
  );
}
