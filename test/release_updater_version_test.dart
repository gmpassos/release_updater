@TestOn('vm')
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pubspec/pubspec.dart';
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseUpdater.VERSION', () {
    setUp(() {});

    test('Check Version', () async {
      var projectDirectory = Directory.current;

      print(projectDirectory);

      var pubspecFile = File(path.join(projectDirectory.path, 'pubspec.yaml'));

      print('pubspecFile: $pubspecFile');

      var pubSpec = await PubSpec.loadFile(pubspecFile.path);

      print('PubSpec.name: ${pubSpec.name}');
      print('PubSpec.version: ${pubSpec.version}');

      var srcPath = path.join(
          projectDirectory.path, 'lib\\src/release_updater_base.dart');

      srcPath = normalizePlatformPath(srcPath);

      var srcFile = File(srcPath);

      print(srcFile);

      var src = srcFile.readAsStringSync();

      var versionMatch = RegExp(r"VERSION\s*=\s*'(.*?)'").firstMatch(src)!;

      var srcVersion = versionMatch.group(1);

      print('srcVersion: $srcVersion');

      expect(pubSpec.version.toString(), equals(srcVersion),
          reason:
              'Bones_API.VERSION[$srcVersion] != PubSpec.version[${pubSpec.version}]');
    });
  });
}
