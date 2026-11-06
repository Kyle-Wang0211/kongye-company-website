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
