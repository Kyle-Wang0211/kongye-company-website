(function () {
  'use strict';
  window.pwConsumeModelHandoff = function () {
    var url = new URL(location.href);
    var id = url.searchParams.get('model_handoff');
    if (!id || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) return null;
    url.searchParams.delete('model_handoff');
    history.replaceState(history.state, '', url.href);
    return id;
  };
  window.pwOpenModelPicker = function (value) {
    return new Promise(function (resolve, reject) {
      var draft;
      try { draft = JSON.parse(value); } catch (_) { reject(Error('invalid_handoff')); return; }
      var mini = window.wx && window.wx.miniProgram;
      if (!mini || !/^[0-9a-f-]{36}$/i.test(draft.id || '') || !/^[A-Za-z0-9_-]{43}$/.test(draft.grant || '')) { reject(Error('native_picker_unavailable')); return; }
      mini.getEnv({ success: function (env) {
        if (!env.miniprogram) { reject(Error('native_picker_unavailable')); return; }
        mini.postMessage({ data: { type: 'pw.model-handoff.v1', id: draft.id, grant: draft.grant } });
        mini.redirectTo({ url: '/pages/model-upload/index?id=' + encodeURIComponent(draft.id),
          success: function () { resolve(true); }, fail: reject });
      }, fail: reject });
    });
  };
})();
