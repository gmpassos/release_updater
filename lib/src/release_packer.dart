import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:yaml/yaml.dart';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_config.dart';
import 'release_updater_io.dart';

class ReleasePacker {
  final String name;
  final Version version;
  final List<ReleasePackerCommand>? prepareCommands;
  final List<ReleasePackerCommand>? finalizeCommands;
  final List<ReleasePackerFile> files;
  final Map<String, String> properties;
  final Directory? configDirectory;

  ReleasePacker(this.name, this.version, this.files,
      {this.prepareCommands,
      this.finalizeCommands,
      Map<String, String>? properties,
      this.configDirectory})
      : properties = properties ?? <String, String>{};

  factory ReleasePacker.fromJson(Map<String, Object?> json,
      {Map<String, String>? properties, Directory? rootDirectory}) {
    json = resolveJsonMapProperties(json, properties);

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

    return ReleasePacker(name, version, releaseFiles,
        prepareCommands: prepareCommands,
        finalizeCommands: finalizeCommands,
        properties: properties,
        configDirectory: rootDirectory);
  }

  factory ReleasePacker.fromFilePath(String filePath,
      {Map<String, String>? properties, Directory? rootDirectory}) {
    var file = _toFile(filePath, rootDirectory);
    return ReleasePacker.fromFile(file,
        properties: properties, rootDirectory: rootDirectory);
  }

  factory ReleasePacker.fromFile(File file,
      {Map<String, String>? properties, Directory? rootDirectory}) {
    var json = _readFile(file);
    return ReleasePacker.fromJson(json,
        properties: properties, rootDirectory: rootDirectory ?? file.parent);
  }

  static File _toFile(String filePath, Directory? rootDirectory) {
    var path = joinPaths((rootDirectory ?? Directory.current).path, filePath);
    return File(path);
  }

  static dynamic _readFilePath(String filePath, Directory? rootDirectory) {
    var file = _toFile(filePath, rootDirectory);
    return _readFile(file);
  }

  static _readFile(File file) {
    if (!file.existsSync()) return null;

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
    var where = files.where((e) => e.sourcePath == filePath);
    if (platform != null) {
      where = where.where((e) => e.matchesPlatform(platform));
    }
    return where.firstOrNull;
  }

  ReleasePackerFile? getFileMatching(RegExp filePathRegexp) =>
      files.firstWhereOrNull((e) => filePathRegexp.hasMatch(e.sourcePath));

  Future<Map<ReleasePackerCommand, bool>> prepare(Directory rootDirectory,
      {String? platform}) {
    var prepareCommands = this.prepareCommands;
    if (prepareCommands != null && prepareCommands.isNotEmpty) {
      print('\n-- Running prepared commands (${prepareCommands.length})...');
    }

    return ReleasePackerCommand.executeCommands(
        this, prepareCommands, rootDirectory,
        platform: platform);
  }

  Future<Map<ReleasePackerCommand, bool>> finalize(Directory rootDirectory,
      {ReleaseBundle? releaseBundle, String? platform}) {
    var finalizeCommands = this.finalizeCommands;
    if (finalizeCommands != null && finalizeCommands.isNotEmpty) {
      print('\n-- Running finalize commands (${finalizeCommands.length})...');
    }

    return ReleasePackerCommand.executeCommands(
        this, finalizeCommands, rootDirectory,
        releaseBundle: releaseBundle, platform: platform);
  }

  Future<ReleaseBundleZip> buildFromDirectory(
      {Directory? rootDirectory, String? sourcePath, String? platform}) async {
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

    await prepare(rootDirectory, platform: platform);

    for (var f in getFiles(platform: platform).where((e) => e.hasCommands)) {
      await f.executeCommands(this, rootDirectory, platform: platform);
    }

    var files = rootDirectory.listSync(recursive: true);

    var rootPath = rootDirectory.path;

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

          var file = File(e.path);

          var destinyPath = packFile.destinyPath;
          var data = file.readAsBytesSync();
          var time = file.lastModifiedSync();
          var exec = ReleaseBundleZip.isExecutableFilePath(destinyPath);

          return ReleaseFile(destinyPath, data, time: time, executable: exec);
        })
        .whereType<ReleaseFile>()
        .toList();

    var release = Release(name, version, platform: platform);
    var releaseBundle = ReleaseBundleZip(release, files: list);

    await finalize(rootDirectory,
        releaseBundle: releaseBundle, platform: platform);

    return releaseBundle;
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

  static RegExp _toRegExp(e) => e is RegExp ? e : RegExp('$e');

  bool matchesPlatform(String? platform) {
    if (platforms.isEmpty || platform == null || platform.isEmpty) return true;
    platform = platform.trim();

    for (var re in platforms) {
      if (re.hasMatch(platform)) return true;
    }

    return false;
  }
}

abstract class ReleasePackerCommand extends ReleasePackerEntry {
  static List<ReleasePackerCommand>? toCommands(
      {String? dartCompileExe, List? jsonList}) {
    var commands = <ReleasePackerCommand>[];

    if (dartCompileExe != null) {
      commands.add(ReleasePackerDartCompileExe(dartCompileExe));
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
    } else if (command is List) {
      return ReleasePackerProcessCommand.fromList(command);
    } else if (command is Map) {
      var map = command.asJsonMap;

      var dartCompileExe = map.get<String>('dart_compile_exe');
      if (dartCompileExe != null && dartCompileExe.isNotEmpty) {
        return ReleasePackerDartCompileExe(dartCompileExe);
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
        return ReleasePackerProcessCommand.from(cmd,
            stdoutFilePath: stdout, stderrFilePath: stderr);
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
      RegExp(r'(?:(\s+)|"(.*?)")'),
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

  FutureOr<bool> execute(ReleasePacker releasePacker, Directory rootDirectory,
      {ReleaseBundle? releaseBundle});

  static Future<Map<ReleasePackerCommand, bool>> executeCommands(
      ReleasePacker releasePacker,
      List<ReleasePackerCommand>? commands,
      Directory rootDirectory,
      {ReleaseBundle? releaseBundle,
      String? platform}) async {
    var results = <ReleasePackerCommand, bool>{};
    if (commands == null || commands.isEmpty) return results;

    for (var c in commands.where((e) => e.matchesPlatform(platform))) {
      var ok = await c.execute(releasePacker, rootDirectory,
          releaseBundle: releaseBundle);
      results[c] = ok;
    }

    return results;
  }
}

abstract class ReleasePackerCommandWithArgs extends ReleasePackerCommand {
  final String command;

  final List<String> args;

  ReleasePackerCommandWithArgs(String command, [List<String>? args])
      : command = command.trim(),
        args = args?.toList() ?? <String>[] {
    if (command.isEmpty) {
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
  FutureOr<bool> execute(ReleasePacker releasePacker, Directory rootDirectory,
      {ReleaseBundle? releaseBundle}) {
    var filePath = joinPaths(rootDirectory.path, path);
    var file = File(filePath);

    if (file.existsSync()) {
      print('-- Deleting file: $filePath');
      file.deleteSync();
      return true;
    }

    return false;
  }
}

class ReleasePackerCommandURL extends ReleasePackerCommand {
  final String url;
  final Map<String, Object?>? parameters;

  final Credential? authorization;
  final Object? body;

  ReleasePackerCommandURL(this.url,
      {this.parameters, this.authorization, this.body}) {
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

      return ReleasePackerCommandURL(url,
          parameters: parameters?.asJsonMap,
          authorization: credential,
          body: body);
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
      var pass = map.get<String>('password') ??
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
  Future<bool> execute(ReleasePacker releasePacker, Directory rootDirectory,
      {ReleaseBundle? releaseBundle}) async {
    Object? body;

    if (this.body == '%RELEASE_BUNDLE%') {
      if (releaseBundle == null) {
        print('** Release bundle not provided for body: $this');
        return false;
      }
      body = await releaseBundle.toBytes();
    } else {
      body = this.body;
    }

    var httpClient = HttpClient(url);

    HttpResponse response;

    if (body != null) {
      print('-- Requesting URL[POS]: $url');

      String bodyStr;
      if (body is List<int>) {
        bodyStr = '${body.length} bytes';
      } else {
        bodyStr = '<<$body>>';
      }

      print('-- Body: $bodyStr');

      try {
        response = await httpClient.post('',
            parameters: parameters, authorization: authorization, body: body);
      } catch (e) {
        print('** Error requesting: $url > $e');
        return false;
      }
    } else {
      print('-- Requesting URL[GET]: $url');

      try {
        response = await httpClient.get(
          '',
          parameters: parameters,
          authorization: authorization,
        );
      } catch (e) {
        print('** Error requesting: $url > $e');
        return false;
      }
    }

    print(
        '-- Request response> status: ${response.status} ; body: ${response.bodyAsString}');

    return response.isOK;
  }

  @override
  String toString() {
    return '$runtimeType{ url: $url, parameters: $parameters, authorization: $authorization, body: $body }';
  }
}

class ReleasePackerCommandUploadReleaseBundle extends ReleasePackerCommandURL {
  ReleasePackerCommandUploadReleaseBundle(String url,
      {Map<String, Object?>? parameters, Credential? authorization})
      : super(url,
            parameters: parameters,
            authorization: authorization,
            body: '%RELEASE_BUNDLE%');

  factory ReleasePackerCommandUploadReleaseBundle.fromJson(Object json) {
    var cmd = ReleasePackerCommandURL.fromJson(json);
    return ReleasePackerCommandUploadReleaseBundle(cmd.url,
        parameters: cmd.parameters, authorization: cmd.authorization);
  }
}

class ReleasePackerProcessCommand extends ReleasePackerCommandWithArgs {
  final String? stdoutFilePath;
  final String? stderrFilePath;

  ReleasePackerProcessCommand(String command,
      [List<String>? args, this.stdoutFilePath, this.stderrFilePath])
      : super(command, args);

  factory ReleasePackerProcessCommand.fromList(List list,
      {String? stdoutFilePath, String? stderrFilePath}) {
    var listStr = list.map((e) => '$e').toList();
    var command = listStr.removeAt(0);
    return ReleasePackerProcessCommand(
        command, listStr, stdoutFilePath, stderrFilePath);
  }

  factory ReleasePackerProcessCommand.inline(String fullCommand,
      {String? stdoutFilePath, String? stderrFilePath}) {
    var list = ReleasePackerCommand.parseInlineCommand(fullCommand);
    var command = list.removeAt(0);
    return ReleasePackerProcessCommand(
        command, list, stdoutFilePath, stderrFilePath);
  }

  factory ReleasePackerProcessCommand.from(Object command,
      {String? stdoutFilePath, String? stderrFilePath}) {
    if (command is String) {
      return ReleasePackerProcessCommand.inline(command,
          stdoutFilePath: stdoutFilePath, stderrFilePath: stderrFilePath);
    } else if (command is List) {
      return ReleasePackerProcessCommand.fromList(command,
          stdoutFilePath: stdoutFilePath, stderrFilePath: stderrFilePath);
    } else {
      throw ArgumentError("Unknown command type: $command");
    }
  }

  @override
  bool execute(ReleasePacker releasePacker, Directory rootDirectory,
      {ReleaseBundle? releaseBundle, int expectedExitCode = 0}) {
    String commandPath;
    if (!containsGenericPathSeparator(command)) {
      commandPath = whichExecutablePath(command);
    } else {
      commandPath = command;
    }

    var fullCommandPath = joinPaths(rootDirectory.path, commandPath);

    print(
        '-- Process command> ${rootDirectory.path} -> $fullCommandPath $args');

    var result = Process.runSync(fullCommandPath, args,
        workingDirectory: rootDirectory.path);

    saveStdout(rootDirectory, result.stdout);
    saveStderr(rootDirectory, result.stderr);

    var exitCode = result.exitCode;
    var ok = exitCode == expectedExitCode;

    if (!ok) {
      print('** Command error! exitCode: $exitCode ; command: $command $args');
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
      Directory rootDirectory, Object? output, String? filePath, String type) {
    if (output == null || filePath == null || filePath.isEmpty) return true;

    var fullPath = joinPaths(rootDirectory.path, filePath);

    print('-- Saving $type to: $fullPath');

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
  ReleasePackerDartCommand(String command, [List<String>? args])
      : super(command, args);

  factory ReleasePackerDartCommand.fromList(List list) {
    var listStr = list.map((e) => '$e').toList();
    var command = listStr.removeAt(0);
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
  bool execute(ReleasePacker releasePacker, Directory rootDirectory,
      {ReleaseBundle? releaseBundle, int expectedExitCode = 0}) {
    var dartPath = whichExecutablePath('dart');

    print('-- Dart command> ${rootDirectory.path} -> $dartPath $command $args');

    var result = Process.runSync(dartPath, [command, ...args],
        workingDirectory: rootDirectory.path);

    var exitCode = result.exitCode;
    var ok = exitCode == expectedExitCode;

    if (!ok) {
      print(
          '** Dart command error! exitCode: $exitCode ; command: $command $args');
      print(result.stdout);
      print(result.stderr);
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

abstract class ReleasePackerOperation extends ReleasePackerEntry {
  List<ReleasePackerCommand>? commands;

  ReleasePackerOperation({Object? platform, this.commands})
      : super(platform: platform);

  bool get hasCommands => commands != null && commands!.isNotEmpty;

  bool hasCommandOfType<T extends ReleasePackerCommand>() =>
      hasCommands && commands!.whereType<T>().isNotEmpty;

  Future<Map<ReleasePackerCommand, bool>> executeCommands(
          ReleasePacker releasePacker, Directory rootDirectory,
          {ReleaseBundle? releaseBundle, String? platform}) =>
      ReleasePackerCommand.executeCommands(
          releasePacker, commands, rootDirectory,
          releaseBundle: releaseBundle, platform: platform);
}

class ReleasePackerFile extends ReleasePackerOperation {
  String sourcePath;

  String destinyPath;

  ReleasePackerFile(this.sourcePath, String destinyPath,
      {Object? platform, String? dartCompileExe})
      : destinyPath = destinyPath == '.' ? sourcePath : destinyPath,
        super(
            platform: platform,
            commands: ReleasePackerCommand.toCommands(
                dartCompileExe: dartCompileExe));

  factory ReleasePackerFile.fromJson(Object json) {
    if (json is String) {
      return ReleasePackerFile(json, json);
    } else if (json is Map) {
      var platform = json['platform'];
      var dartCompileExe = json['dart_compile_exe'];
      var entry = json.entries
          .where((e) => e.key != 'platform' && e.key != 'dart_compile_exe')
          .first;
      return ReleasePackerFile(entry.key, entry.value,
          platform: platform, dartCompileExe: dartCompileExe);
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
