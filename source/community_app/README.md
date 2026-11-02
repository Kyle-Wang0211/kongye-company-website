# Community website source

This directory contains the Flutter source inputs for the website's community entrypoint, including anonymous public work details, the shared 3D viewer, public comments, and authenticated replies. It is website source; it does not represent a new iPhone app release.

## Source identity

- Frozen source input manifest: `c4a2e48c6ff622837db1edc887448d67f8afd634ca27982a07270fcbf602ccae`.
- Corresponding reviewed web `main.dart.js`: `d9924f28c9bf422766f560abb84f5f7a6044192c67ee54424da18a353a1e6142`.
- Entrypoint: `lib/main_community_web.dart`.
- Verified SDK: Flutter **3.47.1**, framework revision `6655482ec06e547f90abf8ae7590466f4415978d`, engine revision `5d531788691ec3404cac0cee66ead4007b177363`, Dart **3.13.1**.

The source files, dependency declarations and lockfile are copied unchanged. Generated build directories, machine-specific package mappings, logs and private build definitions are omitted. The package follows the actual successful web build dependency records, includes all declared asset inputs and local path dependency manifests, and retains the shared viewer source and its license notices. Unrelated native capture code and VM-only implementation branches are omitted.

## Build configuration

Use the SDK identity above and the checked-in `pubspec.lock`. Resolve dependencies in your own environment, then build the existing entrypoint:

```sh
flutter pub get
flutter build web --release --no-pub \
  --target lib/main_community_web.dart \
  --base-href /community/ \
  --dart-define=PW_BACKEND_REGION=china \
  --dart-define=PW_DEPLOYMENT_ID=cn-primary \
  --dart-define=PW_CN_SUPABASE_URL=https://api.kongye.space \
  --dart-define=PW_CN_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
```

Supply the deployment's **public anonymous key** yourself. Never put service-role credentials, admin keys or account sessions into a browser build. This entrypoint validates the China primary deployment identity; arbitrary alternative hosts require a separately reviewed configuration change.

Serve the output under `/community/`. Deep links use `?work=<public-work-UUID>`. Public comment reads use the same community API; comment submission and replies require an authenticated session. Publishing also requires the corresponding reviewed backend routes and policies to be deployed. The source package does not include server credentials or backend deployment configuration.

The live site additionally versions the generated bootstrap and JavaScript URLs for cache invalidation. That release packaging step does not modify the source models or comment timestamps. A new build on a different SDK or configuration is not claimed to reproduce the recorded output hash.

## Validation and scope

The original frozen candidate passed **87 tests**, including comment read/write gates, identity changes, model hash binding, byte/blob lifecycle, work deep links, login return navigation, author reply labels and relative time boundaries. Targeted analysis of ten source files reported no issues.

Those results belong to the complete original candidate. This archive is the website build input set, not the complete iOS or VM test source tree. The two included pure comment-domain/time test files are retained as focused source-level checks; the full 87-test suite is not claimed to be included or rerun from this archive.

## Assets and third-party notices

The unchanged application `pubspec.yaml` declares model assets even where a website screen does not use them directly. They are retained because they are inputs to the existing build recipe. Removing them requires an explicit recipe change. Existing asset provenance documentation and third-party license/notice files are retained in their original locations, including the shared viewer's pinned renderer and surface-comment adaptation notices. No new third-party licensing conclusions are asserted here.
