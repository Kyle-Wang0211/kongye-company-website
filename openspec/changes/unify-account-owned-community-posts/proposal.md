# Unified account-owned community posts

The homepage previously inserted three local museum cards synchronously and inserted network works ahead of them after the first feed and author requests. A refresh therefore briefly displayed a separate three-card list.

All displayed cards now come from the same public, published, approved community feed. The three CC0 museum captures must first be published through the existing authenticated submission, private upload, rendering and moderation route and belong to the provisioned account with display name 林远. No fabricated social counts or dates are introduced. Source licensing stays in the work descriptions.

Retain old `?example=` links as slug-to-published-work-ID aliases only. Resolve these through the same filtered work API. New shares always use `?work=`. A failed request must offer retry without injecting local placeholder works. Bound configuration requests to the existing 15-second network deadline.

Acceptance: all three published work IDs and the public author projection are read back from the live API; Node loading tests cover delayed feed/author responses, failure/retry/deduplication and old-link/new-share identity. Existing viewer bundle hashes remain unchanged. No phone build, installation or device operation is included.
