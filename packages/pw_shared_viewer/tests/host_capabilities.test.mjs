import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');

test('Android and Harmony hosts allow every shared viewer bridge capability', () => {
  const bridge = read('../web/host_bridge.mjs');
  const methods = bridge.match(/const METHODS = new Set\(\[([^\]]+)\]/)[1]
    .match(/'([^']+)'/g).map(value => value.slice(1, -1));
  const android = read('../platform_hosts/android/src/dev/pocketworld/sharedviewerfixture/HostPolicy.java');
  const harmony = read('../platform_hosts/harmony/ets/PwArkWebHost.ets');
  for (const method of methods) {
    assert.ok(android.includes('"' + method + '"'), `Android missing ${method}`);
    assert.ok(harmony.includes("'" + method + "'"), `Harmony missing ${method}`);
  }
});
