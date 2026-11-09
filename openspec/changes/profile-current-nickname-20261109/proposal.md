# Personal profile and canonical nickname
Desktop profile retains community navigation and uses avatar, editable owner nickname, social statistics and horizontal content navigation. Small screens retain full-width content. The avatar opens the personal profile.

Reuse the existing moderated profile API and profiles.display_name, linked to the immutable Auth UUID. Only approved public projection changes author presentation; pending/rejected drafts never replace live names. Read-only refresh preserves the session on transport failures and rejects stale account results. Owner author labels observe CurrentUser; other authors use canonical server projections on fetch. Homepage caches revalidate when returning/focusing and on profile-change signals. No historic comment/work author UUID changes, real account test edits, new nickname database or mobile deployment.

Acceptance: injected synthetic profile/refresh fixtures, wide/narrow widget checks, both source variants analyze/tests, static JS checks, pinned offline web builds and independent review before publish.

## Browser acceptance corrections
Observed immutable icon font URL retained an obsolete browser-cached subset while the font manifest revalidated. Build postprocessing now gives subset fonts content-hash filenames, preserves old paths and leaves compiled JS unchanged.

Homepage uses official persisted Supabase session. Initial restoration is not a signed-out state; focus/return must not erase known account presentation. Cached name/avatar are hints only after SDK owner matching, never authentication or permission authority. Server revocation/signout/switch still clear old presentation; transport failure preserves it.

## Full profile navigation
Own likes/favorites/history render through existing account-library entries embedded beneath the profile header and tab strip. The sidebar remains mounted; work selection returns to the works list. Compact screens use the same hierarchy with horizontal tabs and an overflow settings menu. Owner changes dispose private slots immediately; stale requests cannot repopulate a different account. Existing standalone library routes retain their navigation behavior. Retain prior content-versioned font assets across releases so already-open clients can resolve immutable URLs.

Homepage account entry and both static consumers must reference the identical versioned ESM account-module URL; distinct query strings execute multiple SDK owners and compete for the same header/session. Regression checks bind all three references to one module identity.
