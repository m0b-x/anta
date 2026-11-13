// The push relay: one paired phone pokes the other awake (record
// docs/cloud-shared-freshness.md §7, §8). A poke carries nothing; the woken
// phone reads the truth from the cloud. The relay reads the pair with the
// caller's own sign-in, so Firestore's rules decide who may wake whom, and
// its own credential can only send messages.
//
// Everything the platform provides is injected — fetch, the clock, the rate
// limit binding, waitUntil — so this module runs unchanged under Node's test
// runner and in the Worker. All state lives in this instance's memory, one
// per isolate; nothing is written to a cache other isolates read. WebCrypto
// only; no dependency at run time.

const JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const OAUTH_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const RS256 = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

const MAX_BODY_BYTES = 1024;
const PAIR_ID = /^[A-Za-z0-9_-]{1,128}$/;
const PROJECT_ID = /^[a-z0-9-]{1,64}$/;
const BEARER = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/i;
// A Firebase ID token is about a kilobyte; anything far past that is not one.
const MAX_ID_TOKEN_CHARS = 8192;
const CLOCK_SKEW_S = 60;
const POKES_PER_MINUTE = 6;
const POKES_PER_HOUR = 60;
// Bounds the per-caller counts; past it the least recent caller is forgotten.
const MAX_COUNTED_CALLERS = 1024;
const ENDED_PAIR_SERVED_MS = DAY;
const DEVICE_FRESH_MS = 60 * DAY;
const DEVICE_FUTURE_MS = 5 * MINUTE;
const DEVICE_KINDS = ['fid', 'token'];
const MAX_TARGETS = 5;
const MAX_DEVICE_ID_CHARS = 4096;
const ACCESS_TOKEN_LIFETIME_S = 3600;
const ACCESS_TOKEN_MARGIN_S = 60;
const OAUTH_RETRY_GAP_MS = 30 * SECOND;
// Google always states a max-age; these bound a missing or absurd one.
const DEFAULT_KEYS_TTL_S = 3600;
const MAX_KEYS_TTL_S = DAY / SECOND;
// An unknown kid may be a rotated key, but anyone can send one: refetching
// is held to once a minute so no caller can make the Worker call Google per
// request. A failed fetch is retried no sooner than the second gap.
const KEYS_REFETCH_GAP_MS = MINUTE;
const KEYS_RETRY_GAP_MS = 10 * SECOND;
const DEFAULT_FETCH_TIMEOUT_MS = 5 * SECOND;
const DEFAULT_BODY_DEADLINE_MS = 5 * SECOND;

/** An upstream Google service could not answer; the caller gets 503. */
class Unavailable extends Error {}

/**
 * Builds the relay. `fetch` and `now` (milliseconds) are the platform's;
 * `serviceAccount` is the service account's JSON text; `log` receives only
 * counts and status codes. Each request is handled with
 * `handle(request, {defer, limiter})`: `defer` is the platform's waitUntil,
 * `limiter(key)` the rate limit binding (six a minute per key), resolving to
 * whether the poke may go; without it the minute is counted in memory.
 */
export function createRelay({
  fetch,
  now,
  projectId,
  serviceAccount,
  log = () => {},
  fetchTimeoutMs = DEFAULT_FETCH_TIMEOUT_MS,
  bodyDeadlineMs = DEFAULT_BODY_DEADLINE_MS,
}) {
  let signer = null;
  let projectLogged = false;

  let keySet = null;
  let keysFetchedAt = -Infinity;
  let keysFailed = false;
  let keysInFlight = null;

  let accessToken = null;
  let exchangeInFlight = null;
  let oauthFailedAt = -Infinity;

  const minuteCounts = new BoundedMap(MAX_COUNTED_CALLERS);
  const hourCounts = new BoundedMap(MAX_COUNTED_CALLERS);

  async function handle(request, { defer = () => {}, limiter = null } = {}) {
    try {
      return await serve(request, defer, limiter);
    } catch (error) {
      if (error instanceof Unavailable) return reply(503);
      log('relay: unexpected failure');
      return reply(500);
    }
  }

  async function serve(request, defer, limiter) {
    if (new URL(request.url).pathname !== '/poke') return reply(404);
    if (request.method !== 'POST') return reply(405, { Allow: 'POST' });

    // Checked before anything about the caller, so a 500 says nothing about
    // who is asking or what their partner has.
    if (!(await configured())) return reply(500);

    const match = BEARER.exec(request.headers.get('Authorization') ?? '');
    if (!match || match[1].length > MAX_ID_TOKEN_CHARS) return unauthorized();
    const idToken = match[1];

    const poke = await readPoke(request);
    if (!poke) return reply(400);

    const sub = await verifyIdToken(idToken);
    if (!sub) return unauthorized();

    const wait = await admit(sub, limiter);
    if (wait > 0) return reply(429, { 'Retry-After': String(wait) });

    const pair = await readPair(poke.pair, idToken);
    if (!pair || !pair.members.includes(sub)) return reply(403);

    // From here the caller is a member, and the answer is 204 at once: what
    // the partner has, and how long sending to it takes, stays unseen.
    defer(wake(pair, sub, poke));
    return reply(204);
  }

  async function configured() {
    if (typeof projectId !== 'string' || !PROJECT_ID.test(projectId)) {
      if (!projectLogged) log('relay: bad project id');
      projectLogged = true;
      return false;
    }
    signer ??= importSigner(serviceAccount).catch((error) => {
      log('relay: bad service account');
      throw error;
    });
    try {
      await signer;
      return true;
    } catch {
      return false;
    }
  }

  async function readPoke(request) {
    const bytes = await readBody(request);
    if (!bytes) return null;
    let body;
    try {
      body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    } catch {
      return null;
    }
    if (body === null || typeof body !== 'object' || Array.isArray(body)) return null;
    if (!Object.keys(body).every((key) => key === 'pair' || key === 'urgent')) return null;
    if (typeof body.pair !== 'string' || !PAIR_ID.test(body.pair)) return null;
    if (body.urgent !== undefined && typeof body.urgent !== 'boolean') return null;
    return { pair: body.pair, urgent: body.urgent === true };
  }

  // Reads at most one byte past the limit, within a deadline, so neither an
  // oversized nor a trickled body holds the Worker.
  async function readBody(request) {
    const declared = request.headers.get('Content-Length');
    if (declared !== null && !(Number(declared) <= MAX_BODY_BYTES)) return null;
    if (!request.body) return new Uint8Array(0);
    const reader = request.body.getReader();
    let timer;
    const expired = new Promise((resolve) => {
      timer = setTimeout(() => resolve(null), bodyDeadlineMs);
    });
    const chunks = [];
    let size = 0;
    try {
      for (;;) {
        const result = await Promise.race([reader.read(), expired]);
        if (result === null) {
          reader.cancel().catch(() => {});
          return null;
        }
        if (result.done) break;
        size += result.value.byteLength;
        if (size > MAX_BODY_BYTES) {
          reader.cancel().catch(() => {});
          return null;
        }
        chunks.push(result.value);
      }
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return bytes;
  }

  /** The verified `sub` of a Firebase ID token, or null. */
  async function verifyIdToken(token) {
    const [encodedHeader, encodedPayload, encodedSignature] = token.split('.');
    const header = decodeJson(encodedHeader);
    if (!header || header.alg !== 'RS256' || typeof header.kid !== 'string') return null;
    const jwk = await findKey(header.kid);
    if (!jwk) return null;
    const signature = decodeBase64Url(encodedSignature);
    if (!signature) return null;
    let verified;
    try {
      const key = await crypto.subtle.importKey(
        'jwk',
        { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
        RS256,
        false,
        ['verify'],
      );
      // Over the bytes as sent, never a re-encoding of what was decoded.
      verified = await crypto.subtle.verify(
        RS256,
        key,
        signature,
        new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
      );
    } catch {
      return null;
    }
    if (!verified) return null;

    // Only now is the payload the issuer's word.
    const claims = decodeJson(encodedPayload);
    if (!claims) return null;
    const seconds = now() / SECOND;
    if (claims.aud !== projectId) return null;
    if (claims.iss !== `https://securetoken.google.com/${projectId}`) return null;
    if (!Number.isFinite(claims.exp) || claims.exp <= seconds) return null;
    if (!Number.isFinite(claims.iat) || claims.iat > seconds + CLOCK_SKEW_S) return null;
    if (!Number.isFinite(claims.auth_time) || claims.auth_time > seconds + CLOCK_SKEW_S) {
      return null;
    }
    if (typeof claims.sub !== 'string' || !claims.sub) return null;
    return claims.sub;
  }

  // The key set is the trust anchor: it stays in this isolate's memory, one
  // fetch in flight is shared by every request that needs it, and a failed
  // fetch answers 503 rather than 401.
  async function findKey(kid) {
    if (keySet === null || now() >= keySet.until) await refreshKeys();
    let jwk = lookupKey(kid);
    if (!jwk && (keysInFlight !== null || now() - keysFetchedAt >= KEYS_REFETCH_GAP_MS)) {
      await refreshKeys();
      jwk = lookupKey(kid);
    }
    if (!jwk || jwk.kty !== 'RSA' || typeof jwk.n !== 'string' || typeof jwk.e !== 'string') {
      return null;
    }
    return jwk;
  }

  function lookupKey(kid) {
    return keySet?.keys.find((key) => key?.kid === kid) ?? null;
  }

  function refreshKeys() {
    keysInFlight ??= fetchKeys().finally(() => {
      keysInFlight = null;
    });
    return keysInFlight;
  }

  async function fetchKeys() {
    if (keysFailed && now() - keysFetchedAt < KEYS_RETRY_GAP_MS) throw new Unavailable();
    keysFetchedAt = now();
    keysFailed = true;
    let response;
    try {
      response = await fetch(JWKS_URL, { signal: AbortSignal.timeout(fetchTimeoutMs) });
    } catch {
      log('relay: keys unreachable');
      throw new Unavailable();
    }
    if (!response.ok) {
      log(`relay: keys ${response.status}`);
      throw new Unavailable();
    }
    const body = await response.json().catch(() => null);
    if (!Array.isArray(body?.keys)) {
      log('relay: keys unreadable');
      throw new Unavailable();
    }
    const maxAge = /(?:^|[,\s])max-age=(\d+)/i.exec(response.headers.get('Cache-Control') ?? '');
    const ttl = maxAge ? Math.min(Number(maxAge[1]), MAX_KEYS_TTL_S) : DEFAULT_KEYS_TTL_S;
    keysFailed = false;
    keySet = { keys: body.keys, until: now() + ttl * SECOND };
  }

  // Answers 0 when the poke may go, else the seconds to wait. The binding
  // counts per Cloudflare location and the memory per isolate, and neither
  // is atomic across concurrent requests: best effort, bounded overall by
  // the hourly cap of each isolate.
  async function admit(sub, limiter) {
    const key = await sha256Hex(sub);
    const time = now();
    const hour = Math.floor(time / HOUR);
    if (countIn(hourCounts, key, hour) >= POKES_PER_HOUR) {
      return Math.ceil(((hour + 1) * HOUR - time) / SECOND);
    }
    if (limiter) {
      let allowed = true;
      try {
        allowed = await limiter(key);
      } catch {
        log('relay: limit unavailable');
      }
      if (!allowed) return MINUTE / SECOND;
    } else {
      const minute = Math.floor(time / MINUTE);
      const count = countIn(minuteCounts, key, minute);
      if (count >= POKES_PER_MINUTE) return Math.ceil(((minute + 1) * MINUTE - time) / SECOND);
      minuteCounts.set(key, { window: minute, count: count + 1 });
    }
    hourCounts.set(key, { window: hour, count: countIn(hourCounts, key, hour) + 1 });
    return 0;
  }

  // Firestore's rules answer 200 only to a member (and "not found" for a
  // missing pair), so a 200 here is the proof the caller may wake the other.
  async function readPair(pairId, idToken) {
    const url =
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
      `/databases/(default)/documents/pairs/${pairId}`;
    let response;
    try {
      response = await fetch(url, {
        headers: { Authorization: `Bearer ${idToken}` },
        redirect: 'manual',
        signal: AbortSignal.timeout(fetchTimeoutMs),
      });
    } catch {
      log('relay: firestore unreachable');
      throw new Unavailable();
    }
    if (response.status === 403 || response.status === 404) return null;
    if (response.status !== 200) {
      log(`relay: firestore ${response.status}`);
      throw new Unavailable();
    }
    const fields = (await response.json().catch(() => null))?.fields;
    if (!fields || typeof fields !== 'object') {
      log('relay: firestore unreadable');
      throw new Unavailable();
    }
    const members = readMembers(fields.members?.arrayValue?.values);
    if (!members) return null;
    return {
      members,
      status: fields.status?.stringValue,
      endedAt: parseTimestamp(fields.endedAt?.timestampValue),
      push: fields.push?.mapValue?.fields ?? {},
    };
  }

  /** Never rejects: it runs after the caller has had its answer. */
  async function wake(pair, sub, poke) {
    try {
      if (!servesPair(pair)) return;
      const targets = pickTargets(pair, sub);
      if (targets.length === 0) return;
      const credential = await fcmAccessToken();
      if (!credential) return;
      await send(targets, poke, credential);
    } catch {
      log('relay: unexpected failure');
    }
  }

  // An ended pair is still served for a day: the "pair ended" poke itself,
  // and the partner's phone that was briefly off when it was sent.
  function servesPair(pair) {
    if (pair.status === 'active') return true;
    if (pair.status !== 'ended' || pair.endedAt === null) return false;
    const since = now() - pair.endedAt;
    return since >= 0 && since <= ENDED_PAIR_SERVED_MS;
  }

  function pickTargets(pair, sub) {
    const other = pair.members.find((uid) => uid !== sub);
    if (other === undefined || !Object.hasOwn(pair.push, other)) return [];
    const devices = pair.push[other]?.mapValue?.fields;
    if (!devices || typeof devices !== 'object') return [];
    const time = now();
    const fresh = [];
    for (const device of Object.values(devices)) {
      const fields = device?.mapValue?.fields;
      const id = fields?.id?.stringValue;
      const kind = fields?.kind?.stringValue;
      const at = parseTimestamp(fields?.at?.timestampValue);
      if (typeof id !== 'string' || !id || id.length > MAX_DEVICE_ID_CHARS) continue;
      if (!DEVICE_KINDS.includes(kind)) continue;
      if (at === null || time - at > DEVICE_FRESH_MS || at - time > DEVICE_FUTURE_MS) continue;
      fresh.push({ kind, id, at });
    }
    // The rules cap a member at five devices; the newest win if they ever
    // do not.
    fresh.sort((a, b) => b.at - a.at);
    const targets = [];
    for (const { kind, id } of fresh) {
      if (!targets.some((target) => target.kind === kind && target.id === id)) {
        targets.push({ kind, id });
      }
      if (targets.length === MAX_TARGETS) break;
    }
    return targets;
  }

  async function send(targets, poke, credential) {
    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const results = await Promise.allSettled(
      targets.map(({ kind, id }) =>
        fetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${credential}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              [kind]: id,
              data: { t: 'shared', p: poke.pair },
              android: {
                priority: poke.urgent ? 'HIGH' : 'NORMAL',
                collapse_key: poke.pair,
                ttl: '3600s',
              },
            },
          }),
          redirect: 'manual',
          signal: AbortSignal.timeout(fetchTimeoutMs),
        }),
      ),
    );
    const statuses = results.map((result) =>
      result.status === 'fulfilled' ? result.value.status : 0,
    );
    // A credential FCM no longer takes is dropped so the next poke mints one.
    if (statuses.includes(401) && accessToken?.value === credential) accessToken = null;
    if (statuses.some((status) => status < 200 || status > 299)) {
      log(`relay: fcm ${statuses.join(',')}`);
    }
  }

  function fcmAccessToken() {
    if (accessToken && now() < accessToken.until) return Promise.resolve(accessToken.value);
    if (exchangeInFlight) return exchangeInFlight;
    if (now() - oauthFailedAt < OAUTH_RETRY_GAP_MS) return Promise.resolve(null);
    exchangeInFlight = exchange().finally(() => {
      exchangeInFlight = null;
    });
    return exchangeInFlight;
  }

  /** The access token, or null after one log line. Never rejects. */
  async function exchange() {
    try {
      const { email, key, keyId } = await signer;
      const issuedAt = Math.floor(now() / SECOND);
      const header = { alg: 'RS256', typ: 'JWT', ...(keyId ? { kid: keyId } : {}) };
      const claims = {
        iss: email,
        scope: FCM_SCOPE,
        aud: OAUTH_URL,
        iat: issuedAt,
        exp: issuedAt + ACCESS_TOKEN_LIFETIME_S,
      };
      const input = `${encodeJson(header)}.${encodeJson(claims)}`;
      const signature = await crypto.subtle.sign(RS256, key, new TextEncoder().encode(input));
      let response;
      try {
        response = await fetch(OAUTH_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion: `${input}.${encodeBase64Url(new Uint8Array(signature))}`,
          }).toString(),
          redirect: 'manual',
          signal: AbortSignal.timeout(fetchTimeoutMs),
        });
      } catch {
        return failExchange('relay: oauth unreachable');
      }
      if (!response.ok) return failExchange(`relay: oauth ${response.status}`);
      const body = await response.json().catch(() => null);
      if (typeof body?.access_token !== 'string' || !body.access_token) {
        return failExchange('relay: oauth unreadable');
      }
      const lifetime = Number.isFinite(body.expires_in)
        ? Math.min(Math.max(body.expires_in, 0), ACCESS_TOKEN_LIFETIME_S)
        : ACCESS_TOKEN_LIFETIME_S;
      accessToken = {
        value: body.access_token,
        until: now() + (lifetime - ACCESS_TOKEN_MARGIN_S) * SECOND,
      };
      return accessToken.value;
    } catch {
      return failExchange('relay: oauth failed');
    }
  }

  function failExchange(line) {
    oauthFailedAt = now();
    log(line);
    return null;
  }

  return { handle };
}

/** A Map that forgets its least recently written key past `limit` keys. */
class BoundedMap {
  constructor(limit) {
    this.limit = limit;
    this.map = new Map();
  }

  get(key) {
    return this.map.get(key);
  }

  set(key, value) {
    this.map.delete(key);
    this.map.set(key, value);
    if (this.map.size > this.limit) this.map.delete(this.map.keys().next().value);
  }
}

function countIn(counts, key, window) {
  const held = counts.get(key);
  return held?.window === window ? held.count : 0;
}

// Exactly two distinct uids, or the pair is not one this relay serves.
function readMembers(values) {
  if (!Array.isArray(values) || values.length !== 2) return null;
  const members = values.map((value) => value?.stringValue);
  if (!members.every((uid) => typeof uid === 'string' && uid)) return null;
  return members[0] === members[1] ? null : members;
}

async function importSigner(json) {
  if (typeof json !== 'string') throw new Error('service account');
  const account = JSON.parse(json);
  if (typeof account?.client_email !== 'string' || !account.client_email) {
    throw new Error('service account');
  }
  if (typeof account.private_key !== 'string') throw new Error('service account');
  // A key pasted through a shell often keeps its newlines as a literal "\n".
  const pem = /^-----BEGIN PRIVATE KEY-----([A-Za-z0-9+/=\s]+)-----END PRIVATE KEY-----$/.exec(
    account.private_key.replace(/\\n/g, '\n').trim(),
  );
  if (!pem) throw new Error('service account');
  const der = decodeBase64(pem[1].replace(/\s+/g, ''));
  if (!der) throw new Error('service account');
  const key = await crypto.subtle.importKey('pkcs8', der, RS256, false, ['sign']);
  return {
    email: account.client_email,
    key,
    keyId: typeof account.private_key_id === 'string' ? account.private_key_id : null,
  };
}

function reply(status, headers) {
  return new Response(null, { status, headers });
}

function unauthorized() {
  return reply(401, { 'WWW-Authenticate': 'Bearer' });
}

async function sha256Hex(text) {
  const digest = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

// Firestore writes up to nine fractional digits; Date.parse is only
// specified for three.
function parseTimestamp(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?Z$/.exec(value);
  if (!match) return null;
  const millis = Date.parse(`${match[1]}.${(match[2] ?? '').slice(0, 3).padEnd(3, '0')}Z`);
  return Number.isFinite(millis) ? millis : null;
}

function decodeJson(segment) {
  const bytes = decodeBase64Url(segment);
  if (!bytes) return null;
  try {
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

function encodeJson(value) {
  return encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function decodeBase64Url(segment) {
  if (typeof segment !== 'string') return null;
  return decodeBase64(segment.replace(/-/g, '+').replace(/_/g, '/'));
}

function decodeBase64(text) {
  try {
    const binary = atob(text.padEnd(text.length + ((4 - (text.length % 4)) % 4), '='));
    return Uint8Array.from(binary, (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

function encodeBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
