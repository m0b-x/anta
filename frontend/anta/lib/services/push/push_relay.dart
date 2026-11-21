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
  /// screen, and its process may not live to see the timer, or the account
  /// or a pair is about to go and its token or its document with it. Done
  /// when those sends are, and the ones already under way, each bounded by
  /// its deadline.
  Future<void> flush();
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
  Future<void> flush() async {}
}

/// What the relay answered a poke: its status code and its `Retry-After`
/// header as sent, if any.
typedef PushAnswer = ({int status, String? retryAfter});

/// One POST to the relay: its answer, or a throw when none came within
/// [deadline].
typedef PushPost =
    Future<PushAnswer> Function(
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
  final String? Function() _signedIn;
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

  /// The pokes held for the end of the minute, by pair and the account
  /// signed in when each was asked — urgent when any merged into one was —
  /// and the timer that sends them.
  final Map<({String pair, String? uid}), bool> _held = {};
  Timer? _holding;

  /// The pokes sent at once and not yet answered, which a [flush] waits for
  /// too.
  final Set<Future<void>> _sending = {};

  /// The pairs the relay refused (403) as the account asked under — not a
  /// member, or the pair is gone — and until when each is not poked again
  /// ([kPushRefusalHolds]). Not for the life of the process: the relay's
  /// own refusal is stable, but an edge in front of it can answer one too.
  final Map<({String pair, String? uid}), DateTime> _refusedUntil = {};

  /// Until when the relay asked each account to wait (429, 503): it counts
  /// by caller, so one account's pause is not another's.
  final Map<String, DateTime> _pausedUntil = {};

  /// Whether [until] still lies ahead of now by no more than [bound]. One
  /// further off than it could have been set was set by a clock that has
  /// gone back since, and is over.
  bool _stillHolds(DateTime? until, Duration bound) {
    if (until == null) return false;
    final left = until.difference(_clock());
    return left > Duration.zero && left <= bound;
  }

  /// [readConfig] reads `config/push`'s relay; [idToken] a fresh Firebase
  /// ID token for the signed-in account, and [signedIn] that account's uid.
  /// [prefs] is resolved once, in the background — the install's
  /// preferences are loaded long before any run.
  HttpPushRelay({
    required Future<SharedPreferences> prefs,
    required Future<String?> Function() readConfig,
    required Future<String?> Function() idToken,
    required String? Function() signedIn,
    PushPost post = postJson,
    DateTime Function() clock = DateTime.now,
    Timer Function(Duration, void Function()) timer = Timer.new,
  }) : _readConfig = readConfig,
       _idToken = idToken,
       _signedIn = signedIn,
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
      final since = now.difference(DateTime.fromMillisecondsSinceEpoch(readAt));
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
    await prefs.setInt(
      SettingsKeys.pushRelayReadAt,
      now.millisecondsSinceEpoch,
    );
    _failedAt = null;
    return relay;
  }

  @override
  void poke(String pairId, {required bool urgent}) {
    if (address == null) return;
    final key = (pair: pairId, uid: _signedIn());
    if (_holding != null) {
      _held[key] = urgent || (_held[key] ?? false);
      return;
    }
    final now = _clock();
    final sentAt = _sentAt;
    final since = sentAt == null ? null : now.difference(sentAt);
    if (since == null || since.isNegative || since >= kPushPokeSpacing) {
      _sentAt = now;
      final sending = _send(key.pair, urgent: urgent, askedAs: key.uid);
      _sending.add(sending);
      unawaited(sending.whenComplete(() => _sending.remove(sending)));
      return;
    }
    _held[key] = urgent;
    _holding = _timer(kPushPokeSpacing - since, flush);
  }

  @override
  Future<void> flush() async {
    _holding?.cancel();
    _holding = null;
    final held = {..._held};
    _held.clear();
    if (held.isNotEmpty) _sentAt = _clock();
    await Future.wait([
      ..._sending,
      for (final MapEntry(key: (:pair, :uid), value: urgent) in held.entries)
        _send(pair, urgent: urgent, askedAs: uid),
    ]);
  }

  /// Drops what waits for the minute's end, unsent.
  void dispose() {
    _holding?.cancel();
    _holding = null;
    _held.clear();
  }

  /// Sends as [askedAs] or not at all: a pair asked for under one account
  /// never goes out under another's token, and the line says why it did
  /// not.
  Future<void> _send(
    String pairId, {
    required bool urgent,
    required String? askedAs,
  }) async {
    final relay = address;
    if (relay == null) return;
    final signedIn = _signedIn();
    if (signedIn == null) {
      debugPrint('[PushRelay] poke dropped: nobody signed in');
      return;
    }
    if (signedIn != askedAs) {
      debugPrint('[PushRelay] poke dropped: asked under another account');
      return;
    }
    final key = (pair: pairId, uid: askedAs);
    if (_stillHolds(_refusedUntil[key], kPushRefusalHolds)) return;
    _refusedUntil.remove(key);
    if (_stillHolds(_pausedUntil[signedIn], kPushRetryAfterCeiling)) {
      debugPrint('[PushRelay] poke dropped: the relay asked to wait');
      return;
    }
    _pausedUntil.remove(signedIn);
    try {
      final answer = await () async {
        final token = await _idToken();
        if (token == null) {
          debugPrint('[PushRelay] poke dropped: no ID token');
          return null;
        }
        return _post(
          relay.replace(path: '${relay.path}/poke'),
          bearer: token,
          body: jsonEncode({'pair': pairId, 'urgent': urgent}),
          deadline: kPushPokeDeadline,
        );
      }().timeout(kPushPokeDeadline);
      if (answer != null) _answered(key, answer);
    } catch (e) {
      debugPrint('[PushRelay] poke failed: ${e.runtimeType}');
    }
  }

  /// What an answer changes for the pokes after it; nothing is sent again.
  void _answered(({String pair, String? uid}) key, PushAnswer answer) {
    switch (answer.status) {
      case HttpStatus.noContent:
        return;
      case HttpStatus.forbidden:
        _refusedUntil[key] = _clock().add(kPushRefusalHolds);
        debugPrint(
          '[PushRelay] poke refused: that pair is not poked again for '
          '${kPushRefusalHolds.inMinutes} min',
        );
      case HttpStatus.tooManyRequests || HttpStatus.serviceUnavailable:
        final uid = key.uid;
        if (_retryAfter(answer.retryAfter) case final wait? when uid != null) {
          _pausedUntil[uid] = _clock().add(wait);
        }
        debugPrint('[PushRelay] poke answered ${answer.status}');
      default:
        debugPrint('[PushRelay] poke answered ${answer.status}');
    }
  }

  /// A `Retry-After` in seconds or as an HTTP date, at most
  /// [kPushRetryAfterCeiling]; null when absent, past or unreadable.
  Duration? _retryAfter(String? raw) {
    if (raw == null) return null;
    final Duration wait;
    if (int.tryParse(raw.trim()) case final seconds?) {
      wait = Duration(seconds: seconds);
    } else {
      try {
        wait = HttpDate.parse(raw).difference(_clock());
      } on HttpException {
        return null;
      }
    }
    if (wait.isNegative) return null;
    return wait > kPushRetryAfterCeiling ? kPushRetryAfterCeiling : wait;
  }

  /// [PushPost] over a fresh [HttpClient]: no redirect followed, the client
  /// closed whatever the outcome.
  static Future<PushAnswer> postJson(
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
        return (
          status: response.statusCode,
          retryAfter: response.headers.value(HttpHeaders.retryAfterHeader),
        );
      }().timeout(deadline);
    } finally {
      client.close(force: true);
    }
  }
}
