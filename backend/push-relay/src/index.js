// The Worker's entry: wires the platform into the relay (src/relay.js).

import { createRelay } from './relay.js';

// One relay per isolate, so the key set, the FCM credential and the poke
// counts outlive a single request; rebuilt only if the configuration moves.
let relay = null;
let relayConfig = null;

export default {
  fetch(request, env, ctx) {
    const config = `${env.FIREBASE_PROJECT_ID}\n${env.FCM_SERVICE_ACCOUNT}`;
    if (relay === null || relayConfig !== config) {
      relay = createRelay({
        fetch: (input, init) => fetch(input, init),
        now: () => Date.now(),
        projectId: env.FIREBASE_PROJECT_ID,
        serviceAccount: env.FCM_SERVICE_ACCOUNT,
        log: (line) => console.log(line),
      });
      relayConfig = config;
    }
    const limit = env.POKE_LIMIT;
    return relay.handle(request, {
      defer: (promise) => ctx.waitUntil(promise),
      limiter: limit ? async (key) => (await limit.limit({ key })).success === true : null,
    });
  },
};
