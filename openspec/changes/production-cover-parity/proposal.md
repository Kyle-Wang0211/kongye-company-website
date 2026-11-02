# Production cover and viewer parity

## Frozen contract
Input website revision: 228f1bea28bebac6906572fd5e595c6bc7122b03. Reference App source revision: 198a41cdeecfca0ba38a3027e120700ddca334c6 (209 lineage recorded by the existing release ledger, not a new device probe).

Homepage cards must show full cover pixels at their natural aspect ratio on black, centered with contain, matching production WorkCard/masonry_policy. Loading placeholders may use 3:4; actual artwork must never retain a forced height. Existing user covers remain the user's covers.

Port the production shared initial/canonical cover camera and direct controls; preserve the website's newer spatial-comment hooks. Camera is the unchanged production vector (1.8,1.2,1.8), Y-up, zoom 1, FOV 45, geometry framing distance times 1.05. No new framing algorithm or literal 45-degree-elevation rule. Re-render the three museum covers from their unchanged GLBs through this shared capture path. No AI images or image editing.

## Ownership and limits
Root owns website source, generated assets, serial host rendering, tests, review integration and deployment. Recon agent is read-only. Phone/device writes, dependencies, backend policies, authentication, model geometry, moderation, work ownership and comments are outside scope. Never revert unrelated changes. Use existing pinned SDK/dependencies without installation. One renderer and one build at a time; release renderer after captures.

## Acceptance and stop conditions
- Production initial_cover_camera tests must reproduce failure before the port and pass afterward. Run existing JS renderer, bridge, spatial comment and homepage tests.
- Real browser: loaded image bounds contained in its card at desktop/mobile sizes; image frame aspect equals decoded image aspect, black backing; three refreshed museum covers match production canonical capture with textures loaded and unclipped pixel bounds.
- Preserve public browsing and work deep links, logged-in state and spatial comments; no write actions for testing.
- Freeze source/output hashes; independent fresh-context read-only review before push. Stop on unexplained source drift, identity mismatch, failed tests, broken render, missing existing dependency or credential scope. No phone installation.
- Push reviewed exact files to the existing website repo and verify Pages success plus live content identities. Browser evidence proves this browser, not every device.
