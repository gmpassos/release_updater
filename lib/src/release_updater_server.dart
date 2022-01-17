import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:shelf/shelf.dart' as shelf;

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

shelf.Handler processServerRequest(
    shelf.Handler handler, Directory releasesDir, BasicCredential? credential) {
  return (request) {
    var requestInfo = resolveRequestInfo(request);

    requestInfo.markRequest();
    if (requestInfo.isBlocked()) {
      return shelf.Response.forbidden('Blocked');
    }

    if (credential != null) {
      var response =
          _processUpLoad(request, releasesDir, credential, requestInfo);
      if (response != null) return response;
    }

    return handler(request);
  };
}

FutureOr<shelf.Response>? _processUpLoad(
    shelf.Request request,
    Directory releasesDir,
    BasicCredential credential,
    RequestInfo requestInfo) {
  if (request.method != 'POST') return null;

  var queryParameters = request.url.queryParameters;

  var file = queryParameters['file'];
  if (file == null || file.isEmpty) return null;

  var user = queryParameters['username'] ?? queryParameters['user'];
  var pass = queryParameters['password'] ?? queryParameters['pass'];

  var address = requestInfo.address.address;

  if (credential.username != user || credential.password != pass) {
    print("** Upload ERROR[$address]> Invalid authentication!");
    requestInfo.markError();
    return shelf.Response.forbidden('Authentication error.');
  }

  return request.read().toBytes().then((body) {
    var response = _saveUploadedFile(releasesDir, file, body, address);
    if (response == null) {
      requestInfo.markError();
      return shelf.Response.internalServerError();
    }
    var responseJson = dart_convert.json.encode(response);
    return shelf.Response.ok(responseJson);
  });
}

final _regExpNonWord = RegExp(r'\W');

Map<String, Object?>? _saveUploadedFile(
    Directory releasesDir, String paramFile, Uint8List bytes, String address) {
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

  return {'file': fileName, 'bytes': savedBytes};
}
