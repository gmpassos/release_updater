@TestOn('vm')
import 'dart:io';
import 'dart:typed_data';

import 'package:release_updater/release_utility.dart';
import 'package:test/test.dart';

void main() {
  group('WindowsPEFile', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('windows-pe--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    File testExeFile() {
      var filePath = 'project-foo/bin/foo-windows64.exe';
      var filePossiblePaths = [filePath, 'test/$filePath', '../test/$filePath'];

      return filePossiblePaths
          .map((p) => File(p))
          .firstWhere((f) => f.existsSync());
    }

    File writeFile(String name, List<int> bytes) {
      var file = File('${tmpDir.path}/$name');
      file.writeAsBytesSync(bytes);
      return file;
    }

    test('windowsSubsystemName', () {
      expect(WindowsPEFile.windowsSubsystemName(0), equals('unknown'));
      expect(WindowsPEFile.windowsSubsystemName(2), equals('GUI'));
      expect(WindowsPEFile.windowsSubsystemName(3), equals('console'));
      expect(WindowsPEFile.windowsSubsystemName(9), equals('?'));
    });

    test('seekToWindowsSubsystem', () {
      var peFile = WindowsPEFile(testExeFile());

      var offset = peFile.seekToWindowsSubsystem();

      expect(offset, greaterThan(128));
      expect(peFile.isValidExecutable, isTrue);
      expect(peFile.machineType, equals(0x8664));
    });

    test('invalid PE signature', () {
      var bytes = Uint8List(256);
      // `e_lfanew` (4 bytes at 0x3c) pointing to 0x80:
      bytes[0x3c] = 0x80;

      var file = writeFile('invalid-signature.exe', bytes);

      var peFile = WindowsPEFile(file, verbose: true);

      expect(peFile.isValidExecutable, isFalse);
      expect(() => peFile.readInformation(), throwsStateError);
      expect(() => peFile.readWindowsSubsystem(), throwsStateError);
      expect(() => peFile.seekToWindowsSubsystem(), throwsStateError);
    });

    test('not an executable image', () {
      var bytes = Uint8List(512);
      bytes[0x3c] = 0x80;

      // PE signature (big-endian `0x50450000`) at 0x80:
      bytes[0x80] = 0x50;
      bytes[0x81] = 0x45;

      // `characteristics` (at 0x80 + 4 + 2 + 14) without
      // `IMAGE_FILE_EXECUTABLE_IMAGE` (0x0002):
      bytes[0x80 + 22] = 0x00;
      bytes[0x80 + 23] = 0x00;

      var file = writeFile('not-executable.exe', bytes);

      var peFile = WindowsPEFile(file);

      expect(peFile.isValidExecutable, isFalse);
      expect(
        () => peFile.readInformation(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Not an executable binary'),
          ),
        ),
      );
    });

    test('not a PE32/PE32+ optional header', () {
      var bytes = Uint8List(512);
      bytes[0x3c] = 0x80;

      bytes[0x80] = 0x50;
      bytes[0x81] = 0x45;

      // `characteristics` with `IMAGE_FILE_EXECUTABLE_IMAGE`:
      bytes[0x80 + 22] = 0x02;

      // `optionalHeaderMagic` (at 0x80 + 24) with an invalid value:
      bytes[0x80 + 24] = 0xFF;
      bytes[0x80 + 25] = 0xFF;

      var file = writeFile('invalid-optional-header.exe', bytes);

      var peFile = WindowsPEFile(file);

      expect(peFile.isValidExecutable, isFalse);
      expect(
        () => peFile.readInformation(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Not a normal executable'),
          ),
        ),
      );
    });

    test('machine types', () {
      var peFile = WindowsPEFile(testExeFile());

      expect(peFile.isMachineTypeX64, isTrue);
      expect(peFile.isMachineTypeI386, isFalse);
      expect(peFile.isMachineTypeItanium, isFalse);
      expect(peFile.isMachineTypeARM, isFalse);
      expect(peFile.isMachineTypeARM64, isFalse);
    });

    test('setWindowsSubsystem of an incompatible subsystem', () {
      var exeFile = testExeFile();

      var file = File('${tmpDir.path}/copy.exe');
      exeFile.copySync(file.path);

      var peFile = WindowsPEFile(file);

      // Sets an unsupported subsystem value (`1`: native):
      peFile.writeWindowsSubsystem(1);
      expect(peFile.readWindowsSubsystem(), equals(1));

      expect(() => peFile.setWindowsSubsystem(gui: true), throwsStateError);
    });

    test("save can't overwrite", () {
      var exeFile = testExeFile();

      var peFile = WindowsPEFile(exeFile);

      var outputFile = File('${tmpDir.path}/out.exe');

      peFile.save(outputFile);
      expect(outputFile.lengthSync(), equals(exeFile.lengthSync()));

      expect(() => peFile.save(outputFile), throwsStateError);

      peFile.save(outputFile, overwrite: true);
      expect(outputFile.lengthSync(), equals(exeFile.lengthSync()));
    });
  });
}
