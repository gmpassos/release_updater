import 'dart:async';
import 'dart:typed_data';

import 'package:mercury_client/mercury_client.dart';

import 'release_updater_base.dart';
import 'release_updater_bundle.dart';
import 'release_updater_provider.dart';

class ReleaseProviderHttp extends ReleaseProvider {
  final String baseURL;
  HttpClient? _httpClient;

  final String releasesFile;
  static const String defaultReleasesFile = 'releases.txt';

  final String releasesBundleFileFormat;
  static const String defaultReleasesBundleFileFormat =
      ReleaseBundle.defaultReleasesBundleFileFormat;

  ReleaseProviderHttp.withClient(this._httpClient,
      {this.releasesFile = defaultReleasesFile,
      this.releasesBundleFileFormat = defaultReleasesBundleFileFormat})
      : baseURL = _httpClient!.baseURL;

  ReleaseProviderHttp.baseURL(this.baseURL,
      {this.releasesFile = defaultReleasesFile,
      this.releasesBundleFileFormat = defaultReleasesBundleFileFormat})
      : _httpClient = null;

  @override
  ReleaseProviderHttp copy() => ReleaseProviderHttp.baseURL(baseURL);

  HttpClient get httpClient => _httpClient ??= HttpClient(baseURL);

  Future<HttpBody?> _getHttpPath(String path, {int maxRetries = 3}) async {
    for (var i = 0; i < maxRetries; ++i) {
      try {
        var response = await httpClient.get(path);
        return response.isOK ? response.body : null;
      } catch (_) {
        await Future.delayed(Duration(seconds: 1));
      }
    }

    return null;
  }

  @override
  Future<List<Release>> listReleases() async {
    var body = await _getHttpPath(releasesFile);
    if (body == null) return <Release>[];

    var listStr = body.asString ?? '';

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
    var file = ReleaseBundle.formatReleaseBundleFile(
        releasesBundleFileFormat, name, targetVersion, platform);

    var body = await _getHttpPath(file);
    if (body == null) return null;

    var byteArray = body.asByteArray!;

    var zipBytes =
        byteArray is Uint8List ? byteArray : Uint8List.fromList(byteArray);

    var rootPath =
        file.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');

    var release = Release(name, targetVersion, platform: platform);
    var releaseBundle =
        ReleaseBundleZip(release, zipBytes: zipBytes, rootPath: rootPath);

    return releaseBundle;
  }

  @override
  String toString() {
    return 'ReleaseProviderHttp{baseURL: ${httpClient.baseURL}, releasesFile: $releasesFile, releasesBundleFileFormat: $releasesBundleFileFormat}';
  }
}
