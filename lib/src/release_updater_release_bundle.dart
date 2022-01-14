import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'release_updater_base.dart';

abstract class ReleaseBundle {
  final Release release;

  ReleaseBundle(this.release);

  FutureOr<Set<ReleaseFile>> get files;
}

class ReleaseBundleZip extends ReleaseBundle {
  final Uint8List _zipBytes;

  ReleaseBundleZip(Release release, this._zipBytes) : super(release);

  @override
  FutureOr<Set<ReleaseFile>> get files {
    final archive = ZipDecoder().decodeBytes(_zipBytes);

    var files = archive
        .where((f) => f.isFile)
        .map((f) => ReleaseFile(f.name, f.content,
            time: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000)))
        .toSet();

    return files;
  }
}
