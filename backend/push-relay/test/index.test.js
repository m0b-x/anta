// The Worker's real entry under workerd (miniflare, installed with
// wrangler), with Google faked behind the outbound service.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { Miniflare, Response, convertV4MiniflareOptions } from 'miniflare';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const PROJECT = 'test-project';
const ME = 'uid-me';
const PARTNER = 'uid-partner';
const PAIR = 'pair-entry';
const PARTNER_FID = 'fid-partner-phone';
const ACCESS_TOKEN = 'ya29.entry-access-token';
const HOSTS = new Set([
  'www.googleapis.com',
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
const account = await crypto.subtle.generateKey(RSA, true, ['sign', 'verify']);
const googleJwk = await crypto.subtle.exportKey('jwk', google.publicKey);
const accountDer = Buffer.from(await crypto.subtle.exportKey('pkcs8', account.privateKey));
const SERVICE_ACCOUNT = JSON.stringify({
  client_email: 'relay@test-project.iam.gserviceaccount.com',
  private_key: `-----BEGIN PRIVATE KEY-----\n${accountDer.toString('base64')}\n-----END PRIVATE KEY-----\n`,
});

async function mint() {
  const seconds = Math.floor(Date.now() / 1000);
  const head = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'k1' })).toString('base64url');
  const body = Buffer.from(
    JSON.stringify({
      iss: `https://securetoken.google.com/${PROJECT}`,
      aud: PROJECT,
      auth_time: seconds - 600,
      iat: seconds - 60,
      exp: seconds + 3000,
      sub: ME,
    }),
  ).toString('base64url');
  const signature = Buffer.from(
    await crypto.subtle.sign(RSA, google.privateKey, new TextEncoder().encode(`${head}.${body}`)),
  ).toString('base64url');
  return `${head}.${body}.${signature}`;
}

function pairDocument() {
  const now = new Date().toISOString();
  return {
    fields: {
      members: { arrayValue: { values: [{ stringValue: ME }, { stringValue: PARTNER }] } },
      status: { stringValue: 'active' },
      push: {
        mapValue: {
          fields: {
            [PARTNER]: {
              mapValue: {
                fields: {
                  phone: {
                    mapValue: {
                      fields: {
                        id: { stringValue: PARTNER_FID },
                        kind: { stringValue: 'fid' },
                        at: { timestampValue: now },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  };
}

const calls = [];
const waiters = [];

async function google_(request) {
  const url = new URL(request.url);
  calls.push({
    host: url.host,
    authorization: request.headers.get('Authorization'),
    body: request.method === 'POST' ? await request.text() : null,
  });
  for (const waiter of [...waiters]) waiter();
  switch (url.host) {
    case 'www.googleapis.com':
      return new Response(JSON.stringify({ keys: [{ ...googleJwk, kid: 'k1', alg: 'RS256' }] }), {
        headers: { 'Content-Type': 'application/json', 'Cache-Control': 'max-age=3600' },
      });
    case 'firestore.googleapis.com':
      return new Response(JSON.stringify(pairDocument()), {
        headers: { 'Content-Type': 'application/json' },
      });
    case 'oauth2.googleapis.com':
      return new Response(JSON.stringify({ access_token: ACCESS_TOKEN, expires_in: 3599 }), {
        headers: { 'Content-Type': 'application/json' },
      });
    case 'fcm.googleapis.com':
      return new Response(JSON.stringify({ name: 'projects/x/messages/1' }), {
        headers: { 'Content-Type': 'application/json' },
      });
    default:
      return new Response(null, { status: 502 });
  }
}

function count(host) {
  return calls.filter((call) => call.host === host).length;
}

/** Resolves once `host` has been called `n` times, or fails after 10 s. */
async function until(host, n) {
  const deadline = Date.now() + 10_000;
  while (count(host) < n) {
    assert.ok(Date.now() < deadline, `${host} was not called ${n} times`);
    await new Promise((resolve) => {
      waiters.push(resolve);
      setTimeout(resolve, 50);
    });
    waiters.length = 0;
  }
}

async function options() {
  const module = async (path) => ({
    type: 'ESModule',
    path: join(ROOT, path),
    contents: await readFile(join(ROOT, path), 'utf8'),
  });
  // Miniflare 5 reads a new shape; it still converts the version 4 one.
  return convertV4MiniflareOptions({
    name: 'anta-push-relay',
    modulesRoot: ROOT,
    modules: [await module('src/index.js'), await module('src/relay.js')],
    compatibilityDate: '2026-11-01',
    bindings: { FIREBASE_PROJECT_ID: PROJECT, FCM_SERVICE_ACCOUNT: SERVICE_ACCOUNT },
    ratelimits: { POKE_LIMIT: { namespace_id: '1001', simple: { limit: 6, period: 60 } } },
    outboundService: google_,
  });
}

async function poke(mf, token) {
  const response = await mf.dispatchFetch('https://relay.test/poke', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ pair: PAIR, urgent: true }),
  });
  assert.equal(await response.text(), '');
  return response.status;
}

test('a poke runs through the real entry, and again after the isolate reloads', { timeout: 120_000 }, async () => {
  const config = await options();
  const mf = new Miniflare(config);
  try {
    const token = await mint();

    assert.equal(await poke(mf, token), 204);
    await until('fcm.googleapis.com', 1);
    assert.equal(count('www.googleapis.com'), 1);
    assert.equal(count('oauth2.googleapis.com'), 1);
    const firestore = calls.find((call) => call.host === 'firestore.googleapis.com');
    assert.equal(firestore.authorization, `Bearer ${token}`);
    const fcm = calls.find((call) => call.host === 'fcm.googleapis.com');
    assert.equal(fcm.authorization, `Bearer ${ACCESS_TOKEN}`);
    assert.deepEqual(JSON.parse(fcm.body), {
      message: {
        fid: PARTNER_FID,
        data: { t: 'shared', p: PAIR },
        android: { priority: 'HIGH', collapse_key: PAIR, ttl: '3600s' },
      },
    });

    // The same isolate keeps the key set and the access token.
    assert.equal(await poke(mf, token), 204);
    await until('fcm.googleapis.com', 2);
    assert.equal(count('www.googleapis.com'), 1);
    assert.equal(count('oauth2.googleapis.com'), 1);

    // A reloaded isolate starts from nothing and still serves.
    await mf.setOptions(config);
    assert.equal(await poke(mf, token), 204);
    await until('fcm.googleapis.com', 3);
    assert.equal(count('www.googleapis.com'), 2);
    assert.equal(count('oauth2.googleapis.com'), 2);

    // The binding refuses within six more pokes; a binding that failed would
    // let every poke through (the relay fails open on it).
    const statuses = [];
    for (let i = 0; i < 7 && !statuses.includes(429); i += 1) statuses.push(await poke(mf, token));
    assert.ok(statuses.includes(429), `no 429 in ${statuses}`);

    // A refusal through the entry carries the challenge and no body.
    const refused = await mf.dispatchFetch('https://relay.test/poke', {
      method: 'POST',
      body: JSON.stringify({ pair: PAIR }),
    });
    assert.equal(refused.status, 401);
    assert.equal(refused.headers.get('WWW-Authenticate'), 'Bearer');
    assert.equal(await refused.text(), '');

    for (const call of calls) assert.ok(HOSTS.has(call.host), `the Worker called ${call.host}`);
    for (const call of calls) {
      if (call.host !== 'firestore.googleapis.com') {
        assert.ok(!`${call.authorization}${call.body}`.includes(token), `the ID token went to ${call.host}`);
      }
    }
  } finally {
    await mf.dispose();
  }
});
