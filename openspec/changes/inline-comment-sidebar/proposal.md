# Inline comments and one selected feed

Web work details keep the model and comments in separate Flex children. Desktop comments resize using Flutter's existing GestureDetector and layout constraints; the sidebar maximum is one half of the available width, with a separate eight-pixel divider and a minimum usable model area. Narrow layouts remain in-page rather than overlaying the model. Temporarily disable iframe pointer handling during divider dragging and restore it on release, cancellation, window blur, panel closure and disposal.

Resize-only parent rebuilds must not resend unchanged configure/resume requests to the web viewer. Actual activity, interaction, rotation, background and source changes continue through the existing controller. Native lifecycle behavior remains unchanged. This is lifecycle wiring using Flutter's didUpdateWidget contract, not a new smoothing, camera or rendering algorithm.

Comments use one visible list with mutually exclusive Top/Latest selection, implemented with Flutter Material SegmentedButton. Preserve the existing server ordering, section-bound cursors, cached pages, deduplicated comment identities, parent context, reply drafts and the union of authorized 3D pins. Successful submission selects Latest. Switching order must not duplicate rows, recreate model viewers or drop spatial markers. Anonymous reads and authenticated writes retain their existing permission boundaries.

Reference: Lemmy UI commit 0efd178c09b966e89a25dcb5f948e28b4131167b, post.tsx, uses one CommentSortDropdown and one selected comment view. This is an information-architecture reference only: no Lemmy code, ranking formula, dependency or AGPL component is imported. Alibaba ChatUI and Tencent TUIKit are UI/SDK references, not evidence that their hosted service backends are open source. Sculpt's existing pinned 2e0e11d adaptation remains responsible for spatial annotation interaction; it is not an end-to-end comment service.

Acceptance: desktop maximum at exactly half width; bidirectional real-browser drag and pointer restoration; no model overlap or reload; regression evidence that 25 size-only web updates cause zero configure/resume/load calls while real changes and native behavior still synchronize; overlapping Top/Latest IDs render once; independent cursors, parent context, reply/anchor actions, English and narrow keyboard interaction pass. Preserve renderer/framing/vendor bytes and all asset verification. No phone installation or backend migration is included.

Primary references:
- https://api.flutter.dev/flutter/widgets/GestureDetector-class.html
- https://api.flutter.dev/flutter/widgets/State/didUpdateWidget.html
- https://api.flutter.dev/flutter/material/SegmentedButton-class.html
- https://github.com/LemmyNet/lemmy-ui/blob/0efd178c09b966e89a25dcb5f948e28b4131167b/src/shared/components/post/post.tsx#L715
