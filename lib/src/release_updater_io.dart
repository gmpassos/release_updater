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

final Map<String, String> _cachedExecutablesPaths = <String, String>{};

/// Returns an [executable] binary path.
///
/// - If [useCache] is `true` will use the cached resolutions.
String whichExecutablePath(String executable, {bool useCache = true}) {
  executable = executable.trim();

  if (useCache) {
    var cached = _cachedExecutablesPaths[executable];
    if (cached != null) return cached;
  }

  var path = _whichExecutablePathImpl(executable);
  _cachedExecutablesPaths[executable] = path;

  return path;
}

String _whichExecutablePathImpl(String executable) {
  late final String findCmd;
  if (Platform.isWindows) {
    findCmd = 'where';
  } else {
    findCmd = 'which';
  }

  var processResult = Process.runSync(findCmd, <String>[executable],
      stdoutEncoding: systemEncoding);

  if (processResult.exitCode == 0) {
    var output = processResult.stdout as String?;
    output ??= '';
    output = output.trim();

    if (output.isNotEmpty) {
      if (Platform.isWindows) {
        output = output
            .split('\n')
            .where((element) => element.endsWith('exe'))
            .first
            .replaceAll(RegExp(r'/'), r'\'); // replace file separator
      }
      return output;
    }
  }

  return executable;
}
