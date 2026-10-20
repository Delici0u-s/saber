import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/i18n/strings.g.dart';

class EditorPageManager extends StatefulWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.redrawAndSave,
    required this.insertPageAfter,
    required this.duplicatePage,
    required this.clearPage,
    required this.rotatePage,
    required this.stretchPage,
    required this.deletePage,
    required this.transformationController,
  });

  final EditorCoreInfo coreInfo;
  final int? currentPageIndex;
  final VoidCallback redrawAndSave;

  final void Function(int) insertPageAfter;
  final void Function(int) duplicatePage;
  final void Function(int) clearPage;
  final void Function(int) rotatePage;
  final void Function(int) stretchPage;
  final void Function(int) deletePage;

  final TransformationController transformationController;

  @override
  State<EditorPageManager> createState() => _EditorPageManagerState();
}

class _EditorPageManagerState extends State<EditorPageManager> {
  void scrollToPage(int pageIndex) => CanvasGestureDetector.scrollToPage(
    pageIndex: pageIndex,
    pages: widget.coreInfo.pages,
    screenWidth: MediaQuery.sizeOf(context).width,
    transformationController: widget.transformationController,
  );

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cupertino = platform.isCupertino;
    return SizedBox(
      width: cupertino ? null : 300,
      height: cupertino ? 600 : null,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: widget.coreInfo.pages.length,
        itemBuilder: (context, pageIndex) {
          final isEmptyLastPage =
              pageIndex == widget.coreInfo.pages.length - 1 &&
              widget.coreInfo.pages[pageIndex].isEmpty;
          return InkWell(
            key: ValueKey(pageIndex),
            onTap: () => scrollToPage(pageIndex),
            child: Padding(
              padding: const .all(8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: .spaceAround,
                    children: [
                      Text(
                        '${pageIndex + 1} / ${widget.coreInfo.pages.length}',
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: cupertino ? 100 : 150,
                          maxHeight: 250,
                        ),
                        child: FittedBox(
                          child: CanvasPreview(
                            pageIndex: pageIndex,
                            height: null,
                            coreInfo: widget.coreInfo,
                          ),
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: ReorderableDragStartListener(
                          index: pageIndex,
                          child: const Padding(
                            padding: .all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: .center,
                    children: [
                      IconButton(
                        tooltip: t.editor.menu.insertPage,
                        icon: const AdaptiveIcon(
                          icon: Icons.insert_page_break,
                          cupertinoIcon: CupertinoIcons.add,
                        ),
                        onPressed: () => setState(() {
                          widget.insertPageAfter(pageIndex);
                          scrollToPage(pageIndex + 1);
                        }),
                      ),
                      IconButton(
                        tooltip: t.editor.menu.duplicatePage,
                        icon: const AdaptiveIcon(
                          icon: Icons.content_copy,
                          cupertinoIcon: CupertinoIcons.doc_on_clipboard,
                        ),
                        onPressed: () => setState(() {
                          widget.duplicatePage(pageIndex);
                          scrollToPage(pageIndex + 1);
                        }),
                      ),
                      IconButton(
                        tooltip: t.editor.menu.clearPage(
                          page: pageIndex + 1,
                          totalPages: widget.coreInfo.pages.length,
                        ),
                        icon: const Icon(Icons.cleaning_services),
                        onPressed: isEmptyLastPage
                            ? null
                            : () => setState(() {
                                widget.clearPage(pageIndex);
                                scrollToPage(pageIndex);
                              }),
                      ),
                      PopupMenuButton<_PageReshape>(
                        tooltip: t.editor.menu.rotatePage,
                        icon: const AdaptiveIcon(
                          icon: Icons.rotate_90_degrees_cw,
                          cupertinoIcon: CupertinoIcons.rotate_right,
                        ),
                        onSelected: (reshape) => setState(() {
                          switch (reshape) {
                            case .turn:
                              widget.rotatePage(pageIndex);
                            case .stretch:
                              widget.stretchPage(pageIndex);
                          }
                          scrollToPage(pageIndex);
                        }),
                        itemBuilder: (context) {
                          final size = widget.coreInfo.pages[pageIndex].size;
                          return [
                            PopupMenuItem(
                              value: .turn,
                              child: Text(t.editor.menu.turnPage),
                            ),
                            PopupMenuItem(
                              value: .stretch,
                              child: Text(
                                size.width > size.height
                                    ? t.editor.menu.stretchToPortrait
                                    : t.editor.menu.stretchToLandscape,
                              ),
                            ),
                          ];
                        },
                      ),
                      IconButton(
                        tooltip: t.editor.menu.deletePage,
                        icon: const AdaptiveIcon(
                          icon: Icons.delete,
                          cupertinoIcon: CupertinoIcons.delete,
                        ),
                        onPressed: isEmptyLastPage
                            ? null
                            : () => setState(() {
                                widget.deletePage(pageIndex);
                                scrollToPage(pageIndex);
                              }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        onReorderItem: (oldIndex, newIndex) {
          if (oldIndex == newIndex) return;
          widget.coreInfo.pages.insert(
            newIndex,
            widget.coreInfo.pages.removeAt(oldIndex),
          );

          // reassign pageIndex of pages' strokes and images
          for (int i = 0; i < widget.coreInfo.pages.length; i++) {
            final page = widget.coreInfo.pages[i];
            page.updatePageIndex(i);
          }

          widget.redrawAndSave();
        },
      ),
    );
  }
}

/// What the page manager's rotate menu does to a page.
enum _PageReshape {
  /// Turns it a quarter turn clockwise with what's on it.
  turn,

  /// Stretches it and what's on it to the other orientation.
  stretch,
}
