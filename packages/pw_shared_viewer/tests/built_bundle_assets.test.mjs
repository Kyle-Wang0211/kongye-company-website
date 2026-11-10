import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const source = new URL('../web/', import.meta.url);
const built = process.env.PW_BROWSER_BUNDLE_ROOT
  ? pathToFileURL(`${process.env.PW_BROWSER_BUNDLE_ROOT}/`)
  : new URL('../../../build/web/assets/packages/pw_shared_viewer/web/', import.meta.url);

test('built website viewer verifies complete release bytes and only adapts startup HTML', () => {
  const original = JSON.parse(readFileSync(new URL('BUNDLE_MANIFEST.json', source)));
  const manifest = JSON.parse(readFileSync(new URL('BUNDLE_MANIFEST.json', built)));
  assert.deepEqual(Object.keys(manifest.files), Object.keys(original.files));
  const packaged = readdirSync(built, {recursive:true,withFileTypes:true})
    .filter(entry=>entry.isFile())
    .map(entry=>new URL(entry.name, pathToFileURL(`${entry.parentPath}/`)).href.slice(built.href.length))
    .filter(path=>path !== 'BUNDLE_MANIFEST.json').sort();
  assert.deepEqual(packaged, Object.keys(manifest.files).sort());
  assert.equal(sha(JSON.stringify(manifest.files)),manifest.bundle_sha256);
  for (const [path, hash] of Object.entries(manifest.files)) {
    assert.equal(sha(readFileSync(new URL(path, built))), hash, `Packaged viewer differs: ${path}`);
    if (path !== 'index.html') assert.equal(hash,original.files[path], `Unexpected website adaptation: ${path}`);
  }
  const entry = readFileSync(new URL('index.html', built),'utf8');
  const expected = readFileSync(new URL('index.html', source),'utf8')
    .replace('import { verifyLocalBundle }','import { readReleaseIdentity }')
    .replace(/import \{ create \} from '\.\/viewer\.mjs(?:\?[^']*)?';/,
      "import { create } from './viewer.mjs?v=web-release-startup-20261107-v1';")
    .replace("from './bundle_identity.mjs';","from './bundle_identity.mjs?v=web-release-startup-20261107-v1';")
    .replace('pwSharedViewerReady = verifyLocalBundle()','pwSharedViewerReady = readReleaseIdentity()')
    .replace("bundleIdentityScope: 'runtime-bundle', runtimeBundleBytesVerified: true",
      "bundleIdentityScope: 'release-manifest', runtimeBundleBytesVerified: false");
  assert.equal(entry,expected);
});
