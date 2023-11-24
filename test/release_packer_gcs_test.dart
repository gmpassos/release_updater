@TestOn('vm')
import 'package:path/path.dart' as pack_path;
import 'package:release_updater/release_packer_gcs.dart';
//import 'package:pub_semver/pub_semver.dart' ;
import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

void main() {
  group('ReleasePacker (GCS)', () {
    test('ReleasePackerCommandGCS', () async {
      {
        var cmd = ReleasePackerCommandGCS.fromJson({
          "project": "project1",
          "bucket": "files-bucket",
          "credential": 'metadata.server',
          "parameters": {"file": 'release-x.zip'}
        });

        expect(cmd.project, equals('project1'));
        expect(cmd.bucket, equals('files-bucket'));
        expect(cmd.credential, isNotNull);
        expect(cmd.parameters, equals({"file": 'release-x.zip'}));
      }
    });

    test(
        'ReleasePackerCommandUploadReleaseBundle (credential: service_account)',
        () async {
      var cmd = ReleasePackerCommand.from({
        "upload_release": {
          "gcs": {
            "project": "project-x",
            "bucket": "project-releases",
            "credential": {
              "type": "service_account",
              "project_id": "project-x",
              "private_key_id": "%GCS_PRIVATE_KEY_ID%",
              "private_key": "%GCS_PRIVATE_KEY%",
              "client_email": "%GCS_CLIENT_EMAIL%",
              "client_id": "%GCS_CLIENT_ID%",
              "auth_uri": "https://accounts.google.com/o/oauth2/auth",
              "token_uri": "https://oauth2.googleapis.com/token",
              "auth_provider_x509_cert_url":
                  "https://www.googleapis.com/oauth2/v1/certs",
              "client_x509_cert_url": "%GCS_CERT_URL%"
            },
            "parameters": {
              "directory": "foo-app/releases",
              "contentType": "application/bundle",
            }
          }
        }
      });

      expect(cmd, isA<ReleasePackerCommandUploadReleaseBundle>());

      var cmdBundle = cmd as ReleasePackerCommandUploadReleaseBundle;

      expect(cmdBundle.uploadCommand, isA<ReleasePackerCommandGCS>());

      var cmdGCS = cmdBundle.uploadCommand as ReleasePackerCommandGCS;

      expect(cmdGCS.project, equals('project-x'));
      expect(cmdGCS.bucket, equals('project-releases'));
      expect(cmdGCS.credential, isA<Map>());

      {
        var version = SemanticVersioning.parse('1.0.0');
        var release = Release("foo-app", version);

        var releaseBundle = ReleaseBundleZip(release, files: [
          ReleaseFile("foo.sh", "Some script"),
        ]);

        var bundleBytes = await releaseBundle.toBytes();

        expect(
            await cmdGCS.resolveUploadParameters(releaseBundle: releaseBundle),
            equals((
              bodyBytes: bundleBytes,
              contentType: 'application/bundle',
              filePath:
                  pack_path.normalize('foo-app/releases/foo-app-1.0.0.zip'),
              release: 'foo-app/1.0.0',
            )));
      }
    });

    test(
        'ReleasePackerCommandUploadReleaseBundle (credential: metadata.server)',
        () async {
      var cmd = ReleasePackerCommand.from({
        "upload_release": {
          "gcs": {
            "project": "project-x",
            "bucket": "project-releases",
            "credential": "metadata.server",
          }
        }
      });

      expect(cmd, isA<ReleasePackerCommandUploadReleaseBundle>());

      var cmdBundle = cmd as ReleasePackerCommandUploadReleaseBundle;

      expect(cmdBundle.uploadCommand, isA<ReleasePackerCommandGCS>());

      var cmdGCS = cmdBundle.uploadCommand as ReleasePackerCommandGCS;

      expect(cmdGCS.project, equals('project-x'));
      expect(cmdGCS.bucket, equals('project-releases'));
      expect(cmdGCS.credential, isA<String>());

      {
        var version = SemanticVersioning.parse('1.0.1');
        var release = Release("foo-app", version);

        var releaseBundle = ReleaseBundleZip(release, files: [
          ReleaseFile("foo.sh", "Some script"),
        ]);

        var bundleBytes = await releaseBundle.toBytes();

        expect(
            await cmdGCS.resolveUploadParameters(releaseBundle: releaseBundle),
            equals((
              bodyBytes: bundleBytes,
              contentType: 'application/zip',
              filePath: 'foo-app-1.0.1.zip',
              release: 'foo-app/1.0.1',
            )));
      }
    });
  });
}
