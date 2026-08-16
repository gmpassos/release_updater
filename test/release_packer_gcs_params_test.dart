@TestOn('vm')
import 'package:release_updater/release_packer_gcs.dart';
import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePackerCommandGCS', () {
    ReleaseBundleZip bundle({String? platform}) => ReleaseBundleZip(
      Release('foo-app', SemanticVersioning.parse('1.0.0'), platform: platform),
      files: [ReleaseFile('foo.sh', 'Some script')],
    );

    test('empty project or bucket', () {
      expect(
        () => ReleasePackerCommandGCS('', 'bucket', credential: 'metadata'),
        throwsArgumentError,
      );

      expect(
        () => ReleasePackerCommandGCS('project', '', credential: 'metadata'),
        throwsArgumentError,
      );
    });

    test('fromJson (missing entries)', () {
      expect(
        () => ReleasePackerCommandGCS.fromJson({'bucket': 'b'}),
        throwsArgumentError,
      );

      expect(
        () => ReleasePackerCommandGCS.fromJson({'project': 'p'}),
        throwsArgumentError,
      );

      expect(
        () => ReleasePackerCommandGCS.fromJson({'project': 'p', 'bucket': 'b'}),
        throwsArgumentError,
      );
    });

    test('toString', () {
      var cmd = ReleasePackerCommandGCS(
        'project-x',
        'bucket-x',
        credential: 'metadata.server',
      );

      expect(cmd.toString(), contains('project: project-x'));
      expect(cmd.toString(), contains('bucket: bucket-x'));
    });

    test('resolveUploadParameters (no release bundle)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {'file': '%NAME%-%VER%.zip'},
        body: '%RELEASE_BUNDLE%',
      );

      expect(await cmd.resolveUploadParameters(), isNull);
    });

    test('resolveUploadParameters (platform in the file name)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {
          'file': '%NAME%-%VER%%[-]PLATFORM%.zip',
          'release': '%RELEASE%',
          'directory': 'releases/',
        },
        body: '%RELEASE_BUNDLE%',
      );

      var params = await cmd.resolveUploadParameters(
        releaseBundle: bundle(platform: 'linux-x64'),
      );

      expect(params, isNotNull);
      expect(params!.filePath, equals('releases/foo-app-1.0.0-linux-x64.zip'));
      expect(params.release, equals('foo-app/1.0.0/linux-x64'));
      expect(params.contentType, equals('application/zip'));
      expect(params.bodyBytes, isNotEmpty);
    });

    test('resolveUploadParameters (a literal `release` is kept)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {'file': 'app.zip', 'release': 'my-release'},
        body: '%RELEASE_BUNDLE%',
      );

      var params = await cmd.resolveUploadParameters(releaseBundle: bundle());

      expect(params!.release, equals('my-release'));
      expect(params.filePath, equals('app.zip'));
    });

    test('resolveUploadParameters (a literal body)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {'file': 'notes.txt', 'contentType': 'text/plain'},
        body: 'Some notes',
      );

      var params = await cmd.resolveUploadParameters();

      expect(params!.filePath, equals('notes.txt'));
      expect(params.contentType, equals('text/plain'));
      expect(params.bodyBytes, equals('Some notes'.codeUnits));
      expect(params.release, isNull);
    });

    test('resolveUploadParameters (body as bytes)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {'file': 'a.bin'},
        body: <int>[1, 2, 3],
      );

      var params = await cmd.resolveUploadParameters();

      expect(params!.bodyBytes, equals([1, 2, 3]));
      expect(params.contentType, equals('application/octet-stream'));
    });

    test('resolveUploadParameters (missing `file`)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        body: 'data',
      );

      expect(() => cmd.resolveUploadParameters(), throwsArgumentError);
    });

    test('resolveUploadParameters (missing `body`)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {'file': 'a.zip'},
      );

      expect(() => cmd.resolveUploadParameters(), throwsArgumentError);
    });

    test('resolveUploadParameters (invalid body type)', () async {
      var cmd = ReleasePackerCommandGCS(
        'p',
        'b',
        credential: 'metadata',
        parameters: {'file': 'a.zip'},
        body: 123,
      );

      expect(() => cmd.resolveUploadParameters(), throwsArgumentError);
    });

    test('createGCSClient (invalid credential)', () {
      expect(
        () => ReleasePackerCommandGCS.createGCSClient({'type': 'invalid'}),
        throwsA(anything),
      );
    });
  });

  group('ReleasePackerCommandUploadReleaseBundle', () {
    test('byGCS defaults', () {
      var cmd = ReleasePackerCommandUploadReleaseBundle.byGCS(
        'project-x',
        'bucket-x',
        credential: 'metadata.server',
      );

      var cmdGCS = cmd.uploadCommand as ReleasePackerCommandGCS;

      expect(
        cmdGCS.parameters!['file'],
        equals(ReleaseBundle.defaultReleasesBundleFileFormat),
      );
      expect(cmdGCS.parameters!['release'], equals('%RELEASE%'));
      expect(cmdGCS.body, equals('%RELEASE_BUNDLE%'));
    });

    test('byURL defaults', () {
      var cmd = ReleasePackerCommandUploadReleaseBundle.byURL(
        'http://foo/upload',
        file: 'custom.zip',
      );

      var cmdURL = cmd.uploadCommand as ReleasePackerCommandURL;

      expect(cmdURL.url, equals('http://foo/upload'));
      expect(cmdURL.parameters!['file'], equals('custom.zip'));
      expect(cmdURL.parameters!['release'], equals('%RELEASE%'));
    });

    test('fromJson (URL)', () {
      var cmd = ReleasePackerCommandUploadReleaseBundle.fromJson({
        'url': 'http://foo/upload',
        'authorization': 'joe:123456',
        'file': 'app-%VER%.zip',
        'release': '%RELEASE%',
      });

      var cmdURL = cmd.uploadCommand as ReleasePackerCommandURL;

      expect(cmdURL.url, equals('http://foo/upload'));
      expect(cmdURL.parameters!['file'], equals('app-%VER%.zip'));
      expect(cmdURL.authorization, isNotNull);
    });
  });
}
