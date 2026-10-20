import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/stroke_shape.dart';
import 'package:saber/data/editor/selection_transform.dart';

class SelectResult {
  int pageIndex;
  final List<Stroke> strokes;
  final List<EditorImage> images;
  Path path;

  /// The page the selection was made on, before any move to another page.
  int pageIndexStart;

  /// The box with handles around what's selected, once selecting is done
  /// and something is selected.
  SelectionBox? box;

  /// Whether only what's completely inside [path] is selected (see
  /// [SelectBox.selectsTouching]), shown by a solid outline while selecting.
  var selectsWhole = false;

  /// What made the selection (an editor), as the selection tools are shared
  /// by every editor (e.g. two notes side by side).
  Object? owner;

  SelectResult({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.path,
    required this.pageIndexStart,
  });

  /// The shape selected, if the selection is a single shape (which then
  /// gets handles to reshape it, see [ShapeHandles]).
  StrokeShape? get shape => strokes.length == 1 && images.isEmpty
      ? StrokeShape.of(strokes.single)
      : null;

  bool get isEmpty {
    return strokes.isEmpty && images.isEmpty;
  }

  SelectResult copyWith({
    int? pageIndex,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    Path? path,
    int? pageIndexStart,
  }) {
    return SelectResult(
      pageIndex: pageIndex ?? this.pageIndex,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      path: path ?? this.path,
      pageIndexStart: pageIndexStart ?? this.pageIndexStart,
    )..owner = owner;
  }
}
