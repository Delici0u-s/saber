import 'package:flutter/gestures.dart';

/// Which input switches to the eraser (and back) by double-tapping the
/// canvas, see [Stows.doubleTapToErase].
///
/// Saved by [name], so values can be reordered but not renamed.
enum DoubleTapToErase {
  off,
  finger,
  pen,
  both;

  /// Whether a double tap with [kind] switches. [finger] includes the
  /// mouse: it points rather than writes, like a finger.
  bool accepts(PointerDeviceKind kind) => switch (kind) {
    .touch || .mouse => this == finger || this == both,
    .stylus || .invertedStylus => this == pen || this == both,
    _ => false,
  };

  /// How far apart two taps of [kind] can be to count as a double tap: the
  /// usual distance for fingers, and much less for a pen, whose taps leave
  /// dots, so two dots written next to each other (e.g. an umlaut) don't
  /// count.
  static double slop(PointerDeviceKind kind) => switch (kind) {
    .stylus || .invertedStylus => kDoubleTapTouchSlop,
    _ => kDoubleTapSlop,
  };

  /// The setting saved as [json] (its [name]), or [finger] if unknown.
  static DoubleTapToErase fromJson(Object? json) =>
      values.asNameMap()[json] ?? .finger;
}
