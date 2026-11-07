# Overlap public work author and like reads

## Frozen input and scope

Site revision dd9b96378c168aa0c5e31fc080245d4780ba0d28. Limit this product adapter change to PublicWorkRepository.fetch and its focused Dart regression. The public work query remains authoritative. After it succeeds, overlap the bounded author and authenticated like reads. The existing Viewer mounting boundary and FeedWork projection remain intact.

## Required behavior

Retain the public visibility, moderation, publication and deletion filters. Anonymous loads issue no like read. Preserve missing-author and missing-like defaults, profile-error precedence, the post-profile account check, original like errors and stack traces, and the post-like account check. Attach a like error handler immediately so a failure while profile remains pending cannot become an unhandled asynchronous error. Every request retains its 15 second timeout. Account mismatch must not return a FeedWork. If the captured account temporarily differs before author lookup, skip the early like read. When the original account is restored before the post-author identity check, issue the like read after that check, preserving the original sequential behavior. A skipped early request must never stand in for an absent like. Existing futures do not cancel HTTP operations, so an overlapping like read may finish after the load has failed or its route has gone away.

This is a product adapter using the official Dart Future.then/onError API. A direct Future.wait replacement reports the first completed failure and would change existing profile/auth failure precedence. Official support is documented at https://api.dart.dev/dart-async/Future/then.html and https://api.dart.dev/dart-async/Future/wait.html. Keep the locked Supabase and PostgREST versions. No Viewer, auth UI, algorithm, schema, dependency version or deployment changes belong to this candidate.

## Acceptance and stopping

Deferred fake-HTTP tests must prove both dependent reads start before either finishes, unchanged FeedWork values and filters, anonymous/default behavior, error ordering without uncaught futures, stale-account rejection, the A→B→A account-return deferred-query path, and the existing 15 second deadlines. Run focused analysis using the existing pinned Flutter and offline dependency cache. Stop on source drift, missing cached dependencies, scope conflict or failed acceptance. Existing JS feed test failures are recorded separately and cannot validate this Dart implementation. Browser timing after integration is required before claiming any measured loading improvement.
