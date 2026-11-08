import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

/// A note's images and PDFs are saved in numbered files (`note.sbn2.0`, ...).
/// Images loaded from those files keep reading them (when shown again, and
/// when saving), so saving must never put other content into a file an image
/// was loaded from. It used to renumber the files by where each asset first
/// appears, so adding an asset before others (or reordering pages) shifted
/// every file by one on each save until all held the same content.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupMockPathProvider();
  FlavorConfig.setup();

  setUpAll(() => FileManager.init(shouldWatchRootDirectory: false));

  var noteNumber = 0;
  late String notePath;
  setUp(() => notePath = '/asset_numbers_test/note${noteNumber++}');

  SvgEditorImage svg(EditorCoreInfo note, String content) => SvgEditorImage(
    id: note.nextImageId++,
    assetCache: note.assetCache,
    svgString: content,
    svgFile: null,
    pageIndex: 0,
    pageSize: const Size(100, 100),
    onMoveImage: null,
    onDeleteImage: null,
    onMiscChange: null,
  );

  /// A note with one page per entry of [contents], each with an image.
  Future<void> saveNewNote(List<String> contents) async {
    final note = EditorCoreInfo(filePath: notePath);
    for (final content in contents) {
      note.pages.add(EditorPage(images: [svg(note, content)]));
    }
    await note.saveToFile(currentPageIndex: null);
    note.dispose();
  }

  /// What each page's image shows when read from the file it uses.
  Future<List<String>> pageContents(EditorCoreInfo note) => Future.wait([
    for (final page in note.pages)
      for (final image in page.images.cast<SvgEditorImage>())
        switch (image.svgLoader) {
          SvgFileLoader(:final file) => file.readAsString(),
          final SvgStringLoader loader => Future.value(loader.provideSvg(null)),
          _ => throw StateError('unexpected loader ${image.svgLoader}'),
        },
  ]);

  Future<List<String>> contentsOnDisk() async =>
      pageContents(await EditorCoreInfo.loadFromFilePath(notePath));

  int assetFileCount() {
    var count = 0;
    while (FileManager.getFile('$notePath${Editor.extension}.$count')
        .existsSync()) {
      count++;
    }
    return count;
  }

  test('adding an image before the others keeps them intact', () async {
    await saveNewNote(['<svg>a</svg>', '<svg>b</svg>', '<svg>c</svg>']);
    final note = await EditorCoreInfo.loadFromFilePath(notePath);

    note.pages.insert(0, EditorPage(images: [svg(note, '<svg>new</svg>')]));
    // Autosave runs again and again while the note stays open.
    for (var save = 0; save < 4; save++) {
      await note.saveToFile(currentPageIndex: null);
      expect(await pageContents(note), [
        '<svg>new</svg>',
        '<svg>a</svg>',
        '<svg>b</svg>',
        '<svg>c</svg>',
      ], reason: 'what the open note shows after save ${save + 1}');
    }

    expect(await contentsOnDisk(), [
      '<svg>new</svg>',
      '<svg>a</svg>',
      '<svg>b</svg>',
      '<svg>c</svg>',
    ]);
    note.dispose();
  });

  test('reordering pages keeps every image intact', () async {
    final contents = [for (var i = 0; i < 12; i++) '<svg>$i</svg>'];
    await saveNewNote(contents);
    final note = await EditorCoreInfo.loadFromFilePath(notePath);

    final reversed = note.pages.reversed.toList();
    note.pages
      ..clear()
      ..addAll(reversed);
    for (var save = 0; save < 3; save++) {
      await note.saveToFile(currentPageIndex: null);
    }

    expect(await pageContents(note), contents.reversed);
    expect(await contentsOnDisk(), contents.reversed);
    note.dispose();
  });

  test('a deleted image can be undone after saving', () async {
    await saveNewNote(['<svg>a</svg>', '<svg>b</svg>', '<svg>c</svg>']);
    final note = await EditorCoreInfo.loadFromFilePath(notePath);

    // Delete c's page (undo keeps hold of it) and add a new image.
    final deleted = note.pages.removeAt(2);
    note.pages.add(EditorPage(images: [svg(note, '<svg>new</svg>')]));
    await note.saveToFile(currentPageIndex: null);
    // Undo: the deleted page comes back.
    note.pages.add(deleted);
    await note.saveToFile(currentPageIndex: null);

    expect(await pageContents(note), [
      '<svg>a</svg>',
      '<svg>b</svg>',
      '<svg>new</svg>',
      '<svg>c</svg>',
    ]);
    expect(await contentsOnDisk(), await pageContents(note));
    note.dispose();
  });

  test('assets nothing uses any more are removed', () async {
    await saveNewNote(['<svg>a</svg>', '<svg>b</svg>', '<svg>c</svg>']);
    expect(assetFileCount(), 3);

    // The next time the note is opened, nothing refers to the deleted asset.
    var note = await EditorCoreInfo.loadFromFilePath(notePath);
    note.pages.removeAt(2);
    await note.saveToFile(currentPageIndex: null);
    note.dispose();
    note = await EditorCoreInfo.loadFromFilePath(notePath);
    await note.saveToFile(currentPageIndex: null);

    expect(await contentsOnDisk(), ['<svg>a</svg>', '<svg>b</svg>']);
    expect(assetFileCount(), 2);
    note.dispose();
  });

  test('the same file used twice is saved once', () async {
    await saveNewNote(['<svg>a</svg>']);
    final note = await EditorCoreInfo.loadFromFilePath(notePath);
    final copy = note.pages.first.images.first.copy()..id = note.nextImageId++;
    note.pages.add(EditorPage(images: [copy]));
    await note.saveToFile(currentPageIndex: null);

    expect(await contentsOnDisk(), ['<svg>a</svg>', '<svg>a</svg>']);
    expect(assetFileCount(), 1);
    note.dispose();
  });

  test('an archive (.sba) still numbers its assets from 0', () async {
    await saveNewNote(['<svg>a</svg>', '<svg>b</svg>']);
    final note = await EditorCoreInfo.loadFromFilePath(notePath);
    note.pages.removeAt(0);

    final (_, assets) = note.saveToBinary(currentPageIndex: null);
    expect(assets.length, 1);
    expect(String.fromCharCodes(await assets.getBytes(0)), '<svg>b</svg>');
    note.dispose();
  });

  tearDownAll(() async {
    final dir = Directory(
      '${FileManager.documentsDirectory}/asset_numbers_test',
    );
    if (dir.existsSync()) await dir.delete(recursive: true);
  });
}
