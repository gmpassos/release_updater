import 'dart:async';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';

/// The [Release] provider.
abstract class ReleaseProvider implements Copiable<ReleaseProvider> {
  /// Lists all releases.
  FutureOr<List<Release>> listReleases();

  /// Returns the last [Version] available for [name] and optional [platform].
  FutureOr<Release?> lastRelease(String name, {String? platform}) async {
    var list = await listReleases();

    var listName = list.where((e) => e.name == name).toList();

    var listTargetPlatform = platform == null
        ? <Release>[]
        : listName.where((e) => e.platform == platform).toList();

    if (listTargetPlatform.isNotEmpty) {
      listTargetPlatform.sort();
      return listTargetPlatform.last;
    }

    var listNoPlatform = listName.where((e) => e.platform == null).toList();

    if (listNoPlatform.isNotEmpty) {
      listNoPlatform.sort();
      return listNoPlatform.last;
    }

    if (platform == null) {
      listName.sort();
      return listName.isNotEmpty ? listName.last : null;
    }

    return null;
  }

  /// Gets a [ReleaseBundle] for the [targetVersion].
  FutureOr<ReleaseBundle?> getReleaseBundle(String name, Version targetVersion,
      [String? platform]);
}
