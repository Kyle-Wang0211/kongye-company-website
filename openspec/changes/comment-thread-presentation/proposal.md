# Comment thread presentation

Identify actual work-owner comments with a black badge and white Author label next to the author name. Replies use 24px avatars and 42px indentation. Reuse existing comment-like service. Dislike saves a per-account/region/work hidden-comment preference on the current device, with undo and restoration. Filter the comment list and 3D callbacks consistently. SharedPreferences is the existing dependency. This release deploys the website only.


## Inline hidden state — 2026-11-06 user revision

Personal dislike retains the comment row and replaces content with a gray hidden placeholder. Use outlined broken-heart for normal state and filled gray broken-heart for hidden state. Clicking the same control restores the original published comment. Remove the header restore entry, separate restore sheet and undo snackbar. Keep personal preferences local and account-partitioned. Hidden comment pins/attachments/actions remain suppressed. Center the black author badge using tight line metrics and explicit centered alignment.
