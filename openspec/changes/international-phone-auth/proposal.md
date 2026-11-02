# Login account field and international phone signup

User-approved behavior (2026-11-02): remove fixed +86 from phone/desktop login; show flag and country calling code only for phone signup. Preserve the existing minimalist style and shared Flutter implementation.

- Password login keeps existing email/E.164 parsing and legacy China national-number compatibility.
- SMS login uses one number field, accepts explicit +country numbers and retains China national-number compatibility; sending and verification retain synchronous duplicate-request guards.
- Email signup remains available and gains an explicit phone-signup entry. Phone signup has a searchable country/region selector, with the compact flag and calling code embedded at the leading edge inside the same bordered number field (user refinement23:20). Full international numbers are not prefixed twice. Country selection never claims SMS delivery availability.
- Country metadata must have a fixed authoritative identity and required reuse checks. No new SDK or package resolution.
- Check actual Aliyun international SMS channel/SenderID/target-country requirements. Do not claim activation or delivery based on a UI selector or default channel. Do not alter existing domestic SMS credentials/routes.
- Prepare the mobile successor from verified installed209 source; do not install before candidate-specific approval and the existing incremental-update gates. Report mobile preparation, installation and web deployment separately.

Acceptance: focused widget tests for no fixed login prefix, signup reachability/selector and preserved phone numbers; duplicate-send regression; full serial Dart suite and browser desktop/mobile UI; public website bytes match reviewed build. International delivery remains unverified without a real authorized target number.

Execution: isolate from V6 source -> RED focused auth tests -> minimal auth UI/normalization changes -> GREEN and fresh read-only review -> one serial web build -> archive/source manifests -> push existing website repository main and verify HTTPS. Stop for actual tests/review/build failure, unreviewed country metadata or remote legal/payment authorization requirement.

## Accepted refinements, November 3

Use existing AppL10n/LocaleNotifier as the shared Chinese/English source, with derived catalogs for static pages. Keep all 245 region names paired; retain selected country and typed input across language changes. Localize comments, notifications and legal UI while preserving versioned governing Chinese content. User-created titles, profiles and server moderation decisions remain content, not translated UI.

Web work comments open within the detail page: desktop right sidebar; narrow-screen in-page region, preserving the viewer on close/reopen. Anonymous sign-in action must open the actual auth flow and return to the work. Refresh shows busy state and prevents duplicate requests. Native comment presentation is retained.

Load work cards/covers independently of profile hydration. Viewer startup continues to validate every manifest asset and byte hash, with at most four concurrent fetch/hash operations; failure drains inflight work and fails closed. Renderer, framing and model identity requirements are unchanged.

A single Aliyun-console test reached a user-owned US number and receipt was confirmed. This proves that delivery sample only. International app registration remains gated pending handler integration, dependency packaging and end-to-end account verification.
