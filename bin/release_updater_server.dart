import 'dart:async';
import 'dart:async' show runZonedGuarded;
import 'dart:io';

import 'package:mercury_client/mercury_client.dart';
import 'package:release_updater/src/release_updater_base.dart';
import 'package:release_updater/src/release_updater_config.dart';
import 'package:release_updater/src/release_updater_server.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_gzip/shelf_gzip.dart';
import 'package:shelf_static/shelf_static.dart';

const _hr =
    '────────────────────────────────────────────────────────────────────';

String? parseUploadUsername(Map<String, Object?> config) =>
    config.get<String>('upload-username') ?? config.get<String>('upload-user');

String? parseUploadPassword(Map<String, Object?> config) =>
    config.get<String>('upload-password') ?? config.get<String>('upload-pass');

void main(List<String> args) async {
  args = args.toList();

  print(_hr);
  print('[ release_updater_server/${ReleaseUpdater.VERSION} ]\n');

  var config = parseConfig(args);

  var port = parsePort(config);
  var address = parseAddress(config);
  var releasesDir = parseReleaseDirectory(config);
  var releasesFilePath = parseReleaseFile(config);

  var releasesFile = File(joinPaths(releasesDir.path, releasesFilePath));

  var uploadUsername = parseUploadUsername(config)?.trim();
  var uploadPassword = parseUploadPassword(config)?.trim();

  if (uploadPassword != null && uploadPassword.length < 6) {
    print(
        '▒  Upload password too short (length: ${uploadPassword.length} < 6)!');
    uploadPassword = null;
  }

  var allowUpload = uploadUsername != null &&
      uploadUsername.isNotEmpty &&
      uploadPassword != null &&
      uploadPassword.isNotEmpty;

  print('»  Releases Directory: ${releasesDir.path}');
  print('»  Address: $address');
  print('»  Port: $port');

  if (allowUpload) {
    print('»  Upload: enabled');
    print('»  Upload username: $uploadUsername');
    print('»  Upload password: ******');
  } else {
    print('»  Upload: disabled');
  }

  if (!releasesDir.existsSync()) {
    print("\n▒  Directory doesn't exists: $releasesDir\n");
    exit(1);
  }

  showReleasesFile(releasesFile);

  final uploadCredential =
      allowUpload ? BasicCredential(uploadUsername, uploadPassword) : null;

  var staticHandler =
      createStaticHandler(releasesDir.path, defaultDocument: 'index.html');

  runZonedGuarded(() async {
    var handler = const shelf.Pipeline()
        .addMiddleware(gzipMiddleware)
        .addMiddleware((handler) => processServerRequest(
            handler, releasesDir, uploadCredential, releasesFile))
        .addHandler(staticHandler);

    await shelf_io.serve(handler, address, port);

    print("\n»» Serving $releasesDir on $address:$port");
    print('URL: http://$address:$port/\n');
  }, (e, stackTrace) => print('Server error: $e $stackTrace'));
}
