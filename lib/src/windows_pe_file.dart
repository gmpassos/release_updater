import 'dart:io';
import 'dart:typed_data';

import 'package:data_serializer/data_serializer_io.dart';

/// Window PE file handler.
/// - PE Format:
///   https://learn.microsoft.com/en-gb/windows/win32/debug/pe-format?redirectedfrom=MSDN#characteristics
class WindowPEFile {
  final File file;
  late final BytesBuffer fileBuffer;
  final bool verbose;

  WindowPEFile(this.file, {this.verbose = false}) {
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

  int seekToWindowsSubsystem() {
    fileBuffer.seek(0x3c);

    var peHeaderOffset = fileBuffer.readUint16(Endian.little);
    _logEntry('peHeaderOffset', peHeaderOffset);

    fileBuffer.seek(peHeaderOffset);

    var peSignature = fileBuffer.readUint32();
    _logEntry('peSignature', peSignature);

    if (peSignature != 0x50450000) {
      throw StateError(
          "Invalid PE header signature: $peSignature != 0x50450000");
    }

    var machineType = fileBuffer.readUint16(Endian.little);
    _logEntry('machineType', machineType);

    fileBuffer.seek(fileBuffer.position + 2 + 4 + 4 + 4);

    var sizeOfOptionalHeader = fileBuffer.readUint16(Endian.little);
    _logEntry('sizeOfOptionalHeader', sizeOfOptionalHeader);

    var characteristics = fileBuffer.readUint16(Endian.little);
    _logEntry('characteristics', characteristics, flag: true);

    var isExecutable = (characteristics & 2) == 0;
    if (isExecutable) {
      throw StateError("Not an executable binary: ${file.path}");
    }

    var optionalHeaderOffset = fileBuffer.position;

    var magic = fileBuffer.readUint16(Endian.little);
    _logEntry('magic', magic);

    if (magic != 0x010B && magic != 0x020B) {
      throw StateError(
          "Not a normal executable or a PE32+ executable: ${file.path}");
    }

    fileBuffer.seek(optionalHeaderOffset + 68);

    var pos = fileBuffer.position;

    if (pos != (peHeaderOffset + 0x5C)) {
      throw StateError(
          "Invalid Windows Subsystem offset: ${fileBuffer.position} != ${peHeaderOffset + 0x5C}");
    }

    return pos;
  }

  int readWindowsSubsystem() {
    seekToWindowsSubsystem();

    var subsystem = fileBuffer.readUint16(Endian.little);
    _logEntry('Windows Subsystem', subsystem);

    return subsystem;
  }

  void writeWindowsSubsystem(int subsystem) {
    seekToWindowsSubsystem();
    fileBuffer.writeUint16(subsystem, Endian.little);
    fileBuffer.flush();
  }

  void setWindowsSubsystem({required bool gui}) {
    var currentSubsystem = readWindowsSubsystem();
    if (currentSubsystem != 2 && currentSubsystem != 3) {
      throw StateError(
          "Current subsistem not compatible with `console/GUI` switch: $currentSubsystem");
    }

    var subsystem = gui ? 2 : 3;
    writeWindowsSubsystem(subsystem);
  }

  void flush() {
    fileBuffer.flush();
  }

  void close() {
    fileBuffer.close();
  }
}
