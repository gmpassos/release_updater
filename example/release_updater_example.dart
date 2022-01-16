import 'dart:io';

import 'package:release_updater/release_updater_io.dart';

void main() async {
  var storage = ReleaseStorageDirectory('appx', Directory('/install/path'));

  var provider =
      ReleaseProviderHttp.baseURL('https://your.domain/appx/releases');

  var releaseUpdater = ReleaseUpdater(storage, provider);

  print('-- Updating...');
  var updatedToVersion = await releaseUpdater.update();

  if (updatedToVersion != null) {
    print('-- Updated to version: $updatedToVersion');
  }

  var runResult = await releaseUpdater.runReleaseProcess('run.exe', ['-a']);

  var exitCode = runResult!.exitCode;

  print('-- Exit code: $exitCode');
  print('-- Result: ${runResult.stdout}');

  exit(exitCode);
}
