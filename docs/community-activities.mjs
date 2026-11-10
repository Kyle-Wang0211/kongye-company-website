// Public and editor clients use the deployed official Supabase SDK.
export const legacyActivitySlugs = ['ceramic', 'resort', 'courtyard'];
export function safeActivityUrl(value, { external = false } = {}) {
  if (typeof value !== 'string' || /[\u0000-\u0020\\]/u.test(value)) {
    throw Error('地址无效');
  }
  const url = new URL(value, 'https://kongye.space/');
  if (
    url.protocol !== 'https:' || url.username || url.password ||
    (!external && !['kongye.space', 'api.kongye.space'].includes(url.hostname))
  ) {
    throw Error('地址需要使用可信 HTTPS 域名');
  }
  return url.href;
}
export function validateActivityContent(content) {
  if (
    !content || typeof content.title !== 'string' || !content.title.trim() ||
    content.title.length > 120 || !Number.isInteger(content.sort_order) ||
    content.sort_order < 0 || content.sort_order > 10000 ||
    !['article', 'ceramic', 'resort'].includes(content.template_key) ||
    !content.detail || Array.isArray(content.detail) ||
    typeof content.detail !== 'object'
  ) {
    throw Error('请检查活动标题、排序与详情');
  }
  if (
    content.template_key === 'article' &&
    (!Array.isArray(content.detail.sections) ||
      content.detail.sections.some((section) =>
        !section || typeof section.heading !== 'string' ||
        typeof section.body !== 'string'
      ))
  ) {
    throw Error('图文活动段落无效');
  }
  if (
    content.template_key !== 'article' &&
    (!Array.isArray(content.detail.textBlocks) ||
      content.detail.templateVersion !== content.template_key + '-20261110-v1')
  ) {
    throw Error('专用活动模板版本或文字缺失');
  }
  safeActivityUrl(content.cover_url);
  if (new TextEncoder().encode(JSON.stringify(content.detail)).length > 131072) {
    throw Error('活动详情过长');
  }
  return content;
}
export function normalizeActivities(rows) {
  if (!Array.isArray(rows)) {
    throw Error('活动列表无效');
  }
  const ids = new Set();
  return rows.map((row) => {
    if (
      !row || typeof row.id !== 'string' || ids.has(row.id) ||
      !/^[a-z0-9][a-z0-9-]{0,79}$/.test(row.slug) || !Number.isSafeInteger(row.revision)
    ) {
      throw Error('活动身份无效');
    }
    ids.add(row.id);
    validateActivityContent(row.content);
    return row;
  }).sort((a, b) =>
    a.content.sort_order - b.content.sort_order || a.id.localeCompare(b.id)
  );
}
let publicClient;
export async function getActivityPublicClient() {
  if (!publicClient) {
    publicClient = (async () => {
      if (!globalThis.supabase?.createClient) {
        await import('./vendor/supabase/supabase-2.112.0.js');
      }
      const response = await fetch('community-config.json', {
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) {
        throw Error('活动配置暂不可用');
      }
      const config = await response.json();
      if (config.origin !== 'https://api.kongye.space') {
        throw Error('活动配置无效');
      }
      return globalThis.supabase.createClient(config.origin, config.anonKey, {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
        },
        global: {
          fetch: (url, options = {}) =>
            fetch(url, {
              ...options,
              signal: options.signal || AbortSignal.timeout(15000),
            }),
        },
      });
    })().catch((error) => {
      publicClient = null;
      throw error;
    });
  }
  return publicClient;
}
export async function listActivities(client) {
  client ||= await getActivityPublicClient();
  const { data, error } = await client.rpc('list_community_activities');
  if (error) {
    throw error;
  }
  return normalizeActivities(data);
}
export function selectedActivityIndex(rows, activeId) {
  const index = rows.findIndex((row) => row.id === activeId);
  return index < 0 ? 0 : index;
}
export function carouselPosition(index, selected, count) {
  if (index === selected) {
    return 'center';
  }
  if (count > 1 && index === (selected + 1) % count) {
    return 'right';
  }
  if (count > 2 && index === (selected + count - 1) % count) {
    return 'left';
  }
  return 'hidden';
}
export function activityTextNodes(root) {
  const walker = root.ownerDocument.createTreeWalker(root, 4);
  const nodes = [];
  while (walker.nextNode()) {
    if (walker.currentNode.nodeValue.trim()) {
      nodes.push(walker.currentNode);
    }
  }
  return nodes;
}
// Text blocks address only text nodes in the bundled template. No HTML is accepted.
export function bindActivityDetail(root, detail, templateVersion) {
  if (detail.templateVersion !== templateVersion) {
    throw Error('活动模板版本不匹配，请重新加载后编辑');
  }
  if (!Array.isArray(detail.textBlocks)) {
    throw Error('活动模板文字缺失');
  }
  {
    const nodes = activityTextNodes(root);
    if (
      detail.textBlocks.length !== nodes.length ||
      detail.textBlocks.some((value) => typeof value !== 'string')
    ) {
      throw Error('活动模板与文字版本不匹配');
    }
    nodes.forEach((node, index) => {
      node.nodeValue = detail.textBlocks[index];
    });
  }
  for (const binding of detail.attributes || []) {
    if (
      !['img', 'a'].includes(binding.tag) || !Number.isSafeInteger(binding.index) ||
      binding.index < 0
    ) {
      throw Error('活动资源位置无效');
    }
    const node = root.querySelectorAll(binding.tag)[binding.index];
    if (!node) {
      throw Error('活动资源不存在');
    }
    if (binding.tag === 'img') {
      if (typeof binding.src === 'string') {
        node.src = safeActivityUrl(binding.src);
      }
      if (typeof binding.alt === 'string') {
        node.alt = binding.alt;
      }
    } else if (typeof binding.href === 'string') {
      node.href = safeActivityUrl(binding.href, { external: true });
    }
  }
}
export class ActivityEditor {
  constructor(client) {
    this.client = client;
    this.generation = 0;
  }
  invalidate() {
    this.generation++;
  }
  async asOwner(operation) {
    const epoch = this.generation;
    const { data, error } = await this.client.auth.getSession();
    const owner = data?.session?.user?.id;
    if (error || !owner || epoch !== this.generation) {
      throw Error('请先登录活动管理账号');
    }
    const result = await operation(owner);
    const after = await this.client.auth.getSession();
    if (
      after.error || after.data?.session?.user?.id !== owner ||
      epoch !== this.generation
    ) {
      throw Error('账号已变化，请重新加载');
    }
    return result;
  }
  async manage(action, row = null, content = null, slug = null) {
    if (!['list', 'save', 'publish', 'withdraw'].includes(action)) {
      throw Error('操作无效');
    }
    if (content) {
      validateActivityContent(content);
    }
    return this.asOwner(async () => {
      const { data, error } = await this.client.rpc('manage_community_activity', {
        p_action: action,
        p_id: row?.id ?? null,
        p_expected_revision: row?.draft_revision ?? null,
        p_slug: slug ?? row?.slug ?? null,
        p_content: content,
      });
      if (error) {
        throw error;
      }
      return data;
    });
  }
  async upload(file) {
    if (
      !['image/jpeg', 'image/png', 'image/webp'].includes(file.type) ||
      file.size > 8 * 1024 * 1024
    ) {
      throw Error('请选择 8 MiB 以内的 JPG、PNG 或 WebP 图片');
    }
    return this.asOwner(async () => {
      const extension =
        { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }[file.type];
      const path = `${crypto.randomUUID()}.${extension}`;
      const bucket = this.client.storage.from('activity-covers');
      const { error } = await bucket.upload(path, file, {
        upsert: false,
        contentType: file.type,
        cacheControl: '31536000',
      });
      if (error) {
        throw error;
      }
      return safeActivityUrl(bucket.getPublicUrl(path).data.publicUrl);
    });
  }
}
