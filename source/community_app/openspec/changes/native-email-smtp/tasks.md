- [x] Replace custom email OTP functions with existing official SDK operations
- [x] Remove password from pending-confirmation exception, page and controller plumbing
- [x] Keep native email delivery mutations behind a default-off rollout flag
- [x] Pass bounded request regression and existing authentication tests
- [ ] Independent read-only review by coordinating agent
- [ ] Accept actual native delivery and recovery evidence before rollout

- [x] Continue pending registration opens the existing verifier without signup/resend and requires same-email consent
- [x] Pass two widget regressions for zero-send navigation and email-change consent invalidation
