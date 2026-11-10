# Shared upstream viewer

One locally bundled Three.js 0.186.1 renderer for GLB, PLY and a limited SKP surface-preview import. All hosts load the same JavaScript modules, loaders, materials, shaders and OrbitControls. SKP is converted locally by pinned OpenSKP into GLB and then loaded by the same GLTFLoader; it is not a second renderer. Original files and original38 reconstruction outputs are never rewritten.

## Verified status — 2026-10-20

| Target | Implemented | Actual evidence | Remaining acceptance |
|---|---|---|---|
| Web | Standalone runtime and Flutter iframe host | Actual original38 GLB/PLY rendered; genuine licensed SKP converted and rendered | Broader browsers/devices and production integration |
| iOS | Flutter WKWebView host and portable example | Actual unsigned iOS debug build; bundled resources checked | Physical-device rendering, interaction, lifecycle and composition |
| Android | Flutter host source and separate native WebView fixture | Native unsigned APK compiled using existing SDK34; exact shared assets checked; bounded-stream host tests | Physical-device rendering, interaction and lifecycle; Flutter Android target build |
| Native Harmony NEXT | Native ArkTS/ArkWeb component, transport and immutable resource stager | Host contract/staging tests | Complete ArkTS/Hvigor/OHPM SDK, actual HAP build and device execution |

**This is not yet four-platform runtime acceptance or a production deployment.** No existing production viewer route, account/work record, reconstruction algorithm, dependency lock or daily-use app has been replaced by this candidate.

The selected Three.js vendor files match upstream; `UPSTREAM.json` records source identity. `web/BUNDLE_MANIFEST.json` identifies all packaged resources. The default/native page verifies their SHA-256 before initializing the renderer and reports `bundleIdentity` with `bundleIdentityScope: runtime-bundle` and `runtimeBundleBytesVerified: true` in ready/state receipts. Website staging uses `tool/browser_bundle.py` to check every artifact byte and adapt only startup HTML to normal module loading. The website validates the small canonical release manifest and reports `bundleIdentityScope: release-manifest` and `runtimeBundleBytesVerified: false`. A self-consistent manifest does not prove release freshness or executed-byte integrity. Native build/staging tools verify the same identity. This is a reproducibility check, not a signed remote-attestation or hostile-host security claim.

## Formats and SKP limits

- GLB: unchanged official GLTFLoader; self-contained meshes, materials, embedded textures and normal maps.
- PLY: unchanged official PLYLoader; colored point clouds and indexed mesh surfaces.
- SKP: OpenSKP TypeScript1.3.0 at `13ae161fa0108647a04ad5730776120bb6fe8c83`, bundled without source modifications. Parsing/conversion runs in a cancellable module Worker. Original SKP and derived GLB hashes are returned in `importInfo`.

SKP support is **surface preview**, not a complete SketchUp implementation or certified lossless conversion. Upstream can silently fall back during triangulation or omit unsupported entities. Annotations, construction geometry, styles and saved scenes are outside this surface export. The preview visibly states its limitation. Legacy projected textures, missing texture bytes, empty models and all modern textured SKP files are rejected because current upstream cannot certify their mapping. The per-import SKP input budget is32MiB; this limit is a host guard, not evidence of universal mobile memory safety. For full-fidelity source exports, use SketchUp's official GLB export. Do not expand the supported envelope without authoritative-export comparisons and device evidence.

The genuine4KB SKP fixture in `tests/fixtures/skp/` is upstream-authored synthetic geometry with its own generated PNG; license and provenance notices are retained. Browser verification produced4triangles,2materials and1decoded embedded texture, with original PNG bytes preserved. This does not establish arbitrary-model fidelity. Runtime licenses and exact contributing graph are retained in `web/vendor/openskp/THIRD_PARTY_NOTICES.txt` and `BUNDLE_IDENTITY.json`.

## Embedding

Browser: serve `web/` locally and open `index.html?model=<authorized-same-origin-url>&format=glb` (or `ply`/`skp`). `await window.pwSharedViewerReady` yields the controller. Methods: `load`, `resize`, `capture`, `pause`, `resume`, `dispose`, `getState`.

Flutter: `SharedViewer(controller: controller)` and, after `onReady`, `controller.load(...)` or native `controller.loadLocalFile(...)`, using `SharedModelFormat.glb/ply/skp`. The embedding caller must authorize account/file ownership. The native loopback host streams only explicitly registered files; it exposes no arbitrary filesystem endpoint. Its host code pauses/resumes viewer rendering, not reconstruction jobs.

`example/` builds a portable Flutter iOS/Web host. Query `model`/`format` on Web, or compile-time `VIEWER_MODEL_URL`/`VIEWER_MODEL_FORMAT` for a native integration fixture. It does not access production records or start jobs. It intentionally does not invent a production file-picker or switch routes.

`platform_hosts/android/` contains an independent native WebView fixture and reproducible no-Gradle unsigned-APK build. GLB/PLY selected through Android SAF are streamed rather than copied wholesale into Java heap. `platform_hosts/harmony/` stages the identical resources into an existing approved ArkTS Stage application. Both deny unknown resource/navigation requests. See each host README for build commands, source identities and limitations.

## Verification

From the product repository root:

```sh
python3 packages/pw_shared_viewer/tool/bundle_manifest.py --check
node --test packages/pw_shared_viewer/tests/*.test.mjs
node --test packages/pw_shared_viewer/platform_hosts/tests/harmony_host.test.mjs
cd packages/pw_shared_viewer
flutter test --no-pub
flutter analyze --no-pub lib test
```

Node lifecycle tests use injected boundaries when no GPU is available; they do not replace actual browser/device rendering. Browser integration harness `tests/browser_formats.cjs` expects a local fixture server on127.0.0.1:8974 mapping `/fixtures/final.glb`, `/fixtures/sparse.ply` and `/fixtures/textured.skp`; immutable identities and receipts are in the corresponding OpenSpec change. All model access stays local.

## Production gates

Require actual rendering/gesture/reentry/lifecycle receipts on all targets with matching bundle identities. Verify final GLB reentry and thumbnail precedence. Existing Flutter LiquidGlass cannot sample a native WebView as a Flutter Texture; resolve that composition contract before replacing community cards. Do not retain the old renderer as a per-platform fallback and claim one core. No production replacement is authorized by a successful candidate build alone.

### Static GLB surface comments

`SharedSurfaceAnchor` exports validated, immutable `position`, optional `normal`,
and paired `cameraPosition`/`cameraTarget` vectors, plus `toJson`/`fromJson`.
Position and normal are **current GLB root local coordinates**; camera vectors
are **existing viewer scene coordinates**. Bind saved anchors to the immutable
asset revision at the application layer. PLY/SKP picking and anchor tracking
across replacement or animation are unsupported.

The existing controller exposes `setSurfaceCommentMode(bool)`,
`setSurfaceCommentMarkers(List<SharedSurfaceMarker>)`, and
`focusSurfaceComment(SharedSurfaceAnchor)`, all returning `Future<void>`.
Listen for `surfacePickRevision` changes and read `pickedSurface` for every
successful tap, including repeated taps on the same spot. Marker selection
updates `selectedSurfaceMarkerId`; use ordinary controller listeners to respond.
Markers require unique IDs (1–128 characters), numbers 1–999999 and a maximum of
256. The app must filter marker visibility before sending them to the viewer.
Focus requires a camera snapshot; an anchor containing only position is valid
for display but cannot restore a missing camera view.

Pin mode stops automatic rotation and leaves OrbitControls available. Dragging
more than four CSS pixels, pinching, cancellation, nonprimary buttons and misses
do not create anchors. Disabling mode preserves the model/camera and leaves
rotation stopped until the app explicitly configures it again. Model load clears
pins/mode; disposal removes their listeners and DOM overlay. Rendering remains
the existing Three.js renderer; the numbered buttons use projected HTML overlays.

Sculpt interaction adaptation and its MIT attribution are included in
`web/SURFACE_COMMENTS_NOTICE` and `web/SURFACE_COMMENTS_LICENSE`. Desktop tests
exercise real Three.js raycasts and bridge routing, not physical iPhone behavior.
