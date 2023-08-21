import 'dart:io';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_utility.dart';
import 'package:test/test.dart';

void main() {
  group('WindowsPEFile', () {
    test('info', () {
      var filePath = 'project-foo/bin/foo-windows64.exe';
      var filePossiblePaths = [filePath, 'test/$filePath', '../test/$filePath'];

      var file = filePossiblePaths
          .map((p) => File(p))
          .firstWhere((f) => f.existsSync());

      var windowsPEFile = WindowsPEFile(file, verbose: true);

      var windowsSubsystem = windowsPEFile.readWindowsSubsystem();
      // Expect `console` Windows Subsystem.
      expect(windowsSubsystem, 3);

      var peInfo = windowsPEFile.readInformation();
      print(peInfo);

      expect(peInfo['windowsSubsystem'], 3);
      expect(peInfo['machineType'], 0x8664);
      expect(peInfo['checkSum'], 0);

      expect(windowsPEFile.isMachineTypeX64, isTrue);

      expect(windowsPEFile.isMachineTypeI386, isFalse);
      expect(windowsPEFile.isMachineTypeItanium, isFalse);
      expect(windowsPEFile.isMachineTypeARM, isFalse);
      expect(windowsPEFile.isMachineTypeARM64, isFalse);
    });

    test('Set Windows Subsystem', () {
      var filePath = 'project-foo/bin/foo-windows64.exe';
      var filePossiblePaths = [filePath, 'test/$filePath', '../test/$filePath'];

      var file = filePossiblePaths
          .map((p) => File(p))
          .firstWhere((f) => f.existsSync());

      var file2 = File(pack_path.join(Directory.systemTemp.path,
          'foo-windows64-cp${DateTime.now().millisecondsSinceEpoch}.exe'));

      file.copySync(file2.path);

      expect(file2.lengthSync(), equals(file.lengthSync()));

      var file2Edited =
          File('${pack_path.withoutExtension(file2.path)}-edited.exe');

      expect(file2Edited.existsSync(), isFalse);

      var windowsPEFile = WindowsPEFile(file2, verbose: true);
      try {
        expect(windowsPEFile.isValidExecutable, isTrue);

        var windowsSubsystem = windowsPEFile.readWindowsSubsystem();
        // Expect `console` Windows Subsystem.
        expect(windowsSubsystem, 3);

        expect(windowsPEFile.isMachineTypeX64, isTrue);

        windowsPEFile.setWindowsSubsystem(gui: true);

        var windowsSubsystem2 = windowsPEFile.readWindowsSubsystem();
        // Expect `GUI` Windows Subsystem.
        expect(windowsSubsystem2, 2);

        windowsPEFile.setWindowsSubsystem(gui: false);

        var windowsSubsystem3 = windowsPEFile.readWindowsSubsystem();
        // Expect `console` Windows Subsystem.
        expect(windowsSubsystem3, 3);

        {
          expect(file2Edited.existsSync(), isFalse);

          windowsPEFile.save(file2Edited);

          expect(file2Edited.existsSync(), isTrue);
          expect(file2Edited.lengthSync(), equals(file2.lengthSync()));

          expect(WindowsPEFile(file2Edited).readWindowsSubsystem(), 3);

          expect(file2Edited.readAsBytesSync(),
              equals(windowsPEFile.fileBuffer.toBytes()));
        }

        windowsPEFile.setWindowsSubsystem(gui: true);

        var windowsSubsystem4 = windowsPEFile.readWindowsSubsystem();
        // Expect `GUI` Windows Subsystem.
        expect(windowsSubsystem4, 2);

        {
          expect(file2Edited.existsSync(), isTrue);

          windowsPEFile.save(file2Edited, overwrite: true);

          expect(file2Edited.existsSync(), isTrue);
          expect(file2Edited.lengthSync(), equals(file2.lengthSync()));

          expect(WindowsPEFile(file2Edited).readWindowsSubsystem(), 2);

          expect(file2Edited.readAsBytesSync(),
              equals(windowsPEFile.fileBuffer.toBytes()));
        }
      } finally {
        file2.deleteSync();
        file2Edited.deleteSync();
      }
    });
  });
}
