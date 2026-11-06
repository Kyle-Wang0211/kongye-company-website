import { parseSkp, buildInstancedScene, toInstancedGLB, isLegacy } from './vendor/openskp/openskp-browser.mjs';
import { assertSkpDisplayCompatibility } from './skp_policy.mjs';

self.onmessage = async ({ data }) => {
  try {
    const source = data.bytes;
    const model = parseSkp(source);
    const info = assertSkpDisplayCompatibility(model, isLegacy(new Uint8Array(source)));
    const scene = buildInstancedScene(source);
    const result = toInstancedGLB(scene, { textures: true });
    const bytes = result.buffer.slice(result.byteOffset, result.byteOffset + result.byteLength);
    const hash = async value => [...new Uint8Array(await crypto.subtle.digest('SHA-256', value))]
      .map(byte => byte.toString(16).padStart(2, '0')).join('');
    info.sourceSha256 = await hash(source);
    info.glbSha256 = await hash(bytes);
    self.postMessage({ ok: true, bytes, info }, [bytes]);
  } catch (error) {
    self.postMessage({ ok: false, error: error instanceof Error ? error.message : String(error) });
  }
};
