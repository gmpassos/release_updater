@TestOn('vm')
import 'dart:io';

import 'package:release_updater/release_updater_io.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePlatform', () {
    test('osName', () {
      var osName = ReleasePlatform.osName;

      if (Platform.isLinux) {
        expect(osName, equals('linux'));
      } else if (Platform.isMacOS) {
        expect(osName, equals('macos'));
      } else if (Platform.isWindows) {
        expect(osName, equals('windows'));
      } else {
        expect(osName, isEmpty);
      }
    });

    test('architecture', () {
      var architecture = ReleasePlatform.architecture;

      expect(architecture, isNotEmpty);
      expect(architecture, matches(RegExp(r'^[\w-]+$')));

      // Cached:
      expect(ReleasePlatform.architecture, equals(architecture));

      if (Platform.isWindows) {
        expect(architecture, equals('x86'));
      } else {
        expect(architecture, isIn(['x64', 'arm64', 'arm', 'i386']));
      }
    });

    test('platform', () {
      var platform = ReleasePlatform.platform;

      expect(
        platform,
        equals('${ReleasePlatform.osName}-${ReleasePlatform.architecture}'),
      );
    });

    test('isMacOSArm64', () {
      var arm64 = ReleasePlatform.isMacOSArm64();

      if (!Platform.isMacOS) {
        expect(arm64, isFalse);
      } else {
        expect(arm64, equals(ReleasePlatform.architecture == 'arm64'));
        // Cached:
        expect(ReleasePlatform.isMacOSArm64(), equals(arm64));
      }
    });
  });
}
