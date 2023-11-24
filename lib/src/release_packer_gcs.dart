import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:io';
import 'dart:typed_data';

import 'package:data_serializer/data_serializer_io.dart';
import 'package:gcloud/storage.dart' as gcs;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:path/path.dart' as pack_path;

import 'release_packer.dart';
import 'release_updater_bundle.dart';
import 'release_updater_config.dart';

class ReleasePackerCommandGCS extends ReleasePackerCommand {
  final String project;
  final String bucket;
  final Object credential;

  final Map<String, Object?>? parameters;
  final Object? body;

  ReleasePackerCommandGCS(this.project, this.bucket,
      {required this.credential, this.parameters, this.body}) {
    if (project.isEmpty) throw ArgumentError("Empty project!");
    if (bucket.isEmpty) throw ArgumentError("Empty bucket!");
  }

  factory ReleasePackerCommandGCS.fromJson(Map json) {
    var map = json.asJsonMap;

    var project =
        map.get<String>('project') ?? (throw ArgumentError.notNull('project'));
    var bucket =
        map.get<String>('bucket') ?? (throw ArgumentError.notNull('bucket'));
    var credential =
        map.get('credential') ?? (throw ArgumentError.notNull('credential'));

    var parameters = map.get<Map>('parameters');
    var body = map.get('body');

    return ReleasePackerCommandGCS(project, bucket,
        credential: credential, parameters: parameters?.asJsonMap, body: body);
  }

  static Future<auth.AutoRefreshingAuthClient> createGCSClient(
      Object credential) async {
    if (credential is String) {
      var credentialLC = credential.toLowerCase();
      if (credentialLC == 'metadata' || credentialLC == 'metadata.server') {
        return auth.clientViaMetadataServer();
      }
    }

    final accountCredentials =
        auth.ServiceAccountCredentials.fromJson(credential);

    try {
      var client = await auth.clientViaServiceAccount(
          accountCredentials, gcs.Storage.SCOPES);
      return client;
    } catch (e) {
      throw StateError("Error creating GCP client: $e");
    }
  }

  Future<
      ({
        String filePath,
        Uint8List bodyBytes,
        String contentType,
        String? release
      })?> resolveUploadParameters({ReleaseBundle? releaseBundle}) async {
    String? directory;
    String? file;
    String? release;
    Object? body;

    var contentType = parameters?['contentType'] as String?;

    if (this.body == '%RELEASE_BUNDLE%') {
      if (releaseBundle == null) {
        print('  ▒  Release bundle not provided for body: $this');
        return null;
      } else {
        print('   »  Using `ReleaseBundle` as body.');

        file = parameters?['file'] as String?;
        if (file != null) {
          var release = releaseBundle.release;
          var fileFormatted = ReleaseBundle.formatReleaseBundleFile(
              file, release.name, release.version, release.platform);
          file = fileFormatted;

          print('   »  Parameter `file`: $fileFormatted');
        }

        release = parameters?['release'] as String?;
        if (release != null && release.toLowerCase() == '%release%') {
          release = releaseBundle.release.toString();
          release = release;
        }
      }

      body = await releaseBundle.toBytes();
      contentType ??= releaseBundle.contentType;
    } else {
      file = parameters?['file'] as String?;
      release = parameters?['release'] as String?;
      body = this.body;
    }

    contentType ??= 'application/octet-stream';

    directory = parameters?['directory'] as String?;

    if (file == null) {
      throw ArgumentError.notNull("file");
    }

    if (body == null) {
      throw ArgumentError.notNull("body");
    }

    String filePath;
    if (directory != null && directory.isNotEmpty) {
      filePath = pack_path.normalize(pack_path.join(directory, file));
    } else {
      filePath = file;
    }

    Uint8List bodyBytes;
    if (body is String) {
      bodyBytes = dart_convert.utf8.encode(body);
    } else if (body is List<int>) {
      bodyBytes = body.asUint8List;
    } else {
      throw ArgumentError("Invalid body type: ${body.runtimeType}");
    }

    return (
      filePath: filePath,
      bodyBytes: bodyBytes,
      contentType: contentType,
      release: release,
    );
  }

  @override
  Future<bool> execute(ReleasePacker releasePacker, Directory rootDirectory,
      {ReleaseBundle? releaseBundle}) async {
    var params = await resolveUploadParameters(releaseBundle: releaseBundle);

    if (params == null) return false;

    gcs.ObjectMetadata? metadata;
    if (params.release != null) {
      metadata = gcs.ObjectMetadata(
        contentType: params.contentType,
        custom: {
          'release': params.release!,
        },
      );
    }

    print('   »  Parsing Google Cloud Storage credential...');

    var client = await createGCSClient(credential);

    print(
        '   »  Uploading to Google Cloud Storage> project: $project ; bucket: ${this.bucket} ; file: ${params.filePath}');

    var storage = gcs.Storage(client, project);
    var bucket = storage.bucket(this.bucket);

    var objInfo = await bucket.writeBytes(
      params.filePath,
      params.bodyBytes,
      contentType: params.contentType,
      metadata: metadata,
    );

    var ok = objInfo.length == params.bodyBytes.length;

    print('   »  GCS response> ${ok ? 'Ok' : 'Faul'}');

    return ok;
  }

  @override
  String toString() {
    return '$runtimeType{ project: $project, bucket: $bucket, parameters: $parameters, credential: $credential, body: $body }';
  }
}
