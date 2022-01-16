import 'package:path/path.dart' as pack_path;

final RegExp _genericSeparator = RegExp(r'[\\/]');

final pack_path.Context _contextWindows =
    pack_path.Context(style: pack_path.Style.windows);
final pack_path.Context _contextPosix =
    pack_path.Context(style: pack_path.Style.posix);

bool isGenericPathSeparator(String separator) =>
    (separator == '/' || separator == '\\');

final RegExp _genericSeparatorStart = RegExp(r'^[\\/]+[^\\/]');

bool startsWithGenericPathSeparator(String path) =>
    _genericSeparatorStart.hasMatch(path);

final RegExp _genericSeparatorEnd = RegExp(r'[^\\/][\\/]+?$');

bool endsWithGenericPathSeparator(String path) =>
    _genericSeparatorEnd.hasMatch(path);

final RegExp _genericURIStart =
    RegExp(r'^(?:file|https?|[a-zA-Z]{2,}):[\\//]+');

bool startsWithURI(String path) => _genericURIStart.hasMatch(path);

final RegExp _fileSchemeStart = RegExp(r'^file:[\\/]+');

bool startsWithFileScheme(String path) => _fileSchemeStart.hasMatch(path);

final RegExp _fileSchemeWithHostStart = RegExp(r'^file:[\\/]{1,2}\w+[\\/]+');

bool startsWithFileSchemeWithHost(String path) =>
    _fileSchemeWithHostStart.hasMatch(path);

final RegExp _driverStart = RegExp(r'^[a-zA-Z]:[\\/]');

bool startsWithDriver(String path) => _driverStart.hasMatch(path);

/// Returns `true` if [path] is root relative (platform agnostic).
bool isRootRelativePath(String path) {
  return startsWithURI(path) ||
      startsWithDriver(path) ||
      startsWithGenericPathSeparator(path) ||
      pack_path.isRootRelative(path);
}

/// Resolves a [pack_path.Context].
pack_path.Context getPathContext(
    {bool asWindows = false,
    bool asPosix = false,
    pack_path.Context? pathContext}) {
  if (pathContext != null) return pathContext;

  if (asWindows) {
    return pack_path.context.style != pack_path.Style.windows
        ? _contextWindows
        : pack_path.context;
  } else if (asPosix) {
    return pack_path.context.style != pack_path.Style.posix
        ? _contextPosix
        : pack_path.context;
  }

  return pack_path.context;
}

/// Splits [path] in root prefix and path (platform agnostic).
List<String> splitPathRootPrefix(String path,
    {String? separator,
    bool asWindows = false,
    bool asPosix = false,
    pack_path.Context? pathContext}) {
  if (path.isEmpty) {
    return ['', ''];
  }

  pathContext ??= getPathContext(
      asWindows: asWindows, asPosix: asPosix, pathContext: pathContext);

  separator ??= pathContext.separator;

  if (path.length == 1 && isGenericPathSeparator(path)) {
    return [separator, ''];
  }

  if (startsWithGenericPathSeparator(path)) {
    var path2 = path.substring(1);
    while (startsWithGenericPathSeparator(path2)) {
      path2 = path2.substring(1);
    }

    return [separator, path2];
  }

  if (startsWithURI(path)) {
    var parts = path.split(_genericURIStart);
    var path2 = parts[1];
    var prefix = path.substring(0, path.length - path2.length);

    if (separator == '/') {
      if (prefix == 'file:///') {
        return [prefix, path2];
      } else if (prefix == 'file://') {
        return ['$prefix/', path2];
      } else if (prefix == 'file:/') {
        return ['$prefix//', path2];
      }
    }

    while (endsWithGenericPathSeparator(prefix)) {
      prefix = prefix.substring(0, prefix.length - 1);
    }

    prefix += '$separator$separator';

    return [prefix, path2];
  }

  var rootPrefix = pathContext.rootPrefix(path);

  if (separator != rootPrefix && isGenericPathSeparator(rootPrefix)) {
    rootPrefix = separator;
  }

  String path2;
  if (rootPrefix.isNotEmpty) {
    path2 = path.substring(rootPrefix.length);
    return [rootPrefix, path2];
  } else {
    return ['', path];
  }
}

/// Normalizes [path] to a valid path for the [pathContext] (platform agnostic).
///
/// - If [asPosix] is `true` will use a POSIX context.
/// - If [asWindows] is `true` will use a Windows context.
String normalizePlatformPath(String path,
    {String? separator,
    bool asWindows = false,
    bool asPosix = false,
    pack_path.Context? pathContext}) {
  pathContext ??= getPathContext(
      asWindows: asWindows, asPosix: asPosix, pathContext: pathContext);

  separator ??= pathContext.separator;

  final rootPrefixSplit =
      splitPathRootPrefix(path, separator: separator, pathContext: pathContext);

  var rootPrefix = rootPrefixSplit[0];
  var pathNoRootPrefix = rootPrefixSplit[1];

  if (separator == '/') {
    if (startsWithFileScheme(path)) {
      if (!startsWithFileSchemeWithHost(path)) {
        if (startsWithDriver(pathNoRootPrefix)) {
          rootPrefix = 'file:///';
        } else {
          rootPrefix = '/';
        }
      } else {
        rootPrefix = 'file://';
      }
    } else if (startsWithDriver(pathNoRootPrefix)) {
      rootPrefix = 'file:///';
    }
  } else if (separator == '\\') {
    if (startsWithFileScheme(path)) {
      if (!startsWithFileSchemeWithHost(path)) {
        if (startsWithDriver(pathNoRootPrefix)) {
          rootPrefix = '';
        } else {
          rootPrefix = '\\';
        }
      } else {
        rootPrefix = 'file://';
      }
    }
  }

  var pathNormalized =
      _normalizeToPlatformPath(pathNoRootPrefix, separator, pathContext);

  return '$rootPrefix$pathNormalized';
}

String _normalizeToPlatformPath(
    String pathNoRootPrefix, String separator, pack_path.Context pathContext) {
  if (separator == '/') {
    if (!pathNoRootPrefix.contains('\\') &&
        pathContext.style == pack_path.Style.windows) {
      return pathContext.normalize(pathNoRootPrefix);
    }
  } else if (separator == '\\') {
    if (!pathNoRootPrefix.contains('/') &&
        pathContext.style != pack_path.Style.windows) {
      return pathContext.normalize(pathNoRootPrefix);
    }
  }

  var parts = pathNoRootPrefix.split(_genericSeparator);
  var pathStyled = parts.join(separator);
  var pathNormalized = pathContext.normalize(pathStyled);
  return pathNormalized;
}

/// Joins [parent] and [path], respecting if [path] is root relative (platform agnostic).
String joinPaths(String? parent, String path) {
  if (path.isEmpty) return '';

  path = normalizePlatformPath(path);
  if (parent == null || parent.isEmpty) {
    return path;
  }

  if (isRootRelativePath(path)) {
    return path;
  }

  parent = normalizePlatformPath(parent);

  var pathFull = pack_path.joinAll([parent, path]);

  pathFull = pack_path.normalize(pathFull);
  return pathFull;
}
