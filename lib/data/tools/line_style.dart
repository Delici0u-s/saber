/// How a stroke is drawn along its length.
///
/// Saved in notes by [name], so values can be reordered but not renamed.
enum LineStyle {
  solid([]),
  dashed([3, 2]),
  dotted([0, 2]),
  dashDot([3, 1.5, 0, 1.5]);

  new(this.pattern);

  /// Lengths that are alternately drawn and skipped, in multiples of the
  /// stroke's size, starting with a drawn one. A drawn length of 0 is a dot.
  /// Empty for [solid].
  final List<double> pattern;

  /// The style saved as [json] (its [name]), or [solid] if unknown.
  static LineStyle fromJson(Object? json) => values.asNameMap()[json] ?? .solid;
}
