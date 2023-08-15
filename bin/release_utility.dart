import 'dart:io';

import 'package:release_updater/release_updater.dart';
import 'package:release_updater/release_utility.dart';

void printTitle() {
  print('--------------------------------------------------------------------');
  print('[ release_utility/${ReleaseUpdater.VERSION} ]\n');
}

void showUsage() {
  printTitle();

  print('USAGE:\n');
  print('  Set windows executable to GUI subsystem:');
  print('    \$> release_utility --verbose --windows-gui %file\n');
  print('  Set windows executable to Console subsystem:');
  print('    \$> release_utility --verbose --windows-console %file\n');
}

void main(List<String> args) async {
  if (args.isEmpty) {
    showUsage();
    exit(0);
  }

  final argsOrig = args;
  args = args.toList();

  var cmdHelp = _removeArgsCmd(args, '--help') || _removeArgsCmd(args, '-h');

  if (cmdHelp) {
    showUsage();
    exit(0);
  }

  var cmdWindowConsole = _removeArgsCmd(args, '--windows-console');
  var cmdWindowGUI = _removeArgsCmd(args, '--windows-gui');
  var cmdVerbose = _removeArgsCmd(args, '--verbose');

  if (cmdWindowConsole && cmdWindowGUI) {
    print('** Ambiguous commands: $argsOrig');
    exit(1);
  }

  var filePath = args[0];
  var file = File(filePath);

  if (!file.existsSync()) {
    print("** File does NOT exist: $filePath");
    exit(1);
  }

  printTitle();

  print('-- File: $filePath');

  var windowPEFile = WindowPEFile(file, verbose: cmdVerbose);

  if (cmdWindowConsole) {
    print('-- Setting executable Windows Subsystem to `console`...');
    windowPEFile.setWindowsSubsystem(gui: false);
  } else if (cmdWindowGUI) {
    print('-- Setting executable Windows Subsystem to `GUI`...');
    windowPEFile.setWindowsSubsystem(gui: true);
  } else {
    print('-- Showing Windows PE information:');
  }

  windowPEFile.close();

  var windowPEFile2 = WindowPEFile(file, verbose: cmdVerbose);

  var windowsSubsystem = windowPEFile2.readWindowsSubsystem();

  var windowsSubsystemName = switch (windowsSubsystem) {
    0 => 'unknown',
    2 => 'GUI',
    3 => 'console',
    _ => '?',
  };

  print(
      '-- Current Windows Subsystem: $windowsSubsystem ($windowsSubsystemName)');
}

bool _removeArgsCmd(List<String> args, String cmd) {
  var idx = args.indexOf(cmd);
  if (idx < 0) return false;
  args.removeAt(idx);
  return true;
}
