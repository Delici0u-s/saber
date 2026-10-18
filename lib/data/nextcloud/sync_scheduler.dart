import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';

/// Keeps notes in sync while the app is open.
///
/// Pulls changes from other devices every [Stows.syncPullInterval] seconds
/// and whenever the app is resumed, and makes sure a file saved while it was
/// being uploaded gets uploaded again afterwards.
abstract class SyncScheduler {
  static final log = Logger('SyncScheduler');

  static var _started = false;
  static Timer? _pullTimer;
  static AppLifecycleListener? _lifecycleListener;
  static StreamSubscription<Object>? _uploadSubscription;

  /// Files saved while an upload of the same file was in progress.
  static final _reuploadAfterTransfer = <SaberSyncFile>{};

  /// Starts pulling and watching uploads. Safe to call more than once.
  static void start() {
    if (_started) return;
    _started = true;

    stows.syncPullInterval.addListener(_restartPullTimer);
    _restartPullTimer();
    _lifecycleListener = AppLifecycleListener(onResume: pull);
    _uploadSubscription = syncer.uploader.transferStream.listen(_onUploaded);
  }

  /// Checks the server for changes made on other devices.
  static void pull() {
    if (!stows.loggedIn) return;
    if (syncer.downloader.isRefreshing) return;
    log.fine('Pulling remote changes');
    unawaited(syncer.downloader.refresh());
  }

  /// Uploads the file at [relativeFilePath]. If that file is already queued
  /// (possibly mid-upload, with older contents), it's uploaded again after.
  static Future<void> upload(String relativeFilePath) async {
    if (!stows.loggedIn) return;
    final file = await SaberSyncFile.relative(relativeFilePath);
    final added = await syncer.uploader.enqueue(syncFile: file);
    if (!added) _reuploadAfterTransfer.add(file);
  }

  static void _onUploaded(Object file) {
    if (file is! SaberSyncFile) return;
    if (_reuploadAfterTransfer.remove(file)) {
      unawaited(syncer.uploader.enqueue(syncFile: file));
    }
  }

  static void _restartPullTimer() {
    _pullTimer?.cancel();
    final seconds = stows.syncPullInterval.value;
    if (seconds <= 0) return;
    _pullTimer = Timer.periodic(Duration(seconds: seconds), (_) => pull());
  }

  @visibleForTesting
  static void stop() {
    stows.syncPullInterval.removeListener(_restartPullTimer);
    _pullTimer?.cancel();
    _lifecycleListener?.dispose();
    unawaited(_uploadSubscription?.cancel());
    _reuploadAfterTransfer.clear();
    _started = false;
  }
}
