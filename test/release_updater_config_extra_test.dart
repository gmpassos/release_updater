@TestOn('vm')
import 'dart:convert' as dart_convert;
import 'dart:io';

import 'package:release_updater/src/release_updater_config.dart';
import 'package:test/test.dart';

void main() {
  group('parseProperties', () {
    test('-D, flags and multiple values', () {
      var args = [
        'build',
        '-Dk1=v1',
        '-Pflag',
        '-Pk2=a=b',
        '-Pk3=x=y=z',
        'file.txt',
      ];

      var properties = parseProperties(args);

      expect(args, equals(['build', 'file.txt']));
      expect(
        properties,
        equals({
          'k1': 'v1',
          'flag': 'true',
          // NOTE: a value with `=` is split and joined with `;`:
          'k2': 'a;b',
          'k3': 'x;y;z',
        }),
      );
    });

    test('no properties', () {
      var args = ['build', 'file.txt'];
      expect(parseProperties(args), isEmpty);
      expect(args, equals(['build', 'file.txt']));
    });
  });

  group('parseConfig', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-config--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('empty args', () {
      expect(parseConfig(<String>[]), isEmpty);
    });

    test('a trailing `--key` without a value is not consumed', () {
      var args = ['--k1', 'v1', '--k2'];
      var config = parseConfig(args);

      expect(config, equals({'k1': 'v1'}));
      expect(args, equals(['--k2']));
    });

    test('JSON config file', () {
      var configFile = File('${tmpDir.path}/config.json');
      configFile.writeAsStringSync(
        dart_convert.json.encode({'port': 9090, 'name': 'foo'}),
      );

      var args = ['--address', '0.0.0.0', configFile.path];
      var config = parseConfig(args);

      expect(
        config,
        equals({'address': '0.0.0.0', 'port': 9090, 'name': 'foo'}),
      );
      expect(args, isEmpty);
    });

    test('missing or empty JSON config file', () {
      var missing = ['${tmpDir.path}/missing.json'];
      expect(parseConfig(missing), isEmpty);

      var emptyFile = File('${tmpDir.path}/empty.json');
      emptyFile.writeAsStringSync('{}');

      expect(parseConfig([emptyFile.path]), isEmpty);
    });

    test('a non JSON argument is kept', () {
      var args = ['releases.txt'];
      expect(parseConfig(args), isEmpty);
      expect(args, equals(['releases.txt']));
    });
  });

  group('JsonExtension.get', () {
    test('normalized keys', () {
      var config = <String, Object?>{'Releases-Directory': 'dir'};

      expect(config.get<String>('releases-directory'), equals('dir'));
      expect(config.get<String>('releasesdirectory'), equals('dir'));
      expect(config.get<String>('unknown'), isNull);
      expect(config.get<String>('unknown', 'def'), equals('def'));
    });

    test('type conversion', () {
      var config = <String, Object?>{
        'port': '8081',
        'ratio': '0.5',
        'name': 123,
        'invalid': 'x',
      };

      expect(config.get<int>('port'), equals(8081));
      expect(config.get<double>('ratio'), equals(0.5));
      expect(config.get<String>('name'), equals('123'));
      expect(config.get<int>('invalid', -1), equals(-1));
      expect(config.get<int>('unknown', 10), equals(10));
    });
  });

  group('resolvePropertyValue', () {
    test('resolves and returns literals', () {
      expect(resolvePropertyValue(null, null), isNull);
      expect(resolvePropertyValue({'K': 'v'}, 'literal'), equals('literal'));
      expect(resolvePropertyValue({'K': 'v'}, '%K%'), equals('v'));

      // An unresolved place holder returns `null`:
      expect(resolvePropertyValue({'K': 'v'}, '%OTHER%'), isNull);
      expect(resolvePropertyValue(null, '%K%'), isNull);
    });

    test('allowEnv', () {
      var envKey = Platform.environment.keys.firstWhere(
        (k) => RegExp(r'^\w+$').hasMatch(k),
      );

      expect(
        resolvePropertyValue(null, '%$envKey%', allowEnv: true),
        equals(Platform.environment[envKey]),
      );

      // A property has priority over the environment:
      expect(
        resolvePropertyValue(
          {envKey: 'from-property'},
          '%$envKey%',
          allowEnv: true,
        ),
        equals('from-property'),
      );
    });
  });

  group('resolveJsonProperties', () {
    test('null and unsupported types', () {
      expect(resolveJsonProperties(null, {'K': 'v'}), isNull);
      expect(resolveJsonProperties(123, {'K': 'v'}), isNull);
    });

    test('without properties the JSON is returned as is', () {
      var json = {'a': '%K%'};
      expect(identical(resolveJsonProperties(json, null), json), isTrue);
      expect(identical(resolveJsonProperties(json, {}), json), isTrue);

      var list = ['%K%'];
      expect(identical(resolveJsonListProperties(list, null), list), isTrue);

      expect(resolveJsonListProperties(<Object?>[], {'K': 'v'}), isEmpty);
      expect(
        resolveJsonMapProperties(<Object?, Object?>{}, {'K': 'v'}),
        isEmpty,
      );
    });

    test('non String keys are converted', () {
      expect(
        resolveJsonMapProperties({1: '%K%'}, {'K': 'v'}),
        equals({'1': 'v'}),
      );
    });
  });

  group('parseReleaseDirectory', () {
    test('absolute path', () {
      var path = Platform.isWindows ? r'C:\releases' : '/var/releases';

      expect(
        parseReleaseDirectory({'releases-directory': path}).path,
        equals(path),
      );
    });

    test('`release-directory` alias', () {
      expect(
        parseReleaseDirectory({'release-directory': 'install-dir'}).path,
        endsWith('install-dir'),
      );
    });
  });

  group('parseReleaseFile', () {
    test('default and aliases', () {
      expect(parseReleaseFile({}), equals('releases.txt'));
      expect(parseReleaseFile({'releases-file': 'my.txt'}), equals('my.txt'));
      expect(parseReleaseFile({'release-file': 'my2.txt'}), equals('my2.txt'));
    });
  });
}
