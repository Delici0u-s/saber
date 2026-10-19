import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/prefs.dart';

/// The physical density of the screen, used to show pages at real size.
abstract class ScreenDensity {
  static final log = Logger('ScreenDensity');

  static const _channel = MethodChannel('com.adilhanney.saber/display');

  static const mmPerInch = 25.4;

  /// Logical pixels per inch when the platform can't report it:
  /// mobile platforms define logical pixels around 160 per inch,
  /// desktop platforms around 96 per inch.
  static double get _fallback =>
      Platform.isAndroid || Platform.isIOS ? 160 : 96;

  /// The density reported by the platform, if any. See [refresh].
  static double? _reported;

  /// Reads the screen density from the platform, where available.
  /// On desktop, it is the density of the monitor showing the window,
  /// so call this again before using it.
  static Future<void> refresh() async {
    if (!Platform.isAndroid && !Platform.isLinux) return;
    try {
      _reported = await _channel.invokeMethod<double>('logicalPixelsPerInch');
    } on Exception catch (e) {
      log.warning('Could not read the screen density: $e');
    }
  }

  /// Logical pixels per inch: [Stows.screenDpi] if set,
  /// otherwise the platform's value or a typical one.
  static double get logicalPixelsPerInch {
    final setting = stows.screenDpi.value;
    if (setting > 0) return setting;
    return _reported ?? _fallback;
  }

  /// Logical pixels per millimetre, see [logicalPixelsPerInch].
  static double get logicalPixelsPerMm => logicalPixelsPerInch / mmPerInch;
}
