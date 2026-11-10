import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const css = readFileSync(new URL('../docs/community-screens.css', import.meta.url), 'utf8');

function declarations(selector) {
  const rule = css.split('}').find(rule => rule.trim().startsWith(`${selector}{`));
  assert.ok(rule, `Missing rule for ${selector}`);
  return Object.fromEntries(rule.slice(rule.indexOf('{') + 1).split(';').filter(Boolean).map(value => {
    const separator = value.indexOf(':');
    return [value.slice(0, separator).trim(), value.slice(separator + 1).trim()];
  }));
}

test('screen choices suppress pointer focus rings and use a soft keyboard focus background', () => {
  const choice = declarations('.community-screen-choice');
  const focus = declarations('.community-screen-choice:focus-visible');
  assert.equal(choice.outline, '0');
  assert.equal(focus.outline, '0');
  assert.equal(focus.background, '#ececec');
  assert.equal(focus['border-radius'], '3px');
});

test('selected screen remains a solid enlarged dot', () => {
  const selected = declarations('.community-screen-choice[aria-pressed="true"] .community-screen-dot');
  assert.equal(selected.background, '#161616');
  assert.equal(selected.transform, 'scale(1.25)');
  assert.equal(declarations('.community-screen-dot')['border-radius'], '50%');
});

test('activity cover frames use 16:9 on desktop and compact screens', () => {
  const desktop = declarations('.community-feature-screen');
  assert.equal(desktop['aspect-ratio'], '16/9');
  const compactRules = css.match(/@media\(max-width:600px\)\{([^\n]+)\n/)[1];
  const compactFrame = compactRules.match(/\.community-feature-screen\{([^}]+)\}/)[1];
  assert.match(compactFrame, /aspect-ratio:16\/9(?:;|$)/);
  const desktopHeight = Number(declarations('.community-screen-stage')['aspect-ratio'].split('/')[1]);
  const compactHeight = Number(compactRules.match(/aspect-ratio:100\/([\d.]+)/)[1]);
  assert.ok(Math.abs(desktopHeight - parseFloat(desktop.width) * 9 / 16) < 0.00001);
  assert.ok(Math.abs(compactHeight - 58.67896 * 9 / 16) < 0.00001);
});

test('shared activity artwork fills frame width and aligns to its top', () => {
  const image = declarations('.community-screen-event>img');
  assert.equal(image.width, '100%');
  assert.equal(image.height, '100%');
  assert.equal(image['object-fit'], 'cover');
  assert.equal(image['object-position'], 'center top');
});
