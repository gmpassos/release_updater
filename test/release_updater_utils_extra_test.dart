import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:typed_data';

import 'package:path/path.dart' as pack_path;
import 'package:release_updater/src/release_updater_utils.dart';
import 'package:test/test.dart';

void main() {
  group('Path predicates', () {
    test('isGenericPathSeparator', () {
      expect(isGenericPathSeparator('/'), isTrue);
      expect(isGenericPathSeparator('\\'), isTrue);
      expect(isGenericPathSeparator('|'), isFalse);
    });

    test('containsGenericPathSeparator', () {
      expect(containsGenericPathSeparator('a/b'), isTrue);
      expect(containsGenericPathSeparator(r'a\b'), isTrue);
      expect(containsGenericPathSeparator('ab'), isFalse);
    });

    test('startsWithGenericPathSeparator', () {
      expect(startsWithGenericPathSeparator('/a'), isTrue);
      expect(startsWithGenericPathSeparator(r'\\a'), isTrue);
      expect(startsWithGenericPathSeparator('a/b'), isFalse);
      expect(startsWithGenericPathSeparator('/'), isFalse);
    });

    test('endsWithGenericPathSeparator', () {
      expect(endsWithGenericPathSeparator('a/'), isTrue);
      expect(endsWithGenericPathSeparator(r'a\'), isTrue);
      expect(endsWithGenericPathSeparator('a/b'), isFalse);
    });

    test('startsWithURI', () {
      expect(startsWithURI('file:///a'), isTrue);
      expect(startsWithURI('http://a'), isTrue);
      expect(startsWithURI('https://a'), isTrue);
      expect(startsWithURI('ftp://a'), isTrue);
      expect(startsWithURI('/a'), isFalse);
      expect(startsWithURI('a/b'), isFalse);
    });

    test('startsWithFileScheme', () {
      expect(startsWithFileScheme('file:///a'), isTrue);
      expect(startsWithFileScheme('file://host/a'), isTrue);
      expect(startsWithFileScheme('http://a'), isFalse);
    });

    test('startsWithFileSchemeWithHost', () {
      expect(startsWithFileSchemeWithHost('file://host/a'), isTrue);
      expect(startsWithFileSchemeWithHost('file:///a'), isFalse);
    });

    test('startsWithDriver', () {
      expect(startsWithDriver(r'C:\a'), isTrue);
      expect(startsWithDriver('c:/a'), isTrue);
      expect(startsWithDriver('C:a'), isFalse);
      expect(startsWithDriver('/a'), isFalse);
    });

    test('isRootRelativePath', () {
      expect(isRootRelativePath('/a'), isTrue);
      expect(isRootRelativePath(r'\a'), isTrue);
      expect(isRootRelativePath(r'C:\a'), isTrue);
      expect(isRootRelativePath('file:///a'), isTrue);
      expect(isRootRelativePath('a/b'), isFalse);
      expect(isRootRelativePath('./a'), isFalse);
    });
  });

  group('getPathContext', () {
    test('by style', () {
      expect(
        getPathContext(asPosix: true).style,
        equals(pack_path.Style.posix),
      );
      expect(
        getPathContext(asWindows: true).style,
        equals(pack_path.Style.windows),
      );
      expect(
        getPathContext(separator: '/').style,
        equals(pack_path.Style.posix),
      );
      expect(
        getPathContext(separator: '\\').style,
        equals(pack_path.Style.windows),
      );
      expect(getPathContext().style, equals(pack_path.context.style));
    });

    test('a provided context has priority', () {
      var context = pack_path.Context(style: pack_path.Style.url);

      expect(
        identical(
          getPathContext(pathContext: context, asWindows: true),
          context,
        ),
        isTrue,
      );
    });
  });

  group('splitPathRootPrefix', () {
    test('empty and separator only', () {
      expect(splitPathRootPrefix(''), equals(['', '']));
      expect(splitPathRootPrefix('/', asPosix: true), equals(['/', '']));
      expect(splitPathRootPrefix(r'\', asWindows: true), equals([r'\', '']));
    });

    test('relative path', () {
      expect(
        splitPathRootPrefix('foo/bar.txt', asPosix: true),
        equals(['', 'foo/bar.txt']),
      );
    });

    test('multiple leading separators', () {
      expect(
        splitPathRootPrefix('///foo/bar.txt', asPosix: true),
        equals(['/', 'foo/bar.txt']),
      );
    });

    test('URI prefixes', () {
      expect(
        splitPathRootPrefix('file:///foo/bar.txt', asPosix: true),
        equals(['file:///', 'foo/bar.txt']),
      );

      expect(
        splitPathRootPrefix('http://host/foo.txt', asPosix: true),
        equals(['http://', 'host/foo.txt']),
      );
    });
  });

  group('joinPaths', () {
    test('empty path', () {
      expect(joinPaths('/parent', ''), equals(''));
    });

    test('null or empty parent', () {
      expect(joinPaths(null, 'a/b.txt', asPosix: true), equals('a/b.txt'));
      expect(joinPaths('', 'a/b.txt', asPosix: true), equals('a/b.txt'));
    });

    test('root relative path ignores the parent', () {
      expect(
        joinPaths('/parent', '/a/b.txt', asPosix: true),
        equals('/a/b.txt'),
      );
    });

    test('joins and normalizes', () {
      expect(
        joinPaths('/parent', 'a/../b.txt', asPosix: true),
        equals('/parent/b.txt'),
      );

      expect(
        joinPaths(r'C:\parent', r'a\b.txt', asWindows: true),
        equals(r'C:\parent\a\b.txt'),
      );
    });

    test('mixed separators', () {
      expect(
        joinPaths('/parent', r'a\b.txt', asPosix: true),
        equals('/parent/a/b.txt'),
      );
    });
  });

  group('normalizePlatformPath', () {
    test('POSIX', () {
      expect(
        normalizePlatformPath(r'foo\bar\baz.txt', asPosix: true),
        equals('foo/bar/baz.txt'),
      );

      expect(
        normalizePlatformPath('foo//bar/./baz.txt', asPosix: true),
        equals('foo/bar/baz.txt'),
      );
    });

    test('Windows', () {
      expect(
        normalizePlatformPath('foo/bar/baz.txt', asWindows: true),
        equals(r'foo\bar\baz.txt'),
      );

      expect(
        normalizePlatformPath(r'\foo\bar', asWindows: true),
        equals(r'\foo\bar'),
      );
    });

    test('with an explicit separator', () {
      expect(
        normalizePlatformPath(r'foo\bar', separator: '/'),
        equals('foo/bar'),
      );
    });
  });

  group('splitGenericPathSeparator', () {
    test('splits both separators', () {
      expect(splitGenericPathSeparator(r'a/b\c'), equals(['a', 'b', 'c']));
    });
  });

  group('Extensions', () {
    test('normalizeToPosixLines', () {
      expect('a\r\nb\rc\nd'.normalizeToPosixLines(), equals('a\nb\nc\nd'));
    });

    test('List<List<int>>.toBytes', () {
      expect(
        <List<int>>[
          [1, 2],
          [3],
          <int>[],
          [4, 5],
        ].toBytes(),
        equals([1, 2, 3, 4, 5]),
      );

      expect(<List<int>>[].toBytes(), isEmpty);
    });

    test('Stream<List<int>>.toBytes', () async {
      var stream = Stream<List<int>>.fromIterable([
        [1, 2],
        [3, 4],
      ]);

      expect(await stream.toBytes(), equals([1, 2, 3, 4]));
    });

    test('List<int>.computeSHA256', () {
      var sha256 = dart_convert.utf8.encode('abc').computeSHA256();

      expect(sha256, hasLength(32));
      expect(
        sha256.map((e) => e.toRadixString(16).padLeft(2, '0')).join(),
        equals(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      );

      expect(() => sha256[0] = 0, throwsUnsupportedError);
    });

    test('FutureOr<List<int>>.computeSHA256 (sync)', () {
      Uint8List? onValueSha256;

      FutureOr<List<int>> data = dart_convert.utf8.encode('abc');

      var sha256 = data.computeSHA256(onValue: (sha) => onValueSha256 = sha);

      expect(sha256, isA<Uint8List>());
      expect(onValueSha256, equals(sha256));
    });

    test('FutureOr<List<int>>.computeSHA256 (async)', () async {
      Uint8List? onValueSha256;

      FutureOr<List<int>> data = Future.value(dart_convert.utf8.encode('abc'));

      var sha256 = await data.computeSHA256(
        onValue: (sha) => onValueSha256 = sha,
      );

      expect(sha256, hasLength(32));
      expect(onValueSha256, equals(sha256));
      expect(sha256, equals(dart_convert.utf8.encode('abc').computeSHA256()));
    });
  });
}
