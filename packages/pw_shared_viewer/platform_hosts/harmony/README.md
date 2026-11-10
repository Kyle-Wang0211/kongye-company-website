# Native Harmony NEXT / ArkWeb host

This is a native ArkTS host for the same offline Three.js bundle used by Web,
iOS and Android. It does not use an Android compatibility layer or replace the
Flutter toolchain. The renderer and loaders remain in `../../web`; no renderer
files are copied into this source directory or edited for Harmony.

**Status:** transport and staging contract tests run on the Mac. ArkTS compilation,
HAP assembly, ArkWeb rendering, import maps, WebGL2 and device input remain
unverified. A source overlay is not a compiled Harmony application.

## Reproduce the source overlay

Use an existing Stage-model ArkTS application target created with its approved
DevEco/Harmony SDK. This directory intentionally has no invented Hvigor project
or downloaded compiler. In the repository root, set the target path and stage:

```sh
TARGET=/absolute/path/to/an/isolated/harmony/test/project
node packages/pw_shared_viewer/platform_hosts/harmony/stage_assets.mjs \
  "$TARGET/entry/src/main/resources/rawfile" \
  "$TARGET/entry/src/main/ets/components/pw_shared_viewer"
```

Staging verifies every renderer resource against `web/BUNDLE_MANIFEST.json`,
recomputes its canonical bundle identity, and copies the exact bytes. It also
writes `rawfile/pw_shared_viewer/bundle_identity.json` and generates
`SharedViewerAssets.ets` in the target component directory. The generated asset
list includes the manifest so the unchanged page can verify its own resources.
It refuses to replace different or unexpected existing files and rejects symlink
destinations. Use a fresh target directory when intentionally changing the bundle.
Record the emitted bundle identity in the target build evidence.

An isolated test entry page can embed:

```ts
import { PwArkWebViewer } from '../components/pw_shared_viewer/PwArkWebViewer';
import { PwArkWebHost } from '../components/pw_shared_viewer/PwArkWebHost';

@Entry
@Component
struct Index {
  private host: PwArkWebHost = new PwArkWebHost();
  onPageShow(): void { this.host.setForeground(true); }
  onPageHide(): void { this.host.setForeground(false); }
  build() {
    Column() {
      PwArkWebViewer({ host: this.host })
    }.width('100%').height('100%')
  }
}
```

The embedding application must also forward UIAbility background/foreground
notifications to the same host via `setForeground(false/true)`. A route hide and
application background are distinct events. Create a new host for each mount;
`aboutToDisappear` permanently disposes its host. Ready/state/error packets are
available through `host.onPacket(...)`; poll `host.isReady()` or inspect the ready
packet before dispatch. A successful ready packet must contain `bundleIdentity`
matching the build-generated expected identity. Failure keeps the host unavailable.

The caller selects and authorizes model bytes, then uses:

```ts
const url = host.registerModel(authorizedBytes, 'glb');
await host.request('load', { url: url, format: 'glb' });
await host.request('getState');
// When the model is no longer needed:
host.unregisterModel(url);
```

`registerModel` copies bytes so subsequent caller mutation cannot change the
input. It accepts self-contained GLB/PLY/SKP. SKP uses the same upstream converter worker and conservative compatibility gate as the other hosts; it remains a limited surface preview, not certified lossless SketchUp display. Model bytes
are memory-backed in this overlay, so realistic large models still need an
ArkWeb memory test before production use.

Use a test-only application ID and its own data container. The existing target's
Hvigor wrapper and frozen SDK perform the actual build, for example its supported
`hvigorw --mode module -p product=default -p module=entry@default assembleHap`
invocation. This command is a recipe to validate against the target's own wrapper,
not evidence of a build here. Do not install on the production iPhone bundle.

## Boundary and lifecycle contract

- The entry is the synthetic secure origin `https://pw-viewer.invalid/index.html`.
  Every request is intercepted locally and always receives a response; unknown
  origins/resources receive 404 rather than network fallback. HTTPS is required
  for the shared page's Web Crypto verification. Actual secure-context behavior
  of a fully intercepted origin still requires an ArkWeb target test.
- Only that exact top-level document may navigate. Iframes, remote navigation,
  filesystem access, storage and new windows are disabled or denied. CSP disallows
  frames, object content, external scripts and external fetches.
- JavaScript proxy `PWSharedHost.postMessage` and `PWSharedBridge.request` use
  `PW_SHARED_VIEWER_V1` unchanged. The native proxy exposes only `postMessage`.
  Request IDs correlate responses; dispatch errors, page replacement, disposal
  and 90-second deadlines reject pending operations.
- Visibility/page/application changes forward pause/resume. Renderer crashes and
  main-document errors clear readiness. Disposal rejects pending work, drops
  registered model bytes, disposes the renderer and deletes the native proxy.

## Toolchain preflight observed 2026-10-20

`/Users/kaidongwang/Developer/toolchains/openharmony/6.0.0.47` holds approximately
55 MB of selected native headers/libraries and package metadata. It is not a
complete Harmony application SDK. No `hvigorw`, `ohpm`, ArkTS compiler, or DevEco
Studio was present in the checked toolchain or command path. These native files
cannot compile an ArkUI/ArkWeb ArkTS application. No SDK parts were downloaded.

To remove this blocker, supply the project's approved complete Harmony/DevEco
SDK, ArkTS API declarations/compiler, its Hvigor/OHPM build dependencies, a Stage
application template with build/signing configuration, and a Harmony NEXT device
or emulator with ArkWeb/WebGL2. Exact SDK/build-tool versions must come from that
target's lock/configuration; the existing native 6.0.0.47 subset does not establish
a compatible ArkTS toolchain.

## Official API evidence

`API_SOURCES.json` records exact source URLs, revision and downloaded SHA-256
hashes. API signatures were inspected in the official OpenHarmony 6.0 release
documentation at revision `442679e8594d9c9c9b2a4bdc9a25a47f1035d6cb`:

- [Web events and interception](https://github.com/openharmony/docs/blob/442679e8594d9c9c9b2a4bdc9a25a47f1035d6cb/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-events.md)
- [Web attributes and JavaScript proxy](https://github.com/openharmony/docs/blob/442679e8594d9c9c9b2a4bdc9a25a47f1035d6cb/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-attributes.md)
- [Binary resource responses](https://github.com/openharmony/docs/blob/442679e8594d9c9c9b2a4bdc9a25a47f1035d6cb/en/application-dev/reference/apis-arkweb/arkts-basic-components-web-WebResourceResponse.md)
- [Rawfile resource manager](https://github.com/openharmony/docs/blob/442679e8594d9c9c9b2a4bdc9a25a47f1035d6cb/en/application-dev/reference/apis-localization-kit/js-apis-resource-manager.md)
- [WebviewController](https://github.com/openharmony/docs/blob/442679e8594d9c9c9b2a4bdc9a25a47f1035d6cb/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebviewController.md)

`onLoadIntercept` cancels when true; `onInterceptRequest` returns
`WebResourceResponse`; `setResponseData(ArrayBuffer)` is documented from API 11;
`getRawFileContentSync` from API 10; the proxy must be paired with
`deleteJavaScriptRegister`. The component expects a modern Stage/API-12-or-newer
ArkUI context. These signatures support the implementation design, not a claim of
HarmonyOS NEXT product certification or successful compilation.

## Host tests

```sh
node --test packages/pw_shared_viewer/platform_hosts/tests/harmony_host.test.mjs
```

The test loads the actual transport `.ets` class through Node's TypeScript type
erasure and replaces only ArkWeb boundaries with stubs. It checks bundle hashes,
immutable staging, byte mapping, MIME, denial paths, model freezing, identity
receipts, protocol correlation, dispatch failures, lifecycle and proxy cleanup.
It does not compile ArkTS UI syntax or create a WebGL context.
