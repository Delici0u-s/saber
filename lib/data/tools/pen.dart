import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
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

  /// Replaces [rawStroke] with the recognized [shape] (one that can be
  /// edited as a shape, see [StrokeShape]), keeping the stroke's color,
  /// options, tool and line style.
  static Stroke toShape(Stroke rawStroke, RecognizedUnistroke shape) {
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
        return shapeStroke(
          rawStroke,
          PathShape.polygon([
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ]),
        );
      case DefaultUnistrokeNames.circle:
        final (center, radius) = shape.convertToCircle();
        log.info('Detected circle: c=$center, r=$radius');
        return shapeStroke(
          rawStroke,
          EllipseShape(
            center: center,
            u: Offset(radius, 0),
            v: Offset(0, radius),
          ),
        );
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        final polygon = [...shape.convertToCanonicalPolygon()];
        log.info('Detected ${shape.name}');
        // Without the last corner if it's the first again.
        if (polygon.length > 1 && polygon.first == polygon.last) {
          polygon.removeLast();
        }
        return shapeStroke(rawStroke, PathShape.polygon(polygon));
    }
  }

  /// A stroke along [shape], like [stroke] (its colour, options, tool, line
  /// style and tape), e.g. [stroke] reshaped.
  static Stroke shapeStroke(Stroke stroke, StrokeShape shape) => Stroke(
    color: stroke.color,
    pressureEnabled: stroke.pressureEnabled,
    options: stroke.options.copyWith(),
    pageIndex: stroke.pageIndex,
    page: stroke.page,
    toolId: stroke.toolId,
    lineStyle: stroke.lineStyle,
    isTape: stroke.isTape,
  )..setShape(shape);

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
