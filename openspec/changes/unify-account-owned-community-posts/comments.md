# Public comments and author replies

The public work viewer opens the same Flutter WorkDetailPage and CommunityCommentsPanel used by the App. A public work link retains its work identity through sign-in. Anonymous visitors can read published comments and surface points; all mutations still require authentication. Model bytes and comment asset SHA remain bound before surface comments appear.

Author replies are ordinary replies with a parent ID. The badge appears only when the comment's account ID equals the work's author ID and the comment has a parent. Display names do not confer author identity. Existing backend validation keeps replies within the same public work and asset revision.

Times use local HH:mm through 24 hours, then local calendar yesterday/previous day, otherwise month/day. Stored creation times are unchanged.

Validation: 79 targeted Flutter tests, 55 comment gateway tests, 24 isolated SQL setup/test stages, and 18 homepage tests passed. The dependency lock and renderer source are unchanged. Anonymous reads currently share a 120/minute service quota. Live endpoint checks additionally verify public read, private-work exclusion, and authenticated-only writes.
