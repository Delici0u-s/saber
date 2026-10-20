import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  /// Scales the selected strokes' widths by a factor, relative to their
  /// widths when the slider was grabbed; [finishThickness] when it's let go.
  final ValueChanged<double> changeThickness;
  final VoidCallback finishThickness;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.changeThickness,
    required this.finishThickness,
  });

  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: ColorScheme.of(context).secondary,
      backgroundColor: Colors.transparent,
      shape: const CircleBorder(),
    );
    return Flex(
      direction: axis,
      mainAxisAlignment: .center,
      mainAxisSize: .min,
      children: [
        IconButton(
          onPressed: duplicateSelection,
          style: buttonStyle,
          tooltip: t.editor.selectionBar.duplicate,
          icon: const AdaptiveIcon(
            icon: Icons.content_copy,
            cupertinoIcon: CupertinoIcons.doc_on_clipboard,
          ),
        ),
        IconButton(
          onPressed: deleteSelection,
          style: buttonStyle,
          tooltip: t.editor.selectionBar.delete,
          icon: const AdaptiveIcon(
            icon: Icons.delete,
            cupertinoIcon: CupertinoIcons.delete,
          ),
        ),
        _ThicknessSlider(
          axis: axis,
          change: changeThickness,
          finish: finishThickness,
        ),
      ],
    );
  }
}

/// A slider from [_minFactor] to [_maxFactor] times the selection's
/// thickness, back in the middle (×1) whenever it's let go.
class _ThicknessSlider extends StatefulWidget {
  const new({required this.axis, required this.change, required this.finish});

  final Axis axis;
  final ValueChanged<double> change;
  final VoidCallback finish;

  static const _minFactor = 0.5, _maxFactor = 3.0;

  @override
  State<_ThicknessSlider> createState() => _ThicknessSliderState();
}

class _ThicknessSliderState extends State<_ThicknessSlider> {
  /// The factor's logarithm, so ×0.5 and ×2 are as far from ×1.
  var _logFactor = 0.0;

  double get _factor => exp(_logFactor);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final horizontal = widget.axis == Axis.horizontal;
    return Flex(
      direction: widget.axis,
      mainAxisSize: .min,
      children: [
        Column(
          children: [
            Text(
              t.editor.selectionBar.thickness,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1,
              ),
            ),
            Text('×${_factor.toStringAsFixed(1)}'),
          ],
        ),
        RotatedBox(
          quarterTurns: horizontal ? 0 : 1,
          child: SizedBox(
            width: SizePicker.largeLength,
            child: Slider(
              min: log(_ThicknessSlider._minFactor),
              max: log(_ThicknessSlider._maxFactor),
              value: _logFactor,
              onChanged: (logFactor) {
                setState(() => _logFactor = logFactor);
                widget.change(_factor);
              },
              onChangeEnd: (_) {
                widget.finish();
                setState(() => _logFactor = 0);
              },
            ),
          ),
        ),
      ],
    );
  }
}
