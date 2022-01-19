import 'dart:async';
import 'dart:isolate';

import 'release_updater_base.dart';

extension ReleaseUpdaterIsolateExtension on ReleaseUpdater {
  /// Spawns an [Isolate] with a periodic call to [checkForUpdate].
  ///
  /// - [onNewRelease] is called when the [Isolate] notifies that a new release is available.
  /// - [interval] is the [Timer] interval. Default: 1min.
  ///
  /// See [startPeriodicUpdateChecker].
  Future<Isolate> spawnPeriodicUpdateCheckerIsolate(OnRelease onNewRelease,
      {Duration? interval}) async {
    var receivePort = ReceivePort();

    receivePort.listen((release) => onNewRelease(release));

    var isolate = await Isolate.spawn(
      _isolateMain,
      [receivePort.sendPort, copy(), interval],
      debugName: 'PeriodicUpdateChecker',
    );

    return isolate;
  }
}

void _isolateMain(List msg) {
  var sendPort = msg[0] as SendPort;
  ReleaseUpdater releaseUpdater = msg[1];
  Duration? interval = msg[2];

  releaseUpdater.startPeriodicUpdateChecker((r) => sendPort.send(r),
      interval: interval);
}
