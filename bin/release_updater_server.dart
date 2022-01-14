import 'dart:async';
import 'dart:async' show runZonedGuarded;
import 'dart:io';

import 'package:release_updater/src/release_updater_config.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_gzip/shelf_gzip.dart';
import 'package:shelf_static/shelf_static.dart';

void main(List<String> args) async {
  args = args.toList();

  print('--------------------------------------------------------------------');
  print('[ Release Updater - Server ]');

  var config = parseConfig(args);

  var port = parsePort(config);
  var address = parseAddress(config);
  var releasesDir = parseReleaseDirectory(config);

  print('-- Releases Directory: ${releasesDir.path}');
  print('-- Address: $address');
  print('-- Port: $port');

  if (!releasesDir.existsSync()) {
    print("\n** Directory doesn't exists: $releasesDir\n");
    exit(1);
  }

  var staticHandler =
      createStaticHandler(releasesDir.path, defaultDocument: 'index.html');

  runZonedGuarded(() async {
    var handler = const shelf.Pipeline()
        .addMiddleware(gzipMiddleware)
        .addHandler(staticHandler);

    await shelf_io.serve(handler, address, port);

    print("\n** Serving $releasesDir on $address:$port");
    print('URL: http://$address:$port/\n');
  }, (e, stackTrace) => print('Server error: $e $stackTrace'));
}
