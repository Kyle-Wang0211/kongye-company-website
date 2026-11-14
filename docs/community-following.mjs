import {accountClientReady, getAccountClient} from './community-account.mjs?v=search-results-users-20261113-v1';
import {currentLocale, localeEvent} from './site-l10n.mjs?v=account-library-20261106-v44';
import {feedUrl} from './community-data.mjs?v=account-library-20261106-v44';
import {createPublicAvatarReader} from './community-public-avatar.mjs?v=rds-web-20261104-7931926b3d74';

const opener = document.querySelector('#following-link');
const page = document.querySelector('#following-page');
const homeSections = [...document.querySelector('#main').children].filter(node => node !== page);
const homeLink = document.querySelector('.sidebar-primary a[href="./"]');
const list = document.querySelector('#following-list');
const status = document.querySelector('#following-status');
const more = document.querySelector('#following-more');
const grid = document.querySelector('#following-grid');
const feedStatus = document.querySelector('#following-feed-status');
const feedMore = document.querySelector('#following-feed-more');
const peoplePageSize = 30;
const workPageSize = 12;
let components, client, subscribedClient, avatarReader;
let active = false, owner = null, generation = 0, people = [], peopleShown = 0;
let loading = false, worksLoading = false, workCursor, hasMoreWorks = false;
let peopleMessage = '', workMessage = '';

function text(zh, en) {
  return currentLocale() === 'zh' ? zh : en;
}
function renderMessage(node, state) {
  const messages = {
    loading: text('加载中…', 'Loading…'),
    emptyPeople: text('还没有关注其他用户', 'You are not following anyone yet'),
    emptyWorks: text('关注的用户还没有公开作品', 'No published works from people you follow yet'),
    failed: text('加载失败，请重试', 'Unable to load. Please try again'),
    signin: text('登录后查看关注', 'Sign in to see people you follow'),
  };
  node.replaceChildren();
  if (state === 'signin') {
    const link = document.createElement('a');
    link.href = 'community/?auth=signin';
    link.textContent = messages.signin;
    node.append(link);
  } else node.textContent = messages[state] || '';
}
function renderControls() {
  document.querySelector('#following-title').textContent = text('关注', 'Following');
  document.querySelector('#following-list-title').textContent = text('我的关注', 'People you follow');
  document.querySelector('#following-works-title').textContent = text('最新作品', 'Latest works');
  more.hidden = !loading && peopleShown >= people.length && peopleMessage !== 'failed';
  more.disabled = loading;
  more.textContent = peopleMessage === 'failed' ? text('重试', 'Retry') : text('加载更多', 'Load more');
  feedMore.hidden = !hasMoreWorks && workMessage !== 'failed';
  feedMore.disabled = worksLoading;
  feedMore.textContent = workMessage === 'failed' ? text('重试', 'Retry') : text('加载更多', 'Load more');
  list.setAttribute('aria-busy', String(loading));
  grid.setAttribute('aria-busy', String(worksLoading));
  renderMessage(status, peopleMessage);
  renderMessage(feedStatus, workMessage);
}
function current(epoch, accountId) {
  return active && generation === epoch && owner === accountId;
}
function clear() {
  generation++;
  owner = null;
  people = [];
  peopleShown = 0;
  loading = false;
  worksLoading = false;
  workCursor = undefined;
  hasMoreWorks = false;
  peopleMessage = '';
  workMessage = '';
  list.replaceChildren();
  components?.clearResults(grid);
  grid.replaceChildren();
  renderControls();
}
async function addAvatar(avatar, id, epoch, accountId) {
  try {
    avatarReader ??= createPublicAvatarReader(components.getConfig());
    const src = await avatarReader.read(id);
    if (!src || !current(epoch, accountId) || !avatar.isConnected) return;
    const image = document.createElement('img');
    image.src = src;
    image.alt = '';
    image.width = 32;
    image.height = 32;
    avatar.replaceChildren(image);
  } catch {}
}
function showMorePeople() {
  const epoch = generation, accountId = owner;
  const next = people.slice(peopleShown, peopleShown + peoplePageSize);
  for (const person of next) {
    const link = document.createElement('a');
    link.className = 'following-person';
    link.href = 'community/?profile=' + encodeURIComponent(person.id);
    const avatar = document.createElement('span');
    avatar.className = 'following-avatar';
    avatar.setAttribute('aria-hidden', 'true');
    const identity = document.createElement('span');
    const name = document.createElement('span');
    name.textContent = person.display_name || person.handle || person.id;
    identity.append(name);
    if (person.handle) {
      const handle = document.createElement('small');
      handle.textContent = '@' + person.handle;
      identity.append(handle);
    }
    link.append(avatar, identity);
    list.append(link);
    void addAvatar(avatar, person.id, epoch, accountId);
  }
  peopleShown += next.length;
  renderControls();
}
async function loadWorks() {
  if (!owner || !active || worksLoading || !hasMoreWorks) return;
  const epoch = generation, accountId = owner;
  worksLoading = true;
  workMessage = 'loading';
  const shells = components.createLoadingCards();
  renderControls();
  try {
    const config = components.getConfig();
    const ids = [...new Set(people.map(person => person.id))];
    const candidates = [];
    // Each author batch uses the same global cursor. Merging its first twelve
    // works yields the next twelve across every followed author.
    for (let offset = 0; offset < ids.length; offset += 100) {
      const url = feedUrl(config.origin, workCursor);
      url.searchParams.set('user_id', 'in.(' + ids.slice(offset, offset + 100).join(',') + ')');
      url.searchParams.set('deleted_at', 'is.null');
      const response = await fetch(url, {
        headers: {apikey: config.anonKey, Authorization: 'Bearer ' + config.anonKey},
        cache: 'no-store',
        signal: AbortSignal.timeout(15000),
      });
      if (!current(epoch, accountId)) return;
      if (!response.ok) throw Error('Following works unavailable');
      const rows = await response.json();
      if (!Array.isArray(rows)) throw Error('Invalid work response');
      candidates.push(...rows);
    }
    const {data, error} = await client.auth.getSession();
    if (!current(epoch, accountId)) return;
    if (error || data.session?.user.id !== accountId) throw Error('Session changed');
    const ordered = [...new Map(candidates.map(work => [work.id, work])).values()];
    ordered.sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at) || b.id.localeCompare(a.id));
    const rows = ordered.slice(0, workPageSize);
    for (const shell of shells) shell.remove();
    for (const work of rows) grid.append(components.createCard(work));
    components.onWorkCardsRendered(rows);
    workCursor = rows.at(-1) || workCursor;
    hasMoreWorks = rows.length === workPageSize;
    workMessage = grid.querySelector('.community-card') ? '' : 'emptyWorks';
  } catch {
    if (current(epoch, accountId)) workMessage = 'failed';
  } finally {
    for (const shell of shells) shell.remove();
    if (current(epoch, accountId)) {
      worksLoading = false;
      renderControls();
    }
  }
}
async function openPage() {
  clear();
  const epoch = generation;
  loading = true;
  peopleMessage = 'loading';
  renderControls();
  try {
    client = await accountClientReady.catch(() => getAccountClient());
    if (!active || generation !== epoch) return;
    if (subscribedClient !== client) {
      subscribedClient = client;
      client.auth.onAuthStateChange((event, session) => {
        if (active && (event === 'SIGNED_OUT' || event === 'SIGNED_IN' ||
            (owner && owner !== session?.user.id))) {
          setTimeout(() => { if (active) void openPage(); }, 0);
        }
      });
    }
    const {data, error} = await client.auth.getSession();
    if (!active || generation !== epoch) return;
    if (error) throw error;
    if (!data.session) { peopleMessage = 'signin'; return; }
    const accountId = data.session.user.id;
    owner = accountId;
    let cursor;
    const loaded = new Map();
    while (current(epoch, accountId)) {
      const {data: rows, error: followingError} = await client.rpc('get_my_following', {
        p_limit: 1000,
        p_before_followed_at: cursor?.followed_at ?? null,
        p_before_user_id: cursor?.id ?? null,
      });
      if (!current(epoch, accountId)) return;
      if (followingError) throw followingError;
      if (!Array.isArray(rows) || rows.some(person => !/^[a-f0-9-]{36}$/i.test(person?.id))) {
        throw Error('Invalid following response');
      }
      for (const person of rows) loaded.set(person.id, person);
      if (rows.length < 1000) break;
      const next = rows.at(-1);
      if (!next.followed_at || (next.id === cursor?.id && next.followed_at === cursor?.followed_at)) {
        throw Error('Following cursor did not advance');
      }
      cursor = next;
    }
    if (!current(epoch, accountId)) return;
    people = [...loaded.values()];
    peopleMessage = people.length ? '' : 'emptyPeople';
    workMessage = people.length ? '' : 'emptyWorks';
    hasMoreWorks = people.length > 0;
    showMorePeople();
    void loadWorks();
  } catch {
    if (active && generation === epoch) peopleMessage = 'failed';
  } finally {
    if (active && generation === epoch) { loading = false; renderControls(); }
  }
}
function applyRoute() {
  const next = new URL(location.href).searchParams.get('panel') === 'following';
  page.hidden = !next;
  for (const section of homeSections) section.hidden = next;
  opener.classList.toggle('is-current', next);
  homeLink.classList.toggle('is-current', !next);
  if (next) { opener.setAttribute('aria-current', 'page'); homeLink.removeAttribute('aria-current'); }
  else { homeLink.setAttribute('aria-current', 'page'); opener.removeAttribute('aria-current'); }
  const changed = active !== next;
  active = next;
  if (changed && components) {
    if (active) void openPage();
    else clear();
  }
}
opener.addEventListener('click', event => {
  if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  if (!active) {
    const url = new URL(location.href);
    url.searchParams.set('panel', 'following');
    history.pushState(null, '', url);
    applyRoute();
    window.scrollTo(0, 0);
  }
});
more.addEventListener('click', () => peopleMessage === 'failed' ? void openPage() : showMorePeople());
feedMore.addEventListener('click', () => void loadWorks());
window.addEventListener('popstate', applyRoute);
window.addEventListener(localeEvent, renderControls);
window.addEventListener('pageshow', event => { if (event.persisted && active && components) void openPage(); });
applyRoute();

export function installFollowingPage(sharedComponents) {
  if (components) return;
  components = sharedComponents;
  components.attachWorkGrid(grid);
  if (active) void openPage();
}
