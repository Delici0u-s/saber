import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/pdf_page_chooser.dart';

void main() {
  group('page ranges', () {
    test('single pages and ranges, in any order and spacing', () {
      expect(parsePageRanges('1-3, 7', 10), {1, 2, 3, 7});
      expect(parsePageRanges(' 5 - 3 ,1', 10), {1, 3, 4, 5});
      expect(parsePageRanges('4', 10), {4});
    });

    test('nothing outside the document, and no nonsense', () {
      expect(parsePageRanges('0', 10), isNull);
      expect(parsePageRanges('2-11', 10), isNull);
      expect(parsePageRanges('1-2-3', 10), isNull);
      expect(parsePageRanges('a', 10), isNull);
      expect(parsePageRanges('', 10), isNull);
    });
  });

  testWidgets('a one-page PDF is imported without asking', (tester) async {
    late List<int>? pages;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                pages = await choosePdfPages(context, _FakePdf(1)),
            child: const Text('import'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(pages, [1]);
  });

  testWidgets('picks pages, all to start with', (tester) async {
    late List<int>? pages;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                pages = await choosePdfPages(context, _FakePdf(5)),
            child: const Text('import'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();
    expect(find.text(t.editor.pdfPages.import(n: 5)), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4-2');
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.editor.pdfPages.import(n: 3)));
    await tester.pumpAndSettle();
    expect(pages, [2, 3, 4]);
  });
}

/// A PDF of [count] A4 pages that doesn't render (thumbnails stay blank).
class _FakePdf implements PdfDocument {
  new(int count) : pages = [for (var i = 1; i <= count; i++) _FakePage(i)];

  @override
  final List<PdfPage> pages;

  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePage implements PdfPage {
  new(this.pageNumber);

  @override
  final int pageNumber;

  @override
  double get width => 595;
  @override
  double get height => 842;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async => null;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => _FakeToken();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeToken implements PdfPageRenderCancellationToken {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
