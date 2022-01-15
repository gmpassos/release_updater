import 'dart:io';

import 'release_updater_base.dart';

extension ReleaseUpdaterIOExtension on ReleaseUpdater {
  /// Starts a [Process] using an [executable] inside the current release path.
  ///
  /// See [Process.start].
  Future<Process?> startReleaseProcess(
      String executable, List<String> arguments,
      {String? workingDirectory,
      Map<String, String>? environment,
      ProcessStartMode mode = ProcessStartMode.normal}) async {
    var executablePath = await currentReleaseFilePath(executable);
    if (executablePath == null) return null;

    workingDirectory ??= await currentReleasePath;

    return Process.start(executablePath, arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        mode: mode);
  }

  /// Runs a [Process] using an [executable] inside the current release path.
  ///
  /// See [Process.run].
  Future<ProcessResult?> runReleaseProcess(
      String executable, List<String> arguments,
      {String? workingDirectory, Map<String, String>? environment}) async {
    var executablePath = await currentReleaseFilePath(executable);
    if (executablePath == null) return null;

    workingDirectory ??= await currentReleasePath;

    return Process.run(executablePath, arguments,
        workingDirectory: workingDirectory, environment: environment);
  }
}
