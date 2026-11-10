import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('../../web/index.html', import.meta.url), 'utf8');
const script = html.match(/<script id="pw-work-startup-script">([\s\S]*?)<\/script>/)[1];
const now = 1794283200000;
function metadataNode() {
  return {
    textContent: '',
    skeleton: true,
    classList: {remove(name) {
      assert.equal(name, 'pw-skeleton');
      this.node.skeleton = false;
    }},
  };
}
function start(search, handoff, storageError = false) {
  const shell = {hidden: true, removed: false, remove() { this.removed = true; }};
  const fields = Object.fromEntries(
    ['title', 'author', 'description', 'views', 'likes'].map(name => {
      const node = metadataNode();
      node.classList.node = node;
      return [name, node];
    }),
  );
  shell.querySelector = selector => fields[selector.slice('.pw-'.length)];
  shell.querySelectorAll = selector => {
    assert.equal(selector, '.pw-count');
    return [fields.views, fields.likes];
  };
  const listeners = new Map();
  const document = {documentElement: {style: {}}, getElementById(id) {
    assert.equal(id, 'pw-work-startup'); return shell;
  }};
  const window = {addEventListener(name, callback, options) {
    assert.equal(name, 'flutter-first-frame');
    assert.equal(options.once, true);
    listeners.set(name, {callback, options});
  }};
  const sessionStorage = {getItem(key) {
    assert.equal(key, 'pw-opening-work-v1');
    if (storageError) throw new Error('Storage unavailable');
    return handoff === undefined ? null : handoff;
  }};
  vm.runInNewContext(script, {
    document, window, location: {search}, URLSearchParams, sessionStorage,
    Date: {now: () => now},
  });
  return {shell, document, listeners, fields, frame() {
    const entry = listeners.get('flutter-first-frame');
    if (entry) { entry.callback(); if (entry.options.once) listeners.delete('flutter-first-frame'); }
  }};
}
for (const query of ['?work=123', '?other=1&work=123', '?work=']) {
  test(`work shell exists before Flutter frame: ${query}`, () => {
    const state = start(query);
    assert.equal(state.shell.hidden, false);
    assert.equal(state.shell.removed, false);
    assert.equal(state.document.documentElement.style.background, '#000');
    assert.equal(state.listeners.size, 1);
    state.frame();
    assert.equal(state.shell.removed, true);
    assert.equal(state.listeners.size, 0);
    state.frame(); // one-shot listener; no remaining overlay.
  });
}
for (const query of ['', '?login=1', '?return=%2Fx%3Fwork%3D123']) {
  test(`non-work page keeps its original startup: ${query}`, () => {
    const state = start(query);
    assert.equal(state.shell.hidden, true);
    assert.equal(state.shell.removed, true);
    assert.equal(state.listeners.size, 0);
    assert.equal(state.document.documentElement.style.background, undefined);
  });
}
test('complete static layout and reduced-motion contract precede bootstrap', () => {
  for (const name of ['pw-header', 'pw-model', 'pw-footer', 'pw-title', 'pw-author', 'pw-count', 'pw-description']) {
    assert.ok(html.includes(`class="${name}`) || html.includes(` ${name}"`), name);
  }
  assert.match(html, /class="pw-progress" aria-hidden="true">0%<\/span>/);
  assert.match(html, /prefers-reduced-motion: reduce/);
  assert.match(html, /animation: none/);
  assert.ok(html.indexOf('id="pw-work-startup"') < html.indexOf('<script src="flutter_bootstrap.js"'));
  assert.doesNotMatch(script, /fetch\(|setInterval|setTimeout/);
});

function opening(overrides = {}) {
  return JSON.stringify({
    savedAt: now,
    work: {
      id: 'work-1', user_id: 'author-1', title: '<b>Known title</b>',
      description: 'Known description', views_count: 34, likes_count: 0,
    },
    profile: {id: 'author-1', display_name: 'Known author'},
    ...overrides,
  });
}
test('known handoff metadata replaces existing skeletons before Flutter', () => {
  const state = start('?work=work-1', opening());
  for (const [field, value] of Object.entries({
    title: '<b>Known title</b>', author: 'Known author',
    description: 'Known description', views: '34', likes: '0',
  })) {
    assert.equal(state.fields[field].textContent, value, field);
    assert.equal(state.fields[field].skeleton, false, field);
  }
  assert.equal(state.shell.removed, false);
  state.frame();
  assert.equal(state.shell.removed, true);
  assert.doesNotMatch(script, /innerHTML/);
});
for (const [label, handoff] of [
  ['missing', undefined], ['malformed', '{'],
  ['expired', opening({savedAt: now - 60001})],
  ['future', opening({savedAt: now + 1})],
  ['invalid timestamp', opening({savedAt: String(now)})],
  ['wrong work', opening({work: {id: 'another-work'}})],
  ['missing author identity', opening({work: {id: 'work-1', title: 'Unverified title'}})],
]) {
  test(`${label} handoff retains startup skeletons`, () => {
    const state = start('?work=work-1', handoff);
    for (const field of Object.values(state.fields)) {
      assert.equal(field.skeleton, true);
      assert.equal(field.textContent, '');
    }
    state.frame();
    assert.equal(state.shell.removed, true);
  });
}
for (const savedAt of [now, now - 60000]) {
  test(`handoff accepts age boundary ${now - savedAt}ms`, () => {
    const state = start('?work=work-1', opening({savedAt}));
    assert.equal(state.fields.title.textContent, '<b>Known title</b>');
  });
}
test('unknown metadata and mismatched author retain only their skeletons', () => {
  const state = start('?work=work-1', opening({
    work: {id: 'work-1', user_id: 'author-1', title: 'Known title', views_count: 9},
    profile: {id: 'different-author', display_name: 'Wrong author'},
  }));
  assert.equal(state.fields.title.textContent, 'Known title');
  assert.equal(state.fields.views.textContent, '9');
  for (const name of ['author', 'description', 'likes']) {
    assert.equal(state.fields[name].skeleton, true, name);
  }
});
test('unavailable session storage keeps first-frame removal intact', () => {
  const state = start('?work=work-1', undefined, true);
  assert.equal(state.shell.hidden, false);
  state.frame();
  assert.equal(state.shell.removed, true);
});
