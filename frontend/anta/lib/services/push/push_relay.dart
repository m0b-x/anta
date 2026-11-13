import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/push_constants.dart';
import '../../constants/settings_keys.dart';

/// The relay that wakes the partner's phone (`docs/cloud-shared-freshness.md`
/// §7–§8): where it is, and the poke. Nothing in a sync run waits on it, and
/// no answer of it changes a run's result — a poke that fails is logged and
/// forgotten, and the check is the net.
abstract interface class PushRelay {
  /// The relay as this install last read it; null while none is known. Read
  /// from memory: a database that shares nothing asks it in every run, and
  /// an install that never paired never read one.
  Uri? get address;

  /// Reads `config/push` when the last read is a day old, keeping the last
  /// value when the read fails, and answers [address]. Asked only while
  /// paired. Never throws.
  Future<Uri?> refresh();

  /// Asks the relay to wake the other member of [pairId]; [urgent] when what
  /// changed can ring there (decision j). Returns at once: the first poke
  /// after a quiet minute goes now, and those asked for within the minute
  /// wait for its end — one per pair, urgent when any merged into it was.
  /// Nothing is sent while no relay is known.
  void poke(String pairId, {required bool urgent});

  /// Sends what waits for the minute's end now — the app is leaving the
  /// screen, and its process may not live to see the timer.
  void flush();
}

/// Bound wherever push cannot work: no relay, and a poke goes nowhere.
class NoOpPushRelay implements PushRelay {
  const NoOpPushRelay();

  @override
  Uri? get address => null;

  @override
  Future<Uri?> refresh() async => null;

  @override
  void poke(String pairId, {required bool urgent}) {}

  @override
  void flush() {}
}

/// One POST to the relay: its status code, or a throw when no answer came
/// within [deadline].
typedef PushPost =
    Future<int> Function(
      Uri url, {
      required String bearer,
      required String body,
      required Duration deadline,
    });

/// [PushRelay] over `dart:io`'s client, the relay's address kept in the
/// install's preferences — one relay per project, whichever database is
/// open.
class HttpPushRelay implements PushRelay {
  final Future<String?> Function() _readConfig;
  final Future<String?> Function() _idToken;
  final PushPost _post;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timer;

  SharedPreferences? _prefs;

  /// The `config/push` read in flight, shared by every caller meanwhile.
  Future<Uri?>? _reading;

  /// When a read of `config/push` last failed in this process.
  DateTime? _failedAt;

  /// When the last poke went out.
  DateTime? _sentAt;

  /// The pokes held for the end of the minute, by pair — urgent when any
  /// merged into one was — and the timer that sends them.
  final Map<String, bool> _held = {};
  Timer? _holding;

  /// [readConfig] reads `config/push`'s relay; [idToken] a fresh Firebase
  /// ID token for the signed-in account. [prefs] is resolved once, in the
  /// background — the install's preferences are loaded long before any run.
  HttpPushRelay({
    required Future<SharedPreferences> prefs,
    required Future<String?> Function() readConfig,
    required Future<String?> Function() idToken,
    PushPost post = postJson,
    DateTime Function() clock = DateTime.now,
    Timer Function(Duration, void Function()) timer = Timer.new,
  }) : _readConfig = readConfig,
       _idToken = idToken,
       _post = post,
       _clock = clock,
       _timer = timer {
    prefs.then((loaded) => _prefs = loaded).ignore();
  }

  /// The relay [raw] names, if it is one this app sends to: `https` with a
  /// host, its trailing slash dropped. Anything else is no relay — an ID
  /// token never leaves over a clear link.
  @visibleForTesting
  static Uri? parseRelay(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path);
  }

  @override
  Uri? get address => parseRelay(_prefs?.getString(SettingsKeys.pushRelayUrl));

  @override
  Future<Uri?> refresh() =>
      _reading ??= _refresh().whenComplete(() => _reading = null);

  Future<Uri?> _refresh() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final now = _clock();
    final readAt = prefs.getInt(SettingsKeys.pushRelayReadAt);
    if (readAt != null) {
      final since = now.difference(
        DateTime.fromMillisecondsSinceEpoch(readAt),
      );
      if (!since.isNegative && since < kPushRelayReadInterval) return address;
    }
    final failedAt = _failedAt;
    if (failedAt != null &&
        now.difference(failedAt) < kPushRelayRetryAfterFailure) {
      return address;
    }
    final String? raw;
    try {
      raw = await _readConfig();
    } catch (e) {
      _failedAt = now;
      debugPrint('[PushRelay] config not read: $e');
      return address;
    }
    final relay = parseRelay(raw);
    if (raw != null && relay == null) {
      debugPrint('[PushRelay] config names no https relay; none kept');
    }
    if (relay == null) {
      await prefs.remove(SettingsKeys.pushRelayUrl);
    } else {
      await prefs.setString(SettingsKeys.pushRelayUrl, '$relay');
    }
    await prefs.setInt(SettingsKeys.pushRelayReadAt, now.millisecondsSinceEpoch);
    _failedAt = null;
    return relay;
  }

  @override
  void poke(String pairId, {required bool urgent}) {
    if (address == null) return;
    if (_holding != null) {
      _held[pairId] = urgent || (_held[pairId] ?? false);
      return;
    }
    final now = _clock();
    final sentAt = _sentAt;
    final since = sentAt == null ? null : now.difference(sentAt);
    if (since == null || since.isNegative || since >= kPushPokeSpacing) {
      _sentAt = now;
      unawaited(_send(pairId, urgent: urgent));
      return;
    }
    _held[pairId] = urgent;
    _holding = _timer(kPushPokeSpacing - since, flush);
  }

  @override
  void flush() {
    _holding?.cancel();
    _holding = null;
    if (_held.isEmpty) return;
    final held = {..._held};
    _held.clear();
    _sentAt = _clock();
    for (final MapEntry(key: pair, value: urgent) in held.entries) {
      unawaited(_send(pair, urgent: urgent));
    }
  }

  /// Drops what waits for the minute's end, unsent.
  void dispose() {
    _holding?.cancel();
    _holding = null;
    _held.clear();
  }

  Future<void> _send(String pairId, {required bool urgent}) async {
    final relay = address;
    if (relay == null) return;
    try {
      final status = await () async {
        final token = await _idToken();
        if (token == null) return null;
        return _post(
          relay.replace(path: '${relay.path}/poke'),
          bearer: token,
          body: jsonEncode({'pair': pairId, 'urgent': urgent}),
          deadline: kPushPokeDeadline,
        );
      }().timeout(kPushPokeDeadline);
      if (status != null && status != HttpStatus.noContent) {
        debugPrint('[PushRelay] poke answered $status');
      }
    } catch (e) {
      debugPrint('[PushRelay] poke failed: ${e.runtimeType}');
    }
  }

  /// [PushPost] over a fresh [HttpClient]: no redirect followed, the client
  /// closed whatever the outcome.
  static Future<int> postJson(
    Uri url, {
    required String bearer,
    required String body,
    required Duration deadline,
  }) async {
    final client = HttpClient()..connectionTimeout = deadline;
    try {
      return await () async {
        final request = await client.postUrl(url);
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer $bearer')
          ..contentType = ContentType.json;
        request.write(body);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }().timeout(deadline);
    } finally {
      client.close(force: true);
    }
  }
}
