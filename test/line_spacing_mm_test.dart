import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';

void main() {
  group('EditorPage mm conversion', () {
    test('the default page width is its physical width', () {
      expect(
        EditorPage.unitsToMm(EditorPage.defaultWidth),
        EditorPage.defaultWidthMm,
      );
      expect(
        EditorPage.mmToUnits(EditorPage.defaultWidthMm),
        EditorPage.defaultWidth,
      );
    });

    for (final mm in Stows.standardLineSpacingsMm) {
      test('the $mm mm preset is within half a unit', () {
        final units = EditorPage.mmToUnits(mm);
        final halfUnitMm = EditorPage.unitsToMm(0.5);
        expect(EditorPage.unitsToMm(units), closeTo(mm, halfUnitMm));
      });
    }

    test('5 mm squares stay within 1%', () {
      const mm = 5.0;
      final actual = EditorPage.unitsToMm(EditorPage.mmToUnits(mm));
      expect((actual - mm).abs() / mm, lessThan(0.01));
    });

    test('at least one preset fits the line height range', () {
      final fitting = Stows.standardLineSpacingsMm
          .map(EditorPage.mmToUnits)
          .where(
            (units) =>
                units >= Stows.lineHeightRange.min &&
                units <= Stows.lineHeightRange.max,
          );
      expect(fitting, isNotEmpty);
    });
  });
}
