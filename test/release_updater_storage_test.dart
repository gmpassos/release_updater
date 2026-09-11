@TestOn('vm')
import 'dart:async';

import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('ReleaseStorage.updateTo (errors)', () {
    ReleaseBundle bundle() => MemoryReleaseBundle(Release.parse('foo/1.0.0'), {
      ReleaseFile('hello.txt', 'Hello World!'),
    });

    test("can't save a file", () {
      var storage = _FailingStorage(failSaveFile: true);

      expect(() => storage.updateTo(bundle()), throwsStateError);
    });

    test("can't save the release", () {
      var storage = _FailingStorage(failSaveRelease: true);

      expect(() => storage.updateTo(bundle()), throwsStateError);
    });

    test("can't save the manifest", () {
      var storage = _FailingStorage(failSaveManifest: true);

      expect(() => storage.updateTo(bundle()), throwsStateError);
    });

    test("can't check the manifest", () {
      var storage = _FailingStorage(failCheckManifest: true);

      expect(() => storage.updateTo(bundle()), throwsStateError);
    });

    test('no error', () async {
      var storage = _FailingStorage();

      var result = await storage.updateTo(bundle());

      expect(result!.savedFilesLength, equals(1));
    });
  });
}

/// A [MemoryStorage] that can fail a specific operation.
class _FailingStorage extends MemoryStorage {
  final bool failSaveFile;
  final bool failSaveRelease;
  final bool failSaveManifest;
  final bool failCheckManifest;

  _FailingStorage({
    this.failSaveFile = false,
    this.failSaveRelease = false,
    this.failSaveManifest = false,
    this.failCheckManifest = false,
  });

  @override
  bool saveFile(Release release, ReleaseFile file, {bool verbose = false}) =>
      failSaveFile ? false : super.saveFile(release, file, verbose: verbose);

  @override
  bool saveRelease(Release release) =>
      failSaveRelease ? false : super.saveRelease(release);

  @override
  bool saveManifest(ReleaseManifest manifest) =>
      failSaveManifest ? false : super.saveManifest(manifest);

  @override
  Future<bool> checkManifest(
    ReleaseManifest manifest, {
    bool verbose = false,
  }) async => failCheckManifest
      ? false
      : super.checkManifest(manifest, verbose: verbose);
}
