import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

/// What's open next to the note being edited: another note (which can be
/// written in too) or a PDF, see [SideBySidePane].
class SideBySide extends ChangeNotifier {
  /// The second pane takes this fraction of the space, at least and at most.
  static const minFraction = 0.2, maxFraction = 0.8;

  /// The note's path (without extension) or the PDF's file, if open.
  String? get path => _path;
  String? _path;

  /// Whether [path] is a PDF file rather than a note.
  bool get isPdf => _isPdf;
  var _isPdf = false;

  /// Whether the second pane can't be scrolled or zoomed.
  bool get lockPosition => _lockPosition;
  var _lockPosition = false;
  set lockPosition(bool lockPosition) {
    _lockPosition = lockPosition;
    notifyListeners();
  }

  /// Whether the note in the second pane can be written in.
  bool get writable => _writable;
  var _writable = false;
  set writable(bool writable) {
    _writable = writable;
    notifyListeners();
  }

  /// How much of the space the second pane takes.
  double get fraction => stows.sideBySideFraction.value;
  set fraction(double fraction) {
    stows.sideBySideFraction.value = fraction.clamp(minFraction, maxFraction);
    notifyListeners();
  }

  void openNote(String path) => _open(path, isPdf: false);
  void openPdf(String path) => _open(path, isPdf: true);

  void _open(String path, {required bool isPdf}) {
    _path = path;
    _isPdf = isPdf;
    _lockPosition = false;
    _writable = false;
    notifyListeners();
  }

  void close() {
    _path = null;
    notifyListeners();
  }
}

/// The second pane of [SideBySide]: a bar with its name and toggles, and
/// the note (an [Editor] using the main editor's tools) or PDF.
class SideBySidePane extends StatefulWidget {
  const new({
    super.key,
    required this.sideBySide,
    required this.getTool,
    required this.setTool,
    required this.changed,
  });

  final SideBySide sideBySide;

  /// The main editor's tool, used in the note here too.
  final Tool Function() getTool;
  final ValueChanged<Tool> setTool;

  /// See [EditorEmbedding.changed].
  final VoidCallback changed;

  @override
  State<SideBySidePane> createState() => _SideBySidePaneState();
}

class _SideBySidePaneState extends State<SideBySidePane> {
  /// The note's editor, for its undo and redo; a new one for each note.
  var _editorKey = GlobalKey<EditorState>();
  String? _editorPath;

  @override
  Widget build(BuildContext context) {
    final sideBySide = widget.sideBySide;
    final path = sideBySide.path!;
    if (path != _editorPath) {
      _editorPath = path;
      _editorKey = GlobalKey<EditorState>();
    }
    final strings = t.editor.sideBySide;
    final colorScheme = ColorScheme.of(context);

    return Material(
      color: colorScheme.surfaceContainer,
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.basename(path),
                  overflow: .ellipsis,
                  style: TextTheme.of(context).titleSmall,
                ),
              ),
              IconButton(
                tooltip: strings.lockPosition,
                isSelected: sideBySide.lockPosition,
                onPressed: () =>
                    sideBySide.lockPosition = !sideBySide.lockPosition,
                icon: const Icon(Icons.lock_open),
                selectedIcon: const Icon(Icons.lock),
              ),
              if (!sideBySide.isPdf) ...[
                IconButton(
                  tooltip: strings.write,
                  isSelected: sideBySide.writable,
                  onPressed: () => sideBySide.writable = !sideBySide.writable,
                  icon: const Icon(Icons.edit_off),
                  selectedIcon: const Icon(Icons.edit),
                ),
                if (sideBySide.writable) ...[
                  IconButton(
                    tooltip: t.editor.toolbar.undo,
                    onPressed: () => _editorKey.currentState?.undo(),
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: t.editor.toolbar.redo,
                    onPressed: () => _editorKey.currentState?.redo(),
                    icon: const Icon(Icons.redo),
                  ),
                ],
              ],
              IconButton(
                tooltip: strings.close,
                onPressed: sideBySide.close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(
            child: ClipRect(
              child: sideBySide.isPdf
                  ? PdfViewer.file(
                      path,
                      // Locked: no dragging, pinching, mouse wheel or keys.
                      params: sideBySide.lockPosition
                          ? const PdfViewerParams(
                              panEnabled: false,
                              scaleEnabled: false,
                              scrollByMouseWheel: null,
                              enableKeyboardNavigation: false,
                            )
                          : const PdfViewerParams(),
                    )
                  : Editor(
                      key: _editorKey,
                      path: path,
                      embedding: EditorEmbedding(
                        getTool: widget.getTool,
                        setTool: widget.setTool,
                        changed: widget.changed,
                        lockPosition: sideBySide.lockPosition,
                        writable: sideBySide.writable,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
