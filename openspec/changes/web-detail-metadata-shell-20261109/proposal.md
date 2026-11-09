# Public work detail metadata shell and numeric loading

Frozen input: e7ba682bd503937b077d5f1d19e0875d165845df. Applies identically to community_app and miniprogram-community. No dependency, renderer algorithm, resource, protocol, account, authentication, device or cloud changes.

## Accepted behavior
User's latest correction supersedes an earlier metadata-first download ordering request: model initialization stays immediate and parallel. Do not add post-frame/future delays to WorkDetailPage. While PublicWorkEntry resolves its bounded public-work repository future, PublicWorkOpening must show the full title/author/description/statistics layout. Render known feed-handoff fields immediately; render unknown fields with the existing homepage skeleton (CommunityShimmer in community_app; SkeletonBox in miniprogram-community). Preserve the existing repository timeout and explicit failure/retry branch. A confirmed absent description is empty, not an infinite skeleton. Replace loading metadata normally when the repository resolves.

Loading circles always carry a numeric percentage, starting at zero. The shared viewer retains its last known number when total bytes become unknown; its ring may remain indeterminate. Download completion must not show 100% while rendering is still pending (cap visible loading text at 99%). No timers or fabricated progress. A new source or recovery resets the retained number. Remove the entire comment text-length helper row; preserve all validation and length limits.

## Ownership and verification
Leaf implementation owns only both source projects and this new OpenSpec document in the isolated worktree. Main agent owns independent review, web compilation/deployment, integration and acceptance. No production device operations.

Offline tests: both projects' new detail_metadata_first_test.dart and model_progress_label_test.dart, plus community_app's existing public_work_repository_test.dart (miniprogram-community has no equivalent repository suite). Assert unresolved metadata shell, partial handoff replacement, first painted known metadata alongside immediate GLB/PLY dispatch, numeric unknown→known→unknown→download-complete labels, unchanged bounded errors/auth handling. Targeted flutter analyze --no-pub on changed Dart and tests; git diff --check. Fixed Flutter revision 6655482ec06e547f90abf8ae7590466f4415978d. Root provides actual browser and deploy validation.

## Loading surface clarification
The main model region must shimmer throughout initialization, including missing covers, pending network cover images, and the real ProductModelView download/render readiness overlay. Reuse each project's existing homepage skeleton with MediaQuery reduced-motion behavior. Keep the numeric ring on top and remove the overlay at the existing first-frame readiness boundary; never cover a ready viewer.

## HTML startup before Flutter's first frame
The browser can display index.html before Flutter initializes. For URLs carrying a work query parameter only, a static HTML shell immediately provides header/title, model area, author/description/count placeholders, existing gray shimmer colors and a fixed numeric 0% ring. No metadata fetch, timer or fabricated progress is introduced. Non-work routes remove the hidden shell without changing their startup background. CSS prefers-reduced-motion disables shimmer/spinner animation. The pinned engine's official flutter-first-frame event removes the shell through a once listener, yielding to Dart's already-verified shell and Viewer. Bootstrap configuration and existing external scripts are unchanged.

Each project adds a dependency-free Node VM test for query activation, non-work behavior, complete static layout, reduced motion, retention before the event and one-shot removal after it. This HTML delta does not require changing the already-built Dart semantics; root owns HTML artifact packaging and actual browser validation.
