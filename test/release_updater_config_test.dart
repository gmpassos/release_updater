import 'dart:io';

import 'package:collection/collection.dart';
import 'package:release_updater/src/release_updater_config.dart';
import 'package:test/test.dart';

void main() {
  group('Config', () {
    test('parseProperties', () async {
      var args = ['build', '-Pk1=v1', 'file.txt', '-Pk2=v2'];

      var properties = parseProperties(args);

      expect(args, equals(['build', 'file.txt']));
      expect(properties, equals({'k1': 'v1', 'k2': 'v2'}));
    });

    test('parsePort', () async {
      expect(parsePort({'port': 123}), equals(123));
      expect(parsePort({'foo': 'bar'}), equals(8080));
    });

    test('parseReleaseDirectory', () async {
      expect(parseReleaseDirectory({'releases-directory': 'install-dir'}).path,
          endsWith('install-dir'));
      expect(parseReleaseDirectory({'foo': 'bar'}).path, endsWith('releases'));
    });

    test('parseAddress', () async {
      expect(parseAddress({'address': '0.0.0.0'}), endsWith('0.0.0.0'));
      expect(parseAddress({'foo': 'bar'}), endsWith('localhost'));
    });

    test('parseAppName', () async {
      expect(parseAppName({'name': 'appx'}), endsWith('appx'));
      expect(parseAppName({'foo': 'bar'}), endsWith('app'));
    });

    test('parseBaseURL', () async {
      expect(parseBaseURL({'base-url': 'http://foo/bar'}),
          endsWith('http://foo/bar'));
      expect(parseBaseURL({'foo': 'bar'}), endsWith('http://localhost:8080/'));
    });

    test('parseConfig', () async {
      var args = ['--k1', 'v1', 'file', '--k2', 'v2'];
      var config = parseConfig(args);

      expect(args, equals(['file']));
      expect(config, equals({'k1': 'v1', 'k2': 'v2'}));
    });

    test('resolveJsonProperties', () {
      expect(
          resolveJsonProperties(
            {
              'params': [
                {'id': '%FOO%'},
              ]
            },
            {'FOO': 'bar'},
          ),
          equals({
            'params': [
              {'id': 'bar'},
            ]
          }));
    });

    test('resolveJsonProperties (allowEnv)', () {
      var envEntry = Platform.environment.entries
          .firstWhereOrNull((e) => e.key.length >= 2 && e.value.isNotEmpty);

      var envKey = envEntry?.key ?? 'ENVx';
      var envVal = envEntry?.value ?? 'VALy';

      var properties = envEntry != null ? null : {envKey: envVal};

      print("-- envKey: $envKey");
      print("-- envVal: $envVal");
      print("-- properties: $properties");

      expect(
          resolveJsonProperties(
            {
              'params': [
                {'id': '%$envKey%'},
              ]
            },
            properties,
            allowEnv: true,
          ),
          equals({
            'params': [
              {'id': envVal},
            ]
          }));
    });
  });
}
