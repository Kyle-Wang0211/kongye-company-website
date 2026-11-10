import {
  installMiniProgramNavigation,
  miniProgramTitle,
} from './miniprogram-navigation.mjs?v=phone-brand-20261107';
import { initSiteLocale, t } from './site-l10n.mjs?v=account-library-20261106-v44';
import {
  legacyActivitySlugs,
  listActivities,
  safeActivityUrl,
  validateActivityContent,
} from './community-activities.mjs?v=activities-20261110';
const params = new URL(location.href).searchParams;
const legacy = Number(params.get('screen'));
const slug = params.get('activity') || legacyActivitySlugs[legacy - 1] ||
  legacyActivitySlugs[0];
const main = document.querySelector('main');
let identity;
let loading = false;
await initSiteLocale();
installMiniProgramNavigation();
function clearTemplate() {
  main.activityUnmount?.();
  delete main.activityUnmount;
  main.replaceChildren();
  main.className = 'community-screen-page wrap';
  delete main.dataset.ceramicEvent;
  delete main.dataset.communityResort;
  document.body.classList.remove('event-body', 'resort-body');
  const header = document.querySelector('header');
  header.classList.remove('event-header', 'resort-header');
  header.querySelector('.event-header-register')?.remove();
}
async function render(row) {
  const content = validateActivityContent(row.content);
  clearTemplate();
  if (content.template_key === 'ceramic') {
    const { mountCeramicEvent } = await import(
      './ceramic-event.mjs?v=activities-20261110'
    );
    mountCeramicEvent(content.detail);
  } else if (content.template_key === 'resort') {
    const config = content.detail.resortConfig;
    if (!config) {
      throw Error('活动导览尚未配置');
    }
    safeActivityUrl(config.sourceUrl);
    const { mountCommunityResort } = await import(
      './community-resort.mjs?v=activities-20261110'
    );
    mountCommunityResort(config, content.detail);
  } else {
    const title = document.createElement('h1');
    title.textContent = content.title;
    main.append(title);
    for (const section of content.detail.sections || []) {
      const article = document.createElement('section');
      const heading = document.createElement('h2');
      heading.textContent = section.heading || '';
      const body = document.createElement('p');
      body.textContent = section.body || '';
      body.style.whiteSpace = 'pre-wrap';
      article.append(heading, body);
      main.append(article);
    }
  }
  document.title = miniProgramTitle(
    location.href,
    content.title + ' · ' + t('siteBrand'),
  );
}
async function refresh() {
  if (loading) {
    return;
  }
  loading = true;
  try {
    if (params.has('preview')) {
      const content = JSON.parse(
        sessionStorage.getItem('pw-activity-preview-' + params.get('preview')) ||
          'null',
      );
      await render({ content });
      document.title = '预览 · ' + document.title;
      return;
    }
    const rows = await listActivities();
    const row = rows.find((item) => item.slug === slug || item.id === slug);
    if (!row) {
      identity = null;
      clearTemplate();
      const message = document.createElement('p');
      message.textContent = '活动未发布或已下线';
      main.append(message);
      document.title = '活动 · ' + t('siteBrand');
      return;
    }
    const next = row.id + ':' + row.revision;
    if (next !== identity) {
      await render(row);
      identity = next;
    }
  } catch {
    identity = null;
    clearTemplate();
    const message = document.createElement('p');
    message.textContent = '活动暂不可用，请稍后重试';
    const retry = document.createElement('button');
    retry.type = 'button';
    retry.textContent = '重新加载';
    retry.addEventListener('click', refresh);
    main.append(message, retry);
  } finally {
    loading = false;
  }
}
document.addEventListener('visibilitychange', () => {
  if (!document.hidden) {
    void refresh();
  }
});
window.addEventListener('pageshow', () => void refresh());
await refresh();
