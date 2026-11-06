import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Brand wordmark — English
  ///
  /// In en, this message translates to:
  /// **'PocketWorld'**
  String get appBrand;

  /// No description provided for @splashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'3D capture · minimalist workbench'**
  String get splashSubtitle;

  /// No description provided for @splashStartingEngine.
  ///
  /// In en, this message translates to:
  /// **'Starting 3D engine…'**
  String get splashStartingEngine;

  /// No description provided for @splashRestoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring session…'**
  String get splashRestoringSession;

  /// No description provided for @splashPreparingSignIn.
  ///
  /// In en, this message translates to:
  /// **'Preparing sign-in…'**
  String get splashPreparingSignIn;

  /// No description provided for @authServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sign-in service is unavailable. Check your network and retry.'**
  String get authServiceUnavailable;

  /// No description provided for @authRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get authRetry;

  /// No description provided for @authAutoRetrying.
  ///
  /// In en, this message translates to:
  /// **'Retrying automatically in the background'**
  String get authAutoRetrying;

  /// No description provided for @splashWaking3DEngine.
  ///
  /// In en, this message translates to:
  /// **'Waking 3D engine…'**
  String get splashWaking3DEngine;

  /// No description provided for @splashRendererUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Renderer unavailable, retrying…'**
  String get splashRendererUnavailable;

  /// No description provided for @communityEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No works yet'**
  String get communityEmptyTitle;

  /// No description provided for @communitySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search works'**
  String get communitySearchHint;

  /// No description provided for @communityTabHot.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get communityTabHot;

  /// No description provided for @communityTabNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get communityTabNearby;

  /// No description provided for @communityTabDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get communityTabDiscover;

  /// No description provided for @communityOnlyAuthor.
  ///
  /// In en, this message translates to:
  /// **'Only @{name}'**
  String communityOnlyAuthor(String name);

  /// No description provided for @communityClearAuthorFilter.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get communityClearAuthorFilter;

  /// No description provided for @communityTopicTitle.
  ///
  /// In en, this message translates to:
  /// **'Editors\' Picks'**
  String get communityTopicTitle;

  /// No description provided for @communityTopicBody.
  ///
  /// In en, this message translates to:
  /// **'Spaces we picked by hand. Want to be here? Publish what you scanned.'**
  String get communityTopicBody;

  /// No description provided for @communityTopicCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan it better'**
  String get communityTopicCaptureTitle;

  /// No description provided for @communityTopicCaptureBody.
  ///
  /// In en, this message translates to:
  /// **'Walk around it, go slow, don\'t shoot from one spot. Full coverage is what keeps the model from breaking up.'**
  String get communityTopicCaptureBody;

  /// No description provided for @communityTopicViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to turn it'**
  String get communityTopicViewerTitle;

  /// No description provided for @communityTopicViewerBody.
  ///
  /// In en, this message translates to:
  /// **'Everything here is real 3D. Drag it and look again from another angle.'**
  String get communityTopicViewerBody;

  /// No description provided for @communityNearbyComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Nearby is coming soon — stay tuned.'**
  String get communityNearbyComingSoon;

  /// No description provided for @meMyWorksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No works yet — tap the camera to start your first capture.'**
  String get meMyWorksEmpty;

  /// No description provided for @scanLifecycleCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get scanLifecycleCompleted;

  /// No description provided for @createOptionCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get createOptionCapture;

  /// No description provided for @createOptionUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get createOptionUpload;

  /// No description provided for @createImportingGlb.
  ///
  /// In en, this message translates to:
  /// **'Importing GLB model…'**
  String get createImportingGlb;

  /// No description provided for @createImportPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open file picker: {error}'**
  String createImportPickerFailed(String error);

  /// No description provided for @createImportFileUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the selected file'**
  String get createImportFileUnreadable;

  /// No description provided for @meTapHintInProgress.
  ///
  /// In en, this message translates to:
  /// **'Generating 3D model — opens when ready'**
  String get meTapHintInProgress;

  /// No description provided for @meActionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get meActionRename;

  /// No description provided for @meActionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get meActionDelete;

  /// No description provided for @meActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get meActionCancel;

  /// No description provided for @meActionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get meActionSave;

  /// No description provided for @meDuplicateWorkName.
  ///
  /// In en, this message translates to:
  /// **'A work with this name already exists. Please choose another name.'**
  String get meDuplicateWorkName;

  /// No description provided for @meRenameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get meRenameDialogTitle;

  /// No description provided for @meDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this scan?'**
  String get meDeleteDialogTitle;

  /// No description provided for @meDeleteDialogContent.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete \"{name}\" and all local original photos, point cloud, reconstruction databases, and caches. This action cannot be undone.'**
  String meDeleteDialogContent(String name);

  /// No description provided for @defaultUntitledScan.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get defaultUntitledScan;

  /// No description provided for @captureWarmupHint.
  ///
  /// In en, this message translates to:
  /// **'Initializing AR…'**
  String get captureWarmupHint;

  /// No description provided for @captureReadyHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the center button to aim'**
  String get captureReadyHint;

  /// No description provided for @captureAimHint.
  ///
  /// In en, this message translates to:
  /// **'Align the guide, then tap ✓ to lock and start'**
  String get captureAimHint;

  /// No description provided for @captureMaterialTooSparseHint.
  ///
  /// In en, this message translates to:
  /// **'Keep scanning a moment longer before stopping'**
  String get captureMaterialTooSparseHint;

  /// No description provided for @captureLockFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Surface not detected or tracking not ready — point at the object\'s surface and try again'**
  String get captureLockFailedHint;

  /// No description provided for @captureInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Initialization failed: {error}'**
  String captureInitFailed(String error);

  /// No description provided for @captureRecordingStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start recording: {error}'**
  String captureRecordingStartFailed(String error);

  /// No description provided for @relativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get relativeJustNow;

  /// No description provided for @relativeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String relativeMinutesAgo(int n);

  /// No description provided for @relativeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String relativeHoursAgo(int n);

  /// No description provided for @relativeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} d ago'**
  String relativeDaysAgo(int n);

  /// No description provided for @relativeWeeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} w ago'**
  String relativeWeeksAgo(int n);

  /// No description provided for @relativeMonthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} mo ago'**
  String relativeMonthsAgo(int n);

  /// No description provided for @meSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get meSettingsTitle;

  /// No description provided for @meNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get meNotifications;

  /// No description provided for @meNotificationsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get meNotificationsOn;

  /// No description provided for @mePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get mePrivacy;

  /// No description provided for @meNotificationsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get meNotificationsOff;

  /// No description provided for @mePrivacyPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get mePrivacyPublic;

  /// No description provided for @mePrivacyPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get mePrivacyPrivate;

  /// No description provided for @meSettingNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get meSettingNotConfigured;

  /// No description provided for @meLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get meLanguage;

  /// No description provided for @meLanguageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get meLanguageZh;

  /// No description provided for @meLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get meLanguageEn;

  /// No description provided for @meAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get meAbout;

  /// No description provided for @meSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get meSignOut;

  /// No description provided for @meDetailRunningProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get meDetailRunningProcessing;

  /// No description provided for @meDetailRecordNotFound.
  ///
  /// In en, this message translates to:
  /// **'Record not found'**
  String get meDetailRecordNotFound;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateAccount;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailHint;

  /// No description provided for @authAccountChinaHint.
  ///
  /// In en, this message translates to:
  /// **'Phone or email'**
  String get authAccountChinaHint;

  /// No description provided for @authAccountInternationalHint.
  ///
  /// In en, this message translates to:
  /// **'Phone (include country code) or email'**
  String get authAccountInternationalHint;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @authPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordHint;

  /// No description provided for @authPasswordHintMin.
  ///
  /// In en, this message translates to:
  /// **'Set password (min 8 chars)'**
  String get authPasswordHintMin;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authTermsAcceptance.
  ///
  /// In en, this message translates to:
  /// **'By signing up you agree to PocketWorld\'s Terms of Service and Privacy Policy.'**
  String get authTermsAcceptance;

  /// No description provided for @authErrorDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get authErrorDialogTitle;

  /// No description provided for @otpVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get otpVerifyTitle;

  /// No description provided for @otpVerifySubtitle.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}. Enter it below to finish signing up.'**
  String otpVerifySubtitle(String email);

  /// No description provided for @otpResend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get otpResend;

  /// No description provided for @otpResendCooldown.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String otpResendCooldown(int seconds);

  /// No description provided for @otpResendSent.
  ///
  /// In en, this message translates to:
  /// **'Code re-sent'**
  String get otpResendSent;

  /// No description provided for @otpUseAnotherEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get otpUseAnotherEmail;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetTitle;

  /// No description provided for @resetSubtitleEnterCode.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit code to {email}. Enter it together with your new password.'**
  String resetSubtitleEnterCode(String email);

  /// No description provided for @resetSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get resetSendCode;

  /// No description provided for @resetNewPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'New password (min 8 chars)'**
  String get resetNewPasswordHint;

  /// No description provided for @resetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetConfirm;

  /// No description provided for @captureModeLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get captureModeLocal;

  /// No description provided for @captureModeRemoteLegacy.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get captureModeRemoteLegacy;

  /// No description provided for @captureModeNewRemote.
  ///
  /// In en, this message translates to:
  /// **'New Remote'**
  String get captureModeNewRemote;

  /// No description provided for @languageDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageDialogTitle;

  /// No description provided for @languageDialogChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文 (Chinese)'**
  String get languageDialogChinese;

  /// No description provided for @languageDialogEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageDialogEnglish;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @meTabProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get meTabProjects;

  /// No description provided for @meBadgeGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get meBadgeGenerating;

  /// No description provided for @meBadgeUnfinished.
  ///
  /// In en, this message translates to:
  /// **'Unfinished'**
  String get meBadgeUnfinished;

  /// No description provided for @meBadgeDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get meBadgeDone;

  /// No description provided for @meTabDrafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get meTabDrafts;

  /// No description provided for @defaultImportedScan.
  ///
  /// In en, this message translates to:
  /// **'Imported model'**
  String get defaultImportedScan;

  /// No description provided for @meDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get meDisplayName;

  /// No description provided for @meDisplayNameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit display name'**
  String get meDisplayNameDialogTitle;

  /// No description provided for @meDisplayNameDialogHint.
  ///
  /// In en, this message translates to:
  /// **'New display name (up to 20 chars)'**
  String get meDisplayNameDialogHint;

  /// No description provided for @meDisplayNameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Display name updated'**
  String get meDisplayNameUpdated;

  /// No description provided for @meDisplayNameUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String meDisplayNameUpdateFailed(String error);

  /// No description provided for @meAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Help improve the app'**
  String get meAnalyticsTitle;

  /// No description provided for @meToggleOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get meToggleOn;

  /// No description provided for @meToggleOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get meToggleOff;

  /// No description provided for @legalUserAgreement.
  ///
  /// In en, this message translates to:
  /// **'User Agreement'**
  String get legalUserAgreement;

  /// No description provided for @legalPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get legalPrivacyPolicy;

  /// No description provided for @authTermsAcceptancePrefix.
  ///
  /// In en, this message translates to:
  /// **'By signing up you agree to:'**
  String get authTermsAcceptancePrefix;

  /// No description provided for @mePlatformRules.
  ///
  /// In en, this message translates to:
  /// **'Platform Rules'**
  String get mePlatformRules;

  /// No description provided for @meIpRegion.
  ///
  /// In en, this message translates to:
  /// **'IP location'**
  String get meIpRegion;

  /// No description provided for @meIpRegionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get meIpRegionUnknown;

  /// No description provided for @ipRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'IP location: {region}'**
  String ipRegionLabel(String region);

  /// No description provided for @authPhoneEntry.
  ///
  /// In en, this message translates to:
  /// **'Sign in with SMS code'**
  String get authPhoneEntry;

  /// No description provided for @authPhoneNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get authPhoneNumberHint;

  /// No description provided for @authPhoneDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get authPhoneDisplayNameHint;

  /// No description provided for @authPhoneSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authPhoneSendCode;

  /// No description provided for @authPhoneWillSend.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a one-time code to {target}. Standard SMS rates may apply.'**
  String authPhoneWillSend(String target);

  /// No description provided for @authPhoneCodeSentTo.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {phone}'**
  String authPhoneCodeSentTo(String phone);

  /// No description provided for @authPhoneCodeHint.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get authPhoneCodeHint;

  /// No description provided for @authPhoneSubmitSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authPhoneSubmitSignIn;

  /// No description provided for @authPhoneSubmitSignUp.
  ///
  /// In en, this message translates to:
  /// **'Complete sign up'**
  String get authPhoneSubmitSignUp;

  /// No description provided for @authPhoneChangeNumber.
  ///
  /// In en, this message translates to:
  /// **'Use another number'**
  String get authPhoneChangeNumber;

  /// No description provided for @authPhoneYourNumber.
  ///
  /// In en, this message translates to:
  /// **'your phone'**
  String get authPhoneYourNumber;

  /// No description provided for @meHandle.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get meHandle;

  /// No description provided for @meHandleNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get meHandleNotSet;

  /// No description provided for @meHandleDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set username'**
  String get meHandleDialogTitle;

  /// No description provided for @meHandleDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Lowercase letters, numbers, . and _ (2-32)'**
  String get meHandleDialogHint;

  /// No description provided for @meHandleDialogNote.
  ///
  /// In en, this message translates to:
  /// **'Your username is unique and lets people find you. It can only be changed once every 3 days.'**
  String get meHandleDialogNote;

  /// No description provided for @meHandleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Username updated'**
  String get meHandleUpdated;

  /// No description provided for @meHandleUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Username update failed: {error}'**
  String meHandleUpdateFailed(String error);

  /// No description provided for @sfmSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save Draft'**
  String get sfmSaveDraft;

  /// No description provided for @sfmNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get sfmNext;

  /// No description provided for @sfmDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get sfmDone;

  /// No description provided for @sfmBackToDrafts.
  ///
  /// In en, this message translates to:
  /// **'Back to drafts'**
  String get sfmBackToDrafts;

  /// No description provided for @sfmEditSelection.
  ///
  /// In en, this message translates to:
  /// **'Edit selection'**
  String get sfmEditSelection;

  /// No description provided for @sfmSelectionSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save selection changes?'**
  String get sfmSelectionSaveTitle;

  /// No description provided for @sfmSelectionSaveBody.
  ///
  /// In en, this message translates to:
  /// **'You adjusted the selection box. Saving keeps only the points inside it in the preview and the delivered cloud.'**
  String get sfmSelectionSaveBody;

  /// No description provided for @sfmSelectionSaveKeep.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get sfmSelectionSaveKeep;

  /// No description provided for @sfmSelectionSaveDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get sfmSelectionSaveDiscard;

  /// No description provided for @sfmSelectionSaveCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get sfmSelectionSaveCancel;

  /// No description provided for @sfmGeneratingFinalCloud.
  ///
  /// In en, this message translates to:
  /// **'Generating final point cloud…'**
  String get sfmGeneratingFinalCloud;

  /// No description provided for @captureFinishing.
  ///
  /// In en, this message translates to:
  /// **'Wrapping up capture…'**
  String get captureFinishing;

  /// No description provided for @sfmReconFailedKeptFrames.
  ///
  /// In en, this message translates to:
  /// **'Reconstruction failed — captures kept'**
  String get sfmReconFailedKeptFrames;

  /// No description provided for @sfmChipFinalRecon.
  ///
  /// In en, this message translates to:
  /// **'Final reconstruction'**
  String get sfmChipFinalRecon;

  /// No description provided for @sfmChipReconstructing.
  ///
  /// In en, this message translates to:
  /// **'Reconstructing · {count} pts…'**
  String sfmChipReconstructing(int count);

  /// No description provided for @etaCalculating.
  ///
  /// In en, this message translates to:
  /// **'Estimating…'**
  String get etaCalculating;

  /// No description provided for @etaUnderMinute.
  ///
  /// In en, this message translates to:
  /// **'Time remaining · under a minute'**
  String get etaUnderMinute;

  /// No description provided for @etaMinutes.
  ///
  /// In en, this message translates to:
  /// **'Time remaining · about {n} min'**
  String etaMinutes(int n);

  /// No description provided for @sfmChipReconDone.
  ///
  /// In en, this message translates to:
  /// **'Reconstruction complete · {count} pts'**
  String sfmChipReconDone(int count);

  /// No description provided for @sfmChipReconEnded.
  ///
  /// In en, this message translates to:
  /// **'Reconstruction ended'**
  String get sfmChipReconEnded;

  /// No description provided for @sfmQueueDrainedFinal.
  ///
  /// In en, this message translates to:
  /// **'Frame queue drained · generating final point cloud'**
  String get sfmQueueDrainedFinal;

  /// No description provided for @sfmProgressFedQueued.
  ///
  /// In en, this message translates to:
  /// **'Completed {fed}/{queued} frames'**
  String sfmProgressFedQueued(int fed, int queued);

  /// No description provided for @sfmElapsedSec.
  ///
  /// In en, this message translates to:
  /// **'{secs}s'**
  String sfmElapsedSec(int secs);

  /// No description provided for @sfmElapsedMinSec.
  ///
  /// In en, this message translates to:
  /// **'{min}m {sec}s'**
  String sfmElapsedMinSec(int min, int sec);

  /// No description provided for @sfmStage1.
  ///
  /// In en, this message translates to:
  /// **'Organizing frames… (stage 1/4 · {elapsed})'**
  String sfmStage1(String elapsed);

  /// No description provided for @sfmStage2a.
  ///
  /// In en, this message translates to:
  /// **'Completing matches… (stage 2/4 · {elapsed})'**
  String sfmStage2a(String elapsed);

  /// No description provided for @sfmStage2b.
  ///
  /// In en, this message translates to:
  /// **'Global optimization… (stage 2/4 · {elapsed})'**
  String sfmStage2b(String elapsed);

  /// No description provided for @sfmStage3.
  ///
  /// In en, this message translates to:
  /// **'Extracting colors… (stage 3/4 · {elapsed})'**
  String sfmStage3(String elapsed);

  /// No description provided for @sfmStage4.
  ///
  /// In en, this message translates to:
  /// **'Saving point cloud… (stage 4/4 · {elapsed})'**
  String sfmStage4(String elapsed);

  /// No description provided for @viewerSparseCloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Sparse Point Cloud'**
  String get viewerSparseCloudTitle;

  /// No description provided for @viewerTitleWithCount.
  ///
  /// In en, this message translates to:
  /// **'{title} · {count} pts'**
  String viewerTitleWithCount(String title, int count);

  /// No description provided for @viewerLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load point cloud'**
  String get viewerLoadFailed;

  /// No description provided for @selectionRotatePointCloud.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get selectionRotatePointCloud;

  /// No description provided for @selectionNoCloud.
  ///
  /// In en, this message translates to:
  /// **'No point cloud data'**
  String get selectionNoCloud;

  /// No description provided for @cubeFaceTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get cubeFaceTop;

  /// No description provided for @cubeFaceFront.
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get cubeFaceFront;

  /// No description provided for @cubeFaceRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get cubeFaceRight;

  /// No description provided for @cubeFaceBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get cubeFaceBack;

  /// No description provided for @cubeFaceLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get cubeFaceLeft;

  /// No description provided for @cubeFaceBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get cubeFaceBottom;

  /// No description provided for @denseStageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Processing is not available on this device yet'**
  String get denseStageUnavailable;

  /// No description provided for @selectionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get selectionCancel;

  /// No description provided for @selectionDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get selectionDiscardTitle;

  /// No description provided for @selectionDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes'**
  String get selectionDiscardConfirm;

  /// No description provided for @selectionResetRotation.
  ///
  /// In en, this message translates to:
  /// **'Reset Rotation'**
  String get selectionResetRotation;

  /// No description provided for @selectionResetZoom.
  ///
  /// In en, this message translates to:
  /// **'Reset Zoom'**
  String get selectionResetZoom;

  /// No description provided for @selectionResetBoxSize.
  ///
  /// In en, this message translates to:
  /// **'Reset Box Size'**
  String get selectionResetBoxSize;

  /// No description provided for @publishAction.
  ///
  /// In en, this message translates to:
  /// **'Publish to Community'**
  String get publishAction;

  /// No description provided for @publishNotReady.
  ///
  /// In en, this message translates to:
  /// **'Available after reconstruction'**
  String get publishNotReady;

  /// No description provided for @publishAlreadyDone.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get publishAlreadyDone;

  /// No description provided for @publishSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Once published, anyone can see this work in the community.'**
  String get publishSheetSubtitle;

  /// No description provided for @publishFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get publishFieldTitle;

  /// No description provided for @publishFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get publishFieldDescription;

  /// No description provided for @publishConfirm.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publishConfirm;

  /// No description provided for @publishInProgress.
  ///
  /// In en, this message translates to:
  /// **'Publishing'**
  String get publishInProgress;

  /// No description provided for @publishSuccess.
  ///
  /// In en, this message translates to:
  /// **'Published to community'**
  String get publishSuccess;

  /// No description provided for @publishErrSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in before publishing'**
  String get publishErrSignedOut;

  /// No description provided for @publishErrAlreadyPublished.
  ///
  /// In en, this message translates to:
  /// **'This work is already published'**
  String get publishErrAlreadyPublished;

  /// No description provided for @publishErrReading.
  ///
  /// In en, this message translates to:
  /// **'Could not read the point cloud'**
  String get publishErrReading;

  /// No description provided for @publishErrUploading.
  ///
  /// In en, this message translates to:
  /// **'Upload failed — check your connection and retry'**
  String get publishErrUploading;

  /// No description provided for @publishErrTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This scan exceeds the upload size limit — retrying will not help. Please capture a smaller area and regenerate.'**
  String get publishErrTooLarge;

  /// No description provided for @publishErrRejected.
  ///
  /// In en, this message translates to:
  /// **'This file failed server-side validation and may be corrupted. Please regenerate the scan.'**
  String get publishErrRejected;

  /// No description provided for @publishErrInserting.
  ///
  /// In en, this message translates to:
  /// **'Could not save the publication, please retry'**
  String get publishErrInserting;

  /// No description provided for @publishErrGeneric.
  ///
  /// In en, this message translates to:
  /// **'Publish failed'**
  String get publishErrGeneric;

  /// No description provided for @communityCloudLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the point cloud'**
  String get communityCloudLoadFailed;

  /// No description provided for @communityRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get communityRetry;

  /// No description provided for @communityFormatUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This format cannot be previewed in this version'**
  String get communityFormatUnsupported;

  /// No description provided for @communityPointsSuffix.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get communityPointsSuffix;

  /// No description provided for @meDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get meDeleteAccount;

  /// No description provided for @meDeleteAccountDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account?'**
  String get meDeleteAccountDialogTitle;

  /// No description provided for @meDeleteAccountDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Your account, published works and all cloud data will be permanently deleted. This cannot be undone. Captures stored on this device are not affected.'**
  String get meDeleteAccountDialogBody;

  /// No description provided for @meDeleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get meDeleteAccountConfirm;

  /// No description provided for @meDeleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Deletion failed. Please try again later.'**
  String get meDeleteAccountFailed;

  /// No description provided for @publishModerationUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get publishModerationUnderReview;

  /// No description provided for @publishModerationRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get publishModerationRemoved;

  /// No description provided for @publishModerationRemovedHint.
  ///
  /// In en, this message translates to:
  /// **'This work was removed for violating the community guidelines and is not visible to others. To appeal, use the contact details on the Settings page.'**
  String get publishModerationRemovedHint;

  /// No description provided for @workMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get workMoreActions;

  /// No description provided for @reportAction.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportAction;

  /// No description provided for @reportSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Report this work'**
  String get reportSheetTitle;

  /// No description provided for @reportSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a reason and we\'ll review it promptly.'**
  String get reportSheetSubtitle;

  /// No description provided for @reportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam or advertising'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment or bullying'**
  String get reportReasonHarassment;

  /// No description provided for @reportReasonHateSpeech.
  ///
  /// In en, this message translates to:
  /// **'Hate speech'**
  String get reportReasonHateSpeech;

  /// No description provided for @reportReasonSexualContent.
  ///
  /// In en, this message translates to:
  /// **'Sexual content'**
  String get reportReasonSexualContent;

  /// No description provided for @reportReasonViolence.
  ///
  /// In en, this message translates to:
  /// **'Violence or gore'**
  String get reportReasonViolence;

  /// No description provided for @reportReasonCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright infringement'**
  String get reportReasonCopyright;

  /// No description provided for @reportReasonMisinformation.
  ///
  /// In en, this message translates to:
  /// **'Misinformation'**
  String get reportReasonMisinformation;

  /// No description provided for @reportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportReasonOther;

  /// No description provided for @reportDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Additional details (optional)'**
  String get reportDetailHint;

  /// No description provided for @reportSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get reportSubmit;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted. We\'ll review it promptly.'**
  String get reportSubmitted;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t submit the report. Please try again later.'**
  String get reportFailed;

  /// No description provided for @blockAction.
  ///
  /// In en, this message translates to:
  /// **'Block this user'**
  String get blockAction;

  /// No description provided for @blockDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Block this user?'**
  String get blockDialogTitle;

  /// No description provided for @blockDialogBody.
  ///
  /// In en, this message translates to:
  /// **'You won\'t see their works anymore, and any follow relationship between you will be removed.'**
  String get blockDialogBody;

  /// No description provided for @blockConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockConfirm;

  /// No description provided for @blockDone.
  ///
  /// In en, this message translates to:
  /// **'Blocked. Their works will no longer appear.'**
  String get blockDone;

  /// No description provided for @blockFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed. Please try again later.'**
  String get blockFailed;

  /// No description provided for @workDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Remove from community'**
  String get workDeleteAction;

  /// No description provided for @workDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this work from the community?'**
  String get workDeleteDialogTitle;

  /// No description provided for @workDeleteDialogBody.
  ///
  /// In en, this message translates to:
  /// **'The work will be removed from the community and its cloud files deleted. This cannot be undone. Your original capture on this device is unaffected and can be published again later.'**
  String get workDeleteDialogBody;

  /// No description provided for @workDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get workDeleteConfirm;

  /// No description provided for @workDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'Removed from the community'**
  String get workDeleteDone;

  /// No description provided for @workDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Removal failed. Please try again later.'**
  String get workDeleteFailed;

  /// No description provided for @socialActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Action failed. Please try again later.'**
  String get socialActionFailed;

  /// No description provided for @socialFollowingTitle.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get socialFollowingTitle;

  /// No description provided for @socialFollowingLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your following list'**
  String get socialFollowingLoadFailed;

  /// No description provided for @socialFollowingEmpty.
  ///
  /// In en, this message translates to:
  /// **'You aren\'t following anyone yet'**
  String get socialFollowingEmpty;

  /// No description provided for @socialFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get socialFollow;

  /// No description provided for @socialFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get socialFollowing;

  /// No description provided for @meDownloadIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Download incomplete. Try again later.'**
  String get meDownloadIncomplete;

  /// No description provided for @meWorkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open this work. Try again later.'**
  String get meWorkOpenFailed;

  /// No description provided for @meProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'My profile'**
  String get meProfileTitle;

  /// No description provided for @socialLikesReceived.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get socialLikesReceived;

  /// No description provided for @socialWorks.
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get socialWorks;

  /// No description provided for @socialFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get socialFollowers;

  /// No description provided for @profileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this profile'**
  String get profileLoadFailed;

  /// No description provided for @profileBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get profileBack;

  /// No description provided for @profileMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get profileMore;

  /// No description provided for @profileReportUser.
  ///
  /// In en, this message translates to:
  /// **'Report this user'**
  String get profileReportUser;

  /// No description provided for @profileBlockUser.
  ///
  /// In en, this message translates to:
  /// **'Block this user'**
  String get profileBlockUser;

  /// No description provided for @profileBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Block this user?'**
  String get profileBlockTitle;

  /// No description provided for @profileBlockBody.
  ///
  /// In en, this message translates to:
  /// **'While signed in to PocketWorld with this account, you won\'t see this person in Community, search, following lists, or profiles. Any follow relationship between you will be removed and neither account can follow the other. They won\'t be notified. Public links, signed-out visitors, or other accounts may still see their public content.'**
  String get profileBlockBody;

  /// No description provided for @profileBlockConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get profileBlockConfirm;

  /// No description provided for @profileBlockFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t block this user. Please try again later.'**
  String get profileBlockFailed;

  /// No description provided for @reportUserTitle.
  ///
  /// In en, this message translates to:
  /// **'Report this user'**
  String get reportUserTitle;

  /// No description provided for @reportTierTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose report type'**
  String get reportTierTitle;

  /// No description provided for @reportReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a reason'**
  String get reportReasonTitle;

  /// No description provided for @reportStandardTitle.
  ///
  /// In en, this message translates to:
  /// **'Standard report'**
  String get reportStandardTitle;

  /// No description provided for @reportStandardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Harassment, fraud, harmful content, or another community issue'**
  String get reportStandardSubtitle;

  /// No description provided for @reportRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rights complaint'**
  String get reportRightsTitle;

  /// No description provided for @reportRightsEntry.
  ///
  /// In en, this message translates to:
  /// **'Infringes rights'**
  String get reportRightsEntry;

  /// No description provided for @reportRightsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Impersonation, privacy, portrait, or intellectual-property concerns'**
  String get reportRightsSubtitle;

  /// No description provided for @reportStandardDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Describe whether the issue appears on the front, back, top, or another view'**
  String get reportStandardDetailHint;

  /// No description provided for @reportRightsDetailHint.
  ///
  /// In en, this message translates to:
  /// **'Describe ownership, where the infringement appears, and the requested action'**
  String get reportRightsDetailHint;

  /// No description provided for @reportEvidenceType.
  ///
  /// In en, this message translates to:
  /// **'Evidence type'**
  String get reportEvidenceType;

  /// No description provided for @reportEvidenceContext.
  ///
  /// In en, this message translates to:
  /// **'Issue screenshot'**
  String get reportEvidenceContext;

  /// No description provided for @reportEvidenceIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity evidence'**
  String get reportEvidenceIdentity;

  /// No description provided for @reportEvidenceOwnership.
  ///
  /// In en, this message translates to:
  /// **'Ownership evidence'**
  String get reportEvidenceOwnership;

  /// No description provided for @reportEvidenceAuthorization.
  ///
  /// In en, this message translates to:
  /// **'Authorization evidence'**
  String get reportEvidenceAuthorization;

  /// No description provided for @reportEvidenceOther.
  ///
  /// In en, this message translates to:
  /// **'Other evidence'**
  String get reportEvidenceOther;

  /// No description provided for @reportEvidenceOptional.
  ///
  /// In en, this message translates to:
  /// **'Supporting screenshots (optional)'**
  String get reportEvidenceOptional;

  /// No description provided for @reportEvidenceLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Up to 3 JPG or PNG images. Location and other metadata are removed before upload.'**
  String get reportEvidenceLimitHint;

  /// No description provided for @reportHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get reportHistoryTitle;

  /// No description provided for @reportHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t submitted any reports'**
  String get reportHistoryEmpty;

  /// No description provided for @reportHistoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load report history'**
  String get reportHistoryLoadFailed;

  /// No description provided for @reportHistorySource.
  ///
  /// In en, this message translates to:
  /// **'Related work: {title}'**
  String reportHistorySource(String title);

  /// No description provided for @reportStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get reportStatusPending;

  /// No description provided for @reportStatusInReview.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get reportStatusInReview;

  /// No description provided for @reportStatusNeedsInfo.
  ///
  /// In en, this message translates to:
  /// **'More information needed'**
  String get reportStatusNeedsInfo;

  /// No description provided for @reportStatusActioned.
  ///
  /// In en, this message translates to:
  /// **'Action taken'**
  String get reportStatusActioned;

  /// No description provided for @reportStatusDismissed.
  ///
  /// In en, this message translates to:
  /// **'No violation found'**
  String get reportStatusDismissed;

  /// No description provided for @reportAdditionalInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Additional information'**
  String get reportAdditionalInfoTitle;

  /// No description provided for @reportImageProcessFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t process that image. Choose a JPG or PNG.'**
  String get reportImageProcessFailed;

  /// No description provided for @reportUserSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted'**
  String get reportUserSubmitted;

  /// No description provided for @reportSubmittedPartial.
  ///
  /// In en, this message translates to:
  /// **'Report submitted, but some images weren\'t uploaded'**
  String get reportSubmittedPartial;

  /// No description provided for @reportDetailUserHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what happened (optional)'**
  String get reportDetailUserHint;

  /// No description provided for @reportSourceWork.
  ///
  /// In en, this message translates to:
  /// **'Related work: {workId}'**
  String reportSourceWork(String workId);

  /// No description provided for @reportAddEvidence.
  ///
  /// In en, this message translates to:
  /// **'Add screenshots or photos (up to 3)'**
  String get reportAddEvidence;

  /// No description provided for @reportSensitiveEvidenceWarning.
  ///
  /// In en, this message translates to:
  /// **'Don\'t re-upload or redistribute sensitive material. The platform will preserve linked in-app content for review.'**
  String get reportSensitiveEvidenceWarning;

  /// No description provided for @reportSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get reportSubmitting;

  /// No description provided for @reportSubmitUser.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get reportSubmitUser;

  /// No description provided for @reportReasonImpersonation.
  ///
  /// In en, this message translates to:
  /// **'Impersonation or false account information'**
  String get reportReasonImpersonation;

  /// No description provided for @reportReasonHarassmentThreat.
  ///
  /// In en, this message translates to:
  /// **'Harassment, bullying, or threats'**
  String get reportReasonHarassmentThreat;

  /// No description provided for @reportReasonSpamFraud.
  ///
  /// In en, this message translates to:
  /// **'Fraud, spam, or suspicious account activity'**
  String get reportReasonSpamFraud;

  /// No description provided for @reportReasonMinorSafety.
  ///
  /// In en, this message translates to:
  /// **'Minor safety'**
  String get reportReasonMinorSafety;

  /// No description provided for @reportReasonSexualLowQuality.
  ///
  /// In en, this message translates to:
  /// **'Sexual or explicit content'**
  String get reportReasonSexualLowQuality;

  /// No description provided for @reportReasonViolenceIllegal.
  ///
  /// In en, this message translates to:
  /// **'Violence, self-harm, hate, extremism, or other illegal harmful content'**
  String get reportReasonViolenceIllegal;

  /// No description provided for @reportReasonMisleading.
  ///
  /// In en, this message translates to:
  /// **'False or misleading information'**
  String get reportReasonMisleading;

  /// No description provided for @reportReasonPrivacyIp.
  ///
  /// In en, this message translates to:
  /// **'Privacy, doxxing, portrait, or intellectual property'**
  String get reportReasonPrivacyIp;

  /// No description provided for @reportReasonOtherUncertain.
  ///
  /// In en, this message translates to:
  /// **'Other / not sure'**
  String get reportReasonOtherUncertain;

  /// No description provided for @blockedUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get blockedUsersTitle;

  /// No description provided for @blockedUsersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load blocked users'**
  String get blockedUsersLoadFailed;

  /// No description provided for @blockedUsersEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t blocked anyone'**
  String get blockedUsersEmpty;

  /// No description provided for @unblockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unblock this user?'**
  String get unblockTitle;

  /// No description provided for @unblockBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be able to see their public content again. Previous follow relationships won\'t be restored automatically.'**
  String get unblockBody;

  /// No description provided for @unblockAction.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockAction;

  /// No description provided for @unblockFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t unblock this user. Please try again later.'**
  String get unblockFailed;

  /// No description provided for @meBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get meBlockedUsers;

  /// No description provided for @meSocialLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load social profile'**
  String get meSocialLoadFailed;

  /// No description provided for @etaCountdown.
  ///
  /// In en, this message translates to:
  /// **'Estimated time remaining · {time}'**
  String etaCountdown(String time);

  /// No description provided for @etaSparseCountdown.
  ///
  /// In en, this message translates to:
  /// **'Sparse stage estimated time remaining · {time}'**
  String etaSparseCountdown(String time);

  /// No description provided for @etaSparseCalculating.
  ///
  /// In en, this message translates to:
  /// **'Estimating sparse stage…'**
  String get etaSparseCalculating;

  /// No description provided for @etaDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {n} min'**
  String etaDurationMinutes(int n);

  /// No description provided for @etaDurationUnderMinute.
  ///
  /// In en, this message translates to:
  /// **'Within 1 min'**
  String get etaDurationUnderMinute;

  /// No description provided for @phoneSignUpWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Sign up with phone'**
  String get phoneSignUpWithPhone;

  /// No description provided for @phoneCountrySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search country, region or calling code'**
  String get phoneCountrySearchHint;

  /// No description provided for @phoneCountryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching regions'**
  String get phoneCountryNoMatches;

  /// No description provided for @phoneMobileFormatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Mobile number format is unavailable for this region'**
  String get phoneMobileFormatUnavailable;

  /// No description provided for @phoneMobileExample.
  ///
  /// In en, this message translates to:
  /// **'Mobile number example: {number}'**
  String phoneMobileExample(String number);

  /// No description provided for @phoneOverseasSignupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'SMS verification is not yet available for overseas numbers. You can sign up with email.'**
  String get phoneOverseasSignupUnavailable;

  /// No description provided for @phoneLoginHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter 11 digits for mainland China; include the calling code for overseas numbers. Overseas SMS is not available yet. You can sign up or sign in with email.'**
  String get phoneLoginHelp;

  /// No description provided for @phoneCountryCallingCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'{country} +{callingCode}'**
  String phoneCountryCallingCodeLabel(String country, String callingCode);

  /// No description provided for @phoneCountryAC.
  ///
  /// In en, this message translates to:
  /// **'Ascension Island'**
  String get phoneCountryAC;

  /// No description provided for @phoneCountryAD.
  ///
  /// In en, this message translates to:
  /// **'Andorra'**
  String get phoneCountryAD;

  /// No description provided for @phoneCountryAE.
  ///
  /// In en, this message translates to:
  /// **'United Arab Emirates'**
  String get phoneCountryAE;

  /// No description provided for @phoneCountryAF.
  ///
  /// In en, this message translates to:
  /// **'Afghanistan'**
  String get phoneCountryAF;

  /// No description provided for @phoneCountryAG.
  ///
  /// In en, this message translates to:
  /// **'Antigua & Barbuda'**
  String get phoneCountryAG;

  /// No description provided for @phoneCountryAI.
  ///
  /// In en, this message translates to:
  /// **'Anguilla'**
  String get phoneCountryAI;

  /// No description provided for @phoneCountryAL.
  ///
  /// In en, this message translates to:
  /// **'Albania'**
  String get phoneCountryAL;

  /// No description provided for @phoneCountryAM.
  ///
  /// In en, this message translates to:
  /// **'Armenia'**
  String get phoneCountryAM;

  /// No description provided for @phoneCountryAO.
  ///
  /// In en, this message translates to:
  /// **'Angola'**
  String get phoneCountryAO;

  /// No description provided for @phoneCountryAR.
  ///
  /// In en, this message translates to:
  /// **'Argentina'**
  String get phoneCountryAR;

  /// No description provided for @phoneCountryAS.
  ///
  /// In en, this message translates to:
  /// **'American Samoa'**
  String get phoneCountryAS;

  /// No description provided for @phoneCountryAT.
  ///
  /// In en, this message translates to:
  /// **'Austria'**
  String get phoneCountryAT;

  /// No description provided for @phoneCountryAU.
  ///
  /// In en, this message translates to:
  /// **'Australia'**
  String get phoneCountryAU;

  /// No description provided for @phoneCountryAW.
  ///
  /// In en, this message translates to:
  /// **'Aruba'**
  String get phoneCountryAW;

  /// No description provided for @phoneCountryAX.
  ///
  /// In en, this message translates to:
  /// **'Åland Islands'**
  String get phoneCountryAX;

  /// No description provided for @phoneCountryAZ.
  ///
  /// In en, this message translates to:
  /// **'Azerbaijan'**
  String get phoneCountryAZ;

  /// No description provided for @phoneCountryBA.
  ///
  /// In en, this message translates to:
  /// **'Bosnia & Herzegovina'**
  String get phoneCountryBA;

  /// No description provided for @phoneCountryBB.
  ///
  /// In en, this message translates to:
  /// **'Barbados'**
  String get phoneCountryBB;

  /// No description provided for @phoneCountryBD.
  ///
  /// In en, this message translates to:
  /// **'Bangladesh'**
  String get phoneCountryBD;

  /// No description provided for @phoneCountryBE.
  ///
  /// In en, this message translates to:
  /// **'Belgium'**
  String get phoneCountryBE;

  /// No description provided for @phoneCountryBF.
  ///
  /// In en, this message translates to:
  /// **'Burkina Faso'**
  String get phoneCountryBF;

  /// No description provided for @phoneCountryBG.
  ///
  /// In en, this message translates to:
  /// **'Bulgaria'**
  String get phoneCountryBG;

  /// No description provided for @phoneCountryBH.
  ///
  /// In en, this message translates to:
  /// **'Bahrain'**
  String get phoneCountryBH;

  /// No description provided for @phoneCountryBI.
  ///
  /// In en, this message translates to:
  /// **'Burundi'**
  String get phoneCountryBI;

  /// No description provided for @phoneCountryBJ.
  ///
  /// In en, this message translates to:
  /// **'Benin'**
  String get phoneCountryBJ;

  /// No description provided for @phoneCountryBL.
  ///
  /// In en, this message translates to:
  /// **'St. Barthélemy'**
  String get phoneCountryBL;

  /// No description provided for @phoneCountryBM.
  ///
  /// In en, this message translates to:
  /// **'Bermuda'**
  String get phoneCountryBM;

  /// No description provided for @phoneCountryBN.
  ///
  /// In en, this message translates to:
  /// **'Brunei'**
  String get phoneCountryBN;

  /// No description provided for @phoneCountryBO.
  ///
  /// In en, this message translates to:
  /// **'Bolivia'**
  String get phoneCountryBO;

  /// No description provided for @phoneCountryBQ.
  ///
  /// In en, this message translates to:
  /// **'Caribbean Netherlands'**
  String get phoneCountryBQ;

  /// No description provided for @phoneCountryBR.
  ///
  /// In en, this message translates to:
  /// **'Brazil'**
  String get phoneCountryBR;

  /// No description provided for @phoneCountryBS.
  ///
  /// In en, this message translates to:
  /// **'Bahamas'**
  String get phoneCountryBS;

  /// No description provided for @phoneCountryBT.
  ///
  /// In en, this message translates to:
  /// **'Bhutan'**
  String get phoneCountryBT;

  /// No description provided for @phoneCountryBW.
  ///
  /// In en, this message translates to:
  /// **'Botswana'**
  String get phoneCountryBW;

  /// No description provided for @phoneCountryBY.
  ///
  /// In en, this message translates to:
  /// **'Belarus'**
  String get phoneCountryBY;

  /// No description provided for @phoneCountryBZ.
  ///
  /// In en, this message translates to:
  /// **'Belize'**
  String get phoneCountryBZ;

  /// No description provided for @phoneCountryCA.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get phoneCountryCA;

  /// No description provided for @phoneCountryCC.
  ///
  /// In en, this message translates to:
  /// **'Cocos (Keeling) Islands'**
  String get phoneCountryCC;

  /// No description provided for @phoneCountryCD.
  ///
  /// In en, this message translates to:
  /// **'Congo - Kinshasa'**
  String get phoneCountryCD;

  /// No description provided for @phoneCountryCF.
  ///
  /// In en, this message translates to:
  /// **'Central African Republic'**
  String get phoneCountryCF;

  /// No description provided for @phoneCountryCG.
  ///
  /// In en, this message translates to:
  /// **'Congo - Brazzaville'**
  String get phoneCountryCG;

  /// No description provided for @phoneCountryCH.
  ///
  /// In en, this message translates to:
  /// **'Switzerland'**
  String get phoneCountryCH;

  /// No description provided for @phoneCountryCI.
  ///
  /// In en, this message translates to:
  /// **'Côte d’Ivoire'**
  String get phoneCountryCI;

  /// No description provided for @phoneCountryCK.
  ///
  /// In en, this message translates to:
  /// **'Cook Islands'**
  String get phoneCountryCK;

  /// No description provided for @phoneCountryCL.
  ///
  /// In en, this message translates to:
  /// **'Chile'**
  String get phoneCountryCL;

  /// No description provided for @phoneCountryCM.
  ///
  /// In en, this message translates to:
  /// **'Cameroon'**
  String get phoneCountryCM;

  /// No description provided for @phoneCountryCN.
  ///
  /// In en, this message translates to:
  /// **'China mainland'**
  String get phoneCountryCN;

  /// No description provided for @phoneCountryCO.
  ///
  /// In en, this message translates to:
  /// **'Colombia'**
  String get phoneCountryCO;

  /// No description provided for @phoneCountryCR.
  ///
  /// In en, this message translates to:
  /// **'Costa Rica'**
  String get phoneCountryCR;

  /// No description provided for @phoneCountryCU.
  ///
  /// In en, this message translates to:
  /// **'Cuba'**
  String get phoneCountryCU;

  /// No description provided for @phoneCountryCV.
  ///
  /// In en, this message translates to:
  /// **'Cape Verde'**
  String get phoneCountryCV;

  /// No description provided for @phoneCountryCW.
  ///
  /// In en, this message translates to:
  /// **'Curaçao'**
  String get phoneCountryCW;

  /// No description provided for @phoneCountryCX.
  ///
  /// In en, this message translates to:
  /// **'Christmas Island'**
  String get phoneCountryCX;

  /// No description provided for @phoneCountryCY.
  ///
  /// In en, this message translates to:
  /// **'Cyprus'**
  String get phoneCountryCY;

  /// No description provided for @phoneCountryCZ.
  ///
  /// In en, this message translates to:
  /// **'Czechia'**
  String get phoneCountryCZ;

  /// No description provided for @phoneCountryDE.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get phoneCountryDE;

  /// No description provided for @phoneCountryDJ.
  ///
  /// In en, this message translates to:
  /// **'Djibouti'**
  String get phoneCountryDJ;

  /// No description provided for @phoneCountryDK.
  ///
  /// In en, this message translates to:
  /// **'Denmark'**
  String get phoneCountryDK;

  /// No description provided for @phoneCountryDM.
  ///
  /// In en, this message translates to:
  /// **'Dominica'**
  String get phoneCountryDM;

  /// No description provided for @phoneCountryDO.
  ///
  /// In en, this message translates to:
  /// **'Dominican Republic'**
  String get phoneCountryDO;

  /// No description provided for @phoneCountryDZ.
  ///
  /// In en, this message translates to:
  /// **'Algeria'**
  String get phoneCountryDZ;

  /// No description provided for @phoneCountryEC.
  ///
  /// In en, this message translates to:
  /// **'Ecuador'**
  String get phoneCountryEC;

  /// No description provided for @phoneCountryEE.
  ///
  /// In en, this message translates to:
  /// **'Estonia'**
  String get phoneCountryEE;

  /// No description provided for @phoneCountryEG.
  ///
  /// In en, this message translates to:
  /// **'Egypt'**
  String get phoneCountryEG;

  /// No description provided for @phoneCountryEH.
  ///
  /// In en, this message translates to:
  /// **'Western Sahara'**
  String get phoneCountryEH;

  /// No description provided for @phoneCountryER.
  ///
  /// In en, this message translates to:
  /// **'Eritrea'**
  String get phoneCountryER;

  /// No description provided for @phoneCountryES.
  ///
  /// In en, this message translates to:
  /// **'Spain'**
  String get phoneCountryES;

  /// No description provided for @phoneCountryET.
  ///
  /// In en, this message translates to:
  /// **'Ethiopia'**
  String get phoneCountryET;

  /// No description provided for @phoneCountryFI.
  ///
  /// In en, this message translates to:
  /// **'Finland'**
  String get phoneCountryFI;

  /// No description provided for @phoneCountryFJ.
  ///
  /// In en, this message translates to:
  /// **'Fiji'**
  String get phoneCountryFJ;

  /// No description provided for @phoneCountryFK.
  ///
  /// In en, this message translates to:
  /// **'Falkland Islands'**
  String get phoneCountryFK;

  /// No description provided for @phoneCountryFM.
  ///
  /// In en, this message translates to:
  /// **'Micronesia'**
  String get phoneCountryFM;

  /// No description provided for @phoneCountryFO.
  ///
  /// In en, this message translates to:
  /// **'Faroe Islands'**
  String get phoneCountryFO;

  /// No description provided for @phoneCountryFR.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get phoneCountryFR;

  /// No description provided for @phoneCountryGA.
  ///
  /// In en, this message translates to:
  /// **'Gabon'**
  String get phoneCountryGA;

  /// No description provided for @phoneCountryGB.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get phoneCountryGB;

  /// No description provided for @phoneCountryGD.
  ///
  /// In en, this message translates to:
  /// **'Grenada'**
  String get phoneCountryGD;

  /// No description provided for @phoneCountryGE.
  ///
  /// In en, this message translates to:
  /// **'Georgia'**
  String get phoneCountryGE;

  /// No description provided for @phoneCountryGF.
  ///
  /// In en, this message translates to:
  /// **'French Guiana'**
  String get phoneCountryGF;

  /// No description provided for @phoneCountryGG.
  ///
  /// In en, this message translates to:
  /// **'Guernsey'**
  String get phoneCountryGG;

  /// No description provided for @phoneCountryGH.
  ///
  /// In en, this message translates to:
  /// **'Ghana'**
  String get phoneCountryGH;

  /// No description provided for @phoneCountryGI.
  ///
  /// In en, this message translates to:
  /// **'Gibraltar'**
  String get phoneCountryGI;

  /// No description provided for @phoneCountryGL.
  ///
  /// In en, this message translates to:
  /// **'Greenland'**
  String get phoneCountryGL;

  /// No description provided for @phoneCountryGM.
  ///
  /// In en, this message translates to:
  /// **'Gambia'**
  String get phoneCountryGM;

  /// No description provided for @phoneCountryGN.
  ///
  /// In en, this message translates to:
  /// **'Guinea'**
  String get phoneCountryGN;

  /// No description provided for @phoneCountryGP.
  ///
  /// In en, this message translates to:
  /// **'Guadeloupe'**
  String get phoneCountryGP;

  /// No description provided for @phoneCountryGQ.
  ///
  /// In en, this message translates to:
  /// **'Equatorial Guinea'**
  String get phoneCountryGQ;

  /// No description provided for @phoneCountryGR.
  ///
  /// In en, this message translates to:
  /// **'Greece'**
  String get phoneCountryGR;

  /// No description provided for @phoneCountryGT.
  ///
  /// In en, this message translates to:
  /// **'Guatemala'**
  String get phoneCountryGT;

  /// No description provided for @phoneCountryGU.
  ///
  /// In en, this message translates to:
  /// **'Guam'**
  String get phoneCountryGU;

  /// No description provided for @phoneCountryGW.
  ///
  /// In en, this message translates to:
  /// **'Guinea-Bissau'**
  String get phoneCountryGW;

  /// No description provided for @phoneCountryGY.
  ///
  /// In en, this message translates to:
  /// **'Guyana'**
  String get phoneCountryGY;

  /// No description provided for @phoneCountryHK.
  ///
  /// In en, this message translates to:
  /// **'Hong Kong'**
  String get phoneCountryHK;

  /// No description provided for @phoneCountryHN.
  ///
  /// In en, this message translates to:
  /// **'Honduras'**
  String get phoneCountryHN;

  /// No description provided for @phoneCountryHR.
  ///
  /// In en, this message translates to:
  /// **'Croatia'**
  String get phoneCountryHR;

  /// No description provided for @phoneCountryHT.
  ///
  /// In en, this message translates to:
  /// **'Haiti'**
  String get phoneCountryHT;

  /// No description provided for @phoneCountryHU.
  ///
  /// In en, this message translates to:
  /// **'Hungary'**
  String get phoneCountryHU;

  /// No description provided for @phoneCountryID.
  ///
  /// In en, this message translates to:
  /// **'Indonesia'**
  String get phoneCountryID;

  /// No description provided for @phoneCountryIE.
  ///
  /// In en, this message translates to:
  /// **'Ireland'**
  String get phoneCountryIE;

  /// No description provided for @phoneCountryIL.
  ///
  /// In en, this message translates to:
  /// **'Israel'**
  String get phoneCountryIL;

  /// No description provided for @phoneCountryIM.
  ///
  /// In en, this message translates to:
  /// **'Isle of Man'**
  String get phoneCountryIM;

  /// No description provided for @phoneCountryIN.
  ///
  /// In en, this message translates to:
  /// **'India'**
  String get phoneCountryIN;

  /// No description provided for @phoneCountryIO.
  ///
  /// In en, this message translates to:
  /// **'Chagos Archipelago'**
  String get phoneCountryIO;

  /// No description provided for @phoneCountryIQ.
  ///
  /// In en, this message translates to:
  /// **'Iraq'**
  String get phoneCountryIQ;

  /// No description provided for @phoneCountryIR.
  ///
  /// In en, this message translates to:
  /// **'Iran'**
  String get phoneCountryIR;

  /// No description provided for @phoneCountryIS.
  ///
  /// In en, this message translates to:
  /// **'Iceland'**
  String get phoneCountryIS;

  /// No description provided for @phoneCountryIT.
  ///
  /// In en, this message translates to:
  /// **'Italy'**
  String get phoneCountryIT;

  /// No description provided for @phoneCountryJE.
  ///
  /// In en, this message translates to:
  /// **'Jersey'**
  String get phoneCountryJE;

  /// No description provided for @phoneCountryJM.
  ///
  /// In en, this message translates to:
  /// **'Jamaica'**
  String get phoneCountryJM;

  /// No description provided for @phoneCountryJO.
  ///
  /// In en, this message translates to:
  /// **'Jordan'**
  String get phoneCountryJO;

  /// No description provided for @phoneCountryJP.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get phoneCountryJP;

  /// No description provided for @phoneCountryKE.
  ///
  /// In en, this message translates to:
  /// **'Kenya'**
  String get phoneCountryKE;

  /// No description provided for @phoneCountryKG.
  ///
  /// In en, this message translates to:
  /// **'Kyrgyzstan'**
  String get phoneCountryKG;

  /// No description provided for @phoneCountryKH.
  ///
  /// In en, this message translates to:
  /// **'Cambodia'**
  String get phoneCountryKH;

  /// No description provided for @phoneCountryKI.
  ///
  /// In en, this message translates to:
  /// **'Kiribati'**
  String get phoneCountryKI;

  /// No description provided for @phoneCountryKM.
  ///
  /// In en, this message translates to:
  /// **'Comoros'**
  String get phoneCountryKM;

  /// No description provided for @phoneCountryKN.
  ///
  /// In en, this message translates to:
  /// **'St. Kitts & Nevis'**
  String get phoneCountryKN;

  /// No description provided for @phoneCountryKP.
  ///
  /// In en, this message translates to:
  /// **'North Korea'**
  String get phoneCountryKP;

  /// No description provided for @phoneCountryKR.
  ///
  /// In en, this message translates to:
  /// **'South Korea'**
  String get phoneCountryKR;

  /// No description provided for @phoneCountryKW.
  ///
  /// In en, this message translates to:
  /// **'Kuwait'**
  String get phoneCountryKW;

  /// No description provided for @phoneCountryKY.
  ///
  /// In en, this message translates to:
  /// **'Cayman Islands'**
  String get phoneCountryKY;

  /// No description provided for @phoneCountryKZ.
  ///
  /// In en, this message translates to:
  /// **'Kazakhstan'**
  String get phoneCountryKZ;

  /// No description provided for @phoneCountryLA.
  ///
  /// In en, this message translates to:
  /// **'Laos'**
  String get phoneCountryLA;

  /// No description provided for @phoneCountryLB.
  ///
  /// In en, this message translates to:
  /// **'Lebanon'**
  String get phoneCountryLB;

  /// No description provided for @phoneCountryLC.
  ///
  /// In en, this message translates to:
  /// **'St. Lucia'**
  String get phoneCountryLC;

  /// No description provided for @phoneCountryLI.
  ///
  /// In en, this message translates to:
  /// **'Liechtenstein'**
  String get phoneCountryLI;

  /// No description provided for @phoneCountryLK.
  ///
  /// In en, this message translates to:
  /// **'Sri Lanka'**
  String get phoneCountryLK;

  /// No description provided for @phoneCountryLR.
  ///
  /// In en, this message translates to:
  /// **'Liberia'**
  String get phoneCountryLR;

  /// No description provided for @phoneCountryLS.
  ///
  /// In en, this message translates to:
  /// **'Lesotho'**
  String get phoneCountryLS;

  /// No description provided for @phoneCountryLT.
  ///
  /// In en, this message translates to:
  /// **'Lithuania'**
  String get phoneCountryLT;

  /// No description provided for @phoneCountryLU.
  ///
  /// In en, this message translates to:
  /// **'Luxembourg'**
  String get phoneCountryLU;

  /// No description provided for @phoneCountryLV.
  ///
  /// In en, this message translates to:
  /// **'Latvia'**
  String get phoneCountryLV;

  /// No description provided for @phoneCountryLY.
  ///
  /// In en, this message translates to:
  /// **'Libya'**
  String get phoneCountryLY;

  /// No description provided for @phoneCountryMA.
  ///
  /// In en, this message translates to:
  /// **'Morocco'**
  String get phoneCountryMA;

  /// No description provided for @phoneCountryMC.
  ///
  /// In en, this message translates to:
  /// **'Monaco'**
  String get phoneCountryMC;

  /// No description provided for @phoneCountryMD.
  ///
  /// In en, this message translates to:
  /// **'Moldova'**
  String get phoneCountryMD;

  /// No description provided for @phoneCountryME.
  ///
  /// In en, this message translates to:
  /// **'Montenegro'**
  String get phoneCountryME;

  /// No description provided for @phoneCountryMF.
  ///
  /// In en, this message translates to:
  /// **'St. Martin'**
  String get phoneCountryMF;

  /// No description provided for @phoneCountryMG.
  ///
  /// In en, this message translates to:
  /// **'Madagascar'**
  String get phoneCountryMG;

  /// No description provided for @phoneCountryMH.
  ///
  /// In en, this message translates to:
  /// **'Marshall Islands'**
  String get phoneCountryMH;

  /// No description provided for @phoneCountryMK.
  ///
  /// In en, this message translates to:
  /// **'North Macedonia'**
  String get phoneCountryMK;

  /// No description provided for @phoneCountryML.
  ///
  /// In en, this message translates to:
  /// **'Mali'**
  String get phoneCountryML;

  /// No description provided for @phoneCountryMM.
  ///
  /// In en, this message translates to:
  /// **'Myanmar (Burma)'**
  String get phoneCountryMM;

  /// No description provided for @phoneCountryMN.
  ///
  /// In en, this message translates to:
  /// **'Mongolia'**
  String get phoneCountryMN;

  /// No description provided for @phoneCountryMO.
  ///
  /// In en, this message translates to:
  /// **'Macao'**
  String get phoneCountryMO;

  /// No description provided for @phoneCountryMP.
  ///
  /// In en, this message translates to:
  /// **'Northern Mariana Islands'**
  String get phoneCountryMP;

  /// No description provided for @phoneCountryMQ.
  ///
  /// In en, this message translates to:
  /// **'Martinique'**
  String get phoneCountryMQ;

  /// No description provided for @phoneCountryMR.
  ///
  /// In en, this message translates to:
  /// **'Mauritania'**
  String get phoneCountryMR;

  /// No description provided for @phoneCountryMS.
  ///
  /// In en, this message translates to:
  /// **'Montserrat'**
  String get phoneCountryMS;

  /// No description provided for @phoneCountryMT.
  ///
  /// In en, this message translates to:
  /// **'Malta'**
  String get phoneCountryMT;

  /// No description provided for @phoneCountryMU.
  ///
  /// In en, this message translates to:
  /// **'Mauritius'**
  String get phoneCountryMU;

  /// No description provided for @phoneCountryMV.
  ///
  /// In en, this message translates to:
  /// **'Maldives'**
  String get phoneCountryMV;

  /// No description provided for @phoneCountryMW.
  ///
  /// In en, this message translates to:
  /// **'Malawi'**
  String get phoneCountryMW;

  /// No description provided for @phoneCountryMX.
  ///
  /// In en, this message translates to:
  /// **'Mexico'**
  String get phoneCountryMX;

  /// No description provided for @phoneCountryMY.
  ///
  /// In en, this message translates to:
  /// **'Malaysia'**
  String get phoneCountryMY;

  /// No description provided for @phoneCountryMZ.
  ///
  /// In en, this message translates to:
  /// **'Mozambique'**
  String get phoneCountryMZ;

  /// No description provided for @phoneCountryNA.
  ///
  /// In en, this message translates to:
  /// **'Namibia'**
  String get phoneCountryNA;

  /// No description provided for @phoneCountryNC.
  ///
  /// In en, this message translates to:
  /// **'New Caledonia'**
  String get phoneCountryNC;

  /// No description provided for @phoneCountryNE.
  ///
  /// In en, this message translates to:
  /// **'Niger'**
  String get phoneCountryNE;

  /// No description provided for @phoneCountryNF.
  ///
  /// In en, this message translates to:
  /// **'Norfolk Island'**
  String get phoneCountryNF;

  /// No description provided for @phoneCountryNG.
  ///
  /// In en, this message translates to:
  /// **'Nigeria'**
  String get phoneCountryNG;

  /// No description provided for @phoneCountryNI.
  ///
  /// In en, this message translates to:
  /// **'Nicaragua'**
  String get phoneCountryNI;

  /// No description provided for @phoneCountryNL.
  ///
  /// In en, this message translates to:
  /// **'Netherlands'**
  String get phoneCountryNL;

  /// No description provided for @phoneCountryNO.
  ///
  /// In en, this message translates to:
  /// **'Norway'**
  String get phoneCountryNO;

  /// No description provided for @phoneCountryNP.
  ///
  /// In en, this message translates to:
  /// **'Nepal'**
  String get phoneCountryNP;

  /// No description provided for @phoneCountryNR.
  ///
  /// In en, this message translates to:
  /// **'Nauru'**
  String get phoneCountryNR;

  /// No description provided for @phoneCountryNU.
  ///
  /// In en, this message translates to:
  /// **'Niue'**
  String get phoneCountryNU;

  /// No description provided for @phoneCountryNZ.
  ///
  /// In en, this message translates to:
  /// **'New Zealand'**
  String get phoneCountryNZ;

  /// No description provided for @phoneCountryOM.
  ///
  /// In en, this message translates to:
  /// **'Oman'**
  String get phoneCountryOM;

  /// No description provided for @phoneCountryPA.
  ///
  /// In en, this message translates to:
  /// **'Panama'**
  String get phoneCountryPA;

  /// No description provided for @phoneCountryPE.
  ///
  /// In en, this message translates to:
  /// **'Peru'**
  String get phoneCountryPE;

  /// No description provided for @phoneCountryPF.
  ///
  /// In en, this message translates to:
  /// **'French Polynesia'**
  String get phoneCountryPF;

  /// No description provided for @phoneCountryPG.
  ///
  /// In en, this message translates to:
  /// **'Papua New Guinea'**
  String get phoneCountryPG;

  /// No description provided for @phoneCountryPH.
  ///
  /// In en, this message translates to:
  /// **'Philippines'**
  String get phoneCountryPH;

  /// No description provided for @phoneCountryPK.
  ///
  /// In en, this message translates to:
  /// **'Pakistan'**
  String get phoneCountryPK;

  /// No description provided for @phoneCountryPL.
  ///
  /// In en, this message translates to:
  /// **'Poland'**
  String get phoneCountryPL;

  /// No description provided for @phoneCountryPM.
  ///
  /// In en, this message translates to:
  /// **'St. Pierre & Miquelon'**
  String get phoneCountryPM;

  /// No description provided for @phoneCountryPR.
  ///
  /// In en, this message translates to:
  /// **'Puerto Rico'**
  String get phoneCountryPR;

  /// No description provided for @phoneCountryPS.
  ///
  /// In en, this message translates to:
  /// **'Palestinian Territories'**
  String get phoneCountryPS;

  /// No description provided for @phoneCountryPT.
  ///
  /// In en, this message translates to:
  /// **'Portugal'**
  String get phoneCountryPT;

  /// No description provided for @phoneCountryPW.
  ///
  /// In en, this message translates to:
  /// **'Palau'**
  String get phoneCountryPW;

  /// No description provided for @phoneCountryPY.
  ///
  /// In en, this message translates to:
  /// **'Paraguay'**
  String get phoneCountryPY;

  /// No description provided for @phoneCountryQA.
  ///
  /// In en, this message translates to:
  /// **'Qatar'**
  String get phoneCountryQA;

  /// No description provided for @phoneCountryRE.
  ///
  /// In en, this message translates to:
  /// **'Réunion'**
  String get phoneCountryRE;

  /// No description provided for @phoneCountryRO.
  ///
  /// In en, this message translates to:
  /// **'Romania'**
  String get phoneCountryRO;

  /// No description provided for @phoneCountryRS.
  ///
  /// In en, this message translates to:
  /// **'Serbia'**
  String get phoneCountryRS;

  /// No description provided for @phoneCountryRU.
  ///
  /// In en, this message translates to:
  /// **'Russia'**
  String get phoneCountryRU;

  /// No description provided for @phoneCountryRW.
  ///
  /// In en, this message translates to:
  /// **'Rwanda'**
  String get phoneCountryRW;

  /// No description provided for @phoneCountrySA.
  ///
  /// In en, this message translates to:
  /// **'Saudi Arabia'**
  String get phoneCountrySA;

  /// No description provided for @phoneCountrySB.
  ///
  /// In en, this message translates to:
  /// **'Solomon Islands'**
  String get phoneCountrySB;

  /// No description provided for @phoneCountrySC.
  ///
  /// In en, this message translates to:
  /// **'Seychelles'**
  String get phoneCountrySC;

  /// No description provided for @phoneCountrySD.
  ///
  /// In en, this message translates to:
  /// **'Sudan'**
  String get phoneCountrySD;

  /// No description provided for @phoneCountrySE.
  ///
  /// In en, this message translates to:
  /// **'Sweden'**
  String get phoneCountrySE;

  /// No description provided for @phoneCountrySG.
  ///
  /// In en, this message translates to:
  /// **'Singapore'**
  String get phoneCountrySG;

  /// No description provided for @phoneCountrySH.
  ///
  /// In en, this message translates to:
  /// **'St. Helena'**
  String get phoneCountrySH;

  /// No description provided for @phoneCountrySI.
  ///
  /// In en, this message translates to:
  /// **'Slovenia'**
  String get phoneCountrySI;

  /// No description provided for @phoneCountrySJ.
  ///
  /// In en, this message translates to:
  /// **'Svalbard & Jan Mayen'**
  String get phoneCountrySJ;

  /// No description provided for @phoneCountrySK.
  ///
  /// In en, this message translates to:
  /// **'Slovakia'**
  String get phoneCountrySK;

  /// No description provided for @phoneCountrySL.
  ///
  /// In en, this message translates to:
  /// **'Sierra Leone'**
  String get phoneCountrySL;

  /// No description provided for @phoneCountrySM.
  ///
  /// In en, this message translates to:
  /// **'San Marino'**
  String get phoneCountrySM;

  /// No description provided for @phoneCountrySN.
  ///
  /// In en, this message translates to:
  /// **'Senegal'**
  String get phoneCountrySN;

  /// No description provided for @phoneCountrySO.
  ///
  /// In en, this message translates to:
  /// **'Somalia'**
  String get phoneCountrySO;

  /// No description provided for @phoneCountrySR.
  ///
  /// In en, this message translates to:
  /// **'Suriname'**
  String get phoneCountrySR;

  /// No description provided for @phoneCountrySS.
  ///
  /// In en, this message translates to:
  /// **'South Sudan'**
  String get phoneCountrySS;

  /// No description provided for @phoneCountryST.
  ///
  /// In en, this message translates to:
  /// **'São Tomé & Príncipe'**
  String get phoneCountryST;

  /// No description provided for @phoneCountrySV.
  ///
  /// In en, this message translates to:
  /// **'El Salvador'**
  String get phoneCountrySV;

  /// No description provided for @phoneCountrySX.
  ///
  /// In en, this message translates to:
  /// **'Sint Maarten'**
  String get phoneCountrySX;

  /// No description provided for @phoneCountrySY.
  ///
  /// In en, this message translates to:
  /// **'Syria'**
  String get phoneCountrySY;

  /// No description provided for @phoneCountrySZ.
  ///
  /// In en, this message translates to:
  /// **'Eswatini'**
  String get phoneCountrySZ;

  /// No description provided for @phoneCountryTA.
  ///
  /// In en, this message translates to:
  /// **'Tristan da Cunha'**
  String get phoneCountryTA;

  /// No description provided for @phoneCountryTC.
  ///
  /// In en, this message translates to:
  /// **'Turks & Caicos Islands'**
  String get phoneCountryTC;

  /// No description provided for @phoneCountryTD.
  ///
  /// In en, this message translates to:
  /// **'Chad'**
  String get phoneCountryTD;

  /// No description provided for @phoneCountryTG.
  ///
  /// In en, this message translates to:
  /// **'Togo'**
  String get phoneCountryTG;

  /// No description provided for @phoneCountryTH.
  ///
  /// In en, this message translates to:
  /// **'Thailand'**
  String get phoneCountryTH;

  /// No description provided for @phoneCountryTJ.
  ///
  /// In en, this message translates to:
  /// **'Tajikistan'**
  String get phoneCountryTJ;

  /// No description provided for @phoneCountryTK.
  ///
  /// In en, this message translates to:
  /// **'Tokelau'**
  String get phoneCountryTK;

  /// No description provided for @phoneCountryTL.
  ///
  /// In en, this message translates to:
  /// **'Timor-Leste'**
  String get phoneCountryTL;

  /// No description provided for @phoneCountryTM.
  ///
  /// In en, this message translates to:
  /// **'Turkmenistan'**
  String get phoneCountryTM;

  /// No description provided for @phoneCountryTN.
  ///
  /// In en, this message translates to:
  /// **'Tunisia'**
  String get phoneCountryTN;

  /// No description provided for @phoneCountryTO.
  ///
  /// In en, this message translates to:
  /// **'Tonga'**
  String get phoneCountryTO;

  /// No description provided for @phoneCountryTR.
  ///
  /// In en, this message translates to:
  /// **'Türkiye'**
  String get phoneCountryTR;

  /// No description provided for @phoneCountryTT.
  ///
  /// In en, this message translates to:
  /// **'Trinidad & Tobago'**
  String get phoneCountryTT;

  /// No description provided for @phoneCountryTV.
  ///
  /// In en, this message translates to:
  /// **'Tuvalu'**
  String get phoneCountryTV;

  /// No description provided for @phoneCountryTW.
  ///
  /// In en, this message translates to:
  /// **'Taiwan'**
  String get phoneCountryTW;

  /// No description provided for @phoneCountryTZ.
  ///
  /// In en, this message translates to:
  /// **'Tanzania'**
  String get phoneCountryTZ;

  /// No description provided for @phoneCountryUA.
  ///
  /// In en, this message translates to:
  /// **'Ukraine'**
  String get phoneCountryUA;

  /// No description provided for @phoneCountryUG.
  ///
  /// In en, this message translates to:
  /// **'Uganda'**
  String get phoneCountryUG;

  /// No description provided for @phoneCountryUS.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get phoneCountryUS;

  /// No description provided for @phoneCountryUY.
  ///
  /// In en, this message translates to:
  /// **'Uruguay'**
  String get phoneCountryUY;

  /// No description provided for @phoneCountryUZ.
  ///
  /// In en, this message translates to:
  /// **'Uzbekistan'**
  String get phoneCountryUZ;

  /// No description provided for @phoneCountryVA.
  ///
  /// In en, this message translates to:
  /// **'Vatican City'**
  String get phoneCountryVA;

  /// No description provided for @phoneCountryVC.
  ///
  /// In en, this message translates to:
  /// **'St. Vincent & Grenadines'**
  String get phoneCountryVC;

  /// No description provided for @phoneCountryVE.
  ///
  /// In en, this message translates to:
  /// **'Venezuela'**
  String get phoneCountryVE;

  /// No description provided for @phoneCountryVG.
  ///
  /// In en, this message translates to:
  /// **'British Virgin Islands'**
  String get phoneCountryVG;

  /// No description provided for @phoneCountryVI.
  ///
  /// In en, this message translates to:
  /// **'U.S. Virgin Islands'**
  String get phoneCountryVI;

  /// No description provided for @phoneCountryVN.
  ///
  /// In en, this message translates to:
  /// **'Vietnam'**
  String get phoneCountryVN;

  /// No description provided for @phoneCountryVU.
  ///
  /// In en, this message translates to:
  /// **'Vanuatu'**
  String get phoneCountryVU;

  /// No description provided for @phoneCountryWF.
  ///
  /// In en, this message translates to:
  /// **'Wallis & Futuna'**
  String get phoneCountryWF;

  /// No description provided for @phoneCountryWS.
  ///
  /// In en, this message translates to:
  /// **'Samoa'**
  String get phoneCountryWS;

  /// No description provided for @phoneCountryXK.
  ///
  /// In en, this message translates to:
  /// **'Kosovo'**
  String get phoneCountryXK;

  /// No description provided for @phoneCountryYE.
  ///
  /// In en, this message translates to:
  /// **'Yemen'**
  String get phoneCountryYE;

  /// No description provided for @phoneCountryYT.
  ///
  /// In en, this message translates to:
  /// **'Mayotte'**
  String get phoneCountryYT;

  /// No description provided for @phoneCountryZA.
  ///
  /// In en, this message translates to:
  /// **'South Africa'**
  String get phoneCountryZA;

  /// No description provided for @phoneCountryZM.
  ///
  /// In en, this message translates to:
  /// **'Zambia'**
  String get phoneCountryZM;

  /// No description provided for @phoneCountryZW.
  ///
  /// In en, this message translates to:
  /// **'Zimbabwe'**
  String get phoneCountryZW;

  /// No description provided for @commentAssetChecking.
  ///
  /// In en, this message translates to:
  /// **'Verifying the model. Please try again shortly.'**
  String get commentAssetChecking;

  /// No description provided for @commentAssetUpdated.
  ///
  /// In en, this message translates to:
  /// **'The model has been updated. Please reopen comments.'**
  String get commentAssetUpdated;

  /// No description provided for @commentLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Comments are temporarily unavailable.'**
  String get commentLoadFailed;

  /// No description provided for @commentLoadRetry.
  ///
  /// In en, this message translates to:
  /// **'Unable to load comments. Please try again.'**
  String get commentLoadRetry;

  /// No description provided for @commentSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to send. Your draft has been saved. Please try again.'**
  String get commentSendFailed;

  /// No description provided for @commentImageLimit.
  ///
  /// In en, this message translates to:
  /// **'You can add up to 3 images.'**
  String get commentImageLimit;

  /// No description provided for @commentImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Each image must be no larger than 2 MiB.'**
  String get commentImageTooLarge;

  /// No description provided for @commentImageAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to add images. Choose JPEG, PNG or WebP files, each no larger than 2 MiB.'**
  String get commentImageAddFailed;

  /// No description provided for @commentLikeFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to like this comment. Please try again.'**
  String get commentLikeFailed;

  /// No description provided for @commentDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete this comment. Please try again.'**
  String get commentDeleteFailed;

  /// No description provided for @commentEditDraftFirst.
  ///
  /// In en, this message translates to:
  /// **'Send or clear your current draft before editing a comment.'**
  String get commentEditDraftFirst;

  /// No description provided for @commentReselectImages.
  ///
  /// In en, this message translates to:
  /// **'Please select the images to send again.'**
  String get commentReselectImages;

  /// No description provided for @commentRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh comments'**
  String get commentRefresh;

  /// No description provided for @commentClose.
  ///
  /// In en, this message translates to:
  /// **'Close comments'**
  String get commentClose;

  /// No description provided for @commentReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get commentReload;

  /// No description provided for @commentViewLatest.
  ///
  /// In en, this message translates to:
  /// **'View latest'**
  String get commentViewLatest;

  /// No description provided for @commentHot.
  ///
  /// In en, this message translates to:
  /// **'Top comments'**
  String get commentHot;

  /// No description provided for @commentLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get commentLatest;

  /// No description provided for @commentEmpty.
  ///
  /// In en, this message translates to:
  /// **'No public comments yet. Start a conversation about this work.'**
  String get commentEmpty;

  /// No description provided for @commentHotEmpty.
  ///
  /// In en, this message translates to:
  /// **'No top comments yet'**
  String get commentHotEmpty;

  /// No description provided for @commentLatestEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent comments yet'**
  String get commentLatestEmpty;

  /// No description provided for @commentPrivatePending.
  ///
  /// In en, this message translates to:
  /// **'Pending publication · Only visible to you'**
  String get commentPrivatePending;

  /// No description provided for @commentPrivateRejected.
  ///
  /// In en, this message translates to:
  /// **'Not approved · Only visible to you'**
  String get commentPrivateRejected;

  /// No description provided for @commentPrivateError.
  ///
  /// In en, this message translates to:
  /// **'Submission error · Only visible to you'**
  String get commentPrivateError;

  /// No description provided for @commentAuthorReply.
  ///
  /// In en, this message translates to:
  /// **'Author reply'**
  String get commentAuthorReply;

  /// No description provided for @commentMe.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get commentMe;

  /// No description provided for @commentReplyFallback.
  ///
  /// In en, this message translates to:
  /// **'comment'**
  String get commentReplyFallback;

  /// No description provided for @commentHidden.
  ///
  /// In en, this message translates to:
  /// **'This comment has been hidden for violating the Community Guidelines.'**
  String get commentHidden;

  /// No description provided for @commentViewReasonAppeal.
  ///
  /// In en, this message translates to:
  /// **'View reason and appeal'**
  String get commentViewReasonAppeal;

  /// No description provided for @commentViewPoint.
  ///
  /// In en, this message translates to:
  /// **'View location on model'**
  String get commentViewPoint;

  /// No description provided for @commentReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get commentReply;

  /// No description provided for @commentEditResend.
  ///
  /// In en, this message translates to:
  /// **'Edit and resend'**
  String get commentEditResend;

  /// No description provided for @commentImagePreview.
  ///
  /// In en, this message translates to:
  /// **'Comment image preview'**
  String get commentImagePreview;

  /// No description provided for @commentCloseImage.
  ///
  /// In en, this message translates to:
  /// **'Close image'**
  String get commentCloseImage;

  /// No description provided for @commentImageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image temporarily unavailable'**
  String get commentImageLoadFailed;

  /// No description provided for @commentCancelReply.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get commentCancelReply;

  /// No description provided for @commentPointSelected.
  ///
  /// In en, this message translates to:
  /// **'Model location selected'**
  String get commentPointSelected;

  /// No description provided for @commentRemovePoint.
  ///
  /// In en, this message translates to:
  /// **'Remove model location'**
  String get commentRemovePoint;

  /// No description provided for @commentSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to comment'**
  String get commentSignIn;

  /// No description provided for @commentServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Comment service temporarily unavailable'**
  String get commentServiceUnavailable;

  /// No description provided for @commentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Commenting temporarily unavailable'**
  String get commentUnavailable;

  /// No description provided for @commentComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Say something…'**
  String get commentComposerHint;

  /// No description provided for @commentAddEmoji.
  ///
  /// In en, this message translates to:
  /// **'Add emoji'**
  String get commentAddEmoji;

  /// No description provided for @commentAddImage.
  ///
  /// In en, this message translates to:
  /// **'Add images'**
  String get commentAddImage;

  /// No description provided for @commentSelectPoint.
  ///
  /// In en, this message translates to:
  /// **'Select location on model'**
  String get commentSelectPoint;

  /// No description provided for @commentSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get commentSend;

  /// No description provided for @commentReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report this comment'**
  String get commentReportTitle;

  /// No description provided for @commentPointUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location selection is temporarily unavailable. Please try again later.'**
  String get commentPointUnavailable;

  /// No description provided for @commentHideOnModel.
  ///
  /// In en, this message translates to:
  /// **'Hide model comments'**
  String get commentHideOnModel;

  /// No description provided for @commentShowOnModel.
  ///
  /// In en, this message translates to:
  /// **'Show model comments'**
  String get commentShowOnModel;

  /// No description provided for @commentAllWrite.
  ///
  /// In en, this message translates to:
  /// **'All comments / Write a comment'**
  String get commentAllWrite;

  /// No description provided for @commentPickPointHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the model surface to choose a comment location'**
  String get commentPickPointHint;

  /// No description provided for @commentAll.
  ///
  /// In en, this message translates to:
  /// **'All comments'**
  String get commentAll;

  /// No description provided for @publicWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'Community work'**
  String get publicWorkTitle;

  /// No description provided for @publicWorkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This work is unavailable. Check the link or try again later.'**
  String get publicWorkUnavailable;

  /// No description provided for @commentCount.
  ///
  /// In en, this message translates to:
  /// **'Comments {count}'**
  String commentCount(int count);

  /// No description provided for @commentRetrySection.
  ///
  /// In en, this message translates to:
  /// **'Retry {section}'**
  String commentRetrySection(String section);

  /// No description provided for @commentMoreSection.
  ///
  /// In en, this message translates to:
  /// **'Load more {section}'**
  String commentMoreSection(String section);

  /// No description provided for @commentReplyTo.
  ///
  /// In en, this message translates to:
  /// **'Reply to {name}'**
  String commentReplyTo(String name);

  /// No description provided for @commentImageNumber.
  ///
  /// In en, this message translates to:
  /// **'Comment image {number}'**
  String commentImageNumber(int number);

  /// No description provided for @commentRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image {number}'**
  String commentRemoveImage(int number);

  /// No description provided for @commentLength.
  ///
  /// In en, this message translates to:
  /// **'{current}/{max} · Emoji may count as multiple units'**
  String commentLength(int current, int max);

  /// No description provided for @commentLikeCount.
  ///
  /// In en, this message translates to:
  /// **'Like {count}'**
  String commentLikeCount(int count);

  /// No description provided for @commentUnlikeCount.
  ///
  /// In en, this message translates to:
  /// **'Unlike {count}'**
  String commentUnlikeCount(int count);

  /// No description provided for @commentCalendarDate.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String commentCalendarDate(int month, int day);

  /// No description provided for @commentYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get commentYesterday;

  /// No description provided for @commentDayBeforeYesterday.
  ///
  /// In en, this message translates to:
  /// **'2 days ago'**
  String get commentDayBeforeYesterday;

  /// No description provided for @moderationIdentityChanged.
  ///
  /// In en, this message translates to:
  /// **'Your account or service region has changed. Reload to continue.'**
  String get moderationIdentityChanged;

  /// No description provided for @moderationSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view moderation notices'**
  String get moderationSignInRequired;

  /// No description provided for @moderationRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Try again; your appeal statement has been kept.'**
  String get moderationRequestTimeout;

  /// No description provided for @moderationConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect right now. Try again.'**
  String get moderationConnectionFailed;

  /// No description provided for @moderationInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get moderationInbox;

  /// No description provided for @moderationInboxLoadFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'Inbox. Notices could not be loaded; you can still open it.'**
  String get moderationInboxLoadFailedLabel;

  /// No description provided for @moderationInboxUnreadLabel.
  ///
  /// In en, this message translates to:
  /// **'Inbox. You have unread moderation notices.'**
  String get moderationInboxUnreadLabel;

  /// No description provided for @moderationInboxReadLabel.
  ///
  /// In en, this message translates to:
  /// **'Inbox. No unread moderation notices.'**
  String get moderationInboxReadLabel;

  /// No description provided for @moderationInboxNotLoadedLabel.
  ///
  /// In en, this message translates to:
  /// **'Inbox. Notices have not loaded yet.'**
  String get moderationInboxNotLoadedLabel;

  /// No description provided for @moderationInboxTitle.
  ///
  /// In en, this message translates to:
  /// **'System inbox'**
  String get moderationInboxTitle;

  /// No description provided for @moderationRefreshNotices.
  ///
  /// In en, this message translates to:
  /// **'Refresh notices'**
  String get moderationRefreshNotices;

  /// No description provided for @moderationNoNotices.
  ///
  /// In en, this message translates to:
  /// **'No moderation notices'**
  String get moderationNoNotices;

  /// No description provided for @moderationCommentHidden.
  ///
  /// In en, this message translates to:
  /// **'Comment hidden'**
  String get moderationCommentHidden;

  /// No description provided for @moderationCommentRestored.
  ///
  /// In en, this message translates to:
  /// **'Comment restored'**
  String get moderationCommentRestored;

  /// No description provided for @moderationAppealRejected.
  ///
  /// In en, this message translates to:
  /// **'Appeal rejected'**
  String get moderationAppealRejected;

  /// No description provided for @moderationUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get moderationUnread;

  /// No description provided for @moderationRelatedWorkComment.
  ///
  /// In en, this message translates to:
  /// **'Comment on a related work'**
  String get moderationRelatedWorkComment;

  /// No description provided for @moderationViewCase.
  ///
  /// In en, this message translates to:
  /// **'View moderation details'**
  String get moderationViewCase;

  /// No description provided for @moderationCaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Comment moderation details'**
  String get moderationCaseTitle;

  /// No description provided for @moderationRefreshCase.
  ///
  /// In en, this message translates to:
  /// **'Refresh moderation result'**
  String get moderationRefreshCase;

  /// No description provided for @moderationCommentHiddenBody.
  ///
  /// In en, this message translates to:
  /// **'This comment is currently hidden from other people.'**
  String get moderationCommentHiddenBody;

  /// No description provided for @moderationCommentRestoredBody.
  ///
  /// In en, this message translates to:
  /// **'The server has confirmed that this comment is visible again.'**
  String get moderationCommentRestoredBody;

  /// No description provided for @moderationReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for moderation'**
  String get moderationReason;

  /// No description provided for @moderationRelatedContent.
  ///
  /// In en, this message translates to:
  /// **'Related content'**
  String get moderationRelatedContent;

  /// No description provided for @moderationCommentWork.
  ///
  /// In en, this message translates to:
  /// **'The work this comment belongs to'**
  String get moderationCommentWork;

  /// No description provided for @moderationHiddenPreview.
  ///
  /// In en, this message translates to:
  /// **'This comment is currently hidden. You can view the moderation result and submit an appeal here.'**
  String get moderationHiddenPreview;

  /// No description provided for @moderationRequestReview.
  ///
  /// In en, this message translates to:
  /// **'Request a review'**
  String get moderationRequestReview;

  /// No description provided for @moderationRequestReviewBody.
  ///
  /// In en, this message translates to:
  /// **'Explain why this decision should be reviewed. The comment stays hidden while your appeal is being reviewed.'**
  String get moderationRequestReviewBody;

  /// No description provided for @moderationAppealStatement.
  ///
  /// In en, this message translates to:
  /// **'Appeal statement'**
  String get moderationAppealStatement;

  /// No description provided for @moderationAppealStatementHint.
  ///
  /// In en, this message translates to:
  /// **'Add context or explain what you think needs another review'**
  String get moderationAppealStatementHint;

  /// No description provided for @moderationAppealStatementTooLong.
  ///
  /// In en, this message translates to:
  /// **'The appeal statement must not exceed 1,000 characters'**
  String get moderationAppealStatementTooLong;

  /// No description provided for @moderationSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get moderationSubmitting;

  /// No description provided for @moderationSubmitAppeal.
  ///
  /// In en, this message translates to:
  /// **'Submit appeal'**
  String get moderationSubmitAppeal;

  /// No description provided for @moderationAppealSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Appeal submitted'**
  String get moderationAppealSubmitted;

  /// No description provided for @moderationAppealApproved.
  ///
  /// In en, this message translates to:
  /// **'Appeal approved'**
  String get moderationAppealApproved;

  /// No description provided for @moderationAppealPendingBody.
  ///
  /// In en, this message translates to:
  /// **'Wait for the review result. The comment stays hidden during the review; you do not need to submit again.'**
  String get moderationAppealPendingBody;

  /// No description provided for @moderationAppealResultFallback.
  ///
  /// In en, this message translates to:
  /// **'The result is reflected in the current comment status.'**
  String get moderationAppealResultFallback;

  /// No description provided for @communityCoverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cover unavailable'**
  String get communityCoverUnavailable;

  /// No description provided for @communityFeedLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load works. Please try again.'**
  String get communityFeedLoadFailed;

  /// No description provided for @viewerModelUnavailableDataKept.
  ///
  /// In en, this message translates to:
  /// **'Unable to display the model right now. Your local data has been kept.'**
  String get viewerModelUnavailableDataKept;

  /// No description provided for @moderationDecisionTime.
  ///
  /// In en, this message translates to:
  /// **'Decision time: {date}'**
  String moderationDecisionTime(String date);

  /// No description provided for @siteTitle.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng — Keep spaces close.'**
  String get siteTitle;

  /// No description provided for @siteDescription.
  ///
  /// In en, this message translates to:
  /// **'The official website of Beijing Kongye Technology Co., Ltd. Explore spatial capture and 3D content, learn about the Chuang Hou Cheng iOS app in development, and contact Kongye.'**
  String get siteDescription;

  /// No description provided for @siteSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip to content'**
  String get siteSkip;

  /// No description provided for @siteHome.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng home'**
  String get siteHome;

  /// No description provided for @siteBrand.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng'**
  String get siteBrand;

  /// No description provided for @siteMainNav.
  ///
  /// In en, this message translates to:
  /// **'Main navigation'**
  String get siteMainNav;

  /// No description provided for @siteDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get siteDiscover;

  /// No description provided for @siteSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in ↗'**
  String get siteSignIn;

  /// No description provided for @siteSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get siteSupport;

  /// No description provided for @siteAgreements.
  ///
  /// In en, this message translates to:
  /// **'Agreements'**
  String get siteAgreements;

  /// No description provided for @siteContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get siteContact;

  /// No description provided for @siteTagline.
  ///
  /// In en, this message translates to:
  /// **'Capture spaces. Share 3D creations.'**
  String get siteTagline;

  /// No description provided for @siteOpenCommunity.
  ///
  /// In en, this message translates to:
  /// **'Open community ↗'**
  String get siteOpenCommunity;

  /// No description provided for @siteDiscoverSpaces.
  ///
  /// In en, this message translates to:
  /// **'Discover spaces'**
  String get siteDiscoverSpaces;

  /// No description provided for @siteCommunityWorks.
  ///
  /// In en, this message translates to:
  /// **'Community creations'**
  String get siteCommunityWorks;

  /// No description provided for @siteSupportContact.
  ///
  /// In en, this message translates to:
  /// **'Support & contact'**
  String get siteSupportContact;

  /// No description provided for @siteContactLead.
  ///
  /// In en, this message translates to:
  /// **'Product questions and feedback: '**
  String get siteContactLead;

  /// No description provided for @siteTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get siteTerms;

  /// No description provided for @sitePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get sitePrivacy;

  /// No description provided for @siteRules.
  ///
  /// In en, this message translates to:
  /// **'Community guidelines'**
  String get siteRules;

  /// No description provided for @siteAgreementVersion.
  ///
  /// In en, this message translates to:
  /// **'Agreements V1.1 · Published November 2, 2026 · '**
  String get siteAgreementVersion;

  /// No description provided for @sitePublicationNotice.
  ///
  /// In en, this message translates to:
  /// **'3D publication and review'**
  String get sitePublicationNotice;

  /// No description provided for @siteAbout.
  ///
  /// In en, this message translates to:
  /// **'About us'**
  String get siteAbout;

  /// No description provided for @siteAboutHeadline.
  ///
  /// In en, this message translates to:
  /// **'Spaces take shape.\nExplore without limits.'**
  String get siteAboutHeadline;

  /// No description provided for @siteCompany.
  ///
  /// In en, this message translates to:
  /// **'Beijing Kongye Technology Co., Ltd'**
  String get siteCompany;

  /// No description provided for @siteAboutFirst.
  ///
  /// In en, this message translates to:
  /// **'Kongye is a technology company based in Beijing, China. Our current product focus is developing the Chuang Hou Cheng iOS app, connecting mobile devices, spatial capture, and 3D content.'**
  String get siteAboutFirst;

  /// No description provided for @siteAboutSecond.
  ///
  /// In en, this message translates to:
  /// **'We want capturing and experiencing digital spaces to become part of everyday life. Starting with familiar places, we explore more natural ways to express content. This website provides official company information and contact details.'**
  String get siteAboutSecond;

  /// No description provided for @siteLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get siteLocation;

  /// No description provided for @siteBeijing.
  ///
  /// In en, this message translates to:
  /// **'Beijing · China'**
  String get siteBeijing;

  /// No description provided for @siteProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get siteProduct;

  /// No description provided for @siteProductValue.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng · iOS app development'**
  String get siteProductValue;

  /// No description provided for @siteOfficialWebsite.
  ///
  /// In en, this message translates to:
  /// **'Official website'**
  String get siteOfficialWebsite;

  /// No description provided for @siteCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Beijing Kongye Technology Co., Ltd'**
  String get siteCopyright;

  /// No description provided for @siteFooterNav.
  ///
  /// In en, this message translates to:
  /// **'Footer navigation'**
  String get siteFooterNav;

  /// No description provided for @siteProductSupport.
  ///
  /// In en, this message translates to:
  /// **'Product support'**
  String get siteProductSupport;

  /// No description provided for @siteBackTop.
  ///
  /// In en, this message translates to:
  /// **'Back to top ↑'**
  String get siteBackTop;

  /// No description provided for @siteLanguageSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch to Chinese'**
  String get siteLanguageSwitch;

  /// No description provided for @siteFeedLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading community creations…'**
  String get siteFeedLoading;

  /// No description provided for @siteLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get siteLoadMore;

  /// No description provided for @siteFeedConnection.
  ///
  /// In en, this message translates to:
  /// **'The community is unavailable. Try again or open the full community.'**
  String get siteFeedConnection;

  /// No description provided for @siteFeedFormat.
  ///
  /// In en, this message translates to:
  /// **'The community returned an unexpected response.'**
  String get siteFeedFormat;

  /// No description provided for @siteViewWork.
  ///
  /// In en, this message translates to:
  /// **'View {title}'**
  String siteViewWork(Object title);

  /// No description provided for @siteUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled creation'**
  String get siteUntitled;

  /// No description provided for @siteWorkImage.
  ///
  /// In en, this message translates to:
  /// **'3D creation'**
  String get siteWorkImage;

  /// No description provided for @siteCoverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cover unavailable'**
  String get siteCoverUnavailable;

  /// No description provided for @siteNoCover.
  ///
  /// In en, this message translates to:
  /// **'No cover'**
  String get siteNoCover;

  /// No description provided for @siteLikeSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to like'**
  String get siteLikeSignIn;

  /// No description provided for @siteConfigUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Community configuration is unavailable.'**
  String get siteConfigUnavailable;

  /// No description provided for @siteFeedHint.
  ///
  /// In en, this message translates to:
  /// **'Open a creation to rotate and zoom.'**
  String get siteFeedHint;

  /// No description provided for @siteFeedEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no public creations yet.'**
  String get siteFeedEmpty;

  /// No description provided for @siteFeedRetry.
  ///
  /// In en, this message translates to:
  /// **'The community is unavailable. Please try again.'**
  String get siteFeedRetry;

  /// No description provided for @siteReload.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get siteReload;

  /// No description provided for @siteSharedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The shared creation is unavailable.'**
  String get siteSharedUnavailable;

  /// No description provided for @siteSharedNotPublic.
  ///
  /// In en, this message translates to:
  /// **'The shared creation is unavailable and may no longer be public.'**
  String get siteSharedNotPublic;

  /// No description provided for @siteInvalidCursor.
  ///
  /// In en, this message translates to:
  /// **'Invalid creation cursor'**
  String get siteInvalidCursor;

  /// No description provided for @siteInvalidAsset.
  ///
  /// In en, this message translates to:
  /// **'Invalid creation address'**
  String get siteInvalidAsset;

  /// No description provided for @siteUnsupportedFormat.
  ///
  /// In en, this message translates to:
  /// **'Open the community to view this format.'**
  String get siteUnsupportedFormat;

  /// No description provided for @siteLargeWork.
  ///
  /// In en, this message translates to:
  /// **'This creation is large or its size is unknown. Open the full community to view it.'**
  String get siteLargeWork;

  /// No description provided for @siteInvalidWork.
  ///
  /// In en, this message translates to:
  /// **'Invalid creation link'**
  String get siteInvalidWork;

  /// No description provided for @siteInvalidAuthors.
  ///
  /// In en, this message translates to:
  /// **'Invalid author list'**
  String get siteInvalidAuthors;

  /// No description provided for @siteYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get siteYesterday;

  /// No description provided for @siteDayBeforeYesterday.
  ///
  /// In en, this message translates to:
  /// **'The day before yesterday'**
  String get siteDayBeforeYesterday;

  /// No description provided for @siteMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}'**
  String siteMonthDay(Object day, Object month);

  /// No description provided for @siteGalleryCollapse.
  ///
  /// In en, this message translates to:
  /// **'Close 3D '**
  String get siteGalleryCollapse;

  /// No description provided for @siteGalleryRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate in 3D '**
  String get siteGalleryRotate;

  /// No description provided for @siteMotionReducedAria.
  ///
  /// In en, this message translates to:
  /// **'Reduced motion is enabled by your system'**
  String get siteMotionReducedAria;

  /// No description provided for @siteMotionPlayAria.
  ///
  /// In en, this message translates to:
  /// **'Play geometric animation'**
  String get siteMotionPlayAria;

  /// No description provided for @siteMotionPauseAria.
  ///
  /// In en, this message translates to:
  /// **'Pause geometric animation'**
  String get siteMotionPauseAria;

  /// No description provided for @siteMotionReduced.
  ///
  /// In en, this message translates to:
  /// **'Motion reduced'**
  String get siteMotionReduced;

  /// No description provided for @siteMotionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play animation'**
  String get siteMotionPlay;

  /// No description provided for @siteMotionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause animation'**
  String get siteMotionPause;

  /// No description provided for @meCloudUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cloud is unavailable. Please try again later.'**
  String get meCloudUnavailable;

  /// No description provided for @meDenseStageCannotRebuild.
  ///
  /// In en, this message translates to:
  /// **'This work has entered the dense stage.\nIt can no longer be reconstructed.'**
  String get meDenseStageCannotRebuild;

  /// No description provided for @meThisCapture.
  ///
  /// In en, this message translates to:
  /// **'This capture'**
  String get meThisCapture;

  /// No description provided for @meQuotedCaptureName.
  ///
  /// In en, this message translates to:
  /// **'“{name}”'**
  String meQuotedCaptureName(String name);

  /// No description provided for @meRegenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct again?'**
  String get meRegenerateTitle;

  /// No description provided for @meResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'Resume reconstruction?'**
  String get meResumeTitle;

  /// No description provided for @meRegenerateBody.
  ///
  /// In en, this message translates to:
  /// **'The saved reconstruction data for {name} will be used to regenerate and replace the existing point cloud. No new capture is needed.'**
  String meRegenerateBody(String name);

  /// No description provided for @meResumeBody.
  ///
  /// In en, this message translates to:
  /// **'The point cloud for {name} has not been generated yet. Capture data is fully saved, so reconstruction can resume from where it stopped. No new capture is needed.'**
  String meResumeBody(String name);

  /// No description provided for @meRegenerateAction.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct again'**
  String get meRegenerateAction;

  /// No description provided for @meResumeAction.
  ///
  /// In en, this message translates to:
  /// **'Resume reconstruction'**
  String get meResumeAction;

  /// No description provided for @meStartTraining.
  ///
  /// In en, this message translates to:
  /// **'Start training'**
  String get meStartTraining;

  /// No description provided for @meCaptureMorePhotos.
  ///
  /// In en, this message translates to:
  /// **'Capture more photos'**
  String get meCaptureMorePhotos;

  /// No description provided for @mePhotosRebuildUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This project was not captured with the official pipeline.\nIt cannot be reconstructed from photos.'**
  String get mePhotosRebuildUnsupported;

  /// No description provided for @mePhotosRebuildUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Reconstruction from photos is unavailable.'**
  String get mePhotosRebuildUnavailable;

  /// No description provided for @meMorePhotosUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This project was not captured with the official pipeline.\nAdditional capture is not supported yet.'**
  String get meMorePhotosUnsupported;

  /// No description provided for @meMorePhotosUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Additional capture is unavailable.'**
  String get meMorePhotosUnavailable;

  /// No description provided for @meMorePhotosWait.
  ///
  /// In en, this message translates to:
  /// **'Another project is being reconstructed.\nWait for it to finish before capturing more photos.'**
  String get meMorePhotosWait;

  /// No description provided for @meMorePhotosMissingData.
  ///
  /// In en, this message translates to:
  /// **'Reconstruction data for this capture could not be found.\nAdditional capture is unavailable.'**
  String get meMorePhotosMissingData;

  /// No description provided for @meTrainingNeedsPhotos.
  ///
  /// In en, this message translates to:
  /// **'Training requires at least {minimum} photos.\nThis capture has {count}; {needed} more are needed.\nPlease continue capturing.'**
  String meTrainingNeedsPhotos(int minimum, int count, int needed);

  /// No description provided for @meTrainingWait.
  ///
  /// In en, this message translates to:
  /// **'Another project is being reconstructed.\nOnly one can run at a time. Please wait for it to finish.'**
  String get meTrainingWait;

  /// No description provided for @meTrainingMissingData.
  ///
  /// In en, this message translates to:
  /// **'The reconstruction data is damaged and the photos are no longer available.\nThis capture cannot be reconstructed.'**
  String get meTrainingMissingData;

  /// No description provided for @meCloudPending.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get meCloudPending;

  /// No description provided for @meCloudSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get meCloudSyncing;

  /// No description provided for @meCloudSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to cloud'**
  String get meCloudSaved;

  /// No description provided for @splashSolving.
  ///
  /// In en, this message translates to:
  /// **'Solving'**
  String get splashSolving;

  /// No description provided for @captureExitTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit capture?'**
  String get captureExitTitle;

  /// No description provided for @captureExitSavePrompt.
  ///
  /// In en, this message translates to:
  /// **'Save photos so you can capture more next time'**
  String get captureExitSavePrompt;

  /// No description provided for @captureExitSavePhotos.
  ///
  /// In en, this message translates to:
  /// **'Save photos'**
  String get captureExitSavePhotos;

  /// No description provided for @meCloudIdConflict.
  ///
  /// In en, this message translates to:
  /// **'Work ID conflict. Your local work has been kept.'**
  String get meCloudIdConflict;

  /// No description provided for @meCloudNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'A newer version is in the cloud. Your local version has been kept.'**
  String get meCloudNewerVersion;

  /// No description provided for @meCloudNameConflict.
  ///
  /// In en, this message translates to:
  /// **'A work with the same name exists. Your work has been kept. Please rename it.'**
  String get meCloudNameConflict;

  /// No description provided for @meCloudRetryKept.
  ///
  /// In en, this message translates to:
  /// **'Cloud is unavailable or storage is full. Your work has been kept and will retry automatically later.'**
  String get meCloudRetryKept;

  /// No description provided for @legalPrivacyS0Title.
  ///
  /// In en, this message translates to:
  /// **'Introduction'**
  String get legalPrivacyS0Title;

  /// No description provided for @legalPrivacyS0P0.
  ///
  /// In en, this message translates to:
  /// **'“方寸间” (the “Product”) is operated by 【公司名称待注册后填写】 (“we” or “us”). This Policy explains how we collect, use, store and protect your personal information, and your rights and how to exercise them. Please read this Policy carefully before using the Product, especially the terms in bold.'**
  String get legalPrivacyS0P0;

  /// No description provided for @legalPrivacyS0P1.
  ///
  /// In en, this message translates to:
  /// **'Five key points first; details follow in the text:'**
  String get legalPrivacyS0P1;

  /// No description provided for @legalPrivacyS0P2.
  ///
  /// In en, this message translates to:
  /// **'① The original photos you capture are processed only on your phone and are never uploaded. Only the reconstructed 3D point clouds and thumbnails rendered from them are uploaded;'**
  String get legalPrivacyS0P2;

  /// No description provided for @legalPrivacyS0P3.
  ///
  /// In en, this message translates to:
  /// **'② The Product embeds no third-party analytics, advertising, push notification or crash collection components and contains no form of user tracking;'**
  String get legalPrivacyS0P3;

  /// No description provided for @legalPrivacyS0P4.
  ///
  /// In en, this message translates to:
  /// **'③ We do not share your personal information with any third party;'**
  String get legalPrivacyS0P4;

  /// No description provided for @legalPrivacyS0P5.
  ///
  /// In en, this message translates to:
  /// **'④ Deleting your account deletes your personal information (except information retained as required by law; see Chapter IV);'**
  String get legalPrivacyS0P5;

  /// No description provided for @legalPrivacyS0P6.
  ///
  /// In en, this message translates to:
  /// **'⑤ Under national rules on internet user account information, we publicly display your account\'s IP region (at provincial level). This display cannot be disabled.'**
  String get legalPrivacyS0P6;

  /// No description provided for @legalPrivacyS0P7.
  ///
  /// In en, this message translates to:
  /// **'If you disagree with this Policy, please do not register for or use the Product. Your disagreement does not exempt processing required by laws and regulations (such as displaying the IP region).'**
  String get legalPrivacyS0P7;

  /// No description provided for @legalPrivacyS1Title.
  ///
  /// In en, this message translates to:
  /// **'I. What personal information we collect and why'**
  String get legalPrivacyS1Title;

  /// No description provided for @legalPrivacyS1P0.
  ///
  /// In en, this message translates to:
  /// **'We collect personal information only in the following five scenarios. Each item states its purpose, method and retention period. Except for your phone number, all items are optional; refusing to provide them does not affect your use of other functions.'**
  String get legalPrivacyS1P0;

  /// No description provided for @legalPrivacyS1P1.
  ///
  /// In en, this message translates to:
  /// **'(1) Account registration and sign-in'**
  String get legalPrivacyS1P1;

  /// No description provided for @legalPrivacyS1P2.
  ///
  /// In en, this message translates to:
  /// **'· Mobile phone number (required): Used to register an account, sign in and verify your real identity under the Cybersecurity Law and the Provisions on the Administration of Internet User Account Information. The necessary personal information for online community services is the registered user\'s mobile phone number. This is the only item in this Policy without which you cannot register and use the service. Verification texts are sent by an SMS provider (see Chapter III). Retained until account deletion.'**
  String get legalPrivacyS1P2;

  /// No description provided for @legalPrivacyS1P3.
  ///
  /// In en, this message translates to:
  /// **'· Email address [optional]: Once linked, used for account recovery and important notices. Refusal does not affect any function. Retained until unlinked or your account is deleted.'**
  String get legalPrivacyS1P3;

  /// No description provided for @legalPrivacyS1P4.
  ///
  /// In en, this message translates to:
  /// **'· Sign-in password [sensitive information]: Stored only as a one-way hash; we cannot view your plain-text password. Transmission is encrypted throughout. Passwords are sensitive personal information; please do not reuse a password from another platform.'**
  String get legalPrivacyS1P4;

  /// No description provided for @legalPrivacyS1P5.
  ///
  /// In en, this message translates to:
  /// **'· Nickname, account ID and biography [optional]: Used to show your identity in the community. Nicknames may be duplicated; account IDs are unique across the platform. All three are displayed publicly. Retained until you change them or delete your account.'**
  String get legalPrivacyS1P5;

  /// No description provided for @legalPrivacyS1P6.
  ///
  /// In en, this message translates to:
  /// **'(2) Capture and 3D reconstruction — completed entirely on your phone'**
  String get legalPrivacyS1P6;

  /// No description provided for @legalPrivacyS1P7.
  ///
  /// In en, this message translates to:
  /// **'· Camera images and motion sensor data: Used only for on-device capture guidance and 3D reconstruction; not uploaded or stored on servers.'**
  String get legalPrivacyS1P7;

  /// No description provided for @legalPrivacyS1P8.
  ///
  /// In en, this message translates to:
  /// **'· Original photos: Saved in the Product\'s documents directory on your device. You can view, export or delete them using the system Files app. We do not collect original photos; they do not leave your device in any form.'**
  String get legalPrivacyS1P8;

  /// No description provided for @legalPrivacyS1P9.
  ///
  /// In en, this message translates to:
  /// **'· Reconstructed 3D point clouds: Stored only on your device until you choose to publish them.'**
  String get legalPrivacyS1P9;

  /// No description provided for @legalPrivacyS1P10.
  ///
  /// In en, this message translates to:
  /// **'(3) Publishing works and community interactions'**
  String get legalPrivacyS1P10;

  /// No description provided for @legalPrivacyS1P11.
  ///
  /// In en, this message translates to:
  /// **'· Work content [optional; necessary for publishing]: When you publish a work, we collect its 3D point cloud model file, thumbnail (rendered from the point cloud, not a camera photo), title and description. After approval, the work is displayed publicly to all users, including visitors who are not signed in.'**
  String get legalPrivacyS1P11;

  /// No description provided for @legalPrivacyS1P12.
  ///
  /// In en, this message translates to:
  /// **'· When publishing, you acknowledge that once the work is published and approved, its content, your nickname, account ID and IP region at publication will be visible to everyone.'**
  String get legalPrivacyS1P12;

  /// No description provided for @legalPrivacyS1P13.
  ///
  /// In en, this message translates to:
  /// **'· IP region: Under Article 12 of the Provisions on the Administration of Internet User Account Information, work information displays your IP region at publication, and your account information page displays your IP region from your most recent use. Within China, this is shown at province level (including autonomous regions and municipalities); outside China, at country or region level. No more precise location is displayed. The system determines the region automatically from the IP address; neither you nor we can change it manually. You may appeal through the contact methods in Chapter IX.'**
  String get legalPrivacyS1P13;

  /// No description provided for @legalPrivacyS1P14.
  ///
  /// In en, this message translates to:
  /// **'· Research and technical improvement: The work content you upload will be used for our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction). When providing research data externally, we use only anonymized data that cannot identify you and cannot be restored, or obtain your separate consent. See Chapter VI of the 方寸间 User Agreement.'**
  String get legalPrivacyS1P14;

  /// No description provided for @legalPrivacyS1P15.
  ///
  /// In en, this message translates to:
  /// **'· Like, report and block records: Used to provide the corresponding functions and govern the community. Likes on public works are visible to other users; reports are visible only to you and platform administrators. Retained until you undo the action, the relevant work is deleted or your account is deleted.'**
  String get legalPrivacyS1P15;

  /// No description provided for @legalPrivacyS1P16.
  ///
  /// In en, this message translates to:
  /// **'· View records: Used only to show view counts to work authors, deduplicated hourly; not used for any personalized recommendations or advertising. Retained until the relevant work is deleted; anonymized and no longer linked to you after account deletion.'**
  String get legalPrivacyS1P16;

  /// No description provided for @legalPrivacyS1P17.
  ///
  /// In en, this message translates to:
  /// **'(4) Security'**
  String get legalPrivacyS1P17;

  /// No description provided for @legalPrivacyS1P18.
  ///
  /// In en, this message translates to:
  /// **'· IP address and device identification string (User-Agent): Recorded in security audit logs during key actions such as registration, sign-in, publishing, deletion and reporting, for security, abuse prevention and lawful regulatory cooperation. IP addresses also generate the provincial IP region display described above. Both purposes are disclosed here; we do not use them for other purposes. General audit records are retained for 180 days; records concerning account deletion and content enforcement for 730 days; the system then deletes them automatically.'**
  String get legalPrivacyS1P18;

  /// No description provided for @legalPrivacyS1P19.
  ///
  /// In en, this message translates to:
  /// **'· API frequency records: Brief records of API call frequency are kept to prevent abuse, for no more than 1 day.'**
  String get legalPrivacyS1P19;

  /// No description provided for @legalPrivacyS1P20.
  ///
  /// In en, this message translates to:
  /// **'(5) Product improvement and analytics'**
  String get legalPrivacyS1P20;

  /// No description provided for @legalPrivacyS1P21.
  ///
  /// In en, this message translates to:
  /// **'· Usage events: To understand how the Product is used and detect and fix failures, we collect feature usage events (such as the start, success or failure of publishing and the failure stage), session identifiers, error and crash summaries (error messages and truncated code stacks, excluding your work content or profile), system version and app version. Analytics is built by us; data goes only to our own servers, without any third-party analytics component. Retained for 180 days and then automatically deleted; detached from your identity (anonymized) after account deletion.'**
  String get legalPrivacyS1P21;

  /// No description provided for @legalPrivacyS1P22.
  ///
  /// In en, this message translates to:
  /// **'· Analytics is nonessential information: You can disable it at any time in “Settings → Help improve the product”. We then stop collection and clear analytics data on your device that has not yet been reported. No function is affected.'**
  String get legalPrivacyS1P22;

  /// No description provided for @legalPrivacyS1P23.
  ///
  /// In en, this message translates to:
  /// **'(6) Under laws and regulations, your consent is not required for processing necessary to perform statutory duties or obligations; respond to public health emergencies or protect natural persons\' life, health or property in emergencies; process, within a reasonable scope, personal information you have made public or that has otherwise been lawfully made public; or other circumstances provided by laws and administrative regulations.'**
  String get legalPrivacyS1P23;

  /// No description provided for @legalPrivacyS2Title.
  ///
  /// In en, this message translates to:
  /// **'II. Device permissions and local storage'**
  String get legalPrivacyS2Title;

  /// No description provided for @legalPrivacyS2P0.
  ///
  /// In en, this message translates to:
  /// **'The Product requests only the following two system permissions, each when you first use the relevant function, never at launch:'**
  String get legalPrivacyS2P0;

  /// No description provided for @legalPrivacyS2P1.
  ///
  /// In en, this message translates to:
  /// **'· Camera: To take photos for on-device 3D reconstruction. Refusing permission prevents capture but does not affect other functions such as community browsing.'**
  String get legalPrivacyS2P1;

  /// No description provided for @legalPrivacyS2P2.
  ///
  /// In en, this message translates to:
  /// **'· Motion & Fitness (motion sensors): For real-time capture guidance and camera pose estimation. Data is processed only on your device. Refusing permission affects capture guidance accuracy.'**
  String get legalPrivacyS2P2;

  /// No description provided for @legalPrivacyS2P3.
  ///
  /// In en, this message translates to:
  /// **'We do not request location, contacts, microphone, photo library or any other permissions. You may revoke permissions in system settings at any time; this does not affect the validity of processing already performed under those permissions.'**
  String get legalPrivacyS2P3;

  /// No description provided for @legalPrivacyS2P4.
  ///
  /// In en, this message translates to:
  /// **'Local storage: The Product has no embedded web browser and does not use cookies. The following is stored only on your device and will not be read by us for purposes not stated in this Policy: sign-in credentials (in the system keychain), language and interface preferences, temporary file caches from viewing others\' works (to speed loading, removable by the system), and your original photos and reconstruction outputs (see Chapter I(2)).'**
  String get legalPrivacyS2P4;

  /// No description provided for @legalPrivacyS3Title.
  ///
  /// In en, this message translates to:
  /// **'III. Entrusted processing, sharing, transfer and public disclosure'**
  String get legalPrivacyS3Title;

  /// No description provided for @legalPrivacyS3P0.
  ///
  /// In en, this message translates to:
  /// **'We do not obtain your personal information indirectly from any third party. This chapter explains where information flows from us.'**
  String get legalPrivacyS3P0;

  /// No description provided for @legalPrivacyS3P1.
  ///
  /// In en, this message translates to:
  /// **'(1) Entrusted processing. The following providers process relevant information only on our instructions. We sign data processing agreements specifying the purposes, duration, methods, information types and safeguards, and supervise their processing activities:'**
  String get legalPrivacyS3P1;

  /// No description provided for @legalPrivacyS3P2.
  ///
  /// In en, this message translates to:
  /// **'· Cloud infrastructure provider (database and file storage): 阿里云计算有限公司, storing the server-side information listed in Chapter I;'**
  String get legalPrivacyS3P2;

  /// No description provided for @legalPrivacyS3P3.
  ///
  /// In en, this message translates to:
  /// **'· SMS provider: 阿里云 (sends sign-in verification codes and accesses your mobile phone number);'**
  String get legalPrivacyS3P3;

  /// No description provided for @legalPrivacyS3P4.
  ///
  /// In en, this message translates to:
  /// **'· Email provider: 【邮件服务商待填写 —— 上线前确认为境内服务商】 (sends email verification codes and accesses your email address).'**
  String get legalPrivacyS3P4;

  /// No description provided for @legalPrivacyS3P5.
  ///
  /// In en, this message translates to:
  /// **'(2) Sharing: We do not share your personal information with any third party. Information anonymized so that it cannot identify a specific person and cannot be restored is not personal information under law. Only such anonymized data is used in our external research collaborations (see Chapter I(3)).'**
  String get legalPrivacyS3P5;

  /// No description provided for @legalPrivacyS3P6.
  ///
  /// In en, this message translates to:
  /// **'(3) Third-party SDK list: The Product embeds no third-party analytics, advertising, push notification or crash collection SDKs. If any are added in future, we will update this Policy and list before integration and obtain your consent again.'**
  String get legalPrivacyS3P6;

  /// No description provided for @legalPrivacyS3P7.
  ///
  /// In en, this message translates to:
  /// **'(4) Transfer: In a merger, division, dissolution or acquisition, we will inform you of the recipient\'s name and contact details and require it to continue fulfilling this Policy. If the recipient changes the purposes or methods of processing, your consent will be obtained again.'**
  String get legalPrivacyS3P7;

  /// No description provided for @legalPrivacyS3P8.
  ///
  /// In en, this message translates to:
  /// **'(5) Public disclosure: Other than the legally required IP region display disclosed in Chapter I and content you actively publish, we do not publicly disclose your personal information, except when lawfully cooperating with regulators or judicial authorities.'**
  String get legalPrivacyS3P8;

  /// No description provided for @legalPrivacyS4Title.
  ///
  /// In en, this message translates to:
  /// **'IV. Information storage and protection'**
  String get legalPrivacyS4Title;

  /// No description provided for @legalPrivacyS4P0.
  ///
  /// In en, this message translates to:
  /// **'1. Storage location: Your personal information is stored within the People\'s Republic of China.'**
  String get legalPrivacyS4P0;

  /// No description provided for @legalPrivacyS4P1.
  ///
  /// In en, this message translates to:
  /// **'2. Retention periods: Chapter I lists each period. In summary: account details (phone/email/nickname/ID/biography) until account deletion; works and interaction records until deletion or account deletion; view records anonymized after account deletion; analytics events 180 days; security audit logs 180 days (major actions 730 days); API frequency records no more than 1 day; temporary registration verification data 10 minutes. Information exceeding its period is automatically deleted or anonymized.'**
  String get legalPrivacyS4P1;

  /// No description provided for @legalPrivacyS4P2.
  ///
  /// In en, this message translates to:
  /// **'3. Statutory retention exception: For content governance, copies of files for works lawfully removed will be separately sealed and retained for dispute resolution and regulatory cooperation, and used for no other purpose during that time. These copies may remain for the necessary period after account deletion.'**
  String get legalPrivacyS4P2;

  /// No description provided for @legalPrivacyS4P3.
  ///
  /// In en, this message translates to:
  /// **'4. Safeguards: All transmissions use encrypted channels (TLS); passwords are stored as one-way hashes; database row-level access controls prevent users from reading others\' nonpublic data; sign-in credentials are stored in the system keychain; key actions have audit records; uploads undergo two-stage validation, and files failing validation do not enter public storage.'**
  String get legalPrivacyS4P3;

  /// No description provided for @legalPrivacyS4P4.
  ///
  /// In en, this message translates to:
  /// **'5. Security incidents: If personal information is leaked, altered or lost, we will immediately take remedial measures, inform you of the incident, possible effects and remedies as required by law, and report to regulators.'**
  String get legalPrivacyS4P4;

  /// No description provided for @legalPrivacyS4P5.
  ///
  /// In en, this message translates to:
  /// **'6. Closure: If the Product ceases operation, we will stop collecting personal information, notify you by announcement, and delete or anonymize stored personal information.'**
  String get legalPrivacyS4P5;

  /// No description provided for @legalPrivacyS5Title.
  ///
  /// In en, this message translates to:
  /// **'V. Your rights'**
  String get legalPrivacyS5Title;

  /// No description provided for @legalPrivacyS5P0.
  ///
  /// In en, this message translates to:
  /// **'You have rights to be informed and make decisions about your personal information, and to restrict or refuse processing, as follows:'**
  String get legalPrivacyS5P0;

  /// No description provided for @legalPrivacyS5P1.
  ///
  /// In en, this message translates to:
  /// **'1. Access and copies: You can view your account details and works directly on “Me”. To access or copy other information about you (such as audit log records), use the contact methods in Chapter IX.'**
  String get legalPrivacyS5P1;

  /// No description provided for @legalPrivacyS5P2.
  ///
  /// In en, this message translates to:
  /// **'2. Correction and supplementation: You can edit your nickname, account ID and biography in “Settings”. IP regions are determined automatically and cannot be edited manually; you may appeal if you disagree.'**
  String get legalPrivacyS5P2;

  /// No description provided for @legalPrivacyS5P3.
  ///
  /// In en, this message translates to:
  /// **'3. Deletion: You can delete your works (including those under review) on the work page at any time; their server files are also deleted. Submit other deletion requests through our contact methods. We will proactively delete information in statutory circumstances such as fulfillment of processing purposes, service cessation, withdrawal of consent or unlawful or contract-breaching processing by us. If a legally required retention period has not expired or deletion is technically difficult, we will stop all processing except storage and necessary security safeguards.'**
  String get legalPrivacyS5P3;

  /// No description provided for @legalPrivacyS5P4.
  ///
  /// In en, this message translates to:
  /// **'4. Withdrawal of consent: You can withdraw consent by revoking system permissions, deleting relevant information or deleting your account, or by contacting us. Withdrawal does not affect the validity of earlier processing based on consent. We will not deny functions unrelated to the matter for which consent is withdrawn.'**
  String get legalPrivacyS5P4;

  /// No description provided for @legalPrivacyS5P5.
  ///
  /// In en, this message translates to:
  /// **'5. Explanations: You may ask us to explain this Policy and the rules for processing personal information.'**
  String get legalPrivacyS5P5;

  /// No description provided for @legalPrivacyS5P6.
  ///
  /// In en, this message translates to:
  /// **'6. Rights of a deceased user\'s close relatives: For their own lawful and legitimate interests, close relatives may, with proof of death and kinship, use the contact methods in Chapter IX to exercise access, copying, correction, deletion and other rights concerning the deceased user\'s personal information, unless the deceased arranged otherwise during their lifetime.'**
  String get legalPrivacyS5P6;

  /// No description provided for @legalPrivacyS5P7.
  ///
  /// In en, this message translates to:
  /// **'7. Response time: After verifying your identity, we respond within 15 working days. We will explain any refusal. You may complain or report to cyberspace authorities (www.12377.cn) or telecommunications authorities (www.12321.cn), or bring proceedings in a people\'s court under law.'**
  String get legalPrivacyS5P7;

  /// No description provided for @legalPrivacyS6Title.
  ///
  /// In en, this message translates to:
  /// **'VI. Account deletion'**
  String get legalPrivacyS6Title;

  /// No description provided for @legalPrivacyS6P0.
  ///
  /// In en, this message translates to:
  /// **'You can delete your account at any time in “Settings → Account”, without manual review or preconditions.'**
  String get legalPrivacyS6P0;

  /// No description provided for @legalPrivacyS6P1.
  ///
  /// In en, this message translates to:
  /// **'After deletion: Your account details, works, like and report records are deleted; view records are anonymized. Security audit logs are retained for the periods in Chapter IV and then automatically deleted; sealed copies of lawfully removed works are handled under Chapter IV, paragraph 3. We do not retain your phone number or email for any other purpose.'**
  String get legalPrivacyS6P1;

  /// No description provided for @legalPrivacyS6P2.
  ///
  /// In en, this message translates to:
  /// **'Account deletion is irreversible. Back up any works you want to keep before proceeding. Deletion is completed within 15 working days.'**
  String get legalPrivacyS6P2;

  /// No description provided for @legalPrivacyS7Title.
  ///
  /// In en, this message translates to:
  /// **'VII. Protection of minors'**
  String get legalPrivacyS7Title;

  /// No description provided for @legalPrivacyS7P0.
  ///
  /// In en, this message translates to:
  /// **'The Product is only for users aged 14 or older. Minors under 14 may not register for or use it.'**
  String get legalPrivacyS7P0;

  /// No description provided for @legalPrivacyS7P1.
  ///
  /// In en, this message translates to:
  /// **'We do not knowingly collect personal information from minors under 14. If discovered, we will immediately delete the information and the relevant account.'**
  String get legalPrivacyS7P1;

  /// No description provided for @legalPrivacyS7P2.
  ///
  /// In en, this message translates to:
  /// **'Users aged 14 to under 18 must read and agree to this Policy under a guardian\'s guidance. Guardians who object to a minor\'s use or discover issues with a minor\'s personal information may contact us through Chapter IX; we will give these matters priority.'**
  String get legalPrivacyS7P2;

  /// No description provided for @legalPrivacyS7P3.
  ///
  /// In en, this message translates to:
  /// **'Reports involving minors receive the highest priority in content governance.'**
  String get legalPrivacyS7P3;

  /// No description provided for @legalPrivacyS8Title.
  ///
  /// In en, this message translates to:
  /// **'VIII. Policy updates'**
  String get legalPrivacyS8Title;

  /// No description provided for @legalPrivacyS8P0.
  ///
  /// In en, this message translates to:
  /// **'This Policy may be revised from time to time. We will prominently notify you in the app, such as by an announcement, and update the version number and effective date at the beginning.'**
  String get legalPrivacyS8P0;

  /// No description provided for @legalPrivacyS8P1.
  ///
  /// In en, this message translates to:
  /// **'If processing purposes, processing methods or types of personal information processed change, we will obtain your consent again rather than continue by default.'**
  String get legalPrivacyS8P1;

  /// No description provided for @legalPrivacyS8P2.
  ///
  /// In en, this message translates to:
  /// **'We retain previous versions of this Policy. You may request them through the contact methods in Chapter IX.'**
  String get legalPrivacyS8P2;

  /// No description provided for @legalPrivacyS9Title.
  ///
  /// In en, this message translates to:
  /// **'IX. How to contact us'**
  String get legalPrivacyS9Title;

  /// No description provided for @legalPrivacyS9P0.
  ///
  /// In en, this message translates to:
  /// **'Personal information processor: 【公司名称待注册后填写】'**
  String get legalPrivacyS9P0;

  /// No description provided for @legalPrivacyS9P1.
  ///
  /// In en, this message translates to:
  /// **'Registered address: 【公司注册地待定后填写】'**
  String get legalPrivacyS9P1;

  /// No description provided for @legalPrivacyS9P2.
  ///
  /// In en, this message translates to:
  /// **'Personal information protection officer email: 【联系邮箱待填写 —— 上线前必须替换为真实可达邮箱,与平台公约页同一个】'**
  String get legalPrivacyS9P2;

  /// No description provided for @legalPrivacyS9P3.
  ///
  /// In en, this message translates to:
  /// **'We reply within 15 working days after verifying your identity. If dissatisfied, you may complain or report to cyberspace, telecommunications, public security, market regulation or other authorities, or bring proceedings in a people\'s court under law.'**
  String get legalPrivacyS9P3;

  /// No description provided for @legalAgreementS0Title.
  ///
  /// In en, this message translates to:
  /// **'I. Introduction'**
  String get legalAgreementS0Title;

  /// No description provided for @legalAgreementS0P0.
  ///
  /// In en, this message translates to:
  /// **'Welcome to “方寸间”. This Agreement is between you and 【公司名称待注册后填写】 (“we” or the “Platform”) concerning use of the 方寸间 software and related services. Please read it in full before registration, especially the bold terms on exclusions or limitations of liability, licenses of rights and dispute jurisdiction.'**
  String get legalAgreementS0P0;

  /// No description provided for @legalAgreementS0P1.
  ///
  /// In en, this message translates to:
  /// **'The 方寸间 Platform Rules (including account management rules) and 方寸间 Privacy Policy form integral parts of this Agreement and have equal effect. Accepting this Agreement constitutes acceptance of those documents as well.'**
  String get legalAgreementS0P1;

  /// No description provided for @legalAgreementS0P2.
  ///
  /// In en, this message translates to:
  /// **'By clicking confirmation, completing registration or actually using the Service, you indicate that you have read and agree to this Agreement. If you disagree, do not register for or use it.'**
  String get legalAgreementS0P2;

  /// No description provided for @legalAgreementS0P3.
  ///
  /// In en, this message translates to:
  /// **'This Agreement is written in Chinese, and the Chinese text prevails. Any interface translation is provided solely for reading convenience.'**
  String get legalAgreementS0P3;

  /// No description provided for @legalAgreementS1Title.
  ///
  /// In en, this message translates to:
  /// **'II. Description of the Service'**
  String get legalAgreementS1Title;

  /// No description provided for @legalAgreementS1P0.
  ///
  /// In en, this message translates to:
  /// **'方寸间 is a 3D spatial content tool and community: you capture with your phone, reconstruct 3D point cloud works on the device, and may choose to publish them to the community to share with other users.'**
  String get legalAgreementS1P0;

  /// No description provided for @legalAgreementS1P1.
  ///
  /// In en, this message translates to:
  /// **'The Product\'s 3D reconstruction uses deep synthesis technology (3D reconstruction based on AI models). Under the Provisions on the Administration of Deep Synthesis in Internet Information Services, we prominently remind you: when using the Service to produce or publish information content, you must fulfill information security obligations under law. You must not use it to produce, copy, publish or distribute information prohibited by laws and regulations, or for activities endangering national security or interests, damaging the national image, harming public interests, disrupting economic or social order or infringing others\' lawful rights and interests.'**
  String get legalAgreementS1P1;

  /// No description provided for @legalAgreementS1P2.
  ///
  /// In en, this message translates to:
  /// **'Under those provisions, the Platform applies technical identifiers to published work files (an identifier of the generation method is embedded in the model file). You must not remove, alter or conceal it.'**
  String get legalAgreementS1P2;

  /// No description provided for @legalAgreementS1P3.
  ///
  /// In en, this message translates to:
  /// **'The Service\'s specific form (functions, interface and rules) may change as the Product evolves. Changes affecting your material rights and interests follow the procedure in Chapter XII.'**
  String get legalAgreementS1P3;

  /// No description provided for @legalAgreementS1P4.
  ///
  /// In en, this message translates to:
  /// **'We grant you a personal, nontransferable, nonsublicensable, nonexclusive license to download, install and use this software for noncommercial purposes.'**
  String get legalAgreementS1P4;

  /// No description provided for @legalAgreementS1P5.
  ///
  /// In en, this message translates to:
  /// **'Obtain the software through official channels, such as the App Store. Versions from unofficial channels may pose security risks; you bear the resulting consequences.'**
  String get legalAgreementS1P5;

  /// No description provided for @legalAgreementS1P6.
  ///
  /// In en, this message translates to:
  /// **'You bear the costs of devices and network data needed to use the Service.'**
  String get legalAgreementS1P6;

  /// No description provided for @legalAgreementS1P7.
  ///
  /// In en, this message translates to:
  /// **'The Service is provided to users in mainland People\'s Republic of China. We do not guarantee its availability or suitability in other jurisdictions.'**
  String get legalAgreementS1P7;

  /// No description provided for @legalAgreementS2Title.
  ///
  /// In en, this message translates to:
  /// **'III. Account registration and management'**
  String get legalAgreementS2Title;

  /// No description provided for @legalAgreementS2P0.
  ///
  /// In en, this message translates to:
  /// **'1. Age: You must be at least 14 to register for and use the Service. If under 18, you must also read this Agreement with a guardian and obtain their consent.'**
  String get legalAgreementS2P0;

  /// No description provided for @legalAgreementS2P1.
  ///
  /// In en, this message translates to:
  /// **'2. Real identity verification: Registration requires real identity verification based on a mobile phone number as required by law. Without verification, you cannot register or use information publishing functions such as publishing and liking.'**
  String get legalAgreementS2P1;

  /// No description provided for @legalAgreementS2P2.
  ///
  /// In en, this message translates to:
  /// **'3. Account information: Your nickname, account ID, biography and other account information must comply with laws, regulations and the Platform Rules. You must not impersonate, imitate or maliciously associate with Party, government or military bodies, enterprises, institutions, news media or public figures, or use names likely to be mistaken for official Platform identities. Names containing words such as “中国” or “国家”, or involving national flag or emblem identifiers, are subject to strict verification under national rules; the Platform may request supporting documents or reject them.'**
  String get legalAgreementS2P2;

  /// No description provided for @legalAgreementS2P3.
  ///
  /// In en, this message translates to:
  /// **'4. Ownership and security: Accounts are for your personal use only. Without the Platform\'s written consent, you must not give, lend, rent, transfer, sell or bequeath an account, or otherwise permit others to use it. All actions through your account are treated as yours, with corresponding responsibility borne by you. Safeguard your sign-in credentials. If your account is impersonated or stolen, notify the Platform immediately through Chapter XIV; protective measures such as temporary freezing may be taken as appropriate. You bear losses caused by inadequate safekeeping, except those caused by the Platform.'**
  String get legalAgreementS2P3;

  /// No description provided for @legalAgreementS2P4.
  ///
  /// In en, this message translates to:
  /// **'5. Account deletion: You may delete your account at any time in “Settings → Account”. See the 方寸间 Privacy Policy for the process and data handling.'**
  String get legalAgreementS2P4;

  /// No description provided for @legalAgreementS3Title.
  ///
  /// In en, this message translates to:
  /// **'IV. User conduct'**
  String get legalAgreementS3Title;

  /// No description provided for @legalAgreementS3P0.
  ///
  /// In en, this message translates to:
  /// **'1. You must not use the Service to produce, copy, publish or distribute information that: opposes the basic principles established by the Constitution; endangers national security, discloses state secrets, subverts state power or undermines national unity; harms national honor or interests; distorts, vilifies, desecrates or denies the deeds and spirit of heroes and martyrs; promotes terrorism or extremism or incites terrorist or extremist activities; incites ethnic hatred or discrimination or undermines ethnic unity; undermines national religious policy or promotes cults or feudal superstition; spreads rumors or disrupts economic or social order; spreads obscenity, pornography, gambling, violence, murder or terror, or instigates crime; insults or defames others or infringes their reputation, privacy or other lawful rights and interests; or contains other content prohibited by laws or administrative regulations.'**
  String get legalAgreementS3P0;

  /// No description provided for @legalAgreementS3P1.
  ///
  /// In en, this message translates to:
  /// **'2. You should guard against and resist producing, copying or publishing harmful information that: uses exaggerated headlines seriously inconsistent with content; sensationalizes gossip, scandals or misconduct; inappropriately comments on disasters such as natural disasters or major accidents; contains sexual innuendo or provocation likely to evoke sexual associations; depicts bloodshed, horror or cruelty causing physical or psychological discomfort; incites discrimination against groups or regions; promotes vulgar, coarse or pandering content; may encourage minors to imitate unsafe acts or acts against public morality or develop harmful habits; or otherwise adversely affects the online environment.'**
  String get legalAgreementS3P1;

  /// No description provided for @legalAgreementS3P2.
  ///
  /// In en, this message translates to:
  /// **'3. Special rules for 3D works: Before capturing and publicly publishing reconstructions of nonpublic spaces such as others\' homes or offices, obtain the rights holder\'s consent. If a specific other person is identifiable in images or point clouds, obtain that person\'s consent. Do not publish reconstructions of national security sensitive areas, military facilities or other places where surveying or photography is prohibited by laws and regulations.'**
  String get legalAgreementS3P2;

  /// No description provided for @legalAgreementS3P3.
  ///
  /// In en, this message translates to:
  /// **'4. You must not: use technical means to register accounts in bulk; reverse engineer, crack or bypass the Product\'s technical protections (except as permitted by laws and regulations); scrape, download or copy other users\' works without authorization for use outside the Service; use automation to call the Service at high frequency or collect data; interfere with or disrupt normal operation; create or distribute viruses, Trojans or other malware, or access Platform systems or others\' accounts without authorization; publish spam or malicious marketing; act in the Platform\'s name or mislead others by claiming cooperation, agency or similar relations with it.'**
  String get legalAgreementS3P3;

  /// No description provided for @legalAgreementS3P4.
  ///
  /// In en, this message translates to:
  /// **'5. 3D capture requires moving around on site. Be aware of your surroundings and your own and others\' safety. Do not capture in dangerous places such as roads or edges at heights.'**
  String get legalAgreementS3P4;

  /// No description provided for @legalAgreementS4Title.
  ///
  /// In en, this message translates to:
  /// **'V. Content publishing and review'**
  String get legalAgreementS4Title;

  /// No description provided for @legalAgreementS4P0.
  ///
  /// In en, this message translates to:
  /// **'1. Review before publication: Works you submit must pass Platform review before appearing in the community. During review, they are invisible to other users and you may delete them at any time.'**
  String get legalAgreementS4P0;

  /// No description provided for @legalAgreementS4P1.
  ///
  /// In en, this message translates to:
  /// **'2. Publication is public: Once approved, the work\'s content, your nickname, account ID and IP region at publication are publicly visible to all users, including visitors who are not signed in. IP region display is legally required and cannot be disabled; see the 方寸间 Privacy Policy.'**
  String get legalAgreementS4P1;

  /// No description provided for @legalAgreementS4P2.
  ///
  /// In en, this message translates to:
  /// **'3. “Content” in this Agreement includes 3D point cloud models, reconstruction data, thumbnails, titles, descriptions, account details and any other information you upload or publish through the Service.'**
  String get legalAgreementS4P2;

  /// No description provided for @legalAgreementS4P3.
  ///
  /// In en, this message translates to:
  /// **'4. You independently bear all legal responsibility for your published content. You warrant that you have lawful rights or authorization for it. If third-party claims arising from your content cause losses to the Platform, you must compensate it.'**
  String get legalAgreementS4P3;

  /// No description provided for @legalAgreementS4P4.
  ///
  /// In en, this message translates to:
  /// **'5. If a third party asserts rights against your content, the Platform may lawfully remove it first and notify you. You may appeal through Chapter VIII by submitting a noninfringement statement and proof of rights.'**
  String get legalAgreementS4P4;

  /// No description provided for @legalAgreementS5Title.
  ///
  /// In en, this message translates to:
  /// **'VI. Intellectual property'**
  String get legalAgreementS5Title;

  /// No description provided for @legalAgreementS5P0.
  ///
  /// In en, this message translates to:
  /// **'1. Intellectual property in the Platform software and its interface designs, code, trademarks and identifiers belongs to us or the relevant rights holders. Without permission, you must not copy, modify, distribute or use it for any commercial purpose.'**
  String get legalAgreementS5P0;

  /// No description provided for @legalAgreementS5P1.
  ///
  /// In en, this message translates to:
  /// **'2. Intellectual property in works you publish through the Service (including 3D point cloud models and derived thumbnails) remains with you or the lawful rights holder and does not transfer through publication.'**
  String get legalAgreementS5P1;

  /// No description provided for @legalAgreementS5P2.
  ///
  /// In en, this message translates to:
  /// **'3. To provide the Service and improve the Product, you grant the Platform a worldwide, royalty-free, nonexclusive license including rights to reproduce, disseminate over information networks, adapt, compile and display content, and create derivative content. Here, content means what you upload to the Service, including works published to the community and content stored through future cloud storage functions, including 3D point clouds, mesh models, thumbnails, titles and descriptions. These rights are used only for: (1) operational necessities: storage, backup, transmission, distribution, public display (only content you choose to publish publicly), format adaptation and other technical processing, which may be entrusted to cloud providers bound by this Agreement; (2) displaying and promoting your publicly published works in the Product\'s versions across devices and on app store pages; (3) our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction), using technologies and forms now known or developed later.'**
  String get legalAgreementS5P2;

  /// No description provided for @legalAgreementS5P3.
  ///
  /// In en, this message translates to:
  /// **'4. Providing research data externally: For research data provided in academic papers, public datasets or research collaborations, we use only anonymized data that cannot identify you and cannot be restored. If provision in an identifiable form is needed, we will obtain your separate consent.'**
  String get legalAgreementS5P3;

  /// No description provided for @legalAgreementS5P4.
  ///
  /// In en, this message translates to:
  /// **'5. License duration and termination: The license takes effect when content is uploaded. After you delete the relevant content or delete your account (meaning you voluntarily request deletion of your account and its personal information under Chapter III, paragraph 5 and Chapter VI of the 方寸间 Privacy Policy), the license terminates unless laws, regulations or this Agreement provide otherwise (such as sealed retention of lawfully removed content). We will stop using that content in new research and model training; research results already completed and models already trained are unaffected.'**
  String get legalAgreementS5P4;

  /// No description provided for @legalAgreementS5P5.
  ///
  /// In en, this message translates to:
  /// **'6. To better protect your rights, you agree that the Platform may itself, or through a third party, enforce rights against third-party infringement of content you upload and publish in which you hold intellectual property. Measures include monitoring infringement, sending enforcement letters, bringing litigation or arbitration, mediation and settlement. You may withdraw this enforcement authorization at any time by written notice to the Platform.'**
  String get legalAgreementS5P5;

  /// No description provided for @legalAgreementS5P6.
  ///
  /// In en, this message translates to:
  /// **'7. If you believe content in the Service infringes your lawful rights and interests, notify us through Chapter VIII with proof of ownership and preliminary evidence of infringement. We will handle it promptly under law.'**
  String get legalAgreementS5P6;

  /// No description provided for @legalAgreementS5P7.
  ///
  /// In en, this message translates to:
  /// **'8. The Platform holds rights, to the extent permitted by laws and regulations, in data and results generated in developing and operating the Service that do not include your work content itself (such as statistics, logs, anonymized analyses, algorithm and model parameters and research results). This does not alter work ownership under paragraph 2.'**
  String get legalAgreementS5P7;

  /// No description provided for @legalAgreementS6Title.
  ///
  /// In en, this message translates to:
  /// **'VII. Enforcement and appeals'**
  String get legalAgreementS6Title;

  /// No description provided for @legalAgreementS6P0.
  ///
  /// In en, this message translates to:
  /// **'1. If you violate this Agreement, Platform Rules or laws and regulations, the Platform may, according to severity and under law and this Agreement, take one or more measures: warnings, correction deadlines, account restrictions, suspension, account closure or prohibition on re-registration. Violating works are removed and their files taken out of public locations.'**
  String get legalAgreementS6P0;

  /// No description provided for @legalAgreementS6P1.
  ///
  /// In en, this message translates to:
  /// **'2. When taking these measures, the Platform informs you of the reasons through in-app notices or other means. It retains relevant records and reports to competent authorities as required by law.'**
  String get legalAgreementS6P1;

  /// No description provided for @legalAgreementS6P2.
  ///
  /// In en, this message translates to:
  /// **'3. Appeals: If you disagree with an outcome, appeal through Chapter XIV with explanations and evidence. We review and reply within 15 working days of receipt.'**
  String get legalAgreementS6P2;

  /// No description provided for @legalAgreementS6P3.
  ///
  /// In en, this message translates to:
  /// **'4. The Platform will progressively establish an account credit management system under national rules and provide corresponding services based on account credit.'**
  String get legalAgreementS6P3;

  /// No description provided for @legalAgreementS7Title.
  ///
  /// In en, this message translates to:
  /// **'VIII. Complaints and reports'**
  String get legalAgreementS7Title;

  /// No description provided for @legalAgreementS7P0.
  ///
  /// In en, this message translates to:
  /// **'1. Each work page provides a report option. You may also complain about or report unlawful or violating content or conduct through Chapter XIV.'**
  String get legalAgreementS7P0;

  /// No description provided for @legalAgreementS7P1.
  ///
  /// In en, this message translates to:
  /// **'2. We maintain a public complaint and report handling mechanism to accept and handle reports promptly. Reports involving minors receive priority. On notification by a minor or guardian of cyberbullying content, we promptly take necessary measures such as deletion or blocking.'**
  String get legalAgreementS7P1;

  /// No description provided for @legalAgreementS8Title.
  ///
  /// In en, this message translates to:
  /// **'IX. Changes, interruptions and termination'**
  String get legalAgreementS8Title;

  /// No description provided for @legalAgreementS8P0.
  ///
  /// In en, this message translates to:
  /// **'1. The Platform may change or interrupt some or all services because of changes in laws and regulations, regulatory requirements, technical upgrades or operational adjustments. For interruptions caused by maintenance, failures or force majeure, it will make reasonable efforts to restore service promptly.'**
  String get legalAgreementS8P0;

  /// No description provided for @legalAgreementS8P1.
  ///
  /// In en, this message translates to:
  /// **'2. If the Platform decides to cease all service operations, it will announce this in the app 30 days in advance and provide a work file export channel before closure. We also recommend regularly backing up important works yourself.'**
  String get legalAgreementS8P1;

  /// No description provided for @legalAgreementS8P2.
  ///
  /// In en, this message translates to:
  /// **'3. If a merger, division, acquisition or similar event requires transfer to a successor, the Platform will notify you under law. The successor remains bound by this Agreement and the 方寸间 Privacy Policy; otherwise your consent will be obtained again.'**
  String get legalAgreementS8P2;

  /// No description provided for @legalAgreementS8P3.
  ///
  /// In en, this message translates to:
  /// **'4. After termination, the Platform deletes or anonymizes your personal information under the 方寸间 Privacy Policy.'**
  String get legalAgreementS8P3;

  /// No description provided for @legalAgreementS8P4.
  ///
  /// In en, this message translates to:
  /// **'5. The Platform may entrust some operational or technical support work to affiliates or professional providers, while remaining responsible to you under this Agreement.'**
  String get legalAgreementS8P4;

  /// No description provided for @legalAgreementS9Title.
  ///
  /// In en, this message translates to:
  /// **'X. Disclaimers and limitation of liability'**
  String get legalAgreementS9Title;

  /// No description provided for @legalAgreementS9P0.
  ///
  /// In en, this message translates to:
  /// **'1. The Service is provided “as is” and “as available”. To the extent permitted by law, the Platform does not guarantee uninterrupted, error-free or completely secure service. Reconstruction quality depends on capture conditions, device performance and other factors; results are not guaranteed to meet your particular expectations. The Product\'s 3D reconstruction uses AI technology, which currently has limitations difficult to avoid entirely; results may contain errors, omissions or distortion.'**
  String get legalAgreementS9P0;

  /// No description provided for @legalAgreementS9P1.
  ///
  /// In en, this message translates to:
  /// **'2. To the extent permitted by law, the Platform is not liable for losses caused by force majeure (such as natural disasters, strikes, network infrastructure failures or regulatory policy changes), third parties (such as basic telecommunications interruptions or third-party provider failures), or your own actions.'**
  String get legalAgreementS9P1;

  /// No description provided for @legalAgreementS9P2.
  ///
  /// In en, this message translates to:
  /// **'3. To the maximum extent permitted by law, the Platform is not liable for indirect, consequential or punitive losses. Its total liability to you for the services under this Agreement does not exceed the total fees you actually paid it for the Service (the Service is currently free, in which case liability is limited to actual losses as prescribed by law). This does not apply to damage caused by the Platform\'s intent or gross negligence or exclude liability that cannot lawfully be excluded.'**
  String get legalAgreementS9P2;

  /// No description provided for @legalAgreementS9P3.
  ///
  /// In en, this message translates to:
  /// **'4. Other users\' content represents their views, not the Platform\'s. You may request assistance under this Agreement with disputes between users, but the Platform does not bear the parties\' civil liability. Assess the suitability of content and files obtained through the Service yourself and bear the risks of use. Third-party links or content, if present, are not controlled by the Platform, which is not responsible for their accuracy or security.'**
  String get legalAgreementS9P3;

  /// No description provided for @legalAgreementS9P4.
  ///
  /// In en, this message translates to:
  /// **'5. The Platform reviews published content under law. Review is no guarantee or endorsement of legality, truthfulness or quality, and does not exempt publishers from legal responsibility.'**
  String get legalAgreementS9P4;

  /// No description provided for @legalAgreementS9P5.
  ///
  /// In en, this message translates to:
  /// **'6. If the Platform\'s violation of laws, regulations or this Agreement causes you loss, it bears corresponding liability under law. If your violation causes loss to the Platform or third parties, you likewise bear liability under law.'**
  String get legalAgreementS9P5;

  /// No description provided for @legalAgreementS10Title.
  ///
  /// In en, this message translates to:
  /// **'XI. Minors'**
  String get legalAgreementS10Title;

  /// No description provided for @legalAgreementS10P0.
  ///
  /// In en, this message translates to:
  /// **'1. The Service is only for users aged 14 or older. Minors under 14 may not register or use it.'**
  String get legalAgreementS10P0;

  /// No description provided for @legalAgreementS10P1.
  ///
  /// In en, this message translates to:
  /// **'2. Users aged 14 to under 18 must obtain a guardian\'s consent and use the Service under their guidance. Guardians who have not consented may notify the Platform through Chapter XIV; it will handle the relevant account under law.'**
  String get legalAgreementS10P1;

  /// No description provided for @legalAgreementS10P2.
  ///
  /// In en, this message translates to:
  /// **'3. The Platform does not create or push content that induces addiction in minors or provide inducement-based tipping or spending functions. Content that may affect minors\' physical or mental health will be handled under law.'**
  String get legalAgreementS10P2;

  /// No description provided for @legalAgreementS10P3.
  ///
  /// In en, this message translates to:
  /// **'4. Obtain a minor\'s guardian\'s consent as required by law before publishing works depicting that minor.'**
  String get legalAgreementS10P3;

  /// No description provided for @legalAgreementS11Title.
  ///
  /// In en, this message translates to:
  /// **'XII. Amendments and notices'**
  String get legalAgreementS11Title;

  /// No description provided for @legalAgreementS11P0.
  ///
  /// In en, this message translates to:
  /// **'1. We may amend this Agreement because of changes in laws, regulations, regulatory requirements or the Service. Amendments will be displayed in the app at least 7 days before taking effect; amendments materially affecting your rights and obligations will be displayed for at least 15 days.'**
  String get legalAgreementS11P0;

  /// No description provided for @legalAgreementS11P1.
  ///
  /// In en, this message translates to:
  /// **'2. If you disagree, you may stop using the Service and delete your account; rights and obligations before deletion follow the previous Agreement. Continued use after the notice period constitutes acceptance of the amended Agreement. We will not make acceptance of amendments a preselected option.'**
  String get legalAgreementS11P1;

  /// No description provided for @legalAgreementS11P2.
  ///
  /// In en, this message translates to:
  /// **'3. We retain previous versions of this Agreement, available on request through Chapter XIV.'**
  String get legalAgreementS11P2;

  /// No description provided for @legalAgreementS11P3.
  ///
  /// In en, this message translates to:
  /// **'4. Platform notices may be given through in-app announcements, system notifications, page prompts or your linked phone number or email, and are deemed delivered on publication or sending. Notices from you to the Platform should use the contact methods published in Chapter XIV.'**
  String get legalAgreementS11P3;

  /// No description provided for @legalAgreementS12Title.
  ///
  /// In en, this message translates to:
  /// **'XIII. Governing law and dispute resolution'**
  String get legalAgreementS12Title;

  /// No description provided for @legalAgreementS12P0.
  ///
  /// In en, this message translates to:
  /// **'1. The formation, validity, interpretation and dispute resolution of this Agreement are governed by the laws of the People\'s Republic of China (excluding Hong Kong, Macao and Taiwan for this Agreement).'**
  String get legalAgreementS12P0;

  /// No description provided for @legalAgreementS12P1.
  ///
  /// In en, this message translates to:
  /// **'2. Disputes should first be resolved through friendly consultation. If unsuccessful, either party may bring proceedings in a people\'s court with jurisdiction in 【公司注册地待定后填写】.'**
  String get legalAgreementS12P1;

  /// No description provided for @legalAgreementS12P2.
  ///
  /// In en, this message translates to:
  /// **'3. Invalidity or unenforceability of a term does not affect the remaining terms.'**
  String get legalAgreementS12P2;

  /// No description provided for @legalAgreementS12P3.
  ///
  /// In en, this message translates to:
  /// **'4. Headings are for reading convenience only and are not a basis for interpreting terms.'**
  String get legalAgreementS12P3;

  /// No description provided for @legalAgreementS12P4.
  ///
  /// In en, this message translates to:
  /// **'5. You and the Platform are independent entities. This Agreement creates no partnership, agency, employment or guarantee relationship between you.'**
  String get legalAgreementS12P4;

  /// No description provided for @legalAgreementS12P5.
  ///
  /// In en, this message translates to:
  /// **'6. This Agreement and its component documents constitute the entire agreement between the parties on the relevant matters.'**
  String get legalAgreementS12P5;

  /// No description provided for @legalAgreementS13Title.
  ///
  /// In en, this message translates to:
  /// **'XIV. Contact us'**
  String get legalAgreementS13Title;

  /// No description provided for @legalAgreementS13P0.
  ///
  /// In en, this message translates to:
  /// **'Operator: 【公司名称待注册后填写】'**
  String get legalAgreementS13P0;

  /// No description provided for @legalAgreementS13P1.
  ///
  /// In en, this message translates to:
  /// **'Contact email: 【联系邮箱待填写 —— 上线前必须替换为真实可达邮箱,与平台公约页、隐私政策同一个】'**
  String get legalAgreementS13P1;

  /// No description provided for @legalAgreementS13P2.
  ///
  /// In en, this message translates to:
  /// **'We handle and respond to your feedback, complaints or appeals within 15 working days of receipt.'**
  String get legalAgreementS13P2;

  /// No description provided for @legalRulesS0Title.
  ///
  /// In en, this message translates to:
  /// **'1. Accounts and Names'**
  String get legalRulesS0Title;

  /// No description provided for @legalRulesS0P0.
  ///
  /// In en, this message translates to:
  /// **'Display names may repeat; your ID is unique across the platform. Display names are for showing, IDs are for being found.'**
  String get legalRulesS0P0;

  /// No description provided for @legalRulesS0P1.
  ///
  /// In en, this message translates to:
  /// **'Display names allow up to 20 characters, including Chinese, English and emoji. Leading/trailing spaces are trimmed and internal runs of spaces are collapsed.'**
  String get legalRulesS0P1;

  /// No description provided for @legalRulesS0P2.
  ///
  /// In en, this message translates to:
  /// **'IDs consist of 2-32 lowercase letters, digits, dots or underscores. They may not start or end with a dot/underscore, nor contain consecutive ones.'**
  String get legalRulesS0P2;

  /// No description provided for @legalRulesS0P3.
  ///
  /// In en, this message translates to:
  /// **'A display name or ID cannot be changed again within 3 days of being set.'**
  String get legalRulesS0P3;

  /// No description provided for @legalRulesS0P4.
  ///
  /// In en, this message translates to:
  /// **'Names that could be mistaken for official platform identities are not permitted, including \"official\", \"support\", \"admin\", \"system\" and their Chinese equivalents.'**
  String get legalRulesS0P4;

  /// No description provided for @legalRulesS0P5.
  ///
  /// In en, this message translates to:
  /// **'Names containing national or party symbols are subject to stricter verification under applicable Chinese regulations.'**
  String get legalRulesS0P5;

  /// No description provided for @legalRulesS0P6.
  ///
  /// In en, this message translates to:
  /// **'Registration requires real-identity verification. Unverified accounts cannot publish.'**
  String get legalRulesS0P6;

  /// No description provided for @legalRulesS1Title.
  ///
  /// In en, this message translates to:
  /// **'2. Publishing and Review'**
  String get legalRulesS1Title;

  /// No description provided for @legalRulesS1P0.
  ///
  /// In en, this message translates to:
  /// **'Published works enter review and only appear in the community feed after approval. Until then they are not visible to others.'**
  String get legalRulesS1P0;

  /// No description provided for @legalRulesS1P1.
  ///
  /// In en, this message translates to:
  /// **'Titles are limited to 100 characters; descriptions to 30.'**
  String get legalRulesS1P1;

  /// No description provided for @legalRulesS1P2.
  ///
  /// In en, this message translates to:
  /// **'Content prohibited by law may not be published.'**
  String get legalRulesS1P2;

  /// No description provided for @legalRulesS1P3.
  ///
  /// In en, this message translates to:
  /// **'Obtain consent from people appearing in a scene before publishing it publicly.'**
  String get legalRulesS1P3;

  /// No description provided for @legalRulesS1P4.
  ///
  /// In en, this message translates to:
  /// **'Exported 3D model files carry a provenance marker, as required by Chinese regulations on deep synthesis services. It does not affect normal use of the file.'**
  String get legalRulesS1P4;

  /// No description provided for @legalRulesS2Title.
  ///
  /// In en, this message translates to:
  /// **'3. Enforcement'**
  String get legalRulesS2Title;

  /// No description provided for @legalRulesS2P0.
  ///
  /// In en, this message translates to:
  /// **'Available measures: warning, required correction within a period, feature restriction, suspension, account closure.'**
  String get legalRulesS2P0;

  /// No description provided for @legalRulesS2P1.
  ///
  /// In en, this message translates to:
  /// **'Violating works are taken down and their files removed from public storage; previously saved links stop working.'**
  String get legalRulesS2P1;

  /// No description provided for @legalRulesS2P2.
  ///
  /// In en, this message translates to:
  /// **'You may delete your own work at any time, including work still under review that was never public.'**
  String get legalRulesS2P2;

  /// No description provided for @legalRulesS2P3.
  ///
  /// In en, this message translates to:
  /// **'Account-related actions are logged and retained for at least 6 months.'**
  String get legalRulesS2P3;

  /// No description provided for @legalRulesS3Title.
  ///
  /// In en, this message translates to:
  /// **'4. Reporting and Appeals'**
  String get legalRulesS3Title;

  /// No description provided for @legalRulesS3P0.
  ///
  /// In en, this message translates to:
  /// **'Every work page provides a reporting entry with categories including spam, harassment, hate speech, sexual content, violence, copyright and misinformation.'**
  String get legalRulesS3P0;

  /// No description provided for @legalRulesS3P1.
  ///
  /// In en, this message translates to:
  /// **'You may also block a user; their works will no longer appear in your feed.'**
  String get legalRulesS3P1;

  /// No description provided for @legalRulesS3P2.
  ///
  /// In en, this message translates to:
  /// **'To appeal an enforcement decision, use the contact below.'**
  String get legalRulesS3P2;

  /// No description provided for @legalRulesS4Title.
  ///
  /// In en, this message translates to:
  /// **'5. Contact'**
  String get legalRulesS4Title;

  /// No description provided for @legalRulesS4P0.
  ///
  /// In en, this message translates to:
  /// **'Email: [TO BE FILLED — must be a real, reachable address before launch]'**
  String get legalRulesS4P0;

  /// No description provided for @legalRulesS4P1.
  ///
  /// In en, this message translates to:
  /// **'We respond to reports and appeals as promptly as we can.'**
  String get legalRulesS4P1;

  /// No description provided for @legalRulesFooter.
  ///
  /// In en, this message translates to:
  /// **'These rules describe how the product actually behaves today, and are updated when behaviour changes. In case of any discrepancy, the Chinese version prevails.'**
  String get legalRulesFooter;

  /// No description provided for @legalPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'方寸间 Privacy Policy'**
  String get legalPrivacyTitle;

  /// No description provided for @legalAgreementTitle.
  ///
  /// In en, this message translates to:
  /// **'方寸间 User Agreement'**
  String get legalAgreementTitle;

  /// No description provided for @legalVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get legalVersionLabel;

  /// No description provided for @legalEffectiveDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get legalEffectiveDateLabel;

  /// No description provided for @legalEffectiveDatePending.
  ///
  /// In en, this message translates to:
  /// **'[Effective date to be completed before launch]'**
  String get legalEffectiveDatePending;

  /// No description provided for @legalTranslationNotice.
  ///
  /// In en, this message translates to:
  /// **'The English translation is provided for reading convenience. The Chinese version of this document prevails.'**
  String get legalTranslationNotice;

  /// No description provided for @sharedViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'PocketWorld 3D Viewer'**
  String get sharedViewerTitle;

  /// No description provided for @sharedViewerCanvasLabel.
  ///
  /// In en, this message translates to:
  /// **'3D work'**
  String get sharedViewerCanvasLabel;

  /// No description provided for @sharedViewerInitializing.
  ///
  /// In en, this message translates to:
  /// **'Starting viewer…'**
  String get sharedViewerInitializing;

  /// No description provided for @sharedViewerLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get sharedViewerLoading;

  /// No description provided for @sharedViewerFailure.
  ///
  /// In en, this message translates to:
  /// **'Unable to display this work. Please try again.'**
  String get sharedViewerFailure;

  /// No description provided for @sharedViewerSkpNotice.
  ///
  /// In en, this message translates to:
  /// **'SKP preview: complex structures may look different.'**
  String get sharedViewerSkpNotice;

  /// No description provided for @legalStaticV11Copy0.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng Privacy Policy | 北京空也科技有限公司'**
  String get legalStaticV11Copy0;

  /// No description provided for @legalStaticV11Copy2.
  ///
  /// In en, this message translates to:
  /// **'Back to community'**
  String get legalStaticV11Copy2;

  /// No description provided for @legalStaticV11Copy3.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng Privacy Policy'**
  String get legalStaticV11Copy3;

  /// No description provided for @legalStaticV11Copy4.
  ///
  /// In en, this message translates to:
  /// **'V1.1 · Effective date: November 2, 2026'**
  String get legalStaticV11Copy4;

  /// No description provided for @legalStaticV11Copy9.
  ///
  /// In en, this message translates to:
  /// **'“Chuang Hou Cheng” (the “Product”) is operated by 北京空也科技有限公司 (“we” or “us”). This Policy explains how we collect, use, store and protect your personal information, and your rights and how to exercise them. Please read this Policy carefully before using the Product, especially the terms in bold.'**
  String get legalStaticV11Copy9;

  /// No description provided for @legalStaticV11Copy10.
  ///
  /// In en, this message translates to:
  /// **'① Original photos and motion sensor data during capture are used for on-device reconstruction. Private cloud backup and community publishing upload the final 3D models and related files you choose. Review images are rendered from models, not original capture photos;'**
  String get legalStaticV11Copy10;

  /// No description provided for @legalStaticV11Copy11.
  ///
  /// In en, this message translates to:
  /// **'③ We entrust 阿里云 with storage, communications and content review services; see Chapter III for the processing scope. Public publication does not remove obligations to protect personal information;'**
  String get legalStaticV11Copy11;

  /// No description provided for @legalStaticV11Copy12.
  ///
  /// In en, this message translates to:
  /// **'We process information in the following scenarios. Each item describes its purpose, method and retention period. Except for your phone number, all items are optional; refusing to provide them does not affect your use of other functions.'**
  String get legalStaticV11Copy12;

  /// No description provided for @legalStaticV11Copy13.
  ///
  /// In en, this message translates to:
  /// **'· Original photos: Saved in the Product\'s documents directory on your device. You can view, export or delete them using the system Files app. On-device reconstruction and the model backup and publication review processes described in this Policy do not require uploading these photos. Exporting them yourself or sharing them through other services is outside these processes.'**
  String get legalStaticV11Copy13;

  /// No description provided for @legalStaticV11Copy14.
  ///
  /// In en, this message translates to:
  /// **'· Final 3D works: Stored on your device if you do not choose cloud functions. If you choose private cloud backup or public publication, they are uploaded for the separate purposes below.'**
  String get legalStaticV11Copy14;

  /// No description provided for @legalStaticV11Copy15.
  ///
  /// In en, this message translates to:
  /// **'· Private cloud backup (optional): For retrieval, download and viewing, and protection against local loss. We store the final models you choose to back up (such as GLB mesh models and PLY point clouds, subject to formats currently supported), covers and work records needed for recovery. Backup is not publication and does not put works in the community or make them public to others. Retained until you delete the backup or your account; see Chapter IV for statutory retention and backup cleanup limitations.'**
  String get legalStaticV11Copy15;

  /// No description provided for @legalStaticV11Copy16.
  ///
  /// In en, this message translates to:
  /// **'· Work content (optional; necessary for publishing): Only when you actively choose public publication do we collect the final 3D model (including currently supported formats such as GLB mesh models and PLY point clouds), model-generated cover, title and description. Works remain nonpublic during submission and review, and are displayed publicly to all users, including visitors who are not signed in, only after approval and completion of publication.'**
  String get legalStaticV11Copy16;

  /// No description provided for @legalStaticV11Copy17.
  ///
  /// In en, this message translates to:
  /// **'· Publication review: To check for unlawful and harmful content, the Platform generates 26 review images from multiple angles of the submitted final GLB model. 阿里云 reviews the title and description as text and the 26 model-rendered images as images. These are not original capture photos; this review does not send capture process data, sign-in passwords or account contact details to 阿里云. Detected risks may be referred for manual checks, clear violations are rejected, and works remain nonpublic if the service fails or results are incomplete. Currently unsupported formats cannot automatically become public through this process; follow the page instructions. Review materials and results are retained and cleared under Chapter IV.'**
  String get legalStaticV11Copy17;

  /// No description provided for @legalStaticV11Copy18.
  ///
  /// In en, this message translates to:
  /// **'· When publishing, you acknowledge that once the work is published and approved, its content, your nickname, account ID and IP region at publication will be visible to everyone. Public publication does not waive your privacy or personal information rights or replace authorization from other rights holders represented in the work.'**
  String get legalStaticV11Copy18;

  /// No description provided for @legalStaticV11Copy19.
  ///
  /// In en, this message translates to:
  /// **'· Research and technical improvement: The work content you upload will be used for our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction). When providing research data externally, we use only anonymized data that cannot identify you and cannot be restored, or obtain your separate consent. See Chapter VI of the Chuang Hou Cheng User Agreement.'**
  String get legalStaticV11Copy19;

  /// No description provided for @legalStaticV11Copy20.
  ///
  /// In en, this message translates to:
  /// **'Local storage: The Product has no embedded web browser and does not use cookies. The following is stored only on your device and will not be read by us for purposes not stated in this Policy: sign-in credentials (in the system keychain), language and interface preferences, temporary file caches from viewing others\' works (to speed loading, removable by the system), and original photos and reconstruction outputs you have not chosen to upload. Content you choose to back up or submit for publication is handled separately under Chapter I.'**
  String get legalStaticV11Copy20;

  /// No description provided for @legalStaticV11Copy21.
  ///
  /// In en, this message translates to:
  /// **'· Content review provider: 阿里云 content security services. To review works you actively submit for publication, the provider processes titles, descriptions and 26 review images generated from final models on our behalf, and returns risk labels and review results. This service does not receive original capture photos, complete 3D models, sign-in passwords or account contact details. We limit submissions to the review purpose and provide review images through private storage and short-lived authorized links; the images are not made into public community albums.'**
  String get legalStaticV11Copy21;

  /// No description provided for @legalStaticV11Copy22.
  ///
  /// In en, this message translates to:
  /// **'· Email provider: 阿里云邮件推送 (DirectMail), for email verification codes, account recovery and related notices, processing your email address and email content for the relevant sending purpose.'**
  String get legalStaticV11Copy22;

  /// No description provided for @legalStaticV11Copy23.
  ///
  /// In en, this message translates to:
  /// **'(2) Provision to other personal information processors: Except for the entrusted processing described above, your active public publication, fulfillment of legal obligations or separately obtained valid consent, we do not provide your personal information to other processors. Information anonymized so that it cannot identify a specific person and cannot be restored is not personal information under law. Only such anonymized data is used in our external research collaborations (see Chapter I(3)).'**
  String get legalStaticV11Copy23;

  /// No description provided for @legalStaticV11Copy24.
  ///
  /// In en, this message translates to:
  /// **'2. Retention periods: Chapter I lists each period. In summary: account details (phone/email/nickname/ID/biography) until account deletion; private backups, works and interaction records until deletion or account deletion, subject to statutory retention and backup cleanup limitations below; view records anonymized after account deletion; analytics events 180 days; security audit logs 180 days (major actions 730 days); API frequency records no more than 1 day; temporary registration verification data 10 minutes. Review models, images and results are kept only within the scope and for the periods needed for review, complaint and appeal handling, necessary security protection and statutory retention, not indefinitely for storage convenience; they are then deleted or anonymized. Statutory retention or technical difficulty in immediate deletion is subject to restricted processing as described below.'**
  String get legalStaticV11Copy24;

  /// No description provided for @legalStaticV11Copy25.
  ///
  /// In en, this message translates to:
  /// **'3. Deletion limitations and retention: After deletion or withdrawal, relevant works are no longer provided as public content. Review evidence, report and appeal materials, or necessary copies of lawfully removed works may not be physically deletable immediately because of statutory retention obligations, ongoing disputes or storage retention locks. We restrict their use and access and clear them after the relevant grounds and necessary retention periods end. Backup copies are cleared through backup rotation and deletion procedures. Recorded deletion requests must still be enforced when restoring backups; restoration must not republish content or return it to normal use. If a legally required retention period has not expired or deletion is technically difficult, we stop all processing except storage and necessary security safeguards.'**
  String get legalStaticV11Copy25;

  /// No description provided for @legalStaticV11Copy26.
  ///
  /// In en, this message translates to:
  /// **'3. Deletion: You may request deletion of your works (including those under review) on the work page, and request deletion of private cloud backups. We stop public or normal provision of relevant content, cancel pending publication processing and clear files. Review evidence, retention locks and historical backups do not mean immediate physical erasure; see Chapter IV, paragraph 3. Submit other deletion requests through our contact methods. We proactively delete information in statutory circumstances such as fulfillment of processing purposes, service cessation, withdrawal of consent or unlawful or contract-breaching processing by us. If a legally required retention period has not expired or deletion is technically difficult, we stop all processing except storage and necessary security safeguards.'**
  String get legalStaticV11Copy26;

  /// No description provided for @legalStaticV11Copy27.
  ///
  /// In en, this message translates to:
  /// **'Personal information processor: 北京空也科技有限公司'**
  String get legalStaticV11Copy27;

  /// No description provided for @legalStaticV11Copy28.
  ///
  /// In en, this message translates to:
  /// **'Business license domicile recorded in filing materials (province/city/district): Haidian District, Beijing'**
  String get legalStaticV11Copy28;

  /// No description provided for @legalStaticV11Copy29.
  ///
  /// In en, this message translates to:
  /// **'Personal information protection officer email: wkd20040211@163.com'**
  String get legalStaticV11Copy29;

  /// No description provided for @legalStaticV11Copy31.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng User Agreement | 北京空也科技有限公司'**
  String get legalStaticV11Copy31;

  /// No description provided for @legalStaticV11Copy32.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng User Agreement'**
  String get legalStaticV11Copy32;

  /// No description provided for @legalStaticV11Copy33.
  ///
  /// In en, this message translates to:
  /// **'Welcome to “Chuang Hou Cheng”. This Agreement is between you and 北京空也科技有限公司 (“we” or the “Platform”) concerning use of the Chuang Hou Cheng software and related services. Please read it in full before registration, especially the bold terms on exclusions or limitations of liability, licenses of rights and dispute jurisdiction.'**
  String get legalStaticV11Copy33;

  /// No description provided for @legalStaticV11Copy34.
  ///
  /// In en, this message translates to:
  /// **'The Chuang Hou Cheng Platform Rules (including account management rules) and Chuang Hou Cheng Privacy Policy form integral parts of this Agreement and have equal effect. Accepting this Agreement constitutes acceptance of those documents as well.'**
  String get legalStaticV11Copy34;

  /// No description provided for @legalStaticV11Copy35.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng is a 3D spatial content tool and community: you can reconstruct 3D works on your device or use final model files supported by current functions. Final models include GLB meshes and PLY point clouds; see the relevant function page for supported formats. You may separately choose private cloud backup or public publication; they are different operations.'**
  String get legalStaticV11Copy35;

  /// No description provided for @legalStaticV11Copy36.
  ///
  /// In en, this message translates to:
  /// **'5. Account deletion: You may delete your account at any time in “Settings → Account”. See the Chuang Hou Cheng Privacy Policy for the process and data handling.'**
  String get legalStaticV11Copy36;

  /// No description provided for @legalStaticV11Copy37.
  ///
  /// In en, this message translates to:
  /// **'1. Review before publication: Works you submit must pass Platform review before appearing in the community. During review, they are invisible to other users and you may request withdrawal or deletion. Uploading a private cloud backup does not automatically turn it into a public work.'**
  String get legalStaticV11Copy37;

  /// No description provided for @legalStaticV11Copy38.
  ///
  /// In en, this message translates to:
  /// **'Review method: For final GLB models, the Platform generates 26 model-rendered images from multiple angles and entrusts 阿里云 with text review of titles and descriptions and image review of review images. This process does not require original capture photos or capture process data. Risks detected by automated review may be referred for manual review; clear violations are rejected, and service failures or incomplete results do not lead to automatic public access. Currently unsupported formats cannot automatically become public through this process; changes to submitted work content require another review.'**
  String get legalStaticV11Copy38;

  /// No description provided for @legalStaticV11Copy39.
  ///
  /// In en, this message translates to:
  /// **'2. Publication is public: Once approved, the work\'s content, your nickname, account ID and IP region at publication are publicly visible to all users, including visitors who are not signed in. Public publication does not waive privacy or personal information rights or remove the publisher\'s duty to obtain others\' authorization. IP region display is legally required and cannot be disabled; see the Chuang Hou Cheng Privacy Policy.'**
  String get legalStaticV11Copy39;

  /// No description provided for @legalStaticV11Copy40.
  ///
  /// In en, this message translates to:
  /// **'3. “Content” in this Agreement includes 3D models (such as GLB meshes and PLY point clouds), reconstruction data, covers and derived review images, titles, descriptions, account details and any other information you upload or publish through the Service.'**
  String get legalStaticV11Copy40;

  /// No description provided for @legalStaticV11Copy41.
  ///
  /// In en, this message translates to:
  /// **'Deletion, withdrawal and evidence retention: Ending public access does not immediately physically erase all copies. Restricted processing and cleanup of review materials, complaint and appeal evidence, statutory retention and historical backups follow Chapter IV of the Chuang Hou Cheng Privacy Policy. Restoring backups must not republish relevant copies.'**
  String get legalStaticV11Copy41;

  /// No description provided for @legalStaticV11Copy42.
  ///
  /// In en, this message translates to:
  /// **'2. Intellectual property in works you upload or publish through the Service (including 3D point clouds, mesh models and derived covers and review images) remains with you or the lawful rights holder and does not transfer through publication.'**
  String get legalStaticV11Copy42;

  /// No description provided for @legalStaticV11Copy43.
  ///
  /// In en, this message translates to:
  /// **'3. To provide the Service and improve the Product, you grant the Platform a worldwide, royalty-free, nonexclusive license including rights to reproduce, disseminate over information networks, adapt, compile and display content, and create derivative content. Here, content means what you upload to the Service, including works published to the community and content stored through private cloud backup (cloud storage), including 3D point clouds, mesh models, covers, derived review images, titles and descriptions. These rights are used only for: (1) operational necessities: storage, backup, transmission, distribution, public display (only content you choose to publish publicly), format adaptation, review image generation, text and image content security checks and other technical processing, which may be entrusted to cloud and content review providers subject to binding obligations; (2) displaying and promoting your publicly published works in the Product\'s versions across devices and on app store pages; (3) our internal scientific research, technology development and improvement, including but not limited to training, evaluating and optimizing various AI algorithms and models (such as those related to 3D reconstruction), using technologies and forms now known or developed later.'**
  String get legalStaticV11Copy43;

  /// No description provided for @legalStaticV11Copy44.
  ///
  /// In en, this message translates to:
  /// **'5. License duration and termination: The license takes effect when content is uploaded. After you delete the relevant content or delete your account (meaning you voluntarily request deletion of your account and its personal information under Chapter III, paragraph 5 and Chapter VI of the Chuang Hou Cheng Privacy Policy), the license terminates unless laws, regulations or this Agreement provide otherwise (such as sealed retention of lawfully removed content). We will stop using that content in new research and model training; research results already completed and models already trained are unaffected.'**
  String get legalStaticV11Copy44;

  /// No description provided for @legalStaticV11Copy45.
  ///
  /// In en, this message translates to:
  /// **'3. If a merger, division, acquisition or similar event requires transfer to a successor, the Platform will notify you under law. The successor remains bound by this Agreement and the Chuang Hou Cheng Privacy Policy; otherwise your consent will be obtained again.'**
  String get legalStaticV11Copy45;

  /// No description provided for @legalStaticV11Copy46.
  ///
  /// In en, this message translates to:
  /// **'4. After termination, the Platform deletes or anonymizes your personal information under the Chuang Hou Cheng Privacy Policy.'**
  String get legalStaticV11Copy46;

  /// No description provided for @legalStaticV11Copy47.
  ///
  /// In en, this message translates to:
  /// **'2. Disputes should first be resolved through friendly consultation. If unsuccessful, either party may bring proceedings in a people\'s court with jurisdiction at the company\'s domicile.'**
  String get legalStaticV11Copy47;

  /// No description provided for @legalStaticV11Copy48.
  ///
  /// In en, this message translates to:
  /// **'Operator: 北京空也科技有限公司'**
  String get legalStaticV11Copy48;

  /// No description provided for @legalStaticV11Copy49.
  ///
  /// In en, this message translates to:
  /// **'Contact email: wkd20040211@163.com'**
  String get legalStaticV11Copy49;

  /// No description provided for @legalStaticV11Copy50.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng Platform Rules | 北京空也科技有限公司'**
  String get legalStaticV11Copy50;

  /// No description provided for @legalStaticV11Copy51.
  ///
  /// In en, this message translates to:
  /// **'Chuang Hou Cheng Platform Rules'**
  String get legalStaticV11Copy51;

  /// No description provided for @legalStaticV11Copy52.
  ///
  /// In en, this message translates to:
  /// **'Private cloud backup and public publication are separate: backups do not automatically enter the community. Active submissions enter review, and only appear in the community after approval and completion of publication; until then they are invisible to other users.'**
  String get legalStaticV11Copy52;

  /// No description provided for @legalStaticV11Copy53.
  ///
  /// In en, this message translates to:
  /// **'GLB publication review generates 26 rendered images from multiple angles of the final model. Titles, descriptions and these review images are reviewed by 阿里云 text and image review services. Review images are not original capture photos. Currently unsupported formats cannot automatically become public through this process.'**
  String get legalStaticV11Copy53;

  /// No description provided for @legalStaticV11Copy54.
  ///
  /// In en, this message translates to:
  /// **'Detected risks may be referred for manual checks, clear violations are returned, and service failures or incomplete results do not lead to automatic public access. Changes to work content require another review. Public publication does not waive privacy or others\' lawful rights and interests.'**
  String get legalStaticV11Copy54;

  /// No description provided for @legalStaticV11Copy55.
  ///
  /// In en, this message translates to:
  /// **'You may request withdrawal or deletion of your works, including works still under review that have never been public. Ending public access and physically clearing files are separate; see the Privacy Policy for restricted processing and cleanup of review evidence, dispute materials and historical backups.'**
  String get legalStaticV11Copy55;

  /// No description provided for @legalStaticV11Copy56.
  ///
  /// In en, this message translates to:
  /// **'Email: wkd20040211@163.com'**
  String get legalStaticV11Copy56;

  /// No description provided for @legalStaticV11Copy57.
  ///
  /// In en, this message translates to:
  /// **'3D publication and review | Chuang Hou Cheng'**
  String get legalStaticV11Copy57;

  /// No description provided for @legalStaticV11Copy58.
  ///
  /// In en, this message translates to:
  /// **'Published November 2, 2026 · V1.1'**
  String get legalStaticV11Copy58;

  /// No description provided for @legalStaticV11Copy59.
  ///
  /// In en, this message translates to:
  /// **'Private backup and public publication'**
  String get legalStaticV11Copy59;

  /// No description provided for @legalStaticV11Copy60.
  ///
  /// In en, this message translates to:
  /// **'Private cloud backups do not automatically become community works. Works enter the public community only when you actively submit them for public publication and they pass review.'**
  String get legalStaticV11Copy60;

  /// No description provided for @legalStaticV11Copy61.
  ///
  /// In en, this message translates to:
  /// **'What content review uses'**
  String get legalStaticV11Copy61;

  /// No description provided for @legalStaticV11Copy62.
  ///
  /// In en, this message translates to:
  /// **'Submitting for publication uploads the final GLB model, title and description. The cloud generates 26 review images from different angles of the same model and uses 阿里云 text and image review services to check the title, description and images. Review images are rendered from the model, not original capture photos; the complete model is not sent to the 阿里云 image review API.'**
  String get legalStaticV11Copy62;

  /// No description provided for @legalStaticV11Copy63.
  ///
  /// In en, this message translates to:
  /// **'The 26-view approach is the Product\'s current review method; it does not mean coverage of every model surface has been proven. Currently supported models are self-contained static GLB files within 50 MB. Unsupported models do not pass automatically.'**
  String get legalStaticV11Copy63;

  /// No description provided for @legalStaticV11Copy64.
  ///
  /// In en, this message translates to:
  /// **'Review outcomes and public access'**
  String get legalStaticV11Copy64;

  /// No description provided for @legalStaticV11Copy65.
  ///
  /// In en, this message translates to:
  /// **'Works may be displayed publicly after all review checks pass and publication conditions are met. Risky works receive manual handling. Blocked works, review errors, incomplete evidence and unsupported models do not lead to automatic public access. Replacing a model requires another review.'**
  String get legalStaticV11Copy65;

  /// No description provided for @legalStaticV11Copy66.
  ///
  /// In en, this message translates to:
  /// **'Visitors who are not signed in can view and share public works. Liking and commenting require sign-in. Examples under open licenses retain their material sources and licensing identities.'**
  String get legalStaticV11Copy66;

  /// No description provided for @legalStaticV11Copy67.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal, deletion and rights'**
  String get legalStaticV11Copy67;

  /// No description provided for @legalStaticV11Copy68.
  ///
  /// In en, this message translates to:
  /// **'You may withdraw public publication, request deletion, or submit reports and appeals. Review evidence, dispute handling, statutory retention and historical backups follow the Privacy Policy and actual retention mechanisms. Public publication does not remove your or others\' personal information rights and interests.'**
  String get legalStaticV11Copy68;

  /// No description provided for @legalStaticV11Copy69.
  ///
  /// In en, this message translates to:
  /// **'Operation and contact'**
  String get legalStaticV11Copy69;

  /// No description provided for @legalStaticV11Copy70.
  ///
  /// In en, this message translates to:
  /// **'Operator: 北京空也科技有限公司'**
  String get legalStaticV11Copy70;

  /// No description provided for @legalStaticPrivacyIntro.
  ///
  /// In en, this message translates to:
  /// **'This page publishes the Chuang Hou Cheng app Privacy Policy. Before publishing works publicly, please also read '**
  String get legalStaticPrivacyIntro;

  /// No description provided for @legalStaticTermsIntro.
  ///
  /// In en, this message translates to:
  /// **'This page publishes the Chuang Hou Cheng app User Agreement. Before publishing works publicly, please also read '**
  String get legalStaticTermsIntro;

  /// No description provided for @legalStaticRulesIntro.
  ///
  /// In en, this message translates to:
  /// **'This page publishes the Chuang Hou Cheng app Platform Rules. Before publishing works publicly, please also read '**
  String get legalStaticRulesIntro;

  /// No description provided for @legalStaticContactPrefix.
  ///
  /// In en, this message translates to:
  /// **'Product service and privacy contact: '**
  String get legalStaticContactPrefix;

  /// No description provided for @legalStaticSentenceEnd.
  ///
  /// In en, this message translates to:
  /// **'.'**
  String get legalStaticSentenceEnd;

  /// No description provided for @siteAuthorLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading author…'**
  String get siteAuthorLoading;

  /// No description provided for @siteAuthorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Author unavailable'**
  String get siteAuthorUnavailable;

  /// No description provided for @siteAuthorRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get siteAuthorRetry;

  /// No description provided for @commentResizePanel.
  ///
  /// In en, this message translates to:
  /// **'Resize comments panel'**
  String get commentResizePanel;

  /// No description provided for @commentResizePanelHint.
  ///
  /// In en, this message translates to:
  /// **'Drag left to widen or right to narrow. Use the left and right arrow keys to adjust.'**
  String get commentResizePanelHint;

  /// No description provided for @commentPanelWidth.
  ///
  /// In en, this message translates to:
  /// **'{width} pixels'**
  String commentPanelWidth(int width);

  /// No description provided for @siteScreenOne.
  ///
  /// In en, this message translates to:
  /// **'Screen 01'**
  String get siteScreenOne;

  /// No description provided for @siteScreenTwo.
  ///
  /// In en, this message translates to:
  /// **'Screen 02'**
  String get siteScreenTwo;

  /// No description provided for @siteScreenThree.
  ///
  /// In en, this message translates to:
  /// **'Screen 03'**
  String get siteScreenThree;

  /// No description provided for @siteScreenPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Content coming soon'**
  String get siteScreenPlaceholder;

  /// No description provided for @siteScreenSelection.
  ///
  /// In en, this message translates to:
  /// **'Choose a screen'**
  String get siteScreenSelection;

  /// No description provided for @siteScreenBack.
  ///
  /// In en, this message translates to:
  /// **'Back to community'**
  String get siteScreenBack;

  /// No description provided for @siteScreenStage.
  ///
  /// In en, this message translates to:
  /// **'Featured screens'**
  String get siteScreenStage;

  /// No description provided for @reportHistoryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading reports'**
  String get reportHistoryLoading;

  /// No description provided for @reportHistoryNotice.
  ///
  /// In en, this message translates to:
  /// **'Only reports you submitted are shown. Platform notifications confirm outcomes.'**
  String get reportHistoryNotice;

  /// No description provided for @reportRecordId.
  ///
  /// In en, this message translates to:
  /// **'Report ID'**
  String get reportRecordId;

  /// No description provided for @reportRecordReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reportRecordReason;

  /// No description provided for @reportRecordOutcome.
  ///
  /// In en, this message translates to:
  /// **'Outcome'**
  String get reportRecordOutcome;

  /// No description provided for @reportOutcomeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No outcome yet'**
  String get reportOutcomeUnavailable;

  /// No description provided for @reportAppealAction.
  ///
  /// In en, this message translates to:
  /// **'Submit appeal'**
  String get reportAppealAction;

  /// No description provided for @reportAppealUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Online appeals are currently unavailable.'**
  String get reportAppealUnavailable;

  /// No description provided for @reportAppealSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Appeal submitted. Watch for a platform notification.'**
  String get reportAppealSubmitted;

  /// No description provided for @reportStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get reportStatusClosed;

  /// No description provided for @reportStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Status unconfirmed'**
  String get reportStatusUnknown;

  /// No description provided for @reportAppealRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an appeal explanation'**
  String get reportAppealRequired;

  /// No description provided for @reportAppealFailed.
  ///
  /// In en, this message translates to:
  /// **'Appeal submission failed. Try again.'**
  String get reportAppealFailed;

  /// No description provided for @reportAppealExplanation.
  ///
  /// In en, this message translates to:
  /// **'Appeal explanation'**
  String get reportAppealExplanation;

  /// No description provided for @reportAppealPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Do not include passwords, identity document numbers or other sensitive information.'**
  String get reportAppealPrivacy;

  /// No description provided for @reportAppealSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get reportAppealSubmitting;

  /// No description provided for @reportAppealSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get reportAppealSubmit;

  /// No description provided for @authPolicyConsentLabel.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to'**
  String get authPolicyConsentLabel;

  /// No description provided for @webSettingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get webSettingsLanguage;

  /// No description provided for @webSettingsHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get webSettingsHelp;

  /// No description provided for @webHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & contact'**
  String get webHelpTitle;

  /// No description provided for @webHelpViewQuestion.
  ///
  /// In en, this message translates to:
  /// **'How do I view a 3D work?'**
  String get webHelpViewQuestion;

  /// No description provided for @webHelpViewAnswer.
  ///
  /// In en, this message translates to:
  /// **'Open a work from its cover. Drag to rotate and use the mouse wheel or pinch to zoom.'**
  String get webHelpViewAnswer;

  /// No description provided for @webHelpPublishQuestion.
  ///
  /// In en, this message translates to:
  /// **'Why is my published work not visible yet?'**
  String get webHelpPublishQuestion;

  /// No description provided for @webHelpPublishAnswer.
  ///
  /// In en, this message translates to:
  /// **'Works appear in the community after review. Check the processing status in your publication history.'**
  String get webHelpPublishAnswer;

  /// No description provided for @webHelpAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'What can I do after signing in?'**
  String get webHelpAccountQuestion;

  /// No description provided for @webHelpAccountAnswer.
  ///
  /// In en, this message translates to:
  /// **'Sign in to publish, like, save and comment on works, follow creators and send private messages.'**
  String get webHelpAccountAnswer;

  /// No description provided for @webHelpContactLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get webHelpContactLabel;

  /// No description provided for @webAccountLikes.
  ///
  /// In en, this message translates to:
  /// **'My likes'**
  String get webAccountLikes;

  /// No description provided for @webAccountFavorites.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get webAccountFavorites;

  /// No description provided for @webAccountHistory.
  ///
  /// In en, this message translates to:
  /// **'Viewing history'**
  String get webAccountHistory;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'zh':
      return AppL10nZh();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
