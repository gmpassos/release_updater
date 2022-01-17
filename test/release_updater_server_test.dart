@TestOn('vm')
import 'dart:io';

import 'package:release_updater/src/release_updater_server.dart';
import 'package:test/test.dart';

void main() {
  group('Server', () {
    setUp(() {});

    test('RequestInfo', () async {
      var address10 = InternetAddress('192.160.0.10');

      var requestInfo = resolveAddressRequestInfo(address10);

      var now = DateTime(2022, 1, 1);

      var requestI = 0;

      for (; requestI < 10; ++requestI) {
        now = now.add(Duration(seconds: 1));

        var blocked = requestInfo.isBlocked(now: now);
        print('-- $requestI > $now > $requestInfo > blocked: $blocked');

        expect(blocked, isFalse);

        requestInfo.markRequest(now: now);
        expect(requestInfo.isBlocked(now: now), isFalse);
      }

      print('------');

      for (; requestI < 30; ++requestI) {
        now = now.add(Duration(seconds: 1));

        var blocked = requestInfo.isBlocked(now: now);
        print('-- $requestI > $now > $requestInfo > blocked: $blocked');

        expect(blocked, requestI > 20 ? isTrue : isFalse);

        requestInfo.markRequest(now: now);
        requestInfo.markError(now: now);
        expect(blocked, requestI > 20 ? isTrue : isFalse);
      }

      print('------');

      now = now.add(Duration(minutes: 10));
      expect(requestInfo.isBlocked(now: now), isTrue);

      now = now.add(Duration(minutes: 10));
      expect(requestInfo.isBlocked(now: now), isTrue);

      now = now.add(Duration(minutes: 10));
      expect(requestInfo.isBlocked(now: now), isFalse);

      print('------');

      for (; requestI < 100; ++requestI) {
        now = now.add(Duration(seconds: 1));

        var blocked = requestInfo.isBlocked(now: now);
        print('-- $requestI > $now > $requestInfo > blocked: $blocked');

        expect(blocked, requestI > 80 ? isTrue : isFalse);

        if (!blocked) {
          requestInfo.markRequest(now: now);
          expect(requestInfo.isBlocked(now: now),
              requestI >= 80 ? isTrue : isFalse);
        }
      }
    });
  });
}
