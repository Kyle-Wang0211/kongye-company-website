# Community website source

This directory contains the Flutter source inputs for the website's community entrypoint, including anonymous public work details, the shared 3D viewer, public comments, and authenticated replies. It is website source; it does not represent a new iPhone app release.

## Source identity

- Frozen source input manifest: `d1ed4e02055d197404a98fa413b0deed7c92480809b73e52f1c52848a3ba20cd`.
- Corresponding reviewed web `main.dart.js`: `b3bf8a42950f50dcdf8f5621deaa4b26a29e28745e983644cec85140a75c0910`.
- Entrypoint: `lib/main_community_web.dart`.
- Verified SDK: Flutter **3.47.1**, framework revision `6655482ec06e547f90abf8ae7590466f4415978d`, engine revision `5d531788691ec3404cac0cee66ead4007b177363`, Dart **3.13.1**.

The production source files, dependency declarations and lockfile are copied unchanged. Generated build directories, machine-specific package mappings, logs and private build definitions are omitted. The package follows the actual successful web build dependency records, includes all declared asset inputs and local path dependency manifests, and retains the shared viewer source and its license notices. Unrelated native capture code and VM-only implementation branches are omitted.

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

The original frozen candidate passed **96 tests**, including comment read/write gates, identity changes, model hash binding, byte/blob lifecycle, work deep links, login return navigation, author reply labels and relative time boundaries. Targeted analysis of ten source files reported no issues.

Those results belong to the complete original candidate. This archive is the website build input set, not the complete iOS or VM test source tree. The two included pure comment-domain/time test files are retained as focused source-level checks; the full 96-test suite is not claimed to be included or rerun from this archive.

## Assets and third-party notices

The unchanged application `pubspec.yaml` declares model assets even where a website screen does not use them directly. They are retained because they are inputs to the existing build recipe. Removing them requires an explicit recipe change. Existing asset provenance documentation and third-party license/notice files are retained in their original locations, including the shared viewer's pinned renderer and surface-comment adaptation notices. No new third-party licensing conclusions are asserted here.

## Spatial comment release

Sculpt-based surface pins open the corresponding approved comment inside the shared viewer; the explicit all-comments entry retains the full list and authenticated replies. The upstream reference remains revision `2e0e11d76650748ffd577b45943cd063cf097cb4`; content cards and zoom reveal are product adaptations. Public readers cannot submit comments. Thirty-second paged refresh commits a validated, model-bound snapshot atomically instead of temporarily clearing the selected marker.

The shared viewer JavaScript tests are included under `packages/pw_shared_viewer/tests/` (22 focused checks were run for this candidate). Application widget regressions are preserved in `../patches/spatial-comment-regressions-20261102.patch`; they require the complete original VM test source tree. This web archive does not claim to supply that unrelated native capture source.

The optional `browser_floating_comments_frontend.cjs` harness expects a separately supplied Playwright package. Its machine-specific module path was normalized for this archive; this optional browser harness was not executed for the release and is not part of the 22 focused checks. Shipped viewer sources are unaffected.

## Phone login singleflight update — 2026-11-02

The archived phone form now blocks duplicate sends and code submissions while a request is pending. The shared viewer, provider requests and 300-second OTP policy are unchanged. Root ran 104 Dart tests and one web build; the focused widget reproduction used the real CurrentUser queue with a controlled provider. At build time real-account login was pending; the later live acceptance is recorded in `../releases/phone-login-singleflight-acceptance-20261102.json`.

The complete change and eight widget regressions are preserved in `../patches/phone-login-singleflight-regressions-20261102.patch`. Like the existing spatial regression patch, its VM widget tests require the complete original product source closure, not only this web-oriented archive.

## Production cover parity update — 2026-11-02

Current release `production-viewer-parity-20261102-v5` copies the production App initial/canonical camera and direct-gesture behavior from revision `198a41cdeecfca0ba38a3027e120700ddca334c6`, while retaining newer web spatial-comment hooks. The camera direction is `(1.8,1.2,1.8)` with a 45-degree FOV; it is not a literal 45-degree elevation. Homepage cover frames use decoded image proportions, black background and contain, matching production WorkCard. The three replacement museum posters are actual GLB captures. Existing cloud publication records are unchanged; these exact-model-bound homepage posters remain local fallbacks when a work has no published thumbnail.

The isolated candidate passed 104 Dart tests, 78 JavaScript tests and a 23.30-second web build (maximum RSS 1,209,401,344 bytes, zero swaps). Browser layout checks at desktop and 390px width found all 12 loaded covers contained in their media frames. These checks do not constitute iPhone installation or new all-device validation. Current output identities are in `SOURCE_IDENTITY.json` and `../releases/production-viewer-parity-20261102.json`. Earlier release hashes and receipts above remain historical evidence.

## Aligned rows and staged loading — 2026-11-02

Release `aligned-grid-staged-loading-20261102-v6` supersedes natural-height media frames with fixed 3:4 contain frames and equal title/metadata regions, as explicitly requested. Data appears in API order before each cover decodes; each cover has an independent shimmer/error state. Initial and paginated shells reserve geometry. Enlarged text uses shared row metrics, including like-button padding. Three missing museum thumbnails reuse the same exact-source-bound canonical public covers as the homepage; publisher-selected thumbnails take precedence. Models are never loaded for a feed card. Work opens in a child page, and cached browser Back restores paging. Descriptions remain in details below the Viewer.

Root verification: 111 Dart and 82 JavaScript tests passed. Final web build took25.09seconds, maximum RSS1,145,536,512bytes and zero swaps. Shared App source is prepared in this archive; no production phone installation was performed. Root's controlled local browser harness held configuration/decode completion to prove metadata-before-cover at stable card bounds; these test gates are not part of the published site.

## Phone input and signup country selector (2026-11-02)

Password/SMS login has no fixed country prefix. Legacy mainland SMS input remains supported; phone signup is reachable from the email signup page and offers searchable flag/calling-code selection from 245 pinned geographic regions. Overseas SMS remains explicitly unavailable until sender registration and the production international delivery route have been verified; email signup remains available. Shared route wrappers and keyboard layouts were verified.

129 serial Dart tests passed, including inline prefix layout at mobile width and enlarged text. No package/dependency upgrades, real SMS, backend mutation or phone installation. Canonical mobile metadata originates from Google libphonenumber v9.0.42; license and derivation notices are in third_party/libphonenumber, and distributed with web output.


## Shared bilingual UI and comments, 2026-11-03

The current archive contains the shared phone signup UI (inline country prefix, 245 localized regions), paired AppL10n resources and static exports, localized comments/notification/legal views, inline web comments and real sign-in routing. Every viewer resource remains hash-checked, with at most four fetch/hash workers. Native installation and international account registration are separate acceptance steps; a console delivery test to a user-owned US number succeeded, but international app OTP remains disabled pending backend integration. Existing versioned legal content is preserved.
