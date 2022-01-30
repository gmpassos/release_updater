import 'dart:io';

import 'package:crypto/crypto.dart';

extension FileExtension on File {
  bool get hasExecutablePermission => statSync().modeString().contains('x');

  Digest computeSHA256() => sha256.convert(readAsBytesSync());
}
