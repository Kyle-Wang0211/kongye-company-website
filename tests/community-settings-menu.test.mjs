import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

function boot() {
  const elements = new Map();
  const timers = new Map();
  let timerId = 0;
  let locale = 'zh';
  const choices = [];
  class Element {
    children = []; dataset = {}; attributes = {}; style = {}; listeners = new Map();
    hidden = false; offsetWidth = 176; offsetHeight = 90;
    rect = {left: 14, right: 180, top: 520, bottom: 560};
    constructor(tag) { this.tag = tag; }
    set id(value) { this._id = value; elements.set(`#${value}`, this); }
    get id() { return this._id; }
    setAttribute(key, value) { this.attributes[key] = value; }
    append(...nodes) { this.children.push(...nodes); }
    contains(target) { return this === target || this.children.some(child => child.contains?.(target)); }
    addEventListener(name, listener) {
      const listeners = this.listeners.get(name) || [];
      listeners.push(listener); this.listeners.set(name, listeners);
    }
    emit(name, values = {}) {
      const event = {target: this, preventDefault() { this.prevented = true; }, ...values};
      for (const listener of this.listeners.get(name) || []) listener(event);
      return event;
    }
    focus() { document.activeElement = this; this.emit('focus'); }
    getBoundingClientRect() { return this.rect; }
    querySelectorAll() { return this.children.filter(child => ['section', 'footer'].includes(child.tag)); }
    showModal() { this.open = true; }
    close() { this.open = false; this.emit('close'); }
  }
  const document = new Element('document');
  document.body = new Element('body');
  document.createElement = tag => new Element(tag);
  document.createTextNode = text => ({textContent: text});
  document.querySelector = selector => elements.get(selector);
  for (const id of ['account-menu', 'site-settings', 'open-sidebar-settings', 'open-settings', 'close-settings', 'site-locale-toggle', 'settings-title', 'account-summary']) {
    const element = new Element('button'); element.id = id;
  }
  const dialog = elements.get('#site-settings');
  dialog.append(new Element('section'), new Element('footer'));
  const window = new Element('window');
  window.innerWidth = 800; window.innerHeight = 600;
  const source = readFileSync(new URL('../docs/community-settings.mjs', import.meta.url), 'utf8').replace(/^import .*;\n/gm, '');
  vm.runInNewContext(source, {
    document, window, t: key => key, currentLocale: () => locale, localeEvent: 'pw:localechange',
    setLocale: value => { locale = value; choices.push(value); window.emit('pw:localechange'); },
    setTimeout: callback => { timers.set(++timerId, callback); return timerId; },
    clearTimeout: id => timers.delete(id),
  });
  return {document, window, choices, get: id => elements.get(`#${id}`), flush() {
    for (const [id, callback] of [...timers]) { timers.delete(id); callback(); }
  }};
}

test('sidebar hover opens a two-row menu and pointer travel keeps the submenu usable', () => {
  const page = boot();
  page.get('open-sidebar-settings').emit('pointerenter', {pointerType: 'mouse'});
  const menu = page.get('site-settings-menu');
  assert.equal(menu.hidden, false);
  assert.deepEqual(menu.children.map(child => child.dataset.i18n), ['webSettingsLanguage', 'webSettingsHelp']);
  page.get('open-sidebar-settings').emit('pointerleave');
  menu.emit('pointerenter');
  page.get('settings-language').emit('pointerenter', {pointerType: 'mouse'});
  menu.emit('pointerleave');
  page.get('site-language-menu').emit('pointerenter');
  page.flush();
  assert.equal(menu.hidden, false);
  assert.equal(page.get('site-language-menu').hidden, false);
  page.get('settings-locale-en').emit('click');
  assert.deepEqual(page.choices, ['en']);
  assert.equal(page.get('settings-locale-en').attributes['aria-checked'], 'true');
  assert.equal(menu.hidden, true);
  assert.equal(page.document.activeElement, page.get('open-sidebar-settings'));
});

test('touch click and keyboard navigation use the same menu, Escape restores focus', () => {
  const page = boot();
  const opener = page.get('open-sidebar-settings');
  opener.emit('pointerenter', {pointerType: 'touch'});
  assert.equal(page.get('site-settings-menu').hidden, true);
  opener.emit('click');
  assert.equal(page.document.activeElement, page.get('settings-language'));
  page.get('settings-language').emit('keydown', {key: 'ArrowRight'});
  assert.equal(page.document.activeElement, page.get('settings-locale-zh'));
  page.get('site-language-menu').emit('keydown', {key: 'ArrowDown'});
  assert.equal(page.document.activeElement, page.get('settings-locale-en'));
  page.get('site-language-menu').emit('keydown', {key: 'ArrowLeft'});
  assert.equal(page.get('site-language-menu').hidden, true);
  page.get('site-settings-menu').emit('keydown', {key: 'ArrowDown'});
  assert.equal(page.document.activeElement, page.get('settings-help'));
  page.document.emit('keydown', {key: 'Escape'});
  assert.equal(page.get('site-settings-menu').hidden, true);
  assert.equal(page.document.activeElement, opener);
});

test('avatar settings opens the shared menu and Help reuses the original dialog', () => {
  const page = boot();
  page.get('account-menu').open = true;
  page.get('open-settings').emit('click');
  assert.equal(page.get('account-menu').open, false);
  assert.equal(page.get('site-settings-menu').hidden, false);
  page.get('settings-help').emit('click');
  const dialog = page.get('site-settings');
  assert.equal(dialog.open, true);
  assert.equal(page.get('site-settings-menu').hidden, true);
  assert.equal(page.get('site-locale-toggle').hidden, true);
  assert.equal(dialog.children[0].hidden, true);
  const content = dialog.children.at(-1);
  assert.equal(content.children.filter(child => child.tag === 'details').length, 3);
  assert.equal(content.children.at(-1).children.at(-1).href, 'mailto:kaidong@kongye.space');
  page.get('close-settings').emit('click');
  assert.equal(dialog.open, false);
  assert.equal(page.document.activeElement, page.get('account-summary'));
});

test('menu placement is clamped to viewport and outside click closes it', () => {
  const page = boot();
  page.window.innerWidth = 320; page.window.innerHeight = 220;
  const opener = page.get('open-sidebar-settings');
  opener.rect = {left: 280, right: 310, top: 210, bottom: 220};
  opener.emit('pointerenter', {pointerType: 'mouse'});
  const menu = page.get('site-settings-menu');
  assert.equal(parseFloat(menu.style.left) >= 8, true);
  assert.equal(parseFloat(menu.style.left) + menu.offsetWidth <= 312, true);
  assert.equal(parseFloat(menu.style.top) + menu.offsetHeight <= 212, true);
  page.document.emit('click');
  assert.equal(menu.hidden, true);
});


test('sidebar menu opens above Settings while language still opens to the right', () => {
  const page = boot();
  const opener = page.get('open-sidebar-settings');
  opener.emit('pointerenter', {pointerType: 'mouse'});
  const menu = page.get('site-settings-menu');
  assert.equal(parseFloat(menu.style.left), opener.rect.left);
  assert.equal(parseFloat(menu.style.top) + menu.offsetHeight, opener.rect.top - 4);
  page.get('settings-language').emit('pointerenter', {pointerType: 'mouse'});
  const language = page.get('site-language-menu');
  assert.equal(parseFloat(language.style.left), page.get('settings-language').rect.right + 4);
  opener.rect.top = 400;
  page.window.emit('resize');
  assert.equal(parseFloat(menu.style.top) + menu.offsetHeight, 396);
});
