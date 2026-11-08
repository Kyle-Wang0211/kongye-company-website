const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const { resolve } = require('node:path');
const script = () => readFileSync(resolve(__dirname, '../../web/wechat_sign_in.js'), 'utf8');
const state = 'A'.repeat(43);

test('webview uses official miniProgram navigation to the fixed native login page', () => {
  const calls = [];
  const window = { wx: { miniProgram: { navigateTo: arg => calls.push(arg) } } };
  vm.runInNewContext(script(), { window });
  assert.equal(window.pwWechatSignInNavigate(state), true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `/pages/wechat-login/index?state=${state}`);
});

test('missing SDK, invalid state and navigation exceptions fail without navigation', () => {
  const calls = [];
  const window = {};
  vm.runInNewContext(script(), { window });
  assert.equal(window.pwWechatSignInNavigate(state), false);
  window.wx = { miniProgram: { navigateTo: arg => calls.push(arg) } };
  for (const bad of ['', null, undefined, 'https://evil.invalid', `${state}&url=evil`, 'A'.repeat(42)]) {
    assert.equal(window.pwWechatSignInNavigate(bad), false);
  }
  assert.equal(calls.length, 0);
  window.wx.miniProgram.navigateTo = () => { throw new Error('unavailable'); };
  assert.equal(window.pwWechatSignInNavigate(state), false);
});
