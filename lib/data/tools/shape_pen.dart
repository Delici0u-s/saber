import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class ShapePen extends Pen {
  new()
    : super(
        name: t.editor.pens.shapePen,
        sizeMin: 1,
        sizeMax: 25,
        sizeStep: 1,
        icon: shapePenIcon,
        options: stows.lastShapePenOptions.value,
        pressureEnabled: false,
        color: Color(stows.lastShapePenColor.value),
        toolId: .shapePen,
      );

  static const shapePenIcon = FontAwesomeIcons.shapes;

  /// The shape pen previews shapes continuously instead.
  @override
  bool get holdsToShape => false;

  void _detectShape() {
    Pen.detectedShape = Pen.currentStroke?.detectShape();
  }

  static Timer? _detectShapeDebouncer;
  static var debounceDuration = getDebounceFromPref();
  static Duration getDebounceFromPref() {
    assert(stows.shapeRecognitionDelay.loaded);
    final ms = stows.shapeRecognitionDelay.value;
    if (ms < 0) {
      return const Duration(hours: 1);
    } else {
      return Duration(milliseconds: ms);
    }
  }

  @override
  void onDragUpdate(Offset position, double? pressure) {
    super.onDragUpdate(position, pressure);

    final isPreviewEnabled = debounceDuration < const Duration(hours: 1);
    final isTimerActive = _detectShapeDebouncer?.isActive ?? false;
    if (isPreviewEnabled && !isTimerActive) {
      _detectShapeDebouncer = Timer(debounceDuration, _detectShape);
    }
  }

  @override
  Stroke? onDragEnd() {
    _detectShapeDebouncer?.cancel();
    _detectShapeDebouncer = null;
    _detectShape();
    return super.onDragEnd();
  }
}
