@Tags(['firestore-rules'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Security rules are the only part of this feature with no local safety net:
/// a mistake is silent, remote, and affects every install at once. Two
/// CRITICAL holes were found here by review alone, so these run the real rules
/// engine in the Firestore emulator rather than reasoning about them.
///
///   firebase emulators:start --only firestore --project demo-anta \
///     --config firebase.firestore.json
///   flutter test --tags firestore-rules --run-skipped
const String _project = 'demo-anta';
const String _origin = 'http://127.0.0.1:8080';
const String _base =
    '$_origin/v1/projects/$_project/databases/(default)/documents';
const String _docRoot = 'projects/$_project/databases/(default)/documents';

const String uidA = 'uid-a';
const String uidB = 'uid-b';
const String uidC = 'uid-c';
const String code = 'ABCD2345';

final HttpClient _client = HttpClient();

String _b64url(String raw) =>
    base64Url.encode(utf8.encode(raw)).replaceAll('=', '');

/// Unsigned on purpose: the emulator trusts the payload without checking a
/// signature, which is what makes rules testable with no real credentials.
String _token(String uid) {
  const header = '{"alg":"none","typ":"JWT"}';
  final payload =
      '{"iss":"https://securetoken.google.com/$_project","aud":"$_project",'
      '"sub":"$uid","user_id":"$uid","iat":1700000000,"auth_time":1700000000,'
      '"exp":9999999999,'
      '"firebase":{"identities":{},"sign_in_provider":"custom"}}';
  return '${_b64url(header)}.${_b64url(payload)}.';
}

/// 200 = allowed, 403 = denied by rules, 404 = allowed but absent. That last
/// distinction is an assertion target, not an accident: a mistyped invite code
/// has to read as "not found" or the user is told they lack permission.
Future<({int status, String body})> _call(
  String method,
  String url, {
  String? uid,
  bool admin = false,
  Object? body,
}) async {
  final request = await _client.openUrl(method, Uri.parse(url));
  if (admin) {
    request.headers.set('Authorization', 'Bearer owner');
  } else if (uid != null) {
    request.headers.set('Authorization', 'Bearer ${_token(uid)}');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  return (status: response.statusCode, body: text);
}

Future<int> _commit(
  List<Map<String, Object?>> writes, {
  String? uid,
  bool admin = false,
}) async => (await _call(
  'POST',
  '$_base:commit',
  uid: uid,
  admin: admin,
  body: {'writes': writes},
)).status;

Future<int> _get(String path, {String? uid}) async =>
    (await _call('GET', '$_base/$path', uid: uid)).status;

Future<void> _clear() => _call(
  'DELETE',
  '$_origin/emulator/v1/projects/$_project/databases/(default)/documents',
);

Map<String, Object?> _s(String v) => {'stringValue': v};
Map<String, Object?> _bool(bool v) => {'booleanValue': v};
const Map<String, Object?> _nul = {'nullValue': null};

Map<String, Object?> _ts(DateTime v) => {
  'timestampValue': '${v.toUtc().toIso8601String().split('.').first}Z',
};

Map<String, Object?> _arr(List<String> v) => {
  'arrayValue': {
    'values': [for (final e in v) _s(e)],
  },
};

Map<String, Object?> _map(Map<String, Object?> fields) => {
  'mapValue': {'fields': fields},
};

Map<String, Object?> _profile({String? name, Map<String, Object?>? extra}) =>
    _map({
      'displayName': name == null ? _nul : _s(name),
      'photoUrl': _nul,
      ...?extra,
    });

Map<String, Object?> _consent(bool allow) =>
    _map({'allowPartnerEdit': _bool(allow)});

Map<String, Object?> _pairFields({
  List<String> members = const [uidA, uidB],
  String status = 'active',
  String inviteCode = code,
  Map<String, Object?>? profiles,
  Map<String, Object?>? permissions,
  Map<String, Object?> extra = const {},
}) => {
  'members': _arr(members),
  'status': _s(status),
  'inviteCode': _s(inviteCode),
  'profiles': _map(profiles ?? {for (final m in members) m: _profile()}),
  'permissions': _map(
    permissions ?? {for (final m in members) m: _consent(false)},
  ),
  ...extra,
};

Map<String, Object?> _createPair(
  String id,
  Map<String, Object?> fields, {
  List<String> serverTimeFields = const ['createdAt'],
}) => {
  'update': {'name': '$_docRoot/pairs/$id', 'fields': fields},
  'updateTransforms': [
    for (final f in serverTimeFields)
      {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
  ],
  'currentDocument': {'exists': false},
};

/// The mask is load-bearing: a REST `update` without one REPLACES the whole
/// document, which drops `members` and `createdAt` and is correctly refused by
/// the immutability clauses. Only a masked write is the partial update the app
/// actually performs.
Map<String, Object?> _updatePair(
  String id,
  Map<String, Object?> fields, {
  List<String> serverTimeFields = const [],
}) => {
  'update': {'name': '$_docRoot/pairs/$id', 'fields': fields},
  'updateMask': {'fieldPaths': fields.keys.toList()},
  'updateTransforms': [
    for (final f in serverTimeFields)
      {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
  ],
  'currentDocument': {'exists': true},
};

Map<String, Object?> _createInvite(
  String inviteCode, {
  required String creatorUid,
  Duration lifetime = const Duration(minutes: 10),
  Map<String, Object?> extra = const {},
}) => {
  'update': {
    'name': '$_docRoot/invites/$inviteCode',
    'fields': {
      'creatorUid': _s(creatorUid),
      'expiresAt': _ts(DateTime.now().toUtc().add(lifetime)),
      ...extra,
    },
  },
  'updateTransforms': [
    {'fieldPath': 'createdAt', 'setToServerValue': 'REQUEST_TIME'},
  ],
  'currentDocument': {'exists': false},
};

/// Seeds through the emulator's admin bypass, so a fixture the rules would
/// refuse to create (an expired or already-claimed invite) can still be set up.
Future<void> _seedInvite(
  String inviteCode, {
  required String creatorUid,
  Duration lifetime = const Duration(minutes: 10),
  String? pairId,
  String? redeemedBy,
}) async {
  final status = await _commit([
    {
      'update': {
        'name': '$_docRoot/invites/$inviteCode',
        'fields': {
          'creatorUid': _s(creatorUid),
          'createdAt': _ts(DateTime.now().toUtc()),
          'expiresAt': _ts(DateTime.now().toUtc().add(lifetime)),
          if (pairId != null) 'pairId': _s(pairId),
          if (redeemedBy != null) 'redeemedBy': _s(redeemedBy),
        },
      },
    },
  ], admin: true);
  expect(status, 200, reason: 'admin seed of invite $inviteCode failed');
}

Future<void> _seedPair(
  String id, {
  List<String> members = const [uidA, uidB],
  String status = 'active',
  Map<String, Object?>? permissions,
}) async {
  final result = await _commit([
    {
      'update': {
        'name': '$_docRoot/pairs/$id',
        'fields': {
          ..._pairFields(
            members: members,
            status: status,
            permissions: permissions,
          ),
          'createdAt': _ts(DateTime.now().toUtc()),
        },
      },
    },
  ], admin: true);
  expect(result, 200, reason: 'admin seed of pair $id failed');
}

void main() {
  setUpAll(() async {
    try {
      final probe = await _call('GET', '$_origin/');
      expect(probe.status, 200);
    } on SocketException {
      fail(
        'Firestore emulator not reachable on $_origin.\n'
        'Start it with:\n'
        '  firebase emulators:start --only firestore --project $_project '
        '--config firebase.firestore.json',
      );
    }
  });

  setUp(_clear);

  group('pairs create — consent proof', () {
    test('a pair citing no existing invite is refused', () async {
      expect(
        await _commit([_createPair('p1', _pairFields())], uid: uidA),
        403,
        reason:
            'uid is printed on the Sharing page; without an invite check '
            'anyone knowing it could force a link',
      );
    });

    test(
      'a pair citing an invite the caller minted themselves is refused',
      () async {
        await _seedInvite(code, creatorUid: uidA);
        expect(
          await _commit([_createPair('p1', _pairFields())], uid: uidA),
          403,
        );
      },
    );

    test('a pair citing an expired invite is refused', () async {
      await _seedInvite(
        code,
        creatorUid: uidB,
        lifetime: const Duration(minutes: -5),
      );
      expect(await _commit([_createPair('p1', _pairFields())], uid: uidA), 403);
    });

    test('a pair citing an already-claimed invite is refused', () async {
      await _seedInvite(
        code,
        creatorUid: uidB,
        pairId: 'other',
        redeemedBy: uidC,
      );
      expect(await _commit([_createPair('p1', _pairFields())], uid: uidA), 403);
    });

    test('a pair citing the partner live invite is allowed', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(await _commit([_createPair('p1', _pairFields())], uid: uidA), 200);
    });

    test('a membership that is not exactly two accounts is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          _createPair('p1', _pairFields(members: const [uidA])),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          _createPair('p2', _pairFields(members: const [uidA, uidB, uidC])),
        ], uid: uidA),
        403,
      );
    });

    test('a caller outside the membership is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(await _commit([_createPair('p1', _pairFields())], uid: uidC), 403);
    });

    test('a pair born already ended is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          _createPair('p1', _pairFields(status: 'ended')),
        ], uid: uidA),
        403,
      );
    });

    test('consent cannot be pre-granted at creation', () async {
      await _seedInvite(code, creatorUid: uidB);
      // The redeemer writes both entries, so an unvalidated `permissions`
      // would let it grant itself permanent write access to the other
      // account's data with no revocation path.
      expect(
        await _commit([
          _createPair(
            'p1',
            _pairFields(
              permissions: {uidA: _consent(false), uidB: _consent(true)},
            ),
          ),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          _createPair(
            'p2',
            _pairFields(
              permissions: {uidA: _consent(true), uidB: _consent(false)},
            ),
          ),
        ], uid: uidA),
        403,
      );
    });

    test('permissions keyed to a non-member are refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          _createPair(
            'p1',
            _pairFields(
              permissions: {uidA: _consent(false), uidC: _consent(false)},
            ),
          ),
        ], uid: uidA),
        403,
      );
    });

    test('an unknown top-level field is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          _createPair('p1', _pairFields(extra: {'payload': _s('x' * 100)})),
        ], uid: uidA),
        403,
      );
    });

    test('a profile carrying an extra field is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          _createPair(
            'p1',
            _pairFields(
              profiles: {
                uidA: _profile(extra: {'note': _s('smuggled')}),
                uidB: _profile(),
              },
            ),
          ),
        ], uid: uidA),
        403,
      );
    });

    test('an oversized display name is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          _createPair(
            'p1',
            _pairFields(
              profiles: {
                uidA: _profile(name: 'x' * 300),
                uidB: _profile(),
              },
            ),
          ),
        ], uid: uidA),
        403,
      );
    });

    test('an unauthenticated caller is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(await _commit([_createPair('p1', _pairFields())]), 403);
    });
  });

  group('pairs read', () {
    test('a member may read and a stranger may not', () async {
      await _seedPair('p1');
      expect(await _get('pairs/p1', uid: uidA), 200);
      expect(await _get('pairs/p1', uid: uidB), 200);
      expect(await _get('pairs/p1', uid: uidC), 403);
      expect(await _get('pairs/p1'), 403);
    });

    test(
      'the reconciliation query returns only the caller own pairs',
      () async {
        await _seedPair('mine', members: const [uidA, uidB]);
        await _seedPair('theirs', members: const [uidB, uidC]);

        final result = await _call(
          'POST',
          '$_base:runQuery',
          uid: uidA,
          body: {
            'structuredQuery': {
              'from': [
                {'collectionId': 'pairs'},
              ],
              'where': {
                'compositeFilter': {
                  'op': 'AND',
                  'filters': [
                    {
                      'fieldFilter': {
                        'field': {'fieldPath': 'members'},
                        'op': 'ARRAY_CONTAINS',
                        'value': _s(uidA),
                      },
                    },
                    {
                      'fieldFilter': {
                        'field': {'fieldPath': 'status'},
                        'op': 'EQUAL',
                        'value': _s('active'),
                      },
                    },
                  ],
                },
              },
            },
          },
        );

        expect(result.status, 200);
        expect(result.body, contains('pairs/mine'));
        expect(result.body, isNot(contains('pairs/theirs')));
      },
    );
  });

  group('pairs update and delete', () {
    test('a member may tombstone the pair', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _updatePair(
            'p1',
            {'status': _s('ended'), 'endedBy': _s(uidA)},
            serverTimeFields: const ['endedAt'],
          ),
        ], uid: uidA),
        200,
      );
    });

    test('a member cannot attribute the ending to the partner', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _updatePair(
            'p1',
            {'status': _s('ended'), 'endedBy': _s(uidB)},
            serverTimeFields: const ['endedAt'],
          ),
        ], uid: uidA),
        403,
      );
    });

    test('membership can never change', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _updatePair('p1', {
            'members': _arr(const [uidA, uidC]),
          }),
        ], uid: uidA),
        403,
        reason: 'members is the ACL; a mutable one is a privilege escalation',
      );
    });

    test('an ended pair can never be revived', () async {
      await _seedPair('p1', status: 'ended');
      expect(
        await _commit([
          _updatePair('p1', {'status': _s('active')}),
        ], uid: uidA),
        403,
      );
    });

    test('a member may rewrite only their own profile', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _updatePair('p1', {
            'profiles': _map({uidA: _profile(name: 'Alex'), uidB: _profile()}),
          }),
        ], uid: uidA),
        200,
      );
      expect(
        await _commit([
          _updatePair('p1', {
            'profiles': _map({
              uidA: _profile(name: 'Alex'),
              uidB: _profile(name: 'forged'),
            }),
          }),
        ], uid: uidA),
        403,
      );
    });

    test('a member may grant only their own consent', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _updatePair('p1', {
            'permissions': _map({uidA: _consent(true), uidB: _consent(false)}),
          }),
        ], uid: uidA),
        200,
      );
      expect(
        await _commit([
          _updatePair('p1', {
            'permissions': _map({uidA: _consent(true), uidB: _consent(true)}),
          }),
        ], uid: uidA),
        403,
        reason: 'granting yourself write access to the partner data',
      );
    });

    test('a stranger cannot update the pair', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _updatePair('p1', {'status': _s('ended'), 'endedBy': _s(uidC)}),
        ], uid: uidC),
        403,
      );
    });

    test('nobody may delete a pair, member included', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          {'delete': '$_docRoot/pairs/p1'},
        ], uid: uidA),
        403,
        reason: 'the tombstone model depends on the document surviving',
      );
    });
  });

  group('invites', () {
    test(
      'a code that does not exist reads as absent, not as forbidden',
      () async {
        expect(
          await _get('invites/ZZZZ9999', uid: uidC),
          404,
          reason:
              'a one-character typo is the most common failure in the flow and '
              'must not be reported as a permission problem',
        );
      },
    );

    test(
      'a live invite is readable by a stranger, an expired one is not',
      () async {
        await _seedInvite(code, creatorUid: uidB);
        await _seedInvite(
          'EXPIRED2',
          creatorUid: uidB,
          lifetime: const Duration(minutes: -1),
        );
        expect(await _get('invites/$code', uid: uidC), 200);
        expect(await _get('invites/EXPIRED2', uid: uidC), 403);
        expect(await _get('invites/$code'), 403);
      },
    );

    test('the collection cannot be enumerated', () async {
      await _seedInvite(code, creatorUid: uidB);
      final result = await _call(
        'POST',
        '$_base:runQuery',
        uid: uidC,
        body: {
          'structuredQuery': {
            'from': [
              {'collectionId': 'invites'},
            ],
          },
        },
      );
      expect(
        result.status,
        403,
        reason:
            'enumerable codes would make the whole code space brute-forceable',
      );
    });

    test('an invite must be minted by its own creator', () async {
      expect(
        await _commit([_createInvite(code, creatorUid: uidB)], uid: uidA),
        403,
      );
      expect(
        await _commit([_createInvite(code, creatorUid: uidA)], uid: uidA),
        200,
      );
    });

    test('the lifetime ceiling is enforced against server time', () async {
      expect(
        await _commit([
          _createInvite(
            code,
            creatorUid: uidA,
            lifetime: const Duration(hours: 24),
          ),
        ], uid: uidA),
        403,
        reason: 'a skewed device clock must not mint a year-long invite',
      );
      expect(
        await _commit([
          _createInvite(
            'PAST2345',
            creatorUid: uidA,
            lifetime: const Duration(minutes: -1),
          ),
        ], uid: uidA),
        403,
      );
    });

    test('an invite carrying an unexpected field is refused', () async {
      expect(
        await _commit([
          _createInvite(
            code,
            creatorUid: uidA,
            extra: {'pairId': _s('preclaimed')},
          ),
        ], uid: uidA),
        403,
      );
    });

    test('only a non-creator may claim a live invite', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/invites/$code',
              'fields': {'pairId': _s('p1'), 'redeemedBy': _s(uidB)},
            },
            'updateMask': {
              'fieldPaths': ['pairId', 'redeemedBy'],
            },
          },
        ], uid: uidB),
        403,
        reason: 'the creator claiming its own invite is a self-pair',
      );
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/invites/$code',
              'fields': {'pairId': _s('p1'), 'redeemedBy': _s(uidA)},
            },
            'updateMask': {
              'fieldPaths': ['pairId', 'redeemedBy'],
            },
          },
        ], uid: uidA),
        200,
      );
    });

    test('a claim cannot be forged for someone else or left empty', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/invites/$code',
              'fields': {'pairId': _s('p1'), 'redeemedBy': _s(uidC)},
            },
            'updateMask': {
              'fieldPaths': ['pairId', 'redeemedBy'],
            },
          },
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/invites/$code',
              'fields': {'pairId': _s(''), 'redeemedBy': _s(uidA)},
            },
            'updateMask': {
              'fieldPaths': ['pairId', 'redeemedBy'],
            },
          },
        ], uid: uidA),
        403,
      );
    });

    test('an already-claimed invite cannot be reclaimed', () async {
      await _seedInvite(code, creatorUid: uidB, pairId: 'p1', redeemedBy: uidA);
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/invites/$code',
              'fields': {'pairId': _s('p2'), 'redeemedBy': _s(uidC)},
            },
            'updateMask': {
              'fieldPaths': ['pairId', 'redeemedBy'],
            },
          },
        ], uid: uidC),
        403,
      );
    });

    test('only the creator may cancel an invite', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([
          {'delete': '$_docRoot/invites/$code'},
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          {'delete': '$_docRoot/invites/$code'},
        ], uid: uidB),
        200,
      );
    });
  });
}
