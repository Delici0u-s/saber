import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/tool_mode_button.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/select_box.dart';
import 'package:saber/data/tools/select_lasso.dart';
import 'package:saber/i18n/strings.g.dart';

/// Lets the user pick the selection mode (lasso or box).
class SelectModal extends StatelessWidget {
  const new({super.key, required this.setTool});

  final void Function(Tool) setTool;

  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final modes = <(Select, String)>[
      (SelectLasso.currentSelect, t.editor.selectOptions.lassoSelect),
      (SelectBox.currentSelect, t.editor.selectOptions.boxSelect),
    ];

    return ListenableBuilder(
      listenable: stows.lastSelectBoxMode,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Flex(
          direction: axis,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            for (final (select, tooltip) in modes)
              ToolModeButton(
                selected: Select.current == select,
                tooltip: tooltip,
                onPressed: () {
                  Select.current = select;
                  setTool(select);
                },
                icon: Icon(select.icon),
              ),
          ],
        ),
      ),
    );
  }
}
