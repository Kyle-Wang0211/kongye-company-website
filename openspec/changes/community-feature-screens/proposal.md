# Community feature-screen framework

User-approved layout: three glass screens above the existing community feed. Every pane faces straight toward the user. Center is in front and larger; left/right are symmetrical behind it. No orbit or angled screens. Three selector icons change the selected screen. Clicking any screen opens its own placeholder route with a top-left return to the community. Existing header, accounts, work data, five-to-one grid, loading placeholders and detail viewer stay in place.

Source: private portfolio revision `84b1e5ec8d8274ab34f8bfcae1b3941c40938a49`, `components/three/active-theory-pane.ts` plus preview UV/resource helpers. Reuse the existing `uPresentationLock=1` glass recipe. JSON inlining/type removal and same-origin paths are export adapters; front-facing placements, system-font placeholder captions and on-demand render scheduling are the community product recipe. No original rail/orbit code is included. Upstream notice files remain next to the exported material, without asserting blanket commercial rights. Existing community Three 0.186.1 is reused; no dependency installation.

Acceptance: all three panes remain parallel to the camera, center larger and sides symmetric at desktop/mobile widths; selectors and three placeholder links work, back returns to the community. Keep fallback links when WebGL is unavailable; respect reduced motion and stop rendering while hidden. No phone installation in this task.


2026-11-05 user revision: replace glass geometry with three flat, sharp-corner rectangles, without thickness or refraction. Use native CSS positioning and scale for the same front/behind hierarchy. A blurred elliptical floor shadow belongs to each pane and moves/scales with it during selection. Keep dot controls, swipe/keyboard selection, placeholder routes and reduced-motion behavior. The portfolio glass source remains archived but is no longer imported by the homepage. No new rendering algorithm or dependency is introduced.
