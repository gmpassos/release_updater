import 'dart:async';

import 'release_updater_base.dart';
import 'release_updater_release_bundle.dart';

/// The [Release] provider.
abstract class ReleaseProvider {
  /// Lists all release versions.
  FutureOr<List<Release>> listReleases();

  /// Returns the last [Version] available for [name] and optional [platform].
  FutureOr<Release?> lastRelease(String name, {String? platform}) async {
    var list = await listReleases();

    var listWhere = list.where((e) => e.name == name);

    if (platform != null) {
      listWhere = listWhere.where((e) => e.platform == platform);
    }

    var listFiltered = listWhere.toList();
    listFiltered.sort();

    return listFiltered.isNotEmpty ? listFiltered.last : null;
  }

  /// Gets a [ReleaseBundle] for the [targetVersion].
  FutureOr<ReleaseBundle?> getReleaseBundle(String name, Version targetVersion,
      [String? platform]);
}
