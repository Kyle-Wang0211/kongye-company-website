import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {createHash} from 'node:crypto';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const source = new URL('../web/', import.meta.url);
const built = new URL('../../../build/web/assets/packages/pw_shared_viewer/web/', import.meta.url);

test('built browser viewer includes every manifest asset with exact source bytes', () => {
  const expected = readFileSync(new URL('BUNDLE_MANIFEST.json', source));
  assert.equal(sha(readFileSync(new URL('BUNDLE_MANIFEST.json', built))), sha(expected));
  const manifest = JSON.parse(expected);
  for (const [path, hash] of Object.entries(manifest.files)) {
    const artifact = new URL(path, built);
    assert.ok(existsSync(artifact), `Missing packaged viewer asset: ${path}`);
    assert.equal(sha(readFileSync(artifact)), hash, `Packaged viewer asset differs: ${path}`);
  }
});
