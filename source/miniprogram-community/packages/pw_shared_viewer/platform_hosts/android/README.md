# Android native offline WebView fixture

This is a separate native Activity target with application ID
`dev.pocketworld.sharedviewerfixture`, min SDK 26 and target/compile SDK 34.
It embeds the same exact shared Three.js/OpenSKP modules as the Web, iOS and
Harmony hosts. It has no AndroidX, Gradle or Flutter runtime dependency.

The actual SDK-34 native APK build has passed `aapt → javac → D8 → zipalign`
and packaged-resource byte/file-set verification. This is an unsigned test
artifact. It has not been installed or executed; import maps, WebGL2, module
workers, Web Crypto, touch/lifecycle, screenshots, large real models and visual
parity still require an actual Android System WebView/device test. Min SDK 26
alone does not imply a sufficiently recent System WebView.

## Rebuild with the installed tools

From the product repository root, choose a fresh output directory:

```sh
python3 packages/pw_shared_viewer/platform_hosts/android/build_unsigned_apk.py \
  --out /private/tmp/pw-viewer-android-fresh-build
```

Defaults use the existing SDK at `~/Library/Android/sdk`, API 34's `android.jar`,
build-tools `34.0.0`, and `/opt/homebrew/opt/openjdk`. Override paths using `--sdk`
and `--java-home` only with already approved/available toolchains. The script
performs no downloads, dependency resolution, signing or installation, and
refuses an existing output directory or output inside the product repository.

It verifies the canonical bundle identity and every manifest resource before
staging, generates `BundleAssets.java`, packages the exact renderer bytes,
compiles the Java host, produces DEX, aligns the APK, checks the APK asset file
set/bytes and records commands, tool/source hashes, exit codes and times in
`BUILD_EVIDENCE.json` and `build.log`. The APK has no network/storage permissions,
is not debuggable, and uses its own test application ID/container.

The installed compiler is OpenJDK 27 and the installed D8 reports 8.2.2-dev.
`core-lambda-stubs.jar` from the existing SDK supplies the Android Java-8 lambda
bootstrap signatures. `javac -parameters` is required for this observed tool
pair: without it javac emits an unnamed mandated constructor parameter that
triggers an internal D8 error. Failed attempts are preserved separately. This
records a verified local build recipe, not a general compatibility promise for
other JDK/D8 versions. No compiler or SDK was replaced.

## Host behavior

`ViewerHost` loads `https://pw-viewer.invalid/index.html`. Every request returns
a local intercepted response: exact packaged-asset allowlist, explicitly
registered model stream, or an error. Unknown URLs never fall back to network.
Only the exact top-level entry document may navigate; frames, filesystem and
content URL access from JavaScript, mixed content and new windows are denied.
There is no INTERNET permission, and network loads are also blocked in WebView
settings. CSP includes `worker-src 'self' blob:` for the shared SKP module worker.
The synthetic HTTPS origin is intended to support secure-context Web Crypto;
its actual intercepted loading behavior must be validated on the target WebView.

`PWSharedHost.postMessage` and `PWSharedBridge.request` use
`PW_SHARED_VIEWER_V1` unchanged. A ready/state handshake must return the exact
build-generated `bundleIdentity`. Request IDs, method allowlisting, registered
model URL/format checks and 90-second deadlines protect the transport.
Background/resume forwards pause/resume; page replacement or disposal rejects
pending work. Disposal removes the native interface, closes model streams,
detaches and destroys the WebView. No production records or account API exist.

The test Activity displays a tiny PLY example after readiness and exposes a
system `ACTION_OPEN_DOCUMENT` picker for GLB, PLY and SKP. These are user-operated
fixture flows; this source does not authorize installing or opening any app.

- **GLB/PLY:** the selected content URI must have an explicit Android read grant.
  `registerDocument` rejects filesystem paths and URIs lacking that grant. The
  host stores a private stream factory and opens `ContentResolver.openInputStream`
  only when the registered opaque URL is requested. It does not read the whole
  document or duplicate it in native byte arrays. The shared renderer still
  needs its own model memory; no real 77 MB model/device memory claim is made.
- **SKP:** the selected source is capped at 32 MiB, matching the shared converter's
  declared input limit. Conversion runs in the same pinned OpenSKP worker and
  uses the shared display-compatibility policy. Unsupported/version/size cases
  remain visible errors. No alternate parser or rendering algorithm is added.
- Registering small private `byte[]` fixtures clones their bytes once. Source
  registration is explicit; no arbitrary filesystem/path-serving handler exists.
  Unregistration/disposal drops the mapping and revokes active streams immediately.
  Provider opening runs outside source monitors; late opens after revocation are
  rejected. Potentially blocking provider closes run on daemon cleanup threads,
  so neither open nor close I/O can block the UI revocation caller.

## JVM contract tests

These execute the actual platform-independent host policy/model registry:

```sh
mkdir -p /private/tmp/pw-android-jvm-tests
/opt/homebrew/opt/openjdk/bin/javac -d /private/tmp/pw-android-jvm-tests \
  packages/pw_shared_viewer/platform_hosts/android/src/dev/pocketworld/sharedviewerfixture/HostPolicy.java \
  packages/pw_shared_viewer/platform_hosts/android/src/dev/pocketworld/sharedviewerfixture/ModelRegistry.java \
  packages/pw_shared_viewer/platform_hosts/android/tests/*.java
/opt/homebrew/opt/openjdk/bin/java -Xmx32m -cp /private/tmp/pw-android-jvm-tests \
  dev.pocketworld.sharedviewerfixture.HostPolicyTest
/opt/homebrew/opt/openjdk/bin/java -Xmx32m -cp /private/tmp/pw-android-jvm-tests \
  dev.pocketworld.sharedviewerfixture.ModelRegistryTest
```

The registry test consumes a **synthetic** 77 MiB stream with an 8 KiB buffer
under a 32 MiB JVM heap, proving lazy host registration/streaming and revocation.
Deterministic latch tests also hold provider opening/closing blocked and require
unregister and registry close to return within two seconds before releasing the
provider. They verify late streams are never published, revoked reads fail, raw
cleanup runs off the caller, and opener/caller/cleanup threads finish after release.
It does not test Android SAF permission enforcement, native WebView rendering,
GLB parsing, GPU memory or the actual 77 MB production capture.

## Official API/tool sources

`API_SOURCES.json` records original Android-14 source URLs and downloaded hashes
for `WebViewClient`, `WebSettings`, `WebResourceResponse` and
`JavascriptInterface`, pinned to AOSP tag `android-14.0.0_r1`. The actual build
also hashes the installed `android-34/android.jar` and build tools, and compilation
checks every referenced Android API against that exact SDK jar.

- [Official WebViewClient API](https://developer.android.com/reference/android/webkit/WebViewClient)
- [Official JavaScript interface API](https://developer.android.com/reference/android/webkit/JavascriptInterface)
- [AOSP Android-14 WebViewClient source](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-14.0.0_r1/core/java/android/webkit/WebViewClient.java)
- [Official D8 tool](https://developer.android.com/tools/d8)
- [Official zipalign tool](https://developer.android.com/tools/zipalign)
- [Android SDK Build Tools](https://developer.android.com/tools/releases/build-tools)

This hand-built fixture supplements the Flutter host build evidence. It is not
the production Android application package, a production integration result, or
four-platform runtime verification.
