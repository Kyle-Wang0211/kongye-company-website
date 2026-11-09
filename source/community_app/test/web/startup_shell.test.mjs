import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('../../web/index.html', import.meta.url), 'utf8');
const script = html.match(/<script id="pw-work-startup-script">([\s\S]*?)<\/script>/)[1];
function start(search) {
  const shell = {hidden: true, removed: false, remove() { this.removed = true; }};
  const listeners = new Map();
  const document = {documentElement: {style: {}}, getElementById(id) {
    assert.equal(id, 'pw-work-startup'); return shell;
  }};
  const window = {addEventListener(name, callback, options) {
    assert.equal(name, 'flutter-first-frame');
    assert.equal(options.once, true);
    listeners.set(name, {callback, options});
  }};
  vm.runInNewContext(script, {document, window, location: {search}, URLSearchParams});
  return {shell, document, listeners, frame() {
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
  assert.match(html, /class="pw-progress">0%/);
  assert.match(html, /prefers-reduced-motion: reduce/);
  assert.match(html, /animation: none/);
  assert.ok(html.indexOf('id="pw-work-startup"') < html.indexOf('<script src="flutter_bootstrap.js"'));
  assert.doesNotMatch(script, /fetch\(|setInterval|setTimeout/);
});
