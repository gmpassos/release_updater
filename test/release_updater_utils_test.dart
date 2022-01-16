import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as pack_path;

final pack_path.Context contextWindows =
    pack_path.Context(style: pack_path.Style.windows);
final pack_path.Context contextPosix =
    pack_path.Context(style: pack_path.Style.posix);

void main() {
  group('Utils', () {
    setUp(() {});

    test('normalizePlatformPathStyle', () async {
      expect(splitPathRootPrefix('/foo/bar/baz.txt'),
          equals([pack_path.separator, 'foo/bar/baz.txt']));

      expect(splitPathRootPrefix('/foo/bar/baz.txt', asPosix: true),
          equals(['/', 'foo/bar/baz.txt']));

      expect(splitPathRootPrefix('/foo/bar/baz.txt', asWindows: true),
          equals(['\\', 'foo/bar/baz.txt']));

      expect(
          splitPathRootPrefix('/foo/bar/baz.txt', pathContext: contextWindows),
          equals(['\\', 'foo/bar/baz.txt']));

      expect(splitPathRootPrefix('/foo/bar/baz.txt', pathContext: contextPosix),
          equals(['/', 'foo/bar/baz.txt']));

      expect(splitPathRootPrefix('\\foo\\bar/baz.txt', asPosix: true),
          equals(['/', 'foo\\bar/baz.txt']));

      expect(splitPathRootPrefix('\\foo\\bar/baz.txt', asWindows: true),
          equals(['\\', 'foo\\bar/baz.txt']));

      expect(splitPathRootPrefix('\\\\foo\\bar/baz.txt', asPosix: true),
          equals(['/', 'foo\\bar/baz.txt']));

      expect(splitPathRootPrefix('\\\\foo\\bar/baz.txt', asWindows: true),
          equals(['\\', 'foo\\bar/baz.txt']));

      expect(splitPathRootPrefix('/foo\\bar/baz.txt', asPosix: true),
          equals(['/', 'foo\\bar/baz.txt']));

      expect(splitPathRootPrefix('/foo\\bar/baz.txt', asWindows: true),
          equals(['\\', 'foo\\bar/baz.txt']));
    });

    test('normalizePlatformPathStyle', () async {
      expect(normalizePlatformPath('/foo/bar/baz.txt', separator: '/'),
          equals('/foo/bar/baz.txt'));

      expect(normalizePlatformPath('/foo/bar/baz.txt', separator: '\\'),
          equals('\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('/foo/bar/baz.txt', asPosix: true),
          equals('/foo/bar/baz.txt'));

      expect(normalizePlatformPath('/foo/bar/baz.txt', asWindows: true),
          equals('\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('//foo/bar/baz.txt', asPosix: true),
          equals('/foo/bar/baz.txt'));

      expect(normalizePlatformPath('//foo/bar/baz.txt', asWindows: true),
          equals('\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('\\\\foo/bar/baz.txt', asPosix: true),
          equals('/foo/bar/baz.txt'));

      expect(normalizePlatformPath('\\\\foo/bar/baz.txt', asWindows: true),
          equals('\\foo\\bar\\baz.txt'));

      expect(
          normalizePlatformPath('http://localhost/foo/bar/baz.txt',
              separator: '/'),
          equals('http://localhost/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('https://localhost/foo/bar/baz.txt',
              separator: '/'),
          equals('https://localhost/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('http://localhost/foo\\bar/baz.txt',
              separator: '/'),
          equals('http://localhost/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file://localhost/foo/bar/baz.txt',
              separator: '/'),
          equals('file://localhost/foo/bar/baz.txt'));

      expect(normalizePlatformPath('file:///foo/bar/baz.txt', separator: '/'),
          equals('/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file://localhost/foo\\bar/baz.txt',
              separator: '/'),
          equals('file://localhost/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file:\\localhost\\foo\\bar\\baz.txt',
              separator: '/'),
          equals('file://localhost/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file:\\localhost\\foo\\bar\\baz.txt',
              separator: '\\'),
          equals('file://localhost\\foo\\bar\\baz.txt'));

      expect(
          normalizePlatformPath('file:///C:/foo/bar/baz.txt', separator: '/'),
          equals('file:///C:/foo/bar/baz.txt'));

      expect(normalizePlatformPath('file://C:/foo/bar/baz.txt', separator: '/'),
          equals('file:///C:/foo/bar/baz.txt'));

      expect(normalizePlatformPath('file://C/foo/bar/baz.txt', separator: '/'),
          equals('file://C/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file:///C:/foo/bar/baz.txt', separator: '\\'),
          equals('C:\\foo\\bar\\baz.txt'));

      expect(
          normalizePlatformPath('file://C:/foo/bar/baz.txt', separator: '\\'),
          equals('C:\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('C:/foo/bar/baz.txt', separator: '\\'),
          equals('C:\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('C:\\foo\\bar\\baz.txt', separator: '\\'),
          equals('C:\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('C:\\\\foo\\bar/baz.txt', separator: '/'),
          equals('file:///C:/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file://C:\\foo\\bar/baz.txt', separator: '/'),
          equals('file:///C:/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('file://C:\\foo\\bar/baz.txt', separator: '\\'),
          equals('C:\\foo\\bar\\baz.txt'));

      expect(normalizePlatformPath('C:\\foo\\bar/baz.txt', separator: '/'),
          equals('file:///C:/foo/bar/baz.txt'));

      expect(normalizePlatformPath('C:\\foo\\bar/baz.txt', separator: '\\'),
          equals('C:\\foo\\bar\\baz.txt'));

      expect(
          normalizePlatformPath('C:\\foo\\bar/baz.txt',
              pathContext: contextPosix),
          equals('file:///C:/foo/bar/baz.txt'));

      expect(
          normalizePlatformPath('C:\\foo\\bar/baz.txt',
              pathContext: contextWindows),
          equals('C:\\foo\\bar\\baz.txt'));
    });
  });
}
