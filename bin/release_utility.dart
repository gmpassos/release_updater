import 'dart:io';

import 'package:release_updater/release_updater.dart';
import 'package:release_updater/release_utility.dart';
import 'package:path/path.dart' as pack_path;

const _hr =
    '────────────────────────────────────────────────────────────────────';

void printTitle() {
  print(_hr);
  print('[ release_utility/${ReleaseUpdater.VERSION} ]\n');
}

void showUsage() {
  printTitle();

  print('USAGE:\n');
  print('  Set windows executable to GUI subsystem:');
  print('    \$> release_utility --verbose --windows-gui %file %output\n');
  print('  Set windows executable to Console subsystem:');
  print('    \$> release_utility --verbose --windows-console %file %output\n');
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
    print('▒  Ambiguous commands: $argsOrig');
    exit(1);
  }

  var filePath = args[0];
  var inputFile = File(filePath);

  if (!inputFile.existsSync()) {
    print("▒  File does NOT exist: $filePath");
    exit(1);
  }

  var outputFile = _resolveDefaultOutputFile(args, inputFile);
  if (outputFile == null) {
    throw StateError("Can't define output file!");
  } else if (outputFile.existsSync()) {
    throw StateError("Can't overwrite output file: ${outputFile.path}");
  }

  printTitle();

  print('»  Input File: ${inputFile.path}');

  var windowsPEFile = WindowsPEFile(inputFile, verbose: cmdVerbose);

  if (cmdWindowConsole || cmdWindowGUI) {
    print('»  Output File: ${outputFile.path}');

    if (cmdWindowGUI) {
      print('»  Setting executable Windows Subsystem to `GUI`...');
      windowsPEFile.setWindowsSubsystem(gui: true);
    } else {
      print('»  Setting executable Windows Subsystem to `console`...');
      windowsPEFile.setWindowsSubsystem(gui: false);
    }

    windowsPEFile.save(outputFile);
    _showCurrentWindowsSubsystem(outputFile, cmdVerbose);
  } else {
    print('»  Showing Windows PE information:');
    _showCurrentWindowsSubsystem(inputFile, cmdVerbose);
  }
}

void _showCurrentWindowsSubsystem(File file, bool cmdVerbose) {
  var windowsPEFile = WindowsPEFile(file, verbose: cmdVerbose);

  var windowsSubsystem = windowsPEFile.readWindowsSubsystem();

  var windowsSubsystemName =
      WindowsPEFile.windowsSubsystemName(windowsSubsystem);

  print(
      '»  Current Windows Subsystem: $windowsSubsystem ($windowsSubsystemName) @ ${file.path}');
}

File? _resolveDefaultOutputFile(List<String> args, File file) {
  if (args.length > 1) {
    var outputPath = args[1];
    var outputFile = File(outputPath);
    return outputFile;
  }

  var fileName = pack_path.withoutExtension(file.path);
  var fileExt = pack_path.extension(file.path);

  for (var i = 1; i <= 1000; ++i) {
    var fPath = '$fileName-copy$i$fileExt';

    var f = File(fPath);
    if (!f.existsSync()) return f;
  }

  return null;
}

bool _removeArgsCmd(List<String> args, String cmd) {
  var idx = args.indexOf(cmd);
  if (idx < 0) return false;
  args.removeAt(idx);
  return true;
}
