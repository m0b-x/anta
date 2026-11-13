import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

import { createRelay } from '../src/relay.js';

const PROJECT = 'test-project';
const NOW = Date.parse('2026-11-13T12:00:00Z');
const SECOND = 1000;
const MINUTE = 60 * SECOND;
const DAY = 24 * 60 * MINUTE;
const ME = 'uid-me';
const PARTNER = 'uid-partner';
const PAIR = 'pair_01-AB';
const ACCESS_TOKEN = 'ya29.access-token-secret';

const HOSTS = new Set([
  'www.googleapis.com',
  'firestore.googleapis.com',
  'oauth2.googleapis.com',
  'fcm.googleapis.com',
]);
const CREDENTIAL_HOSTS = new Set([
  'firestore.googleapis.com',
  'oauth2.googleapis.com',
  'fcm.googleapis.com',
]);

const RSA = {
  name: 'RSASSA-PKCS1-v1_5',
  modulusLength: 2048,
  publicExponent: new Uint8Array([1, 0, 1]),
  hash: 'SHA-256',
};
const google = await crypto.subtle.generateKey(RSA, true, ['sign', 'verify']);
const rotated = await crypto.subtle.generateKey(RSA, true, ['sign', 'verify']);
const stranger = await crypto.subtle.generateKey(RSA, true, ['sign', 'verify']);
const account = await crypto.subtle.generateKey(RSA, true, ['sign', 'verify']);

const ACCOUNT_PEM = pem(new Uint8Array(await crypto.subtle.exportKey('pkcs8', account.privateKey)));
const SERVICE_ACCOUNT = serviceAccountJson(ACCOUNT_PEM);

function serviceAccountJson(privateKey) {
  return JSON.stringify({
    type: 'service_account',
    client_email: 'relay@test-project.iam.gserviceaccount.com',
    private_key_id: 'sa-key-1',
    private_key: privateKey,
  });
}

// What must never come back to a caller; logs are held to this and "Bearer".
const leaks = new Set([ACCESS_TOKEN, ME, PARTNER]);
const idTokens = new Set();
const logs = [];
const worlds = [];

// The relay keeps everything in its own memory; any reach for the Worker's
// shared cache is recorded here and fails the test.
const cacheUses = [];
globalThis.caches = new Proxy(
  {},
  {
    get(_, property) {
      cacheUses.push(String(property));
      return undefined;
    },
  },
);

afterEach(async () => {
  for (const w of worlds) {
    const outcomes = await Promise.allSettled(w.deferred);
    for (const outcome of outcomes) assert.equal(outcome.status, 'fulfilled', 'deferred work rejected');
    for (const call of w.calls.all) {
      assert.ok(HOSTS.has(call.host), `the relay called ${call.url}`);
      assert.ok(call.signal instanceof AbortSignal, `no deadline on ${call.host}`);
      if (CREDENTIAL_HOSTS.has(call.host)) {
        assert.equal(call.redirect, 'manual', `${call.host} would follow a redirect`);
      }
      if (call.host !== 'firestore.googleapis.com') {
        const seen = call.url + JSON.stringify([...call.headers]) + (call.body ?? '');
        for (const token of idTokens) assert.ok(!seen.includes(token), `an ID token went to ${call.host}`);
      }
    }
  }
  worlds.length = 0;
  assert.deepEqual(cacheUses, [], 'the relay touched the shared cache');
  for (const line of logs) {
    for (const leak of [...leaks, 'Bearer']) assert.ok(!line.includes(leak), `a log names ${leak}`);
  }
  logs.length = 0;
});

function pem(der) {
  const base64 = Buffer.from(der).toString('base64');
  return `-----BEGIN PRIVATE KEY-----\n${base64.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
}

function base64Url(bytes) {
  return Buffer.from(bytes).toString('base64url');
}

function sha256Hex(text) {
  return createHash('sha256').update(text).digest('hex');
}

async function publicJwk(pair, kid) {
  const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
  return { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', use: 'sig', kid };
}

/** An ID token; `headerText`/`payloadText` replace the canonical JSON. */
async function mint({
  claims = {},
  header = {},
  key = google.privateKey,
  signature,
  headerText,
  payloadText,
} = {}) {
  const seconds = Math.floor(NOW / SECOND);
  const head = base64Url(
    headerText ?? JSON.stringify({ alg: 'RS256', kid: 'k1', typ: 'JWT', ...header }),
  );
  const body = base64Url(
    payloadText ??
      JSON.stringify({
        iss: `https://securetoken.google.com/${PROJECT}`,
        aud: PROJECT,
        auth_time: seconds - 3600,
        iat: seconds - 60,
        exp: seconds + 3000,
        sub: ME,
        user_id: ME,
        ...claims,
      }),
  );
  const signed =
    signature ??
    base64Url(
      new Uint8Array(await crypto.subtle.sign(RSA, key, new TextEncoder().encode(`${head}.${body}`))),
    );
  const token = `${head}.${body}.${signed}`;
  idTokens.add(token);
  leaks.add(token);
  return token;
}

/** A token that stays valid for two days of the tests' clock. */
function lasting(options = {}) {
  return mint({ ...options, claims: { exp: NOW / SECOND + 2 * DAY / SECOND, ...options.claims } });
}

function timestamp(millis) {
  // Firestore writes microseconds.
  return new Date(millis).toISOString().replace('Z', '456Z');
}

function deviceAt(id, at, kind = 'token') {
  if (id) leaks.add(id);
  return {
    mapValue: {
      fields: {
        id: { stringValue: id },
        kind: { stringValue: kind },
        at: { timestampValue: timestamp(at) },
      },
    },
  };
}

function device(id, ageMs, kind = 'token') {
  return deviceAt(id, NOW - ageMs, kind);
}

function pairDocument({
  members = [ME, PARTNER],
  memberValues,
  status = 'active',
  endedAt,
  push,
} = {}) {
  const fields = {
    status: { stringValue: status },
    createdAt: { timestampValue: timestamp(NOW - 30 * DAY) },
  };
  const values =
    memberValues !== undefined ? memberValues : members.map((uid) => ({ stringValue: uid }));
  if (values !== null) fields.members = { arrayValue: { values } };
  if (status === null) delete fields.status;
  if (endedAt !== undefined) fields.endedAt = { timestampValue: timestamp(endedAt) };
  if (push !== undefined) {
    fields.push = {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(push).map(([uid, devices]) => [uid, { mapValue: { fields: devices } }]),
        ),
      },
    };
  }
  return { name: `projects/${PROJECT}/databases/(default)/documents/pairs/${PAIR}`, fields };
}

const PARTNER_PHONE = 'fcm-partner-phone';
const PARTNER_TABLET = 'fcm-partner-tablet';
const MY_PHONE = 'fcm-my-phone';

function twoDevicePush() {
  return {
    [PARTNER]: { phone: device(PARTNER_PHONE, 1 * DAY), tablet: device(PARTNER_TABLET, 59 * DAY) },
    [ME]: { phone: device(MY_PHONE, 0) },
  };
}

function gate() {
  let open;
  const promise = new Promise((resolve) => {
    open = resolve;
  });
  return { promise, open };
}

/** A relay over a faked Google: the key set, Firestore, OAuth and FCM. */
async function world(options = {}) {
  const w = {
    time: NOW,
    keys: [await publicJwk(google, 'k1')],
    keysCacheControl: 'public, max-age=21600, must-revalidate',
    keysStatus: 200,
    keysUnreachable: false,
    keysGate: null,
    firestore: { status: 200, document: options.document ?? pairDocument(), unreachable: false },
    oauth: {
      status: 200,
      body: { access_token: ACCESS_TOKEN, expires_in: 3599, token_type: 'Bearer' },
      unreachable: false,
      gate: null,
    },
    fcmStatus: {},
    fcmReject: new Set(),
    fcmGate: null,
    limiter: options.limiter ?? null,
    calls: { all: [], jwks: [], firestore: [], oauth: [], fcm: [] },
    deferred: [],
  };
  worlds.push(w);

  async function fakeFetch(input, init = {}) {
    const url = new URL(typeof input === 'string' ? input : input.url);
    const call = {
      url: url.href,
      host: url.host,
      method: init.method ?? 'GET',
      headers: new Headers(init.headers),
      body: init.body,
      signal: init.signal,
      redirect: init.redirect,
    };
    w.calls.all.push(call);
    switch (url.host) {
      case 'www.googleapis.com':
        w.calls.jwks.push(call);
        if (w.keysGate) await w.keysGate;
        if (w.keysUnreachable) throw new TypeError('fetch failed');
        if (w.keysStatus !== 200) return new Response('unavailable', { status: w.keysStatus });
        return Response.json(
          { keys: w.keys },
          { headers: w.keysCacheControl === null ? {} : { 'Cache-Control': w.keysCacheControl } },
        );
      case 'firestore.googleapis.com':
        w.calls.firestore.push(call);
        if (w.firestore.unreachable) throw new TypeError('fetch failed');
        // A readable document whatever the status, so only the status decides.
        return w.firestore.raw !== undefined
          ? new Response(w.firestore.raw, { status: w.firestore.status })
          : Response.json(w.firestore.document, { status: w.firestore.status });
      case 'oauth2.googleapis.com':
        w.calls.oauth.push(call);
        if (w.oauth.gate) await w.oauth.gate;
        if (w.oauth.unreachable) throw new TypeError('fetch failed');
        return Response.json(w.oauth.body, { status: w.oauth.status });
      case 'fcm.googleapis.com': {
        w.calls.fcm.push(call);
        const message = JSON.parse(call.body).message;
        const id = message.token ?? message.fid;
        if (w.fcmGate) await w.fcmGate;
        if (w.fcmReject.has(id)) throw new TypeError('fetch failed');
        const status = w.fcmStatus[id] ?? 200;
        return Response.json(
          status === 200
            ? { name: `projects/${PROJECT}/messages/1` }
            : { error: { code: status, message: `Requested entity ${id} was not found.` } },
          { status },
        );
      }
      default:
        return new Response(null, { status: 200 });
    }
  }

  w.isolate = () =>
    createRelay({
      fetch: fakeFetch,
      now: () => w.time,
      projectId: Object.hasOwn(options, 'projectId') ? options.projectId : PROJECT,
      serviceAccount: Object.hasOwn(options, 'serviceAccount')
        ? options.serviceAccount
        : SERVICE_ACCOUNT,
      log: (line) => logs.push(line),
      bodyDeadlineMs: options.bodyDeadlineMs,
    });
  w.relay = w.isolate();

  w.poke = async ({
    token,
    body = { pair: PAIR, urgent: false },
    method = 'POST',
    path = '/poke',
    authorization,
    request,
    relay = w.relay,
    settle = true,
  } = {}) => {
    let incoming = request;
    if (!incoming) {
      const headers = new Headers();
      const bearer = authorization ?? (token === undefined ? undefined : `Bearer ${token}`);
      if (bearer !== undefined) headers.set('Authorization', bearer);
      incoming = new Request(`https://relay.test${path}`, {
        method,
        headers,
        body: method === 'POST' ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined,
      });
    }
    const response = await relay.handle(incoming, {
      defer: (promise) => w.deferred.push(promise),
      limiter: w.limiter,
    });
    assert.equal(await response.clone().text(), '', `a ${response.status} carried a body`);
    const headers = JSON.stringify([...response.headers]);
    for (const leak of leaks) assert.ok(!headers.includes(leak), `a response header names ${leak}`);
    if (response.status === 401) assert.equal(response.headers.get('WWW-Authenticate'), 'Bearer');
    if (response.status === 429) assert.match(response.headers.get('Retry-After') ?? '', /^\d+$/);
    if (settle) await Promise.all(w.deferred);
    return response;
  };

  w.sentTo = () =>
    w.calls.fcm
      .map((call) => {
        const message = JSON.parse(call.body).message;
        return message.token ?? `fid:${message.fid}`;
      })
      .sort();
  return w;
}

// ---------------------------------------------------------------- sending

test('a poke wakes the partner’s fresh devices with the exact message', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  const token = await mint();

  const response = await w.poke({ token, body: { pair: PAIR, urgent: false } });

  assert.equal(response.status, 204);
  assert.equal(w.calls.firestore.length, 1);
  assert.equal(
    w.calls.firestore[0].url,
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/pairs/${PAIR}`,
  );
  assert.equal(w.calls.firestore[0].headers.get('Authorization'), `Bearer ${token}`);
  assert.deepEqual(w.sentTo(), [PARTNER_PHONE, PARTNER_TABLET].sort());
  for (const call of w.calls.fcm) {
    assert.equal(call.method, 'POST');
    assert.equal(call.url, `https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`);
    assert.equal(call.headers.get('Authorization'), `Bearer ${ACCESS_TOKEN}`);
    const id = JSON.parse(call.body).message.token;
    assert.deepEqual(JSON.parse(call.body), {
      message: {
        token: id,
        data: { t: 'shared', p: PAIR },
        android: { priority: 'NORMAL', collapse_key: PAIR, ttl: '3600s' },
      },
    });
  }
});

test('an urgent poke is sent HIGH with the same collapse key; urgent absent reads as NORMAL', async () => {
  const w = await world({
    document: pairDocument({ push: { [PARTNER]: { phone: device(PARTNER_PHONE, DAY) } } }),
  });
  const token = await mint();

  assert.equal((await w.poke({ token, body: { pair: PAIR, urgent: true } })).status, 204);
  assert.deepEqual(JSON.parse(w.calls.fcm[0].body), {
    message: {
      token: PARTNER_PHONE,
      data: { t: 'shared', p: PAIR },
      android: { priority: 'HIGH', collapse_key: PAIR, ttl: '3600s' },
    },
  });

  assert.equal((await w.poke({ token, body: { pair: PAIR } })).status, 204);
  assert.equal(JSON.parse(w.calls.fcm[1].body).message.android.priority, 'NORMAL');
});

test('an installation id is sent as fid; another kind, an empty or an oversized id is skipped', async () => {
  const push = {
    [PARTNER]: {
      fid: device('fid-partner-phone', DAY, 'fid'),
      apns: device('apns-partner', DAY, 'apns'),
      nokind: device('no-kind-partner', DAY, ''),
      empty: device('', DAY),
      huge: device('y'.repeat(4097), DAY),
      longest: device('z'.repeat(4096), 2 * DAY),
    },
  };
  const w = await world({ document: pairDocument({ push }) });

  assert.equal((await w.poke({ token: await mint() })).status, 204);

  assert.deepEqual(w.sentTo(), ['fid:fid-partner-phone', 'z'.repeat(4096)].sort());
  const fidMessage = w.calls.fcm
    .map((call) => JSON.parse(call.body).message)
    .find((message) => message.fid !== undefined);
  assert.deepEqual(Object.keys(fidMessage).sort(), ['android', 'data', 'fid']);
});

test('stale, mine and past the fifth are not sent to', async () => {
  const push = {
    [PARTNER]: {
      a: device('fcm-age-1', 1 * DAY),
      b: device('fcm-age-2', 2 * DAY),
      c: device('fcm-age-3', 3 * DAY),
      d: device('fcm-age-4', 4 * DAY),
      e: device('fcm-age-5', 5 * DAY),
      f: device('fcm-age-6', 6 * DAY),
      old: device('fcm-age-61', 61 * DAY),
    },
    [ME]: { mine: device(MY_PHONE, 0) },
  };
  const w = await world({ document: pairDocument({ push }) });

  assert.equal((await w.poke({ token: await mint() })).status, 204);

  assert.deepEqual(w.sentTo(), ['fcm-age-1', 'fcm-age-2', 'fcm-age-3', 'fcm-age-4', 'fcm-age-5']);
});

test('sixty days is fresh to the millisecond; a device from the near future counts, a later one does not', async () => {
  const push = {
    [PARTNER]: {
      edge: device('fcm-sixty-days', 60 * DAY),
      past: device('fcm-sixty-days-and-1ms', 60 * DAY + 1),
      soon: deviceAt('fcm-in-five-minutes', NOW + 5 * MINUTE),
      later: deviceAt('fcm-in-five-minutes-and-1ms', NOW + 5 * MINUTE + 1),
    },
  };
  const w = await world({ document: pairDocument({ push }) });

  assert.equal((await w.poke({ token: await mint() })).status, 204);

  assert.deepEqual(w.sentTo(), ['fcm-in-five-minutes', 'fcm-sixty-days']);
});

test('one address registered twice is sent to once', async () => {
  const push = {
    [PARTNER]: {
      one: device(PARTNER_PHONE, DAY),
      again: device(PARTNER_PHONE, 2 * DAY),
      asFid: device(PARTNER_PHONE, 3 * DAY, 'fid'),
    },
  };
  const w = await world({ document: pairDocument({ push }) });

  assert.equal((await w.poke({ token: await mint() })).status, 204);

  assert.deepEqual(w.sentTo(), [PARTNER_PHONE, `fid:${PARTNER_PHONE}`]);
});

test('the partner pokes back and reaches only my device', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });

  const response = await w.poke({ token: await mint({ claims: { sub: PARTNER } }) });

  assert.equal(response.status, 204);
  assert.deepEqual(w.sentTo(), [MY_PHONE]);
});

test('no push field → 204, and no access token is minted', async () => {
  const w = await world({ document: pairDocument() });

  assert.equal((await w.poke({ token: await mint() })).status, 204);
  assert.equal(w.calls.oauth.length, 0);
  assert.equal(w.calls.fcm.length, 0);
});

test('only my own devices registered → 204, nothing sent', async () => {
  const w = await world({ document: pairDocument({ push: { [ME]: { phone: device(MY_PHONE, 0) } } }) });

  assert.equal((await w.poke({ token: await mint() })).status, 204);
  assert.equal(w.calls.oauth.length, 0);
  assert.equal(w.calls.fcm.length, 0);
});

test('an ended pair is served for one day after endedAt, to the millisecond', async () => {
  for (const [endedAt, served] of [
    [NOW - DAY, true],
    [NOW - DAY - 1, false],
    [NOW, true],
    [NOW + SECOND, false],
  ]) {
    const w = await world({ document: pairDocument({ status: 'ended', endedAt, push: twoDevicePush() }) });
    const response = await w.poke({ token: await mint(), body: { pair: PAIR, urgent: true } });
    assert.equal(response.status, 204);
    assert.equal(w.calls.fcm.length, served ? 2 : 0, `ended at ${new Date(endedAt).toISOString()}`);
    if (!served) assert.equal(w.calls.oauth.length, 0);
  }
});

test('an ended pair without endedAt, or a status that is neither active nor ended, is not served', async () => {
  for (const document of [
    pairDocument({ status: 'ended', push: twoDevicePush() }),
    pairDocument({ status: 'paused', push: twoDevicePush() }),
    pairDocument({ status: null, push: twoDevicePush() }),
  ]) {
    const w = await world({ document });
    assert.equal((await w.poke({ token: await mint() })).status, 204);
    assert.equal(w.calls.fcm.length, 0);
  }
});

// ------------------------------------------------------------- membership

for (const [name, status] of [
  ['Firestore answering 403', 403],
  ['Firestore answering 404', 404],
]) {
  test(`${name} → 403, and nothing is sent`, async () => {
    const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
    w.firestore.status = status;

    assert.equal((await w.poke({ token: await mint() })).status, 403);
    assert.equal(w.calls.oauth.length, 0);
    assert.equal(w.calls.fcm.length, 0);
  });
}

for (const [name, setUp, line] of [
  ['answering 500', (w) => (w.firestore.status = 500), 'relay: firestore 500'],
  ['answering 401', (w) => (w.firestore.status = 401), 'relay: firestore 401'],
  ['redirecting', (w) => (w.firestore.status = 302), 'relay: firestore 302'],
  ['unreachable', (w) => (w.firestore.unreachable = true), 'relay: firestore unreachable'],
  ['answering 200 with no document', (w) => (w.firestore.raw = 'not json'), 'relay: firestore unreadable'],
]) {
  test(`Firestore ${name} → 503 with one log line, and nothing is sent`, async () => {
    const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
    setUp(w);

    assert.equal((await w.poke({ token: await mint() })).status, 503);
    assert.deepEqual(logs, [line]);
    assert.equal(w.calls.oauth.length, 0);
    assert.equal(w.calls.fcm.length, 0);
  });
}

for (const [name, document] of [
  ['a caller not in members', pairDocument({ members: [PARTNER, 'uid-third'], push: twoDevicePush() })],
  ['one member', pairDocument({ members: [ME], push: twoDevicePush() })],
  ['three members', pairDocument({ members: [ME, PARTNER, 'uid-third'], push: twoDevicePush() })],
  ['the caller twice', pairDocument({ members: [ME, ME], push: twoDevicePush() })],
  ['an empty member', pairDocument({ members: [ME, ''], push: twoDevicePush() })],
  [
    'a member that is not a string',
    pairDocument({ memberValues: [{ stringValue: ME }, { integerValue: '7' }], push: twoDevicePush() }),
  ],
  ['no members', pairDocument({ memberValues: null, push: twoDevicePush() })],
]) {
  test(`${name} → 403, and nothing is sent`, async () => {
    const w = await world({ document });

    assert.equal((await w.poke({ token: await mint() })).status, 403);
    assert.equal(w.calls.oauth.length, 0);
    assert.equal(w.calls.fcm.length, 0);
  });
}

// ---------------------------------------------------------- the ID token

test('the OAuth assertion is the service account’s, for messaging only', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });

  await w.poke({ token: await mint() });

  assert.equal(w.calls.oauth.length, 1);
  const call = w.calls.oauth[0];
  assert.equal(call.method, 'POST');
  assert.equal(call.url, 'https://oauth2.googleapis.com/token');
  assert.equal(call.headers.get('Content-Type'), 'application/x-www-form-urlencoded');
  const form = new URLSearchParams(call.body);
  assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  const [head, body, signature] = form.get('assertion').split('.');
  assert.ok(
    await crypto.subtle.verify(
      RSA,
      account.publicKey,
      Buffer.from(signature, 'base64url'),
      new TextEncoder().encode(`${head}.${body}`),
    ),
  );
  assert.deepEqual(JSON.parse(Buffer.from(head, 'base64url')), {
    alg: 'RS256',
    typ: 'JWT',
    kid: 'sa-key-1',
  });
  const seconds = NOW / SECOND;
  assert.deepEqual(JSON.parse(Buffer.from(body, 'base64url')), {
    iss: 'relay@test-project.iam.gserviceaccount.com',
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: seconds,
    exp: seconds + 3600,
  });
});

test('a token whose header and payload are not canonically encoded is verified as sent', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  const seconds = NOW / SECOND;
  const token = await mint({
    headerText: '{ "typ":"JWT",  "kid": "k1",\n"alg" : "RS256" }',
    payloadText:
      `{"sub":"${ME}", "aud":"${PROJECT}", "iss":"https://securetoken.google.com/${PROJECT}",` +
      ` "exp":${seconds + 3000}, "iat":${seconds - 60}, "auth_time":${seconds - 3600} }`,
  });

  assert.equal((await w.poke({ token })).status, 204);
  assert.equal(w.calls.fcm.length, 2);
});

for (const [name, options] of [
  ['a bad signature', { key: stranger.privateKey }],
  ['a garbled signature', { signature: 'AAAA' }],
  ['an expired token', { claims: { exp: NOW / SECOND - 1 } }],
  ['a token expiring this second', { claims: { exp: NOW / SECOND } }],
  ['exp as a numeric string', { claims: { exp: String(NOW / SECOND + 3000) } }],
  ['a wrong aud', { claims: { aud: 'another-project' } }],
  ['an aud array holding the project', { claims: { aud: [PROJECT] } }],
  ['a wrong iss', { claims: { iss: 'https://securetoken.google.com/another-project' } }],
  ['iat in the future', { claims: { iat: NOW / SECOND + 61 } }],
  ['no iat', { claims: { iat: undefined } }],
  ['auth_time in the future', { claims: { auth_time: NOW / SECOND + 61 } }],
  ['no auth_time', { claims: { auth_time: undefined } }],
  ['an empty sub', { claims: { sub: '' } }],
  ['a numeric sub', { claims: { sub: 42 } }],
  ['alg none', { header: { alg: 'none' } }],
  ['alg HS256', { header: { alg: 'HS256' } }],
  ['no kid', { header: { kid: undefined } }],
]) {
  test(`${name} → 401, and Firestore is never asked`, async () => {
    const w = await world({ document: pairDocument({ push: twoDevicePush() }) });

    assert.equal((await w.poke({ token: await mint(options) })).status, 401);
    assert.equal(w.calls.firestore.length, 0);
    assert.equal(w.calls.fcm.length, 0);
  });
}

test('within the 60 s skew, iat and auth_time pass', async () => {
  const w = await world();
  const response = await w.poke({
    token: await mint({ claims: { iat: NOW / SECOND + 60, auth_time: NOW / SECOND + 60 } }),
  });
  assert.equal(response.status, 204);
});

test('a token past 8192 characters → 401 before the key set is fetched; a long one under it passes', async () => {
  const w = await world();
  const long = await mint({ claims: { pad: 'p'.repeat(5500) } });
  assert.ok(long.length > 7000 && long.length <= 8192, String(long.length));
  assert.equal((await w.poke({ token: long })).status, 204);

  const w2 = await world();
  const over = await mint({ claims: { pad: 'p'.repeat(6000) } });
  assert.ok(over.length > 8192, String(over.length));
  assert.equal((await w2.poke({ token: over })).status, 401);
  assert.equal(w2.calls.jwks.length, 0);
});

for (const [name, authorization] of [
  ['no Authorization', undefined],
  ['a Basic credential', 'Basic dXNlcjpwYXNz'],
  ['a bearer that is not a JWT', 'Bearer not-a-jwt'],
  ['an empty bearer', 'Bearer '],
]) {
  test(`${name} → 401, checked before the body is read`, async () => {
    const w = await world();
    const response = await w.poke({ authorization, body: 'x'.repeat(2000) });
    assert.equal(response.status, 401);
    assert.equal(w.calls.jwks.length, 0);
    assert.equal(w.calls.firestore.length, 0);
  });
}

test('the bearer scheme is matched in any case', async () => {
  const w = await world();
  const token = await mint();
  assert.equal((await w.poke({ authorization: `bearer ${token}` })).status, 204);
  assert.equal((await w.poke({ authorization: `BEARER ${token}` })).status, 204);
});

// ------------------------------------------------------------ the key set

test('the key set and the access token are each fetched once across two pokes', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  const token = await mint();

  assert.equal((await w.poke({ token })).status, 204);
  w.time += 30 * SECOND;
  assert.equal((await w.poke({ token })).status, 204);

  assert.equal(w.calls.jwks.length, 1);
  assert.equal(w.calls.oauth.length, 1);
  assert.equal(w.calls.fcm.length, 4);
});

test('two pokes on a cold isolate share one key-set fetch', async () => {
  const w = await world();
  const keys = gate();
  w.keysGate = keys.promise;
  const token = await mint();

  const pokes = [w.poke({ token }), w.poke({ token })];
  await new Promise((resolve) => setTimeout(resolve, 10));
  keys.open();
  const responses = await Promise.all(pokes);

  assert.deepEqual(responses.map((response) => response.status), [204, 204]);
  assert.equal(w.calls.jwks.length, 1);
});

for (const [name, cacheControl, heldS, refetchS] of [
  ['its max-age', 'public, max-age=120', 119, 121],
  ['an hour without a max-age', null, 3599, 3601],
  ['a day at most', 'max-age=999999', 86399, 86401],
]) {
  test(`the key set is held for ${name}`, async () => {
    const w = await world();
    w.keysCacheControl = cacheControl;
    const token = await lasting();

    assert.equal((await w.poke({ token })).status, 204);
    w.time = NOW + heldS * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.jwks.length, 1);
    w.time = NOW + refetchS * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.jwks.length, 2);
  });
}

test('a rotated key is found by one refetch, at most once a minute', async () => {
  const w = await world();
  assert.equal((await w.poke({ token: await lasting() })).status, 204);
  w.keys.push(await publicJwk(rotated, 'k2'));
  const rotatedToken = await lasting({ header: { kid: 'k2' }, key: rotated.privateKey });

  w.time = NOW + 59 * SECOND;
  assert.equal((await w.poke({ token: rotatedToken })).status, 401);
  assert.equal(w.calls.jwks.length, 1);

  w.time = NOW + 60 * SECOND;
  assert.equal((await w.poke({ token: rotatedToken })).status, 204);
  assert.equal(w.calls.jwks.length, 2);
});

test('twenty unknown-kid requests make one refetch, and twenty more in the minute none', async () => {
  const w = await world();
  assert.equal((await w.poke({ token: await lasting() })).status, 204);
  w.time = NOW + 61 * SECOND;
  const unknown = await lasting({ header: { kid: 'k9' } });

  const responses = await Promise.all(Array.from({ length: 20 }, () => w.poke({ token: unknown })));
  assert.ok(responses.every((response) => response.status === 401));
  assert.equal(w.calls.jwks.length, 2);

  for (let i = 0; i < 20; i += 1) {
    w.time += 2 * SECOND;
    assert.equal((await w.poke({ token: unknown })).status, 401);
  }
  assert.equal(w.calls.jwks.length, 2);
  assert.equal(w.calls.firestore.length, 1);
});

test('an unknown kid on a cold isolate fetches the set once, not twice', async () => {
  const w = await world();
  assert.equal((await w.poke({ token: await mint({ header: { kid: 'k9' } }) })).status, 401);
  assert.equal(w.calls.jwks.length, 1);
});

for (const [name, setUp, line] of [
  ['unreachable', (w) => (w.keysUnreachable = true), 'relay: keys unreachable'],
  ['answering 500', (w) => (w.keysStatus = 500), 'relay: keys 500'],
]) {
  test(`the key endpoint ${name} → 503, retried no sooner than ten seconds`, async () => {
    const w = await world();
    setUp(w);
    const token = await mint();

    assert.equal((await w.poke({ token })).status, 503);
    assert.deepEqual(logs, [line]);
    w.time = NOW + 9 * SECOND;
    assert.equal((await w.poke({ token })).status, 503);
    assert.equal(w.calls.jwks.length, 1);
    assert.equal(w.calls.firestore.length, 0);

    w.keysUnreachable = false;
    w.keysStatus = 200;
    w.time = NOW + 10 * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.jwks.length, 2);
  });
}

// ------------------------------------------------------- the access token

test('the access token is held until a minute before it expires', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  const token = await lasting();

  assert.equal((await w.poke({ token })).status, 204);
  // 3599 s from NOW, less the minute: held until NOW + 3539 s.
  w.time = NOW + 3538 * SECOND;
  assert.equal((await w.poke({ token })).status, 204);
  assert.equal(w.calls.oauth.length, 1);
  w.time = NOW + 3540 * SECOND;
  assert.equal((await w.poke({ token })).status, 204);
  assert.equal(w.calls.oauth.length, 2);
});

for (const [name, expiresIn] of [
  ['expires_in over an hour is held as an hour', 7200],
  ['a missing expires_in is held as an hour', undefined],
]) {
  test(name, async () => {
    const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
    w.oauth.body = { access_token: ACCESS_TOKEN, expires_in: expiresIn };
    const token = await lasting();

    assert.equal((await w.poke({ token })).status, 204);
    w.time = NOW + 3539 * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.oauth.length, 1);
    w.time = NOW + 3541 * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.oauth.length, 2);
  });
}

test('concurrent pokes share one OAuth exchange', { timeout: 5000 }, async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  const exchange = gate();
  w.oauth.gate = exchange.promise;
  const token = await mint();

  const responses = await Promise.all([
    w.poke({ token, settle: false }),
    w.poke({ token, settle: false }),
  ]);
  assert.deepEqual(responses.map((response) => response.status), [204, 204]);
  await new Promise((resolve) => setTimeout(resolve, 10));
  exchange.open();
  await Promise.all(w.deferred);

  assert.equal(w.calls.oauth.length, 1);
  assert.equal(w.calls.fcm.length, 4);
});

for (const [name, setUp, line] of [
  ['answering 500', (w) => (w.oauth.status = 500), 'relay: oauth 500'],
  ['unreachable', (w) => (w.oauth.unreachable = true), 'relay: oauth unreachable'],
  ['answering without a token', (w) => (w.oauth.body = { token_type: 'Bearer' }), 'relay: oauth unreadable'],
]) {
  test(`an OAuth exchange ${name} still answers 204, then waits thirty seconds`, async () => {
    const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
    setUp(w);
    const token = await mint();

    assert.equal((await w.poke({ token })).status, 204);
    assert.deepEqual(logs, [line]);
    assert.equal(w.calls.fcm.length, 0);

    w.time = NOW + 29 * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.oauth.length, 1);

    w.oauth = { status: 200, body: { access_token: ACCESS_TOKEN, expires_in: 3599 }, gate: null };
    w.time = NOW + 30 * SECOND;
    assert.equal((await w.poke({ token })).status, 204);
    assert.equal(w.calls.oauth.length, 2);
    assert.equal(w.calls.fcm.length, 2);
  });
}

// -------------------------------------------------------------------- FCM

test('FCM answering 404 for one device still sends to the other and answers 204', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  w.fcmStatus[PARTNER_TABLET] = 404;

  assert.equal((await w.poke({ token: await mint() })).status, 204);
  assert.deepEqual(w.sentTo(), [PARTNER_PHONE, PARTNER_TABLET].sort());
  assert.deepEqual(logs, ['relay: fcm 200,404']);
});

test('an FCM fetch that fails outright stays inside the deferred work', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  w.fcmReject.add(PARTNER_PHONE);

  assert.equal((await w.poke({ token: await mint() })).status, 204);
  assert.deepEqual(w.sentTo(), [PARTNER_PHONE, PARTNER_TABLET].sort());
  assert.deepEqual(logs, ['relay: fcm 0,200']);
});

test('FCM refusing the credential drops it, so the next poke mints a new one', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  w.fcmStatus[PARTNER_PHONE] = 401;
  const token = await mint();

  assert.equal((await w.poke({ token })).status, 204);
  delete w.fcmStatus[PARTNER_PHONE];
  assert.equal((await w.poke({ token })).status, 204);

  assert.equal(w.calls.oauth.length, 2);
});

test('the answer comes before a hanging FCM send finishes', { timeout: 5000 }, async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  const fcm = gate();
  w.fcmGate = fcm.promise;
  let sent = false;

  const response = await w.poke({ token: await mint(), settle: false });
  const deferred = Promise.all(w.deferred).then(() => {
    sent = true;
  });
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.equal(response.status, 204);
  assert.equal(w.deferred.length, 1);
  assert.equal(sent, false);
  fcm.open();
  await deferred;
  assert.equal(w.calls.fcm.length, 2);
});

// -------------------------------------------------------------- the limit

test('the seventh poke in a minute → 429; the next minute is open again', async () => {
  const w = await world({ document: pairDocument({ push: twoDevicePush() }) });
  w.time = NOW + 5 * SECOND;
  const token = await mint();

  for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token })).status, 204, `poke ${i + 1}`);
  const refused = await w.poke({ token });
  assert.equal(refused.status, 429);
  assert.equal(refused.headers.get('Retry-After'), '55');
  assert.equal(w.calls.firestore.length, 6);

  // The partner has a count of their own.
  assert.equal((await w.poke({ token: await mint({ claims: { sub: PARTNER } }) })).status, 204);

  w.time = NOW + 60 * SECOND;
  assert.equal((await w.poke({ token })).status, 204);
});

test('twelve pokes across a minute boundary pass; the thirteenth does not', async () => {
  const w = await world();
  const token = await mint();

  w.time = NOW + 50 * SECOND;
  for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token })).status, 204);
  w.time = NOW + 61 * SECOND;
  for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token })).status, 204);
  const refused = await w.poke({ token });
  assert.equal(refused.status, 429);
  assert.equal(refused.headers.get('Retry-After'), '59');
});

test('sixty pokes an hour, then 429 until the hour turns', async () => {
  const w = await world();
  const token = await lasting();

  for (let minute = 0; minute < 10; minute += 1) {
    w.time = NOW + minute * MINUTE + 5 * SECOND;
    for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token })).status, 204);
  }
  w.time = NOW + 10 * MINUTE + 5 * SECOND;
  const refused = await w.poke({ token });
  assert.equal(refused.status, 429);
  assert.equal(refused.headers.get('Retry-After'), String(3600 - 605));

  w.time = NOW + 60 * MINUTE;
  assert.equal((await w.poke({ token })).status, 204);
});

test('with the binding, two isolates share one count, keyed by a hash of the uid', async () => {
  const counts = new Map();
  const keys = [];
  const limiter = async (key) => {
    keys.push(key);
    counts.set(key, (counts.get(key) ?? 0) + 1);
    return counts.get(key) <= 6;
  };
  const w = await world({ limiter });
  const other = w.isolate();
  const token = await mint();

  for (let i = 0; i < 4; i += 1) assert.equal((await w.poke({ token })).status, 204);
  for (let i = 0; i < 2; i += 1) assert.equal((await w.poke({ token, relay: other })).status, 204);
  const refused = await w.poke({ token, relay: other });
  assert.equal(refused.status, 429);
  assert.equal(refused.headers.get('Retry-After'), '60');
  assert.deepEqual(new Set(keys), new Set([sha256Hex(ME)]));
});

test('without the binding, each isolate counts its own minute (best effort)', async () => {
  const w = await world();
  const other = w.isolate();
  const token = await mint();

  for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token })).status, 204);
  for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token, relay: other })).status, 204);
  assert.equal((await w.poke({ token })).status, 429);
  assert.equal((await w.poke({ token, relay: other })).status, 429);
});

test('a binding that throws lets the poke through with one log line', async () => {
  const w = await world({
    limiter: async () => {
      throw new Error('binding down');
    },
  });

  assert.equal((await w.poke({ token: await mint() })).status, 204);
  assert.deepEqual(logs, ['relay: limit unavailable']);
});

test('the counts hold 1024 callers, forgetting the least recent', async () => {
  const w = await world();
  const token = await mint();
  for (let i = 0; i < 6; i += 1) assert.equal((await w.poke({ token })).status, 204);
  assert.equal((await w.poke({ token })).status, 429);

  for (let i = 0; i < 1024; i += 1) {
    const response = await w.poke({ token: await mint({ claims: { sub: `uid-caller-${i}` } }) });
    assert.equal(response.status, 403);
  }

  assert.equal((await w.poke({ token })).status, 204);
});

// --------------------------------------------------------------- the body

test('a body of exactly 1 KB is taken; one byte more → 400', async () => {
  const w = await world();
  const token = await mint();
  const json = JSON.stringify({ pair: PAIR, urgent: false });
  const fits = json.slice(0, -1) + ' '.repeat(1024 - json.length) + '}';
  assert.equal(new TextEncoder().encode(fits).length, 1024);

  assert.equal((await w.poke({ token, body: fits })).status, 204);
  const over = json.slice(0, -1) + ' '.repeat(1025 - json.length) + '}';
  assert.equal((await w.poke({ token, body: over })).status, 400);
  assert.equal(w.calls.firestore.length, 1);
});

test('a declared Content-Length over 1 KB → 400, whatever the body', async () => {
  const w = await world();
  const token = await mint();
  const request = {
    url: 'https://relay.test/poke',
    method: 'POST',
    headers: new Headers({ Authorization: `Bearer ${token}`, 'Content-Length': '2048' }),
    body: new Blob([JSON.stringify({ pair: PAIR })]).stream(),
  };

  assert.equal((await w.poke({ request })).status, 400);
  assert.equal(w.calls.firestore.length, 0);
});

test('a body that never finishes → 400 at the deadline', async () => {
  const w = await world({ bodyDeadlineMs: 20 });
  const token = await mint();
  const request = {
    url: 'https://relay.test/poke',
    method: 'POST',
    headers: new Headers({ Authorization: `Bearer ${token}` }),
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode('{"pair":'));
      },
      pull() {
        return new Promise(() => {});
      },
    }),
  };

  assert.equal((await w.poke({ request })).status, 400);
  assert.equal(w.calls.firestore.length, 0);
});

for (const [name, body] of [
  ['not JSON', '{pair: nope'],
  ['a JSON array', '[]'],
  ['JSON null', 'null'],
  ['an empty body', ''],
  ['no pair', { urgent: true }],
  ['an empty pair id', { pair: '' }],
  ['a pair id with a slash', { pair: 'abc/def' }],
  ['a pair id with a dot', { pair: '..' }],
  ['a pair id of 129 characters', { pair: 'a'.repeat(129) }],
  ['a numeric pair', { pair: 12 }],
  ['urgent as a string', { pair: PAIR, urgent: 'yes' }],
  ['urgent as null', { pair: PAIR, urgent: null }],
  ['an extra field', { pair: PAIR, urgent: false, uid: PARTNER }],
]) {
  test(`${name} → 400`, async () => {
    const w = await world();
    assert.equal((await w.poke({ token: await mint(), body })).status, 400);
    assert.equal(w.calls.firestore.length, 0);
  });
}

test('a pair id of 128 characters is taken', async () => {
  const w = await world();
  assert.equal((await w.poke({ token: await mint(), body: { pair: 'a'.repeat(128) } })).status, 204);
});

test('another path → 404; another method → 405, with no CORS', async () => {
  const w = await world();
  const token = await mint();

  assert.equal((await w.poke({ token, path: '/' })).status, 404);
  assert.equal((await w.poke({ token, path: '/poke/' })).status, 404);
  assert.equal((await w.poke({ token, path: '/pokes' })).status, 404);
  for (const method of ['GET', 'PUT', 'DELETE', 'OPTIONS']) {
    const response = await w.poke({ token, method });
    assert.equal(response.status, 405, method);
    assert.equal(response.headers.get('Allow'), 'POST');
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
  }
  assert.equal(w.calls.jwks.length, 0);
  assert.equal(w.calls.firestore.length, 0);
});

// ------------------------------------------------------- the configuration

for (const [name, serviceAccount] of [
  ['a missing secret', undefined],
  ['a secret that is not JSON', 'not json'],
  ['a secret without a private key', JSON.stringify({ client_email: 'a@b.c' })],
  ['a secret with an unreadable key', serviceAccountJson('abc')],
  [
    'a secret with a PKCS#1 label',
    serviceAccountJson(ACCOUNT_PEM.replace(/PRIVATE KEY/g, 'RSA PRIVATE KEY')),
  ],
  [
    'a secret whose key body is not a key',
    serviceAccountJson('-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n'),
  ],
]) {
  test(`${name} → 500 before any check of the caller, logged once`, async () => {
    const w = await world({ serviceAccount, document: pairDocument({ push: twoDevicePush() }) });

    assert.equal((await w.poke({ token: await mint() })).status, 500);
    assert.equal((await w.poke({})).status, 500);
    assert.deepEqual(logs, ['relay: bad service account']);
    assert.equal(w.calls.all.length, 0);
  });
}

test('a project id that is missing → 500, logged once', async () => {
  const w = await world({ projectId: undefined });
  assert.equal((await w.poke({ token: await mint() })).status, 500);
  assert.equal((await w.poke({})).status, 500);
  assert.deepEqual(logs, ['relay: bad project id']);
  assert.equal(w.calls.all.length, 0);
});

test('a key whose newlines arrived as a literal \\n is read', async () => {
  const w = await world({
    serviceAccount: serviceAccountJson(ACCOUNT_PEM.replace(/\n/g, '\\n')),
    document: pairDocument({ push: twoDevicePush() }),
  });

  assert.equal((await w.poke({ token: await mint() })).status, 204);
  assert.equal(w.calls.fcm.length, 2);
});
