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
  static const List<String> defaultExecutableExtensions = ['exe', 'sh'];

  final Uint8List _zipBytes;
  final String? rootPath;
  final List<String> executableExtensions;

  ReleaseBundleZip(Release release, this._zipBytes,
      {this.rootPath, this.executableExtensions = defaultExecutableExtensions})
      : super(release);

  bool isExecutableFilePath(String filePath) => executableExtensions
      .where((ext) => filePath.endsWith('.$ext'))
      .isNotEmpty;

  @override
  FutureOr<Set<ReleaseFile>> get files {
    final archive = ZipDecoder().decodeBytes(_zipBytes);

    var files = archive.where((f) => f.isFile).map(_toReleaseFile).toSet();

    return files;
  }

  ReleaseFile _toReleaseFile(ArchiveFile f) {
    var filePath = f.name;

    var rootPath = this.rootPath;

    if (rootPath != null && filePath.startsWith(rootPath)) {
      filePath = filePath.substring(rootPath.length);
    }

    var executable = isExecutableFilePath(filePath);

    var releaseFile = ReleaseFile(filePath, f.content,
        time: DateTime.fromMillisecondsSinceEpoch(f.lastModTime * 1000),
        executable: executable);

    return releaseFile;
  }
}
