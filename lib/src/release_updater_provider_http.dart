import 'dart:async';
import 'dart:typed_data';

import 'package:mercury_client/mercury_client.dart';
import 'package:release_updater/src/release_updater_base.dart';

import 'release_updater_provider.dart';
import 'release_updater_release_bundle.dart';

class ReleaseProviderHttp extends ReleaseProvider {
  final HttpClient httpClient;

  final String releasesFile;
  static const String defaultReleasesFile = 'releases.txt';

  final String releasesBundleFileFormat;
  static const String defaultReleasesBundleFileFormat =
      '%NAME%-%VER%%[-]PLATFORM%.zip';

  static String formatBundleFile(
      String fileFormat, String name, Version version,
      [String? platform]) {
    var file = _replaceMark(fileFormat, 'NAME', name);
    file = _replaceMark(file, 'VER', version.toString());
    file = _replaceMark(file, 'PLATFORM', platform);
    return file;
  }

  static String _replaceMark(String s, String mark, String? value) {
    var regExp = RegExp(r'%(?:\[(.*?)\])?(' + mark + r')%');

    return s.replaceAllMapped(regExp, (m) {
      var prev = m.group(1) ?? '';
      return value != null ? '$prev$value' : '';
    });
  }

  ReleaseProviderHttp.withClient(this.httpClient,
      {this.releasesFile = defaultReleasesFile,
      this.releasesBundleFileFormat = defaultReleasesBundleFileFormat});

  ReleaseProviderHttp.baseURL(String baseURL,
      {String releasesFile = defaultReleasesFile,
      String releasesBundleFileFormat = defaultReleasesBundleFileFormat})
      : this.withClient(HttpClient(baseURL),
            releasesFile: releasesFile,
            releasesBundleFileFormat: releasesBundleFileFormat);

  @override
  Future<List<Release>> listReleases() async {
    var response = await httpClient.get(releasesFile);
    if (response.isNotOK) return <Release>[];

    var listStr = response.bodyAsString!;

    var list = listStr
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    var releases = list.map((e) => Release.parse(e)).toList();
    return releases;
  }

  @override
  Future<ReleaseBundle?> getReleaseBundle(String name, Version targetVersion,
      [String? platform]) async {
    var file = formatBundleFile(
        releasesBundleFileFormat, name, targetVersion, platform);
    var response = await httpClient.get(file);

    if (response.isNotOK) return null;

    var body = response.body!;

    var byteArray = body.asByteArray!;

    var zipBytes =
        byteArray is Uint8List ? byteArray : Uint8List.fromList(byteArray);

    var rootPath =
        file.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');

    var releaseBundle = ReleaseBundleZip(Release(name, targetVersion), zipBytes,
        rootPath: rootPath);

    return releaseBundle;
  }
}
