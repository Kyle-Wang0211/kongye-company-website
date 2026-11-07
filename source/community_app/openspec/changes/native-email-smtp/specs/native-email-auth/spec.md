## ADDED Requirements

### Requirement Native email registration
The client SHALL register email and password through Supabase Auth signUp and SHALL pass only the email address to its pending-confirmation screen.

#### Scenario Confirmation required
- WHEN signUp succeeds without a session
- THEN the client presents its existing localized OTP screen
- AND verification uses verifyOTP with type email
- AND resend uses resend with type signup
- AND no pending password or custom email OTP function is used

### Requirement Continue pending email registration
The registration form SHALL allow the user to reopen its existing email OTP verification screen using the entered email and current policy consent, without signing up or resending a code.

#### Scenario Code already received
- WHEN the user enters the pending email and accepts the policies
- AND chooses Verify your email on the registration form
- THEN the existing OTP screen opens for that same email
- AND opening the screen performs no Auth request
- AND only submitting the received code invokes the existing native verifyOTP with type email
- AND changing the email revokes the form consent
- AND no passwordless sign-in flow is added

### Requirement Native password recovery
The client SHALL initiate recovery with resetPasswordForEmail and SHALL verify the recovery OTP before authenticated updateUser.

#### Scenario Invalid recovery token
- WHEN native verifyOTP fails or returns no session
- THEN updateUser is not called
- AND the user sees the existing localized error

### Requirement Native email delivery rollout gate
The client SHALL keep email mutations disabled by default until actual managed Auth email delivery and recovery validation is accepted. The approved transport may be the official Send Email Hook.

#### Scenario Native email delivery readiness absent
- WHEN PW_NATIVE_EMAIL_SMTP_READY is false
- THEN email registration, verification, resend and recovery fail with providerUnavailable before making network calls
- AND existing email password and phone authentication retain their behavior
