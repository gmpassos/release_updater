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
  final String? rootPath;

  ReleaseBundleZip(Release release, this._zipBytes, {this.rootPath})
      : super(release);

  @override
  FutureOr<Set<ReleaseFile>> get files {
    final archive = ZipDecoder().decodeBytes(_zipBytes);

    var files = archive.where((f) => f.isFile).map(_toReleaseFile).toSet();

    return files;
  }

  ReleaseFile _toReleaseFile(ArchiveFile f) {
    var name = f.name;

    var rootPath = this.rootPath;

    if (rootPath != null && name.startsWith(rootPath)) {
      name = name.substring(rootPath.length);
    }

    var releaseFile = ReleaseFile(name, f.content,
        time: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000));

    return releaseFile;
  }
}
