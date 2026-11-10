# Optional iOS host registration bridge

This is source-built Objective-C glue for the experimentally verified 192-based
host route. It links the existing, unmodified official
`webview_flutter_wkwebview` 3.25.0 framework against the baseline Flutter framework
and uses public SDK APIs. It contains no renderer or algorithm implementation.
Minimum deployment target is iOS 15.0; architecture is arm64.

Normal iOS hosts and Android keep their existing plugin registration. Only an
iOS app compiled with a nonempty `PW_IOS_WEBVIEW_BRIDGE_SHA256` define loads the
adapter. The define must equal the raw SHA-256 of its final signed executable.
The native viewer waits until after the first frame, then awaits registration
before creating any WebView controller. Concurrent requests share one pending
future; success and failure are cleared so a later call revalidates the engine.
Disposal while registration is pending suppresses controller creation.

## Explicit offline build inputs

Run `python3 native_bridge/build_bridge.py --help` from this package. The helper
requires explicit absolute paths for the existing Flutter.framework, official
WebView framework, iPhoneOS SDK, compiler and signing tool; expected raw hashes
for both input framework binaries; an explicit certificate identity; and a new
output directory. It does not discover/download SDKs, resolve packages, replace
frameworks, modify Runner, install an app, contact a device, or launch an app.
It refuses an existing output, keeps failures, and records source/input/output
hashes, commands and exit codes in `build_receipt.json`. Input framework contents
are frozen before the build and checked afterward. The adapter source is stable;
the caller selects existing approved local tools and signing identity.

The coordinator embeds the signed adapter and exact official plugin using the
approved package assembly process, then builds Dart with
`--dart-define=PW_IOS_WEBVIEW_BRIDGE_SHA256=<final-signed-bridge-raw-sha256>`.
Do not use a hash from a stripped, unsigned or subsequently re-signed binary.
This helper creates only a signed candidate, never a production acceptance.

## ABI, failures and boundaries

The C ABI is declared in `PWSharedWebViewBridge.h`. Registration is dispatched
asynchronously to the main queue. It discovers attached UIWindowScene roots,
walks child/presented controllers, requires each Flutter controller to still be
attached to its engine, and deduplicates engine identity. Multiple/no engines
fail closed. No engine/controller reference survives the queued call.

`hasPlugin` reserves a key; it does not prove registration. Success requires an
exact published official `WebViewFlutterPlugin` instance. A reserved key without
that instance fails without double-registration. One lock protects a single
pending request and generation. New completed-call requests supersede old IDs.
No global success cache, swizzling, private API or binary patch is used.

Statuses: 0 pending, 1 published official plugin, -1 unavailable/detached engine,
-2 multiple engines, -3 reserved unpublished/wrong plugin, -4 missing registrar,
-5 missing publish after registration, -6 Objective-C exception, -7 stale ID.
Error pointers are static UTF-8/ASCII and must not be freed. Swift traps cannot
be caught as Objective-C exceptions.

Dart hashes the adapter executable before loading its app-relative dyld path,
then polls asynchronously with a 10-second cooperative deadline. Hash/load/ABI/
busy/registration errors and timeouts propagate to the existing viewer error
surface; none advertise renderer readiness. A timeout cannot cancel native work,
and synchronous dyld/native calls cannot be preempted by the Dart deadline.

Only the adapter executable is hashed at runtime. The coordinator's frozen
package manifest/signature verification owns the entire adapter/plugin/framework
dependency graph; this bootstrap must not be described as runtime verification
of every dependency. The official source/binary must remain unchanged under the
declared raw and unsigned signing comparisons.

## Evidence and required acceptance

Reviewed adapter source SHA-256:
`bf782f68a8c176f12017639c7b56a84166ef311f9bc052dbb26eaae74d859e8e`.
The isolated iPhone prototype's v3 signed binary was
`4aebce55e188bc80e89322ce67358fc4cf816aff83da13f12dbae2e269e8fbb4`.
Attempt 9 reported `PASS_REGISTRATION` for initial and repeated real Pigeon
calls, and all five actual product-harness stages passed. These are isolated
physical-prototype observations supplied by the coordinating agent, not a
production installation or proof that a new candidate has the same hash.

Before production acceptance, the coordinator must independently verify:

1. Exact baseline 192 Runner equality, separately recording raw and unsigned
   byte comparisons; unchanged native numerical providers/resources and exact
   official plugin source/framework identity. Unexpected differences stop work.
2. Approved package file/plist differences, architectures, dependency/runpaths,
   exports, strict signatures/entitlements, and final adapter raw hash define.
3. Actual Pigeon and platform-view calls, first/repeated registration, rendering
   readiness, WebGL points, point-to-GLB transition, GLB and existing-work reopen.
   Registration alone does not prove rendering.
4. Failure cases: hash mismatch, unavailable/ambiguous engine, reserved key,
   missing load/export, concurrent requests and timeout. Dart boundary tests
   prove ordering/coalescing/error propagation only, never native rendering.
5. Separately authorized incremental production installation and applicable
   preserved-data gates. No production build, signing or device action is
   authorized by this README or by source integration.
