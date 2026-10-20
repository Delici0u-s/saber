import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/i18n/strings.g.dart';

/// Asks which pages of [document] to import, all selected to start with.
/// Returns their numbers (from 1, in order), or null if cancelled. A
/// one-page document doesn't ask.
Future<List<int>?> choosePdfPages(
  BuildContext context,
  PdfDocument document,
) async {
  final count = document.pages.length;
  if (count <= 1) return [for (var page = 1; page <= count; page++) page];
  final chosen = await showDialog<Set<int>>(
    context: context,
    builder: (context) => _PdfPageChooser(document: document),
  );
  return chosen == null ? null : (chosen.toList()..sort());
}

/// The page numbers (from 1) that [text] lists, e.g. "1-3, 7" (ranges can
/// run backwards, and spaces don't matter), or null if it isn't such a list
/// of pages from 1 to [count].
Set<int>? parsePageRanges(String text, int count) {
  final pages = <int>{};
  for (final part in text.split(',')) {
    final bounds = part.split('-').map((bound) => bound.trim()).toList();
    if (bounds.length > 2) return null;
    final numbers = [for (final bound in bounds) int.tryParse(bound)];
    if (numbers.any(
      (number) => number == null || number < 1 || number > count,
    )) {
      return null;
    }
    final first = numbers.first!, last = numbers.last!;
    for (var page = min(first, last); page <= max(first, last); page++) {
      pages.add(page);
    }
  }
  return pages;
}

class _PdfPageChooser extends StatefulWidget {
  const new({required this.document});

  final PdfDocument document;

  @override
  State<_PdfPageChooser> createState() => _PdfPageChooserState();
}

class _PdfPageChooserState extends State<_PdfPageChooser> {
  late final _count = widget.document.pages.length;
  late var _selected = {for (var page = 1; page <= _count; page++) page};
  final _ranges = TextEditingController();
  var _rangesValid = true;

  /// How wide a page's thumbnail is at most.
  static const _thumbnailWidth = 120.0;

  /// How sharp thumbnails are rendered: enough for their size, far less than
  /// the page itself.
  static const _thumbnailDpi = 48.0;

  @override
  void dispose() {
    _ranges.dispose();
    super.dispose();
  }

  void _select(Set<int> pages) => setState(() => _selected = pages);

  void _toggle(int page) => _select(
    _selected.contains(page)
        ? (_selected.toSet()..remove(page))
        : (_selected.toSet()..add(page)),
  );

  /// The thumbnails' shape: the first page's (most PDFs keep one size).
  late final _pageAspectRatio = () {
    final size = widget.document.pages.first.size;
    return size.width / size.height;
  }();

  @override
  Widget build(BuildContext context) {
    final strings = t.editor.pdfPages;
    final colorScheme = ColorScheme.of(context);
    return AlertDialog(
      title: Text(strings.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: .min,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: .center,
              children: [
                TextButton(
                  onPressed: () => _select({
                    for (var page = 1; page <= _count; page++) page,
                  }),
                  child: Text(strings.all),
                ),
                TextButton(
                  onPressed: () => _select({}),
                  child: Text(strings.none),
                ),
                IntrinsicWidth(
                  child: TextField(
                    controller: _ranges,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: strings.ranges,
                      hintText: strings.rangesExample,
                      errorText: _rangesValid
                          ? null
                          : strings.rangesInvalid(n: _count),
                    ),
                    onChanged: (text) {
                      final pages = parsePageRanges(text, _count);
                      setState(() => _rangesValid = pages != null);
                      if (pages != null) _select(pages);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _thumbnailWidth,
                  childAspectRatio: _pageAspectRatio,
                ),
                itemCount: _count,
                itemBuilder: (context, index) {
                  final page = index + 1;
                  final selected = _selected.contains(page);
                  return InkWell(
                    onTap: () => _toggle(page),
                    child: Padding(
                      padding: const .all(4),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Opacity(
                              opacity: selected ? 1 : 0.4,
                              child: PdfPageView(
                                document: widget.document,
                                pageNumber: page,
                                maximumDpi: _thumbnailDpi,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Checkbox(
                              value: selected,
                              onChanged: (_) => _toggle(page),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            bottom: 0,
                            child: ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: Padding(
                                padding: const .symmetric(horizontal: 4),
                                child: Text('$page'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text(strings.import(n: _selected.length)),
        ),
      ],
    );
  }
}
