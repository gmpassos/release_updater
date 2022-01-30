import 'dart:async';
import 'dart:isolate';

import 'release_updater_base.dart';

extension ReleaseUpdaterIsolateExtension on ReleaseUpdater {
  /// Spawns an [Isolate] with a periodic call to [checkForUpdate].
  ///
  /// - [onNewRelease] is called when the [Isolate] notifies that a new release is available.
  /// - [interval] is the [Timer] interval. Default: 1min.
  ///
  /// - The created [Isolate] is shared by all calls to [spawnPeriodicUpdateCheckerIsolate].
  ///
  /// See [startPeriodicUpdateChecker].
  Future<bool> spawnPeriodicUpdateCheckerIsolate(OnRelease onNewRelease,
          {Duration? interval, Release? currentRelease}) =>
      _PeriodicUpdateCheckerController.sendTask(
          this, onNewRelease, interval, currentRelease);
}

class _PeriodicUpdateCheckerController {
  static SendPort? _isolatePort;

  static Future<SendPort> _getIsolatePort() async {
    if (_isolatePort != null) return _isolatePort!;
    return _spawnIsolate();
  }

  static Completer<SendPort>? _isolatePortCompleter;

  static Future<SendPort> _spawnIsolate() async {
    if (_isolatePortCompleter != null) return _isolatePortCompleter!.future;

    var isolatePortCompleter = _isolatePortCompleter = Completer<SendPort>();

    var receivePort = ReceivePort();
    receivePort.listen((sendPort) => isolatePortCompleter.complete(sendPort));

    await Isolate.spawn(
        _PeriodicUpdateCheckerIsolate.isolateMain, [receivePort.sendPort],
        debugName: 'PeriodicUpdateChecker');

    var isolatePort = await isolatePortCompleter.future;
    _isolatePort = isolatePort;

    receivePort.close();

    return isolatePort;
  }

  static Future<bool> sendTask(
      ReleaseUpdater releaseUpdater,
      OnRelease onNewRelease,
      Duration? interval,
      Release? currentRelease) async {
    var isolatePort = await _getIsolatePort();

    var receivePort = ReceivePort();
    receivePort.listen((release) => onNewRelease(release));

    isolatePort.send([
      receivePort.sendPort,
      releaseUpdater.copy(),
      interval,
      currentRelease?.toString()
    ]);

    return true;
  }
}

class _PeriodicUpdateCheckerIsolate {
  final ReceivePort _receivePort = ReceivePort();
  final SendPort _sendPort;

  _PeriodicUpdateCheckerIsolate(this._sendPort);

  void start() {
    _receivePort.listen(onReceiveTask);
    _sendPort.send(_receivePort.sendPort);
  }

  void onReceiveTask(dynamic message) {
    SendPort sendPort = message[0];
    ReleaseUpdater releaseUpdater = message[1];
    Duration? interval = message[2];
    String? currentReleaseStr = message[3];

    var currentRelease =
        currentReleaseStr != null ? Release.parse(currentReleaseStr) : null;

    var ret = Future.sync(() => releaseUpdater.onSpawned());

    ret.then((_) {
      releaseUpdater.startPeriodicUpdateChecker((r) => sendPort.send(r),
          interval: interval, currentRelease: currentRelease);
    });
  }

  static void isolateMain(List msg) {
    var sendPort = msg[0] as SendPort;
    var isolate = _PeriodicUpdateCheckerIsolate(sendPort);
    isolate.start();
  }
}
