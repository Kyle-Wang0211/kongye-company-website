# Website viewer standard module loading

## Intent

Product loading adaptation at base dd9b96378c168aa0c5e31fc080245d4780ba0d28. Website viewers use normal ES module imports and existing official Three.js loaders after validating the small release manifest. Whole-bundle byte verification moves to website build/export and final artifact checks. Native/default HTML continues requiring full runtime verification. Preserve packaged files, engine bytes, model authorization, comment asset identity and coordinates.

## Identity contract

Website ready/state receipts label bundleIdentity as release-manifest identity and runtimeBundleBytesVerified false. Canonical manifest validation proves internal consistency and rejects malformed hashes/paths/schema. It provides no independent release freshness or executed-byte attestation. Build/export checks reject stale manifests and mixed revision artifact bytes. Every changed manifest-covered byte changes the actual digest. No SRI, custom authority cache or new dependency is introduced.

## Acceptance fixed before implementation

Run node tests for release manifest, existing full verifier, host bridge/runtime behavior and staged browser bundles. Assert browser startup requests only the manifest through its identity reader, rejects malformed/canonical-wrong manifests, and reports truthful scope. Assert default source HTML still calls full verification. Verify every manifest-covered staged byte and negative stale-manifest/mixed-artifact copies. Confirm unchanged engine/copyright/SKP assets, unchanged Dart and clean source-input scope. Browser functionality and first-frame timing require root's separate local browser verification and independent review before publication.

## Stop conditions

Stop on cross-platform contract churn, engine/model/auth/comment changes, new dependencies, missing exact manifest coverage, or failed deterministic tests. No deployment, device action or approval to publish is included. Root adjudicates review and publication.
