import 'dart:convert';
import 'dart:io';

import 'release_updater_utils.dart';

Map<String, String> parseProperties(List<String> args) {
  var properties = <String, String>{};

  for (var i = 0; i < args.length;) {
    var a = args[i];
    if (a.startsWith('-P') || a.startsWith('-D')) {
      var parts = a.split('=');
      var key = parts.removeAt(0).substring(2);
      var val = parts.isEmpty
          ? 'true'
          : (parts.length == 1 ? parts[0] : parts.join(';'));
      properties[key] = val;
      args.removeAt(i);
    } else {
      i++;
    }
  }

  return properties;
}

final RegExp _propertyPlaceHolder = RegExp(r'^%(\w+)%$');

String? resolvePropertyValue(Map<String, String> properties, String? value) {
  if (value == null) return null;

  var match = _propertyPlaceHolder.firstMatch(value);
  if (match == null) return value;

  var key = match.group(1)!;
  var propertyValue = properties.get(key);
  return propertyValue;
}

Object? resolveJsonProperties(Object? json, Map<String, String>? properties) {
  if (json == null || properties == null || properties.isEmpty) {
    return json;
  }

  if (json is String) {
    return resolvePropertyValue(properties, json);
  } else if (json is List) {
    return resolveJsonListProperties(json, properties);
  } else if (json is Map) {
    return resolveJsonMapProperties(json, properties);
  } else {
    return null;
  }
}

List<Object?> resolveJsonListProperties(
    List<Object?> jsonList, Map<String, String>? properties) {
  if (jsonList.isEmpty || properties == null || properties.isEmpty) {
    return jsonList;
  }

  var list = jsonList.map((e) => resolveJsonProperties(e, properties)).toList();

  return list;
}

Map<String, Object?> resolveJsonMapProperties(
    Map<Object?, Object?> jsonMap, Map<String, String>? properties) {
  if (jsonMap.isEmpty || properties == null || properties.isEmpty) {
    return jsonMap.asJsonMap;
  }

  var map = jsonMap.map((key, value) =>
      MapEntry('$key', resolveJsonProperties(value, properties)));

  return map;
}

Map<String, Object?> parseConfig(List<String> args) {
  var config = <String, Object?>{};

  if (args.isEmpty) return config;

  for (var i = 0; i < args.length;) {
    var a = args[i];
    if (a.startsWith('--') && i < args.length - 1) {
      var k = a.substring(2);
      var v = args[i + 1];
      config[k] = v;
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
    key.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

extension MapExtension on Map {
  Map<String, Object?> get asJsonMap => this is Map<String, Object?>
      ? (this as Map<String, Object?>)
      : map((key, value) => MapEntry('$key', value));
}

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
  var releasesDirPath = config.get<String>('releases-directory') ??
      config.get<String>('release-directory') ??
      'releases';

  if (releasesDirPath.startsWith('/')) {
    return Directory(releasesDirPath);
  } else {
    var executableFile = File(Platform.script.toFilePath());
    var executableDir = executableFile.parent;

    var releasesDir = Directory(joinPaths(executableDir.path, releasesDirPath));
    return releasesDir;
  }
}

String parseReleaseFile(Map<String, Object?> config) {
  var releasesFile = config.get<String>('releases-file') ??
      config.get<String>('release-file') ??
      'releases.txt';
  return releasesFile;
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
