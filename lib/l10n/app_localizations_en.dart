// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appBrand => 'PocketWorld';

  @override
  String get splashSubtitle => '3D capture · minimalist workbench';

  @override
  String get splashStartingEngine => 'Starting 3D engine…';

  @override
  String get splashRestoringSession => 'Restoring session…';

  @override
  String get splashPreparingSignIn => 'Preparing sign-in…';

  @override
  String get authServiceUnavailable =>
      'Sign-in service is unavailable. Check your network and retry.';

  @override
  String get authRetry => 'Retry';

  @override
  String get authAutoRetrying => 'Retrying automatically in the background';

  @override
  String get splashWaking3DEngine => 'Waking 3D engine…';

  @override
  String get splashRendererUnavailable => 'Renderer unavailable, retrying…';

  @override
  String get communityEmptyTitle => 'No works yet';

  @override
  String get communitySearchHint => 'Search works';

  @override
  String get communityTabHot => 'Hot';

  @override
  String get communityTabNearby => 'Nearby';

  @override
  String get communityTabDiscover => 'Discover';

  @override
  String communityOnlyAuthor(String name) {
    return 'Only @$name';
  }

  @override
  String get communityClearAuthorFilter => 'Show all';

  @override
  String get communityTopicTitle => 'Editors\' Picks';

  @override
  String get communityTopicBody =>
      'Spaces we picked by hand. Want to be here? Publish what you scanned.';

  @override
  String get communityTopicCaptureTitle => 'Scan it better';

  @override
  String get communityTopicCaptureBody =>
      'Walk around it, go slow, don\'t shoot from one spot. Full coverage is what keeps the model from breaking up.';

  @override
  String get communityTopicViewerTitle => 'Tap to turn it';

  @override
  String get communityTopicViewerBody =>
      'Everything here is real 3D. Drag it and look again from another angle.';

  @override
  String get communityNearbyComingSoon => 'Nearby is coming soon — stay tuned.';

  @override
  String get meMyWorksEmpty =>
      'No works yet — tap the camera to start your first capture.';

  @override
  String get scanLifecycleCompleted => 'Completed';

  @override
  String get createOptionCapture => 'Capture';

  @override
  String get createOptionUpload => 'Upload';

  @override
  String get createImportingGlb => 'Importing GLB model…';

  @override
  String createImportPickerFailed(String error) {
    return 'Couldn\'t open file picker: $error';
  }

  @override
  String get createImportFileUnreadable => 'Couldn\'t read the selected file';

  @override
  String get meTapHintInProgress => 'Generating 3D model — opens when ready';

  @override
  String get meActionRename => 'Rename';

  @override
  String get meActionDelete => 'Delete';

  @override
  String get meActionCancel => 'Cancel';

  @override
  String get meActionSave => 'Save';

  @override
  String get meDuplicateWorkName =>
      'A work with this name already exists. Please choose another name.';

  @override
  String get meRenameDialogTitle => 'Rename';

  @override
  String get meDeleteDialogTitle => 'Delete this scan?';

  @override
  String meDeleteDialogContent(String name) {
    return 'This will permanently delete \"$name\" and all local original photos, point cloud, reconstruction databases, and caches. This action cannot be undone.';
  }

  @override
  String get defaultUntitledScan => 'Untitled';

  @override
  String get captureWarmupHint => 'Initializing AR…';

  @override
  String get captureReadyHint => 'Tap the center button to aim';

  @override
  String get captureAimHint => 'Align the guide, then tap ✓ to lock and start';

  @override
  String get captureMaterialTooSparseHint =>
      'Keep scanning a moment longer before stopping';

  @override
  String get captureLockFailedHint =>
      'Surface not detected or tracking not ready — point at the object\'s surface and try again';

  @override
  String captureInitFailed(String error) {
    return 'Initialization failed: $error';
  }

  @override
  String captureRecordingStartFailed(String error) {
    return 'Couldn\'t start recording: $error';
  }

  @override
  String get relativeJustNow => 'just now';

  @override
  String relativeMinutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String relativeHoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String relativeDaysAgo(int n) {
    return '$n d ago';
  }

  @override
  String relativeWeeksAgo(int n) {
    return '$n w ago';
  }

  @override
  String relativeMonthsAgo(int n) {
    return '$n mo ago';
  }

  @override
  String get meSettingsTitle => 'Settings';

  @override
  String get meNotifications => 'Notifications';

  @override
  String get meNotificationsOn => 'On';

  @override
  String get mePrivacy => 'Privacy';

  @override
  String get meNotificationsOff => 'Off';

  @override
  String get mePrivacyPublic => 'Public';

  @override
  String get mePrivacyPrivate => 'Private';

  @override
  String get meSettingNotConfigured => 'Not configured';

  @override
  String get meLanguage => 'Language';

  @override
  String get meLanguageZh => '简体中文';

  @override
  String get meLanguageEn => 'English';

  @override
  String get meAbout => 'About';

  @override
  String get meSignOut => 'Sign out';

  @override
  String get meDetailRunningProcessing => 'Processing';

  @override
  String get meDetailRecordNotFound => 'Record not found';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authCreateAccount => 'Create your account';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authEmailHint => 'Email';

  @override
  String get authAccountChinaHint => 'Phone or email';

  @override
  String get authAccountInternationalHint =>
      'Phone (include country code) or email';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authPasswordHint => 'Password';

  @override
  String get authPasswordHintMin => 'Set password (min 8 chars)';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authTermsAcceptance =>
      'By signing up you agree to PocketWorld\'s Terms of Service and Privacy Policy.';

  @override
  String get authErrorDialogTitle => 'Something went wrong';

  @override
  String get otpVerifyTitle => 'Verify your email';

  @override
  String otpVerifySubtitle(String email) {
    return 'We sent a 6-digit code to $email. Enter it below to finish signing up.';
  }

  @override
  String get otpResend => 'Resend code';

  @override
  String otpResendCooldown(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get otpResendSent => 'Code re-sent';

  @override
  String get otpUseAnotherEmail => 'Use a different email';

  @override
  String get resetTitle => 'Reset password';

  @override
  String resetSubtitleEnterCode(String email) {
    return 'We sent a 6-digit code to $email. Enter the code to continue.';
  }

  @override
  String get resetSendCode => 'Send code';

  @override
  String get resetNewPasswordHint => 'New password (min 8 chars)';

  @override
  String get resetConfirm => 'Reset password';

  @override
  String get captureModeLocal => 'Local';

  @override
  String get captureModeRemoteLegacy => 'Remote';

  @override
  String get captureModeNewRemote => 'New Remote';

  @override
  String get languageDialogTitle => 'Language';

  @override
  String get languageDialogChinese => '简体中文 (Chinese)';

  @override
  String get languageDialogEnglish => 'English';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get meTabProjects => 'Projects';

  @override
  String get meBadgeGenerating => 'Generating';

  @override
  String get meBadgeUnfinished => 'Unfinished';

  @override
  String get meBadgeDone => 'Done';

  @override
  String get meTabDrafts => 'Drafts';

  @override
  String get defaultImportedScan => 'Imported model';

  @override
  String get meDisplayName => 'Display name';

  @override
  String get meDisplayNameDialogTitle => 'Edit display name';

  @override
  String get meDisplayNameDialogHint => 'New display name (up to 20 chars)';

  @override
  String get meDisplayNameUpdated => 'Display name updated';

  @override
  String meDisplayNameUpdateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get meAnalyticsTitle => 'Help improve the app';

  @override
  String get meToggleOn => 'On';

  @override
  String get meToggleOff => 'Off';

  @override
  String get legalUserAgreement => 'User Agreement';

  @override
  String get legalPrivacyPolicy => 'Privacy Policy';

  @override
  String get authTermsAcceptancePrefix => 'By signing up you agree to:';

  @override
  String get mePlatformRules => 'Platform Rules';

  @override
  String get meIpRegion => 'IP location';

  @override
  String get meIpRegionUnknown => 'Unknown';

  @override
  String ipRegionLabel(String region) {
    return 'IP location: $region';
  }

  @override
  String get authPhoneEntry => 'Sign in with SMS code';

  @override
  String get authPhoneNumberHint => 'Phone number';

  @override
  String get authPhoneDisplayNameHint => 'Display name (optional)';

  @override
  String get authPhoneSendCode => 'Send code';

  @override
  String authPhoneWillSend(String target) {
    return 'We\'ll send a one-time code to $target. Standard SMS rates may apply.';
  }

  @override
  String authPhoneCodeSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get authPhoneCodeHint => '6-digit code';

  @override
  String get authPhoneSubmitSignIn => 'Sign in';

  @override
  String get authPhoneSubmitSignUp => 'Complete sign up';

  @override
  String get authPhoneChangeNumber => 'Use another number';

  @override
  String get authPhoneYourNumber => 'your phone';

  @override
  String get meHandle => 'Username';

  @override
  String get meHandleNotSet => 'Not set';

  @override
  String get meHandleDialogTitle => 'Set username';

  @override
  String get meHandleDialogHint => 'Lowercase letters, numbers, . and _ (2-32)';

  @override
  String get meHandleDialogNote =>
      'Your username is unique and lets people find you. It can only be changed once every 3 days.';

  @override
  String get meHandleUpdated => 'Username updated';

  @override
  String meHandleUpdateFailed(String error) {
    return 'Username update failed: $error';
  }

  @override
  String get sfmSaveDraft => 'Save Draft';

  @override
  String get sfmNext => 'Next';

  @override
  String get sfmDone => 'Done';

  @override
  String get sfmBackToDrafts => 'Back to drafts';

  @override
  String get sfmEditSelection => 'Edit selection';

  @override
  String get sfmSelectionSaveTitle => 'Save selection changes?';

  @override
  String get sfmSelectionSaveBody =>
      'You adjusted the selection box. Saving keeps only the points inside it in the preview and the delivered cloud.';

  @override
  String get sfmSelectionSaveKeep => 'Save';

  @override
  String get sfmSelectionSaveDiscard => 'Discard';

  @override
  String get sfmSelectionSaveCancel => 'Cancel';

  @override
  String get sfmGeneratingFinalCloud => 'Generating final point cloud…';

  @override
  String get captureFinishing => 'Wrapping up capture…';

  @override
  String get sfmReconFailedKeptFrames =>
      'Reconstruction failed — captures kept';

  @override
  String get sfmChipFinalRecon => 'Final reconstruction';

  @override
  String sfmChipReconstructing(int count) {
    return 'Reconstructing · $count pts…';
  }

  @override
  String get etaCalculating => 'Estimating…';

  @override
  String get etaUnderMinute => 'Time remaining · under a minute';

  @override
  String etaMinutes(int n) {
    return 'Time remaining · about $n min';
  }

  @override
  String sfmChipReconDone(int count) {
    return 'Reconstruction complete · $count pts';
  }

  @override
  String get sfmChipReconEnded => 'Reconstruction ended';

  @override
  String get sfmQueueDrainedFinal =>
      'Frame queue drained · generating final point cloud';

  @override
  String sfmProgressFedQueued(int fed, int queued) {
    return 'Completed $fed/$queued frames';
  }

  @override
  String sfmElapsedSec(int secs) {
    return '${secs}s';
  }

  @override
  String sfmElapsedMinSec(int min, int sec) {
    return '${min}m ${sec}s';
  }

  @override
  String sfmStage1(String elapsed) {
    return 'Organizing frames… (stage 1/4 · $elapsed)';
  }

  @override
  String sfmStage2a(String elapsed) {
    return 'Completing matches… (stage 2/4 · $elapsed)';
  }

  @override
  String sfmStage2b(String elapsed) {
    return 'Global optimization… (stage 2/4 · $elapsed)';
  }

  @override
  String sfmStage3(String elapsed) {
    return 'Extracting colors… (stage 3/4 · $elapsed)';
  }

  @override
  String sfmStage4(String elapsed) {
    return 'Saving point cloud… (stage 4/4 · $elapsed)';
  }

  @override
  String get viewerSparseCloudTitle => 'Sparse Point Cloud';

  @override
  String viewerTitleWithCount(String title, int count) {
    return '$title · $count pts';
  }

  @override
  String get viewerLoadFailed => 'Failed to load point cloud';

  @override
  String get selectionRotatePointCloud => 'Rotate';

  @override
  String get selectionNoCloud => 'No point cloud data';

  @override
  String get cubeFaceTop => 'Top';

  @override
  String get cubeFaceFront => 'Front';

  @override
  String get cubeFaceRight => 'Right';

  @override
  String get cubeFaceBack => 'Back';

  @override
  String get cubeFaceLeft => 'Left';

  @override
  String get cubeFaceBottom => 'Bottom';

  @override
  String get denseStageUnavailable =>
      'Processing is not available on this device yet';

  @override
  String get selectionCancel => 'Cancel';

  @override
  String get selectionDiscardTitle => 'Discard changes?';

  @override
  String get selectionDiscardConfirm => 'Discard Changes';

  @override
  String get selectionResetRotation => 'Reset Rotation';

  @override
  String get selectionResetZoom => 'Reset Zoom';

  @override
  String get selectionResetBoxSize => 'Reset Box Size';

  @override
  String get publishAction => 'Publish to Community';

  @override
  String get publishNotReady => 'Available after reconstruction';

  @override
  String get publishAlreadyDone => 'Published';

  @override
  String get publishSheetSubtitle =>
      'Once published, anyone can see this work in the community.';

  @override
  String get publishFieldTitle => 'Title';

  @override
  String get publishFieldDescription => 'Description (optional)';

  @override
  String get publishConfirm => 'Publish';

  @override
  String get publishInProgress => 'Publishing';

  @override
  String get publishSuccess => 'Published to community';

  @override
  String get publishErrSignedOut => 'Sign in before publishing';

  @override
  String get publishErrAlreadyPublished => 'This work is already published';

  @override
  String get publishErrReading => 'Could not read the point cloud';

  @override
  String get publishErrUploading =>
      'Upload failed — check your connection and retry';

  @override
  String get publishErrTooLarge =>
      'This scan exceeds the upload size limit — retrying will not help. Please capture a smaller area and regenerate.';

  @override
  String get publishErrRejected =>
      'This file failed server-side validation and may be corrupted. Please regenerate the scan.';

  @override
  String get publishErrInserting =>
      'Could not save the publication, please retry';

  @override
  String get publishErrGeneric => 'Publish failed';

  @override
  String get communityCloudLoadFailed => 'Could not load the point cloud';

  @override
  String get communityRetry => 'Retry';

  @override
  String get communityFormatUnsupported =>
      'This format cannot be previewed in this version';

  @override
  String get communityPointsSuffix => 'points';

  @override
  String get meDeleteAccount => 'Delete account';

  @override
  String get meDeleteAccountDialogTitle => 'Permanently delete your account?';

  @override
  String get meDeleteAccountDialogBody =>
      'Your account, published works and all cloud data will be permanently deleted. This cannot be undone. Captures stored on this device are not affected.';

  @override
  String get meDeleteAccountConfirm => 'Delete permanently';

  @override
  String get meDeleteAccountFailed =>
      'Deletion failed. Please try again later.';

  @override
  String get publishModerationUnderReview => 'Under review';

  @override
  String get publishModerationRemoved => 'Removed';

  @override
  String get publishModerationRemovedHint =>
      'This work was removed for violating the community guidelines and is not visible to others. To appeal, use the contact details on the Settings page.';

  @override
  String get workMoreActions => 'More';

  @override
  String get reportAction => 'Report';

  @override
  String get reportSheetTitle => 'Report this work';

  @override
  String get reportSheetSubtitle =>
      'Pick a reason and we\'ll review it promptly.';

  @override
  String get reportReasonSpam => 'Spam or advertising';

  @override
  String get reportReasonHarassment => 'Harassment or bullying';

  @override
  String get reportReasonHateSpeech => 'Hate speech';

  @override
  String get reportReasonSexualContent => 'Sexual content';

  @override
  String get reportReasonViolence => 'Violence or gore';

  @override
  String get reportReasonCopyright => 'Copyright infringement';

  @override
  String get reportReasonMisinformation => 'Misinformation';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportDetailHint => 'Additional details (optional)';

  @override
  String get reportSubmit => 'Submit report';

  @override
  String get reportSubmitted => 'Report submitted. We\'ll review it promptly.';

  @override
  String get reportFailed =>
      'Couldn\'t submit the report. Please try again later.';

  @override
  String get blockAction => 'Block this user';

  @override
  String get blockDialogTitle => 'Block this user?';

  @override
  String get blockDialogBody =>
      'You won\'t see their works anymore, and any follow relationship between you will be removed.';

  @override
  String get blockConfirm => 'Block';

  @override
  String get blockDone => 'Blocked. Their works will no longer appear.';

  @override
  String get blockFailed => 'Action failed. Please try again later.';

  @override
  String get workDeleteAction => 'Remove from community';

  @override
  String get workDeleteDialogTitle => 'Remove this work from the community?';

  @override
  String get workDeleteDialogBody =>
      'The work will be removed from the community and its cloud files deleted. This cannot be undone. Your original capture on this device is unaffected and can be published again later.';

  @override
  String get workDeleteConfirm => 'Remove';

  @override
  String get workDeleteDone => 'Removed from the community';

  @override
  String get workDeleteFailed => 'Removal failed. Please try again later.';

  @override
  String get socialActionFailed => 'Action failed. Please try again later.';

  @override
  String get socialFollowingTitle => 'Following';

  @override
  String get socialFollowingLoadFailed => 'Couldn\'t load your following list';

  @override
  String get socialFollowingEmpty => 'You aren\'t following anyone yet';

  @override
  String get socialFollow => 'Follow';

  @override
  String get socialFollowing => 'Following';

  @override
  String get meDownloadIncomplete => 'Download incomplete. Try again later.';

  @override
  String get meWorkOpenFailed => 'Could not open this work. Try again later.';

  @override
  String get meProfileTitle => 'My profile';

  @override
  String get socialLikesReceived => 'Likes';

  @override
  String get socialWorks => 'Works';

  @override
  String get socialFollowers => 'Followers';

  @override
  String get profileLoadFailed => 'Couldn\'t load this profile';

  @override
  String get profileBack => 'Back';

  @override
  String get profileMore => 'More';

  @override
  String get profileReportUser => 'Report this user';

  @override
  String get profileBlockUser => 'Block this user';

  @override
  String get profileBlockTitle => 'Block this user?';

  @override
  String get profileBlockBody =>
      'While signed in to PocketWorld with this account, you won\'t see this person in Community, search, following lists, or profiles. Any follow relationship between you will be removed and neither account can follow the other. They won\'t be notified. Public links, signed-out visitors, or other accounts may still see their public content.';

  @override
  String get profileBlockConfirm => 'Block';

  @override
  String get profileBlockFailed =>
      'Couldn\'t block this user. Please try again later.';

  @override
  String get reportUserTitle => 'Report this user';

  @override
  String get reportTierTitle => 'Choose report type';

  @override
  String get reportReasonTitle => 'Choose a reason';

  @override
  String get reportStandardTitle => 'Standard report';

  @override
  String get reportStandardSubtitle =>
      'Harassment, fraud, harmful content, or another community issue';

  @override
  String get reportRightsTitle => 'Rights complaint';

  @override
  String get reportRightsEntry => 'Infringes rights';

  @override
  String get reportRightsSubtitle =>
      'Impersonation, privacy, portrait, or intellectual-property concerns';

  @override
  String get reportStandardDetailHint =>
      'Describe whether the issue appears on the front, back, top, or another view';

  @override
  String get reportRightsDetailHint =>
      'Describe ownership, where the infringement appears, and the requested action';

  @override
  String get reportEvidenceType => 'Evidence type';

  @override
  String get reportEvidenceContext => 'Issue screenshot';

  @override
  String get reportEvidenceIdentity => 'Identity evidence';

  @override
  String get reportEvidenceOwnership => 'Ownership evidence';

  @override
  String get reportEvidenceAuthorization => 'Authorization evidence';

  @override
  String get reportEvidenceOther => 'Other evidence';

  @override
  String get reportEvidenceOptional => 'Supporting screenshots (optional)';

  @override
  String get reportEvidenceLimitHint =>
      'Up to 3 JPG or PNG images. Location and other metadata are removed before upload.';

  @override
  String get reportHistoryTitle => 'My reports';

  @override
  String get reportHistoryEmpty => 'You haven\'t submitted any reports';

  @override
  String get reportHistoryLoadFailed => 'Couldn\'t load report history';

  @override
  String reportHistorySource(String title) {
    return 'Related work: $title';
  }

  @override
  String get reportStatusPending => 'Pending';

  @override
  String get reportStatusInReview => 'In review';

  @override
  String get reportStatusNeedsInfo => 'More information needed';

  @override
  String get reportStatusActioned => 'Action taken';

  @override
  String get reportStatusDismissed => 'No violation found';

  @override
  String get reportAdditionalInfoTitle => 'Additional information';

  @override
  String get reportImageProcessFailed =>
      'Couldn\'t process that image. Choose a JPG or PNG.';

  @override
  String get reportUserSubmitted => 'Report submitted';

  @override
  String get reportSubmittedPartial =>
      'Report submitted, but some images weren\'t uploaded';

  @override
  String get reportDetailUserHint => 'Describe what happened (optional)';

  @override
  String reportSourceWork(String workId) {
    return 'Related work: $workId';
  }

  @override
  String get reportAddEvidence => 'Add screenshots or photos (up to 3)';

  @override
  String get reportSensitiveEvidenceWarning =>
      'Don\'t re-upload or redistribute sensitive material. The platform will preserve linked in-app content for review.';

  @override
  String get reportSubmitting => 'Submitting…';

  @override
  String get reportSubmitUser => 'Submit report';

  @override
  String get reportReasonImpersonation =>
      'Impersonation or false account information';

  @override
  String get reportReasonHarassmentThreat => 'Harassment, bullying, or threats';

  @override
  String get reportReasonSpamFraud =>
      'Fraud, spam, or suspicious account activity';

  @override
  String get reportReasonMinorSafety => 'Minor safety';

  @override
  String get reportReasonSexualLowQuality => 'Sexual or explicit content';

  @override
  String get reportReasonViolenceIllegal =>
      'Violence, self-harm, hate, extremism, or other illegal harmful content';

  @override
  String get reportReasonMisleading => 'False or misleading information';

  @override
  String get reportReasonPrivacyIp =>
      'Privacy, doxxing, portrait, or intellectual property';

  @override
  String get reportReasonOtherUncertain => 'Other / not sure';

  @override
  String get blockedUsersTitle => 'Blocked users';

  @override
  String get blockedUsersLoadFailed => 'Couldn\'t load blocked users';

  @override
  String get blockedUsersEmpty => 'You haven\'t blocked anyone';

  @override
  String get unblockTitle => 'Unblock this user?';

  @override
  String get unblockBody =>
      'You\'ll be able to see their public content again. Previous follow relationships won\'t be restored automatically.';

  @override
  String get unblockAction => 'Unblock';

  @override
  String get unblockFailed =>
      'Couldn\'t unblock this user. Please try again later.';

  @override
  String get meBlockedUsers => 'Blocked users';

  @override
  String get meSocialLoadFailed => 'Couldn\'t load social profile';

  @override
  String etaCountdown(String time) {
    return 'Estimated time remaining · $time';
  }

  @override
  String etaSparseCountdown(String time) {
    return 'Sparse stage estimated time remaining · $time';
  }

  @override
  String get etaSparseCalculating => 'Estimating sparse stage…';

  @override
  String etaDurationMinutes(int n) {
    return 'about $n min';
  }

  @override
  String get etaDurationUnderMinute => 'Within 1 min';

  @override
  String get phoneSignUpWithPhone => 'Sign up with phone';

  @override
  String get phoneCountrySearchHint => 'Search country, region or calling code';

  @override
  String get phoneCountryNoMatches => 'No matching regions';

  @override
  String get phoneMobileFormatUnavailable =>
      'Mobile number format is unavailable for this region';

  @override
  String phoneMobileExample(String number) {
    return 'Mobile number example: $number';
  }

  @override
  String get phoneOverseasSignupUnavailable =>
      'SMS verification is not yet available for overseas numbers. You can sign up with email.';

  @override
  String get phoneLoginHelp =>
      'Enter 11 digits for mainland China; include the calling code for overseas numbers. Overseas SMS is not available yet. You can sign up or sign in with email.';

  @override
  String phoneCountryCallingCodeLabel(String country, String callingCode) {
    return '$country +$callingCode';
  }

  @override
  String get phoneCountryAC => 'Ascension Island';

  @override
  String get phoneCountryAD => 'Andorra';

  @override
  String get phoneCountryAE => 'United Arab Emirates';

  @override
  String get phoneCountryAF => 'Afghanistan';

  @override
  String get phoneCountryAG => 'Antigua & Barbuda';

  @override
  String get phoneCountryAI => 'Anguilla';

  @override
  String get phoneCountryAL => 'Albania';

  @override
  String get phoneCountryAM => 'Armenia';

  @override
  String get phoneCountryAO => 'Angola';

  @override
  String get phoneCountryAR => 'Argentina';

  @override
  String get phoneCountryAS => 'American Samoa';

  @override
  String get phoneCountryAT => 'Austria';

  @override
  String get phoneCountryAU => 'Australia';

  @override
  String get phoneCountryAW => 'Aruba';

  @override
  String get phoneCountryAX => 'Åland Islands';

  @override
  String get phoneCountryAZ => 'Azerbaijan';

  @override
  String get phoneCountryBA => 'Bosnia & Herzegovina';

  @override
  String get phoneCountryBB => 'Barbados';

  @override
  String get phoneCountryBD => 'Bangladesh';

  @override
  String get phoneCountryBE => 'Belgium';

  @override
  String get phoneCountryBF => 'Burkina Faso';

  @override
  String get phoneCountryBG => 'Bulgaria';

  @override
  String get phoneCountryBH => 'Bahrain';

  @override
  String get phoneCountryBI => 'Burundi';

  @override
  String get phoneCountryBJ => 'Benin';

  @override
  String get phoneCountryBL => 'St. Barthélemy';

  @override
  String get phoneCountryBM => 'Bermuda';

  @override
  String get phoneCountryBN => 'Brunei';

  @override
  String get phoneCountryBO => 'Bolivia';

  @override
  String get phoneCountryBQ => 'Caribbean Netherlands';

  @override
  String get phoneCountryBR => 'Brazil';

  @override
  String get phoneCountryBS => 'Bahamas';

  @override
  String get phoneCountryBT => 'Bhutan';

  @override
  String get phoneCountryBW => 'Botswana';

  @override
  String get phoneCountryBY => 'Belarus';

  @override
  String get phoneCountryBZ => 'Belize';

  @override
  String get phoneCountryCA => 'Canada';

  @override
  String get phoneCountryCC => 'Cocos (Keeling) Islands';

  @override
  String get phoneCountryCD => 'Congo - Kinshasa';

  @override
  String get phoneCountryCF => 'Central African Republic';

  @override
  String get phoneCountryCG => 'Congo - Brazzaville';

  @override
  String get phoneCountryCH => 'Switzerland';

  @override
  String get phoneCountryCI => 'Côte d’Ivoire';

  @override
  String get phoneCountryCK => 'Cook Islands';

  @override
  String get phoneCountryCL => 'Chile';

  @override
  String get phoneCountryCM => 'Cameroon';

  @override
  String get phoneCountryCN => 'China mainland';

  @override
  String get phoneCountryCO => 'Colombia';

  @override
  String get phoneCountryCR => 'Costa Rica';

  @override
  String get phoneCountryCU => 'Cuba';

  @override
  String get phoneCountryCV => 'Cape Verde';

  @override
  String get phoneCountryCW => 'Curaçao';

  @override
  String get phoneCountryCX => 'Christmas Island';

  @override
  String get phoneCountryCY => 'Cyprus';

  @override
  String get phoneCountryCZ => 'Czechia';

  @override
  String get phoneCountryDE => 'Germany';

  @override
  String get phoneCountryDJ => 'Djibouti';

  @override
  String get phoneCountryDK => 'Denmark';

  @override
  String get phoneCountryDM => 'Dominica';

  @override
  String get phoneCountryDO => 'Dominican Republic';

  @override
  String get phoneCountryDZ => 'Algeria';

  @override
  String get phoneCountryEC => 'Ecuador';

  @override
  String get phoneCountryEE => 'Estonia';

  @override
  String get phoneCountryEG => 'Egypt';

  @override
  String get phoneCountryEH => 'Western Sahara';

  @override
  String get phoneCountryER => 'Eritrea';

  @override
  String get phoneCountryES => 'Spain';

  @override
  String get phoneCountryET => 'Ethiopia';

  @override
  String get phoneCountryFI => 'Finland';

  @override
  String get phoneCountryFJ => 'Fiji';

  @override
  String get phoneCountryFK => 'Falkland Islands';

  @override
  String get phoneCountryFM => 'Micronesia';

  @override
  String get phoneCountryFO => 'Faroe Islands';

  @override
  String get phoneCountryFR => 'France';

  @override
  String get phoneCountryGA => 'Gabon';

  @override
  String get phoneCountryGB => 'United Kingdom';

  @override
  String get phoneCountryGD => 'Grenada';

  @override
  String get phoneCountryGE => 'Georgia';

  @override
  String get phoneCountryGF => 'French Guiana';

  @override
  String get phoneCountryGG => 'Guernsey';

  @override
  String get phoneCountryGH => 'Ghana';

  @override
  String get phoneCountryGI => 'Gibraltar';

  @override
  String get phoneCountryGL => 'Greenland';

  @override
  String get phoneCountryGM => 'Gambia';

  @override
  String get phoneCountryGN => 'Guinea';

  @override
  String get phoneCountryGP => 'Guadeloupe';

  @override
  String get phoneCountryGQ => 'Equatorial Guinea';

  @override
  String get phoneCountryGR => 'Greece';

  @override
  String get phoneCountryGT => 'Guatemala';

  @override
  String get phoneCountryGU => 'Guam';

  @override
  String get phoneCountryGW => 'Guinea-Bissau';

  @override
  String get phoneCountryGY => 'Guyana';

  @override
  String get phoneCountryHK => 'Hong Kong';

  @override
  String get phoneCountryHN => 'Honduras';

  @override
  String get phoneCountryHR => 'Croatia';

  @override
  String get phoneCountryHT => 'Haiti';

  @override
  String get phoneCountryHU => 'Hungary';

  @override
  String get phoneCountryID => 'Indonesia';

  @override
  String get phoneCountryIE => 'Ireland';

  @override
  String get phoneCountryIL => 'Israel';

  @override
  String get phoneCountryIM => 'Isle of Man';

  @override
  String get phoneCountryIN => 'India';

  @override
  String get phoneCountryIO => 'Chagos Archipelago';

  @override
  String get phoneCountryIQ => 'Iraq';

  @override
  String get phoneCountryIR => 'Iran';

  @override
  String get phoneCountryIS => 'Iceland';

  @override
  String get phoneCountryIT => 'Italy';

  @override
  String get phoneCountryJE => 'Jersey';

  @override
  String get phoneCountryJM => 'Jamaica';

  @override
  String get phoneCountryJO => 'Jordan';

  @override
  String get phoneCountryJP => 'Japan';

  @override
  String get phoneCountryKE => 'Kenya';

  @override
  String get phoneCountryKG => 'Kyrgyzstan';

  @override
  String get phoneCountryKH => 'Cambodia';

  @override
  String get phoneCountryKI => 'Kiribati';

  @override
  String get phoneCountryKM => 'Comoros';

  @override
  String get phoneCountryKN => 'St. Kitts & Nevis';

  @override
  String get phoneCountryKP => 'North Korea';

  @override
  String get phoneCountryKR => 'South Korea';

  @override
  String get phoneCountryKW => 'Kuwait';

  @override
  String get phoneCountryKY => 'Cayman Islands';

  @override
  String get phoneCountryKZ => 'Kazakhstan';

  @override
  String get phoneCountryLA => 'Laos';

  @override
  String get phoneCountryLB => 'Lebanon';

  @override
  String get phoneCountryLC => 'St. Lucia';

  @override
  String get phoneCountryLI => 'Liechtenstein';

  @override
  String get phoneCountryLK => 'Sri Lanka';

  @override
  String get phoneCountryLR => 'Liberia';

  @override
  String get phoneCountryLS => 'Lesotho';

  @override
  String get phoneCountryLT => 'Lithuania';

  @override
  String get phoneCountryLU => 'Luxembourg';

  @override
  String get phoneCountryLV => 'Latvia';

  @override
  String get phoneCountryLY => 'Libya';

  @override
  String get phoneCountryMA => 'Morocco';

  @override
  String get phoneCountryMC => 'Monaco';

  @override
  String get phoneCountryMD => 'Moldova';

  @override
  String get phoneCountryME => 'Montenegro';

  @override
  String get phoneCountryMF => 'St. Martin';

  @override
  String get phoneCountryMG => 'Madagascar';

  @override
  String get phoneCountryMH => 'Marshall Islands';

  @override
  String get phoneCountryMK => 'North Macedonia';

  @override
  String get phoneCountryML => 'Mali';

  @override
  String get phoneCountryMM => 'Myanmar (Burma)';

  @override
  String get phoneCountryMN => 'Mongolia';

  @override
  String get phoneCountryMO => 'Macao';

  @override
  String get phoneCountryMP => 'Northern Mariana Islands';

  @override
  String get phoneCountryMQ => 'Martinique';

  @override
  String get phoneCountryMR => 'Mauritania';

  @override
  String get phoneCountryMS => 'Montserrat';

  @override
  String get phoneCountryMT => 'Malta';

  @override
  String get phoneCountryMU => 'Mauritius';

  @override
  String get phoneCountryMV => 'Maldives';

  @override
  String get phoneCountryMW => 'Malawi';

  @override
  String get phoneCountryMX => 'Mexico';

  @override
  String get phoneCountryMY => 'Malaysia';

  @override
  String get phoneCountryMZ => 'Mozambique';

  @override
  String get phoneCountryNA => 'Namibia';

  @override
  String get phoneCountryNC => 'New Caledonia';

  @override
  String get phoneCountryNE => 'Niger';

  @override
  String get phoneCountryNF => 'Norfolk Island';

  @override
  String get phoneCountryNG => 'Nigeria';

  @override
  String get phoneCountryNI => 'Nicaragua';

  @override
  String get phoneCountryNL => 'Netherlands';

  @override
  String get phoneCountryNO => 'Norway';

  @override
  String get phoneCountryNP => 'Nepal';

  @override
  String get phoneCountryNR => 'Nauru';

  @override
  String get phoneCountryNU => 'Niue';

  @override
  String get phoneCountryNZ => 'New Zealand';

  @override
  String get phoneCountryOM => 'Oman';

  @override
  String get phoneCountryPA => 'Panama';

  @override
  String get phoneCountryPE => 'Peru';

  @override
  String get phoneCountryPF => 'French Polynesia';

  @override
  String get phoneCountryPG => 'Papua New Guinea';

  @override
  String get phoneCountryPH => 'Philippines';

  @override
  String get phoneCountryPK => 'Pakistan';

  @override
  String get phoneCountryPL => 'Poland';

  @override
  String get phoneCountryPM => 'St. Pierre & Miquelon';

  @override
  String get phoneCountryPR => 'Puerto Rico';

  @override
  String get phoneCountryPS => 'Palestinian Territories';

  @override
  String get phoneCountryPT => 'Portugal';

  @override
  String get phoneCountryPW => 'Palau';

  @override
  String get phoneCountryPY => 'Paraguay';

  @override
  String get phoneCountryQA => 'Qatar';

  @override
  String get phoneCountryRE => 'Réunion';

  @override
  String get phoneCountryRO => 'Romania';

  @override
  String get phoneCountryRS => 'Serbia';

  @override
  String get phoneCountryRU => 'Russia';

  @override
  String get phoneCountryRW => 'Rwanda';

  @override
  String get phoneCountrySA => 'Saudi Arabia';

  @override
  String get phoneCountrySB => 'Solomon Islands';

  @override
  String get phoneCountrySC => 'Seychelles';

  @override
  String get phoneCountrySD => 'Sudan';

  @override
  String get phoneCountrySE => 'Sweden';

  @override
  String get phoneCountrySG => 'Singapore';

  @override
  String get phoneCountrySH => 'St. Helena';

  @override
  String get phoneCountrySI => 'Slovenia';

  @override
  String get phoneCountrySJ => 'Svalbard & Jan Mayen';

  @override
  String get phoneCountrySK => 'Slovakia';

  @override
  String get phoneCountrySL => 'Sierra Leone';

  @override
  String get phoneCountrySM => 'San Marino';

  @override
  String get phoneCountrySN => 'Senegal';

  @override
  String get phoneCountrySO => 'Somalia';

  @override
  String get phoneCountrySR => 'Suriname';

  @override
  String get phoneCountrySS => 'South Sudan';

  @override
  String get phoneCountryST => 'São Tomé & Príncipe';

  @override
  String get phoneCountrySV => 'El Salvador';

  @override
  String get phoneCountrySX => 'Sint Maarten';

  @override
  String get phoneCountrySY => 'Syria';

  @override
  String get phoneCountrySZ => 'Eswatini';

  @override
  String get phoneCountryTA => 'Tristan da Cunha';

  @override
  String get phoneCountryTC => 'Turks & Caicos Islands';

  @override
  String get phoneCountryTD => 'Chad';

  @override
  String get phoneCountryTG => 'Togo';

  @override
  String get phoneCountryTH => 'Thailand';

  @override
  String get phoneCountryTJ => 'Tajikistan';

  @override
  String get phoneCountryTK => 'Tokelau';

  @override
  String get phoneCountryTL => 'Timor-Leste';

  @override
  String get phoneCountryTM => 'Turkmenistan';

  @override
  String get phoneCountryTN => 'Tunisia';

  @override
  String get phoneCountryTO => 'Tonga';

  @override
  String get phoneCountryTR => 'Türkiye';

  @override
  String get phoneCountryTT => 'Trinidad & Tobago';

  @override
  String get phoneCountryTV => 'Tuvalu';

  @override
  String get phoneCountryTW => 'Taiwan';

  @override
  String get phoneCountryTZ => 'Tanzania';

  @override
  String get phoneCountryUA => 'Ukraine';

  @override
  String get phoneCountryUG => 'Uganda';

  @override
  String get phoneCountryUS => 'United States';

  @override
  String get phoneCountryUY => 'Uruguay';

  @override
  String get phoneCountryUZ => 'Uzbekistan';

  @override
  String get phoneCountryVA => 'Vatican City';

  @override
  String get phoneCountryVC => 'St. Vincent & Grenadines';

  @override
  String get phoneCountryVE => 'Venezuela';

  @override
  String get phoneCountryVG => 'British Virgin Islands';

  @override
  String get phoneCountryVI => 'U.S. Virgin Islands';

  @override
  String get phoneCountryVN => 'Vietnam';

  @override
  String get phoneCountryVU => 'Vanuatu';

  @override
  String get phoneCountryWF => 'Wallis & Futuna';

  @override
  String get phoneCountryWS => 'Samoa';

  @override
  String get phoneCountryXK => 'Kosovo';

  @override
  String get phoneCountryYE => 'Yemen';

  @override
  String get phoneCountryYT => 'Mayotte';

  @override
  String get phoneCountryZA => 'South Africa';

  @override
  String get phoneCountryZM => 'Zambia';

  @override
  String get phoneCountryZW => 'Zimbabwe';

  @override
  String get commentAssetChecking =>
      'Verifying the model. Please try again shortly.';

  @override
  String get commentAssetUpdated =>
      'The model has been updated. Please reopen comments.';

  @override
  String get commentLoadFailed => 'Comments are temporarily unavailable.';

  @override
  String get commentLoadRetry => 'Unable to load comments. Please try again.';

  @override
  String get commentSendFailed =>
      'Unable to send. Your draft has been saved. Please try again.';

  @override
  String get commentImageLimit => 'You can add up to 3 images.';

  @override
  String get commentImageTooLarge => 'Each image must be no larger than 2 MiB.';

  @override
  String get commentImageAddFailed =>
      'Unable to add images. Choose JPEG, PNG or WebP files, each no larger than 2 MiB.';

  @override
  String get commentLikeFailed =>
      'Unable to like this comment. Please try again.';

  @override
  String get commentDeleteFailed =>
      'Unable to delete this comment. Please try again.';

  @override
  String get commentEditDraftFirst =>
      'Send or clear your current draft before editing a comment.';

  @override
  String get commentReselectImages => 'Please select the images to send again.';

  @override
  String get commentRefresh => 'Refresh comments';

  @override
  String get commentClose => 'Close comments';

  @override
  String get commentReload => 'Reload';

  @override
  String get commentViewLatest => 'View latest';

  @override
  String get commentHot => 'Top comments';

  @override
  String get commentLatest => 'Latest';

  @override
  String get commentEmpty =>
      'No public comments yet. Start a conversation about this work.';

  @override
  String get commentHotEmpty => 'No top comments yet';

  @override
  String get commentLatestEmpty => 'No recent comments yet';

  @override
  String get commentPrivatePending =>
      'Pending publication · Only visible to you';

  @override
  String get commentPrivateRejected => 'Not approved · Only visible to you';

  @override
  String get commentPrivateError => 'Submission error · Only visible to you';

  @override
  String get commentAuthorReply => 'Author reply';

  @override
  String get commentMe => 'Me';

  @override
  String get commentReplyFallback => 'comment';

  @override
  String get commentHidden =>
      'This comment has been hidden for violating the Community Guidelines.';

  @override
  String get commentViewReasonAppeal => 'View reason and appeal';

  @override
  String get commentViewPoint => 'View location on model';

  @override
  String get commentReply => 'Reply';

  @override
  String get commentEditResend => 'Edit and resend';

  @override
  String get commentImagePreview => 'Comment image preview';

  @override
  String get commentCloseImage => 'Close image';

  @override
  String get commentImageLoadFailed => 'Image temporarily unavailable';

  @override
  String get commentCancelReply => 'Cancel reply';

  @override
  String get commentPointSelected => 'Model location selected';

  @override
  String get commentRemovePoint => 'Remove model location';

  @override
  String get commentSignIn => 'Sign in to comment';

  @override
  String get commentServiceUnavailable =>
      'Comment service temporarily unavailable';

  @override
  String get commentUnavailable => 'Commenting temporarily unavailable';

  @override
  String get commentComposerHint => 'Say something…';

  @override
  String get commentAddEmoji => 'Add emoji';

  @override
  String get commentAddImage => 'Add images';

  @override
  String get commentSelectPoint => 'Select location on model';

  @override
  String get commentSend => 'Send';

  @override
  String get commentReportTitle => 'Report this comment';

  @override
  String get commentPointUnavailable =>
      'Location selection is temporarily unavailable. Please try again later.';

  @override
  String get commentHideOnModel => 'Hide model comments';

  @override
  String get commentShowOnModel => 'Show model comments';

  @override
  String get commentAllWrite => 'All comments / Write a comment';

  @override
  String get commentPickPointHint =>
      'Tap the model surface to choose a comment location';

  @override
  String get commentAll => 'All comments';

  @override
  String get publicWorkTitle => 'Community work';

  @override
  String get publicWorkUnavailable =>
      'This work is unavailable. Check the link or try again later.';

  @override
  String commentCount(int count) {
    return 'Comments $count';
  }

  @override
  String commentRetrySection(String section) {
    return 'Retry $section';
  }

  @override
  String commentMoreSection(String section) {
    return 'Load more $section';
  }

  @override
  String commentReplyTo(String name) {
    return 'Reply to $name';
  }

  @override
  String commentImageNumber(int number) {
    return 'Comment image $number';
  }

  @override
  String commentRemoveImage(int number) {
    return 'Remove image $number';
  }

  @override
  String commentLength(int current, int max) {
    return '$current/$max · Emoji may count as multiple units';
  }

  @override
  String commentLikeCount(int count) {
    return 'Like $count';
  }

  @override
  String commentUnlikeCount(int count) {
    return 'Unlike $count';
  }

  @override
  String commentCalendarDate(int month, int day) {
    return '$month/$day';
  }

  @override
  String get commentYesterday => 'Yesterday';

  @override
  String get commentDayBeforeYesterday => '2 days ago';

  @override
  String get moderationIdentityChanged =>
      'Your account or service region has changed. Reload to continue.';

  @override
  String get moderationSignInRequired => 'Sign in to view moderation notices';

  @override
  String get moderationRequestTimeout =>
      'Request timed out. Try again; your appeal statement has been kept.';

  @override
  String get moderationConnectionFailed =>
      'Unable to connect right now. Try again.';

  @override
  String get moderationInbox => 'Inbox';

  @override
  String get moderationInboxLoadFailedLabel =>
      'Inbox. Notices could not be loaded; you can still open it.';

  @override
  String get moderationInboxUnreadLabel =>
      'Inbox. You have unread moderation notices.';

  @override
  String get moderationInboxReadLabel => 'Inbox. No unread moderation notices.';

  @override
  String get moderationInboxNotLoadedLabel =>
      'Inbox. Notices have not loaded yet.';

  @override
  String get moderationInboxTitle => 'System inbox';

  @override
  String get moderationRefreshNotices => 'Refresh notices';

  @override
  String get moderationNoNotices => 'No moderation notices';

  @override
  String get moderationCommentHidden => 'Comment hidden';

  @override
  String get moderationCommentRestored => 'Comment restored';

  @override
  String get moderationAppealRejected => 'Appeal rejected';

  @override
  String get moderationUnread => 'Unread';

  @override
  String get moderationRelatedWorkComment => 'Comment on a related work';

  @override
  String get moderationViewCase => 'View moderation details';

  @override
  String get moderationCaseTitle => 'Comment moderation details';

  @override
  String get moderationRefreshCase => 'Refresh moderation result';

  @override
  String get moderationCommentHiddenBody =>
      'This comment is currently hidden from other people.';

  @override
  String get moderationCommentRestoredBody =>
      'The server has confirmed that this comment is visible again.';

  @override
  String get moderationReason => 'Reason for moderation';

  @override
  String get moderationRelatedContent => 'Related content';

  @override
  String get moderationCommentWork => 'The work this comment belongs to';

  @override
  String get moderationHiddenPreview =>
      'This comment is currently hidden. You can view the moderation result and submit an appeal here.';

  @override
  String get moderationRequestReview => 'Request a review';

  @override
  String get moderationRequestReviewBody =>
      'Explain why this decision should be reviewed. The comment stays hidden while your appeal is being reviewed.';

  @override
  String get moderationAppealStatement => 'Appeal statement';

  @override
  String get moderationAppealStatementHint =>
      'Add context or explain what you think needs another review';

  @override
  String get moderationAppealStatementTooLong =>
      'The appeal statement must not exceed 1,000 characters';

  @override
  String get moderationSubmitting => 'Submitting…';

  @override
  String get moderationSubmitAppeal => 'Submit appeal';

  @override
  String get moderationAppealSubmitted => 'Appeal submitted';

  @override
  String get moderationAppealApproved => 'Appeal approved';

  @override
  String get moderationAppealPendingBody =>
      'Wait for the review result. The comment stays hidden during the review; you do not need to submit again.';

  @override
  String get moderationAppealResultFallback =>
      'The result is reflected in the current comment status.';

  @override
  String get communityCoverUnavailable => 'Cover unavailable';

  @override
  String get communityFeedLoadFailed =>
      'Unable to load works. Please try again.';

  @override
  String get viewerModelUnavailableDataKept =>
      'Unable to display the model right now. Your local data has been kept.';

  @override
  String moderationDecisionTime(String date) {
    return 'Decision time: $date';
  }

  @override
  String get siteTitle => 'Chuang Hou Cheng — Keep spaces close.';

  @override
  String get siteDescription =>
      'The official website of Beijing Kongye Technology Co., Ltd. Explore spatial capture and 3D content, learn about the Chuang Hou Cheng iOS app in development, and contact Kongye.';

  @override
  String get siteSkip => 'Skip to content';

  @override
  String get siteHome => 'Chuang Hou Cheng home';

  @override
  String get siteBrand => 'Chuang Hou Cheng';

  @override
  String get siteMainNav => 'Main navigation';

  @override
  String get siteDiscover => 'Discover';

  @override
  String get siteSignIn => 'Sign in ↗';

  @override
  String get siteSupport => 'Support';

  @override
  String get siteAgreements => 'Agreements';

  @override
  String get siteContact => 'Contact';

  @override
  String get siteTagline => 'Capture spaces. Share 3D creations.';

  @override
  String get siteOpenCommunity => 'Open community ↗';

  @override
  String get siteDiscoverSpaces => 'Discover spaces';

  @override
  String get siteCommunityWorks => 'Community creations';

  @override
  String get siteSupportContact => 'Support & contact';

  @override
  String get siteContactLead => 'Product questions and feedback: ';

  @override
  String get siteTerms => 'Terms of service';

  @override
  String get sitePrivacy => 'Privacy policy';

  @override
  String get siteRules => 'Community guidelines';

  @override
  String get siteAgreementVersion =>
      'Agreements V1.1 · Published November 2, 2026 · ';

  @override
  String get sitePublicationNotice => '3D publication and review';

  @override
  String get siteAbout => 'About us';

  @override
  String get siteAboutHeadline => 'Spaces take shape.\nExplore without limits.';

  @override
  String get siteCompany => 'Beijing Kongye Technology Co., Ltd';

  @override
  String get siteAboutFirst =>
      'Kongye is a technology company based in Beijing, China. Our current product focus is developing the Chuang Hou Cheng iOS app, connecting mobile devices, spatial capture, and 3D content.';

  @override
  String get siteAboutSecond =>
      'We want capturing and experiencing digital spaces to become part of everyday life. Starting with familiar places, we explore more natural ways to express content. This website provides official company information and contact details.';

  @override
  String get siteLocation => 'Location';

  @override
  String get siteBeijing => 'Beijing · China';

  @override
  String get siteProduct => 'Product';

  @override
  String get siteProductValue => 'Chuang Hou Cheng · iOS app development';

  @override
  String get siteOfficialWebsite => 'Official website';

  @override
  String get siteCopyright => '© 2026 Beijing Kongye Technology Co., Ltd';

  @override
  String get siteFooterNav => 'Footer navigation';

  @override
  String get siteProductSupport => 'Product support';

  @override
  String get siteBackTop => 'Back to top ↑';

  @override
  String get siteLanguageSwitch => 'Switch to Chinese';

  @override
  String get siteFeedLoading => 'Loading community creations…';

  @override
  String get siteLoadMore => 'Load more';

  @override
  String get siteFeedConnection =>
      'The community is unavailable. Try again or open the full community.';

  @override
  String get siteFeedFormat => 'The community returned an unexpected response.';

  @override
  String siteViewWork(Object title) {
    return 'View $title';
  }

  @override
  String get siteUntitled => 'Untitled creation';

  @override
  String get siteWorkImage => '3D creation';

  @override
  String get siteCoverUnavailable => 'Cover unavailable';

  @override
  String get siteNoCover => 'No cover';

  @override
  String get siteLikeSignIn => 'Sign in to like';

  @override
  String get siteConfigUnavailable => 'Community configuration is unavailable.';

  @override
  String get siteFeedHint => 'Open a creation to rotate and zoom.';

  @override
  String get siteFeedEmpty => 'There are no public creations yet.';

  @override
  String get siteFeedRetry => 'The community is unavailable. Please try again.';

  @override
  String get siteReload => 'Retry';

  @override
  String get siteSharedUnavailable => 'The shared creation is unavailable.';

  @override
  String get siteSharedNotPublic =>
      'The shared creation is unavailable and may no longer be public.';

  @override
  String get siteInvalidCursor => 'Invalid creation cursor';

  @override
  String get siteInvalidAsset => 'Invalid creation address';

  @override
  String get siteUnsupportedFormat => 'Open the community to view this format.';

  @override
  String get siteLargeWork =>
      'This creation is large or its size is unknown. Open the full community to view it.';

  @override
  String get siteInvalidWork => 'Invalid creation link';

  @override
  String get siteInvalidAuthors => 'Invalid author list';

  @override
  String get siteYesterday => 'Yesterday';

  @override
  String get siteDayBeforeYesterday => 'The day before yesterday';

  @override
  String siteMonthDay(Object day, Object month) {
    return '$month/$day';
  }

  @override
  String get siteGalleryCollapse => 'Close 3D ';

  @override
  String get siteGalleryRotate => 'Rotate in 3D ';

  @override
  String get siteMotionReducedAria =>
      'Reduced motion is enabled by your system';

  @override
  String get siteMotionPlayAria => 'Play geometric animation';

  @override
  String get siteMotionPauseAria => 'Pause geometric animation';

  @override
  String get siteMotionReduced => 'Motion reduced';

  @override
  String get siteMotionPlay => 'Play animation';

  @override
  String get siteMotionPause => 'Pause animation';

  @override
  String get meCloudUnavailable =>
      'Cloud is unavailable. Please try again later.';

  @override
  String get meDenseStageCannotRebuild =>
      'This work has entered the dense stage.\nIt can no longer be reconstructed.';

  @override
  String get meThisCapture => 'This capture';

  @override
  String meQuotedCaptureName(String name) {
    return '“$name”';
  }

  @override
  String get meRegenerateTitle => 'Reconstruct again?';

  @override
  String get meResumeTitle => 'Resume reconstruction?';

  @override
  String meRegenerateBody(String name) {
    return 'The saved reconstruction data for $name will be used to regenerate and replace the existing point cloud. No new capture is needed.';
  }

  @override
  String meResumeBody(String name) {
    return 'The point cloud for $name has not been generated yet. Capture data is fully saved, so reconstruction can resume from where it stopped. No new capture is needed.';
  }

  @override
  String get meRegenerateAction => 'Reconstruct again';

  @override
  String get meResumeAction => 'Resume reconstruction';

  @override
  String get meStartTraining => 'Start training';

  @override
  String get meCaptureMorePhotos => 'Capture more photos';

  @override
  String get mePhotosRebuildUnsupported =>
      'This project was not captured with the official pipeline.\nIt cannot be reconstructed from photos.';

  @override
  String get mePhotosRebuildUnavailable =>
      'Reconstruction from photos is unavailable.';

  @override
  String get meMorePhotosUnsupported =>
      'This project was not captured with the official pipeline.\nAdditional capture is not supported yet.';

  @override
  String get meMorePhotosUnavailable => 'Additional capture is unavailable.';

  @override
  String get meMorePhotosWait =>
      'Another project is being reconstructed.\nWait for it to finish before capturing more photos.';

  @override
  String get meMorePhotosMissingData =>
      'Reconstruction data for this capture could not be found.\nAdditional capture is unavailable.';

  @override
  String meTrainingNeedsPhotos(int minimum, int count, int needed) {
    return 'Training requires at least $minimum photos.\nThis capture has $count; $needed more are needed.\nPlease continue capturing.';
  }

  @override
  String get meTrainingWait =>
      'Another project is being reconstructed.\nOnly one can run at a time. Please wait for it to finish.';

  @override
  String get meTrainingMissingData =>
      'The reconstruction data is damaged and the photos are no longer available.\nThis capture cannot be reconstructed.';

  @override
  String get meCloudPending => 'Pending sync';

  @override
  String get meCloudSyncing => 'Syncing';

  @override
  String get meCloudSaved => 'Saved to cloud';

  @override
  String get splashSolving => 'Solving';

  @override
  String get captureExitTitle => 'Exit capture?';

  @override
  String get captureExitSavePrompt =>
      'Save photos so you can capture more next time';

  @override
  String get captureExitSavePhotos => 'Save photos';

  @override
  String get meCloudIdConflict =>
      'Work ID conflict. Your local work has been kept.';

  @override
  String get meCloudNewerVersion =>
      'A newer version is in the cloud. Your local version has been kept.';

  @override
  String get meCloudNameConflict =>
      'A work with the same name exists. Your work has been kept. Please rename it.';

  @override
  String get meCloudRetryKept =>
      'Cloud is unavailable or storage is full. Your work has been kept and will retry automatically later.';

  @override
  String get legalPrivacyS0Title => 'Introduction';

  @override
  String get legalPrivacyS0P0 =>
      '“方寸间” (the “Product”) is operated by 【公司名称待注册后填写】 (“we” or “us”). This Policy explains how we collect, use, store and protect your personal information, and your rights and how to exercise them. Please read this Policy carefully before using the Product, especially the terms in bold.';

  @override
  String get legalPrivacyS0P1 =>
      'Five key points first; details follow in the text:';

  @override
  String get legalPrivacyS0P2 =>
      '① The original photos you capture are processed only on your phone and are never uploaded. Only the reconstructed 3D point clouds and thumbnails rendered from them are uploaded;';

  @override
  String get legalPrivacyS0P3 =>
      '② The Product embeds no third-party analytics, advertising, push notification or crash collection components and contains no form of user tracking;';

  @override
  String get legalPrivacyS0P4 =>
      '③ We do not share your personal information with any third party;';

  @override
  String get legalPrivacyS0P5 =>
      '④ Deleting your account deletes your personal information (except information retained as required by law; see Chapter IV);';

  @override
  String get legalPrivacyS0P6 =>
      '⑤ Under national rules on internet user account information, we publicly display your account\'s IP region (at provincial level). This display cannot be disabled.';

  @override
  String get legalPrivacyS0P7 =>
      'If you disagree with this Policy, please do not register for or use the Product. Your disagreement does not exempt processing required by laws and regulations (such as displaying the IP region).';

  @override
  String get legalPrivacyS1Title =>
      'I. What personal information we collect and why';

  @override
  String get legalPrivacyS1P0 =>
      'We collect personal information only in the following five scenarios. Each item states its purpose, method and retention period. Except for your phone number, all items are optional; refusing to provide them does not affect your use of other functions.';

  @override
  String get legalPrivacyS1P1 => '(1) Account registration and sign-in';

  @override
  String get legalPrivacyS1P2 =>
      '· Mobile phone number (required): Used to register an account, sign in and verify your real identity under the Cybersecurity Law and the Provisions on the Administration of Internet User Account Information. The necessary personal information for online community services is the registered user\'s mobile phone number. This is the only item in this Policy without which you cannot register and use the service. Verification texts are sent by an SMS provider (see Chapter III). Retained until account deletion.';

  @override
  String get legalPrivacyS1P3 =>
      '· Email address [optional]: Once linked, used for account recovery and important notices. Refusal does not affect any function. Retained until unlinked or your account is deleted.';

  @override
  String get legalPrivacyS1P4 =>
      '· Sign-in password [sensitive information]: Stored only as a one-way hash; we cannot view your plain-text password. Transmission is encrypted throughout. Passwords are sensitive personal information; please do not reuse a password from another platform.';

  @override
  String get legalPrivacyS1P5 =>
      '· Nickname, account ID and biography [optional]: Used to show your identity in the community. Nicknames may be duplicated; account IDs are unique across the platform. All three are displayed publicly. Retained until you change them or delete your account.';

  @override
  String get legalPrivacyS1P6 =>
      '(2) Capture and 3D reconstruction — completed entirely on your phone';

  @override
  String get legalPrivacyS1P7 =>
      '· Camera images and motion sensor data: Used only for on-device capture guidance and 3D reconstruction; not uploaded or stored on servers.';

  @override
  String get legalPrivacyS1P8 =>
      '· Original photos: Saved in the Product\'s documents directory on your device. You can view, export or delete them using the system Files app. We do not collect original photos; they do not leave your device in any form.';

  @override
  String get legalPrivacyS1P9 =>
      '· Reconstructed 3D point clouds: Stored only on your device until you choose to publish them.';

  @override
  String get legalPrivacyS1P10 =>
      '(3) Publishing works and community interactions';

  @override
  String get legalPrivacyS1P11 =>
      '· Work content [optional; necessary for publishing]: When you publish a work, we collect its 3D point cloud model file, thumbnail (rendered from the point cloud, not a camera photo), title and description. After approval, the work is displayed publicly to all users, including visitors who are not signed in.';

  @override
  String get legalPrivacyS1P12 =>
      '· When publishing, you acknowledge that once the work is published and approved, its content, your nickname, account ID and IP region at publication will be visible to everyone.';

  @override
  String get legalPrivacyS1P13 =>
      '· IP region: Under Article 12 of the Provisions on the Administration of Internet User Account Information, work information displays your IP region at publication, and your account information page displays your IP region from your most recent use. Within China, this is shown at province level (including autonomous regions and municipalities); outside China, at country or region level. No more precise location is displayed. The system determines the region automatically from the IP address; neither you nor we can change it manually. You may appeal through the contact methods in Chapter IX.';

  @override
  String get legalPrivacyS1P14 =>
      '· Research and technical improvement: The work content you upload will be used for our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction). When providing research data externally, we use only anonymized data that cannot identify you and cannot be restored, or obtain your separate consent. See Chapter VI of the 方寸间 User Agreement.';

  @override
  String get legalPrivacyS1P15 =>
      '· Like, report and block records: Used to provide the corresponding functions and govern the community. Likes on public works are visible to other users; reports are visible only to you and platform administrators. Retained until you undo the action, the relevant work is deleted or your account is deleted.';

  @override
  String get legalPrivacyS1P16 =>
      '· View records: Used only to show view counts to work authors, deduplicated hourly; not used for any personalized recommendations or advertising. Retained until the relevant work is deleted; anonymized and no longer linked to you after account deletion.';

  @override
  String get legalPrivacyS1P17 => '(4) Security';

  @override
  String get legalPrivacyS1P18 =>
      '· IP address and device identification string (User-Agent): Recorded in security audit logs during key actions such as registration, sign-in, publishing, deletion and reporting, for security, abuse prevention and lawful regulatory cooperation. IP addresses also generate the provincial IP region display described above. Both purposes are disclosed here; we do not use them for other purposes. General audit records are retained for 180 days; records concerning account deletion and content enforcement for 730 days; the system then deletes them automatically.';

  @override
  String get legalPrivacyS1P19 =>
      '· API frequency records: Brief records of API call frequency are kept to prevent abuse, for no more than 1 day.';

  @override
  String get legalPrivacyS1P20 => '(5) Product improvement and analytics';

  @override
  String get legalPrivacyS1P21 =>
      '· Usage events: To understand how the Product is used and detect and fix failures, we collect feature usage events (such as the start, success or failure of publishing and the failure stage), session identifiers, error and crash summaries (error messages and truncated code stacks, excluding your work content or profile), system version and app version. Analytics is built by us; data goes only to our own servers, without any third-party analytics component. Retained for 180 days and then automatically deleted; detached from your identity (anonymized) after account deletion.';

  @override
  String get legalPrivacyS1P22 =>
      '· Analytics is nonessential information: You can disable it at any time in “Settings → Help improve the product”. We then stop collection and clear analytics data on your device that has not yet been reported. No function is affected.';

  @override
  String get legalPrivacyS1P23 =>
      '(6) Under laws and regulations, your consent is not required for processing necessary to perform statutory duties or obligations; respond to public health emergencies or protect natural persons\' life, health or property in emergencies; process, within a reasonable scope, personal information you have made public or that has otherwise been lawfully made public; or other circumstances provided by laws and administrative regulations.';

  @override
  String get legalPrivacyS2Title => 'II. Device permissions and local storage';

  @override
  String get legalPrivacyS2P0 =>
      'The Product requests only the following two system permissions, each when you first use the relevant function, never at launch:';

  @override
  String get legalPrivacyS2P1 =>
      '· Camera: To take photos for on-device 3D reconstruction. Refusing permission prevents capture but does not affect other functions such as community browsing.';

  @override
  String get legalPrivacyS2P2 =>
      '· Motion & Fitness (motion sensors): For real-time capture guidance and camera pose estimation. Data is processed only on your device. Refusing permission affects capture guidance accuracy.';

  @override
  String get legalPrivacyS2P3 =>
      'We do not request location, contacts, microphone, photo library or any other permissions. You may revoke permissions in system settings at any time; this does not affect the validity of processing already performed under those permissions.';

  @override
  String get legalPrivacyS2P4 =>
      'Local storage: The Product has no embedded web browser and does not use cookies. The following is stored only on your device and will not be read by us for purposes not stated in this Policy: sign-in credentials (in the system keychain), language and interface preferences, temporary file caches from viewing others\' works (to speed loading, removable by the system), and your original photos and reconstruction outputs (see Chapter I(2)).';

  @override
  String get legalPrivacyS3Title =>
      'III. Entrusted processing, sharing, transfer and public disclosure';

  @override
  String get legalPrivacyS3P0 =>
      'We do not obtain your personal information indirectly from any third party. This chapter explains where information flows from us.';

  @override
  String get legalPrivacyS3P1 =>
      '(1) Entrusted processing. The following providers process relevant information only on our instructions. We sign data processing agreements specifying the purposes, duration, methods, information types and safeguards, and supervise their processing activities:';

  @override
  String get legalPrivacyS3P2 =>
      '· Cloud infrastructure provider (database and file storage): 阿里云计算有限公司, storing the server-side information listed in Chapter I;';

  @override
  String get legalPrivacyS3P3 =>
      '· SMS provider: 阿里云 (sends sign-in verification codes and accesses your mobile phone number);';

  @override
  String get legalPrivacyS3P4 =>
      '· Email provider: 【邮件服务商待填写 —— 上线前确认为境内服务商】 (sends email verification codes and accesses your email address).';

  @override
  String get legalPrivacyS3P5 =>
      '(2) Sharing: We do not share your personal information with any third party. Information anonymized so that it cannot identify a specific person and cannot be restored is not personal information under law. Only such anonymized data is used in our external research collaborations (see Chapter I(3)).';

  @override
  String get legalPrivacyS3P6 =>
      '(3) Third-party SDK list: The Product embeds no third-party analytics, advertising, push notification or crash collection SDKs. If any are added in future, we will update this Policy and list before integration and obtain your consent again.';

  @override
  String get legalPrivacyS3P7 =>
      '(4) Transfer: In a merger, division, dissolution or acquisition, we will inform you of the recipient\'s name and contact details and require it to continue fulfilling this Policy. If the recipient changes the purposes or methods of processing, your consent will be obtained again.';

  @override
  String get legalPrivacyS3P8 =>
      '(5) Public disclosure: Other than the legally required IP region display disclosed in Chapter I and content you actively publish, we do not publicly disclose your personal information, except when lawfully cooperating with regulators or judicial authorities.';

  @override
  String get legalPrivacyS4Title => 'IV. Information storage and protection';

  @override
  String get legalPrivacyS4P0 =>
      '1. Storage location: Your personal information is stored within the People\'s Republic of China.';

  @override
  String get legalPrivacyS4P1 =>
      '2. Retention periods: Chapter I lists each period. In summary: account details (phone/email/nickname/ID/biography) until account deletion; works and interaction records until deletion or account deletion; view records anonymized after account deletion; analytics events 180 days; security audit logs 180 days (major actions 730 days); API frequency records no more than 1 day; temporary registration verification data 10 minutes. Information exceeding its period is automatically deleted or anonymized.';

  @override
  String get legalPrivacyS4P2 =>
      '3. Statutory retention exception: For content governance, copies of files for works lawfully removed will be separately sealed and retained for dispute resolution and regulatory cooperation, and used for no other purpose during that time. These copies may remain for the necessary period after account deletion.';

  @override
  String get legalPrivacyS4P3 =>
      '4. Safeguards: All transmissions use encrypted channels (TLS); passwords are stored as one-way hashes; database row-level access controls prevent users from reading others\' nonpublic data; sign-in credentials are stored in the system keychain; key actions have audit records; uploads undergo two-stage validation, and files failing validation do not enter public storage.';

  @override
  String get legalPrivacyS4P4 =>
      '5. Security incidents: If personal information is leaked, altered or lost, we will immediately take remedial measures, inform you of the incident, possible effects and remedies as required by law, and report to regulators.';

  @override
  String get legalPrivacyS4P5 =>
      '6. Closure: If the Product ceases operation, we will stop collecting personal information, notify you by announcement, and delete or anonymize stored personal information.';

  @override
  String get legalPrivacyS5Title => 'V. Your rights';

  @override
  String get legalPrivacyS5P0 =>
      'You have rights to be informed and make decisions about your personal information, and to restrict or refuse processing, as follows:';

  @override
  String get legalPrivacyS5P1 =>
      '1. Access and copies: You can view your account details and works directly on “Me”. To access or copy other information about you (such as audit log records), use the contact methods in Chapter IX.';

  @override
  String get legalPrivacyS5P2 =>
      '2. Correction and supplementation: You can edit your nickname, account ID and biography in “Settings”. IP regions are determined automatically and cannot be edited manually; you may appeal if you disagree.';

  @override
  String get legalPrivacyS5P3 =>
      '3. Deletion: You can delete your works (including those under review) on the work page at any time; their server files are also deleted. Submit other deletion requests through our contact methods. We will proactively delete information in statutory circumstances such as fulfillment of processing purposes, service cessation, withdrawal of consent or unlawful or contract-breaching processing by us. If a legally required retention period has not expired or deletion is technically difficult, we will stop all processing except storage and necessary security safeguards.';

  @override
  String get legalPrivacyS5P4 =>
      '4. Withdrawal of consent: You can withdraw consent by revoking system permissions, deleting relevant information or deleting your account, or by contacting us. Withdrawal does not affect the validity of earlier processing based on consent. We will not deny functions unrelated to the matter for which consent is withdrawn.';

  @override
  String get legalPrivacyS5P5 =>
      '5. Explanations: You may ask us to explain this Policy and the rules for processing personal information.';

  @override
  String get legalPrivacyS5P6 =>
      '6. Rights of a deceased user\'s close relatives: For their own lawful and legitimate interests, close relatives may, with proof of death and kinship, use the contact methods in Chapter IX to exercise access, copying, correction, deletion and other rights concerning the deceased user\'s personal information, unless the deceased arranged otherwise during their lifetime.';

  @override
  String get legalPrivacyS5P7 =>
      '7. Response time: After verifying your identity, we respond within 15 working days. We will explain any refusal. You may complain or report to cyberspace authorities (www.12377.cn) or telecommunications authorities (www.12321.cn), or bring proceedings in a people\'s court under law.';

  @override
  String get legalPrivacyS6Title => 'VI. Account deletion';

  @override
  String get legalPrivacyS6P0 =>
      'You can delete your account at any time in “Settings → Account”, without manual review or preconditions.';

  @override
  String get legalPrivacyS6P1 =>
      'After deletion: Your account details, works, like and report records are deleted; view records are anonymized. Security audit logs are retained for the periods in Chapter IV and then automatically deleted; sealed copies of lawfully removed works are handled under Chapter IV, paragraph 3. We do not retain your phone number or email for any other purpose.';

  @override
  String get legalPrivacyS6P2 =>
      'Account deletion is irreversible. Back up any works you want to keep before proceeding. Deletion is completed within 15 working days.';

  @override
  String get legalPrivacyS7Title => 'VII. Protection of minors';

  @override
  String get legalPrivacyS7P0 =>
      'The Product is only for users aged 14 or older. Minors under 14 may not register for or use it.';

  @override
  String get legalPrivacyS7P1 =>
      'We do not knowingly collect personal information from minors under 14. If discovered, we will immediately delete the information and the relevant account.';

  @override
  String get legalPrivacyS7P2 =>
      'Users aged 14 to under 18 must read and agree to this Policy under a guardian\'s guidance. Guardians who object to a minor\'s use or discover issues with a minor\'s personal information may contact us through Chapter IX; we will give these matters priority.';

  @override
  String get legalPrivacyS7P3 =>
      'Reports involving minors receive the highest priority in content governance.';

  @override
  String get legalPrivacyS8Title => 'VIII. Policy updates';

  @override
  String get legalPrivacyS8P0 =>
      'This Policy may be revised from time to time. We will prominently notify you in the app, such as by an announcement, and update the version number and effective date at the beginning.';

  @override
  String get legalPrivacyS8P1 =>
      'If processing purposes, processing methods or types of personal information processed change, we will obtain your consent again rather than continue by default.';

  @override
  String get legalPrivacyS8P2 =>
      'We retain previous versions of this Policy. You may request them through the contact methods in Chapter IX.';

  @override
  String get legalPrivacyS9Title => 'IX. How to contact us';

  @override
  String get legalPrivacyS9P0 => 'Personal information processor: 【公司名称待注册后填写】';

  @override
  String get legalPrivacyS9P1 => 'Registered address: 【公司注册地待定后填写】';

  @override
  String get legalPrivacyS9P2 =>
      'Personal information protection officer email: 【联系邮箱待填写 —— 上线前必须替换为真实可达邮箱,与平台公约页同一个】';

  @override
  String get legalPrivacyS9P3 =>
      'We reply within 15 working days after verifying your identity. If dissatisfied, you may complain or report to cyberspace, telecommunications, public security, market regulation or other authorities, or bring proceedings in a people\'s court under law.';

  @override
  String get legalAgreementS0Title => 'I. Introduction';

  @override
  String get legalAgreementS0P0 =>
      'Welcome to “方寸间”. This Agreement is between you and 【公司名称待注册后填写】 (“we” or the “Platform”) concerning use of the 方寸间 software and related services. Please read it in full before registration, especially the bold terms on exclusions or limitations of liability, licenses of rights and dispute jurisdiction.';

  @override
  String get legalAgreementS0P1 =>
      'The 方寸间 Platform Rules (including account management rules) and 方寸间 Privacy Policy form integral parts of this Agreement and have equal effect. Accepting this Agreement constitutes acceptance of those documents as well.';

  @override
  String get legalAgreementS0P2 =>
      'By clicking confirmation, completing registration or actually using the Service, you indicate that you have read and agree to this Agreement. If you disagree, do not register for or use it.';

  @override
  String get legalAgreementS0P3 =>
      'This Agreement is written in Chinese, and the Chinese text prevails. Any interface translation is provided solely for reading convenience.';

  @override
  String get legalAgreementS1Title => 'II. Description of the Service';

  @override
  String get legalAgreementS1P0 =>
      '方寸间 is a 3D spatial content tool and community: you capture with your phone, reconstruct 3D point cloud works on the device, and may choose to publish them to the community to share with other users.';

  @override
  String get legalAgreementS1P1 =>
      'The Product\'s 3D reconstruction uses deep synthesis technology (3D reconstruction based on AI models). Under the Provisions on the Administration of Deep Synthesis in Internet Information Services, we prominently remind you: when using the Service to produce or publish information content, you must fulfill information security obligations under law. You must not use it to produce, copy, publish or distribute information prohibited by laws and regulations, or for activities endangering national security or interests, damaging the national image, harming public interests, disrupting economic or social order or infringing others\' lawful rights and interests.';

  @override
  String get legalAgreementS1P2 =>
      'Under those provisions, the Platform applies technical identifiers to published work files (an identifier of the generation method is embedded in the model file). You must not remove, alter or conceal it.';

  @override
  String get legalAgreementS1P3 =>
      'The Service\'s specific form (functions, interface and rules) may change as the Product evolves. Changes affecting your material rights and interests follow the procedure in Chapter XII.';

  @override
  String get legalAgreementS1P4 =>
      'We grant you a personal, nontransferable, nonsublicensable, nonexclusive license to download, install and use this software for noncommercial purposes.';

  @override
  String get legalAgreementS1P5 =>
      'Obtain the software through official channels, such as the App Store. Versions from unofficial channels may pose security risks; you bear the resulting consequences.';

  @override
  String get legalAgreementS1P6 =>
      'You bear the costs of devices and network data needed to use the Service.';

  @override
  String get legalAgreementS1P7 =>
      'The Service is provided to users in mainland People\'s Republic of China. We do not guarantee its availability or suitability in other jurisdictions.';

  @override
  String get legalAgreementS2Title =>
      'III. Account registration and management';

  @override
  String get legalAgreementS2P0 =>
      '1. Age: You must be at least 14 to register for and use the Service. If under 18, you must also read this Agreement with a guardian and obtain their consent.';

  @override
  String get legalAgreementS2P1 =>
      '2. Real identity verification: Registration requires real identity verification based on a mobile phone number as required by law. Without verification, you cannot register or use information publishing functions such as publishing and liking.';

  @override
  String get legalAgreementS2P2 =>
      '3. Account information: Your nickname, account ID, biography and other account information must comply with laws, regulations and the Platform Rules. You must not impersonate, imitate or maliciously associate with Party, government or military bodies, enterprises, institutions, news media or public figures, or use names likely to be mistaken for official Platform identities. Names containing words such as “中国” or “国家”, or involving national flag or emblem identifiers, are subject to strict verification under national rules; the Platform may request supporting documents or reject them.';

  @override
  String get legalAgreementS2P3 =>
      '4. Ownership and security: Accounts are for your personal use only. Without the Platform\'s written consent, you must not give, lend, rent, transfer, sell or bequeath an account, or otherwise permit others to use it. All actions through your account are treated as yours, with corresponding responsibility borne by you. Safeguard your sign-in credentials. If your account is impersonated or stolen, notify the Platform immediately through Chapter XIV; protective measures such as temporary freezing may be taken as appropriate. You bear losses caused by inadequate safekeeping, except those caused by the Platform.';

  @override
  String get legalAgreementS2P4 =>
      '5. Account deletion: You may delete your account at any time in “Settings → Account”. See the 方寸间 Privacy Policy for the process and data handling.';

  @override
  String get legalAgreementS3Title => 'IV. User conduct';

  @override
  String get legalAgreementS3P0 =>
      '1. You must not use the Service to produce, copy, publish or distribute information that: opposes the basic principles established by the Constitution; endangers national security, discloses state secrets, subverts state power or undermines national unity; harms national honor or interests; distorts, vilifies, desecrates or denies the deeds and spirit of heroes and martyrs; promotes terrorism or extremism or incites terrorist or extremist activities; incites ethnic hatred or discrimination or undermines ethnic unity; undermines national religious policy or promotes cults or feudal superstition; spreads rumors or disrupts economic or social order; spreads obscenity, pornography, gambling, violence, murder or terror, or instigates crime; insults or defames others or infringes their reputation, privacy or other lawful rights and interests; or contains other content prohibited by laws or administrative regulations.';

  @override
  String get legalAgreementS3P1 =>
      '2. You should guard against and resist producing, copying or publishing harmful information that: uses exaggerated headlines seriously inconsistent with content; sensationalizes gossip, scandals or misconduct; inappropriately comments on disasters such as natural disasters or major accidents; contains sexual innuendo or provocation likely to evoke sexual associations; depicts bloodshed, horror or cruelty causing physical or psychological discomfort; incites discrimination against groups or regions; promotes vulgar, coarse or pandering content; may encourage minors to imitate unsafe acts or acts against public morality or develop harmful habits; or otherwise adversely affects the online environment.';

  @override
  String get legalAgreementS3P2 =>
      '3. Special rules for 3D works: Before capturing and publicly publishing reconstructions of nonpublic spaces such as others\' homes or offices, obtain the rights holder\'s consent. If a specific other person is identifiable in images or point clouds, obtain that person\'s consent. Do not publish reconstructions of national security sensitive areas, military facilities or other places where surveying or photography is prohibited by laws and regulations.';

  @override
  String get legalAgreementS3P3 =>
      '4. You must not: use technical means to register accounts in bulk; reverse engineer, crack or bypass the Product\'s technical protections (except as permitted by laws and regulations); scrape, download or copy other users\' works without authorization for use outside the Service; use automation to call the Service at high frequency or collect data; interfere with or disrupt normal operation; create or distribute viruses, Trojans or other malware, or access Platform systems or others\' accounts without authorization; publish spam or malicious marketing; act in the Platform\'s name or mislead others by claiming cooperation, agency or similar relations with it.';

  @override
  String get legalAgreementS3P4 =>
      '5. 3D capture requires moving around on site. Be aware of your surroundings and your own and others\' safety. Do not capture in dangerous places such as roads or edges at heights.';

  @override
  String get legalAgreementS4Title => 'V. Content publishing and review';

  @override
  String get legalAgreementS4P0 =>
      '1. Review before publication: Works you submit must pass Platform review before appearing in the community. During review, they are invisible to other users and you may delete them at any time.';

  @override
  String get legalAgreementS4P1 =>
      '2. Publication is public: Once approved, the work\'s content, your nickname, account ID and IP region at publication are publicly visible to all users, including visitors who are not signed in. IP region display is legally required and cannot be disabled; see the 方寸间 Privacy Policy.';

  @override
  String get legalAgreementS4P2 =>
      '3. “Content” in this Agreement includes 3D point cloud models, reconstruction data, thumbnails, titles, descriptions, account details and any other information you upload or publish through the Service.';

  @override
  String get legalAgreementS4P3 =>
      '4. You independently bear all legal responsibility for your published content. You warrant that you have lawful rights or authorization for it. If third-party claims arising from your content cause losses to the Platform, you must compensate it.';

  @override
  String get legalAgreementS4P4 =>
      '5. If a third party asserts rights against your content, the Platform may lawfully remove it first and notify you. You may appeal through Chapter VIII by submitting a noninfringement statement and proof of rights.';

  @override
  String get legalAgreementS5Title => 'VI. Intellectual property';

  @override
  String get legalAgreementS5P0 =>
      '1. Intellectual property in the Platform software and its interface designs, code, trademarks and identifiers belongs to us or the relevant rights holders. Without permission, you must not copy, modify, distribute or use it for any commercial purpose.';

  @override
  String get legalAgreementS5P1 =>
      '2. Intellectual property in works you publish through the Service (including 3D point cloud models and derived thumbnails) remains with you or the lawful rights holder and does not transfer through publication.';

  @override
  String get legalAgreementS5P2 =>
      '3. To provide the Service and improve the Product, you grant the Platform a worldwide, royalty-free, nonexclusive license including rights to reproduce, disseminate over information networks, adapt, compile and display content, and create derivative content. Here, content means what you upload to the Service, including works published to the community and content stored through future cloud storage functions, including 3D point clouds, mesh models, thumbnails, titles and descriptions. These rights are used only for: (1) operational necessities: storage, backup, transmission, distribution, public display (only content you choose to publish publicly), format adaptation and other technical processing, which may be entrusted to cloud providers bound by this Agreement; (2) displaying and promoting your publicly published works in the Product\'s versions across devices and on app store pages; (3) our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction), using technologies and forms now known or developed later.';

  @override
  String get legalAgreementS5P3 =>
      '4. Providing research data externally: For research data provided in academic papers, public datasets or research collaborations, we use only anonymized data that cannot identify you and cannot be restored. If provision in an identifiable form is needed, we will obtain your separate consent.';

  @override
  String get legalAgreementS5P4 =>
      '5. License duration and termination: The license takes effect when content is uploaded. After you delete the relevant content or delete your account (meaning you voluntarily request deletion of your account and its personal information under Chapter III, paragraph 5 and Chapter VI of the 方寸间 Privacy Policy), the license terminates unless laws, regulations or this Agreement provide otherwise (such as sealed retention of lawfully removed content). We will stop using that content in new research and model training; research results already completed and models already trained are unaffected.';

  @override
  String get legalAgreementS5P5 =>
      '6. To better protect your rights, you agree that the Platform may itself, or through a third party, enforce rights against third-party infringement of content you upload and publish in which you hold intellectual property. Measures include monitoring infringement, sending enforcement letters, bringing litigation or arbitration, mediation and settlement. You may withdraw this enforcement authorization at any time by written notice to the Platform.';

  @override
  String get legalAgreementS5P6 =>
      '7. If you believe content in the Service infringes your lawful rights and interests, notify us through Chapter VIII with proof of ownership and preliminary evidence of infringement. We will handle it promptly under law.';

  @override
  String get legalAgreementS5P7 =>
      '8. The Platform holds rights, to the extent permitted by laws and regulations, in data and results generated in developing and operating the Service that do not include your work content itself (such as statistics, logs, anonymized analyses, algorithm and model parameters and research results). This does not alter work ownership under paragraph 2.';

  @override
  String get legalAgreementS6Title => 'VII. Enforcement and appeals';

  @override
  String get legalAgreementS6P0 =>
      '1. If you violate this Agreement, Platform Rules or laws and regulations, the Platform may, according to severity and under law and this Agreement, take one or more measures: warnings, correction deadlines, account restrictions, suspension, account closure or prohibition on re-registration. Violating works are removed and their files taken out of public locations.';

  @override
  String get legalAgreementS6P1 =>
      '2. When taking these measures, the Platform informs you of the reasons through in-app notices or other means. It retains relevant records and reports to competent authorities as required by law.';

  @override
  String get legalAgreementS6P2 =>
      '3. Appeals: If you disagree with an outcome, appeal through Chapter XIV with explanations and evidence. We review and reply within 15 working days of receipt.';

  @override
  String get legalAgreementS6P3 =>
      '4. The Platform will progressively establish an account credit management system under national rules and provide corresponding services based on account credit.';

  @override
  String get legalAgreementS7Title => 'VIII. Complaints and reports';

  @override
  String get legalAgreementS7P0 =>
      '1. Each work page provides a report option. You may also complain about or report unlawful or violating content or conduct through Chapter XIV.';

  @override
  String get legalAgreementS7P1 =>
      '2. We maintain a public complaint and report handling mechanism to accept and handle reports promptly. Reports involving minors receive priority. On notification by a minor or guardian of cyberbullying content, we promptly take necessary measures such as deletion or blocking.';

  @override
  String get legalAgreementS8Title =>
      'IX. Changes, interruptions and termination';

  @override
  String get legalAgreementS8P0 =>
      '1. The Platform may change or interrupt some or all services because of changes in laws and regulations, regulatory requirements, technical upgrades or operational adjustments. For interruptions caused by maintenance, failures or force majeure, it will make reasonable efforts to restore service promptly.';

  @override
  String get legalAgreementS8P1 =>
      '2. If the Platform decides to cease all service operations, it will announce this in the app 30 days in advance and provide a work file export channel before closure. We also recommend regularly backing up important works yourself.';

  @override
  String get legalAgreementS8P2 =>
      '3. If a merger, division, acquisition or similar event requires transfer to a successor, the Platform will notify you under law. The successor remains bound by this Agreement and the 方寸间 Privacy Policy; otherwise your consent will be obtained again.';

  @override
  String get legalAgreementS8P3 =>
      '4. After termination, the Platform deletes or anonymizes your personal information under the 方寸间 Privacy Policy.';

  @override
  String get legalAgreementS8P4 =>
      '5. The Platform may entrust some operational or technical support work to affiliates or professional providers, while remaining responsible to you under this Agreement.';

  @override
  String get legalAgreementS9Title =>
      'X. Disclaimers and limitation of liability';

  @override
  String get legalAgreementS9P0 =>
      '1. The Service is provided “as is” and “as available”. To the extent permitted by law, the Platform does not guarantee uninterrupted, error-free or completely secure service. Reconstruction quality depends on capture conditions, device performance and other factors; results are not guaranteed to meet your particular expectations. The Product\'s 3D reconstruction uses AI technology, which currently has limitations difficult to avoid entirely; results may contain errors, omissions or distortion.';

  @override
  String get legalAgreementS9P1 =>
      '2. To the extent permitted by law, the Platform is not liable for losses caused by force majeure (such as natural disasters, strikes, network infrastructure failures or regulatory policy changes), third parties (such as basic telecommunications interruptions or third-party provider failures), or your own actions.';

  @override
  String get legalAgreementS9P2 =>
      '3. To the maximum extent permitted by law, the Platform is not liable for indirect, consequential or punitive losses. Its total liability to you for the services under this Agreement does not exceed the total fees you actually paid it for the Service (the Service is currently free, in which case liability is limited to actual losses as prescribed by law). This does not apply to damage caused by the Platform\'s intent or gross negligence or exclude liability that cannot lawfully be excluded.';

  @override
  String get legalAgreementS9P3 =>
      '4. Other users\' content represents their views, not the Platform\'s. You may request assistance under this Agreement with disputes between users, but the Platform does not bear the parties\' civil liability. Assess the suitability of content and files obtained through the Service yourself and bear the risks of use. Third-party links or content, if present, are not controlled by the Platform, which is not responsible for their accuracy or security.';

  @override
  String get legalAgreementS9P4 =>
      '5. The Platform reviews published content under law. Review is no guarantee or endorsement of legality, truthfulness or quality, and does not exempt publishers from legal responsibility.';

  @override
  String get legalAgreementS9P5 =>
      '6. If the Platform\'s violation of laws, regulations or this Agreement causes you loss, it bears corresponding liability under law. If your violation causes loss to the Platform or third parties, you likewise bear liability under law.';

  @override
  String get legalAgreementS10Title => 'XI. Minors';

  @override
  String get legalAgreementS10P0 =>
      '1. The Service is only for users aged 14 or older. Minors under 14 may not register or use it.';

  @override
  String get legalAgreementS10P1 =>
      '2. Users aged 14 to under 18 must obtain a guardian\'s consent and use the Service under their guidance. Guardians who have not consented may notify the Platform through Chapter XIV; it will handle the relevant account under law.';

  @override
  String get legalAgreementS10P2 =>
      '3. The Platform does not create or push content that induces addiction in minors or provide inducement-based tipping or spending functions. Content that may affect minors\' physical or mental health will be handled under law.';

  @override
  String get legalAgreementS10P3 =>
      '4. Obtain a minor\'s guardian\'s consent as required by law before publishing works depicting that minor.';

  @override
  String get legalAgreementS11Title => 'XII. Amendments and notices';

  @override
  String get legalAgreementS11P0 =>
      '1. We may amend this Agreement because of changes in laws, regulations, regulatory requirements or the Service. Amendments will be displayed in the app at least 7 days before taking effect; amendments materially affecting your rights and obligations will be displayed for at least 15 days.';

  @override
  String get legalAgreementS11P1 =>
      '2. If you disagree, you may stop using the Service and delete your account; rights and obligations before deletion follow the previous Agreement. Continued use after the notice period constitutes acceptance of the amended Agreement. We will not make acceptance of amendments a preselected option.';

  @override
  String get legalAgreementS11P2 =>
      '3. We retain previous versions of this Agreement, available on request through Chapter XIV.';

  @override
  String get legalAgreementS11P3 =>
      '4. Platform notices may be given through in-app announcements, system notifications, page prompts or your linked phone number or email, and are deemed delivered on publication or sending. Notices from you to the Platform should use the contact methods published in Chapter XIV.';

  @override
  String get legalAgreementS12Title =>
      'XIII. Governing law and dispute resolution';

  @override
  String get legalAgreementS12P0 =>
      '1. The formation, validity, interpretation and dispute resolution of this Agreement are governed by the laws of the People\'s Republic of China (excluding Hong Kong, Macao and Taiwan for this Agreement).';

  @override
  String get legalAgreementS12P1 =>
      '2. Disputes should first be resolved through friendly consultation. If unsuccessful, either party may bring proceedings in a people\'s court with jurisdiction in 【公司注册地待定后填写】.';

  @override
  String get legalAgreementS12P2 =>
      '3. Invalidity or unenforceability of a term does not affect the remaining terms.';

  @override
  String get legalAgreementS12P3 =>
      '4. Headings are for reading convenience only and are not a basis for interpreting terms.';

  @override
  String get legalAgreementS12P4 =>
      '5. You and the Platform are independent entities. This Agreement creates no partnership, agency, employment or guarantee relationship between you.';

  @override
  String get legalAgreementS12P5 =>
      '6. This Agreement and its component documents constitute the entire agreement between the parties on the relevant matters.';

  @override
  String get legalAgreementS13Title => 'XIV. Contact us';

  @override
  String get legalAgreementS13P0 => 'Operator: 【公司名称待注册后填写】';

  @override
  String get legalAgreementS13P1 =>
      'Contact email: 【联系邮箱待填写 —— 上线前必须替换为真实可达邮箱,与平台公约页、隐私政策同一个】';

  @override
  String get legalAgreementS13P2 =>
      'We handle and respond to your feedback, complaints or appeals within 15 working days of receipt.';

  @override
  String get legalRulesS0Title => '1. Accounts and Names';

  @override
  String get legalRulesS0P0 =>
      'Display names may repeat; your ID is unique across the platform. Display names are for showing, IDs are for being found.';

  @override
  String get legalRulesS0P1 =>
      'Display names allow up to 20 characters, including Chinese, English and emoji. Leading/trailing spaces are trimmed and internal runs of spaces are collapsed.';

  @override
  String get legalRulesS0P2 =>
      'IDs consist of 2-32 lowercase letters, digits, dots or underscores. They may not start or end with a dot/underscore, nor contain consecutive ones.';

  @override
  String get legalRulesS0P3 =>
      'A display name or ID cannot be changed again within 3 days of being set.';

  @override
  String get legalRulesS0P4 =>
      'Names that could be mistaken for official platform identities are not permitted, including \"official\", \"support\", \"admin\", \"system\" and their Chinese equivalents.';

  @override
  String get legalRulesS0P5 =>
      'Names containing national or party symbols are subject to stricter verification under applicable Chinese regulations.';

  @override
  String get legalRulesS0P6 =>
      'Registration requires real-identity verification. Unverified accounts cannot publish.';

  @override
  String get legalRulesS1Title => '2. Publishing and Review';

  @override
  String get legalRulesS1P0 =>
      'Published works enter review and only appear in the community feed after approval. Until then they are not visible to others.';

  @override
  String get legalRulesS1P1 =>
      'Titles are limited to 100 characters; descriptions to 30.';

  @override
  String get legalRulesS1P2 =>
      'Content prohibited by law may not be published.';

  @override
  String get legalRulesS1P3 =>
      'Obtain consent from people appearing in a scene before publishing it publicly.';

  @override
  String get legalRulesS1P4 =>
      'Exported 3D model files carry a provenance marker, as required by Chinese regulations on deep synthesis services. It does not affect normal use of the file.';

  @override
  String get legalRulesS2Title => '3. Enforcement';

  @override
  String get legalRulesS2P0 =>
      'Available measures: warning, required correction within a period, feature restriction, suspension, account closure.';

  @override
  String get legalRulesS2P1 =>
      'Violating works are taken down and their files removed from public storage; previously saved links stop working.';

  @override
  String get legalRulesS2P2 =>
      'You may delete your own work at any time, including work still under review that was never public.';

  @override
  String get legalRulesS2P3 =>
      'Account-related actions are logged and retained for at least 6 months.';

  @override
  String get legalRulesS3Title => '4. Reporting and Appeals';

  @override
  String get legalRulesS3P0 =>
      'Every work page provides a reporting entry with categories including spam, harassment, hate speech, sexual content, violence, copyright and misinformation.';

  @override
  String get legalRulesS3P1 =>
      'You may also block a user; their works will no longer appear in your feed.';

  @override
  String get legalRulesS3P2 =>
      'To appeal an enforcement decision, use the contact below.';

  @override
  String get legalRulesS4Title => '5. Contact';

  @override
  String get legalRulesS4P0 =>
      'Email: [TO BE FILLED — must be a real, reachable address before launch]';

  @override
  String get legalRulesS4P1 =>
      'We respond to reports and appeals as promptly as we can.';

  @override
  String get legalRulesFooter =>
      'These rules describe how the product actually behaves today, and are updated when behaviour changes. In case of any discrepancy, the Chinese version prevails.';

  @override
  String get legalPrivacyTitle => '方寸间 Privacy Policy';

  @override
  String get legalAgreementTitle => '方寸间 User Agreement';

  @override
  String get legalVersionLabel => 'Version';

  @override
  String get legalEffectiveDateLabel => 'Effective date';

  @override
  String get legalEffectiveDatePending =>
      '[Effective date to be completed before launch]';

  @override
  String get legalTranslationNotice =>
      'The English translation is provided for reading convenience. The Chinese version of this document prevails.';

  @override
  String get sharedViewerTitle => 'PocketWorld 3D Viewer';

  @override
  String get sharedViewerCanvasLabel => '3D work';

  @override
  String get sharedViewerInitializing => 'Starting viewer…';

  @override
  String get sharedViewerLoading => 'Loading…';

  @override
  String get sharedViewerFailure =>
      'Unable to display this work. Please try again.';

  @override
  String get sharedViewerSkpNotice =>
      'SKP preview: complex structures may look different.';

  @override
  String get legalStaticV11Copy0 =>
      'Chuang Hou Cheng Privacy Policy | 北京空也科技有限公司';

  @override
  String get legalStaticV11Copy2 => 'Back to community';

  @override
  String get legalStaticV11Copy3 => 'Chuang Hou Cheng Privacy Policy';

  @override
  String get legalStaticV11Copy4 => 'V1.1 · Effective date: November 2, 2026';

  @override
  String get legalStaticV11Copy9 =>
      '“Chuang Hou Cheng” (the “Product”) is operated by 北京空也科技有限公司 (“we” or “us”). This Policy explains how we collect, use, store and protect your personal information, and your rights and how to exercise them. Please read this Policy carefully before using the Product, especially the terms in bold.';

  @override
  String get legalStaticV11Copy10 =>
      '① Original photos and motion sensor data during capture are used for on-device reconstruction. Private cloud backup and community publishing upload the final 3D models and related files you choose. Review images are rendered from models, not original capture photos;';

  @override
  String get legalStaticV11Copy11 =>
      '③ We entrust 阿里云 with storage, communications and content review services; see Chapter III for the processing scope. Public publication does not remove obligations to protect personal information;';

  @override
  String get legalStaticV11Copy12 =>
      'We process information in the following scenarios. Each item describes its purpose, method and retention period. Except for your phone number, all items are optional; refusing to provide them does not affect your use of other functions.';

  @override
  String get legalStaticV11Copy13 =>
      '· Original photos: Saved in the Product\'s documents directory on your device. You can view, export or delete them using the system Files app. On-device reconstruction and the model backup and publication review processes described in this Policy do not require uploading these photos. Exporting them yourself or sharing them through other services is outside these processes.';

  @override
  String get legalStaticV11Copy14 =>
      '· Final 3D works: Stored on your device if you do not choose cloud functions. If you choose private cloud backup or public publication, they are uploaded for the separate purposes below.';

  @override
  String get legalStaticV11Copy15 =>
      '· Private cloud backup (optional): For retrieval, download and viewing, and protection against local loss. We store the final models you choose to back up (such as GLB mesh models and PLY point clouds, subject to formats currently supported), covers and work records needed for recovery. Backup is not publication and does not put works in the community or make them public to others. Retained until you delete the backup or your account; see Chapter IV for statutory retention and backup cleanup limitations.';

  @override
  String get legalStaticV11Copy16 =>
      '· Work content (optional; necessary for publishing): Only when you actively choose public publication do we collect the final 3D model (including currently supported formats such as GLB mesh models and PLY point clouds), model-generated cover, title and description. Works remain nonpublic during submission and review, and are displayed publicly to all users, including visitors who are not signed in, only after approval and completion of publication.';

  @override
  String get legalStaticV11Copy17 =>
      '· Publication review: To check for unlawful and harmful content, the Platform generates 26 review images from multiple angles of the submitted final GLB model. 阿里云 reviews the title and description as text and the 26 model-rendered images as images. These are not original capture photos; this review does not send capture process data, sign-in passwords or account contact details to 阿里云. Detected risks may be referred for manual checks, clear violations are rejected, and works remain nonpublic if the service fails or results are incomplete. Currently unsupported formats cannot automatically become public through this process; follow the page instructions. Review materials and results are retained and cleared under Chapter IV.';

  @override
  String get legalStaticV11Copy18 =>
      '· When publishing, you acknowledge that once the work is published and approved, its content, your nickname, account ID and IP region at publication will be visible to everyone. Public publication does not waive your privacy or personal information rights or replace authorization from other rights holders represented in the work.';

  @override
  String get legalStaticV11Copy19 =>
      '· Research and technical improvement: The work content you upload will be used for our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction). When providing research data externally, we use only anonymized data that cannot identify you and cannot be restored, or obtain your separate consent. See Chapter VI of the Chuang Hou Cheng User Agreement.';

  @override
  String get legalStaticV11Copy20 =>
      'Local storage: The Product has no embedded web browser and does not use cookies. The following is stored only on your device and will not be read by us for purposes not stated in this Policy: sign-in credentials (in the system keychain), language and interface preferences, temporary file caches from viewing others\' works (to speed loading, removable by the system), and original photos and reconstruction outputs you have not chosen to upload. Content you choose to back up or submit for publication is handled separately under Chapter I.';

  @override
  String get legalStaticV11Copy21 =>
      '· Content review provider: 阿里云 content security services. To review works you actively submit for publication, the provider processes titles, descriptions and 26 review images generated from final models on our behalf, and returns risk labels and review results. This service does not receive original capture photos, complete 3D models, sign-in passwords or account contact details. We limit submissions to the review purpose and provide review images through private storage and short-lived authorized links; the images are not made into public community albums.';

  @override
  String get legalStaticV11Copy22 =>
      '· Email provider: 阿里云邮件推送 (DirectMail), for email verification codes, account recovery and related notices, processing your email address and email content for the relevant sending purpose.';

  @override
  String get legalStaticV11Copy23 =>
      '(2) Provision to other personal information processors: Except for the entrusted processing described above, your active public publication, fulfillment of legal obligations or separately obtained valid consent, we do not provide your personal information to other processors. Information anonymized so that it cannot identify a specific person and cannot be restored is not personal information under law. Only such anonymized data is used in our external research collaborations (see Chapter I(3)).';

  @override
  String get legalStaticV11Copy24 =>
      '2. Retention periods: Chapter I lists each period. In summary: account details (phone/email/nickname/ID/biography) until account deletion; private backups, works and interaction records until deletion or account deletion, subject to statutory retention and backup cleanup limitations below; view records anonymized after account deletion; analytics events 180 days; security audit logs 180 days (major actions 730 days); API frequency records no more than 1 day; temporary registration verification data 10 minutes. Review models, images and results are kept only within the scope and for the periods needed for review, complaint and appeal handling, necessary security protection and statutory retention, not indefinitely for storage convenience; they are then deleted or anonymized. Statutory retention or technical difficulty in immediate deletion is subject to restricted processing as described below.';

  @override
  String get legalStaticV11Copy25 =>
      '3. Deletion limitations and retention: After deletion or withdrawal, relevant works are no longer provided as public content. Review evidence, report and appeal materials, or necessary copies of lawfully removed works may not be physically deletable immediately because of statutory retention obligations, ongoing disputes or storage retention locks. We restrict their use and access and clear them after the relevant grounds and necessary retention periods end. Backup copies are cleared through backup rotation and deletion procedures. Recorded deletion requests must still be enforced when restoring backups; restoration must not republish content or return it to normal use. If a legally required retention period has not expired or deletion is technically difficult, we stop all processing except storage and necessary security safeguards.';

  @override
  String get legalStaticV11Copy26 =>
      '3. Deletion: You may request deletion of your works (including those under review) on the work page, and request deletion of private cloud backups. We stop public or normal provision of relevant content, cancel pending publication processing and clear files. Review evidence, retention locks and historical backups do not mean immediate physical erasure; see Chapter IV, paragraph 3. Submit other deletion requests through our contact methods. We proactively delete information in statutory circumstances such as fulfillment of processing purposes, service cessation, withdrawal of consent or unlawful or contract-breaching processing by us. If a legally required retention period has not expired or deletion is technically difficult, we stop all processing except storage and necessary security safeguards.';

  @override
  String get legalStaticV11Copy27 =>
      'Personal information processor: 北京空也科技有限公司';

  @override
  String get legalStaticV11Copy28 =>
      'Business license domicile recorded in filing materials (province/city/district): Haidian District, Beijing';

  @override
  String get legalStaticV11Copy29 =>
      'Personal information protection officer email: wkd20040211@163.com';

  @override
  String get legalStaticV11Copy31 =>
      'Chuang Hou Cheng User Agreement | 北京空也科技有限公司';

  @override
  String get legalStaticV11Copy32 => 'Chuang Hou Cheng User Agreement';

  @override
  String get legalStaticV11Copy33 =>
      'Welcome to “Chuang Hou Cheng”. This Agreement is between you and 北京空也科技有限公司 (“we” or the “Platform”) concerning use of the Chuang Hou Cheng software and related services. Please read it in full before registration, especially the bold terms on exclusions or limitations of liability, licenses of rights and dispute jurisdiction.';

  @override
  String get legalStaticV11Copy34 =>
      'The Chuang Hou Cheng Platform Rules (including account management rules) and Chuang Hou Cheng Privacy Policy form integral parts of this Agreement and have equal effect. Accepting this Agreement constitutes acceptance of those documents as well.';

  @override
  String get legalStaticV11Copy35 =>
      'Chuang Hou Cheng is a 3D spatial content tool and community: you can reconstruct 3D works on your device or use final model files supported by current functions. Final models include GLB meshes and PLY point clouds; see the relevant function page for supported formats. You may separately choose private cloud backup or public publication; they are different operations.';

  @override
  String get legalStaticV11Copy36 =>
      '5. Account deletion: You may delete your account at any time in “Settings → Account”. See the Chuang Hou Cheng Privacy Policy for the process and data handling.';

  @override
  String get legalStaticV11Copy37 =>
      '1. Review before publication: Works you submit must pass Platform review before appearing in the community. During review, they are invisible to other users and you may request withdrawal or deletion. Uploading a private cloud backup does not automatically turn it into a public work.';

  @override
  String get legalStaticV11Copy38 =>
      'Review method: For final GLB models, the Platform generates 26 model-rendered images from multiple angles and entrusts 阿里云 with text review of titles and descriptions and image review of review images. This process does not require original capture photos or capture process data. Risks detected by automated review may be referred for manual review; clear violations are rejected, and service failures or incomplete results do not lead to automatic public access. Currently unsupported formats cannot automatically become public through this process; changes to submitted work content require another review.';

  @override
  String get legalStaticV11Copy39 =>
      '2. Publication is public: Once approved, the work\'s content, your nickname, account ID and IP region at publication are publicly visible to all users, including visitors who are not signed in. Public publication does not waive privacy or personal information rights or remove the publisher\'s duty to obtain others\' authorization. IP region display is legally required and cannot be disabled; see the Chuang Hou Cheng Privacy Policy.';

  @override
  String get legalStaticV11Copy40 =>
      '3. “Content” in this Agreement includes 3D models (such as GLB meshes and PLY point clouds), reconstruction data, covers and derived review images, titles, descriptions, account details and any other information you upload or publish through the Service.';

  @override
  String get legalStaticV11Copy41 =>
      'Deletion, withdrawal and evidence retention: Ending public access does not immediately physically erase all copies. Restricted processing and cleanup of review materials, complaint and appeal evidence, statutory retention and historical backups follow Chapter IV of the Chuang Hou Cheng Privacy Policy. Restoring backups must not republish relevant copies.';

  @override
  String get legalStaticV11Copy42 =>
      '2. Intellectual property in works you upload or publish through the Service (including 3D point clouds, mesh models and derived covers and review images) remains with you or the lawful rights holder and does not transfer through publication.';

  @override
  String get legalStaticV11Copy43 =>
      '3. To provide the Service and improve the Product, you grant the Platform a worldwide, royalty-free, nonexclusive license including rights to reproduce, disseminate over information networks, adapt, compile and display content, and create derivative content. Here, content means what you upload to the Service, including works published to the community and content stored through private cloud backup (cloud storage), including 3D point clouds, mesh models, covers, derived review images, titles and descriptions. These rights are used only for: (1) operational necessities: storage, backup, transmission, distribution, public display (only content you choose to publish publicly), format adaptation, review image generation, text and image content security checks and other technical processing, which may be entrusted to cloud and content review providers subject to binding obligations; (2) displaying and promoting your publicly published works in the Product\'s versions across devices and on app store pages; (3) our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction), using technologies and forms now known or developed later.';

  @override
  String get legalStaticV11Copy44 =>
      '5. License duration and termination: The license takes effect when content is uploaded. After you delete the relevant content or delete your account (meaning you voluntarily request deletion of your account and its personal information under Chapter III, paragraph 5 and Chapter VI of the Chuang Hou Cheng Privacy Policy), the license terminates unless laws, regulations or this Agreement provide otherwise (such as sealed retention of lawfully removed content). We will stop using that content in new research and model training; research results already completed and models already trained are unaffected.';

  @override
  String get legalStaticV11Copy45 =>
      '3. If a merger, division, acquisition or similar event requires transfer to a successor, the Platform will notify you under law. The successor remains bound by this Agreement and the Chuang Hou Cheng Privacy Policy; otherwise your consent will be obtained again.';

  @override
  String get legalStaticV11Copy46 =>
      '4. After termination, the Platform deletes or anonymizes your personal information under the Chuang Hou Cheng Privacy Policy.';

  @override
  String get legalStaticV11Copy47 =>
      '2. Disputes should first be resolved through friendly consultation. If unsuccessful, either party may bring proceedings in a people\'s court with jurisdiction at the company\'s domicile.';

  @override
  String get legalStaticV11Copy48 => 'Operator: 北京空也科技有限公司';

  @override
  String get legalStaticV11Copy49 => 'Contact email: wkd20040211@163.com';

  @override
  String get legalStaticV11Copy50 =>
      'Chuang Hou Cheng Platform Rules | 北京空也科技有限公司';

  @override
  String get legalStaticV11Copy51 => 'Chuang Hou Cheng Platform Rules';

  @override
  String get legalStaticV11Copy52 =>
      'Private cloud backup and public publication are separate: backups do not automatically enter the community. Active submissions enter review, and only appear in the community after approval and completion of publication; until then they are invisible to other users.';

  @override
  String get legalStaticV11Copy53 =>
      'GLB publication review generates 26 rendered images from multiple angles of the final model. Titles, descriptions and these review images are reviewed by 阿里云 text and image review services. Review images are not original capture photos. Currently unsupported formats cannot automatically become public through this process.';

  @override
  String get legalStaticV11Copy54 =>
      'Detected risks may be referred for manual checks, clear violations are returned, and service failures or incomplete results do not lead to automatic public access. Changes to work content require another review. Public publication does not waive privacy or others\' lawful rights and interests.';

  @override
  String get legalStaticV11Copy55 =>
      'You may request withdrawal or deletion of your works, including works still under review that have never been public. Ending public access and physically clearing files are separate; see the Privacy Policy for restricted processing and cleanup of review evidence, dispute materials and historical backups.';

  @override
  String get legalStaticV11Copy56 => 'Email: wkd20040211@163.com';

  @override
  String get legalStaticV11Copy57 =>
      '3D publication and review | Chuang Hou Cheng';

  @override
  String get legalStaticV11Copy58 => 'Published November 2, 2026 · V1.1';

  @override
  String get legalStaticV11Copy59 => 'Private backup and public publication';

  @override
  String get legalStaticV11Copy60 =>
      'Private cloud backups do not automatically become community works. Works enter the public community only when you actively submit them for public publication and they pass review.';

  @override
  String get legalStaticV11Copy61 => 'What content review uses';

  @override
  String get legalStaticV11Copy62 =>
      'Submitting for publication uploads the final GLB model, title and description. The cloud generates 26 review images from different angles of the same model and uses 阿里云 text and image review services to check the title, description and images. Review images are rendered from the model, not original capture photos; the complete model is not sent to the 阿里云 image review API.';

  @override
  String get legalStaticV11Copy63 =>
      'The 26-view approach is the Product\'s current review method; it does not mean coverage of every model surface has been proven. Currently supported models are self-contained static GLB files within 50 MB. Unsupported models do not pass automatically.';

  @override
  String get legalStaticV11Copy64 => 'Review outcomes and public access';

  @override
  String get legalStaticV11Copy65 =>
      'Works may be displayed publicly after all review checks pass and publication conditions are met. Risky works receive manual handling. Blocked works, review errors, incomplete evidence and unsupported models do not lead to automatic public access. Replacing a model requires another review.';

  @override
  String get legalStaticV11Copy66 =>
      'Visitors who are not signed in can view and share public works. Liking and commenting require sign-in. Examples under open licenses retain their material sources and licensing identities.';

  @override
  String get legalStaticV11Copy67 => 'Withdrawal, deletion and rights';

  @override
  String get legalStaticV11Copy68 =>
      'You may withdraw public publication, request deletion, or submit reports and appeals. Review evidence, dispute handling, statutory retention and historical backups follow the Privacy Policy and actual retention mechanisms. Public publication does not remove your or others\' personal information rights and interests.';

  @override
  String get legalStaticV11Copy69 => 'Operation and contact';

  @override
  String get legalStaticV11Copy70 => 'Operator: 北京空也科技有限公司';

  @override
  String get legalStaticPrivacyIntro =>
      'This page publishes the Chuang Hou Cheng app Privacy Policy. Before publishing works publicly, please also read ';

  @override
  String get legalStaticTermsIntro =>
      'This page publishes the Chuang Hou Cheng app User Agreement. Before publishing works publicly, please also read ';

  @override
  String get legalStaticRulesIntro =>
      'This page publishes the Chuang Hou Cheng app Platform Rules. Before publishing works publicly, please also read ';

  @override
  String get legalStaticContactPrefix =>
      'Product service and privacy contact: ';

  @override
  String get legalStaticSentenceEnd => '.';

  @override
  String get siteAuthorLoading => 'Loading author…';

  @override
  String get siteAuthorUnavailable => 'Author unavailable';

  @override
  String get siteAuthorRetry => 'Retry';

  @override
  String get commentResizePanel => 'Resize comments panel';

  @override
  String get commentResizePanelHint =>
      'Drag left to widen or right to narrow. Use the left and right arrow keys to adjust.';

  @override
  String commentPanelWidth(int width) {
    return '$width pixels';
  }

  @override
  String get siteScreenOne => 'Screen 01';

  @override
  String get siteScreenTwo => 'Screen 02';

  @override
  String get siteScreenThree => 'Screen 03';

  @override
  String get siteScreenPlaceholder => 'Content coming soon';

  @override
  String get siteScreenSelection => 'Choose a screen';

  @override
  String get siteScreenBack => 'Back to community';

  @override
  String get siteScreenStage => 'Featured screens';

  @override
  String get reportHistoryLoading => 'Loading reports';

  @override
  String get reportHistoryNotice =>
      'Only reports you submitted are shown. Platform notifications confirm outcomes.';

  @override
  String get reportRecordId => 'Report ID';

  @override
  String get reportRecordReason => 'Reason';

  @override
  String get reportRecordOutcome => 'Outcome';

  @override
  String get reportOutcomeUnavailable => 'No outcome yet';

  @override
  String get reportAppealAction => 'Submit appeal';

  @override
  String get reportAppealUnavailable =>
      'Online appeals are currently unavailable.';

  @override
  String get reportAppealSubmitted =>
      'Appeal submitted. Watch for a platform notification.';

  @override
  String get reportStatusClosed => 'Closed';

  @override
  String get reportStatusUnknown => 'Status unconfirmed';

  @override
  String get reportAppealRequired => 'Enter an appeal explanation';

  @override
  String get reportAppealFailed => 'Appeal submission failed. Try again.';

  @override
  String get reportAppealExplanation => 'Appeal explanation';

  @override
  String get reportAppealPrivacy =>
      'Do not include passwords, identity document numbers or other sensitive information.';

  @override
  String get reportAppealSubmitting => 'Submitting…';

  @override
  String get reportAppealSubmit => 'Submit';

  @override
  String get authPolicyConsentLabel => 'I have read and agree to';

  @override
  String get webSettingsLanguage => 'Language';

  @override
  String get webSettingsHelp => 'Help';

  @override
  String get webHelpTitle => 'Help & contact';

  @override
  String get webHelpViewQuestion => 'How do I view a 3D work?';

  @override
  String get webHelpViewAnswer =>
      'Open a work from its cover. Drag to rotate and use the mouse wheel or pinch to zoom.';

  @override
  String get webHelpPublishQuestion =>
      'Why is my published work not visible yet?';

  @override
  String get webHelpPublishAnswer =>
      'Works appear in the community after review. Check the processing status in your publication history.';

  @override
  String get webHelpAccountQuestion => 'What can I do after signing in?';

  @override
  String get webHelpAccountAnswer =>
      'Sign in to publish, like, save and comment on works, follow creators and send private messages.';

  @override
  String get webHelpContactLabel => 'Contact support';

  @override
  String get webAccountLikes => 'My likes';

  @override
  String get webAccountFavorites => 'My favorites';

  @override
  String get webAccountHistory => 'Viewing history';

  @override
  String get resetVerifyCode => 'Verify code';

  @override
  String get resetSubtitleNewPassword =>
      'Choose a new password, then return to sign in.';

  @override
  String get resetConfirmPasswordHint => 'Confirm new password';

  @override
  String get resetPasswordTooShort =>
      'Use at least 8 characters for your new password.';

  @override
  String get resetPasswordMismatch => 'The passwords do not match.';

  @override
  String get resetInvalidCode =>
      'The code is incorrect or has expired. Please try again.';

  @override
  String get resetRequestFailed =>
      'Unable to reset your password. Please try again.';

  @override
  String get resetRateLimited => 'Too many requests. Please try again later.';

  @override
  String get resetNetworkError =>
      'The request timed out or could not connect. Please try again.';

  @override
  String get resetSessionExpired =>
      'Your recovery session has expired. Return to sign in and request a new code.';

  @override
  String get authPhonePasswordLogin => 'Phone login';

  @override
  String get authEmailPasswordLogin => 'Email login';

  @override
  String get authCodeLogin => 'Code login';

  @override
  String get authPasswordLogin => 'Password login';

  @override
  String get authLoginCodeTitle => 'Sign in with a code';

  @override
  String get authLoginCodeFailed =>
      'Unable to send or verify the login code. Please try again.';
}
