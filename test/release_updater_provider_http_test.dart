@TestOn('vm')
import 'dart:io';
import 'dart:typed_data';

import 'package:mercury_client/mercury_client.dart' as mercury;
import 'package:release_updater/release_updater_io.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseProviderHttp', () {
    late HttpServer server;
    late String baseURL;
    late Map<String, List<int>> serverFiles;
    late List<String> requestedPaths;

    setUp(() async {
      serverFiles = <String, List<int>>{};
      requestedPaths = <String>[];

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseURL = 'http://${server.address.host}:${server.port}/';

      server.listen((request) async {
        var path = request.uri.path;
        if (path.startsWith('/')) path = path.substring(1);

        requestedPaths.add(path);

        var data = serverFiles[path];

        if (data == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = path.endsWith('.zip')
              ? ContentType('application', 'zip')
              : ContentType.text;
          request.response.add(data);
        }

        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<Uint8List> bundleBytes(String version, {String? platform}) async {
      var bundle = ReleaseBundleZip(
        Release('foo', SemanticVersioning.parse(version), platform: platform),
        files: [
          ReleaseFile('README.md', '#Foo/$version\n'),
          ReleaseFile('run.sh', '#!/bin/sh\n', executable: true),
        ],
      );
      return await bundle.toBytes();
    }

    test('listReleases', () async {
      serverFiles['releases.txt'] =
          'foo/1.0.0/linux-x64\n'
                  '\n'
                  'foo/1.0.2/linux-x64\r\n'
                  ' foo/1.0.1/linux-x64 \n'
              .codeUnits;

      var provider = ReleaseProviderHttp.baseURL(baseURL);

      var releases = await provider.listReleases();

      expect(
        releases.map((e) => e.toString()),
        equals([
          'foo/1.0.0/linux-x64',
          'foo/1.0.2/linux-x64',
          'foo/1.0.1/linux-x64',
        ]),
      );

      expect(
        (await provider.lastRelease('foo', platform: 'linux-x64')).toString(),
        equals('foo/1.0.2/linux-x64'),
      );
    });

    test('listReleases (missing releases file)', () async {
      var provider = ReleaseProviderHttp.baseURL(baseURL);
      expect(await provider.listReleases(), isEmpty);
    });

    test('listReleases (custom releases file)', () async {
      serverFiles['my-releases.txt'] = 'foo/1.0.0\n'.codeUnits;

      var provider = ReleaseProviderHttp.baseURL(
        baseURL,
        releasesFile: 'my-releases.txt',
      );

      expect(
        (await provider.listReleases()).map((e) => e.toString()),
        equals(['foo/1.0.0']),
      );
    });

    test('getReleaseBundle', () async {
      serverFiles['foo-1.0.2-linux-x64.zip'] = await bundleBytes(
        '1.0.2',
        platform: 'linux-x64',
      );

      var provider = ReleaseProviderHttp.baseURL(baseURL);

      var bundle = await provider.getReleaseBundle(
        'foo',
        SemanticVersioning.parse('1.0.2'),
        'linux-x64',
      );

      expect(bundle, isNotNull);
      expect(bundle!.release.toString(), equals('foo/1.0.2/linux-x64'));

      var files = (await bundle.files).toList()..sort();
      expect(files.map((e) => e.filePath), equals(['README.md', 'run.sh']));
      expect(await files[0].dataAsString, equals('#Foo/1.0.2\n'));
      expect(files[1].executable, isTrue);
    });

    test('getReleaseBundle (no platform)', () async {
      serverFiles['foo-1.0.2.zip'] = await bundleBytes('1.0.2');

      var provider = ReleaseProviderHttp.baseURL(baseURL);

      var bundle = await provider.getReleaseBundle(
        'foo',
        SemanticVersioning.parse('1.0.2'),
      );

      expect(bundle!.release.toString(), equals('foo/1.0.2'));
      expect((await bundle.files), hasLength(2));
    });

    test('getReleaseBundle (not found)', () async {
      var provider = ReleaseProviderHttp.baseURL(baseURL);

      expect(
        await provider.getReleaseBundle(
          'foo',
          SemanticVersioning.parse('1.0.2'),
        ),
        isNull,
      );
    });

    test('withClient', () async {
      serverFiles['releases.txt'] = 'foo/1.0.0\n'.codeUnits;

      var client = mercury.HttpClient(baseURL);
      var provider = ReleaseProviderHttp.withClient(client);

      expect(provider.baseURL, equals(client.baseURL));
      expect(
        (await provider.listReleases()).map((e) => e.toString()),
        equals(['foo/1.0.0']),
      );
    });

    test('copy', () {
      var provider = ReleaseProviderHttp.baseURL(
        baseURL,
        releasesFile: 'my-releases.txt',
        releasesBundleFileFormat: '%NAME%/%VER%/bundle.zip',
      );

      var copy = provider.copy();

      expect(copy.baseURL, equals(provider.baseURL));
      expect(copy.releasesFile, equals('my-releases.txt'));
      expect(copy.releasesBundleFileFormat, equals('%NAME%/%VER%/bundle.zip'));
    });

    test('custom `releasesBundleFileFormat`', () async {
      serverFiles['foo/1.0.2/bundle.zip'] = await bundleBytes('1.0.2');

      var provider = ReleaseProviderHttp.baseURL(
        baseURL,
        releasesBundleFileFormat: '%NAME%/%VER%/bundle.zip',
      );

      var bundle = await provider.getReleaseBundle(
        'foo',
        SemanticVersioning.parse('1.0.2'),
      );

      expect(bundle, isNotNull);
      expect((await bundle!.files), hasLength(2));
    });

    test('toString', () {
      var provider = ReleaseProviderHttp.baseURL(baseURL);
      expect(provider.toString(), contains('releasesFile: releases.txt'));
    });

    test('onSpawned', () {
      expect(ReleaseProviderHttp.baseURL(baseURL).onSpawned(), isTrue);
    });

    test('update a local storage from the HTTP provider', () async {
      serverFiles['releases.txt'] = 'foo/1.0.0\nfoo/1.0.2\n'.codeUnits;
      serverFiles['foo-1.0.2.zip'] = await bundleBytes('1.0.2');

      var tmp = Directory.systemTemp.createTempSync('release-updater-http--');

      try {
        var storage = ReleaseStorageDirectory('foo', tmp);
        var provider = ReleaseProviderHttp.baseURL(baseURL);

        var updater = ReleaseUpdater(storage, provider);

        var result = await updater.update();

        expect(result, isNotNull);
        expect(result!.release.toString(), equals('foo/1.0.2'));
        expect(result.savedFilesLength, equals(2));

        var readme = File(
          await updater.currentReleaseFilePath('README.md') ?? '',
        );

        expect(readme.existsSync(), isTrue);
        expect(readme.readAsStringSync(), equals('#Foo/1.0.2\n'));

        // Already at the last release:
        expect(await updater.checkForUpdate(), isNull);
        expect(await updater.update(), isNull);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('retries a failed request', () async {
      await server.close(force: true);

      var provider = ReleaseProviderHttp.baseURL(baseURL);

      // The server is down: all the retries fail and an empty list
      // is returned (without throwing).
      expect(await provider.listReleases(), isEmpty);
    });
  });
}
