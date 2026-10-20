import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/select_result.dart';
import 'package:saber/data/tools/select.dart';
import 'package:sbn/tool_id.dart';

class SelectBox extends Select {
  SelectBox._();

  static final _currentSelect = SelectBox._();
  static SelectBox get currentSelect => _currentSelect;

  Offset lastOffset = Offset.zero;
  Offset firstOffset = Offset.zero;

  @override
  ToolId get toolId => .select;

  @override
  IconData get icon => Symbols.select;

  @override
  void unselect() {
    doneSelecting = false;
    selectResult.pageIndex = -1;
    selectResult.box = null;
  }

  @override
  Color? getDominantStrokeColor() {
    if (!doneSelecting) return null;
    if (selectResult.strokes.isEmpty) return null;

    final colorDistribution = <Color, int>{};
    for (final stroke in selectResult.strokes) {
      colorDistribution.update(
        stroke.color,
        (value) => value + stroke.length,
        ifAbsent: () => stroke.length,
      );
    }
    assert(colorDistribution.isNotEmpty);

    return colorDistribution.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
  }

  @override
  void onDragStart(Offset position, int pageIndex) {
    doneSelecting = false;
    firstOffset = position;
    selectResult = SelectResult(
      pageIndex: pageIndex,
      strokes: [],
      images: [],
      path: Path(),
      pageIndexStart: pageIndex,
    );
    onDragUpdate(position);
  }

  @override
  void onDragUpdate(Offset position) {
    lastOffset = position;
    selectResult.selectsWhole = !selectsTouching;
    selectResult.path = Path();
    selectResult.path.moveTo(firstOffset.dx, firstOffset.dy);
    selectResult.path.lineTo(lastOffset.dx, firstOffset.dy);
    selectResult.path.lineTo(lastOffset.dx, lastOffset.dy);
    selectResult.path.lineTo(firstOffset.dx, lastOffset.dy);
    selectResult.path.close();
  }

  /// Whether the box selects everything it touches: when dragged from right
  /// to left (else only what's completely inside it), like in CAD programs.
  bool get selectsTouching => lastOffset.dx < firstOffset.dx;

  /// Selects the [strokes] and [images] in the box, see [selectsTouching].
  @override
  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path = Path();
    selectResult.path.moveTo(firstOffset.dx, firstOffset.dy);
    selectResult.path.lineTo(lastOffset.dx, firstOffset.dy);
    selectResult.path.lineTo(lastOffset.dx, lastOffset.dy);
    selectResult.path.lineTo(firstOffset.dx, lastOffset.dy);
    selectResult.path.close();
    doneSelecting = true;

    final box = Rect.fromPoints(firstOffset, lastOffset);
    final touching = selectsTouching;
    for (final stroke in strokes) {
      final polygon = stroke.lowQualityPolygon;
      if (polygon.isEmpty) continue;
      if (touching ? touches(box, polygon) : polygon.every(box.contains)) {
        selectResult.strokes.add(stroke);
      }
    }
    for (final image in images) {
      final rect = image.dstRect;
      if (touching ? box.overlaps(rect) : box.intersect(rect) == rect) {
        selectResult.images.add(image);
      }
    }
  }

  /// Whether [polygon] (a closed outline) has a point in [box] or a side
  /// crossing it.
  static bool touches(Rect box, List<Offset> polygon) {
    if (polygon.any(box.contains)) return true;
    for (var i = 0; i < polygon.length; i++) {
      if (_segmentCrosses(box, polygon[i], polygon[(i + 1) % polygon.length])) {
        return true;
      }
    }
    return false;
  }

  /// Whether the line from [a] to [b] passes through [box] (clipping it to
  /// the box, Liang–Barsky).
  static bool _segmentCrosses(Rect box, Offset a, Offset b) {
    final d = b - a;
    var t0 = 0.0, t1 = 1.0;
    for (final (p, q) in [
      (-d.dx, a.dx - box.left),
      (d.dx, box.right - a.dx),
      (-d.dy, a.dy - box.top),
      (d.dy, box.bottom - a.dy),
    ]) {
      if (p == 0) {
        if (q < 0) return false;
        continue;
      }
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
    }
    return true;
  }
}
