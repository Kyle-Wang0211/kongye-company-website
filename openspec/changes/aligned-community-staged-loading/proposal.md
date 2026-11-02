# Aligned community rows and staged loading

## User-approved direction and immutable inputs
Website base 83180b4a30a3e6b0bc88e7e9d43eb479646f2629. User's 2026-11-02 correction replaces natural-height card frames with equally sized media frames in aligned rows. Preserve the black/white product style and current canonical viewer camera. User supplied a grid reference and explicitly requested gray shimmer, metadata before media, and no homepage body descriptions.

## Behavior
Use fixed 3:4 media frames, centered contain on black (complete image pixels, no crop), and equal title/metadata areas. Before the API resolves, render inert gray shimmering card shells. After work and author data resolve, display true title/author/count/time immediately while the media frame remains a shimmer. Decode each image separately, then reveal only that cover. Its load or error must never change card dimensions or reorder works. Reduced-motion mode uses static placeholders. Media failure leaves a finite, legible retry/placeholder state with the metadata usable.

Pagination retains existing cards, appends bounded skeletons for the next request, atomically replaces/removes only its skeletons on success/error, and preserves cursor filters, ordering, single-flight and deduplication. Never flash three local-only works or invent titles/authors/counts. Homepage cards have no description paragraphs; full descriptions remain below the 3D Viewer in work details.

Apply the same layout/readiness contract to the shared Flutter community source. Preserve authentication, read/write gates, viewer modules, account/author bindings and backend data. This task prepares shared App source changes but does not authorize a production-phone installation; website deployment is authorized by the ongoing request.

## Ownership, acceptance, stops
Root owns static homepage JS/CSS, test integration, archive/build packaging, browser validation, review and website deployment. Leaf worker exclusively owns isolated candidate Dart community grid/card/feed files and related widget tests. Fresh reviewer is read-only. No shared write domains, dependency downloads, backend changes, device commands, AI images, unrelated refactors or new algorithms.

Require regressions proving equal frame/card bounds for mixed portrait/landscape covers, real metadata visible while cover completion is blocked, independent staged media reveal/error handling, initial and pagination skeleton cleanup, stable order/cursors and details-only descriptions. Root runs focused/full existing tests, one bounded serial web build, desktop/mobile browser checks, secret scan and independent review. Stop on source drift, failed tests, missing locked dependency, unbounded loading, authentication regression or unsafe device/remote operation. Final claims distinguish web deployment from phone installation.

## Additional user instruction
Opening a work navigates to its existing `/community/?work=UUID` child page, with ordinary browser back navigation. Remove the homepage modal and duplicate outer description/interaction chrome. Legacy share URLs still resolve the same real public work before navigating. The Flutter detail page retains the body description below its Viewer. For three museum models whose cloud covers are absent, the shared card may reuse the existing homepage canonical cover only by exact approved model-content identity; published user-selected thumbnails keep precedence. No backend record changes.
