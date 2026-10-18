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
}
