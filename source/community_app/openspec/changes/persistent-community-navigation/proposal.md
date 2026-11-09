# Shared community navigation frame

## Why
The message inbox used a standalone Navigator page, so entering it replaced the profile-only sidebar. The user requires the community sidebar to remain the same across community pages.

## Behavior
- Mount the existing canonical four-module sidebar above the account-owned web Navigator: 热门 / 关注 / 我的 / 消息.
- Preserve one frame through inbox, conversation, profile, profile editing and internal routes. Direct message links include the frame. Standalone authentication and full-screen work entry retain their existing layout.
- Selection may inherit a destination from an unnamed detail page; navigation deduplication must use actual top route identity and arguments. Clicking Messages from a conversation opens the inbox; clicking Me from a detail opens the owner profile.
- Isolate route BlockSemantics within a content semantic container; all four sidebar buttons remain exposed and actionable on inbox, profile, return and compact rail.
- Keep existing account-switch Navigator isolation. Keep drafts mounted on internal navigation; confirm discarding unsaved profile edits before full-document navigation.
- Retain canonical sidebar dimensions/icons, 20-character nickname counter and fixed five-visible-line, 160-character bio area. No backend, dependency, device or production-account changes.

## Verification
Both community variants: 36 targeted widget tests and seven-file analyzer pass; fresh read-only review. Locked offline web builds. Immutable static deployment through owner-controlled official operation, exact public asset readback and live browser confirmation. Never restore revoked SSH privileges.
