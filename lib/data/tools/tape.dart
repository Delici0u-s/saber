import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

/// Draws tape: straight opaque strips that hide what's under them until
/// tapped, for learning (see [Stroke.isTape]). Picked in the highlighter's
/// tab, and as wide as the highlighter.
class Tape extends Pen {
  new()
    : super(
        name: t.editor.pens.tape,
        sizeMin: _highlighter.sizeMin,
        sizeMax: _highlighter.sizeMax,
        sizeStep: _highlighter.sizeStep,
        icon: tapeIcon,
        options: _highlighter.options,
        pressureEnabled: false,
        color: _highlighter.color.withValues(alpha: 1),
        // As the highlighter, so the toolbar and the next launch treat it
        // as the highlighter's tab.
        toolId: .highlighter,
      );

  static Pen get _highlighter => Highlighter.currentHighlighter;

  static var currentTape = Tape();

  static const tapeIcon = FontAwesomeIcons.tape;

  /// The highlighter or tape, whichever was picked last in the
  /// highlighter's tab.
  static Pen get highlighterTab =>
      stows.lastHighlighterTabIsTape.value ? currentTape : _highlighter;

  /// Saved like a shape pen's stroke: other Saber versions then draw it
  /// opaque and above handwriting (see [ToolId]'s order).
  @override
  ToolId get strokeToolId => .shapePen;

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    super.onDragStart(position, page, pageIndex, pressure);
    Pen.currentStroke?.isTape = true;
  }

  /// The tape as drawn (or the shape it was held into), or null for a tap
  /// (which opens or closes tape instead, see [Stroke.tapeRevealed]).
  @override
  Stroke? onDragEnd() {
    final stroke = super.onDragEnd();
    if (stroke == null || stroke.isDot) return null;
    return stroke;
  }
}
