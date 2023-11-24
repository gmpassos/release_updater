@TestOn('vm')
import 'package:release_updater/src/release_packer.dart';
import 'package:release_updater/src/release_packer_gcs.dart';
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

    test('ReleasePackerCommandUploadReleaseBundle', () async {
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
    });
  });
}
