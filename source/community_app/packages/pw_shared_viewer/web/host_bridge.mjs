// Embedding/lifecycle messages only. All rendering stays in the unchanged upstream engine.
const PROTOCOL = 'PW_SHARED_VIEWER_V1';
const METHODS = new Set(['load', 'resize', 'capture', 'pause', 'resume', 'dispose', 'getState', 'configure', 'resetCamera', 'setSurfaceCommentMode', 'setSurfaceCommentMarkers', 'focusSurfaceComment']);

export function createHostBridge({ ready, send }) {
  async function request(packet) {
    const id = typeof packet?.id === 'string' ? packet.id : null;
    let response;
    try {
      if (!id || id.length > 128 || !METHODS.has(packet?.method)) {
        throw new Error('Invalid viewer request identity or method');
      }
      const viewer = await ready;
      const args = packet.args ?? {};
      let result;
      switch (packet.method) {
        case 'setSurfaceCommentMode': result = viewer.setSurfaceCommentMode(args.enabled); break;
        case 'setSurfaceCommentMarkers': result = viewer.setSurfaceCommentMarkers(args.markers); break;
        case 'focusSurfaceComment': result = viewer.focusSurfaceComment(args.anchor); break;
        case 'load': result = await viewer.load(args); break;
        case 'configure': result = viewer.configure(args); break;
        case 'resize': result = viewer.resize(args.width, args.height, args.pixelRatio); break;
        case 'capture': result = viewer.capture(args.type, args.quality); break;
        default: result = viewer[packet.method]();
      }
      response = { protocol: PROTOCOL, id, ok: true, result: result ?? null };
    } catch (failure) {
      response = { protocol: PROTOCOL, id, ok: false, error: {
        code: 'VIEWER_REQUEST_FAILED', message: failure instanceof Error ? failure.message : String(failure),
      } };
    }
    send(response);
    return response;
  }
  return Object.freeze({ request });
}

export function installHostBridge(hostWindow) {
  const send = packet => {
    if (hostWindow.PWSharedHost?.postMessage) {
      hostWindow.PWSharedHost.postMessage(JSON.stringify(packet));
    } else if (hostWindow.parent !== hostWindow && hostWindow.location.origin !== 'null') {
      hostWindow.parent.postMessage(packet, hostWindow.location.origin);
    }
  };
  const bridge = createHostBridge({ ready: hostWindow.pwSharedViewerReady, send });
  hostWindow.PWSharedBridge = bridge;
  const onRequest = event => {
    if (event.source !== hostWindow.parent || event.origin !== hostWindow.location.origin ||
        event.data?.type !== 'pw-shared-request') return;
    void bridge.request(event.data.request);
  };
  const onState = event => send({ protocol: PROTOCOL, type: 'pw-viewer-state', state: event.detail });
  const surfaceEvents = ['pw-viewer-surface-picked', 'pw-viewer-surface-marker-selected', 'pw-viewer-surface-marker-layout'];
  const onSurface = event => send({ ...event.detail, protocol: PROTOCOL, type: event.type });
  for (const type of surfaceEvents) hostWindow.addEventListener(type, onSurface);
  hostWindow.addEventListener('message', onRequest);
  hostWindow.addEventListener('pw-viewer-state', onState);
  hostWindow.pwSharedViewerReady.then(viewer => {
    send({ protocol: PROTOCOL, type: 'pw-viewer-ready', state: viewer.getState() });
  }).catch(error => {
    send({ protocol: PROTOCOL, type: 'pw-viewer-state', state: {
      status: 'error', error: error instanceof Error ? error.message : String(error),
    } });
  });
  hostWindow.addEventListener('pagehide', event => {
    if (event.persisted) return;
    for (const type of surfaceEvents) hostWindow.removeEventListener(type, onSurface);
    hostWindow.removeEventListener('message', onRequest);
    hostWindow.removeEventListener('pw-viewer-state', onState);
  });
  return bridge;
}
