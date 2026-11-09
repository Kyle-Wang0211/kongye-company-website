# Account UI and nickname persistence

Accepted behavior, 2026-11-09:

- Email login uses password only. Email six-digit codes verify registration ownership or password recovery; no email OTP login entry/API is introduced.
- Phone login offers password and SMS code. SMS login targets existing accounts only. Switching to email resets the login method to password.
- Email and phone registration require a nickname, a password of at least eight characters, and an exactly matching confirmation before any signup request. Phone registration uses official phone/password signup before SMS verification.
- Signup/resend preserves the selected nickname. Authenticated nickname changes save to the existing canonical profile display_name; the current-user UI refreshes that value and rejects stale asynchronous results. No production schema change is required.
- Web, mini web and mobile share the accepted minimalist UI: country PNG and chevron, language-appropriate country search, readable labels, forgot-password below/right of the password line, and six separate code boxes.
- Recovery keeps verification before a separate two-password page, then returns to login without entering the community.

Verification: synthetic SDK/HTTP and widget tests, targeted analyzer, locked offline web builds, immutable file manifests and fresh read-only review. No real production account is a test fixture; no live code is sent by an agent. Public release preserves unrelated website and viewer changes.

Mobile source preparation is separate from installation. Registered version 219 must install before later auth updates. Rebase/merge onto the actual installed predecessor and its complete source; the old 218-based frozen 220 is held and must not overwrite 219. A new concrete candidate follows the canonical device-data, authorization and queue gates.

Review acceptance refinements: leaving an SMS login route cancels its owned pending verification at actual pop initiation, including reverse transitions. Submitted phone/signup nickname/password are bound immutably to the issued challenge; pending inputs are disabled and an explicit restart clears that binding. Synthetic delayed-completion tests cover both cases.

## Accepted responsive refinement, November 9

Keep auth form content centered in the middle third of a wide viewport. Group headings, labels, inputs, six code boxes, consent, and actions in the same column; retain full-width top navigation. Use one-third width when that fits a usable form, a 360px content floor limited by available viewport width, and 16–24px gutters on small screens. Every input has a persistent visible label above it, with wrapping and no truncation. Short height/keyboard allows vertical scrolling; no horizontal overflow at 320px or larger text. Typed data must survive viewport resizing. Applies to login, both registrations, signup/login verification and recovery/new-password pages across mobile and both web entries.

User clarification: the middle-third width applies to wide web layouts only. Native mobile uses all available width in portrait and landscape, retaining normal side padding; narrow web uses the same full-width form treatment. All labels remain persistent and wrap.
