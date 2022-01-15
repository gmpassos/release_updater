import 'dart:io';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_updater_io.dart';
import 'package:release_updater/src/release_updater_config.dart';

Directory parseReleaseDirectory(Map<String, Object?> config) {
  var executable = File(Platform.resolvedExecutable);
  var executableDir = executable.parent;

  var releasesDirPath = config.get<String>('releases-directory', 'releases')!;

  var releasesDir =
      Directory(pack_path.join(executableDir.path, releasesDirPath));

  return releasesDir;
}

void main(List<String> args) async {
  args = args.toList();

  print('--------------------------------------------------------------------');
  print('[ release_updater/${ReleaseUpdater.VERSION} ]\n');

  if (args.isEmpty) {
    print('USAGE:');
    print(' \$> release_updater config.json\n');

    exit(0);
  }

  var config = parseConfig(args);

  var appName = parseAppName(config);
  var releasesDir = parseReleaseDirectory(config);
  var baseURL = parseBaseURL(config);

  print('-- App Name: $appName');
  print('-- Base URL: $baseURL');
  print('-- Releases Directory: ${releasesDir.path}');

  if (!releasesDir.existsSync()) {
    print("\n** Directory doesn't exists: $releasesDir\n");
    exit(1);
  }

  var storage = ReleaseStorageDirectory(appName, releasesDir);
  var provider = ReleaseProviderHttp.baseURL(baseURL);

  var releaseUpdater = ReleaseUpdater(storage, provider);

  if (args.isNotEmpty) {
    await processCommand(releaseUpdater, args);
  } else {
    await updateRelease(releaseUpdater, storage);
  }
}

Future<void> updateRelease(
    ReleaseUpdater releaseUpdater, ReleaseStorageDirectory storage) async {
  var name = releaseUpdater.name;

  print('\n** [$name] Updating...');

  var currentRelease = storage.currentRelease;
  print('-- [$name] Current release: $currentRelease');

  var currentReleasePath = await storage.currentReleasePath;

  if (currentReleasePath != null) {
    var releaseDirectory = Directory(currentReleasePath).absolute;
    print('-- [$name] Current Release directory: ${releaseDirectory.path}');
  }

  var updatedRelease = await releaseUpdater.update();

  if (updatedRelease != null) {
    print('-- [$name] Updated to: $updatedRelease');

    currentReleasePath = await storage.currentReleasePath;

    if (currentReleasePath != null) {
      var releaseDirectory = Directory(currentReleasePath).absolute;
      print('-- [$name] Release directory: ${releaseDirectory.path}');
    }
  } else {
    print('-- [$name] Nothing to update!');
  }

  print('');
  exit(0);
}

Future<void> processCommand(
    ReleaseUpdater releaseUpdater, List<String> args) async {
  var cmd = args.removeAt(0).toLowerCase().trim();

  print('');

  var name = releaseUpdater.name;

  switch (cmd) {
    case 'check':
      {
        print('** [$name] Checking for update...');
        var currentRelease = await releaseUpdater.currentRelease;
        print('-- [$name] Current release: $currentRelease');
        var toUpdate = await releaseUpdater.checkForUpdate();
        if (toUpdate != null) {
          print('-- [$name] New release to update: $toUpdate');
        } else {
          print('-- [$name] NO new release!');
        }
        break;
      }
    case 'last':
      {
        print('** [$name] Getting last release...');
        var currentRelease = await releaseUpdater.currentRelease;
        print('-- [$name] Current release: $currentRelease');
        var lastRelease = releaseUpdater.lastRelease;
        print('-- [$name] Last release: $lastRelease');
        break;
      }
    case 'list':
      {
        print('** [$name] Listing releases...');
        var currentRelease = await releaseUpdater.currentRelease;
        print('-- [$name] Current release: $currentRelease');

        var releases = await releaseUpdater.listReleases();
        print('-- [$name] Releases:');
        for (var r in releases) {
          print('    -- $r');
        }
        break;
      }
    default:
      {
        print('** Unknown CMD: $args');
        exit(1);
      }
  }

  print('');
  exit(0);
}
