import 'dart:io';

/// Provides the current [Release] platform.
class ReleasePlatform {
  /// The platform ([osName] + [architecture]).
  static String get platform {
    var os = osName;

    if (os.isEmpty) {
      return '';
    }

    var arch = architecture;

    if (arch.isEmpty) {
      return os;
    }

    return '$os-$arch';
  }

  /// The current OS name.
  static String get osName {
    if (Platform.isLinux) {
      return 'linux';
    } else if (Platform.isMacOS) {
      return 'macos';
    } else if (Platform.isWindows) {
      return 'windows';
    } else {
      return '';
    }
  }

  static String? _architecture;

  /// The current OS architecture name.
  static String get architecture => _architecture ??= _architectureImpl();

  static String _architectureImpl() {
    if (Platform.isWindows) {
      return 'x86';
    } else if (Platform.isLinux) {
      return _runUnameM()!;
    } else if (Platform.isMacOS) {
      var arm64 = isMacOSArm64();
      return arm64 ? 'arm64' : 'x64';
    } else {
      return '';
    }
  }

  static bool? _macOSArm64;

  /// Returns `true` if this is a `macOS` `arm64`.
  static bool isMacOSArm64() {
    if (!Platform.isMacOS) return false;
    if (_macOSArm64 != null) return _macOSArm64!;
    var output = _runUnameM()!;
    return _macOSArm64 = output == 'arm64';
  }

  static String? _runUnameM() {
    if (!Platform.isLinux && !Platform.isMacOS) return null;
    var arch = _runProcess(['/usr/bin/uname', '/bin/uname'], ['-m'], 0)
        .toLowerCase()
        .trim();

    if (arch == 'x86_64') {
      return 'x64';
    }

    return arch;
  }

  static String _runProcess(
      List<String> possibleCMDs, List<String> args, int exitCode) {
    Object? error;
    for (var cmd in possibleCMDs) {
      try {
        var process = Process.runSync(cmd, args);
        if (process.exitCode == exitCode) {
          return process.stdout;
        }
      } catch (e) {
        error == e;
        continue;
      }
    }

    if (error != null) {
      throw error;
    } else {
      throw StateError("Can't run any of the possible commands: $possibleCMDs");
    }
  }
}
