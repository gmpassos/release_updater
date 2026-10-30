import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_utility.dart';
import 'package:yaml/yaml.dart';

import 'release_packer_gcs.dart';
import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_config.dart';
import 'release_updater_io.dart';
import 'release_updater_storage_io.dart';
import 'release_updater_utils.dart';
import 'release_updater_utils_io.dart';

class ReleasePacker {
  final String name;
  final Version version;
  final List<ReleasePackerCommand>? prepareCommands;
  final List<ReleasePackerCommand>? finalizeCommands;
  final List<ReleasePackerFile> files;
  final Map<String, String> properties;
  final Directory? configDirectory;

  ReleasePacker(
    this.name,
    this.version,
    this.files, {
    this.prepareCommands,
    this.finalizeCommands,
    Map<String, String>? properties,
    this.configDirectory,
  }) : properties = properties ?? <String, String>{};

  factory ReleasePacker.fromJson(
    Map<String, Object?> json, {
    Map<String, String>? properties,
    Directory? rootDirectory,
    bool allowPropertiesFromEnv = false,
  }) {
    json = resolveJsonMapProperties(
      json,
      properties,
      allowEnv: allowPropertiesFromEnv,
    );

    var name = json.get<String>('name') ?? 'app';
    var versionStr = json.get<String>('version');

    if (versionStr == null) {
      var versionFrom = json.get<String>('version_from');
      if (versionFrom != null) {
        var json = _readFilePath(versionFrom, rootDirectory);
        versionStr = json is Map ? json['version'] : null;
      }
    }

    var version = SemanticVersioning.parse(versionStr ?? '0.0.1');

    var prepare = json.get<List>('prepare', [])!;
    var prepareCommands = ReleasePackerCommand.toCommands(jsonList: prepare);

    var finalize = json.get<List>('finalize', [])!;
    var finalizeCommands = ReleasePackerCommand.toCommands(jsonList: finalize);

    var files = json.get<List>('files', [])!;
    var releaseFiles = files.map((e) => ReleasePackerFile.fromJson(e)).toList();

    return ReleasePacker(
      name,
      version,
      releaseFiles,
      prepareCommands: prepareCommands,
      finalizeCommands: finalizeCommands,
      properties: properties,
      configDirectory: rootDirectory,
    );
  }

  factory ReleasePacker.fromFilePath(
    String filePath, {
    Map<String, String>? properties,
    Directory? rootDirectory,
    bool allowPropertiesFromEnv = false,
  }) {
    var file = _toFile(filePath, rootDirectory);
    return ReleasePacker.fromFile(
      file,
      properties: properties,
      rootDirectory: rootDirectory,
      allowPropertiesFromEnv: allowPropertiesFromEnv,
    );
  }

  factory ReleasePacker.fromFile(
    File file, {
    Map<String, String>? properties,
    Directory? rootDirectory,
    bool allowPropertiesFromEnv = false,
  }) {
    var json = _readFile(file, expected: true);
    if (json is! Map) {
      throw StateError("Can't read a JSON/YAML `Map` from file: $file");
    }
    return ReleasePacker.fromJson(
      json.asJsonMap,
      properties: properties,
      rootDirectory: rootDirectory ?? file.parent,
      allowPropertiesFromEnv: allowPropertiesFromEnv,
    );
  }

  static File _toFile(String filePath, Directory? rootDirectory) {
    var path = joinPaths((rootDirectory ?? Directory.current).path, filePath);
    return File(path);
  }

  static dynamic _readFilePath(String filePath, Directory? rootDirectory) {
    var file = _toFile(filePath, rootDirectory);
    return _readFile(file);
  }

  static Object? _readFile(File file, {bool expected = false}) {
    if (!file.existsSync()) {
      if (expected) {
        throw StateError("File does NOT exists: ${file.path}");
      }
      return null;
    }

    var content = file.readAsStringSync();

    var path = file.path;

    if (path.endsWith('.json')) {
      return dart_convert.json.decode(content);
    } else if (path.endsWith('.yaml') || path.endsWith('.yml')) {
      return loadYaml(content);
    }

    return content;
  }

  List<ReleasePackerFile> getFiles({String? platform}) {
    Iterable<ReleasePackerFile> where = files;
    if (platform != null) {
      where = where.where((e) => e.matchesPlatform(platform));
    }
    return where.toList();
  }

  ReleasePackerFile? getFile(String filePath, {String? platform}) {
    var possibleDirPath = filePath.endsWith('/') ? filePath : '$filePath/';

    var where = files.where(
      (e) => e.sourcePath == filePath || e.sourcePath == possibleDirPath,
    );

    if (platform != null) {
      where = where.where((e) => e.matchesPlatform(platform));
    }

    return where.firstOrNull;
  }

  ReleasePackerFile? getFileMatching(RegExp filePathRegexp) =>
      files.firstWhereOrNull((e) => filePathRegexp.hasMatch(e.sourcePath));

  /// Runs the [prepareCommands].
  ///
  /// Throws a [ReleasePackerError] if a command fails.
  Future<Map<ReleasePackerCommand, ReleasePackerCommandStatus>> prepare(
    Directory rootDirectory, {
    String? platform,
  }) {
    var prepareCommands = this.prepareCommands;
    if (prepareCommands != null && prepareCommands.isNotEmpty) {
      print('\n»  Running prepare commands (${prepareCommands.length})...');
    }

    return ReleasePackerCommand.executeCommands(
      this,
      prepareCommands,
      rootDirectory,
      platform: platform,
      context: 'prepare',
    );
  }

  /// Runs the [finalizeCommands].
  ///
  /// Throws a [ReleasePackerError] if a command fails.
  Future<Map<ReleasePackerCommand, ReleasePackerCommandStatus>> finalize(
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    String? platform,
  }) {
    var finalizeCommands = this.finalizeCommands;
    if (finalizeCommands != null && finalizeCommands.isNotEmpty) {
      print('\n»  Running finalize commands (${finalizeCommands.length})...');
    }

    return ReleasePackerCommand.executeCommands(
      this,
      finalizeCommands,
      rootDirectory,
      releaseBundle: releaseBundle,
      platform: platform,
      context: 'finalize',
    );
  }

  Future<ReleaseBundleZip> buildFromDirectory({
    Directory? rootDirectory,
    String? sourcePath,
    String? platform,
  }) async {
    var configDirectory = this.configDirectory;

    if (rootDirectory == null) {
      if (sourcePath != null) {
        rootDirectory = Directory(joinPaths(configDirectory?.path, sourcePath));
      } else if (configDirectory != null) {
        rootDirectory = configDirectory;
      }
    }

    if (rootDirectory == null) {
      throw ArgumentError("Can't define `rootDirectory`!");
    }

    // Before `prepare` (if the resolution is up to date), to fail fast, and
    // after it, as `prepare` can resolve or change the dependencies:
    if (isPackageResolutionUpToDate(rootDirectory)) {
      checkBuildHooks(rootDirectory, platform: platform, warnings: false);
    }

    await prepare(rootDirectory, platform: platform);

    checkBuildHooks(rootDirectory, platform: platform);

    var filesWithCommand = getFiles(
      platform: platform,
    ).where((e) => e.hasCommands).toList();

    if (filesWithCommand.isNotEmpty) {
      print('»  Running files commands (${filesWithCommand.length}):');
      for (var f in filesWithCommand) {
        await f.executeCommands(
          this,
          rootDirectory,
          platform: platform,
          context: 'file: ${f.sourcePath}',
        );
      }
    }

    var files = rootDirectory.listSync(recursive: true);

    var rootPath = rootDirectory.path;

    print('»  Loading release bundle files from: $rootPath');

    var list = files
        .map((e) {
          var sourcePath = e.path;
          if (sourcePath.startsWith(rootPath)) {
            sourcePath = sourcePath.substring(rootPath.length);
          }

          sourcePath = ReleaseFile.normalizePath(sourcePath);

          var packFile = getFile(sourcePath, platform: platform);

          if (packFile == null) {
            return null;
          }

          var destinyPath = packFile.destinyPath;

          var file = File(e.path);
          var fileType = file.statSync().type;

          var releaseFiles = <ReleaseFile>[];

          if (fileType == FileSystemEntityType.directory) {
            var dir = Directory(file.path);
            var dirPath = dir.path;

            var dirFiles = dir
                .listSync(recursive: true)
                .whereType<File>()
                .toList();

            for (var f in dirFiles) {
              var filePath = f.path;
              if (filePath.startsWith(dirPath)) {
                filePath = filePath.substring(dirPath.length);
                while (filePath.startsWith(pack_path.separator)) {
                  filePath = filePath.substring(1);
                }
              }

              var fileDestinyPath = pack_path.join(destinyPath, filePath);

              var data = f.readAsBytesSync();
              var time = f.lastModifiedSync();
              var exec =
                  f.hasExecutablePermission ||
                  ReleaseBundleZip.isExecutableFilePath(fileDestinyPath);

              var releaseFile = ReleaseFile(
                fileDestinyPath,
                data,
                time: time,
                executable: exec,
              );

              releaseFiles.add(releaseFile);
            }
          } else {
            // A single file mapped to the release root keeps its name:
            if (destinyPath.isEmpty) {
              destinyPath = pack_path.basename(sourcePath);
            }

            var data = file.readAsBytesSync();
            var time = file.lastModifiedSync();
            var exec =
                file.hasExecutablePermission ||
                ReleaseBundleZip.isExecutableFilePath(destinyPath);

            var releaseFile = ReleaseFile(
              destinyPath,
              data,
              time: time,
              executable: exec,
            );

            releaseFiles.add(releaseFile);
          }

          return releaseFiles;
        })
        .nonNulls
        .expand((e) => e)
        .toList();

    list = await mergeDuplicatedFiles(list);

    var release = Release(name, version, platform: platform);
    var releaseBundle = ReleaseBundleZip(release, files: list);

    await finalize(
      rootDirectory,
      releaseBundle: releaseBundle,
      platform: platform,
    );

    return releaseBundle;
  }

  /// Merges the [files] with the same path, like the `lib/` of two
  /// `dart build cli` bundles of the same project.
  ///
  /// A merged file is executable if any of its copies is.
  ///
  /// Throws a [ReleasePackerError] if files with the same path have
  /// different contents.
  static Future<List<ReleaseFile>> mergeDuplicatedFiles(
    List<ReleaseFile> files,
  ) async {
    var byPath = <String, ReleaseFile>{};

    for (var f in files) {
      var prev = byPath[f.filePath];
      if (prev == null) {
        byPath[f.filePath] = f;
        continue;
      }

      var prevData = await prev.data;

      if (!const ListEquality<int>().equals(prevData, await f.data)) {
        throw ReleasePackerError(
          "Different files for the same release path: ${f.filePath}",
        );
      }

      if (f.executable && !prev.executable) {
        byPath[f.filePath] = ReleaseFile(
          prev.filePath,
          prevData,
          time: prev.time,
          executable: true,
        );
      }
    }

    return byPath.values.toList();
  }

  /// All the commands of this packer for [platform]: `prepare`, `files` and
  /// `finalize`.
  List<ReleasePackerCommand> allCommands({String? platform}) => [
    ...?prepareCommands,
    for (var f in getFiles(platform: platform)) ...?f.commands,
    ...?finalizeCommands,
  ].where((c) => c.matchesPlatform(platform)).toList();

  /// Returns `true` if the `.dart_tool/package_config.json` of
  /// [rootDirectory] exists and is NOT older than its `pubspec.yaml` and
  /// `pubspec.lock`: a stale resolution (like one restored from a cache)
  /// may NOT reflect the current dependencies.
  static bool isPackageResolutionUpToDate(Directory rootDirectory) {
    var configFile = File(
      pack_path.join(rootDirectory.path, '.dart_tool', 'package_config.json'),
    );
    if (!configFile.existsSync()) return false;

    var configTime = configFile.lastModifiedSync();

    for (var name in ['pubspec.yaml', 'pubspec.lock']) {
      var file = File(pack_path.join(rootDirectory.path, name));
      if (file.existsSync() && file.lastModifiedSync().isAfter(configTime)) {
        return false;
      }
    }

    return true;
  }

  /// The packages with build hooks (`hook/build.dart`) in the
  /// `.dart_tool/package_config.json` of [rootDirectory].
  ///
  /// Only the runtime dependencies count, as for `dart compile exe`: if there
  /// is a `.dart_tool/package_graph.json`, the `devDependencies` of the root
  /// packages (and the packages only they use) are ignored.
  ///
  /// Returns `null` if the packages are not resolved yet.
  static List<String>? packagesWithBuildHooks(Directory rootDirectory) {
    var dartToolDir = Directory(
      pack_path.join(rootDirectory.path, '.dart_tool'),
    );

    var config = _readJson(
      File(pack_path.join(dartToolDir.path, 'package_config.json')),
    );

    var packages = config is Map ? config['packages'] : null;
    if (packages is! List) return null;

    var runtimePackages = _runtimePackages(
      _readJson(File(pack_path.join(dartToolDir.path, 'package_graph.json'))),
    );

    var configDirUri = Uri.directory(dartToolDir.absolute.path);

    var withHooks = <String>[];

    for (var p in packages.whereType<Map>()) {
      var name = p['name'];
      var rootUri = p['rootUri'];
      if (name is! String || rootUri is! String) continue;

      if (runtimePackages != null && !runtimePackages.contains(name)) {
        continue;
      }

      var packageUri = configDirUri.resolve(
        rootUri.endsWith('/') ? rootUri : '$rootUri/',
      );

      var hookFile = File.fromUri(packageUri.resolve('hook/build.dart'));
      if (hookFile.existsSync()) {
        withHooks.add(name);
      }
    }

    return withHooks;
  }

  static Object? _readJson(File file) {
    if (!file.existsSync()) return null;
    try {
      return dart_convert.json.decode(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// The runtime packages of a `package_graph.json`: the `roots` and their
  /// `dependencies`, transitively (the `devDependencies` are NOT followed).
  ///
  /// Returns `null` for an invalid graph.
  static Set<String>? _runtimePackages(Object? graph) {
    if (graph is! Map) return null;

    var roots = graph['roots'];
    var packages = graph['packages'];
    if (roots is! List || packages is! List) return null;

    var dependencies = <String, List<String>>{
      for (var p in packages.whereType<Map>())
        if (p['name'] is String)
          p['name'] as String: [
            ...((p['dependencies'] as List?) ?? const []).whereType<String>(),
          ],
    };

    var runtime = <String>{};
    var pending = roots.whereType<String>().toList();

    while (pending.isNotEmpty) {
      var name = pending.removeLast();
      if (runtime.add(name)) {
        pending.addAll(dependencies[name] ?? const []);
      }
    }

    return runtime;
  }

  /// Checks that the commands for [platform] support the build hooks of the
  /// packages of [rootDirectory].
  ///
  /// `dart compile exe` (and `aot-snapshot`) does NOT support build hooks,
  /// so a [ReleasePackerError] is thrown, suggesting `dart_build_cli`, before
  /// running a build that will fail. A `dart compile kernel` builds, but
  /// can't find the dynamic libraries of the hooks: only a warning, if
  /// [warnings] (the check before `prepare` doesn't repeat it).
  void checkBuildHooks(
    Directory rootDirectory, {
    String? platform,
    bool warnings = true,
  }) {
    var withHooks = packagesWithBuildHooks(rootDirectory);
    if (withHooks == null || withHooks.isEmpty) return;

    var commands = allCommands(platform: platform);

    bool isCompile(ReleasePackerCommand c, List<String> kinds) =>
        c is ReleasePackerDartCommand &&
        c.command == 'compile' &&
        c.args.isNotEmpty &&
        kinds.contains(c.args.first);

    var kernelCommands = warnings
        ? commands.where((c) => isCompile(c, ['kernel']))
        : const <ReleasePackerCommand>[];
    for (var c in kernelCommands) {
      print(
        '  ▒  WARNING: packages with build hooks (${withHooks.join(', ')}): '
        "a `dart compile kernel` builds, but can't load their dynamic "
        'libraries: $c',
      );
    }

    var unsupported = commands
        .where((c) => isCompile(c, ['exe', 'aot-snapshot']))
        .toList();
    if (unsupported.isEmpty) return;

    var message =
        '`dart compile exe` does NOT support build hooks '
        '(packages with build hooks: ${withHooks.join(', ')}). '
        'Use `dart_build_cli` (`dart build cli`) instead: '
        '${unsupported.join(' ; ')}';

    print('  ▒▒  $message\n');

    throw ReleasePackerError(message, failedCommands: unsupported);
  }

  @override
  String toString() {
    return 'ReleasePacker{name: $name, version: $version, files: ${files.length}';
  }
}

abstract class ReleasePackerEntry {
  List<RegExp> platforms;

  ReleasePackerEntry({Object? platform})
    : platforms = platform == null
          ? <RegExp>[]
          : (platform is List
                ? platform.where((e) => e != null).map(_toRegExp).toList()
                : <RegExp>[_toRegExp(platform)]);

  static RegExp _toRegExp(Object? e) => e is RegExp ? e : RegExp('$e');

  bool matchesPlatform(String? platform) {
    if (platforms.isEmpty || platform == null || platform.isEmpty) return true;
    platform = platform.trim();

    for (var re in platforms) {
      if (re.hasMatch(platform)) return true;
    }

    return false;
  }
}

/// The status of a [ReleasePackerCommand] execution.
enum ReleasePackerCommandStatus {
  /// The command was executed successfully.
  ok,

  /// The command was not applicable in the current context and was skipped.
  /// NOT an error: it does not abort the build.
  ignored,

  /// The command failed: it aborts the build.
  error;

  bool get isOK => this == ok;

  bool get isIgnored => this == ignored;

  bool get isError => this == error;

  /// `true` if it does NOT abort the build ([ok] or [ignored]).
  bool get isSuccessful => this != error;
}

/// Error thrown when a `release_packer` build fails.
///
/// A failed command aborts the build instead of generating an incomplete
/// release bundle, avoiding a silent error while building/releasing an
/// artifact.
class ReleasePackerError extends Error {
  /// The error message.
  final String message;

  /// The commands that returned [ReleasePackerCommandStatus.error].
  final List<ReleasePackerCommand> failedCommands;

  ReleasePackerError(this.message, {List<ReleasePackerCommand>? failedCommands})
    : failedCommands = failedCommands ?? <ReleasePackerCommand>[];

  @override
  String toString() => 'ReleasePackerError: $message';
}

abstract class ReleasePackerCommand extends ReleasePackerEntry {
  static List<ReleasePackerCommand>? toCommands({
    String? sourcePath,
    String? dartCompileExe,
    String? dartCompileKernel,
    List<ReleasePackerDartBuild>? dartBuilds,
    String? windowsGUI,
    List? jsonList,
  }) {
    var commands = <ReleasePackerCommand>[];

    if (dartCompileExe != null) {
      commands.add(ReleasePackerDartCompileExe(dartCompileExe));
    }

    if (dartCompileKernel != null) {
      commands.add(ReleasePackerDartCompileKernel(dartCompileKernel));
    }

    if (dartBuilds != null) {
      commands.addAll(dartBuilds);
    }

    var dartBuildCli = ReleasePackerDartBuildCli.firstOf(dartBuilds);

    if (windowsGUI != null) {
      String? inputFile;
      String? outputFile;

      if (dartCompileExe != null) {
        if (dartCompileExe != windowsGUI) {
          inputFile = dartCompileExe;
          outputFile = windowsGUI;
        } else {
          inputFile = dartCompileExe;
          outputFile = sourcePath ?? windowsGUI;
        }
      } else if (dartBuildCli != null) {
        // The executable inside the bundle, changed in place:
        inputFile = outputFile = windowsGUI;
      } else if (sourcePath != null) {
        if (sourcePath != windowsGUI) {
          inputFile = windowsGUI;
          outputFile = sourcePath;
        } else {
          inputFile = sourcePath;
          outputFile = windowsGUI;
        }
      } else {
        inputFile = outputFile = windowsGUI;
      }

      commands.add(
        ReleasePackerWindowsSubsystemCommand(true, inputFile, outputFile),
      );
    }

    if (jsonList != null) {
      for (var e in jsonList) {
        var cmd = ReleasePackerCommand.from(e);
        if (cmd != null) {
          commands.add(cmd);
        }
      }
    }

    return commands.isNotEmpty ? commands : null;
  }

  ReleasePackerCommand();

  static ReleasePackerCommand? from(Object command) {
    if (command is ReleasePackerCommand) {
      return command;
    }

    if (command is String) {
      var fullCommand = command.trim();

      var fullCommandLc = fullCommand.toLowerCase();
      if (fullCommandLc == 'dart_pub_get' || fullCommandLc == 'dart pub get') {
        return ReleasePackerDartPubGet();
      }

      if (fullCommand.isEmpty) return null;

      var list = parseInlineCommand(fullCommand);

      if (list.isNotEmpty) {
        if (list[0] == 'dart') {
          list.removeAt(0);
          return ReleasePackerDartCommand.fromList(list);
        } else {
          return ReleasePackerProcessCommand.fromList(list);
        }
      }

      return null;
    } else if (command is List) {
      var cmd = ReleasePackerProcessCommand.fromList(command);
      var args = cmd.args;

      if (cmd.command == 'dart') {
        if (args.equals(['pub', 'get'])) {
          return ReleasePackerDartPubGet();
        } else if (args.length == 3 &&
            args[0] == 'compile' &&
            args[1] == 'exe') {
          return ReleasePackerDartCompileExe(args[2]);
        } else if (args.length == 3 &&
            args[0] == 'compile' &&
            args[1] == 'kernel') {
          return ReleasePackerDartCompileKernel(args[2]);
        } else if (args.length >= 2 && args[0] == 'build') {
          return ReleasePackerDartBuild.fromArgs(args.sublist(1));
        }
      } else if (cmd.command == 'release_utility' && args.length >= 2) {
        var gui = args[0].toLowerCase().contains('gui');
        var input = cmd.args[1];
        var output = cmd.args.length > 2 ? cmd.args[2] : input;
        return ReleasePackerWindowsSubsystemCommand(gui, input, output);
      } else if (cmd.command == 'windows_gui' && args.isNotEmpty) {
        var input = cmd.args[0];
        var output = cmd.args.length > 1 ? cmd.args[1] : input;
        return ReleasePackerWindowsSubsystemCommand(true, input, output);
      }

      return cmd;
    } else if (command is Map) {
      var map = command.asJsonMap;

      var dartCompileExe = map.get<String>('dart_compile_exe');
      if (dartCompileExe != null && dartCompileExe.isNotEmpty) {
        return ReleasePackerDartCompileExe(dartCompileExe);
      }

      var dartCompileKernel = map.get<String>('dart_compile_kernel');
      if (dartCompileKernel != null && dartCompileKernel.isNotEmpty) {
        return ReleasePackerDartCompileKernel(dartCompileKernel);
      }

      var dartBuilds = ReleasePackerDartBuild.fromJsonMap(map);
      if (dartBuilds.length > 1) {
        throw ArgumentError(
          "Only one `dart_build_*` per command entry: ${map.keys}",
        );
      } else if (dartBuilds.isNotEmpty) {
        return dartBuilds.first;
      }

      var dartPubGet = map.get<String>('dart_pub_get');
      if (dartPubGet != null && dartPubGet.isNotEmpty) {
        dartPubGet = dartPubGet.trim().toLowerCase();
        if (dartPubGet != 'false') {
          return ReleasePackerDartPubGet();
        }
      }

      var dart = map.get('dart');
      if (dart != null) {
        return ReleasePackerDartCommand.from(dart);
      }

      var windowsGUI = map.get('windows_gui');
      if (windowsGUI != null) {
        String? input;
        String? output;

        if (windowsGUI is List && windowsGUI.isNotEmpty) {
          input = windowsGUI[0];
          output = windowsGUI.length > 1 ? windowsGUI[1] : input;
        } else if (windowsGUI is Map && windowsGUI.isNotEmpty) {
          input = windowsGUI['input'];
          output = windowsGUI['output'] ?? input;
        } else if (windowsGUI is String) {
          input = output = windowsGUI;
        }

        if (input == null || output == null) {
          throw StateError(
            "Can't define `windows_gui` input and output: $windowsGUI",
          );
        }

        return ReleasePackerWindowsSubsystemCommand(
          true,
          input.toString(),
          output.toString(),
        );
      }

      var rm = map.get<String>('rm') ?? map.get<String>('del');
      if (rm != null) {
        rm = rm.trim();
        if (rm.isNotEmpty) {
          return ReleasePackerCommandDelete(rm);
        }
      }

      var cmd = map.get('command') ?? map.get('cmd');
      if (cmd != null) {
        var stdout = map.get<String>('stdout');
        var stderr = map.get<String>('stderr');
        return ReleasePackerProcessCommand.from(
          cmd,
          stdoutFilePath: stdout,
          stderrFilePath: stderr,
        );
      }

      var url = map.get('url');
      if (url != null) {
        return ReleasePackerCommandURL.fromJson(url);
      }

      var uploadRelease =
          map.get('upload_release') ?? map.get('upload_release_bundle');
      if (uploadRelease != null) {
        return ReleasePackerCommandUploadReleaseBundle.fromJson(uploadRelease);
      }

      return null;
    } else {
      throw ArgumentError("Unknown command type: $command");
    }
  }

  static List<String> parseInlineCommand(String fullCommand) {
    fullCommand = fullCommand.trim();

    var list = <String>[];

    fullCommand.splitMapJoin(
      RegExp(r'(\s+)|"(.*?)"'),
      onMatch: (m) {
        var quoted = m[2];
        if (quoted != null) {
          list.add(quoted);
        }
        return '';
      },
      onNonMatch: (s) {
        if (s.isNotEmpty) {
          list.add(s);
        }
        return '';
      },
    );

    return list;
  }

  FutureOr<bool> execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  });

  /// Executes this command returning its [ReleasePackerCommandStatus].
  ///
  /// The default implementation maps [execute]: `true` to
  /// [ReleasePackerCommandStatus.ok] and `false` to
  /// [ReleasePackerCommandStatus.error]. Commands that can be skipped
  /// without failing the build override this to return
  /// [ReleasePackerCommandStatus.ignored].
  FutureOr<ReleasePackerCommandStatus> executeStatus(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    var ok = execute(
      releasePacker,
      rootDirectory,
      releaseBundle: releaseBundle,
    );

    return ok is Future<bool> ? ok.then(_toStatus) : _toStatus(ok);
  }

  static ReleasePackerCommandStatus _toStatus(bool ok) =>
      ok ? ReleasePackerCommandStatus.ok : ReleasePackerCommandStatus.error;

  /// Executes [commands] that match [platform].
  ///
  /// Stops at the 1st command that fails and throws a [ReleasePackerError],
  /// to avoid running the remaining commands over a broken build and
  /// generating an incomplete release bundle.
  static Future<Map<ReleasePackerCommand, ReleasePackerCommandStatus>>
  executeCommands(
    ReleasePacker releasePacker,
    List<ReleasePackerCommand>? commands,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    String? platform,
    String? context,
  }) async {
    var results = <ReleasePackerCommand, ReleasePackerCommandStatus>{};
    if (commands == null || commands.isEmpty) return results;

    for (var c in commands.where((e) => e.matchesPlatform(platform))) {
      var status = await c.executeStatus(
        releasePacker,
        rootDirectory,
        releaseBundle: releaseBundle,
      );

      results[c] = status;

      if (status.isError) break;
    }

    print('   »  Commands results:');
    for (var e in results.entries) {
      print('     -  ${e.key} »  ${e.value.name}');
    }
    print('');

    checkCommandsResults(results, context: context);

    return results;
  }

  /// Throws a [ReleasePackerError] if any command in [results] has failed.
  static void checkCommandsResults(
    Map<ReleasePackerCommand, ReleasePackerCommandStatus> results, {
    String? context,
  }) {
    var failedCommands = results.entries
        .where((e) => e.value.isError)
        .map((e) => e.key)
        .toList();

    if (failedCommands.isEmpty) return;

    var at = context != null && context.isNotEmpty ? ' at `$context`' : '';

    for (var c in failedCommands) {
      print('  ▒▒  FAILED COMMAND$at: $c');
    }
    print('');

    throw ReleasePackerError(
      'Command error$at: ${failedCommands.join(' ; ')}',
      failedCommands: failedCommands,
    );
  }
}

abstract class ReleasePackerCommandWithArgs extends ReleasePackerCommand {
  final String command;

  final List<String> args;

  ReleasePackerCommandWithArgs(String command, [List<String>? args])
    : command = command.trim(),
      args = args?.toList() ?? <String>[] {
    // NOTE: checks the trimmed field, not the parameter:
    if (this.command.isEmpty) {
      throw ArgumentError("Empty command!");
    }
  }
}

class ReleasePackerCommandDelete extends ReleasePackerCommand {
  final String path;

  ReleasePackerCommandDelete(this.path) {
    if (path.isEmpty) {
      throw ArgumentError("Empty path!");
    }
  }

  @override
  FutureOr<bool> execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    var filePath = joinPaths(rootDirectory.path, path);
    var file = File(filePath);

    if (file.existsSync()) {
      print('   »  Deleting file: $filePath');
      file.deleteSync();
      return true;
    }

    return false;
  }

  @override
  FutureOr<ReleasePackerCommandStatus> executeStatus(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    var filePath = joinPaths(rootDirectory.path, path);

    // Nothing to delete is already the desired state, NOT an error:
    if (!File(filePath).existsSync()) {
      print('   »  IGNORING delete command> File not found: $filePath');
      return ReleasePackerCommandStatus.ignored;
    }

    return super.executeStatus(
      releasePacker,
      rootDirectory,
      releaseBundle: releaseBundle,
    );
  }

  @override
  String toString() {
    return 'ReleasePackerCommandDelete{ path: $path }';
  }
}

class ReleasePackerCommandURL extends ReleasePackerCommand {
  final String url;
  final Map<String, Object?>? parameters;

  final Credential? authorization;
  final Object? body;

  ReleasePackerCommandURL(
    this.url, {
    this.parameters,
    this.authorization,
    this.body,
  }) {
    if (url.isEmpty) {
      throw ArgumentError("Empty URL!");
    }
  }

  factory ReleasePackerCommandURL.fromJson(Object json) {
    if (json is String) {
      return ReleasePackerCommandURL(json);
    } else if (json is Map) {
      var map = json.asJsonMap;

      var url = map.get<String>('url');
      if (url == null || url.isEmpty) {
        throw ArgumentError("Invalid JSON! Invalid `url`: $url");
      }

      var parameters = map.get<Map>('parameters');
      var authorization = map.get('authorization');
      var body = map.get('body');

      var credential = toCredential(authorization);

      return ReleasePackerCommandURL(
        url,
        parameters: parameters?.asJsonMap,
        authorization: credential,
        body: body,
      );
    } else {
      throw ArgumentError("Unknown type: $json");
    }
  }

  static Credential? toCredential(Object? o) {
    if (o == null) return null;
    if (o is Credential) return o;

    if (o is String) {
      var parts = o.split(':');

      var user = parts[0];
      var pass = parts.length > 1 ? parts[1] : null;

      return BasicCredential(user, pass ?? '');
    }
    if (o is List) {
      var list = o.map((e) => '$e').toList();
      var user = list.isNotEmpty ? list[0] : null;
      var pass = list.length > 1 ? list[1] : null;

      if (user != null) {
        return BasicCredential(user, pass ?? '');
      }
    } else if (o is Map) {
      var map = o.asJsonMap;
      var user = map.get<String>('username') ?? map.get<String>('user');
      var pass =
          map.get<String>('password') ??
          map.get<String>('pass') ??
          map.get<String>('passphrase');
      var bearer = map.get<String>('bearer') ?? map.get<String>('token');

      if (user != null) {
        return BasicCredential(user, pass ?? bearer ?? '');
      }

      if (bearer != null) {
        return BearerCredential(bearer);
      }
    }

    return null;
  }

  @override
  Future<bool> execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) async {
    var parameters = this.parameters != null
        ? Map<String, Object?>.from(this.parameters!)
        : null;

    Object? body;

    if (this.body == '%RELEASE_BUNDLE%') {
      if (releaseBundle == null) {
        print('  ▒  Release bundle not provided for body: $this');
        return false;
      } else {
        print('   »  Using `ReleaseBundle` as body.');

        var file = parameters?['file'] as String?;
        if (file != null) {
          var release = releaseBundle.release;
          var fileFormatted = ReleaseBundle.formatReleaseBundleFile(
            file,
            release.name,
            release.version,
            release.platform,
          );
          parameters!['file'] = fileFormatted;

          print('   »  Parameter `file`: $fileFormatted');
        }

        var release = parameters?['release'] as String?;
        if (release != null && release.toLowerCase() == '%release%') {
          release = releaseBundle.release.toString();
          parameters!['release'] = release;
        }
      }
      body = await releaseBundle.toBytes();
    } else {
      body = this.body;
    }

    var httpClient = HttpClient(url);

    HttpResponse response;

    if (body != null) {
      print('   »  Requesting URL[POS]: $url');

      String bodyStr;
      if (body is List<int>) {
        bodyStr = '${body.length} bytes';
      } else {
        bodyStr = '<<$body>>';
      }

      print('   »  Body: $bodyStr');

      try {
        response = await httpClient.post(
          '',
          parameters: parameters,
          authorization: authorization,
          body: body,
        );
      } catch (e) {
        print('  ▒  Error requesting: $url > $e');
        return false;
      }
    } else {
      print('   »  Requesting URL[GET]: $url');

      try {
        response = await httpClient.get(
          '',
          parameters: parameters,
          authorization: authorization,
        );
      } catch (e) {
        print('  ▒  Error requesting: $url > $e');
        return false;
      }
    }

    print(
      '   »  Request response> status: ${response.status} ; body: ${response.bodyAsString}',
    );

    return response.isOK;
  }

  @override
  String toString() {
    return '$runtimeType{ url: $url, parameters: $parameters, authorization: $authorization, body: $body }';
  }
}

class ReleasePackerCommandUploadReleaseBundle extends ReleasePackerCommand {
  final ReleasePackerCommand uploadCommand;

  ReleasePackerCommandUploadReleaseBundle._(this.uploadCommand);

  factory ReleasePackerCommandUploadReleaseBundle.byURL(
    String url, {
    Map<String, Object?>? parameters,
    Credential? authorization,
    String? file,
    String? release,
  }) {
    file ??= ReleaseBundle.defaultReleasesBundleFileFormat;
    release ??= '%RELEASE%';

    parameters ??= <String, Object?>{};

    parameters['file'] ??= file;
    parameters['release'] ??= release;

    var cmd = ReleasePackerCommandURL(
      url,
      parameters: parameters,
      authorization: authorization,
      body: '%RELEASE_BUNDLE%',
    );

    return ReleasePackerCommandUploadReleaseBundle._(cmd);
  }

  factory ReleasePackerCommandUploadReleaseBundle.byGCS(
    String project,
    String bucket, {
    Map<String, Object?>? parameters,
    required Object credential,
    String? file,
    String? release,
  }) {
    file ??= ReleaseBundle.defaultReleasesBundleFileFormat;
    release ??= '%RELEASE%';

    parameters ??= <String, Object?>{};

    parameters['file'] ??= file;
    parameters['release'] ??= release;

    var cmd = ReleasePackerCommandGCS(
      project,
      bucket,
      credential: credential,
      parameters: parameters,
      body: '%RELEASE_BUNDLE%',
    );

    return ReleasePackerCommandUploadReleaseBundle._(cmd);
  }

  factory ReleasePackerCommandUploadReleaseBundle.fromJson(Object json) {
    String? file;
    String? release;

    if (json is Map) {
      var map = json.asJsonMap;

      file = map.get('file');
      release = map.get('release');

      var gcs = map.get<Map>('gcs');
      if (gcs != null) {
        var cmd = ReleasePackerCommandGCS.fromJson(gcs);

        return ReleasePackerCommandUploadReleaseBundle.byGCS(
          cmd.project,
          cmd.bucket,
          credential: cmd.credential,
          parameters: cmd.parameters,
          file: file,
          release: release,
        );
      }
    }

    var cmd = ReleasePackerCommandURL.fromJson(json);

    return ReleasePackerCommandUploadReleaseBundle.byURL(
      cmd.url,
      parameters: cmd.parameters,
      authorization: cmd.authorization,
      file: file,
      release: release,
    );
  }

  @override
  FutureOr<bool> execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    return uploadCommand.execute(
      releasePacker,
      rootDirectory,
      releaseBundle: releaseBundle,
    );
  }
}

class ReleasePackerProcessCommand extends ReleasePackerCommandWithArgs {
  final String? stdoutFilePath;
  final String? stderrFilePath;

  ReleasePackerProcessCommand(
    super.command, [
    super.args,
    this.stdoutFilePath,
    this.stderrFilePath,
  ]);

  factory ReleasePackerProcessCommand.fromList(
    List list, {
    String? stdoutFilePath,
    String? stderrFilePath,
  }) {
    var listStr = list.map((e) => '$e').toList();
    var command = listStr.removeAt(0);
    return ReleasePackerProcessCommand(
      command,
      listStr,
      stdoutFilePath,
      stderrFilePath,
    );
  }

  factory ReleasePackerProcessCommand.inline(
    String fullCommand, {
    String? stdoutFilePath,
    String? stderrFilePath,
  }) {
    var list = ReleasePackerCommand.parseInlineCommand(fullCommand);
    var command = list.removeAt(0);
    return ReleasePackerProcessCommand(
      command,
      list,
      stdoutFilePath,
      stderrFilePath,
    );
  }

  factory ReleasePackerProcessCommand.from(
    Object command, {
    String? stdoutFilePath,
    String? stderrFilePath,
  }) {
    if (command is String) {
      return ReleasePackerProcessCommand.inline(
        command,
        stdoutFilePath: stdoutFilePath,
        stderrFilePath: stderrFilePath,
      );
    } else if (command is List) {
      return ReleasePackerProcessCommand.fromList(
        command,
        stdoutFilePath: stdoutFilePath,
        stderrFilePath: stderrFilePath,
      );
    } else {
      throw ArgumentError("Unknown command type: $command");
    }
  }

  @override
  bool execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    int expectedExitCode = 0,
  }) {
    String commandPath;
    if (!containsGenericPathSeparator(command)) {
      commandPath = whichExecutablePath(command);
    } else {
      commandPath = command;
    }

    var fullCommandPath = joinPaths(rootDirectory.path, commandPath);

    print(
      '   »  Process command> ${rootDirectory.path} -> $fullCommandPath $args',
    );

    var result = Process.runSync(
      fullCommandPath,
      args,
      workingDirectory: rootDirectory.path,
    );

    saveStdout(rootDirectory, result.stdout);
    saveStderr(rootDirectory, result.stderr);

    var exitCode = result.exitCode;
    var ok = exitCode == expectedExitCode;

    if (!ok) {
      print(
        '  ▒  Command error! exitCode: $exitCode ; command: $command $args',
      );
      print(result.stdout);
      print(result.stderr);
    }

    return ok;
  }

  bool saveStdout(Directory rootDirectory, Object? stdout) =>
      _saveTo(rootDirectory, stdout, stdoutFilePath, 'STDOUT');

  bool saveStderr(Directory rootDirectory, Object? stderr) =>
      _saveTo(rootDirectory, stderr, stderrFilePath, 'STDERR');

  bool _saveTo(
    Directory rootDirectory,
    Object? output,
    String? filePath,
    String type,
  ) {
    if (output == null || filePath == null || filePath.isEmpty) return true;

    var fullPath = joinPaths(rootDirectory.path, filePath);

    print('   »  Saving $type to: $fullPath');

    var outFile = File(fullPath);

    if (output is String) {
      outFile.writeAsStringSync(output);
      return true;
    } else if (output is List<int>) {
      outFile.writeAsBytesSync(output);
      return true;
    } else {
      return false;
    }
  }

  @override
  String toString() {
    return 'ReleasePackerProcessCommand[$command $args]{stdoutFilePath: $stdoutFilePath, stderrFilePath: $stderrFilePath}';
  }
}

class ReleasePackerDartCommand extends ReleasePackerCommandWithArgs {
  ReleasePackerDartCommand(super.command, [super.args]);

  factory ReleasePackerDartCommand.fromList(List list) {
    var listStr = list.map((e) => '$e').toList();
    var command = listStr.removeAt(0);

    if (command == 'build' && listStr.isNotEmpty) {
      return ReleasePackerDartBuild.fromArgs(listStr);
    }

    return ReleasePackerDartCommand(command, listStr);
  }

  factory ReleasePackerDartCommand.from(Object command) {
    if (command is String) {
      var list = ReleasePackerCommand.parseInlineCommand(command);
      return ReleasePackerDartCommand.fromList(list);
    } else if (command is List) {
      return ReleasePackerDartCommand.fromList(command);
    } else {
      throw ArgumentError("Unknown command type: $command");
    }
  }

  @override
  bool execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    int expectedExitCode = 0,
  }) {
    var dartPath = whichExecutablePath('dart');

    print(
      '   »  Dart command> ${rootDirectory.path} -> $dartPath $command $args',
    );

    var result = Process.runSync(dartPath, [
      command,
      ...args,
    ], workingDirectory: rootDirectory.path);

    var exitCode = result.exitCode;
    var ok = exitCode == expectedExitCode;

    if (!ok) {
      print(
        '  ▒  Dart command error! exitCode: $exitCode ; command: $command $args',
      );
      print(result.stdout);
      print(result.stderr);

      if ('${result.stdout}\n${result.stderr}'.contains(
        'does not support build hooks',
      )) {
        print(
          '  ▒  A dependency has build hooks (native assets): '
          'use `dart_build_cli` (`dart build cli`) instead of '
          '`dart_compile_exe` (`dart compile exe`).',
        );
      }
    }

    return ok;
  }

  @override
  String toString() {
    return 'ReleasePackerDartCommand[$command $args]';
  }
}

class ReleasePackerDartPubGet extends ReleasePackerDartCommand {
  ReleasePackerDartPubGet() : super('pub', ['get']);

  @override
  String toString() {
    return 'ReleasePackerDartPubGet{}';
  }
}

class ReleasePackerDartCompileExe extends ReleasePackerDartCommand {
  ReleasePackerDartCompileExe(String dartScript)
    : super('compile', ['exe', dartScript]);

  @override
  String toString() {
    return 'ReleasePackerDartCompileExe[${args.last}]';
  }
}

class ReleasePackerDartCompileKernel extends ReleasePackerDartCommand {
  ReleasePackerDartCompileKernel(String dartScript)
    : super('compile', ['kernel', dartScript]);

  @override
  String toString() {
    return 'ReleasePackerDartCompileKernel[${args.last}]';
  }
}

/// A `dart build <subcommand>` command.
///
/// Declared in JSON as `dart_build_<subcommand>`, like `dart_build_cli`
/// ([ReleasePackerDartBuildCli]). Other subcommands receive the arguments
/// as is: a `String` (inline command) or a `List`.
class ReleasePackerDartBuild extends ReleasePackerDartCommand {
  static final RegExp _jsonKeyRegExp = RegExp(r'^dart_build_(\w+)$');

  /// The `dart build` subcommand, like `cli`.
  final String subcommand;

  ReleasePackerDartBuild(this.subcommand, [List<String>? args])
    : super('build', [subcommand, ...?args]);

  /// The subcommand of a `dart_build_<subcommand>` JSON [key], or `null`.
  static String? subcommandOfJsonKey(Object? key) =>
      key is String ? _jsonKeyRegExp.firstMatch(key)?.group(1) : null;

  /// Returns `true` if [key] is a `dart_build_<subcommand>` JSON key.
  static bool isJsonKey(Object? key) => subcommandOfJsonKey(key) != null;

  /// The commands of the `dart_build_<subcommand>` entries of [map].
  static List<ReleasePackerDartBuild> fromJsonMap(Map map) => map.entries
      .map((e) {
        var subcommand = subcommandOfJsonKey(e.key);
        return subcommand != null
            ? ReleasePackerDartBuild.fromJson(subcommand, e.value)
            : null;
      })
      .nonNulls
      .toList();

  /// Creates a `dart build` [subcommand] from a `dart_build_<subcommand>`
  /// JSON value.
  factory ReleasePackerDartBuild.fromJson(String subcommand, Object? json) {
    if (subcommand == 'cli') {
      return ReleasePackerDartBuildCli.fromJson(json);
    }

    List<String> args;
    if (json == null || json == true) {
      args = <String>[];
    } else if (json is String) {
      args = ReleasePackerCommand.parseInlineCommand(json);
    } else if (json is List) {
      args = json.map((e) => '$e').toList();
    } else {
      throw ArgumentError("Invalid `dart_build_$subcommand` value: $json");
    }

    return ReleasePackerDartBuild(subcommand, args);
  }

  /// Creates a command from the `dart build` [args]: `[subcommand, ...]`.
  ///
  /// The arguments are kept as is, including for `cli`: see
  /// [ReleasePackerDartBuildCli] for the default `--output`.
  factory ReleasePackerDartBuild.fromArgs(List<String> args) {
    if (args.isEmpty) {
      throw ArgumentError("Empty `dart build` subcommand!");
    }
    return ReleasePackerDartBuild(args.first, args.sublist(1));
  }

  @override
  String toString() {
    return 'ReleasePackerDartBuild[$subcommand ${args.skip(1).toList()}]';
  }
}

/// A `dart build cli` command: required when a dependency has build hooks
/// (native assets), as `dart compile exe` does NOT support them.
///
/// It builds a bundle at `<output>/bundle/`:
/// ```text
/// bin/<name>      (<name>.exe on Windows)
/// lib/<dynamic libraries>
/// ```
///
/// The executable loads the dynamic libraries from `../lib/`, relative to
/// itself, so the release must keep the `bin/` and `lib/` layout.
///
/// With [launcher], a script at the bundle root (`<name>`, or `<name>.cmd` on
/// Windows) runs `bin/<name>`, keeping the path of a release that used to
/// have the executable at its root.
class ReleasePackerDartBuildCli extends ReleasePackerDartBuild {
  /// The main Dart script, like `bin/foo.dart`.
  final String target;

  /// The output directory, where the `bundle/` is built.
  final String output;

  /// If `true` generates a launcher script at the bundle root.
  final bool launcher;

  /// The [output] must be relative to the root directory: the bundle is
  /// mapped from it. The [args] can't set the target or the output: use
  /// [target] and [output].
  factory ReleasePackerDartBuildCli(
    String target, {
    String? output,
    List<String>? args,
    bool launcher = false,
  }) {
    var outputPath = normalizeOutput(output ?? defaultOutput(target));

    var reserved = args?.firstWhereOrNull(_isReservedArg);
    if (reserved != null) {
      throw ArgumentError(
        "`dart_build_cli` arguments can't set the target or the output "
        "(use `target` and `output`): $reserved",
      );
    }

    return ReleasePackerDartBuildCli._(target, outputPath, args, launcher);
  }

  ReleasePackerDartBuildCli._(
    this.target,
    this.output,
    List<String>? args,
    this.launcher,
  ) : super('cli', ['--target', target, '--output', output, ...?args]);

  static bool _isReservedArg(String a) =>
      a == '--target' ||
      a == '--output' ||
      a.startsWith('--target=') ||
      a.startsWith('--output=') ||
      a.startsWith('-t') ||
      a.startsWith('-o');

  /// Normalizes an [output] path (`./build/out` -> `build/out`).
  ///
  /// Throws an [ArgumentError] if it's absolute or outside the root
  /// directory: the bundle couldn't be mapped into the release.
  static String normalizeOutput(String output) {
    var normalized = pack_path.posix.normalize(output.replaceAll(r'\', '/'));

    if (pack_path.posix.isAbsolute(normalized) ||
        pack_path.windows.isAbsolute(output) ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError(
        "`dart_build_cli` output must be a directory inside the root "
        "directory: $output",
      );
    }

    return normalized;
  }

  /// The first [ReleasePackerDartBuildCli] in [commands], or `null`.
  static ReleasePackerDartBuildCli? firstOf(
    Iterable<ReleasePackerCommand>? commands,
  ) => commands?.whereType<ReleasePackerDartBuildCli>().firstOrNull;

  /// Creates a command from a `dart_build_cli` JSON value: the [target]
  /// (`String`) or a `Map` with `target`, and the optional `output`, `args`
  /// and `launcher`.
  factory ReleasePackerDartBuildCli.fromJson(Object? json) {
    if (json is String) {
      return ReleasePackerDartBuildCli(json);
    } else if (json is Map) {
      var target = json['target'];
      if (target is! String || target.isEmpty) {
        throw ArgumentError("`dart_build_cli` without a `target`: $json");
      }

      var output = json['output'] as String?;

      var args = json['args'];
      var argsList = args is String
          ? ReleasePackerCommand.parseInlineCommand(args)
          : (args as List?)?.map((e) => '$e').toList();

      var launcher = json['launcher'];

      return ReleasePackerDartBuildCli(
        target,
        output: output,
        args: argsList,
        launcher: launcher == true || '$launcher'.toLowerCase() == 'true',
      );
    } else {
      throw ArgumentError("Invalid `dart_build_cli` value: $json");
    }
  }

  /// The default [output] of a [target]: `build/cli/<name>`.
  ///
  /// Always passed to `dart build cli`: its own default
  /// (`build/cli/<os>_<arch>/`) is shared by all the targets.
  static String defaultOutput(String target) => 'build/cli/${nameOf(target)}';

  /// The executable name of a [target]: its file name without extension.
  static String nameOf(String target) =>
      pack_path.basenameWithoutExtension(target);

  /// The executable name: the [target] file name without extension.
  String get name => nameOf(target);

  /// The path of the built bundle: `<output>/bundle`.
  String get bundlePath => pack_path.posix.join(output, 'bundle');

  /// Returns `true` if building for Windows: the `--target-os` argument, or
  /// the current platform.
  bool get targetsWindows {
    for (var i = 0; i < args.length; ++i) {
      var a = args[i];
      if (a.startsWith('--target-os=')) {
        return a.substring('--target-os='.length) == 'windows';
      } else if (a == '--target-os' && i + 1 < args.length) {
        return args[i + 1] == 'windows';
      }
    }
    return Platform.isWindows;
  }

  /// The path of the built executable: `<output>/bundle/bin/<name>`.
  String get executablePath => pack_path.posix.join(
    bundlePath,
    'bin',
    targetsWindows ? '$name.exe' : name,
  );

  /// The path of the [launcher] script: `<output>/bundle/<name>`.
  String get launcherPath =>
      pack_path.posix.join(bundlePath, targetsWindows ? '$name.cmd' : name);

  /// The [launcher] script content.
  ///
  /// The POSIX script resolves symbolic links to itself (like one in
  /// `/usr/local/bin`), to find the bundle directory.
  String get launcherScript => targetsWindows
      ? '@echo off\r\n"%~dp0bin\\$name.exe" %*\r\n'
      : '#!/bin/sh\n'
            'p="\$0"\n'
            'while [ -L "\$p" ]; do\n'
            '  t="\$(readlink "\$p")"\n'
            '  case "\$t" in\n'
            '    /*) p="\$t" ;;\n'
            '    *) p="\$(dirname "\$p")/\$t" ;;\n'
            '  esac\n'
            'done\n'
            'exec "\$(dirname "\$p")/bin/$name" "\$@"\n';

  @override
  bool execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    int expectedExitCode = 0,
  }) {
    var ok = super.execute(
      releasePacker,
      rootDirectory,
      releaseBundle: releaseBundle,
      expectedExitCode: expectedExitCode,
    );
    if (!ok) return false;

    var executable = File(pack_path.join(rootDirectory.path, executablePath));
    if (!executable.existsSync()) {
      print("  ▒  Can't find the built executable: ${executable.path}");
      return false;
    }

    print(
      '   »  Built bundle: ${pack_path.join(rootDirectory.path, bundlePath)}',
    );

    if (launcher) {
      writeLauncher(rootDirectory);
    }

    return true;
  }

  /// Writes the [launcher] script at the bundle root.
  File writeLauncher(Directory rootDirectory) {
    var file = File(pack_path.join(rootDirectory.path, launcherPath));
    file.writeAsStringSync(launcherScript);

    if (!targetsWindows) {
      ReleaseStorageDirectory.setFileExecutablePermission(file, true);
    }

    print('   »  Launcher: ${file.path} -> bin/$name');
    return file;
  }

  @override
  String toString() {
    return 'ReleasePackerDartBuildCli[$target -> $bundlePath]';
  }
}

class ReleasePackerWindowsSubsystemCommand
    extends ReleasePackerCommandWithArgs {
  ReleasePackerWindowsSubsystemCommand(
    bool gui,
    String executableFile,
    String outputFile,
  ) : super('release_utility', [
        gui ? '--windows-gui' : '--windows-console',
        executableFile,
        outputFile,
      ]);

  factory ReleasePackerWindowsSubsystemCommand.fromList(List list) {
    var listStr = list.map((e) => '$e').toList();

    if (listStr.first == 'release_utility') {
      listStr.removeAt(0);
    }

    var argGuiIdx = listStr.indexOf('--windows-gui');
    var argConsoleIdx = listStr.indexOf('--windows-console');

    var argGUI = false;
    if (argGuiIdx >= 0) {
      listStr.removeAt(argGuiIdx);
      argGUI = true;
    }

    if (argConsoleIdx >= 0) {
      listStr.removeAt(argConsoleIdx);
      argGUI = false;
    }

    var executable =
        listStr.firstWhereOrNull((e) => e.endsWith('.exe')) ?? listStr.first;

    var output =
        listStr.lastWhereOrNull((e) => e.endsWith('.exe')) ?? listStr.last;

    return ReleasePackerWindowsSubsystemCommand(argGUI, executable, output);
  }

  factory ReleasePackerWindowsSubsystemCommand.from(Object command) {
    if (command is String) {
      var list = ReleasePackerCommand.parseInlineCommand(command);
      return ReleasePackerWindowsSubsystemCommand.fromList(list);
    } else if (command is List) {
      return ReleasePackerWindowsSubsystemCommand.fromList(command);
    } else {
      throw ArgumentError("Unknown command type: $command");
    }
  }

  @override
  bool execute(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    int expectedExitCode = 0,
  }) {
    var executableOutputPath = args.last;

    var inputPath = resolveInputPath(rootDirectory);

    var outputPath = pack_path.normalize(
      pack_path.join(rootDirectory.path, executableOutputPath),
    );

    var inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      print("  ▒  Can't find Windows executable file: $inputPath");
      return false;
    }

    var outputFile = File(outputPath);
    if (outputFile.existsSync() && inputFile.path != outputFile.path) {
      print("  ▒  Can't overwrite output file: $outputPath");
      return false;
    }

    var argGUI = args.contains('--windows-gui');
    var argConsole = args.contains('--windows-console');

    bool gui;
    if (argGUI && argConsole) {
      print("  ▒  Ambiguous parameters: $args");
      return false;
    } else if (argGUI) {
      gui = true;
    } else if (argConsole) {
      gui = false;
    } else {
      print("  ▒  No `--windows-gui` or `--windows-console` parameters: $args");
      return false;
    }

    print(
      '   »  Windows Subsystem command> ${rootDirectory.path} -> GUI: $gui ; executable: $inputPath',
    );

    WindowsPEFile windowsPEFile;
    try {
      windowsPEFile = WindowsPEFile(inputFile);
    } catch (e, s) {
      print("  ▒  Error opening Windows Executable: $inputPath");
      print(e);
      print(s);
      return false;
    }

    try {
      if (!windowsPEFile.isValidExecutable) {
        print(
          "   »  IGNORING Windows Subsystem command> Not a valid Windows Executable: $inputPath",
        );
        return false;
      }

      windowsPEFile.setWindowsSubsystem(gui: gui);

      if (inputFile.path == outputFile.path) {
        var inputFileCp = _resolveInputFileCopy(inputFile);

        if (inputFileCp != null) {
          inputFile.renameSync(inputFileCp.path);
          windowsPEFile.save(outputFile);

          if (!outputFile.existsSync() ||
              outputFile.lengthSync() != windowsPEFile.fileBuffer.length) {
            print(
              '  ▒  Error saving executable file: ${outputFile.path} (copy: ${inputFileCp.path})',
            );
            return false;
          }

          inputFileCp.deleteSync();

          print('   »  Executable saved: ${outputFile.path}');
        }
      } else {
        windowsPEFile.save(outputFile);
        print('   »  New executable saved: ${outputFile.path}');
      }

      // Re-open and test:
      windowsPEFile = WindowsPEFile(outputFile);

      var windowsSubsystem = windowsPEFile.readWindowsSubsystem();
      var expectedWindowsSubsystem = gui ? 2 : 3;

      if (windowsSubsystem != expectedWindowsSubsystem) {
        print(
          "  ▒  Windows Subsystem Error> "
          "Value not set to `$expectedWindowsSubsystem` (${WindowsPEFile.windowsSubsystemName(expectedWindowsSubsystem)}). "
          "Read value: `$windowsSubsystem` (${WindowsPEFile.windowsSubsystemName(windowsSubsystem)})",
        );
        return false;
      } else {
        print(
          "   »  Windows Subsystem> "
          "Current value: `$windowsSubsystem` (${WindowsPEFile.windowsSubsystemName(windowsSubsystem)}) "
          "@ $outputFile",
        );
      }
    } catch (e, s) {
      print(e);
      print(s);
      return false;
    }

    return true;
  }

  /// Resolves the input executable path at [rootDirectory].
  String resolveInputPath(Directory rootDirectory) => pack_path.normalize(
    pack_path.join(rootDirectory.path, args[args.length - 2]),
  );

  /// Returns `true` if the input file exists but is NOT a Windows executable.
  ///
  /// This is the usual case when building on another platform: there's no
  /// Windows Subsystem to set, and it's not a build error.
  bool isNotAWindowsExecutable(Directory rootDirectory) {
    var inputFile = File(resolveInputPath(rootDirectory));

    // A missing or unreadable input file IS an error, reported by `execute`:
    if (!inputFile.existsSync()) return false;

    try {
      return !WindowsPEFile(inputFile).isValidExecutable;
    } catch (_) {
      return false;
    }
  }

  @override
  FutureOr<ReleasePackerCommandStatus> executeStatus(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
  }) {
    if (isNotAWindowsExecutable(rootDirectory)) {
      print(
        "   »  IGNORING Windows Subsystem command> "
        "Not a valid Windows Executable: ${resolveInputPath(rootDirectory)}",
      );
      return ReleasePackerCommandStatus.ignored;
    }

    return super.executeStatus(
      releasePacker,
      rootDirectory,
      releaseBundle: releaseBundle,
    );
  }

  File? _resolveInputFileCopy(File inputFile) {
    var inputFileName = pack_path.withoutExtension(inputFile.path);
    var inputFileExt = pack_path.extension(inputFile.path);

    for (var i = 1; i <= 1000; ++i) {
      var fCp = '$inputFileName-copy$i$inputFileExt';
      var f = File(fCp);
      if (!f.existsSync()) {
        return f;
      }
    }

    return null;
  }

  @override
  String toString() {
    return 'ReleasePackerWindowsSubsystemCommand[$command $args]';
  }
}

abstract class ReleasePackerOperation extends ReleasePackerEntry {
  List<ReleasePackerCommand>? commands;

  ReleasePackerOperation({super.platform, this.commands});

  bool get hasCommands => commands != null && commands!.isNotEmpty;

  bool hasCommandOfType<T extends ReleasePackerCommand>() =>
      hasCommands && commands!.whereType<T>().isNotEmpty;

  /// Runs the [commands] of this operation.
  ///
  /// Throws a [ReleasePackerError] if a command fails.
  Future<Map<ReleasePackerCommand, ReleasePackerCommandStatus>> executeCommands(
    ReleasePacker releasePacker,
    Directory rootDirectory, {
    ReleaseBundle? releaseBundle,
    String? platform,
    String? context,
  }) => ReleasePackerCommand.executeCommands(
    releasePacker,
    commands,
    rootDirectory,
    releaseBundle: releaseBundle,
    platform: platform,
    context: context,
  );
}

class ReleasePackerFile extends ReleasePackerOperation {
  String sourcePath;

  String destinyPath;

  ReleasePackerFile(
    this.sourcePath,
    String destinyPath, {
    super.platform,
    String? dartCompileExe,
    String? dartCompileKernel,
    List<ReleasePackerDartBuild>? dartBuilds,
    String? windowsGUI,
  }) : destinyPath = _normalizeDestinyPath(sourcePath, destinyPath),
       super(
         commands: ReleasePackerCommand.toCommands(
           sourcePath: sourcePath,
           dartCompileExe: dartCompileExe,
           dartCompileKernel: dartCompileKernel,
           dartBuilds: dartBuilds,
           windowsGUI: windowsGUI,
         ),
       );

  /// `.` is the [sourcePath]; `/` and `./` are the release root (`''`),
  /// to map a directory (like a `dart build cli` bundle) to the root.
  static String _normalizeDestinyPath(String sourcePath, String destinyPath) {
    if (destinyPath == '.') return sourcePath;
    if (destinyPath == '/' || destinyPath == './') return '';
    return destinyPath;
  }

  factory ReleasePackerFile.fromJson(Object json) {
    if (json is String) {
      return ReleasePackerFile(json, json);
    } else if (json is Map) {
      var platform = json['platform'];
      var dartCompileExe = json['dart_compile_exe'] as String?;
      var dartCompileKernel = json['dart_compile_kernel'] as String?;
      var dartBuilds = ReleasePackerDartBuild.fromJsonMap(json);
      var windowsGUI = json['windows_gui'];

      var dartBuildCli = ReleasePackerDartBuildCli.firstOf(dartBuilds);

      var entry = json.entries
          .where(
            (e) =>
                e.key != 'platform' &&
                e.key != 'dart_compile_exe' &&
                e.key != 'dart_compile_kernel' &&
                e.key != 'windows_gui' &&
                !ReleasePackerDartBuild.isJsonKey(e.key),
          )
          .firstOrNull;

      String sourcePath;
      String destinyPath;

      if (entry != null) {
        sourcePath = entry.key;
        destinyPath = entry.value;
      } else if (dartBuildCli != null) {
        // Only `dart_build_cli`: its bundle goes to the release root.
        sourcePath = '${dartBuildCli.bundlePath}/';
        destinyPath = '';
      } else {
        throw ArgumentError("No file path in: $json");
      }

      if (windowsGUI is bool && windowsGUI) {
        windowsGUI =
            dartCompileExe ?? dartBuildCli?.executablePath ?? sourcePath;
      }

      return ReleasePackerFile(
        sourcePath,
        destinyPath,
        platform: platform,
        dartCompileExe: dartCompileExe,
        dartCompileKernel: dartCompileKernel,
        dartBuilds: dartBuilds.isNotEmpty ? dartBuilds : null,
        windowsGUI: windowsGUI,
      );
    } else {
      throw ArgumentError("Unknown type: $json");
    }
  }

  @override
  String toString() {
    var commandsStr = commands != null ? '<<${commands!.join(' ; ')}>>' : '';
    return 'ReleasePackerFile{ path: $sourcePath -> $destinyPath, platform: $platforms }$commandsStr';
  }
}
