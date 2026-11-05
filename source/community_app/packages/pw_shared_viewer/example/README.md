# Portable shared-viewer host fixture

This isolated Flutter application embeds `pw_shared_viewer` and has no production record/account/job access. Web receipts use `pwFlutterHostReady`, `pwFlutterHostState` and `pwFlutterHostError`; native receipts are tagged `PW_VIEWER_*` logs.

Use the existing locked Flutter SDK/cache. Resolve only offline and build without resolving again:

```sh
flutter pub get --offline
flutter build ios --debug --no-pub --no-codesign
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run
```

On Web, supply `?model=<same-origin-url>&format=glb` (or `ply`/`skp`). Native fixture model URLs/formats may be supplied using compile-time `VIEWER_MODEL_URL` and `VIEWER_MODEL_FORMAT`. For actual application-owned local files use `SharedViewerController.loadLocalFile` after caller-side authorization. No production container or model is implicitly mounted.

An unsigned iOS build and actual Flutter Web rendering are recorded in the corresponding OpenSpec change. The generated Flutter Android project has not been built: its Gradle/SDK dependencies are unavailable locally. The separately compiled native Android fixture in `../platform_hosts/android/` uses the same rendering resources without those dependencies. No target has been installed by this task; no successful build is a device-rendering claim.

The example lock follows the installed Flutter SDK's meta1.18.3/vector_math2.4.0 constraints, resolved from the existing offline cache; the product application's dependency lock remains unchanged.
