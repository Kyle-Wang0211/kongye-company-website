# Community account header

Replace homepage branding/nav/product introduction/discovery heading with one header: Community left; authenticated account avatar/name right, or Log in / Sign up for guests. Retain works and footer. Reuse China primary auth and the Flutter browser session key sb-api-auth-token with official Supabase JS. Validate identity using getUser; use existing get_social_profile and ensure-generated-avatar endpoints. Preserve original generated-avatar validation (version/PNG/dimensions/SHA256). Never log credentials, generate avatars locally or expose a service key. Bind asynchronous profile responses to current identity. Add auth=signup to existing Flutter web entry, reusing EmailSignUpPage. No phone changes.

Acceptance: guest and account UI, expired/revoked session and identity-change handling; official avatar validation; no obsolete intro/nav labels in header; desktop/mobile browser checks; existing Node suite and offline Flutter web build. Production publication requires successful checks.

## User correction, 2026-11-03
Restore original brand Logo/name/roman typography. Keep Community as section label. Both guest and authenticated avatar summaries open an account menu with Settings. Move existing support/legal/company/footer markup intact into native modal Settings, outside the infinite feed. Preserve auth and viewer behavior. Guest retains login/signup menu entries. Accept only after menu/modal/keyboard and live header checks.
