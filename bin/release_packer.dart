import 'dart:io';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:release_updater/src/release_updater_config.dart';

const _hr1 =
    '══════════════════════════════════════════════════════════════════════════════';

const _hr2 =
    '──────────────────────────────────────────────────────────────────────────────';

void main(List<String> args) async {
  var dartVersion = Platform.version.split(' ')[0];
  var operatingSystem = Platform.operatingSystem;

  var title =
      'release_packer/${ReleaseUpdater.VERSION} | Dart $dartVersion ($operatingSystem)';

  print('''
╔══${'═' * title.length}${'═' * (_hr1.length - title.length - 6)}══╗
║  $title ${' ' * (_hr1.length - title.length - 6)} ║
╚══${'═' * title.length}${'═' * (_hr1.length - title.length - 6)}══╝
''');

  if (args.length < 2) {
    print('USAGE:\n');
    print(
        ' \$> release_packer release_packer.json build ./source-dir ./releases-dir -Puser=pass\n');

    print(
        ' \$> release_packer release_packer.json info ./source-dir [generate]\n');

    exit(0);
  }

  args = args.toList();

  var releasePackerJsonPath = args.removeAt(0);
  var allowEnv = args.remove('--allow-env');
  var properties = parseProperties(args);

  var cmd = args.removeAt(0).toLowerCase();

  print('»  Current directory: ${Directory.current.path}');

  print('»  Loading `ReleasePacker` from: $releasePackerJsonPath');
  var releasePacker = ReleasePacker.fromFilePath(
    releasePackerJsonPath,
    properties: properties,
    allowPropertiesFromEnv: allowEnv,
  );

  if (cmd == 'info') {
    var sourcePath = args.isNotEmpty ? args[0] : './';
    var generateBundle = args.where((a) => a.contains('generate')).isNotEmpty;

    _showReleasePacker(releasePacker, showFiles: true);

    if (generateBundle) {
      ReleaseBundleZip releaseBundle =
          await _buildReleaseBundle(releasePacker, sourcePath);

      await _showBundleFiles(releaseBundle);
    }
  } else if (cmd == 'build') {
    var sourcePath = args.isNotEmpty ? args[0] : './';
    var releasesPath = args.length > 1 ? args[1] : './';

    _showReleasePacker(releasePacker);

    ReleaseBundleZip releaseBundle =
        await _buildReleaseBundle(releasePacker, sourcePath, releasesPath);

    await _showBundleFiles(releaseBundle);

    var releasesDir = Directory(releasesPath).absolute;

    var releaseZipPath = pack_path.normalize(pack_path.join(
        releasesDir.path, '${releaseBundle.release.asFileName}.zip'));

    var releaseZipFile = File(releaseZipPath).absolute;

    print('»  Generating Release Zip...');
    var zipBytes = await releaseBundle.zipBytes;
    releaseZipFile.writeAsBytesSync(zipBytes);

    print('»  Release Zip size: ${releaseZipFile.lengthSync()} bytes.');

    print(
        '\n»  Release `${releaseBundle.release}` saved at:\n\n  ${releaseZipFile.path}\n');
  } else {
    print('▒  Unknown command: $cmd $args\n');
    exit(1);
  }

  print(_hr1);
  exit(0);
}

void _showReleasePacker(ReleasePacker releasePacker, {bool showFiles = false}) {
  print('\n»  Release name: ${releasePacker.name}');
  print('»  Release version: ${releasePacker.version}');

  var prepareCommands = releasePacker.prepareCommands;
  if (prepareCommands != null) {
    print('\n»  Prepare commands (${prepareCommands.length}):');
    for (var cmd in prepareCommands) {
      print('   -  $cmd');
    }
  }

  var finalizeCommands = releasePacker.finalizeCommands;
  if (finalizeCommands != null) {
    print('\n»  Finalize commands (${finalizeCommands.length}):');
    for (var cmd in finalizeCommands) {
      print('   -  $cmd');
    }
  }

  if (showFiles) {
    var files = releasePacker.files;
    print('\n»  Files ${files.length}:');

    for (var f in files) {
      print('   »  $f');
    }
  }
}

Future<ReleaseBundleZip> _buildReleaseBundle(
    ReleasePacker releasePacker, String sourcePath,
    [String? releasesPath]) async {
  print('\n$_hr2');

  print('\n»»  Generating release bundle...\n');

  print(
      '»  Building release from `$sourcePath`${releasesPath != null ? ' to `$releasesPath`' : ''}');

  var platform = ReleasePlatform.platform;

  var releaseBundle = await releasePacker.buildFromDirectory(
      sourcePath: sourcePath, platform: platform);

  print('»  Generated release: `${releaseBundle.release}`');
  return releaseBundle;
}

Future<void> _showBundleFiles(ReleaseBundleZip releaseBundle) async {
  var files = await releaseBundle.files;

  print('\n»  Bundle files (${files.length}):');

  var asciiArtTree = await releaseBundle.toASCIIArtTree();
  var tree = asciiArtTree.generate(indent: '   ║  ', trim: true);

  print('\n$tree\n');
}
