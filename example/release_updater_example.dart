import 'dart:io';

import 'package:release_updater/release_updater_io.dart';

void main() async {
  var storage = ReleaseStorageDirectory('appx', Directory('/install/path'));
  var provider =
      ReleaseProviderHttp.baseURL('https://your.domain/appx/releases');

  var releaseUpdater = ReleaseUpdater(storage, provider);

  var version = await releaseUpdater.update();

  print('-- Updated to version: $version');
}
