import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    posts = [];
    status = 204;
    hold = null;
    configReads = 0;
    configAnswer = 'https://relay.test/';
    now = DateTime(2026, 11, 13, 12);
  });

  Future<int> post(
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
    return status;
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
      idToken: () async => 'token',
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

    test('anything but https is refused', () {
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
        idToken: () async => 'token',
        post: post,
        clock: () => now,
      );
      async.flushMicrotasks();
      return relay;
    }

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
        expect([for (final post in posts.skip(1)) post.body], [
          {'pair': 'pair-1', 'urgent': true},
          {'pair': 'pair-2', 'urgent': false},
        ]);
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
        } else {
          request.response.statusCode = HttpStatus.noContent;
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('sends the bearer, a JSON content type and the body', () async {
      final status = await HttpPushRelay.postJson(
        at('/poke'),
        bearer: 'secret',
        body: '{"pair":"p","urgent":true}',
        deadline: const Duration(seconds: 5),
      );

      expect(status, HttpStatus.noContent);
      expect(seen.single.method, 'POST');
      expect(
        seen.single.headers.value(HttpHeaders.authorizationHeader),
        'Bearer secret',
      );
      expect(seen.single.headers.contentType?.mimeType, 'application/json');
      expect(bodies.single, '{"pair":"p","urgent":true}');
    });

    test('follows no redirect: the token never reaches another place', () async {
      final status = await HttpPushRelay.postJson(
        at('/moved'),
        bearer: 'secret',
        body: '{}',
        deadline: const Duration(seconds: 5),
      );

      expect(status, HttpStatus.found);
      expect(seen, hasLength(1));
    });
  });
}
