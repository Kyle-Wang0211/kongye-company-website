// Local transport/work scheduling only. Conversion uses pinned upstream OpenSKP.
export async function convertSkpUrl(url, { signal, maxBytes = 32 * 1024 * 1024 } = {}) {
  if (signal?.aborted) throw new DOMException('SKP import cancelled', 'AbortError');
  const response = await fetch(url, { signal });
  if (!response.ok) throw new Error(`SKP 加载失败 (${response.status})`);
  const length = Number(response.headers.get('Content-Length'));
  if (length > maxBytes) throw new Error('SKP 超过当前导入容量，请从 SketchUp 导出 GLB');
  const reader = response.body.getReader();
  const chunks = []; let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) throw new Error('SKP 超过当前导入容量，请从 SketchUp 导出 GLB');
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./skp_import_worker.mjs', import.meta.url), { type: 'module' });
    const finish = (error, result) => {
      clearTimeout(timeout); signal?.removeEventListener('abort', abort); worker.terminate();
      if (error) reject(error); else resolve(result);
    };
    const abort = () => finish(new DOMException('SKP import cancelled', 'AbortError'));
    const timeout = setTimeout(() => finish(new Error('SKP 导入超时，请从 SketchUp 导出 GLB')), 85000);
    signal?.addEventListener('abort', abort, { once: true });
    worker.onerror = () => finish(new Error('SKP 转换器无法完成导入'));
    worker.onmessage = ({ data }) => data.ok ? finish(null, data) : finish(new Error(data.error));
    worker.postMessage({ bytes: bytes.buffer }, [bytes.buffer]);
  });
}
