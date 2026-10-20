import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/select_result.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:saber/data/tools/select_lasso.dart';

abstract class Select extends Tool {
  /// The selection tool chosen last (lasso or box), remembered across launches.
  static Select get current => stows.lastSelectBoxMode.value
      ? SelectBox.currentSelect
      : SelectLasso.currentSelect;
  static set current(Select select) =>
      stows.lastSelectBoxMode.value = select is SelectBox;

  /// The icon representing this selection mode.
  IconData get icon;

  var selectResult = SelectResult(
    pageIndex: -1,
    strokes: const [],
    images: const [],
    path: Path(),
    pageIndexStart: -1,
  );
  var doneSelecting = false;

  void unselect() {}

  Color? getDominantStrokeColor() {
    return null;
  }

  void onDragStart(Offset position, int pageIndex);

  void onDragUpdate(Offset position);

  void onDragEnd(List<Stroke> strokes, List<EditorImage> images);

  /// Selects what's at [position] on page [pageIndex], as if selected
  /// around it: the nearest of [strokes] within [reach] (the one on top, if
  /// several are as near), else the image on top there. Returns whether
  /// anything was.
  bool selectAt(
    Offset position,
    int pageIndex,
    List<Stroke> strokes,
    List<EditorImage> images, {
    required double reach,
  }) {
    Stroke? nearest;
    var nearestDistance = reach;
    for (final stroke in strokes.reversed) {
      final distance = distanceToStroke(position, stroke);
      if (distance > nearestDistance) continue;
      if (nearest != null && distance == nearestDistance) continue;
      nearest = stroke;
      nearestDistance = distance;
    }
    final image = nearest == null
        ? images.lastWhereOrNull((image) => image.dstRect.contains(position))
        : null;
    if (nearest == null && image == null) return false;

    final bounds = nearest?.lowQualityPath.getBounds() ?? image!.dstRect;
    selectResult = SelectResult(
      pageIndex: pageIndex,
      strokes: [?nearest],
      images: [?image],
      path: Path()..addRect(bounds),
      pageIndexStart: pageIndex,
    );
    doneSelecting = true;
    return true;
  }

  /// How far [point] is from [stroke]'s outline: 0 on it.
  static double distanceToStroke(Offset point, Stroke stroke) {
    if (stroke.lowQualityPath.contains(point)) return 0;
    final polygon = stroke.lowQualityPolygon;
    var nearest = double.infinity;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i], b = polygon[(i + 1) % polygon.length];
      final ab = b - a;
      final t = ab == Offset.zero
          ? 0.0
          : (((point - a).dx * ab.dx + (point - a).dy * ab.dy) /
                    ab.distanceSquared)
                .clamp(0.0, 1.0);
      nearest = min(nearest, (point - (a + ab * t)).distance);
    }
    return nearest;
  }
}
