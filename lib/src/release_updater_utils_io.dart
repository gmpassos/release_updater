import 'dart:io';

extension FileExtension on File {
  bool get hasExecutablePermission => statSync().modeString().contains('x');
}
