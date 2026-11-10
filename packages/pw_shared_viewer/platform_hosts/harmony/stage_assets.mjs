import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs/promises';

const webRoot = fileURLToPath(new URL('../../web/', import.meta.url));
export async function verifyBundle(source = webRoot) {
  const manifest = JSON.parse(await fs.readFile(path.join(source, 'BUNDLE_MANIFEST.json'), 'utf8'));
  if (manifest.engine !== 'three' || manifest.engine_version !== '0.186.1' ||
      manifest.upstream_commit !== '9b4a2ac29c63ccb43fd51c5661f2f873ac2c39b8' ||
      !manifest.files || typeof manifest.files !== 'object' || Array.isArray(manifest.files) ||
      !['index.html', 'viewer.mjs', 'host_bridge.mjs', 'bundle_identity.mjs'].every(file => Object.hasOwn(manifest.files, file))) {
    throw Error('Shared viewer engine or required asset identity mismatch');
  }
  const canonical = JSON.stringify(Object.fromEntries(Object.entries(manifest.files).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)));
  const hash = createHash('sha256').update(canonical).digest('hex');
  if (manifest.schema !== 'PW_SHARED_VIEWER_BUNDLE_V1' || manifest.bundle_sha256 !== hash) throw Error('Shared bundle identity mismatch');
  for (const [relative, expected] of Object.entries(manifest.files)) {
    if (!/^[a-f0-9]{64}$/.test(expected) || !relative || relative.startsWith('/') || relative.includes('\\') || relative.split('/').some(p => !p || p === '.' || p === '..')) {
      throw Error('Unsafe bundle path');
    }
    const file = path.join(source, relative);
    if (!(await fs.lstat(file)).isFile()) throw Error('Bundle entry is not a regular file');
    if (createHash('sha256').update(await fs.readFile(file)).digest('hex') !== expected) throw Error(`Shared asset identity mismatch: ${relative}`);
  }
  return manifest;
}

async function noSymlinkParents(destination) {
  let current = path.resolve(destination);
  while (true) {
    try { if ((await fs.lstat(current)).isSymbolicLink()) throw Error('Symlink staging destination forbidden'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}
export async function stageAssets(rawfileRoot, source = webRoot) {
  const manifest = await verifyBundle(source);
  const destination = path.resolve(rawfileRoot, 'pw_shared_viewer');
  await noSymlinkParents(destination);
  // A destination is immutable once staged. Refuse a different previous bundle.
  const files = [...Object.keys(manifest.files), 'BUNDLE_MANIFEST.json'];
  const generatedReceipt = Buffer.from(JSON.stringify({ schema: 'PW_ARKWEB_BUNDLE_RECEIPT_V1', bundle_sha256: manifest.bundle_sha256, upstream_commit: manifest.upstream_commit }, null, 2) + '\n');
  const allFiles = [...files, 'bundle_identity.json'];
  async function walk(directory, prefix = '') {
    let entries;
    try { entries = await fs.readdir(directory, { withFileTypes: true }); }
    catch (error) { if (error.code === 'ENOENT') return []; throw error; }
    const result = [];
    for (const entry of entries) {
      const relative = prefix + entry.name;
      if (entry.isSymbolicLink()) throw Error('Symlink staging destination forbidden');
      if (entry.isDirectory()) result.push(...await walk(path.join(directory, entry.name), relative + '/'));
      else if (entry.isFile()) result.push(relative);
      else throw Error('Nonregular staging destination forbidden');
    }
    return result;
  }
  for (const existing of await walk(destination)) {
    if (!allFiles.includes(existing)) throw Error(`Unexpected staged asset: ${existing}`);
    const before = await fs.readFile(path.join(destination, existing));
    const expected = existing === 'bundle_identity.json' ? generatedReceipt : await fs.readFile(path.join(source, existing));
    if (!before.equals(expected)) throw Error(`Refusing to overwrite different staged asset: ${existing}`);
  }
  for (const relative of files) {
    const target = path.join(destination, relative);
    await fs.mkdir(path.dirname(target), { recursive: true });
    try { await fs.copyFile(path.join(source, relative), target, fs.constants.COPYFILE_EXCL); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  await fs.writeFile(path.join(destination, 'bundle_identity.json'), generatedReceipt, { flag: 'wx' }).catch(error => { if (error.code !== 'EEXIST') throw error; });
  const staged = await verifyBundle(destination);
  return { bundle_sha256: staged.bundle_sha256, files: allFiles.length, rawfile_directory: destination };
}
export function assetDeclarations(manifest) {
  return "// Build-generated from the verified shared bundle manifest.\nexport const BUNDLE_SHA256: string = '" + manifest.bundle_sha256 + "';\nexport const ASSET_PATHS: string[] = " + JSON.stringify([...Object.keys(manifest.files), 'BUNDLE_MANIFEST.json', 'bundle_identity.json'].sort(), null, 2) + ";\n";
}
export async function stageHost(rawfileRoot, etsDirectory, source = webRoot) {
  const manifest = await verifyBundle(source);
  const receipt = await stageAssets(rawfileRoot, source);
  await noSymlinkParents(etsDirectory);
  await fs.mkdir(etsDirectory, { recursive: true });
  for (const name of ['PwArkWebHost.ets', 'PwArkWebViewer.ets']) {
    const bytes = await fs.readFile(new URL('ets/' + name, import.meta.url));
    const target = path.join(etsDirectory, name);
    await noSymlinkParents(target);
    try { await fs.writeFile(target, bytes, { flag: 'wx' }); }
    catch (error) {
      if (error.code !== 'EEXIST' || !(await fs.readFile(target)).equals(bytes)) throw Error(`Refusing to overwrite host source: ${name}`);
    }
  }
  const declarations = assetDeclarations(manifest);
  const target = path.join(etsDirectory, 'SharedViewerAssets.ets');
  await noSymlinkParents(target);
  try { await fs.writeFile(target, declarations, { flag: 'wx' }); }
  catch (error) {
    if (error.code !== 'EEXIST' || await fs.readFile(target, 'utf8') !== declarations) throw Error('Refusing to overwrite different generated asset declarations');
  }
  return { ...receipt, ets_directory: path.resolve(etsDirectory) };
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 4) throw Error('Usage: node stage_assets.mjs RAWFILE_DIRECTORY ETS_COMPONENT_DIRECTORY');
  console.log(JSON.stringify(await stageHost(process.argv[2], process.argv[3]), null, 2));
}
