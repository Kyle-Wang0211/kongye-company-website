# Personal profile and canonical nickname
Desktop profile retains community navigation and uses avatar, editable owner nickname, social statistics and horizontal content navigation. Small screens retain full-width content. The avatar opens the personal profile.

Reuse the existing moderated profile API and profiles.display_name, linked to the immutable Auth UUID. Only approved public projection changes author presentation; pending/rejected drafts never replace live names. Read-only refresh preserves the session on transport failures and rejects stale account results. Owner author labels observe CurrentUser; other authors use canonical server projections on fetch. Homepage caches revalidate when returning/focusing and on profile-change signals. No historic comment/work author UUID changes, real account test edits, new nickname database or mobile deployment.

Acceptance: injected synthetic profile/refresh fixtures, wide/narrow widget checks, both source variants analyze/tests, static JS checks, pinned offline web builds and independent review before publish.
