import 'dart:io';
import 'package:path/path.dart' as pack_path;
import 'package:test/test.dart';
import 'package:release_updater/release_utility.dart';

void main() {
  group('WindowPEFile', () {
    test('info', () {
      var filePath = 'project-foo/bin/foo-windows64.exe';
      var filePossiblePaths = [filePath, 'test/$filePath', '../test/$filePath'];

      var file = filePossiblePaths
          .map((p) => File(p))
          .firstWhere((f) => f.existsSync());

      var windowPEFile = WindowPEFile(file, verbose: true);

      var windowsSubsystem = windowPEFile.readWindowsSubsystem();
      // Expect `console` Windows Subsystem.
      expect(windowsSubsystem, 3);

      var peInfo = windowPEFile.readInformation();
      print(peInfo);

      expect(peInfo['windowsSubsystem'], 3);
      expect(peInfo['machineType'], 0x8664);

      expect(windowPEFile.isMachineTypeX64, isTrue);

      expect(windowPEFile.isMachineTypeI386, isFalse);
      expect(windowPEFile.isMachineTypeItanium, isFalse);
      expect(windowPEFile.isMachineTypeARM, isFalse);
      expect(windowPEFile.isMachineTypeARM64, isFalse);
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

      try {
        var windowPEFile = WindowPEFile(file2, verbose: true);

        var windowsSubsystem = windowPEFile.readWindowsSubsystem();
        // Expect `console` Windows Subsystem.
        expect(windowsSubsystem, 3);

        expect(windowPEFile.isMachineTypeX64, isTrue);

        windowPEFile.setWindowsSubsystem(gui: true);

        var windowsSubsystem2 = windowPEFile.readWindowsSubsystem();
        // Expect `GUI` Windows Subsystem.
        expect(windowsSubsystem2, 2);

        windowPEFile.setWindowsSubsystem(gui: false);

        var windowsSubsystem3 = windowPEFile.readWindowsSubsystem();
        // Expect `console` Windows Subsystem.
        expect(windowsSubsystem3, 3);
      } finally {
        file2.deleteSync();
      }
    });
  });
}
