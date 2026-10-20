import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

/// Searches all notes by name and folder, and opens the one picked.
class SearchNotesButton extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t.home.search.tooltip,
      onPressed: () async {
        final path = await showSearch(
          context: context,
          delegate: NotesSearchDelegate(FileManager.getAllFiles()),
        );
        if (path != null && context.mounted) {
          context.push(RoutePaths.editFilePath(path));
        }
      },
      icon: const Icon(Icons.search),
    );
  }
}

/// Lists the notes in [notes] (their paths, see [FileManager.getAllFiles])
/// whose path contains every word of the query, ignoring case.
class NotesSearchDelegate extends SearchDelegate<String> {
  new(this.notes) : super(searchFieldLabel: t.home.search.hint);

  final Future<List<String>> notes;

  /// The paths in [all] that match [query], see [NotesSearchDelegate].
  static List<String> matching(List<String> all, String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    return [
      for (final path in all)
        if (words.every(path.toLowerCase().contains)) path,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
        onPressed: () => query = '',
        icon: const Icon(Icons.clear),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => const BackButton();

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    return FutureBuilder(
      future: notes,
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = matching(all, query);
        if (results.isEmpty) {
          return Center(child: Text(t.home.noFiles));
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final path = results[index];
            final slash = path.lastIndexOf('/');
            return ListTile(
              leading: _NoteThumbnail(path),
              title: Text(path.substring(slash + 1)),
              subtitle: slash > 0 ? Text(path.substring(0, slash)) : null,
              onTap: () => close(context, path),
            );
          },
        );
      },
    );
  }
}

/// The thumbnail of the note at [path] (saved next to it when it was last
/// edited, like on the home screen), or a note icon if there's none.
class _NoteThumbnail extends StatelessWidget {
  const new(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = FileManager.getFile('$path${Editor.extension}.p');
    if (!file.existsSync()) return const Icon(Icons.description_outlined);
    return Image.file(
      file,
      height: kMinInteractiveDimension,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(Icons.description_outlined),
    );
  }
}
