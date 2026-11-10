// Native navigation uses Tencent's official JS SDK. Credentials stay server-side.
(function () {
  'use strict';
  window.pwWechatSignInNavigate = function (state) {
    if (typeof state !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(state)) return false;
    try {
      var mini = window.wx && window.wx.miniProgram;
      if (!mini || typeof mini.navigateTo !== 'function') return false;
      mini.navigateTo({ url: '/pages/wechat-login/index?state=' + encodeURIComponent(state) });
      return true;
    } catch (_) {
      return false;
    }
  };
})();
