@TestOn('vm')
import 'dart:io';

import 'package:mercury_client/mercury_client.dart';
import 'package:release_updater/release_packer.dart';
import 'package:release_updater/release_updater.dart';
import 'package:test/test.dart';

void main() {
  group('parseInlineCommand', () {
    test('quoted arguments', () {
      expect(
        ReleasePackerCommand.parseInlineCommand('foo  a   "b c"  d'),
        equals(['foo', 'a', 'b c', 'd']),
      );
    });

    test('empty', () {
      expect(ReleasePackerCommand.parseInlineCommand('   '), isEmpty);
    });
  });

  group('ReleasePackerCommand.from', () {
    test('String (dart pub get)', () {
      expect(
        ReleasePackerCommand.from('dart_pub_get'),
        isA<ReleasePackerDartPubGet>(),
      );
      expect(
        ReleasePackerCommand.from('DART PUB GET'),
        isA<ReleasePackerDartPubGet>(),
      );
    });

    test('String (empty)', () {
      expect(ReleasePackerCommand.from(''), isNull);
    });

    test('String (dart command)', () {
      var cmd = ReleasePackerCommand.from('dart compile exe bin/foo.dart');

      // NOTE: the inline `String` form is not specialized to a
      // `ReleasePackerDartCompileExe` (the `List` form is).
      expect(cmd, isA<ReleasePackerDartCommand>());

      var dartCmd = cmd as ReleasePackerDartCommand;
      expect(dartCmd.command, equals('compile'));
      expect(dartCmd.args, equals(['exe', 'bin/foo.dart']));
      expect(cmd.toString(), contains('bin/foo.dart'));
    });

    test('String (process command)', () {
      var cmd = ReleasePackerCommand.from('bin/foo.exe -a "x y"');

      expect(cmd, isA<ReleasePackerProcessCommand>());

      var processCmd = cmd as ReleasePackerProcessCommand;
      expect(processCmd.command, equals('bin/foo.exe'));
      expect(processCmd.args, equals(['-a', 'x y']));
      expect(processCmd.toString(), contains('bin/foo.exe'));
    });

    test('a `ReleasePackerCommand` is returned as is', () {
      var cmd = ReleasePackerDartPubGet();
      expect(identical(ReleasePackerCommand.from(cmd), cmd), isTrue);
    });

    test('Map (rm/del)', () {
      var cmd = ReleasePackerCommand.from({'rm': 'foo.out'});

      expect(cmd, isA<ReleasePackerCommandDelete>());
      expect((cmd as ReleasePackerCommandDelete).path, equals('foo.out'));

      expect(
        (ReleasePackerCommand.from({'del': 'foo.out'})
                as ReleasePackerCommandDelete)
            .path,
        equals('foo.out'),
      );

      expect(ReleasePackerCommand.from({'rm': '  '}), isNull);
    });

    test('Map (dart_pub_get)', () {
      expect(
        ReleasePackerCommand.from({'dart_pub_get': 'true'}),
        isA<ReleasePackerDartPubGet>(),
      );

      expect(ReleasePackerCommand.from({'dart_pub_get': 'false'}), isNull);
    });

    test('Map (dart)', () {
      var cmd = ReleasePackerCommand.from({'dart': 'compile exe bin/foo.dart'});

      expect(cmd, isA<ReleasePackerDartCommand>());
      expect((cmd as ReleasePackerDartCommand).command, equals('compile'));
      expect(cmd.args, equals(['exe', 'bin/foo.dart']));
    });

    test('Map (windows_gui)', () {
      var fromString =
          ReleasePackerCommand.from({'windows_gui': 'bin/foo.exe'})
              as ReleasePackerWindowsSubsystemCommand;

      expect(
        fromString.args,
        equals(['--windows-gui', 'bin/foo.exe', 'bin/foo.exe']),
      );

      var fromMap =
          ReleasePackerCommand.from({
                'windows_gui': {'input': 'in.exe', 'output': 'out.exe'},
              })
              as ReleasePackerWindowsSubsystemCommand;

      expect(fromMap.args, equals(['--windows-gui', 'in.exe', 'out.exe']));

      expect(
        () => ReleasePackerCommand.from({'windows_gui': <String, Object?>{}}),
        throwsStateError,
      );
    });

    test('Map (command with stdout/stderr)', () {
      var cmd =
          ReleasePackerCommand.from({
                'command': 'bin/foo.exe -x',
                'stdout': 'foo.out',
                'stderr': 'foo.err',
              })
              as ReleasePackerProcessCommand;

      expect(cmd.command, equals('bin/foo.exe'));
      expect(cmd.args, equals(['-x']));
      expect(cmd.stdoutFilePath, equals('foo.out'));
      expect(cmd.stderrFilePath, equals('foo.err'));
    });

    test('Map (url)', () {
      var cmd =
          ReleasePackerCommand.from({'url': 'http://foo/bar'})
              as ReleasePackerCommandURL;

      expect(cmd.url, equals('http://foo/bar'));
    });

    test('Map (unknown)', () {
      expect(ReleasePackerCommand.from({'unknown': 'x'}), isNull);
    });

    test('List (release_utility)', () {
      var cmd =
          ReleasePackerCommand.from([
                'release_utility',
                '--windows-console',
                'in.exe',
              ])
              as ReleasePackerWindowsSubsystemCommand;

      expect(cmd.args, equals(['--windows-console', 'in.exe', 'in.exe']));
    });

    test('unknown type', () {
      expect(() => ReleasePackerCommand.from(123), throwsArgumentError);
    });
  });

  group('ReleasePackerCommandWithArgs', () {
    test('empty command', () {
      expect(() => ReleasePackerProcessCommand(' '), throwsArgumentError);
    });

    test('from (unknown type)', () {
      expect(() => ReleasePackerProcessCommand.from(123), throwsArgumentError);
      expect(() => ReleasePackerDartCommand.from(123), throwsArgumentError);
      expect(
        () => ReleasePackerWindowsSubsystemCommand.from(123),
        throwsArgumentError,
      );
    });
  });

  group('ReleasePackerCommandDelete', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-cmd--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('empty path', () {
      expect(() => ReleasePackerCommandDelete(''), throwsArgumentError);
    });

    test('execute', () async {
      var file = File('${tmpDir.path}/foo.out');
      file.writeAsStringSync('x');

      var cmd = ReleasePackerCommandDelete('foo.out');

      expect(cmd.toString(), contains('foo.out'));

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );

      expect(await cmd.execute(packer, tmpDir), isTrue);
      expect(file.existsSync(), isFalse);

      // The file does not exist anymore:
      expect(await cmd.execute(packer, tmpDir), isFalse);
    });
  });

  group('ReleasePackerProcessCommand', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('release-packer-proc--');
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('execute and save stdout', () async {
      if (Platform.isWindows) return;

      File('${tmpDir.path}/a.txt').writeAsStringSync('x');

      var cmd = ReleasePackerProcessCommand('ls', ['a.txt'], 'ls.out');

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );

      expect(cmd.execute(packer, tmpDir), isTrue);

      var out = File('${tmpDir.path}/ls.out');
      expect(out.existsSync(), isTrue);
      expect(out.readAsStringSync().trim(), equals('a.txt'));
    });

    test('execute with an error exit code', () {
      if (Platform.isWindows) return;

      var cmd = ReleasePackerProcessCommand('ls', ['unknown-file-x']);

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );

      expect(cmd.execute(packer, tmpDir), isFalse);
    });

    test('saveStdout without a file path', () {
      var cmd = ReleasePackerProcessCommand('ls');

      expect(cmd.saveStdout(tmpDir, 'output'), isTrue);
      expect(cmd.saveStderr(tmpDir, null), isTrue);
    });

    test('saveStdout of an unsupported type', () {
      var cmd = ReleasePackerProcessCommand('ls', [], 'out.txt');

      expect(cmd.saveStdout(tmpDir, 123), isFalse);
    });

    test('saveStdout of bytes', () {
      var cmd = ReleasePackerProcessCommand('ls', [], 'out.bin');

      expect(cmd.saveStdout(tmpDir, <int>[65, 66]), isTrue);
      expect(File('${tmpDir.path}/out.bin').readAsStringSync(), equals('AB'));
    });
  });

  group('ReleasePackerCommandURL', () {
    test('empty URL', () {
      expect(() => ReleasePackerCommandURL(''), throwsArgumentError);
    });

    test('fromJson (String)', () {
      var cmd = ReleasePackerCommandURL.fromJson('http://foo/bar');

      expect(cmd.url, equals('http://foo/bar'));
      expect(cmd.parameters, isNull);
      expect(cmd.authorization, isNull);
      expect(cmd.body, isNull);
    });

    test('fromJson (invalid)', () {
      expect(() => ReleasePackerCommandURL.fromJson(123), throwsArgumentError);
      expect(
        () => ReleasePackerCommandURL.fromJson(<String, Object?>{}),
        throwsArgumentError,
      );
    });

    test('toCredential', () {
      expect(ReleasePackerCommandURL.toCredential(null), isNull);
      expect(ReleasePackerCommandURL.toCredential(123), isNull);
      expect(ReleasePackerCommandURL.toCredential(<Object>[]), isNull);

      var credential = BasicCredential('joe', '123');
      expect(
        identical(ReleasePackerCommandURL.toCredential(credential), credential),
        isTrue,
      );

      var fromString =
          ReleasePackerCommandURL.toCredential('joe:123') as BasicCredential;
      expect(fromString.username, equals('joe'));
      expect(fromString.password, equals('123'));

      var fromStringNoPass =
          ReleasePackerCommandURL.toCredential('joe') as BasicCredential;
      expect(fromStringNoPass.password, equals(''));

      var fromList =
          ReleasePackerCommandURL.toCredential(['joe', '123'])
              as BasicCredential;
      expect(fromList.username, equals('joe'));

      var fromMap =
          ReleasePackerCommandURL.toCredential({'user': 'joe', 'pass': '123'})
              as BasicCredential;
      expect(fromMap.username, equals('joe'));
      expect(fromMap.password, equals('123'));

      var fromMapPassphrase =
          ReleasePackerCommandURL.toCredential({
                'username': 'joe',
                'passphrase': 'abc',
              })
              as BasicCredential;
      expect(fromMapPassphrase.password, equals('abc'));

      var bearer =
          ReleasePackerCommandURL.toCredential({'token': 'abc123'})
              as BearerCredential;
      expect(bearer.token, equals('abc123'));

      expect(ReleasePackerCommandURL.toCredential({'other': 'x'}), isNull);
    });

    test('execute (connection error)', () async {
      var cmd = ReleasePackerCommandURL(
        'http://localhost:1/unknown',
        body: 'data',
      );

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );

      expect(await cmd.execute(packer, Directory.systemTemp), isFalse);
    });

    test('execute (missing release bundle)', () async {
      var cmd = ReleasePackerCommandURL(
        'http://localhost:1/unknown',
        body: '%RELEASE_BUNDLE%',
      );

      var packer = ReleasePacker(
        'foo',
        SemanticVersioning.parse('1.0.0'),
        <ReleasePackerFile>[],
      );

      expect(await cmd.execute(packer, Directory.systemTemp), isFalse);
    });

    test('upload a release bundle to a server', () async {
      var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      var uploads = <String, int>{};

      server.listen((request) async {
        var params = request.uri.queryParameters;
        var body = await request.fold<int>(0, (n, bs) => n + bs.length);

        uploads[params['file'] ?? ''] = body;
        uploads['release:${params['release']}'] = 1;

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.text;
        request.response.write('OK');
        await request.response.close();
      });

      try {
        var url = 'http://${server.address.host}:${server.port}/upload';

        var cmd = ReleasePackerCommandUploadReleaseBundle.byURL(
          url,
          authorization: BasicCredential('joe', '123456'),
        );

        var bundle = ReleaseBundleZip(
          Release.parse('foo/1.0.2/linux-x64'),
          files: [ReleaseFile('a.txt', 'A')],
        );

        var packer = ReleasePacker(
          'foo',
          SemanticVersioning.parse('1.0.2'),
          <ReleasePackerFile>[],
        );

        var ok = await cmd.execute(
          packer,
          Directory.systemTemp,
          releaseBundle: bundle,
        );

        expect(ok, isTrue);
        expect(uploads.keys, contains('foo-1.0.2-linux-x64.zip'));
        expect(uploads['foo-1.0.2-linux-x64.zip'], greaterThan(0));
        expect(uploads.keys, contains('release:foo/1.0.2/linux-x64'));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('ReleasePackerFile', () {
    test('fromJson (String)', () {
      var file = ReleasePackerFile.fromJson('a.txt');

      expect(file.sourcePath, equals('a.txt'));
      expect(file.destinyPath, equals('a.txt'));
      expect(file.hasCommands, isFalse);
    });

    test('fromJson (Map)', () {
      var file = ReleasePackerFile.fromJson({
        'bin/foo.exe': 'foo-cli.exe',
        'platform': 'linux',
      });

      expect(file.sourcePath, equals('bin/foo.exe'));
      expect(file.destinyPath, equals('foo-cli.exe'));
      expect(file.matchesPlatform('linux-x64'), isTrue);
      expect(file.matchesPlatform('windows-x86'), isFalse);
      expect(file.matchesPlatform(null), isTrue);
      expect(file.toString(), contains('bin/foo.exe'));
    });

    test('fromJson (`.` destiny path)', () {
      var file = ReleasePackerFile.fromJson({'a.txt': '.'});

      expect(file.destinyPath, equals('a.txt'));
    });

    test('fromJson (windows_gui: true)', () {
      var file = ReleasePackerFile.fromJson({
        'bin/foo.exe': 'foo.exe',
        'windows_gui': true,
      });

      expect(file.hasCommands, isTrue);
      expect(
        file.hasCommandOfType<ReleasePackerWindowsSubsystemCommand>(),
        isTrue,
      );
    });

    test('fromJson (platform list)', () {
      var file = ReleasePackerFile.fromJson({
        'a.txt': 'a.txt',
        'platform': ['linux', 'macos'],
      });

      expect(file.platforms, hasLength(2));
      expect(file.matchesPlatform('macos-arm64'), isTrue);
      expect(file.matchesPlatform('windows-x86'), isFalse);
    });

    test('fromJson (unknown type)', () {
      expect(() => ReleasePackerFile.fromJson(123), throwsArgumentError);
    });
  });

  group('ReleasePacker', () {
    test('getFiles and getFileMatching', () {
      var packer = ReleasePacker('foo', SemanticVersioning.parse('1.0.0'), [
        ReleasePackerFile('a.txt', 'a.txt'),
        ReleasePackerFile('b.txt', 'b.txt', platform: 'linux'),
      ]);

      expect(packer.files, hasLength(2));
      expect(packer.getFiles(), hasLength(2));
      expect(packer.getFiles(platform: 'linux-x64'), hasLength(2));
      expect(
        packer.getFiles(platform: 'windows-x86').map((e) => e.sourcePath),
        equals(['a.txt']),
      );

      expect(packer.getFile('a.txt')!.destinyPath, equals('a.txt'));
      expect(packer.getFile('unknown.txt'), isNull);
      expect(packer.getFile('b.txt', platform: 'windows-x86'), isNull);

      expect(
        packer.getFileMatching(RegExp(r'\.txt$'))!.sourcePath,
        equals('a.txt'),
      );
      expect(packer.getFileMatching(RegExp(r'\.exe$')), isNull);

      expect(packer.toString(), contains('files: 2'));
      expect(packer.properties, isEmpty);
    });

    test('fromJson (defaults)', () {
      var packer = ReleasePacker.fromJson(<String, Object?>{});

      expect(packer.name, equals('app'));
      expect(packer.version.toString(), equals('0.0.1'));
      expect(packer.files, isEmpty);
      expect(packer.prepareCommands, isNull);
      expect(packer.finalizeCommands, isNull);
    });

    test('fromFilePath (missing file)', () {
      expect(
        () => ReleasePacker.fromFilePath('__unknown_config__.json'),
        throwsStateError,
      );
    });
  });
}
