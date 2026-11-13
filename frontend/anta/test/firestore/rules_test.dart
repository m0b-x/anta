@Tags(['firestore-rules'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/content_chunks_binding.dart';

/// Security rules are the only part of this feature with no local safety net:
/// a mistake is silent, remote, and affects every install at once. Two
/// CRITICAL holes were found here by review alone, so these run the real rules
/// engine in the Firestore emulator rather than reasoning about them.
///
///   firebase emulators:start --only firestore \
///     --project alexs-note-tracking-app --config firebase.emulators.json
///   flutter test --tags firestore-rules --run-skipped
///
/// The project id is the app's own: on Android the google-services plugin
/// creates the native default app, so a QA build's traffic arrives under
/// `alexs-note-tracking-app` and rules judged under another id would say
/// nothing about the device pass (record cloud-sync-phase-02 §3.8).
const String _project = 'alexs-note-tracking-app';
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

/// A pair created as the app creates one: its id is [inviteCode], then `_`
/// and [nonce] (`PairingGateway.pairIdFor`), which the rules hold a new pair
/// to. [id] names the document outright, for a pair the rules must refuse
/// by its name.
Map<String, Object?> _createPair(
  String nonce,
  Map<String, Object?> fields, {
  List<String> serverTimeFields = const ['createdAt'],
  String inviteCode = code,
  String? id,
}) => {
  'update': {
    'name': '$_docRoot/pairs/${id ?? '${inviteCode}_$nonce'}',
    'fields': fields,
  },
  'updateTransforms': [
    for (final f in serverTimeFields)
      {'fieldPath': f, 'setToServerValue': 'REQUEST_TIME'},
  ],
  'currentDocument': {'exists': false},
};

/// The claim of [inviteCode] for the pair [pairId], as its redeemer [by]
/// stamps it.
Map<String, Object?> _claimInvite(
  String pairId, {
  required String by,
  String inviteCode = code,
}) => {
  'update': {
    'name': '$_docRoot/invites/$inviteCode',
    'fields': {'pairId': _s(pairId), 'redeemedBy': _s(by)},
  },
  'updateMask': {
    'fieldPaths': ['pairId', 'redeemedBy'],
  },
};

/// A redemption as the app commits one (`PairingGateway.createPair`): the
/// pair and the claim of its invite by [by], in one write — the rules hold
/// each to the other.
List<Map<String, Object?>> _redeem(
  String nonce,
  Map<String, Object?> fields, {
  required String by,
  String inviteCode = code,
  String? id,
}) => [
  _createPair(nonce, fields, inviteCode: inviteCode, id: id),
  _claimInvite(id ?? '${inviteCode}_$nonce', by: by, inviteCode: inviteCode),
];

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

/// The invites whose [field] is [value] — the one listing the rules answer,
/// and only for the caller's own uid.
Future<({int status, String body})> _queryInvites(
  String field,
  String value, {
  required String? uid,
}) => _call(
  'POST',
  '$_base:runQuery',
  uid: uid,
  body: {
    'structuredQuery': {
      'from': [
        {'collectionId': 'invites'},
      ],
      'where': {
        'fieldFilter': {
          'field': {'fieldPath': field},
          'op': 'EQUAL',
          'value': _s(value),
        },
      },
    },
  },
);

Future<void> _seedPair(
  String id, {
  List<String> members = const [uidA, uidB],
  String status = 'active',
  Map<String, Object?>? permissions,
  Map<String, Object?> extra = const {},
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
            extra: extra,
          ),
          'createdAt': _ts(DateTime.now().toUtc()),
        },
      },
    },
  ], admin: true);
  expect(result, 200, reason: 'admin seed of pair $id failed');
}

// The pair's `push` field (docs/cloud-shared-freshness.md §7).

/// A device entry as the registry writes one; [at] a client time instead of
/// the server's, [extra] fields beside the three.
Map<String, Object?> _device({
  String id = 'fid-1',
  String kind = 'fid',
  DateTime? at,
  Map<String, Object?> extra = const {},
}) => _map({
  'id': _s(id),
  'kind': _s(kind),
  'at': _ts(at ?? DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
  ...extra,
});

/// `push.<owner>` as one masked write of [devices] by [owner]'s map — null
/// deletes it — the way a field-path update lands; [extraFields] are written
/// beside it in the same mask.
Map<String, Object?> _writePush(
  String id,
  String owner,
  Map<String, Object?>? devices, {
  Map<String, Object?> extraFields = const {},
}) => {
  'update': {
    'name': '$_docRoot/pairs/$id',
    'fields': {
      if (devices != null) 'push': _map({owner: _map(devices)}),
      ...extraFields,
    },
  },
  'updateMask': {
    'fieldPaths': ['push.`$owner`', ...extraFields.keys],
  },
  'currentDocument': {'exists': true},
};

// Phase 02 — one account's own spaces (`users/{owner}/spaces`, §3.7).

Map<String, Object?> _int(int v) => {'integerValue': '$v'};

Map<String, Object?> _serverTime(String path) => {
  'fieldPath': path,
  'setToServerValue': 'REQUEST_TIME',
};

String _spaceDoc(String owner, String spaceId) =>
    'users/$owner/spaces/$spaceId';

/// A space create as `createSpace` sends it: `createdAt` rides as a server
/// timestamp, which is the only form the rules accept.
Map<String, Object?> _createSpace(
  String owner,
  String spaceId, {
  String name = 'Main',
  int schema = 43,
  Map<String, Object?> extra = const {},
  bool serverCreatedAt = true,
}) => {
  'update': {
    'name': '$_docRoot/${_spaceDoc(owner, spaceId)}',
    'fields': {
      'name': _s(name),
      'createdBy': _s('A'),
      'schema': _int(schema),
      ...extra,
    },
  },
  if (serverCreatedAt) 'updateTransforms': [_serverTime('createdAt')],
};

/// The space document a push merges, as `set(…, merge: true)` sends it: the
/// mask carries the two plain fields, the stamps ride as transforms.
Map<String, Object?> _spaceMerge(
  String owner,
  String spaceId,
  int schema, {
  String table = 'folders',
}) => {
  'update': {
    'name': '$_docRoot/${_spaceDoc(owner, spaceId)}',
    'fields': {'lastWriter': _s('A'), 'schema': _int(schema)},
  },
  'updateMask': {
    'fieldPaths': ['lastWriter', 'schema'],
  },
  'updateTransforms': [
    _serverTime('touched.$table'),
    _serverTime('lastWriteAt'),
  ],
};

/// [length] bytes as a Firestore bytes value.
Map<String, Object?> _bytes(int length) => {
  'bytesValue': base64Encode(List.filled(length, 0x61)),
};

/// A chunk document's data as the gateway writes it (wire 46): the hash it
/// is keyed by, the gzip'd text under `gz` — [gz] replaces it — and the
/// text's length.
Map<String, Object?> _chunkData(String hash, {Map<String, Object?>? gz}) =>
    _map({
      ContentChunksBinding.hashKey: _s(hash),
      ContentChunksBinding.gzKey: gz ?? _bytes(1024),
      ContentChunksBinding.lengthKey: _int(1000),
    });

/// A row document as the gateway writes it — a `content_chunks` one in the
/// chunk shape — [fields] overrides some, [omit] drops some, [pushedAt]
/// writes a client time instead of the server's.
Map<String, Object?> _row(
  String owner,
  String spaceId,
  String table,
  String rowKey, {
  Map<String, Object?> fields = const {},
  List<String> omit = const [],
  DateTime? pushedAt,
}) {
  final envelope = <String, Object?>{
    'hlc': _s('000000000001:0000:A'),
    'deviceId': _s('A'),
    'version': _int(3),
    'op': _s('upsert'),
    'ownerId': _s(owner),
    'pushedBy': _s('A'),
    'data': table == 'content_chunks'
        ? _chunkData(rowKey)
        : _map({'id': _s(rowKey), 'name': _s('Training')}),
    ...fields,
  };
  for (final field in omit) {
    envelope.remove(field);
  }
  if (pushedAt != null) envelope['pushedAt'] = _ts(pushedAt);
  return {
    'update': {
      'name': '$_docRoot/${_spaceDoc(owner, spaceId)}/$table/$rowKey',
      'fields': envelope,
    },
    if (pushedAt == null) 'updateTransforms': [_serverTime('pushedAt')],
  };
}

/// A push as the gateway makes it: the rows and the space merge in one batch.
Future<int> _push(
  List<Map<String, Object?>> rows, {
  String owner = uidA,
  String spaceId = 's1',
  int schema = 43,
  String table = 'folders',
}) => _commit([
  ...rows,
  _spaceMerge(owner, spaceId, schema, table: table),
], uid: owner);

/// Seeds a space through the rules themselves — the create is allowed, and
/// going that way leaves `createdAt` the server timestamp the update clauses
/// compare against.
Future<void> _seedSpace({
  String owner = uidA,
  String spaceId = 's1',
  int schema = 43,
}) async {
  final status = await _commit([
    _createSpace(owner, spaceId, schema: schema),
  ], uid: owner);
  expect(status, 200, reason: 'seed of space $owner/$spaceId failed');
}

/// A mark as `markSpaceDeleted` sends it: an `update` — never a create —
/// whose only change is `deletedAt`, riding as a server timestamp unless
/// [clientTime] writes that instead.
Map<String, Object?> _mark(
  String owner,
  String spaceId, {
  DateTime? clientTime,
}) => {
  'update': {
    'name': '$_docRoot/${_spaceDoc(owner, spaceId)}',
    'fields': {if (clientTime != null) 'deletedAt': _ts(clientTime)},
  },
  'updateMask': {
    'fieldPaths': [if (clientTime != null) 'deletedAt'],
  },
  if (clientTime == null) 'updateTransforms': [_serverTime('deletedAt')],
  'currentDocument': {'exists': true},
};

Map<String, Object?> _delete(String path) => {'delete': '$_docRoot/$path'};

/// Seeds space `s1` of [uidA] with a row `folders/f1`, then marks it — both
/// through the rules.
Future<void> _seedMarked() async {
  await _seedSpace();
  expect(
    await _push([_row(uidA, 's1', 'folders', 'f1')]),
    200,
    reason: 'seed push failed',
  );
  expect(
    await _commit([_mark(uidA, 's1')], uid: uidA),
    200,
    reason: 'seed mark failed',
  );
}

// Sharing — a partner reading the rows an owner shared into their pair
// (docs/cloud-sharing-foundations.md §4).

/// The top-level fields a shared row's document carries beside its
/// envelope: the pair, and the wire version of the build that wrote it.
Map<String, Object?> _share(String pair, {int wire = 47}) => {
  'sharedPair': _s(pair),
  'wire': _int(wire),
};

/// A push whose space merge also says which pair the space's notes are
/// shared into, as the gateway sends it — [sharedPair] null takes the field
/// out, which is what every push of a database that shares nothing does.
Future<int> _pushSharing(
  List<Map<String, Object?>> rows, {
  required String? sharedPair,
  String owner = uidA,
  String spaceId = 's1',
  int schema = 47,
  String table = 'folders',
}) => _commit([
  ...rows,
  {
    'update': {
      'name': '$_docRoot/${_spaceDoc(owner, spaceId)}',
      'fields': {
        'lastWriter': _s('A'),
        'schema': _int(schema),
        if (sharedPair != null) 'sharedPair': _s(sharedPair),
      },
    },
    'updateMask': {
      'fieldPaths': ['lastWriter', 'schema', 'sharedPair'],
    },
    'updateTransforms': [
      _serverTime('touched.$table'),
      _serverTime('lastWriteAt'),
    ],
  },
], uid: owner);

/// The partner's query as the reader sends it: [table] across every space,
/// pinned to [pair] and — unless null — to [owner], in arrival order.
Map<String, Object?> _sharedQuery(
  String table, {
  required String? pair,
  required String? owner,
}) => {
  'from': [
    {'collectionId': table, 'allDescendants': true},
  ],
  'where': {
    'compositeFilter': {
      'op': 'AND',
      'filters': [
        if (pair != null)
          {
            'fieldFilter': {
              'field': {'fieldPath': 'sharedPair'},
              'op': 'EQUAL',
              'value': _s(pair),
            },
          },
        if (owner != null)
          {
            'fieldFilter': {
              'field': {'fieldPath': 'ownerId'},
              'op': 'EQUAL',
              'value': _s(owner),
            },
          },
      ],
    },
  },
  'orderBy': [
    {
      'field': {'fieldPath': 'pushedAt'},
    },
    {
      'field': {'fieldPath': '__name__'},
    },
  ],
};

/// Runs [query] as [uid]: the status, and the row keys it returned.
Future<({int status, List<String> keys})> _runShared(
  Map<String, Object?> query, {
  required String? uid,
}) async {
  final answer = await _call(
    'POST',
    '$_base:runQuery',
    uid: uid,
    body: {'structuredQuery': query},
  );
  return (
    status: answer.status,
    keys: [
      for (final match in RegExp(
        r'"name":\s*"[^"]*/([^/"]+)"',
      ).allMatches(answer.body))
        match.group(1)!,
    ],
  );
}

/// The count of [query] as [uid] — the aggregation the reader compares
/// with what it holds — or null when the answer carries none.
Future<({int status, int? count})> _countShared(
  Map<String, Object?> query, {
  required String? uid,
}) async {
  final answer = await _call(
    'POST',
    '$_base:runAggregationQuery',
    uid: uid,
    body: {
      'structuredAggregationQuery': {
        'structuredQuery': query,
        'aggregations': [
          {'alias': 'n', 'count': <String, Object?>{}},
        ],
      },
    },
  );
  final count = RegExp(
    r'"integerValue":\s*"(\d+)"',
  ).firstMatch(answer.body)?.group(1);
  return (
    status: answer.status,
    count: count == null ? null : int.parse(count),
  );
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
        '--config firebase.emulators.json',
      );
    }
  });

  setUp(_clear);

  group('pairs create — consent proof', () {
    test('a pair citing no existing invite is refused', () async {
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
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
          await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
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
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
        403,
      );
    });

    test('a pair citing an already-claimed invite is refused', () async {
      await _seedInvite(
        code,
        creatorUid: uidB,
        pairId: 'other',
        redeemedBy: uidC,
      );
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
        403,
      );
    });

    test('a pair citing the partner live invite is allowed', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
        200,
      );
    });

    test('a membership that is not exactly two accounts is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem('p1', _pairFields(members: const [uidA]), by: uidA),
          uid: uidA,
        ),
        403,
      );
      expect(
        await _commit(
          _redeem(
            'p2',
            _pairFields(members: const [uidA, uidB, uidC]),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('a caller outside the membership is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidC), uid: uidC),
        403,
      );
    });

    test('a pair born already ended is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem('p1', _pairFields(status: 'ended'), by: uidA),
          uid: uidA,
        ),
        403,
      );
    });

    test('a pair is refused without the claim of its invite in the same '
        'write, and with a claim that names another pair', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([_createPair('p1', _pairFields())], uid: uidA),
        403,
        reason: 'an unclaimed invite would let the same id be made again',
      );
      expect(
        await _commit([
          _createPair('p1', _pairFields()),
          _claimInvite('${code}_other', by: uidA),
        ], uid: uidA),
        403,
      );
      expect(await _get('pairs/${code}_p1', uid: uidA), 404);
    });

    test('a pair\'s id is made once: its invite is spent by the write that '
        'creates it, so ending and deleting the pair does not free the id — '
        'not inside the invite\'s life, nor once the spent invite is '
        'deleted', () async {
      await _seedInvite(code, creatorUid: uidB);
      final redemption = _redeem('p1', _pairFields(), by: uidA);
      expect(await _commit(redemption, uid: uidA), 200);
      expect(
        await _commit([
          _updatePair(
            '${code}_p1',
            {'status': _s('ended'), 'endedBy': _s(uidA)},
            serverTimeFields: const ['endedAt'],
          ),
        ], uid: uidA),
        200,
      );
      expect(await _commit([_delete('pairs/${code}_p1')], uid: uidA), 200);

      expect(await _commit(redemption, uid: uidA), 403);
      expect(await _commit([_createPair('p1', _pairFields())], uid: uidA), 403);

      expect(await _commit([_delete('invites/$code')], uid: uidA), 200);
      expect(await _commit(redemption, uid: uidA), 403);
    });

    test('consent cannot be pre-granted at creation', () async {
      await _seedInvite(code, creatorUid: uidB);
      // The redeemer writes both entries, so an unvalidated `permissions`
      // would let it grant itself permanent write access to the other
      // account's data with no revocation path.
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(
              permissions: {uidA: _consent(false), uidB: _consent(true)},
            ),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
      expect(
        await _commit(
          _redeem(
            'p2',
            _pairFields(
              permissions: {uidA: _consent(true), uidB: _consent(false)},
            ),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('permissions keyed to a non-member are refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(
              permissions: {uidA: _consent(false), uidC: _consent(false)},
            ),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('an unknown top-level field is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(extra: {'payload': _s('x' * 100)}),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('a profile carrying an extra field is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(
              profiles: {
                uidA: _profile(extra: {'note': _s('smuggled')}),
                uidB: _profile(),
              },
            ),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('an oversized display name is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(
              profiles: {
                uidA: _profile(name: 'x' * 300),
                uidB: _profile(),
              },
            ),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('an unauthenticated caller is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(await _commit(_redeem('p1', _pairFields(), by: uidA)), 403);
    });

    test('a pair whose id does not start with its invite\'s code is refused: '
        'an id cannot be chosen freely, so it cannot be one that was used '
        'before', () async {
      await _seedInvite(code, creatorUid: uidB);
      for (final id in ['p1', 'OTHER_p1', code, '${code}_', '${code}x_p1']) {
        expect(
          await _commit(
            _redeem('', _pairFields(), by: uidA, id: id),
            uid: uidA,
          ),
          403,
          reason: id,
        );
      }
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
        200,
      );
    });

    test('a former partner cannot bring an ended pair\'s id back with the '
        'same person: the id follows the other one\'s new invite', () async {
      // The pair that ended was made from `code`; uidA invites again, and
      // the code of that invite is new.
      const again = 'NEWCODE2';
      await _seedInvite(again, creatorUid: uidA);
      expect(
        await _commit(
          _redeem(
            '',
            _pairFields(inviteCode: again),
            by: uidB,
            inviteCode: again,
            id: '${code}_p1',
          ),
          uid: uidB,
        ),
        403,
      );
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(inviteCode: again),
            by: uidB,
            inviteCode: again,
          ),
          uid: uidB,
        ),
        200,
      );
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

    test('a pair that does not exist reads as absent, not as forbidden — '
        'a member has to tell a pair its partner removed from one that was '
        'never theirs', () async {
      expect(await _get('pairs/gone', uid: uidA), 404);
      expect(await _get('pairs/gone'), 403);
    });

    test('an account deletion\'s walk returns the caller\'s pairs, ended '
        'ones included, and nobody else\'s', () async {
      await _seedPair('live', members: const [uidA, uidB]);
      await _seedPair('over', members: const [uidA, uidC], status: 'ended');
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
              'fieldFilter': {
                'field': {'fieldPath': 'members'},
                'op': 'ARRAY_CONTAINS',
                'value': _s(uidA),
              },
            },
          },
        },
      );

      expect(result.status, 200);
      expect(result.body, contains('pairs/live'));
      expect(result.body, contains('pairs/over'));
      expect(result.body, isNot(contains('pairs/theirs')));
    });
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

    test('nobody may delete an active pair, member included', () async {
      await _seedPair('p1');
      expect(
        await _commit([_delete('pairs/p1')], uid: uidA),
        403,
        reason:
            'the partner learns of an ending from the tombstone: a pair '
            'must be ended before it can go',
      );
    });

    test('a member may delete an ended pair, as an account\'s deletion '
        'does; a stranger may not', () async {
      await _seedPair('p1', status: 'ended');
      expect(await _commit([_delete('pairs/p1')], uid: uidC), 403);
      expect(await _commit([_delete('pairs/p1')]), 403);
      expect(await _commit([_delete('pairs/p1')], uid: uidB), 200);
      expect(await _get('pairs/p1', uid: uidA), 404);
    });

    test('a pair already gone is deleted again without a refusal, so two '
        'account deletions walking the same pair never fail each other; '
        'signed out it still is refused', () async {
      await _seedPair('p1', status: 'ended');
      expect(await _commit([_delete('pairs/p1')], uid: uidA), 200);
      expect(await _commit([_delete('pairs/p1')], uid: uidB), 200);
      expect(await _commit([_delete('pairs/never')], uid: uidC), 200);
      expect(await _commit([_delete('pairs/p1')]), 403);
    });

    test('a member ends the pair and deletes it, in that order', () async {
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
      expect(await _commit([_delete('pairs/p1')], uid: uidA), 200);
    });
  });

  group('the pair\'s push addresses', () {
    test('a member writes their own device, at a past or the server time', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device()}),
        ], uid: uidA),
        200,
      );
      expect(
        await _commit([
          {
            ..._writePush('p1', uidA, {
              'd1': _device(),
              'd2': _device(id: 'fid-2'),
            }),
            'updateTransforms': [
              _serverTime('push.`$uidA`.d2.at'),
            ],
          },
        ], uid: uidA),
        200,
      );
    });

    test('nobody writes under the other member\'s uid', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush('p1', uidB, {'d1': _device()}),
        ], uid: uidA),
        403,
        reason: 'one member must never name the devices the relay wakes for '
            'the other',
      );
    });

    test('five devices are allowed, a sixth is refused', () async {
      await _seedPair('p1');
      Map<String, Object?> devices(int count) => {
        for (var i = 0; i < count; i++) 'd$i': _device(id: 'fid-$i'),
      };
      expect(
        await _commit([_writePush('p1', uidA, devices(5))], uid: uidA),
        200,
      );
      expect(
        await _commit([_writePush('p1', uidA, devices(6))], uid: uidA),
        403,
      );
    });

    test('a kind other than fid or token is refused', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(kind: 'token')}),
        ], uid: uidA),
        200,
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(kind: 'apns')}),
        ], uid: uidA),
        403,
      );
    });

    test('an id is a non-empty string of at most 4096', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(id: 'f' * 4096)}),
        ], uid: uidA),
        200,
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(id: 'f' * 4097)}),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(id: '')}),
        ], uid: uidA),
        403,
      );
    });

    test('an entry dated in the future, missing a key or carrying another '
        'is refused', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush('p1', uidA, {
            'd1': _device(
              at: DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
          }),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {
            'd1': _map({'id': _s('fid-1'), 'kind': _s('fid')}),
          }),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {
            'd1': _device(extra: {'name': _s('Pixel')}),
          }),
        ], uid: uidA),
        403,
      );
    });

    test('another field changed in the same write is refused', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush(
            'p1',
            uidA,
            {'d1': _device()},
            extraFields: {
              'profiles': _map({
                uidA: _profile(name: 'Alex'),
                uidB: _profile(),
              }),
            },
          ),
        ], uid: uidA),
        403,
      );
    });

    test('a pair cannot be created carrying push', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(
          _redeem(
            'p1',
            _pairFields(
              extra: {
                'push': _map({
                  uidA: _map({'d1': _device()}),
                }),
              },
            ),
            by: uidA,
          ),
          uid: uidA,
        ),
        403,
      );
    });

    test('an ended pair refuses an added or changed device and lets one '
        'leave', () async {
      // One instant for every entry: a device left as it was must read as
      // unchanged, which two stamps across a second's boundary would not.
      final at = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      await _seedPair(
        'p1',
        status: 'ended',
        extra: {
          'push': _map({
            uidA: _map({
              'd1': _device(id: 'fid-1', at: at),
              'd2': _device(id: 'fid-2', at: at),
            }),
          }),
        },
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {
            'd1': _device(id: 'fid-1', at: at),
            'd2': _device(id: 'fid-2', at: at),
            'd3': _device(id: 'fid-3', at: at),
          }),
        ], uid: uidA),
        403,
        reason: 'an address must not be made reachable through an ended pair',
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(id: 'fid-9', at: at)}),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          _writePush('p1', uidA, {'d1': _device(id: 'fid-1', at: at)}),
        ], uid: uidA),
        200,
      );
      expect(await _commit([_writePush('p1', uidA, null)], uid: uidA), 200);
    });

    test('a stranger, or nobody signed in, writes no device', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          _writePush('p1', uidC, {'d1': _device()}),
        ], uid: uidC),
        403,
      );
      expect(
        await _commit([_writePush('p1', uidA, {'d1': _device()})]),
        403,
      );
    });

    test('a bad entry beside good ones is refused at each of the five '
        'places', () async {
      await _seedPair('p1');
      for (var bad = 0; bad < 5; bad++) {
        expect(
          await _commit([
            _writePush('p1', uidA, {
              for (var i = 0; i < 5; i++)
                'd$i': i == bad ? _device(kind: 'apns') : _device(id: 'f$i'),
            }),
          ], uid: uidA),
          403,
          reason: 'the bad entry at place $bad',
        );
      }
    });

    /// A masked write of [field] — the whole of it — as [value]; null
    /// deletes it.
    Map<String, Object?> writeField(String field, Map<String, Object?>? value) =>
        {
          'update': {
            'name': '$_docRoot/pairs/p1',
            'fields': {field: ?value},
          },
          'updateMask': {
            'fieldPaths': [field],
          },
          'currentDocument': {'exists': true},
        };

    test('the partner\'s devices cannot be deleted, alone or with the whole '
        'map', () async {
      await _seedPair(
        'p1',
        extra: {
          'push': _map({
            uidA: _map({'d1': _device()}),
            uidB: _map({'d1': _device(id: 'fid-b')}),
          }),
        },
      );
      expect(
        await _commit([_writePush('p1', uidB, null)], uid: uidA),
        403,
      );
      expect(await _commit([writeField('push', null)], uid: uidA), 403);
    });

    test('a key that is not a member, a push that is not a map, and devices '
        'that are not a map are refused', () async {
      await _seedPair('p1');
      expect(
        await _commit([
          writeField(
            'push',
            _map({
              uidA: _map({'d1': _device()}),
              uidC: _map({'d1': _device()}),
            }),
          ),
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/pairs/p1',
              'fields': {'push': _s('nothing')},
            },
            'updateMask': {
              'fieldPaths': ['push'],
            },
          },
        ], uid: uidA),
        403,
      );
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/pairs/p1',
              'fields': {
                'push': _map({uidA: _s('nothing')}),
              },
            },
            'updateMask': {
              'fieldPaths': ['push.`$uidA`'],
            },
          },
        ], uid: uidA),
        403,
      );
    });

    test('config/push: a signed-in get; no list, no write, nothing signed '
        'out', () async {
      expect(await _get('config/push', uid: uidA), 404);
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/config/push',
              'fields': {'relay': _s('https://relay.example')},
            },
          },
        ], admin: true),
        200,
      );
      expect(await _get('config/push', uid: uidA), 200);
      expect(await _get('config/push'), 403);
      expect(
        await _get('config/other', uid: uidA),
        403,
        reason: 'the one document alone is open',
      );
      expect(
        (await _call('GET', '$_base/config', uid: uidA)).status,
        403,
        reason: 'a listing of config is never answered',
      );
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/config/push',
              'fields': {'relay': _s('https://evil.example')},
            },
          },
        ], uid: uidA),
        403,
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
        await _commit(_redeem('p1', _pairFields(), by: uidB), uid: uidB),
        403,
        reason: 'the creator claiming its own invite is a self-pair',
      );
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidA), uid: uidA),
        200,
      );
    });

    test('a claim that names no pair, or a pair that is not the caller\'s '
        'made from this invite, is refused: an invite is never spent on '
        'nothing', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit([_claimInvite('${code}_p1', by: uidA)], uid: uidA),
        403,
        reason: 'no such pair',
      );
      await _seedPair('${code}_theirs', members: const [uidB, uidC]);
      expect(
        await _commit([_claimInvite('${code}_theirs', by: uidA)], uid: uidA),
        403,
        reason: 'a pair of two other accounts',
      );
      const other = 'OTHER234';
      await _seedInvite(other, creatorUid: uidB);
      await _seedPair('${code}_mine');
      expect(
        await _commit([
          _claimInvite('${code}_mine', by: uidA, inviteCode: other),
        ], uid: uidA),
        403,
        reason: 'a pair made from another invite',
      );
      expect(await _get('invites/$code', uid: uidA), 200);
    });

    test('a claim cannot be forged for someone else or left empty', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(
        await _commit(_redeem('p1', _pairFields(), by: uidC), uid: uidA),
        403,
      );
      expect(
        await _commit([
          _createPair('p1', _pairFields()),
          _claimInvite('', by: uidA),
        ], uid: uidA),
        403,
      );
    });

    test('an already-claimed invite cannot be reclaimed', () async {
      await _seedInvite(
        code,
        creatorUid: uidB,
        pairId: '${code}_p1',
        redeemedBy: uidA,
      );
      await _seedPair('${code}_p2', members: const [uidB, uidC]);
      expect(
        await _commit([_claimInvite('${code}_p2', by: uidC)], uid: uidC),
        403,
      );
    });

    test('only the creator may cancel a pending invite', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(await _commit([_delete('invites/$code')], uid: uidA), 403);
      expect(await _commit([_delete('invites/$code')]), 403);
      expect(await _commit([_delete('invites/$code')], uid: uidB), 200);
    });

    test(
      'a spent invite is removed by either side, never by a stranger',
      () async {
        await _seedInvite(
          code,
          creatorUid: uidB,
          pairId: 'p1',
          redeemedBy: uidA,
        );
        expect(await _commit([_delete('invites/$code')], uid: uidC), 403);
        expect(await _commit([_delete('invites/$code')], uid: uidA), 200);

        await _seedInvite(
          'SPENT234',
          creatorUid: uidB,
          pairId: 'p2',
          redeemedBy: uidA,
        );
        expect(await _commit([_delete('invites/SPENT234')], uid: uidB), 200);
      },
    );

    test('an invite already gone is deleted again without a refusal; '
        'signed out it still is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect(await _commit([_delete('invites/$code')], uid: uidB), 200);
      expect(await _commit([_delete('invites/$code')], uid: uidB), 200);
      expect(await _commit([_delete('invites/$code')], uid: uidA), 200);
      expect(await _commit([_delete('invites/$code')]), 403);
    });

    test('an account lists the invites it created and the ones it '
        'redeemed, expired ones included', () async {
      await _seedInvite(code, creatorUid: uidA);
      await _seedInvite(
        'EXPIRED2',
        creatorUid: uidA,
        lifetime: const Duration(minutes: -1),
      );
      await _seedInvite(
        'SPENT234',
        creatorUid: uidB,
        pairId: 'p1',
        redeemedBy: uidA,
      );
      await _seedInvite('THEIRS23', creatorUid: uidB);

      final created = await _queryInvites('creatorUid', uidA, uid: uidA);
      expect(created.status, 200);
      expect(created.body, contains('invites/$code'));
      expect(created.body, contains('invites/EXPIRED2'));
      expect(created.body, isNot(contains('invites/THEIRS23')));

      final redeemed = await _queryInvites('redeemedBy', uidA, uid: uidA);
      expect(redeemed.status, 200);
      expect(redeemed.body, contains('invites/SPENT234'));
      expect(redeemed.body, isNot(contains('invites/$code')));
    });

    test('a listing of another account\'s invites is refused', () async {
      await _seedInvite(code, creatorUid: uidB);
      expect((await _queryInvites('creatorUid', uidB, uid: uidC)).status, 403);
      expect((await _queryInvites('redeemedBy', uidB, uid: uidC)).status, 403);
      expect((await _queryInvites('creatorUid', uidB, uid: null)).status, 403);
    });
  });

  /// Case for case the same set as `tool/firebase/rules_probe.ps1`, which is
  /// a Windows convenience — it brings its own emulator and needs
  /// `taskkill.exe` — while these are the coverage: they run in the gate on
  /// either machine whenever `firestore.rules` changes.
  group('spaces', () {
    test('owner creates a space', () async {
      expect(await _commit([_createSpace(uidA, 's1')], uid: uidA), 200);
    });

    test('owner reads the space', () async {
      await _seedSpace();
      expect(await _get(_spaceDoc(uidA, 's1'), uid: uidA), 200);
    });

    test('a stranger reads the space', () async {
      await _seedSpace();
      expect(await _get(_spaceDoc(uidA, 's1'), uid: uidB), 403);
    });

    test('signed out reads the space', () async {
      await _seedSpace();
      expect(await _get(_spaceDoc(uidA, 's1')), 403);
    });

    test('owner pushes an upsert, space merged at an equal schema', () async {
      await _seedSpace();
      expect(await _push([_row(uidA, 's1', 'folders', 'f1')]), 200);
    });

    test('owner reads the row', () async {
      await _seedSpace();
      expect(await _push([_row(uidA, 's1', 'folders', 'f1')]), 200);
      expect(await _get('${_spaceDoc(uidA, 's1')}/folders/f1', uid: uidA), 200);
    });

    test('owner lists the table in pull order', () async {
      await _seedSpace();
      expect(await _push([_row(uidA, 's1', 'folders', 'f1')]), 200);

      final result = await _call(
        'POST',
        '$_base/${_spaceDoc(uidA, 's1')}:runQuery',
        uid: uidA,
        body: {
          'structuredQuery': {
            'from': [
              {'collectionId': 'folders'},
            ],
            'orderBy': [
              {
                'field': {'fieldPath': 'pushedAt'},
              },
              {
                'field': {'fieldPath': '__name__'},
              },
            ],
            'limit': 499,
          },
        },
      );

      expect(result.status, 200);
      expect(result.body, contains('folders/f1'));
    });

    test('a stranger pushes into the space', () async {
      await _seedSpace();
      expect(
        await _commit([
          _row(uidA, 's1', 'folders', 'f9', fields: {'ownerId': _s(uidB)}),
        ], uid: uidB),
        403,
      );
    });

    test('a tombstone with data null', () async {
      await _seedSpace();
      expect(
        await _push([
          _row(
            uidA,
            's1',
            'folders',
            'f2',
            fields: {'op': _s('tombstone'), 'data': _nul},
          ),
        ]),
        200,
      );
    });

    test('a tombstone without the data key', () async {
      await _seedSpace();
      expect(
        await _push([
          _row(
            uidA,
            's1',
            'folders',
            'f3',
            fields: {'op': _s('tombstone')},
            omit: const ['data'],
          ),
        ]),
        403,
        reason: 'a merge on an existing row would leave the old data behind',
      );
    });

    test('a tombstone with map data', () async {
      await _seedSpace();
      expect(
        await _push([
          _row(uidA, 's1', 'folders', 'f11', fields: {'op': _s('tombstone')}),
        ]),
        403,
      );
    });

    test('an upsert with data null', () async {
      await _seedSpace();
      expect(
        await _push([
          _row(uidA, 's1', 'folders', 'f12', fields: {'data': _nul}),
        ]),
        403,
      );
    });

    test('a space created with a client createdAt', () async {
      expect(
        await _commit([
          _createSpace(
            uidA,
            's2',
            name: 'Other',
            serverCreatedAt: false,
            extra: {'createdAt': _ts(DateTime.utc(2026))},
          ),
        ], uid: uidA),
        403,
        reason: 'a backdated space would sit below every cursor',
      );
    });

    test('a space update changing createdAt', () async {
      await _seedSpace();
      expect(
        await _commit([
          {
            'update': {
              'name': '$_docRoot/${_spaceDoc(uidA, 's1')}',
              'fields': {'createdAt': _ts(DateTime.utc(2020))},
            },
            'updateMask': {
              'fieldPaths': ['createdAt'],
            },
          },
        ], uid: uidA),
        403,
      );
    });

    test('ownerId null', () async {
      await _seedSpace();
      expect(
        await _push([
          _row(uidA, 's1', 'folders', 'f4', fields: {'ownerId': _nul}),
        ]),
        403,
      );
    });

    test('a space merge at a lower schema', () async {
      await _seedSpace();
      expect(
        await _push([_row(uidA, 's1', 'folders', 'f5')], schema: 42),
        403,
        reason: 'an outdated device must not write rows lacking columns',
      );
    });

    test('a push to a missing space', () async {
      expect(
        await _push([
          _row(uidA, 'missing', 'folders', 'f6'),
        ], spaceId: 'missing'),
        403,
      );
    });

    test('an unknown table', () async {
      await _seedSpace();
      expect(
        await _push([_row(uidA, 's1', 'secrets', 'x1')], table: 'secrets'),
        403,
      );
    });

    // The rules' table list is otherwise pinned only textually
    // (firestore_rules_tables_test); walking the app's own list puts the
    // newest table, and every one added after it, before the real engine.
    for (final binding in syncTableBindings) {
      final table = binding.table;
      test('owner pushes an upsert under $table', () async {
        await _seedSpace();
        expect(await _push([_row(uidA, 's1', table, 'k1')], table: table), 200);
      });

      test('the same upsert under a name near $table', () async {
        await _seedSpace();
        final unknown = '${table}_x';
        expect(
          await _push([_row(uidA, 's1', unknown, 'k1')], table: unknown),
          403,
        );
      });
    }

    // A chunk is immutable text under its hash (scalability record S6): the
    // rules hold its shape, so no build can store a body it cannot carry.
    group('a chunk document', () {
      Future<int> pushChunk(Map<String, Object?> fields) => _push([
        _row(uidA, 's1', 'content_chunks', 'h1', fields: fields),
      ], table: 'content_chunks');

      test('with gz bytes at 64 KB', () async {
        await _seedSpace();
        expect(
          await pushChunk({
            'data': _chunkData(
              'h1',
              gz: _bytes(ContentChunksBinding.maxGzBytes),
            ),
          }),
          200,
        );
      });

      test('as a tombstone', () async {
        await _seedSpace();
        expect(
          await pushChunk({'op': _s('tombstone'), 'data': _nul}),
          403,
          reason: 'a manifest anywhere may still name it',
        );
      });

      test('with gz over 64 KB', () async {
        await _seedSpace();
        expect(
          await pushChunk({
            'data': _chunkData(
              'h1',
              gz: _bytes(ContentChunksBinding.maxGzBytes + 1),
            ),
          }),
          403,
        );
      });

      test('with gz not bytes', () async {
        await _seedSpace();
        expect(
          await pushChunk({'data': _chunkData('h1', gz: _s('text'))}),
          403,
        );
      });
    });

    test('pushedAt not the request time', () async {
      await _seedSpace();
      expect(
        await _push([
          _row(uidA, 's1', 'folders', 'f7', pushedAt: DateTime.utc(2026)),
        ]),
        403,
        reason: 'a backdated row would sit below every puller cursor',
      );
    });

    // Recorded, not judged: the rules check no parent, so a row alone under a
    // space that does not exist is allowed. What a denial rests on is the
    // gateway writing the space document in the same batch (§3.3) — never on
    // the rules, so this expectation is the rules as they are, not a wish.
    test('a row alone, no space write, under a missing space', () async {
      expect(
        await _commit([_row(uidA, 'missing', 'folders', 'f8')], uid: uidA),
        200,
      );
    });

    test('a space merge at a higher schema', () async {
      await _seedSpace();
      expect(
        await _push([_row(uidA, 's1', 'folders', 'f10')], schema: 44),
        200,
        reason: 'the schema only ever rises, and a newer device raises it',
      );
    });
  });

  /// Deleting a space (record cloud-multi-user-roadmap §5.3, §5.6): marked,
  /// emptied, removed. Case for case the same set as the probe's.
  group('deleting a space', () {
    final row = '${_spaceDoc(uidA, 's1')}/folders/f1';
    final space = _spaceDoc(uidA, 's1');

    test('a row of an unmarked space cannot be deleted', () async {
      await _seedSpace();
      expect(await _push([_row(uidA, 's1', 'folders', 'f1')]), 200);
      expect(
        await _commit([_delete(row)], uid: uidA),
        403,
        reason: 'a live space loses a row by tombstone only',
      );
    });

    test('an unmarked space cannot be deleted', () async {
      await _seedSpace();
      expect(await _commit([_delete(space)], uid: uidA), 403);
    });

    test('the owner marks the space', () async {
      await _seedSpace();
      expect(await _commit([_mark(uidA, 's1')], uid: uidA), 200);
    });

    test('a stranger marks the space', () async {
      await _seedSpace();
      expect(await _commit([_mark(uidA, 's1')], uid: uidB), 403);
    });

    test('a mark at a client time', () async {
      await _seedSpace();
      expect(
        await _commit([
          _mark(uidA, 's1', clientTime: DateTime.utc(2026)),
        ], uid: uidA),
        403,
      );
    });

    test('a space created already marked', () async {
      expect(
        await _commit([
          {
            ..._createSpace(uidA, 's2'),
            'updateTransforms': [
              _serverTime('createdAt'),
              _serverTime('deletedAt'),
            ],
          },
        ], uid: uidA),
        403,
      );
    });

    test('a second mark', () async {
      await _seedMarked();
      expect(await _commit([_mark(uidA, 's1')], uid: uidA), 403);
    });

    test('a push to a marked space', () async {
      await _seedMarked();
      expect(
        await _push([_row(uidA, 's1', 'folders', 'f2')]),
        403,
        reason: 'the space merge is an update, and a marked space takes none',
      );
    });

    test('the mark removed', () async {
      await _seedMarked();
      expect(
        await _commit([
          {
            'update': {'name': '$_docRoot/$space', 'fields': {}},
            'updateMask': {
              'fieldPaths': ['deletedAt'],
            },
          },
        ], uid: uidA),
        403,
      );
    });

    test('the owner deletes a row of a marked space', () async {
      await _seedMarked();
      expect(await _commit([_delete(row)], uid: uidA), 200);
    });

    // A whole page as `deleteRows` sends it: twenty rows in one commit, each
    // delete one `get()` of the space (review F9; SyncGateway.rowDeleteBatch).
    test(
      'the owner deletes twenty rows of a marked space in one commit',
      () async {
        await _seedSpace();
        final keys = [
          for (var i = 0; i < 20; i++) 'p${i.toString().padLeft(2, '0')}',
        ];
        expect(
          await _push([
            for (final key in keys) _row(uidA, 's1', 'folders', key),
          ]),
          200,
        );
        expect(await _commit([_mark(uidA, 's1')], uid: uidA), 200);
        expect(
          await _commit([
            for (final key in keys)
              _delete('${_spaceDoc(uidA, 's1')}/folders/$key'),
          ], uid: uidA),
          200,
        );
        for (final key in keys) {
          expect(
            await _get('${_spaceDoc(uidA, 's1')}/folders/$key', uid: uidA),
            404,
          );
        }
      },
    );

    test('a stranger deletes a row of a marked space', () async {
      await _seedMarked();
      expect(await _commit([_delete(row)], uid: uidB), 403);
    });

    // What makes a repeated delete of a page safe to retry.
    test('a row already gone under a marked space', () async {
      await _seedMarked();
      expect(
        await _commit([
          _delete('${_spaceDoc(uidA, 's1')}/folders/never'),
        ], uid: uidA),
        200,
      );
    });

    test('a row of an unknown table under a marked space', () async {
      await _seedMarked();
      expect(
        await _commit([
          _delete('${_spaceDoc(uidA, 's1')}/secrets/x1'),
        ], uid: uidA),
        403,
      );
    });

    test('a row under a missing space', () async {
      expect(
        await _commit([_row(uidA, 'missing', 'folders', 'f8')], uid: uidA),
        200,
      );
      expect(
        await _commit([
          _delete('${_spaceDoc(uidA, 'missing')}/folders/f8'),
        ], uid: uidA),
        403,
      );
    });

    test('the owner deletes the rows, then the marked space', () async {
      await _seedMarked();
      expect(await _commit([_delete(row)], uid: uidA), 200);
      expect(await _commit([_delete(space)], uid: uidA), 200);
      expect(await _get(space, uid: uidA), 404);
    });

    test('a stranger deletes the marked space', () async {
      await _seedMarked();
      expect(await _commit([_delete(space)], uid: uidB), 403);
    });

    // Recorded: a space already gone has no mark to read, so a repeated
    // delete is refused — the gateway reads the space and completes.
    test('a space already gone', () async {
      await _seedMarked();
      expect(await _commit([_delete(space)], uid: uidA), 200);
      expect(await _commit([_delete(space)], uid: uidA), 403);
    });
  });

  /// Sharing (docs/cloud-sharing-foundations.md §4): what an owner may
  /// write about a share, and what a member of the pair may read. uidA
  /// owns, uidB is the partner, uidC a stranger.
  group('sharing', () {
    String rowPath(String table, String key, {String owner = uidA}) =>
        '${_spaceDoc(owner, 's1')}/$table/$key';

    group('the owner writes', () {
      test('a shared row of each shareable table, a tombstone too', () async {
        await _seedSpace();
        for (final table in sharedTables) {
          expect(
            await _push([
              _row(uidA, 's1', table, 'k1', fields: _share('p1')),
              _row(
                uidA,
                's1',
                table,
                'k2',
                fields: {..._share('p1'), 'op': _s('tombstone'), 'data': _nul},
              ),
            ], table: table),
            200,
            reason: table,
          );
        }
      });

      test('a shared row of a table that cannot be shared', () async {
        await _seedSpace();
        for (final table in [
          'calendar_event_absences',
          'calendar_event_alerts',
          'counters',
          'counter_values',
          'calendar_category_alerts',
          'calendar_category_profiles',
          'calendar_event_templates',
          'content_chunks',
        ]) {
          expect(
            await _push([
              _row(uidA, 's1', table, 'k1', fields: _share('p1')),
            ], table: table),
            403,
            reason: '$table is a person\'s own, or carries no grant',
          );
        }
      });

      test('a share without the wire that wrote it, or a wire without a '
          'share', () async {
        await _seedSpace();
        expect(
          await _push([
            _row(uidA, 's1', 'folders', 'f1', fields: {'sharedPair': _s('p1')}),
          ]),
          403,
        );
        expect(
          await _push([
            _row(uidA, 's1', 'folders', 'f1', fields: {'wire': _int(47)}),
          ]),
          403,
        );
      });

      test('a share that is not a short, non-empty string', () async {
        await _seedSpace();
        for (final bad in [_s(''), _s('p' * 65), _int(1), _nul]) {
          expect(
            await _push([
              _row(
                uidA,
                's1',
                'folders',
                'f1',
                fields: {'sharedPair': bad, 'wire': _int(47)},
              ),
            ]),
            403,
            reason: '$bad',
          );
        }
        expect(
          await _push([
            _row(
              uidA,
              's1',
              'folders',
              'f1',
              fields: {'sharedPair': _s('p1'), 'wire': _s('47')},
            ),
          ]),
          403,
        );
      });

      test('a row made private again: the same document, without a '
          'share', () async {
        await _seedSpace();
        expect(
          await _push([
            _row(uidA, 's1', 'folders', 'f1', fields: _share('p1')),
          ]),
          200,
        );
        expect(await _push([_row(uidA, 's1', 'folders', 'f1')]), 200);
      });

      test('the pair its notes are shared into on the space, and takes it '
          'out again', () async {
        await _seedSpace();
        expect(
          await _pushSharing([
            _row(uidA, 's1', 'folders', 'f1', fields: _share('p1')),
          ], sharedPair: 'p1'),
          200,
        );
        expect(
          await _pushSharing([
            _row(uidA, 's1', 'folders', 'f1'),
          ], sharedPair: null),
          200,
        );
      });

      test('a push that names no pair, to a space that never had one — '
          'every push of a database that shares nothing', () async {
        await _seedSpace();
        expect(
          await _pushSharing([
            _row(uidA, 's1', 'folders', 'f1'),
          ], sharedPair: null),
          200,
        );
      });

      test('a pair on the space that is not a short, non-empty '
          'string', () async {
        await _seedSpace();
        for (final bad in ['', 'p' * 65]) {
          expect(
            await _pushSharing([
              _row(uidA, 's1', 'folders', 'f1'),
            ], sharedPair: bad),
            403,
            reason: 'length ${bad.length}',
          );
        }
      });
    });

    group('the partner reads', () {
      /// Space `s1` of uidA: `shared` and its tombstone `gone` shared into
      /// `p1`, `private` shared with nobody — in each shareable table — the
      /// text chunk `h1`, and the space naming `p1`. `p1` pairs A and B.
      Future<void> seed({String pairStatus = 'active'}) async {
        await _seedPair('p1', status: pairStatus);
        await _seedSpace(schema: 47);
        for (final table in sharedTables) {
          expect(
            await _pushSharing(
              [
                _row(uidA, 's1', table, 'shared', fields: _share('p1')),
                _row(
                  uidA,
                  's1',
                  table,
                  'gone',
                  fields: {
                    ..._share('p1'),
                    'op': _s('tombstone'),
                    'data': _nul,
                  },
                ),
                _row(uidA, 's1', table, 'private'),
              ],
              sharedPair: 'p1',
              table: table,
            ),
            200,
            reason: 'seed of $table',
          );
        }
        expect(
          await _pushSharing(
            [_row(uidA, 's1', 'content_chunks', 'h1')],
            sharedPair: 'p1',
            table: 'content_chunks',
          ),
          200,
          reason: 'seed of the chunk',
        );
      }

      test('the rows shared into the pair, of each shareable table — the '
          'tombstone with them, a private row never', () async {
        await seed();
        for (final table in sharedTables) {
          final read = await _runShared(
            _sharedQuery(table, pair: 'p1', owner: uidA),
            uid: uidB,
          );
          expect(read.status, 200, reason: table);
          expect(read.keys, unorderedEquals(['shared', 'gone']), reason: table);
        }
      });

      test('how many there are, by the same query', () async {
        await seed();
        final counted = await _countShared(
          _sharedQuery('folders', pair: 'p1', owner: uidA),
          uid: uidB,
        );
        expect(counted.status, 200);
        expect(counted.count, 2);
      });

      test('one shared row by its path; a private one is refused', () async {
        await seed();
        expect(await _get(rowPath('notes', 'shared'), uid: uidB), 200);
        expect(await _get(rowPath('notes', 'gone'), uid: uidB), 200);
        expect(await _get(rowPath('notes', 'private'), uid: uidB), 403);
      });

      test('the text of the space that shares into the pair, one chunk by '
          'its hash — never a listing of it', () async {
        await seed();
        expect(await _get(rowPath('content_chunks', 'h1'), uid: uidB), 200);
        final listed = await _call(
          'GET',
          '$_base/${_spaceDoc(uidA, 's1')}/content_chunks',
          uid: uidB,
        );
        expect(listed.status, 403);
      });

      test('nothing of a space that shares into no pair: its text is the '
          'owner\'s alone', () async {
        await seed();
        expect(
          await _pushSharing(
            [_row(uidA, 's1', 'content_chunks', 'h2')],
            sharedPair: null,
            table: 'content_chunks',
          ),
          200,
        );
        expect(await _get(rowPath('content_chunks', 'h1'), uid: uidB), 403);
        expect(await _get(rowPath('content_chunks', 'h2'), uid: uidB), 403);
      });

      test('never the space document itself, nor a row of a table that is '
          'not shared', () async {
        await seed();
        expect(await _get(_spaceDoc(uidA, 's1'), uid: uidB), 403);
        expect(
          await _push(
            [_row(uidA, 's1', 'counters', 'c1')],
            schema: 47,
            table: 'counters',
          ),
          200,
        );
        expect(await _get(rowPath('counters', 'c1'), uid: uidB), 403);
        final listed = await _runShared(
          _sharedQuery('counters', pair: 'p1', owner: uidA),
          uid: uidB,
        );
        expect(listed.status, 403);
      });

      test('a query that does not pin the pair is refused whole: nothing '
          'is ever listed across pairs', () async {
        await seed();
        final byOwner = await _runShared(
          _sharedQuery('folders', pair: null, owner: uidA),
          uid: uidB,
        );
        expect(byOwner.status, 403);
      });

      test(
        'a query for a pair without naming the owner is refused whole: '
        'whether the pair holds each row\'s owner cannot be decided',
        () async {
          await seed();
          final read = await _runShared(
            _sharedQuery('folders', pair: 'p1', owner: null),
            uid: uidB,
          );
          expect(read.status, 403);
        },
      );

      test('the owner reads its shared rows by the same query', () async {
        await seed();
        final read = await _runShared(
          _sharedQuery('folders', pair: 'p1', owner: uidA),
          uid: uidA,
        );
        expect(read.status, 200);
        expect(read.keys, unorderedEquals(['shared', 'gone']));
      });

      test('a partner writes nothing: not a shared row, not its own under '
          'the owner\'s space', () async {
        await seed();
        expect(
          await _commit([
            _row(uidA, 's1', 'folders', 'shared', fields: _share('p1')),
          ], uid: uidB),
          403,
        );
        expect(
          await _commit([
            _row(uidA, 's1', 'folders', 'mine', fields: {'ownerId': _s(uidB)}),
          ], uid: uidB),
          403,
        );
        expect(
          await _commit([_delete(rowPath('folders', 'shared'))], uid: uidB),
          403,
        );
      });
    });

    group('everyone else is refused', () {
      Future<void> seedShared({String status = 'active'}) async {
        await _seedPair('p1', status: status);
        await _seedSpace(schema: 47);
        expect(
          await _pushSharing([
            _row(uidA, 's1', 'folders', 'shared', fields: _share('p1')),
            _row(
              uidA,
              's1',
              'calendar_categories',
              'shared',
              fields: _share('p1', wire: 48),
            ),
            _row(uidA, 's1', 'content_chunks', 'h1'),
          ], sharedPair: 'p1'),
          200,
          reason: 'seed',
        );
      }

      Future<void> expectNothingFor(
        String? uid, {
        String? reason,
        String table = 'folders',
      }) async {
        final listed = await _runShared(
          _sharedQuery(table, pair: 'p1', owner: uidA),
          uid: uid,
        );
        expect(listed.status, 403, reason: reason);
        final counted = await _countShared(
          _sharedQuery(table, pair: 'p1', owner: uidA),
          uid: uid,
        );
        expect(counted.status, 403, reason: reason);
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/$table/shared', uid: uid),
          403,
          reason: reason,
        );
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/content_chunks/h1', uid: uid),
          403,
          reason: reason,
        );
      }

      test('a stranger, and nobody signed in', () async {
        await seedShared();
        await expectNothingFor(uidC, reason: 'not a member of the pair');
        await expectNothingFor(null, reason: 'not signed in');
        await expectNothingFor(
          uidC,
          reason: 'a category, to a stranger',
          table: 'calendar_categories',
        );
        await expectNothingFor(
          null,
          reason: 'a category, signed out',
          table: 'calendar_categories',
        );
      });

      test('the partner, once the pair is ended — at once, with the '
          'owner\'s documents still naming it', () async {
        await seedShared();
        expect(
          (await _runShared(
            _sharedQuery('folders', pair: 'p1', owner: uidA),
            uid: uidB,
          )).status,
          200,
        );
        expect(
          (await _runShared(
            _sharedQuery('calendar_categories', pair: 'p1', owner: uidA),
            uid: uidB,
          )).keys,
          ['shared'],
        );
        await _seedPair('p1', status: 'ended');

        await expectNothingFor(uidB, reason: 'the pair is ended');
        await expectNothingFor(
          uidB,
          reason: 'a category, the pair ended',
          table: 'calendar_categories',
        );
      });

      test('the partner, once the pair is removed by an account\'s '
          'deletion', () async {
        await seedShared();
        expect(
          await _commit([_delete('pairs/p1')], admin: true),
          200,
          reason: 'admin removal of the pair',
        );

        await expectNothingFor(uidB, reason: 'the pair is gone');
      });

      test('a member of another pair that happens to be named on the row: '
          'only that pair\'s members read it', () async {
        await seedShared();
        await _seedPair('p2', members: const [uidB, uidC]);

        await expectNothingFor(uidC, reason: 'a member of p2, not of p1');
      });

      test('a row that names a pair its owner is not in is read by nobody: '
          'the pair has to hold the owner', () async {
        // uidC shares into p1, the pair of A and B, without being in it.
        await _seedPair('p1');
        await _seedSpace(owner: uidC, schema: 47);
        expect(
          await _pushSharing(
            [
              _row(uidC, 's1', 'folders', 'planted', fields: _share('p1')),
              _row(uidC, 's1', 'content_chunks', 'h1'),
            ],
            sharedPair: 'p1',
            owner: uidC,
          ),
          200,
        );

        final asked = await _runShared(
          _sharedQuery('folders', pair: 'p1', owner: uidC),
          uid: uidB,
        );
        expect(asked.status, 403);
        expect(
          await _get('${_spaceDoc(uidC, 's1')}/folders/planted', uid: uidB),
          403,
        );
        expect(
          await _get('${_spaceDoc(uidC, 's1')}/content_chunks/h1', uid: uidB),
          403,
        );
        final pinned = await _runShared(
          _sharedQuery('folders', pair: 'p1', owner: uidA),
          uid: uidB,
        );
        expect(pinned.status, 200);
        expect(pinned.keys, isEmpty);
      });

      test('the former partner who removes the ended pair and makes it '
          'again under the same id with another account — the owner\'s '
          'documents still name that id, and the new pair does not hold the '
          'owner', () async {
        await seedShared();
        await _seedPair('p1', status: 'ended');
        expect(await _commit([_delete('pairs/p1')], uid: uidB), 200);
        // Whatever let the id be taken again: the admin stands in for it, so
        // the read rule is judged on its own.
        await _seedPair('p1', members: const [uidB, uidC]);

        await expectNothingFor(uidB, reason: 'the owner is not in this pair');
        await expectNothingFor(uidC, reason: 'the owner is not in this pair');
      });
    });

    // A category is a root of a grant (docs/cloud-share-surfaces-roadmap.md
    // §7): its own document carries its mark, and an event without a mark
    // of its own carries its category's, derived when it is encoded.
    group('a category', () {
      const table = 'calendar_categories';

      /// Space `s1` of uidA: the category `shared` and its tombstone `gone`
      /// shared into `p1`, `private` shared with nobody, and `other` shared
      /// into `p2` — the pair of B and C, which does not hold the owner.
      Future<void> seed() async {
        await _seedPair('p1');
        await _seedPair('p2', members: const [uidB, uidC]);
        await _seedSpace(schema: 48);
        expect(
          await _pushSharing(
            [
              _row(uidA, 's1', table, 'shared', fields: _share('p1', wire: 48)),
              _row(
                uidA,
                's1',
                table,
                'gone',
                fields: {
                  ..._share('p1', wire: 48),
                  'op': _s('tombstone'),
                  'data': _nul,
                },
              ),
              _row(uidA, 's1', table, 'private'),
              _row(uidA, 's1', table, 'other', fields: _share('p2', wire: 48)),
            ],
            sharedPair: 'p1',
            schema: 48,
            table: table,
          ),
          200,
          reason: 'seed',
        );
      }

      test('the partner\'s query and its count: the shared one and its '
          'tombstone, never a private one or one of another pair', () async {
        await seed();
        final read = await _runShared(
          _sharedQuery(table, pair: 'p1', owner: uidA),
          uid: uidB,
        );
        expect(read.status, 200);
        expect(read.keys, unorderedEquals(['shared', 'gone']));
        final counted = await _countShared(
          _sharedQuery(table, pair: 'p1', owner: uidA),
          uid: uidB,
        );
        expect(counted.status, 200);
        expect(counted.count, 2);
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/$table/shared', uid: uidB),
          200,
        );
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/$table/private', uid: uidB),
          403,
        );
      });

      test('a query without the pair filter, or without the owner, is '
          'refused whole', () async {
        await seed();
        expect(
          (await _runShared(
            _sharedQuery(table, pair: null, owner: uidA),
            uid: uidB,
          )).status,
          403,
        );
        expect(
          (await _countShared(
            _sharedQuery(table, pair: null, owner: uidA),
            uid: uidB,
          )).status,
          403,
        );
        expect(
          (await _runShared(
            _sharedQuery(table, pair: 'p1', owner: null),
            uid: uidB,
          )).status,
          403,
        );
      });

      test('a category naming a pair its owner is not in is read by nobody, '
          'whoever is in that pair', () async {
        await seed();
        for (final uid in const [uidB, uidC]) {
          expect(
            (await _runShared(
              _sharedQuery(table, pair: 'p2', owner: uidA),
              uid: uid,
            )).status,
            403,
            reason: uid,
          );
          expect(
            await _get('${_spaceDoc(uidA, 's1')}/$table/other', uid: uid),
            403,
            reason: uid,
          );
        }
      });

      test('the partner writes none: not the owner\'s category, not a '
          'category of its own in the owner\'s space, not a delete', () async {
        await seed();
        expect(
          await _commit([
            _row(uidA, 's1', table, 'shared', fields: _share('p1', wire: 48)),
          ], uid: uidB),
          403,
        );
        expect(
          await _commit([
            _row(uidA, 's1', table, 'mine', fields: {'ownerId': _s(uidB)}),
          ], uid: uidB),
          403,
        );
        expect(
          await _commit([
            _delete('${_spaceDoc(uidA, 's1')}/$table/shared'),
          ], uid: uidB),
          403,
        );
      });

      test('an event shared only through its category is read as long as its '
          'document names the pair, and not once the owner sends it '
          'without', () async {
        await seed();
        Map<String, Object?> event(
          String key,
          String category, {
          String? pair,
        }) => _row(
          uidA,
          's1',
          'calendar_events',
          key,
          fields: {
            'data': _map({
              'id': _s(key),
              'title': _s('Climb'),
              'category': _s(category),
            }),
            if (pair != null) ..._share(pair, wire: 48),
          },
        );
        expect(
          await _pushSharing(
            [
              event('through', 'shared', pair: 'p1'),
              event('beside', 'private'),
            ],
            sharedPair: 'p1',
            schema: 48,
            table: 'calendar_events',
          ),
          200,
        );
        final eventPath = '${_spaceDoc(uidA, 's1')}/calendar_events';
        expect(
          (await _runShared(
            _sharedQuery('calendar_events', pair: 'p1', owner: uidA),
            uid: uidB,
          )).keys,
          ['through'],
        );
        expect(await _get('$eventPath/through', uid: uidB), 200);
        expect(await _get('$eventPath/beside', uid: uidB), 403);

        // The category's mark cleared: the owner re-sends it and its events
        // without the pair.
        expect(
          await _pushSharing(
            [_row(uidA, 's1', table, 'shared'), event('through', 'shared')],
            sharedPair: 'p1',
            schema: 48,
            table: 'calendar_events',
          ),
          200,
        );
        expect(await _get('$eventPath/through', uid: uidB), 403);
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/$table/shared', uid: uidB),
          403,
        );
        expect(
          (await _runShared(
            _sharedQuery('calendar_events', pair: 'p1', owner: uidA),
            uid: uidB,
          )).keys,
          isEmpty,
        );
      });

      test('a plain listing of the owner\'s categories by the partner is '
          'refused whole', () async {
        await seed();
        final listed = await _call(
          'GET',
          '$_base/${_spaceDoc(uidA, 's1')}/$table',
          uid: uidB,
        );
        expect(listed.status, 403);
      });

      test('the pair\'s query on a category\'s alerts, profiles and '
          'templates is refused: they are never shared', () async {
        await seed();
        for (final never in const [
          'calendar_category_alerts',
          'calendar_category_profiles',
          'calendar_event_templates',
        ]) {
          expect(
            await _pushSharing(
              [_row(uidA, 's1', never, 'k1')],
              sharedPair: 'p1',
              schema: 48,
              table: never,
            ),
            200,
            reason: 'seed $never',
          );
          final read = await _runShared(
            _sharedQuery(never, pair: 'p1', owner: uidA),
            uid: uidB,
          );
          expect(read.status, 403, reason: never);
          expect(read.keys, isEmpty, reason: never);
        }
      });

      test('a push at the schema before the category\'s mark, into a space '
          'already at it, is refused', () async {
        await seed();
        expect(
          await _pushSharing(
            [_row(uidA, 's1', table, 'private')],
            sharedPair: 'p1',
            schema: 47,
            table: table,
          ),
          403,
        );
        expect(
          await _pushSharing(
            [_row(uidA, 's1', 'calendar_events', 'ev47')],
            sharedPair: null,
            schema: 47,
            table: 'calendar_events',
          ),
          403,
        );
      });

      test('the partner cannot add the pair to a private category', () async {
        await seed();
        expect(
          await _commit([
            {
              'update': {
                'name': '$_docRoot/${_spaceDoc(uidA, 's1')}/$table/private',
                'fields': {'sharedPair': _s('p1')},
              },
              'updateMask': {
                'fieldPaths': ['sharedPair'],
              },
            },
          ], uid: uidB),
          403,
        );
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/$table/private', uid: uidB),
          403,
        );
      });

      test('once the pair ends, the partner reads and counts none of '
          'them', () async {
        await seed();
        await _seedPair('p1', status: 'ended');
        expect(
          await _get('${_spaceDoc(uidA, 's1')}/$table/shared', uid: uidB),
          403,
        );
        final counted = await _countShared(
          _sharedQuery(table, pair: 'p1', owner: uidA),
          uid: uidB,
        );
        expect(counted.status, 403);
        expect(counted.count, isNull);
      });
    });
  });
}
