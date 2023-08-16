import 'dart:io';
import 'dart:typed_data';

import 'package:data_serializer/data_serializer_io.dart';

/// Window PE file handler.
/// - PE Format:
///   https://learn.microsoft.com/en-gb/windows/win32/debug/pe-format?redirectedfrom=MSDN#characteristics
class WindowsPEFile {
  /// The file to read or modify.
  final File file;

  /// The [file] buffer.
  late final BytesBuffer fileBuffer;

  /// If `true` will [print] to the console each operation.
  final bool verbose;

  WindowsPEFile(this.file, {this.verbose = false}) {
    var bytesIO = BytesFileIO.fromFile(file);
    fileBuffer = BytesBuffer.fromIO(bytesIO);

    _log('Opened: ${file.path}');
  }

  void _log(Object? o) {
    if (o == null) return;
    if (!verbose) return;
    print('[Windows PE]\t$o');
  }

  void _logEntry(String key, Object? o, {bool flag = false}) {
    var desc = '';

    if (o is int) {
      desc = ' (0x${o.toHex32()})';
      if (flag) {
        desc += ' [${o.bits16}]';
      }
    }

    _log('$key: $o$desc');
  }

  /// Seeks to the Windows Subsystem position.
  int seekToWindowsSubsystem() {
    var info = _seekToWindowsSubsystemImpl();
    var windowsSubsystemOffset = info['windowsSubsystemOffset']!;
    return windowsSubsystemOffset;
  }

  Map<String, int> _seekToWindowsSubsystemImpl() {
    fileBuffer.seek(0x3c);

    var info = <String, int>{};

    var peHeaderOffset = fileBuffer.readUint16(Endian.little);
    info['peHeaderOffset'] = peHeaderOffset;
    _logEntry('peHeaderOffset', peHeaderOffset);

    fileBuffer.seek(peHeaderOffset);

    var peSignature = fileBuffer.readUint32();
    info['peSignature'] = peSignature;
    _logEntry('peSignature', peSignature);

    if (peSignature != 0x50450000) {
      throw StateError(
          "Invalid PE header signature: $peSignature != 0x50450000");
    }

    var machineType = fileBuffer.readUint16(Endian.little);
    info['machineType'] = machineType;
    _logEntry('machineType', machineType);

    fileBuffer.seek(fileBuffer.position + 2 + 4 + 4 + 4);

    var sizeOfOptionalHeader = fileBuffer.readUint16(Endian.little);
    info['sizeOfOptionalHeader'] = sizeOfOptionalHeader;
    _logEntry('sizeOfOptionalHeader', sizeOfOptionalHeader);

    var characteristics = fileBuffer.readUint16(Endian.little);
    info['characteristics'] = characteristics;
    _logEntry('characteristics', characteristics, flag: true);

    var isExecutable = (characteristics & 2) == 0;
    if (isExecutable) {
      throw StateError("Not an executable binary: ${file.path}");
    }

    var optionalHeaderOffset = fileBuffer.position;
    info['optionalHeaderOffset'] = optionalHeaderOffset;

    var optionalHeaderMagic = fileBuffer.readUint16(Endian.little);
    info['optionalHeaderMagic'] = optionalHeaderMagic;
    _logEntry('optionalHeaderMagic', optionalHeaderMagic);

    if (optionalHeaderMagic != 0x010B && optionalHeaderMagic != 0x020B) {
      throw StateError(
          "Not a normal executable or a PE32+ executable: ${file.path}");
    }

    fileBuffer.seek(optionalHeaderOffset + 68);

    var windowsSubsystemOffset = fileBuffer.position;

    if (windowsSubsystemOffset != (peHeaderOffset + 0x5C)) {
      throw StateError(
          "Invalid Windows Subsystem offset: ${fileBuffer.position} != ${peHeaderOffset + 0x5C}");
    }

    info['windowsSubsystemOffset'] = windowsSubsystemOffset;

    return info;
  }

  /// Reads the basic PE information.
  Map<String, int> readInformation() {
    var info = _seekToWindowsSubsystemImpl();

    var windowsSubsystem = fileBuffer.readUint16(Endian.little);
    _logEntry('Windows Subsystem', windowsSubsystem);

    info['windowsSubsystem'] = windowsSubsystem;

    return info;
  }

  /// Returns the `machineType` of the executable.
  int get machineType => readInformation()['machineType']!;

  /// Returns `true` if [machineType] is `x64`.
  bool get isMachineTypeX64 => machineType == 0x8664;

  /// Returns `true` if [machineType] is `i386`.
  bool get isMachineTypeI386 => machineType == 0x14c;

  /// Returns `true` if [machineType] is `Intel Itanium`.
  bool get isMachineTypeItanium => machineType == 0x200;

  /// Returns `true` if [machineType] is `ARM little endian`.
  bool get isMachineTypeARM => machineType == 0x1c0;

  /// Returns `true` if [machineType] is `ARM64 little endian`.
  bool get isMachineTypeARM64 => machineType == 0xaa64;

  /// Returns `true` if [file] is a valid Windows executable in `GUI` or `Console` Subsystem.
  bool get isValidExecutable {
    try {
      var info = _seekToWindowsSubsystemImpl();
      var pos = info['windowsSubsystemOffset'];
      return pos != null && pos > 128;
    } catch (_) {
      return false;
    }
  }

  /// Returns the [windowsSubsystem] value name.
  static String windowsSubsystemName(int windowsSubsystem) =>
      switch (windowsSubsystem) {
        0 => 'unknown',
        2 => 'GUI',
        3 => 'console',
        _ => '?',
      };

  /// Reads the current Windows Subsystem value.
  int readWindowsSubsystem() {
    _seekToWindowsSubsystemImpl();

    var subsystem = fileBuffer.readUint16(Endian.little);
    _logEntry('Windows Subsystem', subsystem);

    return subsystem;
  }

  /// Writes the Windows Subsystem.
  void writeWindowsSubsystem(int subsystem) {
    _seekToWindowsSubsystemImpl();
    fileBuffer.writeUint16(subsystem, Endian.little);
    fileBuffer.flush();
  }

  /// Sets/writes the Windows Subsystem to `GUI` or `Console`.
  void setWindowsSubsystem({required bool gui}) {
    var currentSubsystem = readWindowsSubsystem();
    if (currentSubsystem != 2 && currentSubsystem != 3) {
      throw StateError(
          "Current subsistem not compatible with `console/GUI` switch: $currentSubsystem");
    }

    var subsystem = gui ? 2 : 3;
    writeWindowsSubsystem(subsystem);
  }

  /// Flushes the [fileBuffer].
  void flush() {
    fileBuffer.flush();
  }

  /// Closes the [fileBuffer].
  void close() {
    fileBuffer.close();
  }
}
