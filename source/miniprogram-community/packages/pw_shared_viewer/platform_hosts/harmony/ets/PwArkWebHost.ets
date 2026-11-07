import { webview } from '@kit.ArkWeb';
import { BUNDLE_SHA256, ASSET_PATHS } from './SharedViewerAssets';

export const PROTOCOL: string = 'PW_SHARED_VIEWER_V1';
export const ORIGIN: string = 'https://pw-viewer.invalid';
export const ENTRY: string = ORIGIN + '/index.html';
const METHODS: string[] = ['getCameraFraming', 'setCameraFraming', 'setDownloadProgress', 'load', 'resize', 'capture', 'pause', 'resume', 'dispose', 'getState', 'configure', 'resetCamera', 'setSurfaceCommentMode', 'setSurfaceCommentMarkers', 'focusSurfaceComment', 'beginSelectionEditing', 'endSelectionEditing', 'getSelectionView', 'setSelectionView', 'getSelectionBounds', 'setSelectionPreview'];

export interface ViewerArgs {
  url?: string;
  format?: string;
  preserveCamera?: boolean;
  width?: number;
  height?: number;
  pixelRatio?: number;
  type?: string;
  quality?: number;
  canonicalCamera?: boolean;
  initialCaptureCamera?: CaptureCamera;
  interactive?: boolean;
  autoRotate?: boolean;
  autoRotateUntilTouched?: boolean;
  background?: number;
  pointSize?: number;
  maxFps?: number;
  autoRotateSpeed?: number;
  enabled?: boolean;
  markers?: SurfaceMarker[];
  anchor?: SurfaceAnchor;
  radius?: number;
  rotation?: number[];
  target?: number[];
  box?: SelectionBox | null;
  decorations?: boolean;
  framing?: CameraFraming;
  receivedBytes?: number;
  totalBytes?: number | null;
}
export interface CaptureCamera {
  position: number[];
  target: number[];
  up: number[];
  focalPixels: number;
  principalX: number;
  principalY: number;
}
export interface CameraFraming {
  projection: string;
  position: number[];
  target: number[];
  up: number[];
  fov_y_degrees: number;
  aspect: number;
}
export interface SelectionBox {
  v: number;
  cx: number;
  cy: number;
  cz: number;
  sx: number;
  sy: number;
  sz: number;
  rot: number[];
}
export interface SurfaceAnchor {
  position: number[];
  normal?: number[];
  cameraPosition?: number[];
  cameraTarget?: number[];
}
export interface SurfaceMarker {
  id: string;
  number: number;
  anchor: SurfaceAnchor;
}
interface ViewerIdentity {
  bundleIdentity?: string;
}
interface ViewerPacket {
  state?: ViewerIdentity;
  result?: ViewerIdentity;
  protocol?: string;
  id?: string;
  type?: string;
  ok?: boolean;
}
interface ViewerRequest {
  id: string;
  method: string;
  args: ViewerArgs;
}
class PendingRequest {
  resolve: (packet: string) => void;
  reject: (failure: Error) => void;
  timer: number;
  constructor(resolve: (packet: string) => void, reject: (failure: Error) => void, timer: number) {
    this.resolve = resolve;
    this.reject = reject;
    this.timer = timer;
  }
}

// Transport and asset routing only. Rendering stays in the hash-verified bundle.
export class PwArkWebHost {
  readonly controller: webview.WebviewController = new webview.WebviewController();
  readonly bundleSha256: string = BUNDLE_SHA256;
  private ready: boolean = false;
  private dead: boolean = false;
  private pageActive: boolean = false;
  private foreground: boolean = true;
  private serial: number = 0;
  private modelSerial: number = 0;
  private models: Map<string, Uint8Array> = new Map();
  private pending: Map<string, PendingRequest> = new Map();
  private packetListener: (packet: string) => void = (_packet: string) => {};
  private assetReader: (path: string) => Uint8Array = (_path: string) => {
    throw new Error('Rawfile resource reader not attached');
  };

  setAssetReader(reader: (path: string) => Uint8Array): void { this.assetReader = reader; }
  onPacket(listener: (packet: string) => void): void { this.packetListener = listener; }
  isReady(): boolean { return this.ready && !this.dead; }

  // Only the one packaged document can navigate; resources use intercept().
  allowNavigation(url: string, mainFrame: boolean): boolean {
    return !this.dead && mainFrame && url === ENTRY;
  }
  pageBegin(url: string): void {
    this.pageActive = url === ENTRY && !this.dead;
    this.ready = false;
    this.rejectPending('Viewer document changed');
  }
  pageEnd(url: string): void {
    if (url !== ENTRY || this.dead) return;
    this.pageActive = true;
    // Ready can precede the end callback; this explicit state response handles it.
    this.controller.runJavaScript("window.pwSharedViewerReady.then(() => window.PWSharedBridge.request({id:'host-ready',method:'getState',args:{}})).catch(() => {});")
      .catch(() => this.fail('Viewer handshake failed'));
  }

  // ArkWeb javaScriptProxy exposes exactly this method, under PWSharedHost.
  postMessage(message: string): void {
    if (this.dead || !this.pageActive || typeof message !== 'string' || message.length > 64 * 1024 * 1024) return;
    let packet: ViewerPacket;
    try { packet = JSON.parse(message) as ViewerPacket; } catch (_) { return; }
    if (packet === null || typeof packet !== 'object') return;
    if (packet.protocol !== PROTOCOL) return;
    if (packet.type === 'pw-viewer-ready' || (packet.id === 'host-ready' && packet.ok === true)) {
      const identity = packet.type === 'pw-viewer-ready' ? packet.state?.bundleIdentity : packet.result?.bundleIdentity;
      if (identity !== BUNDLE_SHA256) {
        this.fail('Viewer bundle receipt does not match packaged identity');
        return;
      }
      this.ready = true;
      if (!this.foreground) this.request('pause').catch(() => {});
    }
    if (packet.id !== undefined) {
      const request = this.pending.get(packet.id);
      if (request !== undefined) {
        clearTimeout(request.timer);
        this.pending.delete(packet.id);
        if (packet.ok === true) request.resolve(message);
        else request.reject(new Error(message));
      }
    }
    this.packetListener(message);
  }

  request(method: string, args: ViewerArgs = {}): Promise<string> {
    if (!this.isReady() || !METHODS.includes(method)) return Promise.reject(new Error('Viewer not ready or invalid method'));
    if (method === 'load' && (args.url === undefined || !this.models.has(args.url) ||
      !['glb', 'ply', 'skp'].includes(args.format ?? '') || !args.url.endsWith('.' + args.format))) {
      return Promise.reject(new Error('Load requires a registered self-contained GLB or PLY'));
    }
    const id = 'ark-' + (++this.serial).toString();
    const packet: ViewerRequest = { id: id, method: method, args: args };
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('Viewer request timed out'));
      }, 90000);
      this.pending.set(id, new PendingRequest(resolve, reject, timer));
      this.controller.runJavaScript('window.PWSharedBridge.request(' + JSON.stringify(packet) + ').catch(() => {});')
        .catch(() => {
          const current = this.pending.get(id);
          if (current !== undefined) {
            clearTimeout(current.timer);
            this.pending.delete(id);
            current.reject(new Error('ArkWeb script dispatch failed'));
          }
        });
    });
  }

  // Caller owns account authorization and file selection. Copy freezes input bytes.
  registerModel(bytes: Uint8Array, format: string): string {
    if (this.dead || bytes.byteLength === 0 || !['glb', 'ply', 'skp'].includes(format)) {
      throw new Error('Expected nonempty GLB, PLY or SKP bytes');
    }
    const url = ORIGIN + '/models/' + (++this.modelSerial).toString() + '.' + format;
    this.models.set(url, new Uint8Array(bytes));
    return url;
  }
  unregisterModel(url: string): void { this.models.delete(url); }

  intercept(url: string, method: string): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseHeader([
      { headerKey: 'X-Content-Type-Options', headerValue: 'nosniff' },
      { headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'Content-Security-Policy', headerValue: "default-src 'none'; script-src 'self' 'unsafe-inline'; worker-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data: blob:; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'" }
    ]);
    let code = 404;
    let body: ArrayBuffer = new ArrayBuffer(0);
    let mime = 'application/octet-stream';
    if (!this.dead && method === 'GET') {
      const model = this.models.get(url);
      if (model !== undefined) {
        body = new Uint8Array(model).buffer;
        mime = url.endsWith('.glb') ? 'model/gltf-binary' : 'application/octet-stream';
        code = 200;
      } else {
        const path = url.startsWith(ORIGIN + '/') ? url.substring(ORIGIN.length + 1) : '';
        if (ASSET_PATHS.includes(path)) {
          try {
            body = new Uint8Array(this.assetReader('pw_shared_viewer/' + path)).buffer;
            mime = path.endsWith('.json') ? 'application/json' : path.endsWith('.html') ? 'text/html' :
              (path.endsWith('.js') || path.endsWith('.mjs')) ? 'text/javascript' : 'application/octet-stream';
            code = 200;
          } catch (_) { code = 500; }
        }
      }
    }
    response.setResponseCode(code);
    response.setReasonMessage(code === 200 ? 'OK' : code === 500 ? 'Asset unavailable' : 'Not Found');
    response.setResponseMimeType(mime);
    response.setResponseEncoding('utf-8');
    response.setResponseData(body);
    return response; // Always respond: no network fallback, including unknown origins.
  }

  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (this.isReady()) this.request(foreground ? 'resume' : 'pause').catch(() => {});
  }
  private rejectPending(reason: string): void {
    this.pending.forEach((request: PendingRequest) => {
      clearTimeout(request.timer);
      request.reject(new Error(reason));
    });
    this.pending.clear();
  }
  fail(reason: string): void {
    this.ready = false;
    this.pageActive = false;
    this.rejectPending(reason);
  }
  dispose(): void {
    if (this.dead) return;
    this.dead = true;
    this.fail('Viewer host disposed');
    this.models.clear();
    this.controller.runJavaScript('window.pwSharedViewerController?.dispose();').catch(() => {});
    try { this.controller.deleteJavaScriptRegister('PWSharedHost'); } catch (_) {}
    this.packetListener = (_packet: string) => {};
  }
}
