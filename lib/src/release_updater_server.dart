import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:path/path.dart' as pack_path;

import 'release_updater_utils.dart';

final Map<String, RequestInfo> _requestsInfos = <String, RequestInfo>{};

RequestInfo resolveRequestInfo(
  shelf.Request request,
) {
  final connectionInfo =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo;

  return resolveAddressRequestInfo(connectionInfo.remoteAddress);
}

RequestInfo resolveAddressRequestInfo(InternetAddress remoteAddress) {
  var requestInfo =
      _requestsInfos[remoteAddress.address] ??= RequestInfo(remoteAddress);
  return requestInfo;
}

class RequestInfo {
  final InternetAddress address;

  RequestInfo(this.address);

  final QueueList<DateTime> _requestsTime = QueueList<DateTime>();

  void markRequest({DateTime? now}) {
    now ??= DateTime.now();
    _requestsTime.add(now);
  }

  final QueueList<DateTime> _errorsTime = QueueList<DateTime>();

  void markError({DateTime? now}) {
    now ??= DateTime.now();
    _errorsTime.add(now);
  }

  static final Duration _requestsTimeout = Duration(minutes: 2);
  static final Duration _errorsTimeout = Duration(minutes: 30);

  void purge({DateTime? now}) {
    now ??= DateTime.now();

    _purgeImpl(_requestsTime, now, _requestsTimeout);
    _purgeImpl(_errorsTime, now, _errorsTimeout);
  }

  void _purgeImpl(QueueList<DateTime> list, DateTime now, Duration timeout) {
    while (list.isNotEmpty) {
      var t = list.first;
      var elapsed = now.difference(t);
      if (elapsed > timeout) {
        list.removeFirst();
      } else {
        break;
      }
    }
  }

  bool isBlocked({DateTime? now}) {
    purge(now: now);

    if (_errorsTime.length > 10) return true;
    if (_requestsTime.length > 50) return true;

    return false;
  }

  @override
  String toString() {
    return 'RequestInfo{address: $address, requests: ${_requestsTime.length}, errors: ${_errorsTime.length}';
  }
}

shelf.Handler processServerRequest(shelf.Handler handler, Directory releasesDir,
    BasicCredential? credential, File releasesFile) {
  return (request) {
    var requestInfo = resolveRequestInfo(request);

    requestInfo.markRequest();
    if (requestInfo.isBlocked()) {
      return shelf.Response.forbidden('Blocked');
    }

    if (credential != null) {
      var response = _processUpLoad(
          request, releasesDir, credential, releasesFile, requestInfo);
      if (response != null) return response;
    }

    final urlPath = request.url.path;

    switch (urlPath) {
      case 'RELEASES':
        return _processReleases(releasesFile);
      case 'RELEASES-FILES':
        return _processReleasesFiles(releasesDir);
      case 'RELEASES-URL':
      case 'RELEASES-URLS':
        return _processReleasesURLs(releasesDir, request.requestedUri);
      default:
        break;
    }

    return handler(request);
  };
}

shelf.Response _processReleases(File releasesFile) {
  var content = releasesFile.readAsStringSync();

  return shelf.Response.ok(content, headers: {
    HttpHeaders.contentTypeHeader: 'text/plain',
  });
}

shelf.Response _processReleasesFiles(Directory releasesDir) {
  Iterable<String> filesPaths = _listReleasesFilesPaths(releasesDir);

  var content = filesPaths.join('\n') + '\n';

  return shelf.Response.ok(content, headers: {
    HttpHeaders.contentTypeHeader: 'text/plain',
  });
}

shelf.Response _processReleasesURLs(Directory releasesDir, Uri requestedURL) {
  var basePaths = requestedURL.pathSegments.toList();
  if (basePaths.isNotEmpty) {
    basePaths.removeAt(0);
  }

  var filesPaths = _listReleasesFilesPaths(releasesDir);

  var urls = filesPaths
      .map((f) => [...basePaths, f].join('/'))
      .map((p) => requestedURL.replace(path: p))
      .toList();

  var content = urls.join('\n') + '\n';

  return shelf.Response.ok(content, headers: {
    HttpHeaders.contentTypeHeader: 'text/plain',
  });
}

List<String> _listReleasesFilesPaths(Directory releasesDir) {
  var files = releasesDir
      .listSync()
      .where((f) => f.path.endsWith('.zip'))
      .whereType<File>()
      .toList();

  var filesPaths = files.map((f) => pack_path.split(f.path).last).toList();
  filesPaths.sort();

  return filesPaths;
}

FutureOr<shelf.Response>? _processUpLoad(
    shelf.Request request,
    Directory releasesDir,
    BasicCredential credential,
    File releasesFile,
    RequestInfo requestInfo) {
  if (request.method != 'POST') return null;

  var queryParameters = request.url.queryParameters;

  var file = queryParameters['file'];
  if (file == null || file.isEmpty) return null;

  var release = queryParameters['release'];

  var address = requestInfo.address.address;

  var requestCredential = _parseRequestCredential(request);

  if (credential.username != requestCredential.username ||
      credential.password != requestCredential.password) {
    print("** Upload ERROR[$address]> Invalid authentication!");
    requestInfo.markError();
    return shelf.Response.forbidden('Authentication error.');
  }

  return request.read().toBytes().then((body) {
    var response = _saveUploadedFile(
        releasesDir, file, body, releasesFile, release, address);
    if (response == null) {
      requestInfo.markError();
      return shelf.Response.internalServerError();
    }
    var responseJson = dart_convert.json.encode(response);
    return shelf.Response.ok(responseJson);
  });
}

BasicCredential _parseRequestCredential(
  shelf.Request request,
) {
  var headerAuthorization = request.headers['authorization'];

  if (headerAuthorization != null && headerAuthorization.isNotEmpty) {
    var headerAuthorizationLc = headerAuthorization.toLowerCase();
    if (headerAuthorizationLc.startsWith('basic')) {
      var base64 = headerAuthorization.split(RegExp(r'\s+'))[1].trim();
      return BasicCredential.base64(base64);
    }
  }

  var queryParameters = request.url.queryParameters;
  var user = queryParameters['username'] ?? queryParameters['user'] ?? '';
  var pass = queryParameters['password'] ?? queryParameters['pass'] ?? '';

  return BasicCredential(user, pass);
}

final _regExpNonWord = RegExp(r'\W');

Map<String, Object?>? _saveUploadedFile(Directory releasesDir, String paramFile,
    Uint8List bytes, File releasesFile, String? release, String address) {
  if (bytes.isEmpty) {
    print("** Upload ERROR[$address]> Empty release file: $paramFile");
    return null;
  }

  var fileParts = splitGenericPathSeparator(paramFile);
  var fileName = fileParts.last.trim();

  if (fileName.isEmpty ||
      fileName.startsWith('.') ||
      fileName.replaceAll(_regExpNonWord, '').isEmpty) {
    print("** Upload ERROR[$address]> Invalid release file: $paramFile");
    return null;
  }

  var filePath = joinPaths(releasesDir.path, fileName);

  var file = File(filePath);

  if (file.existsSync()) {
    print(
        "** Upload ERROR[$address]> Can't overwrite release file: ${file.path}");
    return null;
  }

  file.writeAsBytesSync(bytes);

  var savedBytes = file.lengthSync();

  print(
      '-- Upload[$address]> Saved release file: ${file.path} ($savedBytes bytes)');

  var result = {'file': fileName, 'bytes': savedBytes};

  if (release != null) {
    appendToReleasesFile(releasesFile, release);
  }

  return result;
}

bool appendToReleasesFile(File releasesFile, String release) {
  release = release.trim();
  if (release.isEmpty) return false;

  if (!releasesFile.existsSync()) return false;

  var lines = readReleasesFileLines(releasesFile);
  if (lines.contains(release)) return false;

  lines.add(release);
  lines.sort();

  var content = lines.join('\n') + '\n';

  releasesFile.writeAsStringSync(content);

  print('-- Appended `$release` to releases file: ${releasesFile.path}');

  showReleasesFile(releasesFile);
  print('');

  return true;
}

void showReleasesFile(File releasesFile) {
  if (!releasesFile.existsSync()) return;

  var lines = readReleasesFileLines(releasesFile);

  var content = '  -- ' + lines.join('\n  -- ');

  print('\n-- Releases File: ${releasesFile.path}');
  print(content);
}

List<String> readReleasesFileLines(File releasesFile) {
  if (!releasesFile.existsSync()) {
    return <String>[];
  }

  var content = releasesFile.readAsStringSync();

  var lines = content
      .split(RegExp(r'[\r\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  return lines;
}
