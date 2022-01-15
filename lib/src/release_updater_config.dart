import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as pack_path;

Map<String, Object?> parseConfig(List<String> args) {
  var config = <String, Object?>{};

  if (args.isEmpty) return config;

  for (var i = 0; i < args.length;) {
    var a = args[i];
    if (a.startsWith('--') && i < args.length - 1) {
      var v = args[i + 1];
      config[a] = v;
      args.removeAt(i + 1);
      args.removeAt(i);
    } else {
      ++i;
    }
  }

  if (args.isNotEmpty) {
    var configFilePath = args[0];
    if (configFilePath.endsWith('.json')) {
      args.removeAt(0);

      var configFile = File(configFilePath);

      if (!configFile.existsSync() || configFile.lengthSync() <= 2) {
        return config;
      }

      var configJson = configFile.readAsStringSync();

      var config2 = json.decode(configJson) as Map<String, Object?>;
      config.addAll(config2);
    }
  }

  return config;
}

String _normalizeKey(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

extension JsonExtension on Map<String, Object?> {
  V? get<V>(String key, [V? def]) {
    var val = _get(key);
    if (val == null) return def;
    if (val is V) return val as V;

    if (V == String) {
      return '$val' as V;
    } else if (V == int) {
      return (int.tryParse('$val') as V?) ?? def;
    } else if (V == double) {
      return (double.tryParse('$val') as V?) ?? def;
    }

    return val as V;
  }

  Object? _get(String key) {
    var val = this[key];
    if (val != null) return val;

    key = _normalizeKey(key);

    for (var e in entries) {
      var k = _normalizeKey(e.key);
      if (k == key) return e.value;
    }

    return null;
  }
}

Directory parseReleaseDirectory(Map<String, Object?> config) {
  var releasesDirPath = config.get<String>('releases-directory', 'releases')!;

  if (releasesDirPath.startsWith('/')) {
    return Directory(releasesDirPath);
  } else {
    var executableFile = File(Platform.script.toFilePath());
    var executableDir = executableFile.parent;

    var releasesDir =
        Directory(pack_path.join(executableDir.path, releasesDirPath));
    return releasesDir;
  }
}

int parsePort(Map<String, Object?> config) {
  var port = config.get<int>('port', 8080)!;
  return port;
}

String parseAddress(Map<String, Object?> config) {
  var address = config.get<String>('address', 'localhost')!;
  return address;
}

String parseAppName(Map<String, Object?> config) {
  var name = config.get<String>('name', 'app')!;
  return name;
}

String parseBaseURL(Map<String, Object?> config) {
  var baseURL = config.get<String>('base-url');
  if (baseURL == null) {
    var port = parsePort(config);
    baseURL = 'http://localhost:$port/';
  }
  return baseURL;
}
