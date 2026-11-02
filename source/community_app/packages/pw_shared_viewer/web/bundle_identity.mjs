// Content verification only; the engine and parsers are unchanged upstream files.
export async function verifyBundle({ manifest, fetchResource, crypto = globalThis.crypto }) {
  if (!crypto?.subtle) throw new Error('Secure content verification is unavailable');
  if (!manifest?.files || !/^[a-f0-9]{64}$/.test(manifest.bundle_sha256)) {
    throw new Error('Invalid viewer bundle manifest');
  }
  const sha256 = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map(byte => byte.toString(16).padStart(2, '0')).join('');
  const paths = Object.keys(manifest.files).sort();
  if (paths.length === 0) throw new Error('Empty viewer bundle manifest');
  for (const path of paths) {
    if (!/^[a-zA-Z0-9_.\/-]+$/.test(path) || path.startsWith('/') ||
        path.split('/').some(part => !part || part === '.' || part === '..')) {
      throw new Error('Invalid bundle path');
    }
    if (!/^[a-f0-9]{64}$/.test(manifest.files[path])) throw new Error('Invalid resource hash');
  }
  const canonical = Object.fromEntries(paths.map(path => [path, manifest.files[path]]));
  if (await sha256(new TextEncoder().encode(JSON.stringify(canonical))) !== manifest.bundle_sha256) {
    throw new Error('Bundle manifest identity mismatch');
  }
  // Keep at most one extra asset buffer alive, including on memory-constrained phones.
  for (const path of paths) {
    if (await sha256(await fetchResource(path)) !== manifest.files[path]) {
      throw new Error(`Viewer resource identity mismatch: ${path}`);
    }
  }
  return manifest.bundle_sha256;
}

export async function verifyLocalBundle(base = new URL('./', import.meta.url)) {
  const manifestResponse = await fetch(new URL('BUNDLE_MANIFEST.json', base), { cache: 'no-cache' });
  if (!manifestResponse.ok) throw new Error('Viewer bundle manifest is unavailable');
  const manifest = await manifestResponse.json();
  return verifyBundle({ manifest, fetchResource: async path => {
    const response = await fetch(new URL(path, base), { cache: 'no-cache' });
    if (!response.ok) throw new Error(`Viewer resource unavailable: ${path}`);
    return response.arrayBuffer();
  } });
}
