@TestOn('vm')
import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:mercury_client/mercury_client.dart';
import 'package:release_updater/src/release_updater_server.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  group('processServerRequest', () {
    late Directory releasesDir;
    late File releasesFile;
    late HttpServer server;
    late String baseURL;
    late HttpClient client;

    Future<void> startServer({BasicCredential? credential}) async {
      var handler = const shelf.Pipeline()
          .addMiddleware(
            (handler) => processServerRequest(
              handler,
              releasesDir,
              credential,
              releasesFile,
            ),
          )
          .addHandler((request) => shelf.Response.notFound('Not Found'));

      server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

      baseURL = 'http://${server.address.host}:${server.port}/';
      client = HttpClient(baseURL);
    }

    setUp(() {
      releasesDir = Directory.systemTemp.createTempSync('release-server--');

      releasesFile = File('${releasesDir.path}/releases.txt');
      releasesFile.writeAsStringSync('foo/1.0.0\nfoo/1.0.1\n');

      File('${releasesDir.path}/foo-1.0.0.zip').writeAsStringSync('ZIP-0');
      File('${releasesDir.path}/foo-1.0.1.zip').writeAsStringSync('ZIP-1');
      File('${releasesDir.path}/other.txt').writeAsStringSync('other');
    });

    tearDown(() async {
      await server.close(force: true);
      releasesDir.deleteSync(recursive: true);
    });

    test('RELEASES', () async {
      await startServer();

      var response = await client.get('RELEASES');

      expect(response.isOK, isTrue);
      expect(response.bodyAsString, equals('foo/1.0.0\nfoo/1.0.1\n'));
    });

    test('RELEASES-FILES', () async {
      await startServer();

      var response = await client.get('RELEASES-FILES');

      expect(response.isOK, isTrue);
      expect(response.bodyAsString, equals('foo-1.0.0.zip\nfoo-1.0.1.zip\n'));
    });

    test('RELEASES-URLS', () async {
      await startServer();

      for (var path in ['RELEASES-URL', 'RELEASES-URLS']) {
        var response = await client.get(path);

        expect(response.isOK, isTrue);
        expect(
          response.bodyAsString,
          equals(
            '${baseURL}foo-1.0.0.zip\n'
            '${baseURL}foo-1.0.1.zip\n',
          ),
        );
      }
    });

    test('unknown path is delegated to the next handler', () async {
      await startServer();

      var response = await client.get('unknown');

      expect(response.isOK, isFalse);
      expect(response.status, equals(404));
    });

    test('upload (disabled)', () async {
      await startServer();

      var response = await client.post(
        '',
        parameters: {'file': 'foo-1.0.2.zip'},
        body: 'ZIP-2',
      );

      // Without a credential the upload is not processed and
      // the request is delegated:
      expect(response.status, equals(404));
      expect(File('${releasesDir.path}/foo-1.0.2.zip').existsSync(), isFalse);
    });

    test('upload', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post(
        '',
        parameters: {'file': 'foo-1.0.2.zip', 'release': 'foo/1.0.2'},
        authorization: BasicCredential('joe', '123456'),
        body: 'ZIP-2',
        contentType: 'application/zip',
      );

      expect(response.isOK, isTrue);

      expect(
        dart_convert.json.decode(response.bodyAsString!),
        equals({'file': 'foo-1.0.2.zip', 'bytes': 5}),
      );

      var uploadedFile = File('${releasesDir.path}/foo-1.0.2.zip');
      expect(uploadedFile.existsSync(), isTrue);
      expect(uploadedFile.readAsStringSync(), equals('ZIP-2'));

      // The release was appended to the releases file:
      expect(
        readReleasesFileLines(releasesFile),
        equals(['foo/1.0.0', 'foo/1.0.1', 'foo/1.0.2']),
      );
    });

    test('upload (invalid credential)', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post(
        '',
        parameters: {'file': 'foo-1.0.2.zip'},
        authorization: BasicCredential('joe', 'wrong-pass'),
        body: 'ZIP-2',
      );

      expect(response.status, equals(403));
      expect(File('${releasesDir.path}/foo-1.0.2.zip').existsSync(), isFalse);
    });

    test('upload (credential as query parameters)', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post(
        '',
        parameters: {
          'file': 'foo-1.0.2.zip',
          'username': 'joe',
          'password': '123456',
        },
        body: 'ZIP-2',
      );

      expect(response.isOK, isTrue);
      expect(File('${releasesDir.path}/foo-1.0.2.zip').existsSync(), isTrue);
    });

    test('upload (without a `file` parameter)', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post('', body: 'ZIP-2');

      // Not an upload request: delegated to the next handler.
      expect(response.status, equals(404));
    });

    test('upload (empty body)', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post(
        '',
        parameters: {'file': 'foo-1.0.2.zip'},
        authorization: BasicCredential('joe', '123456'),
        body: '',
      );

      expect(response.status, equals(500));
      expect(File('${releasesDir.path}/foo-1.0.2.zip').existsSync(), isFalse);
    });

    test('upload (invalid file name)', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      for (var file in ['.hidden.zip', '...', 'dir/']) {
        var response = await client.post(
          '',
          parameters: {'file': file},
          authorization: BasicCredential('joe', '123456'),
          body: 'ZIP-2',
        );

        expect(response.status, equals(500), reason: 'file: $file');
      }
    });

    test('upload (a directory path is reduced to the file name)', () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post(
        '',
        parameters: {'file': '../../foo-1.0.2.zip'},
        authorization: BasicCredential('joe', '123456'),
        body: 'ZIP-2',
      );

      expect(response.isOK, isTrue);

      // Saved inside the releases directory:
      expect(File('${releasesDir.path}/foo-1.0.2.zip').existsSync(), isTrue);
      expect(
        File('${releasesDir.parent.path}/foo-1.0.2.zip').existsSync(),
        isFalse,
      );
    });

    test("upload (can't overwrite)", () async {
      await startServer(credential: BasicCredential('joe', '123456'));

      var response = await client.post(
        '',
        parameters: {'file': 'foo-1.0.0.zip'},
        authorization: BasicCredential('joe', '123456'),
        body: 'OTHER',
      );

      expect(response.status, equals(500));

      // The previous file is preserved:
      expect(
        File('${releasesDir.path}/foo-1.0.0.zip').readAsStringSync(),
        equals('ZIP-0'),
      );
    });

    test('blocks an address with too many requests', () async {
      await startServer();

      // The block limit is 50 requests in a 2 minutes window:
      for (var i = 0; i < 51; ++i) {
        await client.get('RELEASES');
      }

      var response = await client.get('RELEASES');

      expect(response.status, equals(403));
      expect(response.bodyAsString, equals('Blocked'));
    });
  });

  group('RequestInfo', () {
    test('isExpired', () {
      var requestInfo = RequestInfo(InternetAddress('192.160.0.20'));

      var now = DateTime(2022, 1, 1);

      expect(requestInfo.isExpired(now: now), isTrue);

      requestInfo.markRequest(now: now);
      expect(requestInfo.isExpired(now: now), isFalse);

      // The requests window is 2 minutes:
      expect(requestInfo.isExpired(now: now.add(Duration(minutes: 3))), isTrue);

      requestInfo.markError(now: now);
      expect(
        requestInfo.isExpired(now: now.add(Duration(minutes: 3))),
        isFalse,
      );

      // The errors window is 30 minutes:
      expect(
        requestInfo.isExpired(now: now.add(Duration(minutes: 31))),
        isTrue,
      );
    });

    test('toString', () {
      var requestInfo = RequestInfo(InternetAddress('192.160.0.21'));
      requestInfo.markRequest();
      requestInfo.markError();

      expect(
        requestInfo.toString(),
        equals(
          'RequestInfo{address: '
          "InternetAddress('192.160.0.21', IPv4), requests: 1, errors: 1}",
        ),
      );
    });
  });

  group('purgeRequestsInfos', () {
    test('removes the expired tracked addresses', () {
      var address1 = InternetAddress('192.160.0.31');
      var address2 = InternetAddress('192.160.0.32');

      var lengthBefore = requestsInfosLength;

      var requestInfo1 = resolveAddressRequestInfo(address1);
      var requestInfo2 = resolveAddressRequestInfo(address2);

      // The same instance is returned for the same address:
      expect(
        identical(resolveAddressRequestInfo(address1), requestInfo1),
        isTrue,
      );

      expect(requestsInfosLength, equals(lengthBefore + 2));

      var now = DateTime(2022, 1, 1);

      requestInfo1.markRequest(now: now);
      requestInfo2.markRequest(now: now);

      // Nothing expired yet:
      expect(purgeRequestsInfos(now: now), equals(0));
      expect(requestsInfosLength, equals(lengthBefore + 2));

      // Expired, but `requestInfo2` is kept:
      var purged = purgeRequestsInfos(
        now: now.add(Duration(minutes: 31)),
        keep: requestInfo2,
      );

      expect(purged, greaterThanOrEqualTo(1));
      expect(
        identical(resolveAddressRequestInfo(address2), requestInfo2),
        isTrue,
      );
      expect(
        identical(resolveAddressRequestInfo(address1), requestInfo1),
        isFalse,
      );
    });
  });

  group('Releases file', () {
    late Directory tmpDir;
    late File releasesFile;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-server-file--');
      releasesFile = File('${tmpDir.path}/releases.txt');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('readReleasesFileLines', () {
      expect(readReleasesFileLines(releasesFile), isEmpty);

      releasesFile.writeAsStringSync('foo/1.0.0\r\n\n  foo/1.0.1  \n');

      expect(
        readReleasesFileLines(releasesFile),
        equals(['foo/1.0.0', 'foo/1.0.1']),
      );
    });

    test('appendToReleasesFile', () {
      // A missing file is not created:
      expect(appendToReleasesFile(releasesFile, 'foo/1.0.0'), isFalse);

      releasesFile.writeAsStringSync('foo/1.0.1\n');

      expect(appendToReleasesFile(releasesFile, 'foo/1.0.0'), isTrue);
      expect(releasesFile.readAsStringSync(), equals('foo/1.0.0\nfoo/1.0.1\n'));

      // Already present:
      expect(appendToReleasesFile(releasesFile, 'foo/1.0.0'), isFalse);

      // Empty release:
      expect(appendToReleasesFile(releasesFile, '  '), isFalse);
    });

    test('showReleasesFile', () {
      // Does not throw for a missing file:
      showReleasesFile(releasesFile);

      releasesFile.writeAsStringSync('foo/1.0.0\n');
      showReleasesFile(releasesFile);
    });
  });
}
