import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/push_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/push/push_relay.dart';

/// Where the relay is and the poke (`docs/cloud-shared-freshness.md` §7):
/// `config/push` read at most once a day, only `https` kept; one poke in
/// thirty seconds, the last kept and urgent winning, bounded by ten seconds.
/// The HTTP call is a seam, so nothing here opens a socket.
void main() {
  late List<({Uri url, String bearer, Map<String, Object?> body})> posts;
  late int status;
  late Completer<void>? hold;
  late int configReads;
  late Object? configAnswer;
  late DateTime now;
  late String? signedIn;
  late String? token;
  late String? retryAfter;

  setUp(() {
    posts = [];
    status = 204;
    retryAfter = null;
    hold = null;
    configReads = 0;
    configAnswer = 'https://relay.test/';
    now = DateTime(2026, 11, 13, 12);
    signedIn = 'uid-a';
    token = 'token';
  });

  Future<PushAnswer> post(
    Uri url, {
    required String bearer,
    required String body,
    required Duration deadline,
  }) async {
    posts.add((
      url: url,
      bearer: bearer,
      body: jsonDecode(body) as Map<String, Object?>,
    ));
    if (hold case final waiting?) await waiting.future;
    return (status: status, retryAfter: retryAfter);
  }

  Future<HttpPushRelay> relayOver(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = SharedPreferences.getInstance();
    final relay = HttpPushRelay(
      prefs: prefs,
      readConfig: () async {
        configReads++;
        final answer = configAnswer;
        if (answer is Exception) throw answer;
        return answer as String?;
      },
      idToken: () async => token,
      signedIn: () => signedIn,
      post: post,
      clock: () => now,
    );
    await prefs;
    await pumpEventQueue();
    return relay;
  }

  group('where the relay is', () {
    test('read once a day, kept for the install, its trailing slash '
        'dropped', () async {
      final relay = await relayOver({});
      expect(relay.address, isNull);

      expect(await relay.refresh(), Uri.parse('https://relay.test'));
      expect(configReads, 1);
      now = now.add(const Duration(hours: 23));
      await relay.refresh();
      expect(configReads, 1);
      now = now.add(const Duration(hours: 2));
      await relay.refresh();
      expect(configReads, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SettingsKeys.pushRelayUrl), 'https://relay.test');
    });

    test('a failed read keeps the last value; an absent document is no '
        'relay', () async {
      final relay = await relayOver({});
      await relay.refresh();
      now = now.add(const Duration(days: 2));
      configAnswer = Exception('offline');
      expect(await relay.refresh(), Uri.parse('https://relay.test'));
      now = now.add(const Duration(days: 2));
      configAnswer = null;
      expect(await relay.refresh(), isNull);
      expect(relay.address, isNull);
    });

    test('after a failed read the next is tried an hour later, not '
        'before', () async {
      final relay = await relayOver({});
      await relay.refresh();
      now = now.add(const Duration(days: 2));
      configAnswer = Exception('offline');
      await relay.refresh();
      expect(configReads, 2);
      now = now.add(const Duration(minutes: 59));
      await relay.refresh();
      expect(configReads, 2);
      now = now.add(const Duration(minutes: 2));
      await relay.refresh();
      expect(configReads, 3);
    });

    test('callers while a read is in flight share it', () async {
      final relay = await relayOver({});
      final first = relay.refresh();
      final second = relay.refresh();
      expect(await first, Uri.parse('https://relay.test'));
      expect(await second, Uri.parse('https://relay.test'));
      expect(configReads, 1);
    });

    test('a clock gone backwards reads again, and pokes at once', () async {
      final relay = await relayOver({});
      await relay.refresh();
      now = now.subtract(const Duration(hours: 1));
      await relay.refresh();
      expect(configReads, 2);

      relay.poke('pair-1', urgent: false);
      now = now.subtract(const Duration(seconds: 10));
      relay.poke('pair-1', urgent: true);
      await pumpEventQueue();
      expect(posts, hasLength(2));
    });

    test('anything but https is refused', () {
      expect(HttpPushRelay.parseRelay('https://user@relay.test'), isNull);
      expect(HttpPushRelay.parseRelay('https://relay.test/#x'), isNull);
      expect(HttpPushRelay.parseRelay('http://relay.test'), isNull);
      expect(HttpPushRelay.parseRelay('relay.test'), isNull);
      expect(HttpPushRelay.parseRelay('https://'), isNull);
      expect(HttpPushRelay.parseRelay('https://relay.test?x=1'), isNull);
      expect(
        HttpPushRelay.parseRelay(' https://relay.test/base// '),
        Uri.parse('https://relay.test/base'),
      );
    });
  });

  group('the poke', () {
    const known = {SettingsKeys.pushRelayUrl: 'https://relay.test'};

    test('POSTs the pair and its urgency with the account\'s token', () async {
      final relay = await relayOver(known);
      relay.poke('pair-1', urgent: true);
      await pumpEventQueue();

      expect(posts.single.url, Uri.parse('https://relay.test/poke'));
      expect(posts.single.bearer, 'token');
      expect(posts.single.body, {'pair': 'pair-1', 'urgent': true});
    });

    test('nothing goes out while no relay is known', () async {
      final relay = await relayOver({});
      relay.poke('pair-1', urgent: true);
      await pumpEventQueue();
      expect(posts, isEmpty);
    });

    HttpPushRelay fakeRelay(FakeAsync async) {
      SharedPreferences.setMockInitialValues(known);
      final relay = HttpPushRelay(
        prefs: SharedPreferences.getInstance(),
        readConfig: () async => null,
        idToken: () async => token,
        signedIn: () => signedIn,
        post: post,
        clock: () => now,
      );
      async.flushMicrotasks();
      return relay;
    }

    List<String> capturedLog() {
      final logged = <String>[];
      final printer = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add('$message');
      addTearDown(() => debugPrint = printer);
      return logged;
    }

    test('a held poke belongs to the account it was asked under: another '
        'account at the minute\'s end drops it, with a line', () {
      final logged = capturedLog();
      fakeAsync((async) {
        final relay = fakeRelay(async);
        relay.poke('pair-a', urgent: false);
        async.flushMicrotasks();
        now = now.add(const Duration(seconds: 5));
        relay.poke('pair-a', urgent: true);
        signedIn = 'uid-b';
        token = 'token-of-b';
        now = now.add(const Duration(seconds: 55));
        async.elapse(const Duration(seconds: 55));

        expect(posts, hasLength(1));
        expect(posts.single.bearer, 'token');
        expect(logged.last, contains('another account'));
      });
    });

    test('nobody signed in at the minute\'s end, or no token: dropped, '
        'with a line', () {
      final logged = capturedLog();
      fakeAsync((async) {
        final relay = fakeRelay(async);
        relay.poke('pair-a', urgent: false);
        async.flushMicrotasks();
        now = now.add(const Duration(seconds: 5));
        relay.poke('pair-a', urgent: true);
        signedIn = null;
        relay.flush();
        async.flushMicrotasks();
        expect(posts, hasLength(1));
        expect(logged.last, contains('nobody signed in'));

        signedIn = 'uid-a';
        token = null;
        now = now.add(const Duration(minutes: 2));
        relay.poke('pair-a', urgent: true);
        async.flushMicrotasks();
        expect(posts, hasLength(1));
        expect(logged.last, contains('no ID token'));
      });
    });

    group('the relay\'s answers, told apart — no queue, no retry', () {
      /// Pokes [pair] two minutes after the last, past the spacing.
      void pokeLater(FakeAsync async, HttpPushRelay relay, String pair) {
        now = now.add(const Duration(minutes: 2));
        async.elapse(const Duration(minutes: 2));
        relay.poke(pair, urgent: false);
        async.flushMicrotasks();
      }

      test('403: that pair is not poked again in this process, said '
          'once; another pair still is', () {
        final logged = capturedLog();
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 403;
          relay.poke('pair-x', urgent: true);
          async.flushMicrotasks();
          expect(logged.where((l) => l.contains('refused')), hasLength(1));

          status = 204;
          pokeLater(async, relay, 'pair-x');
          pokeLater(async, relay, 'pair-x');
          expect(posts, hasLength(1));
          expect(logged.where((l) => l.contains('refused')), hasLength(1));

          pokeLater(async, relay, 'pair-y');
          expect(posts.last.body['pair'], 'pair-y');
        });
      });

      test('a 403 holds for kPushRefusalHolds, not for the life of the '
          'process — an edge in front of the relay can answer one too — and '
          'by pair AND account: the same pair under another account still '
          'goes (second look, D6)', () {
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 403;
          relay.poke('pair-x', urgent: true);
          async.flushMicrotasks();
          status = 204;

          signedIn = 'uid-b';
          pokeLater(async, relay, 'pair-x');
          expect(posts, hasLength(2), reason: 'another account, that pair');

          signedIn = 'uid-a';
          pokeLater(async, relay, 'pair-x');
          expect(posts, hasLength(2), reason: 'refused as uid-a, still');

          now = now.add(kPushRefusalHolds);
          async.elapse(kPushRefusalHolds);
          relay.poke('pair-x', urgent: false);
          async.flushMicrotasks();
          expect(posts, hasLength(3), reason: 'the refusal ended');
        });
      });

      test('a pause is the account\'s, as the relay counts its callers: '
          'account A asked to wait, account B\'s poke goes (second look, '
          'D6)', () {
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 429;
          retryAfter = '3600';
          relay.poke('pair-1', urgent: false);
          async.flushMicrotasks();
          status = 204;
          retryAfter = null;

          signedIn = 'uid-b';
          pokeLater(async, relay, 'pair-2');
          expect(posts, hasLength(2));
          expect(posts.last.body['pair'], 'pair-2');

          signedIn = 'uid-a';
          pokeLater(async, relay, 'pair-1');
          expect(posts, hasLength(2), reason: 'uid-a still waits');
        });
      });

      test('a phone clock set back does not lengthen a pause or a refusal '
          'past its bound', () {
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 429;
          retryAfter = '300';
          relay.poke('pair-1', urgent: false);
          async.flushMicrotasks();
          status = 403;
          retryAfter = null;
          now = now.add(const Duration(minutes: 6));
          async.elapse(const Duration(minutes: 6));
          relay.poke('pair-x', urgent: false);
          async.flushMicrotasks();
          expect(posts, hasLength(2));
          status = 204;

          // A day back: both would stand a day longer.
          now = now.subtract(const Duration(days: 1));
          async.elapse(const Duration(minutes: 2));
          relay.poke('pair-x', urgent: false);
          async.flushMicrotasks();
          expect(posts, hasLength(3));
        });
      });

      test('429: pokes inside its Retry-After are dropped, with a line; the '
          'first after it goes', () {
        final logged = capturedLog();
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 429;
          retryAfter = '300';
          relay.poke('pair-1', urgent: false);
          async.flushMicrotasks();
          status = 204;
          retryAfter = null;

          pokeLater(async, relay, 'pair-1');
          pokeLater(async, relay, 'pair-2');
          expect(posts, hasLength(1));
          expect(logged.last, contains('asked to wait'));

          pokeLater(async, relay, 'pair-1');
          expect(posts, hasLength(2));
        });
      });

      test('503 with a Retry-After past the ceiling pauses for the ceiling '
          'alone; one as a date is read as a date', () {
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 503;
          retryAfter = '86400';
          relay.poke('pair-1', urgent: false);
          async.flushMicrotasks();
          status = 204;
          retryAfter = null;
          now = now.add(const Duration(minutes: 58));
          async.elapse(const Duration(minutes: 58));
          relay.poke('pair-1', urgent: false);
          async.flushMicrotasks();
          expect(posts, hasLength(1));

          pokeLater(async, relay, 'pair-1');
          expect(posts, hasLength(2), reason: 'an hour is the ceiling');

          status = 503;
          // Three minutes past the poke that is answered, two from now.
          retryAfter = HttpDate.format(now.add(const Duration(minutes: 5)));
          pokeLater(async, relay, 'pair-1');
          status = 204;
          retryAfter = null;
          pokeLater(async, relay, 'pair-1');
          expect(posts, hasLength(3), reason: 'two minutes into three');
          pokeLater(async, relay, 'pair-1');
          expect(posts, hasLength(4));
        });
      });

      test('503 with no Retry-After, and 401: logged and dropped, the next '
          'poke goes as ever', () {
        final logged = capturedLog();
        fakeAsync((async) {
          final relay = fakeRelay(async);
          status = 503;
          relay.poke('pair-1', urgent: false);
          async.flushMicrotasks();
          expect(logged.last, contains('503'));
          status = 401;
          pokeLater(async, relay, 'pair-1');
          expect(logged.last, contains('401'));
          async.elapse(const Duration(minutes: 5));
          expect(posts, hasLength(2), reason: 'nothing tried again');

          status = 204;
          pokeLater(async, relay, 'pair-1');
          expect(posts, hasLength(3));
        });
      });
    });

    test('a flush is done when its sends are: what waited goes before the '
        'caller goes on', () async {
      final relay = await relayOver(known);
      relay.poke('pair-a', urgent: false);
      relay.poke('pair-a', urgent: true);
      hold = Completer<void>();
      var flushed = false;
      final flushing = relay.flush().then((_) => flushed = true);
      await pumpEventQueue();
      expect(posts, hasLength(2));
      expect(flushed, isFalse, reason: 'the held send has no answer yet');

      hold!.complete();
      await flushing;
      expect(flushed, isTrue);
    });

    test('the first after a quiet minute goes at once; those within it wait '
        'for its end, one per pair, urgent when any merged was', () {
      fakeAsync((async) {
        final relay = fakeRelay(async);
        relay.poke('pair-1', urgent: false);
        async.flushMicrotasks();
        now = now.add(const Duration(seconds: 5));
        relay.poke('pair-1', urgent: true);
        relay.poke('pair-1', urgent: false);
        relay.poke('pair-2', urgent: false);
        async.flushMicrotasks();
        expect(posts, hasLength(1));

        now = now.add(const Duration(seconds: 54));
        async.elapse(const Duration(seconds: 54));
        expect(posts, hasLength(1), reason: 'still within the minute');
        now = now.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        expect(
          [for (final post in posts.skip(1)) post.body],
          [
            {'pair': 'pair-1', 'urgent': true},
            {'pair': 'pair-2', 'urgent': false},
          ],
        );
      });
    });

    test('leaving the screen sends what waits now; dispose drops it', () {
      fakeAsync((async) {
        final relay = fakeRelay(async);
        relay.poke('pair-1', urgent: false);
        relay.poke('pair-1', urgent: true);
        async.flushMicrotasks();
        relay.flush();
        async.flushMicrotasks();
        expect(posts, hasLength(2));

        now = now.add(const Duration(seconds: 1));
        relay.poke('pair-2', urgent: true);
        relay.dispose();
        async.elapse(const Duration(minutes: 2));
        expect(posts, hasLength(2));
      });
    });

    test('an answer but 204 is logged and forgotten; a call with no answer '
        'is given up at ten seconds', () {
      final logged = <String>[];
      final printer = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add('$message');
      addTearDown(() => debugPrint = printer);
      fakeAsync((async) {
        final relay = fakeRelay(async);
        status = 503;
        relay.poke('pair-1', urgent: true);
        async.flushMicrotasks();
        expect(logged.last, contains('answered 503'));

        hold = Completer<void>();
        now = now.add(const Duration(minutes: 2));
        relay.poke('pair-1', urgent: true);
        async.elapse(const Duration(seconds: 9));
        expect(logged.where((line) => line.contains('Timeout')), isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(logged.last, contains('TimeoutException'));
      });
    });
  });

  group('postJson', () {
    late HttpServer server;
    late List<HttpRequest> seen;
    late List<String> bodies;

    setUp(() async {
      seen = [];
      bodies = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        seen.add(request);
        bodies.add(await utf8.decoder.bind(request).join());
        if (request.uri.path == '/moved') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/poke');
        } else if (request.uri.path == '/busy') {
          request.response
            ..statusCode = HttpStatus.tooManyRequests
            ..headers.set(HttpHeaders.retryAfterHeader, '120');
        } else {
          request.response.statusCode = HttpStatus.noContent;
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('sends the bearer, a JSON content type and the body', () async {
      final answer = await HttpPushRelay.postJson(
        at('/poke'),
        bearer: 'secret',
        body: '{"pair":"p","urgent":true}',
        deadline: const Duration(seconds: 5),
      );

      expect(answer.status, HttpStatus.noContent);
      expect(answer.retryAfter, isNull);
      expect(seen.single.method, 'POST');
      expect(
        seen.single.headers.value(HttpHeaders.authorizationHeader),
        'Bearer secret',
      );
      expect(seen.single.headers.contentType?.mimeType, 'application/json');
      expect(bodies.single, '{"pair":"p","urgent":true}');
    });

    test(
      'follows no redirect: the token never reaches another place',
      () async {
        final answer = await HttpPushRelay.postJson(
          at('/moved'),
          bearer: 'secret',
          body: '{}',
          deadline: const Duration(seconds: 5),
        );

        expect(answer.status, HttpStatus.found);
        expect(seen, hasLength(1));
      },
    );

    test('hands back the Retry-After the relay sent', () async {
      final answer = await HttpPushRelay.postJson(
        at('/busy'),
        bearer: 'secret',
        body: '{}',
        deadline: const Duration(seconds: 5),
      );

      expect(answer.status, HttpStatus.tooManyRequests);
      expect(answer.retryAfter, '120');
    });
  });
}
