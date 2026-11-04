// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppL10nZh extends AppL10n {
  AppL10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appBrand => '方寸间';

  @override
  String get splashSubtitle => '三维捕捉 · 极简工作台';

  @override
  String get splashStartingEngine => '正在启动 3D 引擎…';

  @override
  String get splashRestoringSession => '正在恢复会话…';

  @override
  String get splashPreparingSignIn => '准备登录界面…';

  @override
  String get authServiceUnavailable => '登录服务暂时不可用,请检查网络后重试';

  @override
  String get authRetry => '重试';

  @override
  String get authAutoRetrying => '已在后台自动重试';

  @override
  String get splashWaking3DEngine => '正在唤醒 3D 引擎…';

  @override
  String get splashRendererUnavailable => '渲染器不可用，即将进入重试';

  @override
  String get communityEmptyTitle => '社区还没有作品';

  @override
  String get communitySearchHint => '搜索作品';

  @override
  String get communityTabHot => '热门';

  @override
  String get communityTabNearby => '附近';

  @override
  String get communityTabDiscover => '发现';

  @override
  String communityOnlyAuthor(String name) {
    return '只看 @$name 的作品';
  }

  @override
  String get communityClearAuthorFilter => '看全部';

  @override
  String get communityTopicTitle => '本周精选';

  @override
  String get communityTopicBody => '编辑挑出的空间。想上这里，就把你扫的地方发出来。';

  @override
  String get communityTopicCaptureTitle => '怎么扫得更好';

  @override
  String get communityTopicCaptureBody => '绕着走,慢一点,别只站在一个位置。覆盖够了,模型才不会破。';

  @override
  String get communityTopicViewerTitle => '点开就能转';

  @override
  String get communityTopicViewerBody => '这里每一件都是真的三维。拖一下,换个角度再看一遍。';

  @override
  String get communityNearbyComingSoon => '附近功能即将上线，敬请期待。';

  @override
  String get meMyWorksEmpty => '还没有作品 —— 点右下角的相机开始第一次扫描。';

  @override
  String get scanLifecycleCompleted => '已完成';

  @override
  String get createOptionCapture => '拍摄';

  @override
  String get createOptionUpload => '上传';

  @override
  String get createImportingGlb => '正在导入 GLB 模型…';

  @override
  String createImportPickerFailed(String error) {
    return '打开文件选择器失败：$error';
  }

  @override
  String get createImportFileUnreadable => '无法读取所选文件';

  @override
  String get meTapHintInProgress => '正在生成 3D 模型，完成后会自动打开';

  @override
  String get meActionRename => '改名';

  @override
  String get meActionDelete => '删除';

  @override
  String get meActionCancel => '取消';

  @override
  String get meActionSave => '保存';

  @override
  String get meDuplicateWorkName => '已有同名作品，请换一个名称。';

  @override
  String get meRenameDialogTitle => '改名';

  @override
  String get meDeleteDialogTitle => '删除这次扫描?';

  @override
  String meDeleteDialogContent(String name) {
    return '\"$name\" 的本机原始照片、点云、重建数据库和缓存将被永久删除，无法恢复。';
  }

  @override
  String get defaultUntitledScan => '未命名';

  @override
  String get captureWarmupHint => '正在初始化 AR…';

  @override
  String get captureReadyHint => '点击下方按钮进入瞄准';

  @override
  String get captureAimHint => '将准星对准主体，再点 ✓ 锁定并开始';

  @override
  String get captureMaterialTooSparseHint => '请继续拍摄一会儿再停止';

  @override
  String get captureLockFailedHint => '未检测到平面或跟踪未就绪 — 请对准物体所在表面后再试';

  @override
  String captureInitFailed(String error) {
    return '初始化失败：$error';
  }

  @override
  String captureRecordingStartFailed(String error) {
    return '开始录制失败：$error';
  }

  @override
  String get relativeJustNow => '刚刚';

  @override
  String relativeMinutesAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String relativeHoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String relativeDaysAgo(int n) {
    return '$n 天前';
  }

  @override
  String relativeWeeksAgo(int n) {
    return '$n 周前';
  }

  @override
  String relativeMonthsAgo(int n) {
    return '$n 个月前';
  }

  @override
  String get meSettingsTitle => '设置';

  @override
  String get meNotifications => '通知';

  @override
  String get meNotificationsOn => '开启';

  @override
  String get mePrivacy => '隐私';

  @override
  String get meNotificationsOff => '已关闭';

  @override
  String get mePrivacyPublic => '公开';

  @override
  String get mePrivacyPrivate => '仅自己可见';

  @override
  String get meSettingNotConfigured => '未配置';

  @override
  String get meLanguage => '语言';

  @override
  String get meLanguageZh => '简体中文';

  @override
  String get meLanguageEn => 'English';

  @override
  String get meAbout => '关于';

  @override
  String get meSignOut => '退出登录';

  @override
  String get meDetailRunningProcessing => '处理中';

  @override
  String get meDetailRecordNotFound => '找不到这条作品';

  @override
  String get authWelcomeBack => '欢迎回来';

  @override
  String get authCreateAccount => '创建你的账号';

  @override
  String get authSignIn => '登录';

  @override
  String get authSignUp => '注册';

  @override
  String get authEmailHint => '邮箱';

  @override
  String get authAccountChinaHint => '手机号或邮箱';

  @override
  String get authAccountInternationalHint => '手机号（含国家区号）或邮箱';

  @override
  String get authShowPassword => '显示密码';

  @override
  String get authHidePassword => '隐藏密码';

  @override
  String get authPasswordHint => '密码';

  @override
  String get authPasswordHintMin => '设置密码（至少 8 位）';

  @override
  String get authForgotPassword => '忘记密码？';

  @override
  String get authTermsAcceptance => '注册即表示你同意方寸间的服务条款与隐私政策。';

  @override
  String get authErrorDialogTitle => '出错了';

  @override
  String get otpVerifyTitle => '验证邮箱';

  @override
  String otpVerifySubtitle(String email) {
    return '我们已向 $email 发送 6 位验证码，请在下方输入完成注册。';
  }

  @override
  String get otpResend => '重新发送';

  @override
  String otpResendCooldown(int seconds) {
    return '$seconds 秒后可重发';
  }

  @override
  String get otpResendSent => '已重新发送';

  @override
  String get otpUseAnotherEmail => '换一个邮箱';

  @override
  String get resetTitle => '重置密码';

  @override
  String resetSubtitleEnterCode(String email) {
    return '我们已向 $email 发送 6 位验证码，请连同新密码一起输入';
  }

  @override
  String get resetSendCode => '发送验证码';

  @override
  String get resetNewPasswordHint => '新密码（至少 8 位）';

  @override
  String get resetConfirm => '重置密码';

  @override
  String get captureModeLocal => '本地方案';

  @override
  String get captureModeRemoteLegacy => '远程方案';

  @override
  String get captureModeNewRemote => '新远程方案';

  @override
  String get languageDialogTitle => '语言';

  @override
  String get languageDialogChinese => '简体中文';

  @override
  String get languageDialogEnglish => 'English';

  @override
  String get commonCancel => '取消';

  @override
  String get commonOk => '确定';

  @override
  String get meTabProjects => '项目';

  @override
  String get meBadgeGenerating => '生成中';

  @override
  String get meBadgeUnfinished => '未完成';

  @override
  String get meBadgeDone => '完成';

  @override
  String get meTabDrafts => '草稿';

  @override
  String get defaultImportedScan => '导入的模型';

  @override
  String get meDisplayName => '昵称';

  @override
  String get meDisplayNameDialogTitle => '修改昵称';

  @override
  String get meDisplayNameDialogHint => '新昵称(最多 20 字)';

  @override
  String get meDisplayNameUpdated => '昵称已更新';

  @override
  String meDisplayNameUpdateFailed(String error) {
    return '更新失败:$error';
  }

  @override
  String get meAnalyticsTitle => '帮助改进产品';

  @override
  String get meToggleOn => '已开启';

  @override
  String get meToggleOff => '已关闭';

  @override
  String get legalUserAgreement => '用户协议';

  @override
  String get legalPrivacyPolicy => '隐私政策';

  @override
  String get authTermsAcceptancePrefix => '注册即表示你同意:';

  @override
  String get mePlatformRules => '平台公约';

  @override
  String get meIpRegion => 'IP 属地';

  @override
  String get meIpRegionUnknown => '未知';

  @override
  String ipRegionLabel(String region) {
    return 'IP属地:$region';
  }

  @override
  String get authPhoneEntry => '用短信验证码登录';

  @override
  String get authPhoneNumberHint => '手机号';

  @override
  String get authPhoneDisplayNameHint => '昵称(可选)';

  @override
  String get authPhoneSendCode => '发送验证码';

  @override
  String authPhoneWillSend(String target) {
    return '我们会发送一次性验证码到 $target。标准短信费可能适用。';
  }

  @override
  String authPhoneCodeSentTo(String phone) {
    return '验证码已发送到 $phone';
  }

  @override
  String get authPhoneCodeHint => '6 位验证码';

  @override
  String get authPhoneSubmitSignIn => '登录';

  @override
  String get authPhoneSubmitSignUp => '完成注册';

  @override
  String get authPhoneChangeNumber => '换个手机号';

  @override
  String get authPhoneYourNumber => '你的手机号';

  @override
  String get meHandle => 'ID';

  @override
  String get meHandleNotSet => '未设置';

  @override
  String get meHandleDialogTitle => '设置 ID';

  @override
  String get meHandleDialogHint => '小写字母、数字、点、下划线,2-32 位';

  @override
  String get meHandleDialogNote => 'ID 全站唯一,用来让别人找到你。设置后 3 天内不能再改。';

  @override
  String get meHandleUpdated => 'ID 已更新';

  @override
  String meHandleUpdateFailed(String error) {
    return 'ID 更新失败:$error';
  }

  @override
  String get sfmSaveDraft => '保存草稿';

  @override
  String get sfmNext => '下一步';

  @override
  String get sfmDone => '完成';

  @override
  String get sfmBackToDrafts => '返回草稿';

  @override
  String get sfmEditSelection => '选区编辑';

  @override
  String get sfmSelectionSaveTitle => '编辑记录是否保存';

  @override
  String get sfmSelectionSaveBody => '你调整过选区范围。保存后预览与交付都只包含框内的点。';

  @override
  String get sfmSelectionSaveKeep => '保存';

  @override
  String get sfmSelectionSaveDiscard => '不保存';

  @override
  String get sfmSelectionSaveCancel => '取消';

  @override
  String get sfmGeneratingFinalCloud => '正在生成最终点云…';

  @override
  String get captureFinishing => '正在收尾拍摄…';

  @override
  String get sfmReconFailedKeptFrames => '本次未能重建,已保留素材';

  @override
  String get sfmChipFinalRecon => '最终重建';

  @override
  String sfmChipReconstructing(int count) {
    return '重建中 · $count 点…';
  }

  @override
  String get etaCalculating => '估算中…';

  @override
  String get etaUnderMinute => '剩余等待时间 · 不到一分钟';

  @override
  String etaMinutes(int n) {
    return '剩余等待时间 · 约 $n 分钟';
  }

  @override
  String sfmChipReconDone(int count) {
    return '重建完成 · $count 点';
  }

  @override
  String get sfmChipReconEnded => '重建结束';

  @override
  String get sfmQueueDrainedFinal => '帧队列已清空 · 正在生成最终点云';

  @override
  String sfmProgressFedQueued(int fed, int queued) {
    return '已完成 $fed/$queued 帧';
  }

  @override
  String sfmElapsedSec(int secs) {
    return '$secs 秒';
  }

  @override
  String sfmElapsedMinSec(int min, int sec) {
    return '$min 分 $sec 秒';
  }

  @override
  String sfmStage1(String elapsed) {
    return '整理帧数据…(阶段 1/4 · 已 $elapsed)';
  }

  @override
  String sfmStage2a(String elapsed) {
    return '补全匹配中…(阶段 2/4 · 已 $elapsed)';
  }

  @override
  String sfmStage2b(String elapsed) {
    return '全局优化中…(阶段 2/4 · 已 $elapsed)';
  }

  @override
  String sfmStage3(String elapsed) {
    return '提取色彩…(阶段 3/4 · 已 $elapsed)';
  }

  @override
  String sfmStage4(String elapsed) {
    return '保存点云…(阶段 4/4 · 已 $elapsed)';
  }

  @override
  String get viewerSparseCloudTitle => '稀疏点云';

  @override
  String viewerTitleWithCount(String title, int count) {
    return '$title · $count 点';
  }

  @override
  String get viewerLoadFailed => '点云文件读取失败';

  @override
  String get selectionRotatePointCloud => '旋转';

  @override
  String get selectionNoCloud => '暂无点云数据';

  @override
  String get cubeFaceTop => '顶';

  @override
  String get cubeFaceFront => '前';

  @override
  String get cubeFaceRight => '右';

  @override
  String get cubeFaceBack => '后';

  @override
  String get cubeFaceLeft => '左';

  @override
  String get cubeFaceBottom => '底';

  @override
  String get denseStageUnavailable => '后续处理还没接入本机';

  @override
  String get selectionCancel => '取消';

  @override
  String get selectionDiscardTitle => '确定要放弃更改吗?';

  @override
  String get selectionDiscardConfirm => '放弃更改';

  @override
  String get selectionResetRotation => '回到初始旋转角度';

  @override
  String get selectionResetZoom => '回到初始点云大小';

  @override
  String get selectionResetBoxSize => '恢复原始框大小';

  @override
  String get publishAction => '发布到社区';

  @override
  String get publishNotReady => '重建完成后可发布';

  @override
  String get publishAlreadyDone => '已发布到社区';

  @override
  String get publishSheetSubtitle => '发布后,任何人都能在社区看到这个作品。';

  @override
  String get publishFieldTitle => '标题';

  @override
  String get publishFieldDescription => '描述(选填)';

  @override
  String get publishConfirm => '确认发布';

  @override
  String get publishInProgress => '正在发布';

  @override
  String get publishSuccess => '已发布到社区';

  @override
  String get publishErrSignedOut => '请先登录再发布';

  @override
  String get publishErrAlreadyPublished => '这个作品已经发布过了';

  @override
  String get publishErrReading => '读取点云失败';

  @override
  String get publishErrUploading => '上传失败,请检查网络后重试';

  @override
  String get publishErrTooLarge => '这个扫描太大,超出了上传上限,重试不会成功。请缩小扫描范围后重新生成。';

  @override
  String get publishErrRejected => '文件未通过服务端校验,可能已损坏。请重新生成这个扫描。';

  @override
  String get publishErrInserting => '发布信息写入失败,请稍后重试';

  @override
  String get publishErrGeneric => '发布失败';

  @override
  String get communityCloudLoadFailed => '点云加载失败';

  @override
  String get communityRetry => '重试';

  @override
  String get communityFormatUnsupported => '当前版本无法预览这种格式';

  @override
  String get communityPointsSuffix => '点';

  @override
  String get meDeleteAccount => '删除账号';

  @override
  String get meDeleteAccountDialogTitle => '永久删除账号？';

  @override
  String get meDeleteAccountDialogBody =>
      '你的账号、已发布的作品和全部云端数据将被永久删除，此操作无法撤销。本机已拍摄的项目不受影响。';

  @override
  String get meDeleteAccountConfirm => '永久删除';

  @override
  String get meDeleteAccountFailed => '删除失败，请稍后重试';

  @override
  String get publishModerationUnderReview => '审核中';

  @override
  String get publishModerationRemoved => '已下架';

  @override
  String get publishModerationRemovedHint =>
      '该作品因违反社区规范已被下架，其他人无法看到。如有疑问请通过设置页的联系方式申诉。';

  @override
  String get workMoreActions => '更多';

  @override
  String get reportAction => '举报';

  @override
  String get reportSheetTitle => '举报这个作品';

  @override
  String get reportSheetSubtitle => '请选择原因，我们会尽快处理。';

  @override
  String get reportReasonSpam => '垃圾信息或广告';

  @override
  String get reportReasonHarassment => '骚扰或霸凌';

  @override
  String get reportReasonHateSpeech => '仇恨言论';

  @override
  String get reportReasonSexualContent => '色情内容';

  @override
  String get reportReasonViolence => '暴力或血腥';

  @override
  String get reportReasonCopyright => '侵犯版权';

  @override
  String get reportReasonMisinformation => '虚假信息';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportDetailHint => '补充说明（可选）';

  @override
  String get reportSubmit => '提交举报';

  @override
  String get reportSubmitted => '举报已提交，我们会尽快处理';

  @override
  String get reportFailed => '举报提交失败，请稍后重试';

  @override
  String get blockAction => '屏蔽此用户';

  @override
  String get blockDialogTitle => '屏蔽这个用户？';

  @override
  String get blockDialogBody => '屏蔽后你将不再看到该用户的作品，你们之间的关注关系也会取消。';

  @override
  String get blockConfirm => '屏蔽';

  @override
  String get blockDone => '已屏蔽，该用户的作品不再显示';

  @override
  String get blockFailed => '操作失败，请稍后重试';

  @override
  String get workDeleteAction => '从社区删除';

  @override
  String get workDeleteDialogTitle => '从社区删除这个作品？';

  @override
  String get workDeleteDialogBody =>
      '该作品将从社区移除，云端文件一并删除，无法恢复。本机的原始拍摄项目不受影响，之后仍可重新发布。';

  @override
  String get workDeleteConfirm => '删除';

  @override
  String get workDeleteDone => '已从社区删除';

  @override
  String get workDeleteFailed => '删除失败，请稍后重试';

  @override
  String get socialActionFailed => '操作失败，请稍后重试';

  @override
  String get socialFollowingTitle => '我的关注';

  @override
  String get socialFollowingLoadFailed => '暂时无法加载关注列表';

  @override
  String get socialFollowingEmpty => '还没有关注任何人';

  @override
  String get socialFollow => '关注';

  @override
  String get socialFollowing => '已关注';

  @override
  String get meDownloadIncomplete => '下载未完成，稍后重试';

  @override
  String get meWorkOpenFailed => '作品暂时无法打开，稍后重试';

  @override
  String get meProfileTitle => '我的';

  @override
  String get socialLikesReceived => '获赞';

  @override
  String get socialWorks => '作品';

  @override
  String get socialFollowers => '粉丝';

  @override
  String get profileLoadFailed => '暂时无法加载个人主页';

  @override
  String get profileBack => '返回';

  @override
  String get profileMore => '更多';

  @override
  String get profileReportUser => '举报该用户';

  @override
  String get profileBlockUser => '拉黑该用户';

  @override
  String get profileBlockTitle => '拉黑该用户？';

  @override
  String get profileBlockBody =>
      '使用当前账号登录 PocketWorld 时，你将不再在社区、搜索、关注列表和个人主页看到对方；双方关注关系会立即解除，也不能再次关注。对方不会收到通知。公开链接、未登录访问或其他账号仍可能看到其公开内容。';

  @override
  String get profileBlockConfirm => '确认拉黑';

  @override
  String get profileBlockFailed => '拉黑失败，请稍后重试';

  @override
  String get reportUserTitle => '举报该用户';

  @override
  String get reportTierTitle => '选择举报类型';

  @override
  String get reportReasonTitle => '选择原因';

  @override
  String get reportStandardTitle => '普通举报';

  @override
  String get reportStandardSubtitle => '骚扰、诈骗、违法有害或其他社区问题';

  @override
  String get reportRightsTitle => '权益投诉';

  @override
  String get reportRightsEntry => '侵犯权益';

  @override
  String get reportRightsSubtitle => '冒充、隐私、肖像或知识产权问题';

  @override
  String get reportStandardDetailHint => '请说明问题位于作品正面、背面、顶部或哪个画面';

  @override
  String get reportRightsDetailHint => '请说明权利归属、侵权位置和处理请求';

  @override
  String get reportEvidenceType => '证明材料类型';

  @override
  String get reportEvidenceContext => '问题截图';

  @override
  String get reportEvidenceIdentity => '身份证明';

  @override
  String get reportEvidenceOwnership => '权属证明';

  @override
  String get reportEvidenceAuthorization => '授权证明';

  @override
  String get reportEvidenceOther => '其他证明';

  @override
  String get reportEvidenceOptional => '补充截图（选填）';

  @override
  String get reportEvidenceLimitHint => '最多 3 张，仅支持 JPG 或 PNG；图片会在上传前移除定位等元数据。';

  @override
  String get reportHistoryTitle => '我的举报';

  @override
  String get reportHistoryEmpty => '还没有提交过举报';

  @override
  String get reportHistoryLoadFailed => '暂时无法加载举报记录';

  @override
  String reportHistorySource(String title) {
    return '关联作品：$title';
  }

  @override
  String get reportStatusPending => '待处理';

  @override
  String get reportStatusInReview => '审核中';

  @override
  String get reportStatusNeedsInfo => '需要补充材料';

  @override
  String get reportStatusActioned => '已处理';

  @override
  String get reportStatusDismissed => '未发现违规';

  @override
  String get reportAdditionalInfoTitle => '补充信息';

  @override
  String get reportImageProcessFailed => '无法处理这张图片，请选择 JPG 或 PNG';

  @override
  String get reportUserSubmitted => '举报已提交';

  @override
  String get reportSubmittedPartial => '举报已提交，部分图片未上传';

  @override
  String get reportDetailUserHint => '可补充说明具体情况';

  @override
  String reportSourceWork(String workId) {
    return '关联作品：$workId';
  }

  @override
  String get reportAddEvidence => '添加截图或照片（最多 3 张）';

  @override
  String get reportSensitiveEvidenceWarning =>
      '请不要重新上传或传播敏感材料。平台会保全关联的站内内容并交由审核处理。';

  @override
  String get reportSubmitting => '提交中…';

  @override
  String get reportSubmitUser => '提交举报';

  @override
  String get reportReasonImpersonation => '冒充他人或账号资料虚假';

  @override
  String get reportReasonHarassmentThreat => '骚扰、网络暴力或人身威胁';

  @override
  String get reportReasonSpamFraud => '诈骗、广告骚扰或异常账号行为';

  @override
  String get reportReasonMinorSafety => '涉及未成年人安全';

  @override
  String get reportReasonSexualLowQuality => '色情低俗';

  @override
  String get reportReasonViolenceIllegal => '暴力、自伤、仇恨、极端或其他违法有害信息';

  @override
  String get reportReasonMisleading => '虚假不实或误导性信息';

  @override
  String get reportReasonPrivacyIp => '隐私、人肉搜索、肖像或知识产权';

  @override
  String get reportReasonOtherUncertain => '其他 / 不确定';

  @override
  String get blockedUsersTitle => '已拉黑用户';

  @override
  String get blockedUsersLoadFailed => '暂时无法加载拉黑名单';

  @override
  String get blockedUsersEmpty => '没有已拉黑的用户';

  @override
  String get unblockTitle => '解除拉黑？';

  @override
  String get unblockBody => '解除后可以重新看到对方的公开内容，但不会自动恢复双方原来的关注关系。';

  @override
  String get unblockAction => '解除拉黑';

  @override
  String get unblockFailed => '解除拉黑失败，请稍后重试';

  @override
  String get meBlockedUsers => '已拉黑用户';

  @override
  String get meSocialLoadFailed => '暂时无法加载社交资料';

  @override
  String etaCountdown(String time) {
    return '预估剩余时间 · $time';
  }

  @override
  String etaSparseCountdown(String time) {
    return '稀疏阶段预估剩余时间 · $time';
  }

  @override
  String get etaSparseCalculating => '正在估算稀疏阶段剩余时间…';

  @override
  String etaDurationMinutes(int n) {
    return '约 $n 分钟';
  }

  @override
  String get etaDurationUnderMinute => '1分钟内完成';

  @override
  String get phoneSignUpWithPhone => '使用手机号注册';

  @override
  String get phoneCountrySearchHint => '搜索国家、地区或区号';

  @override
  String get phoneCountryNoMatches => '无匹配结果';

  @override
  String get phoneMobileFormatUnavailable => '此地区暂无可用的手机号格式资料';

  @override
  String phoneMobileExample(String number) {
    return '手机号示例：$number';
  }

  @override
  String get phoneOverseasSignupUnavailable => '境外手机号暂不支持短信验证，可先使用邮箱注册。';

  @override
  String get phoneLoginHelp =>
      '中国大陆请输入11位手机号；境外号码请带国家区号。境外短信验证暂未开放，可先使用邮箱注册或登录。';

  @override
  String phoneCountryCallingCodeLabel(String country, String callingCode) {
    return '$country +$callingCode';
  }

  @override
  String get phoneCountryAC => '阿森松岛';

  @override
  String get phoneCountryAD => '安道尔';

  @override
  String get phoneCountryAE => '阿拉伯联合酋长国';

  @override
  String get phoneCountryAF => '阿富汗';

  @override
  String get phoneCountryAG => '安提瓜和巴布达';

  @override
  String get phoneCountryAI => '安圭拉';

  @override
  String get phoneCountryAL => '阿尔巴尼亚';

  @override
  String get phoneCountryAM => '亚美尼亚';

  @override
  String get phoneCountryAO => '安哥拉';

  @override
  String get phoneCountryAR => '阿根廷';

  @override
  String get phoneCountryAS => '美属萨摩亚';

  @override
  String get phoneCountryAT => '奥地利';

  @override
  String get phoneCountryAU => '澳大利亚';

  @override
  String get phoneCountryAW => '阿鲁巴';

  @override
  String get phoneCountryAX => '奥兰群岛';

  @override
  String get phoneCountryAZ => '阿塞拜疆';

  @override
  String get phoneCountryBA => '波斯尼亚和黑塞哥维那';

  @override
  String get phoneCountryBB => '巴巴多斯';

  @override
  String get phoneCountryBD => '孟加拉国';

  @override
  String get phoneCountryBE => '比利时';

  @override
  String get phoneCountryBF => '布基纳法索';

  @override
  String get phoneCountryBG => '保加利亚';

  @override
  String get phoneCountryBH => '巴林';

  @override
  String get phoneCountryBI => '布隆迪';

  @override
  String get phoneCountryBJ => '贝宁';

  @override
  String get phoneCountryBL => '圣巴泰勒米';

  @override
  String get phoneCountryBM => '百慕大';

  @override
  String get phoneCountryBN => '文莱';

  @override
  String get phoneCountryBO => '玻利维亚';

  @override
  String get phoneCountryBQ => '荷属加勒比区';

  @override
  String get phoneCountryBR => '巴西';

  @override
  String get phoneCountryBS => '巴哈马';

  @override
  String get phoneCountryBT => '不丹';

  @override
  String get phoneCountryBW => '博茨瓦纳';

  @override
  String get phoneCountryBY => '白俄罗斯';

  @override
  String get phoneCountryBZ => '伯利兹';

  @override
  String get phoneCountryCA => '加拿大';

  @override
  String get phoneCountryCC => '科科斯（基林）群岛';

  @override
  String get phoneCountryCD => '刚果（金）';

  @override
  String get phoneCountryCF => '中非共和国';

  @override
  String get phoneCountryCG => '刚果（布）';

  @override
  String get phoneCountryCH => '瑞士';

  @override
  String get phoneCountryCI => '科特迪瓦';

  @override
  String get phoneCountryCK => '库克群岛';

  @override
  String get phoneCountryCL => '智利';

  @override
  String get phoneCountryCM => '喀麦隆';

  @override
  String get phoneCountryCN => '中国大陆';

  @override
  String get phoneCountryCO => '哥伦比亚';

  @override
  String get phoneCountryCR => '哥斯达黎加';

  @override
  String get phoneCountryCU => '古巴';

  @override
  String get phoneCountryCV => '佛得角';

  @override
  String get phoneCountryCW => '库拉索';

  @override
  String get phoneCountryCX => '圣诞岛';

  @override
  String get phoneCountryCY => '塞浦路斯';

  @override
  String get phoneCountryCZ => '捷克';

  @override
  String get phoneCountryDE => '德国';

  @override
  String get phoneCountryDJ => '吉布提';

  @override
  String get phoneCountryDK => '丹麦';

  @override
  String get phoneCountryDM => '多米尼克';

  @override
  String get phoneCountryDO => '多米尼加共和国';

  @override
  String get phoneCountryDZ => '阿尔及利亚';

  @override
  String get phoneCountryEC => '厄瓜多尔';

  @override
  String get phoneCountryEE => '爱沙尼亚';

  @override
  String get phoneCountryEG => '埃及';

  @override
  String get phoneCountryEH => '西撒哈拉';

  @override
  String get phoneCountryER => '厄立特里亚';

  @override
  String get phoneCountryES => '西班牙';

  @override
  String get phoneCountryET => '埃塞俄比亚';

  @override
  String get phoneCountryFI => '芬兰';

  @override
  String get phoneCountryFJ => '斐济';

  @override
  String get phoneCountryFK => '福克兰群岛';

  @override
  String get phoneCountryFM => '密克罗尼西亚';

  @override
  String get phoneCountryFO => '法罗群岛';

  @override
  String get phoneCountryFR => '法国';

  @override
  String get phoneCountryGA => '加蓬';

  @override
  String get phoneCountryGB => '英国';

  @override
  String get phoneCountryGD => '格林纳达';

  @override
  String get phoneCountryGE => '格鲁吉亚';

  @override
  String get phoneCountryGF => '法属圭亚那';

  @override
  String get phoneCountryGG => '根西岛';

  @override
  String get phoneCountryGH => '加纳';

  @override
  String get phoneCountryGI => '直布罗陀';

  @override
  String get phoneCountryGL => '格陵兰';

  @override
  String get phoneCountryGM => '冈比亚';

  @override
  String get phoneCountryGN => '几内亚';

  @override
  String get phoneCountryGP => '瓜德罗普';

  @override
  String get phoneCountryGQ => '赤道几内亚';

  @override
  String get phoneCountryGR => '希腊';

  @override
  String get phoneCountryGT => '危地马拉';

  @override
  String get phoneCountryGU => '关岛';

  @override
  String get phoneCountryGW => '几内亚比绍';

  @override
  String get phoneCountryGY => '圭亚那';

  @override
  String get phoneCountryHK => '香港';

  @override
  String get phoneCountryHN => '洪都拉斯';

  @override
  String get phoneCountryHR => '克罗地亚';

  @override
  String get phoneCountryHT => '海地';

  @override
  String get phoneCountryHU => '匈牙利';

  @override
  String get phoneCountryID => '印度尼西亚';

  @override
  String get phoneCountryIE => '爱尔兰';

  @override
  String get phoneCountryIL => '以色列';

  @override
  String get phoneCountryIM => '马恩岛';

  @override
  String get phoneCountryIN => '印度';

  @override
  String get phoneCountryIO => '查戈斯群岛';

  @override
  String get phoneCountryIQ => '伊拉克';

  @override
  String get phoneCountryIR => '伊朗';

  @override
  String get phoneCountryIS => '冰岛';

  @override
  String get phoneCountryIT => '意大利';

  @override
  String get phoneCountryJE => '泽西岛';

  @override
  String get phoneCountryJM => '牙买加';

  @override
  String get phoneCountryJO => '约旦';

  @override
  String get phoneCountryJP => '日本';

  @override
  String get phoneCountryKE => '肯尼亚';

  @override
  String get phoneCountryKG => '吉尔吉斯斯坦';

  @override
  String get phoneCountryKH => '柬埔寨';

  @override
  String get phoneCountryKI => '基里巴斯';

  @override
  String get phoneCountryKM => '科摩罗';

  @override
  String get phoneCountryKN => '圣基茨和尼维斯';

  @override
  String get phoneCountryKP => '朝鲜';

  @override
  String get phoneCountryKR => '韩国';

  @override
  String get phoneCountryKW => '科威特';

  @override
  String get phoneCountryKY => '开曼群岛';

  @override
  String get phoneCountryKZ => '哈萨克斯坦';

  @override
  String get phoneCountryLA => '老挝';

  @override
  String get phoneCountryLB => '黎巴嫩';

  @override
  String get phoneCountryLC => '圣卢西亚';

  @override
  String get phoneCountryLI => '列支敦士登';

  @override
  String get phoneCountryLK => '斯里兰卡';

  @override
  String get phoneCountryLR => '利比里亚';

  @override
  String get phoneCountryLS => '莱索托';

  @override
  String get phoneCountryLT => '立陶宛';

  @override
  String get phoneCountryLU => '卢森堡';

  @override
  String get phoneCountryLV => '拉脱维亚';

  @override
  String get phoneCountryLY => '利比亚';

  @override
  String get phoneCountryMA => '摩洛哥';

  @override
  String get phoneCountryMC => '摩纳哥';

  @override
  String get phoneCountryMD => '摩尔多瓦';

  @override
  String get phoneCountryME => '黑山';

  @override
  String get phoneCountryMF => '法属圣马丁';

  @override
  String get phoneCountryMG => '马达加斯加';

  @override
  String get phoneCountryMH => '马绍尔群岛';

  @override
  String get phoneCountryMK => '北马其顿';

  @override
  String get phoneCountryML => '马里';

  @override
  String get phoneCountryMM => '缅甸';

  @override
  String get phoneCountryMN => '蒙古';

  @override
  String get phoneCountryMO => '澳门';

  @override
  String get phoneCountryMP => '北马里亚纳群岛';

  @override
  String get phoneCountryMQ => '马提尼克';

  @override
  String get phoneCountryMR => '毛里塔尼亚';

  @override
  String get phoneCountryMS => '蒙特塞拉特';

  @override
  String get phoneCountryMT => '马耳他';

  @override
  String get phoneCountryMU => '毛里求斯';

  @override
  String get phoneCountryMV => '马尔代夫';

  @override
  String get phoneCountryMW => '马拉维';

  @override
  String get phoneCountryMX => '墨西哥';

  @override
  String get phoneCountryMY => '马来西亚';

  @override
  String get phoneCountryMZ => '莫桑比克';

  @override
  String get phoneCountryNA => '纳米比亚';

  @override
  String get phoneCountryNC => '新喀里多尼亚';

  @override
  String get phoneCountryNE => '尼日尔';

  @override
  String get phoneCountryNF => '诺福克岛';

  @override
  String get phoneCountryNG => '尼日利亚';

  @override
  String get phoneCountryNI => '尼加拉瓜';

  @override
  String get phoneCountryNL => '荷兰';

  @override
  String get phoneCountryNO => '挪威';

  @override
  String get phoneCountryNP => '尼泊尔';

  @override
  String get phoneCountryNR => '瑙鲁';

  @override
  String get phoneCountryNU => '纽埃';

  @override
  String get phoneCountryNZ => '新西兰';

  @override
  String get phoneCountryOM => '阿曼';

  @override
  String get phoneCountryPA => '巴拿马';

  @override
  String get phoneCountryPE => '秘鲁';

  @override
  String get phoneCountryPF => '法属波利尼西亚';

  @override
  String get phoneCountryPG => '巴布亚新几内亚';

  @override
  String get phoneCountryPH => '菲律宾';

  @override
  String get phoneCountryPK => '巴基斯坦';

  @override
  String get phoneCountryPL => '波兰';

  @override
  String get phoneCountryPM => '圣皮埃尔和密克隆群岛';

  @override
  String get phoneCountryPR => '波多黎各';

  @override
  String get phoneCountryPS => '巴勒斯坦领土';

  @override
  String get phoneCountryPT => '葡萄牙';

  @override
  String get phoneCountryPW => '帕劳';

  @override
  String get phoneCountryPY => '巴拉圭';

  @override
  String get phoneCountryQA => '卡塔尔';

  @override
  String get phoneCountryRE => '留尼汪';

  @override
  String get phoneCountryRO => '罗马尼亚';

  @override
  String get phoneCountryRS => '塞尔维亚';

  @override
  String get phoneCountryRU => '俄罗斯';

  @override
  String get phoneCountryRW => '卢旺达';

  @override
  String get phoneCountrySA => '沙特阿拉伯';

  @override
  String get phoneCountrySB => '所罗门群岛';

  @override
  String get phoneCountrySC => '塞舌尔';

  @override
  String get phoneCountrySD => '苏丹';

  @override
  String get phoneCountrySE => '瑞典';

  @override
  String get phoneCountrySG => '新加坡';

  @override
  String get phoneCountrySH => '圣赫勒拿';

  @override
  String get phoneCountrySI => '斯洛文尼亚';

  @override
  String get phoneCountrySJ => '斯瓦尔巴和扬马延';

  @override
  String get phoneCountrySK => '斯洛伐克';

  @override
  String get phoneCountrySL => '塞拉利昂';

  @override
  String get phoneCountrySM => '圣马力诺';

  @override
  String get phoneCountrySN => '塞内加尔';

  @override
  String get phoneCountrySO => '索马里';

  @override
  String get phoneCountrySR => '苏里南';

  @override
  String get phoneCountrySS => '南苏丹';

  @override
  String get phoneCountryST => '圣多美和普林西比';

  @override
  String get phoneCountrySV => '萨尔瓦多';

  @override
  String get phoneCountrySX => '荷属圣马丁';

  @override
  String get phoneCountrySY => '叙利亚';

  @override
  String get phoneCountrySZ => '斯威士兰';

  @override
  String get phoneCountryTA => '特里斯坦-达库尼亚群岛';

  @override
  String get phoneCountryTC => '特克斯和凯科斯群岛';

  @override
  String get phoneCountryTD => '乍得';

  @override
  String get phoneCountryTG => '多哥';

  @override
  String get phoneCountryTH => '泰国';

  @override
  String get phoneCountryTJ => '塔吉克斯坦';

  @override
  String get phoneCountryTK => '托克劳';

  @override
  String get phoneCountryTL => '东帝汶';

  @override
  String get phoneCountryTM => '土库曼斯坦';

  @override
  String get phoneCountryTN => '突尼斯';

  @override
  String get phoneCountryTO => '汤加';

  @override
  String get phoneCountryTR => '土耳其';

  @override
  String get phoneCountryTT => '特立尼达和多巴哥';

  @override
  String get phoneCountryTV => '图瓦卢';

  @override
  String get phoneCountryTW => '台湾';

  @override
  String get phoneCountryTZ => '坦桑尼亚';

  @override
  String get phoneCountryUA => '乌克兰';

  @override
  String get phoneCountryUG => '乌干达';

  @override
  String get phoneCountryUS => '美国';

  @override
  String get phoneCountryUY => '乌拉圭';

  @override
  String get phoneCountryUZ => '乌兹别克斯坦';

  @override
  String get phoneCountryVA => '梵蒂冈';

  @override
  String get phoneCountryVC => '圣文森特和格林纳丁斯';

  @override
  String get phoneCountryVE => '委内瑞拉';

  @override
  String get phoneCountryVG => '英属维尔京群岛';

  @override
  String get phoneCountryVI => '美属维尔京群岛';

  @override
  String get phoneCountryVN => '越南';

  @override
  String get phoneCountryVU => '瓦努阿图';

  @override
  String get phoneCountryWF => '瓦利斯和富图纳';

  @override
  String get phoneCountryWS => '萨摩亚';

  @override
  String get phoneCountryXK => '科索沃';

  @override
  String get phoneCountryYE => '也门';

  @override
  String get phoneCountryYT => '马约特';

  @override
  String get phoneCountryZA => '南非';

  @override
  String get phoneCountryZM => '赞比亚';

  @override
  String get phoneCountryZW => '津巴布韦';

  @override
  String get commentAssetChecking => '模型身份校验中，请稍后重试';

  @override
  String get commentAssetUpdated => '模型版本已更新，请重新打开评论';

  @override
  String get commentLoadFailed => '评论暂时无法加载';

  @override
  String get commentLoadRetry => '评论暂时无法加载，请重试';

  @override
  String get commentSendFailed => '发送失败，草稿已保留，请重试';

  @override
  String get commentImageLimit => '最多添加 3 张图片';

  @override
  String get commentImageTooLarge => '每张图片不能超过 2 MiB';

  @override
  String get commentImageAddFailed => '无法添加图片，请选择 JPEG、PNG 或 WebP（每张不超过 2 MiB）';

  @override
  String get commentLikeFailed => '暂时无法点赞，请重试';

  @override
  String get commentDeleteFailed => '暂时无法删除，请重试';

  @override
  String get commentEditDraftFirst => '请先发送或清空当前草稿，再修改评论';

  @override
  String get commentReselectImages => '请重新选择要发送的图片';

  @override
  String get commentRefresh => '刷新评论';

  @override
  String get commentClose => '关闭评论';

  @override
  String get commentReload => '重新加载';

  @override
  String get commentViewLatest => '查看最新';

  @override
  String get commentHot => '热评';

  @override
  String get commentLatest => '最新';

  @override
  String get commentEmpty => '还没有公开评论，来聊聊这个作品';

  @override
  String get commentHotEmpty => '暂无热评';

  @override
  String get commentLatestEmpty => '还没有最新评论';

  @override
  String get commentPrivatePending => '待发布 · 仅自己可见';

  @override
  String get commentPrivateRejected => '未通过审核 · 仅自己可见';

  @override
  String get commentPrivateError => '提交异常 · 仅自己可见';

  @override
  String get commentAuthorReply => '作者回复';

  @override
  String get commentMe => '我';

  @override
  String get commentReplyFallback => '评论';

  @override
  String get commentHidden => '该评论因违反社区规范已被隐藏';

  @override
  String get commentViewReasonAppeal => '查看原因与申诉';

  @override
  String get commentViewPoint => '查看模型点位';

  @override
  String get commentReply => '回复';

  @override
  String get commentEditResend => '修改重发';

  @override
  String get commentImagePreview => '评论图片预览';

  @override
  String get commentCloseImage => '关闭图片';

  @override
  String get commentImageLoadFailed => '图片暂时无法加载';

  @override
  String get commentCancelReply => '取消回复';

  @override
  String get commentPointSelected => '已选择模型点位';

  @override
  String get commentRemovePoint => '移除模型点位';

  @override
  String get commentSignIn => '登录后发表评论';

  @override
  String get commentServiceUnavailable => '评论服务暂不可用';

  @override
  String get commentUnavailable => '暂时无法评论';

  @override
  String get commentComposerHint => '说点什么…';

  @override
  String get commentAddEmoji => '添加表情';

  @override
  String get commentAddImage => '添加图片';

  @override
  String get commentSelectPoint => '选择模型点位';

  @override
  String get commentSend => '发送';

  @override
  String get commentReportTitle => '举报这条评论';

  @override
  String get commentPointUnavailable => '点位选择暂不可用，请稍后重试';

  @override
  String get commentHideOnModel => '关闭模型评论';

  @override
  String get commentShowOnModel => '显示模型评论';

  @override
  String get commentAllWrite => '全部评论 / 写评论';

  @override
  String get commentPickPointHint => '点一下模型表面，选择评论位置';

  @override
  String get commentAll => '全部评论';

  @override
  String get publicWorkTitle => '社区作品';

  @override
  String get publicWorkUnavailable => '作品暂不可访问，请检查链接或稍后重试。';

  @override
  String commentCount(int count) {
    return '用户评论 $count';
  }

  @override
  String commentRetrySection(String section) {
    return '重试$section';
  }

  @override
  String commentMoreSection(String section) {
    return '加载更多$section';
  }

  @override
  String commentReplyTo(String name) {
    return '回复 $name';
  }

  @override
  String commentImageNumber(int number) {
    return '评论图片 $number';
  }

  @override
  String commentRemoveImage(int number) {
    return '移除图片 $number';
  }

  @override
  String commentLength(int current, int max) {
    return '$current/$max · 表情可能占多个长度单位';
  }

  @override
  String commentLikeCount(int count) {
    return '点赞 $count';
  }

  @override
  String commentUnlikeCount(int count) {
    return '取消点赞 $count';
  }

  @override
  String commentCalendarDate(int month, int day) {
    return '$month月$day日';
  }

  @override
  String get commentYesterday => '昨天';

  @override
  String get commentDayBeforeYesterday => '前天';

  @override
  String get moderationIdentityChanged => '账号或服务区域已变化，请重新加载';

  @override
  String get moderationSignInRequired => '请登录后查看审核通知';

  @override
  String get moderationRequestTimeout => '请求超时，请重试；申诉说明已保留';

  @override
  String get moderationConnectionFailed => '暂时无法连接，请重试';

  @override
  String get moderationInbox => '收件箱';

  @override
  String get moderationInboxLoadFailedLabel => '收件箱，通知加载失败，仍可打开';

  @override
  String get moderationInboxUnreadLabel => '收件箱，有未读审核通知';

  @override
  String get moderationInboxReadLabel => '收件箱，无未读审核通知';

  @override
  String get moderationInboxNotLoadedLabel => '收件箱，通知尚未加载';

  @override
  String get moderationInboxTitle => '系统收件箱';

  @override
  String get moderationRefreshNotices => '刷新通知';

  @override
  String get moderationNoNotices => '暂无审核通知';

  @override
  String get moderationCommentHidden => '评论已隐藏';

  @override
  String get moderationCommentRestored => '评论已恢复';

  @override
  String get moderationAppealRejected => '申诉未通过';

  @override
  String get moderationUnread => '未读';

  @override
  String get moderationRelatedWorkComment => '相关作品中的评论';

  @override
  String get moderationViewCase => '查看处理详情';

  @override
  String get moderationCaseTitle => '评论处理详情';

  @override
  String get moderationRefreshCase => '刷新处理结果';

  @override
  String get moderationCommentHiddenBody => '这条评论目前对其他人不可见。';

  @override
  String get moderationCommentRestoredBody => '服务端确认这条评论已恢复可见。';

  @override
  String get moderationReason => '处理原因';

  @override
  String get moderationRelatedContent => '关联内容';

  @override
  String get moderationCommentWork => '该评论所属作品';

  @override
  String get moderationHiddenPreview => '该条评论目前已隐藏，可在此查看处理结果并提出申诉。';

  @override
  String get moderationRequestReview => '申请复核';

  @override
  String get moderationRequestReviewBody => '请说明需要复核的原因。申诉处理期间，评论保持隐藏。';

  @override
  String get moderationAppealStatement => '申诉说明';

  @override
  String get moderationAppealStatementHint => '补充上下文或说明你认为需要复核的地方';

  @override
  String get moderationAppealStatementTooLong => '申诉说明不能超过 1000 字符';

  @override
  String get moderationSubmitting => '正在提交…';

  @override
  String get moderationSubmitAppeal => '提交申诉';

  @override
  String get moderationAppealSubmitted => '申诉已提交';

  @override
  String get moderationAppealApproved => '申诉已通过';

  @override
  String get moderationAppealPendingBody => '请等待复核结果。处理期间评论保持隐藏，无需重复提交。';

  @override
  String get moderationAppealResultFallback => '处理结果以当前评论状态为准。';

  @override
  String get communityCoverUnavailable => '封面暂不可用';

  @override
  String get communityFeedLoadFailed => '暂时无法加载作品，请重试';

  @override
  String get viewerModelUnavailableDataKept => '暂时无法显示模型，本地数据已保留';

  @override
  String moderationDecisionTime(String date) {
    return '处理时间：$date';
  }

  @override
  String get siteTitle => '窗后城 — 让空间，留在身边。';

  @override
  String get siteDescription =>
      '北京空也科技有限公司官方网站。探索空间记录与三维内容，了解正在开发的 iOS 应用「窗后城」，联系空也科技。';

  @override
  String get siteSkip => '跳至正文';

  @override
  String get siteHome => '窗后城首页';

  @override
  String get siteBrand => '窗后城';

  @override
  String get siteMainNav => '主导航';

  @override
  String get siteDiscover => '发现';

  @override
  String get siteSignIn => '登录社区 ↗';

  @override
  String get siteSupport => '支持';

  @override
  String get siteAgreements => '协议';

  @override
  String get siteContact => '联系';

  @override
  String get siteTagline => '记录空间，分享三维作品。';

  @override
  String get siteOpenCommunity => '进入完整社区 ↗';

  @override
  String get siteDiscoverSpaces => '发现空间';

  @override
  String get siteCommunityWorks => '社区作品';

  @override
  String get siteSupportContact => '支持与联系';

  @override
  String get siteContactLead => '产品咨询、使用反馈：';

  @override
  String get siteTerms => '用户协议';

  @override
  String get sitePrivacy => '隐私政策';

  @override
  String get siteRules => '平台公约';

  @override
  String get siteAgreementVersion => '协议 V1.1 · 2026年11月2日发布 · ';

  @override
  String get sitePublicationNotice => '三维作品发布与审核说明';

  @override
  String get siteAbout => '公司介绍';

  @override
  String get siteAboutHeadline => '空间有形，\n探索无界。';

  @override
  String get siteCompany => '北京空也科技有限公司';

  @override
  String get siteAboutFirst =>
      '空也科技是一家位于中国北京的科技公司，当前以「窗后城」iOS 应用研发为主要产品工作，关注移动设备、空间记录与三维内容之间的连接。';

  @override
  String get siteAboutSecond =>
      '我们希望让数字空间的记录与体验逐渐融入日常，从熟悉的场景出发，寻找更自然的内容表达方式。本网站是公司的官方信息与联系渠道。';

  @override
  String get siteLocation => '所在地';

  @override
  String get siteBeijing => '中国 · 北京';

  @override
  String get siteProduct => '产品';

  @override
  String get siteProductValue => '窗后城 · iOS 应用研发';

  @override
  String get siteOfficialWebsite => '官方网站';

  @override
  String get siteCopyright => '© 2026 北京空也科技有限公司';

  @override
  String get siteFooterNav => '页脚导航';

  @override
  String get siteProductSupport => '产品支持';

  @override
  String get siteBackTop => '回到顶部 ↑';

  @override
  String get siteLanguageSwitch => '切换为英文';

  @override
  String get siteFeedLoading => '正在读取社区作品…';

  @override
  String get siteLoadMore => '加载更多';

  @override
  String get siteFeedConnection => '社区暂时未能连接，请重试或进入完整社区';

  @override
  String get siteFeedFormat => '社区返回格式异常';

  @override
  String siteViewWork(Object title) {
    return '查看 $title';
  }

  @override
  String get siteUntitled => '未命名作品';

  @override
  String get siteWorkImage => '三维作品';

  @override
  String get siteCoverUnavailable => '封面暂不可用';

  @override
  String get siteNoCover => '暂无封面';

  @override
  String get siteLikeSignIn => '登录后点赞';

  @override
  String get siteConfigUnavailable => '社区配置不可用';

  @override
  String get siteFeedHint => '点击作品，旋转、缩放查看。';

  @override
  String get siteFeedEmpty => '社区暂时没有公开作品。';

  @override
  String get siteFeedRetry => '社区暂时未能连接，请重试';

  @override
  String get siteReload => '重新加载';

  @override
  String get siteSharedUnavailable => '分享的作品暂不可访问。';

  @override
  String get siteSharedNotPublic => '分享的作品暂不可访问，可能已取消公开。';

  @override
  String get siteInvalidCursor => '无效作品游标';

  @override
  String get siteInvalidAsset => '无效作品地址';

  @override
  String get siteUnsupportedFormat => '请在社区中查看此格式';

  @override
  String get siteLargeWork => '该作品较大或大小未确认，请进入完整社区查看';

  @override
  String get siteInvalidWork => '无效作品链接';

  @override
  String get siteInvalidAuthors => '无效作者列表';

  @override
  String get siteYesterday => '昨天';

  @override
  String get siteDayBeforeYesterday => '前天';

  @override
  String siteMonthDay(Object day, Object month) {
    return '$month月$day日';
  }

  @override
  String get siteGalleryCollapse => '收起 3D ';

  @override
  String get siteGalleryRotate => '旋转查看 3D ';

  @override
  String get siteMotionReducedAria => '系统已启用减少动态效果';

  @override
  String get siteMotionPlayAria => '播放几何动效';

  @override
  String get siteMotionPauseAria => '暂停几何动效';

  @override
  String get siteMotionReduced => '已减少动态效果';

  @override
  String get siteMotionPlay => '播放动效';

  @override
  String get siteMotionPause => '暂停动效';

  @override
  String get meCloudUnavailable => '云端暂不可用，稍后重试';

  @override
  String get meDenseStageCannotRebuild => '这个作品已进入稠密阶段，\n不能再重建。';

  @override
  String get meThisCapture => '这次拍摄';

  @override
  String meQuotedCaptureName(String name) {
    return '「$name」';
  }

  @override
  String get meRegenerateTitle => '重新重建？';

  @override
  String get meResumeTitle => '继续重建？';

  @override
  String meRegenerateBody(String name) {
    return '将用$name已保存的重建数据重新生成点云，完成后覆盖现有点云，无需重拍。';
  }

  @override
  String meResumeBody(String name) {
    return '$name的点云还没有生成。拍摄数据已完整保存，可以从中断处继续重建，无需重拍。';
  }

  @override
  String get meRegenerateAction => '重新重建';

  @override
  String get meResumeAction => '继续重建';

  @override
  String get meStartTraining => '开始训练';

  @override
  String get meCaptureMorePhotos => '拍摄更多照片';

  @override
  String get mePhotosRebuildUnsupported => '这个项目不是官方管线拍的，\n无法从照片重建。';

  @override
  String get mePhotosRebuildUnavailable => '从照片重建的入口没有接上。';

  @override
  String get meMorePhotosUnsupported => '这个项目不是官方管线拍的，\n暂不支持补拍。';

  @override
  String get meMorePhotosUnavailable => '补拍入口没有接上。';

  @override
  String get meMorePhotosWait => '另一个项目正在重建中。\n等它完成后再补拍。';

  @override
  String get meMorePhotosMissingData => '找不到这次拍摄的重建数据，\n无法补拍。';

  @override
  String meTrainingNeedsPhotos(int minimum, int count, int needed) {
    return '要开始训练，必须至少拍摄 $minimum 张照片。\n这次拍摄只有 $count 张，还需要 $needed 张。\n请继续拍摄补足。';
  }

  @override
  String get meTrainingWait => '另一个项目正在重建中。\n同时只能跑一个，等它完成后再来。';

  @override
  String get meTrainingMissingData => '这次拍摄的重建数据已损坏，照片也不在了，\n无法重建。';

  @override
  String get meCloudPending => '待同步';

  @override
  String get meCloudSyncing => '同步中';

  @override
  String get meCloudSaved => '已保存到云端';

  @override
  String get splashSolving => '正在解算';

  @override
  String get captureExitTitle => '退出拍摄？';

  @override
  String get captureExitSavePrompt => '是否保存照片，方便下次补拍';

  @override
  String get captureExitSavePhotos => '保存照片';

  @override
  String get meCloudIdConflict => '作品编号冲突，本地作品已保留';

  @override
  String get meCloudNewerVersion => '云端已有新版本，本地版本已保留';

  @override
  String get meCloudNameConflict => '存在同名作品，作品已保留，请重命名';

  @override
  String get meCloudRetryKept => '云端暂不可用或额度不足，作品已保留，稍后自动重试';

  @override
  String get legalPrivacyS0Title => '引言';

  @override
  String get legalPrivacyS0P0 =>
      '「方寸间」(以下称\"本产品\")由【公司名称待注册后填写】(以下称\"我们\")运营。本政策说明我们如何收集、使用、存储、保护您的个人信息,以及您享有的权利和行使方式。请您在使用本产品前仔细阅读本政策,特别是加粗显示的条款。';

  @override
  String get legalPrivacyS0P1 => '先说五个要点,细节在正文里:';

  @override
  String get legalPrivacyS0P2 =>
      '① 您拍摄的源照片只在您的手机上处理,永远不会上传 —— 上传的只有重建生成的三维点云和由点云渲染的缩略图;';

  @override
  String get legalPrivacyS0P3 => '② 本产品没有嵌入任何第三方统计、广告、推送或崩溃收集组件,不含任何形式的用户跟踪;';

  @override
  String get legalPrivacyS0P4 => '③ 我们不与任何第三方共享您的个人信息;';

  @override
  String get legalPrivacyS0P5 => '④ 注销账号将删除您的个人信息(法定留存的除外,见第四章);';

  @override
  String get legalPrivacyS0P6 =>
      '⑤ 依照国家关于互联网用户账号信息管理的规定,我们会公开展示您的账号 IP 属地(省级),该展示无法关闭。';

  @override
  String get legalPrivacyS0P7 =>
      '如果您不同意本政策,请不要注册或使用本产品。基于法律法规规定必须处理的信息(如 IP 属地展示)不因您的不同意而免除。';

  @override
  String get legalPrivacyS1Title => '一、我们收集哪些个人信息,用来做什么';

  @override
  String get legalPrivacyS1P0 =>
      '我们只在下列五个场景收集个人信息。每一项都标注了目的、方式与保存期限;除手机号外,其余各项均为可选,拒绝提供不影响您使用其余功能。';

  @override
  String get legalPrivacyS1P1 => '(一)账号注册与登录';

  @override
  String get legalPrivacyS1P2 =>
      '· 手机号码【必要】:用于注册账号、登录,以及依照《网络安全法》与《互联网用户账号信息管理规定》进行真实身份认证。网络社区类服务的必要个人信息为注册用户的移动电话号码 —— 这是本政策中唯一一项拒绝提供即无法注册使用的信息。验证码短信由短信服务商代发(见第三章)。保存至账号注销。';

  @override
  String get legalPrivacyS1P3 =>
      '· 电子邮箱【可选】:绑定后用于账号找回与重要通知。拒绝提供不影响任何功能。保存至解绑或账号注销。';

  @override
  String get legalPrivacyS1P4 =>
      '· 登录口令【敏感信息】:仅以单向加密(哈希)形式存储,我们无法查看您的明文口令;传输全程加密。口令属于个人敏感信息,请勿使用与其他平台相同的口令。';

  @override
  String get legalPrivacyS1P5 =>
      '· 昵称、账号 ID、个人简介【可选】:用于在社区中展示您的身份。昵称可重复,账号 ID 全站唯一。这三项会公开展示。保存至您修改或账号注销。';

  @override
  String get legalPrivacyS1P6 => '(二)拍摄与三维重建 —— 全部在您的手机上完成';

  @override
  String get legalPrivacyS1P7 => '· 相机画面与运动传感器数据:仅用于本机的拍摄引导与三维重建,不上传、不存储于服务器。';

  @override
  String get legalPrivacyS1P8 =>
      '· 源照片:保存在您设备内本产品的文档目录中,您可以通过系统\"文件\"应用自行查看、导出或删除。我们不收集源照片 —— 它们不会以任何形式离开您的设备。';

  @override
  String get legalPrivacyS1P9 => '· 重建生成的三维点云:在您选择发布之前,仅存于您的设备。';

  @override
  String get legalPrivacyS1P10 => '(三)作品发布与社区互动';

  @override
  String get legalPrivacyS1P11 =>
      '· 作品内容【可选,发布功能所必需】:您发布作品时,我们收集三维点云模型文件、作品缩略图(由点云渲染生成,不是相机照片)、标题与描述。作品经审核通过后对所有用户(含未登录访客)公开展示。';

  @override
  String get legalPrivacyS1P12 =>
      '· 发布时您已知悉:作品发布并通过审核后,作品内容、您的昵称、账号 ID 及发布时的 IP 属地将对所有人可见。';

  @override
  String get legalPrivacyS1P13 =>
      '· IP 属地:依照《互联网用户账号信息管理规定》第十二条,我们在作品信息中展示您发布那一刻的 IP 属地,在账号信息页面展示您最近使用时的 IP 属地。境内展示到省(自治区、直辖市),境外展示到国家(地区),不展示更精确的位置。属地由系统根据 IP 地址自动判定,无法由您或我们手工修改;如有异议可通过第九章的方式申诉。';

  @override
  String get legalPrivacyS1P14 =>
      '· 科研与技术改进用途:您上传的作品内容将用于我们内部的科学研究、技术开发与改进,包括但不限于各类人工智能算法与模型的训练、评测与优化(如三维重建相关算法与模型)。对外提供研究数据时,仅使用经匿名化处理、无法识别您身份且不能复原的数据,或另行征得您的单独同意。详见《方寸间用户协议》第六章。';

  @override
  String get legalPrivacyS1P15 =>
      '· 点赞、举报、屏蔽记录:用于实现相应功能与社区治理。公开作品的点赞对其他用户可见;举报内容仅您本人与平台管理人员可见。保存至您撤销相应操作、相关作品删除或账号注销。';

  @override
  String get legalPrivacyS1P16 =>
      '· 浏览记录:仅用于向作品作者展示浏览计数,按小时去重,不用于任何形式的个性化推荐或广告。保存至相关作品删除;您注销账号后即匿名化,不再与您关联。';

  @override
  String get legalPrivacyS1P17 => '(四)安全保障';

  @override
  String get legalPrivacyS1P18 =>
      '· IP 地址与设备标识串(User-Agent):在注册、登录、发布、删除、举报等关键操作时记录于安全审计日志,用于安全防护、防滥用,以及依法配合监管。IP 地址同时用于生成上述省级属地展示 —— 这两项用途在此一并告知,我们不会将其用于其他目的。一般审计记录保存 180 天;涉及账号注销与内容处置的记录保存 730 天;期满由系统自动删除。';

  @override
  String get legalPrivacyS1P19 => '· 接口频次记录:为防止滥用,对接口调用做短暂的频次记录,保存不超过 1 天。';

  @override
  String get legalPrivacyS1P20 => '(五)产品改进与统计分析';

  @override
  String get legalPrivacyS1P21 =>
      '· 使用情况事件:为了解产品被如何使用、发现并修复故障,我们收集功能使用事件(如发布流程的开始、成功或失败及失败阶段)、会话标识、错误与崩溃摘要(错误信息与截断的代码堆栈,不含您的作品内容或个人资料)、系统版本与 App 版本。统计为我们自行建设,数据仅进入我们自己的服务器,不经任何第三方统计组件。保存 180 天,期满自动删除;注销账号后与您的身份解除关联(匿名化)。';

  @override
  String get legalPrivacyS1P22 =>
      '· 统计属于非必要信息:您可以随时在\"设置 → 帮助改进产品\"中关闭,关闭后我们停止收集并清除设备上尚未上报的统计数据,不影响任何功能的使用。';

  @override
  String get legalPrivacyS1P23 =>
      '(六)依照法律法规,以下情形处理个人信息无需征得您的同意:为履行法定职责或法定义务所必需;为应对突发公共卫生事件或紧急情况下保护自然人生命健康财产安全所必需;在合理范围内处理您自行公开或其他已合法公开的个人信息;法律、行政法规规定的其他情形。';

  @override
  String get legalPrivacyS2Title => '二、设备权限与本地存储说明';

  @override
  String get legalPrivacyS2P0 => '本产品只申请以下两项系统权限,均在您首次使用对应功能时申请,不会在启动时索取:';

  @override
  String get legalPrivacyS2P1 =>
      '· 相机:用于拍摄照片以进行本机三维重建。拒绝授权将无法拍摄,但不影响浏览社区等其他功能。';

  @override
  String get legalPrivacyS2P2 =>
      '· 运动与健身(运动传感器):用于拍摄时的实时引导与相机位姿估计,数据仅在本机处理。拒绝授权将影响拍摄引导的准确性。';

  @override
  String get legalPrivacyS2P3 =>
      '我们不申请定位、通讯录、麦克风、照片库等任何其他权限。您可以随时在系统设置中关闭已授予的权限,关闭不影响此前基于授权已进行处理的效力。';

  @override
  String get legalPrivacyS2P4 =>
      '本地存储说明:本产品不内嵌网页浏览器,不使用 Cookie。以下信息仅保存在您的设备本地,不会被我们读取用于本政策未载明的目的:登录凭据(保存在系统钥匙串中)、语言与界面偏好设置、浏览他人作品时的临时文件缓存(用于加快加载,可随系统清理),以及您拍摄的源照片与重建产物(见第一章第(二)节)。';

  @override
  String get legalPrivacyS3Title => '三、委托处理、共享、转让与公开披露';

  @override
  String get legalPrivacyS3P0 => '我们不从任何第三方间接获取您的个人信息;本章描述的是信息从我们这里流向何处。';

  @override
  String get legalPrivacyS3P1 =>
      '(一)委托处理。以下服务商仅按照我们的指令处理相应信息,我们与其签订数据处理协议,约定处理目的、期限、方式、信息种类与保护措施,并对其处理活动进行监督:';

  @override
  String get legalPrivacyS3P2 =>
      '· 云基础设施服务商(数据库与文件存储):阿里云计算有限公司,存储本政策第一章所列服务端信息;';

  @override
  String get legalPrivacyS3P3 => '· 短信服务商:阿里云(发送登录验证码,接触您的手机号码);';

  @override
  String get legalPrivacyS3P4 =>
      '· 邮件服务商:【邮件服务商待填写 —— 上线前确认为境内服务商】(发送邮箱验证码,接触您的电子邮箱)。';

  @override
  String get legalPrivacyS3P5 =>
      '(二)共享:我们不与任何第三方共享您的个人信息。经匿名化处理、无法识别特定个人且不能复原的信息,依法不属于个人信息;我们在对外科研合作中仅使用此类匿名化数据(见第一章第(三)节)。';

  @override
  String get legalPrivacyS3P6 =>
      '(三)第三方 SDK 清单:本产品未嵌入任何第三方统计、广告、推送或崩溃收集 SDK。如未来接入,我们将在接入前更新本政策与本清单,并重新征得您的同意。';

  @override
  String get legalPrivacyS3P7 =>
      '(四)转让:发生合并、分立、解散或被收购时,我们会告知您接收方的名称与联系方式,并要求其继续履行本政策;接收方变更处理目的、方式的,将重新征得您的同意。';

  @override
  String get legalPrivacyS3P8 =>
      '(五)公开披露:除第一章已告知的法定属地展示与您主动公开发布的内容外,我们不公开披露您的个人信息;依法配合监管部门、司法机关的除外。';

  @override
  String get legalPrivacyS4Title => '四、信息的存储与保护';

  @override
  String get legalPrivacyS4P0 => '1. 存储地点:您的个人信息存储于中华人民共和国境内。';

  @override
  String get legalPrivacyS4P1 =>
      '2. 存储期限:各类信息的保存期限已在第一章逐项写明,汇总如下 —— 账号资料(手机号/邮箱/昵称/ID/简介)保存至注销;作品及互动记录保存至删除或注销;浏览记录于注销后匿名化;统计事件 180 天;安全审计日志 180 天(重大操作 730 天);接口频次记录不超过 1 天;注册过程中的临时验证数据 10 分钟。超出期限的信息由系统自动删除或匿名化。';

  @override
  String get legalPrivacyS4P2 =>
      '3. 法定留存例外:因内容治理需要,被依法下架作品的文件副本将单独封存留存,用于处置争议与配合监管,在此期间不用于任何其他目的;该副本在注销账号后仍可能在必要期限内留存。';

  @override
  String get legalPrivacyS4P3 =>
      '4. 保护措施:全部传输经加密通道(TLS);口令单向哈希存储;数据库启用行级访问控制,任何用户无法读取他人的非公开数据;登录凭据保存在系统钥匙串中;关键操作留有审计记录;内容上传采用两阶段校验,未通过校验的文件不会进入公开存储。';

  @override
  String get legalPrivacyS4P4 =>
      '5. 安全事件:一旦发生个人信息泄露、篡改、丢失,我们将立即采取补救措施,按照法律要求告知您事件情况、可能的影响与补救措施,并向监管部门报告。';

  @override
  String get legalPrivacyS4P5 =>
      '6. 停止运营:本产品停止运营时,我们将停止收集个人信息,以公告形式通知您,并对已存个人信息进行删除或匿名化处理。';

  @override
  String get legalPrivacyS5Title => '五、您的权利';

  @override
  String get legalPrivacyS5P0 => '您对自己的个人信息享有知情权与决定权,有权限制或拒绝处理。具体如下:';

  @override
  String get legalPrivacyS5P1 =>
      '1. 查阅、复制:您的账号资料与作品可在\"我的\"页面直接查看;其余与您相关的信息(如审计日志中的记录)可通过第九章的联系方式申请查阅、复制。';

  @override
  String get legalPrivacyS5P2 =>
      '2. 更正、补充:昵称、账号 ID、简介可在\"设置\"中直接修改;IP 属地由系统自动判定、不可手工修改,如有异议可申诉。';

  @override
  String get legalPrivacyS5P3 =>
      '3. 删除:您可以随时在作品页删除自己的作品(含审核中的作品),删除后服务器上的文件一并删除;其他删除请求可通过联系方式提出。出现处理目的已实现、我们停止服务、您撤回同意、我们违法违约处理等法定情形时,我们将主动删除。法律法规规定的保存期限未届满或技术上难以实现删除的,我们将停止除存储和采取必要安全保护措施之外的处理。';

  @override
  String get legalPrivacyS5P4 =>
      '4. 撤回同意:您可以通过关闭系统权限、删除相应信息或注销账号撤回相应同意,也可以通过联系方式向我们提出。撤回不影响撤回前基于同意已进行处理的效力。我们不会因您撤回同意而拒绝提供与所撤回事项无关的功能。';

  @override
  String get legalPrivacyS5P5 => '5. 解释说明:您有权要求我们对本政策与个人信息处理规则作出解释说明。';

  @override
  String get legalPrivacyS5P6 =>
      '6. 逝者近亲属权利:用户不幸去世后,其近亲属为了自身合法、正当利益,可凭死亡证明与亲属关系证明,通过第九章联系方式对逝者相关个人信息行使查阅、复制、更正、删除等权利;逝者生前另有安排的除外。';

  @override
  String get legalPrivacyS5P7 =>
      '7. 响应时限:对上述请求,我们在验证您的身份后于 15 个工作日内响应。拒绝请求的,我们会说明理由;您可以向网信部门(www.12377.cn)、电信主管部门(www.12321.cn)投诉举报,或依法向人民法院提起诉讼。';

  @override
  String get legalPrivacyS6Title => '六、账号注销';

  @override
  String get legalPrivacyS6P0 => '您可以在\"设置 → 账号\"中随时注销账号,无需人工审核、不设任何前置条件。';

  @override
  String get legalPrivacyS6P1 =>
      '注销后:您的账号资料、作品、点赞与举报记录将被删除,浏览记录被匿名化;安全审计日志按第四章期限留存后自动删除;被依法下架作品的封存副本按第四章第 3 条处理。我们不保留您的手机号或邮箱用于任何其他目的。';

  @override
  String get legalPrivacyS6P2 => '注销为不可逆操作,请在操作前自行备份需要保留的作品。注销在 15 个工作日内完成。';

  @override
  String get legalPrivacyS7Title => '七、未成年人保护';

  @override
  String get legalPrivacyS7P0 => '本产品仅面向年满 14 周岁的用户。不满 14 周岁的未成年人不得注册或使用本产品。';

  @override
  String get legalPrivacyS7P1 =>
      '我们不会在知情的情况下收集不满 14 周岁未成年人的个人信息;一经发现,将立即删除相关信息并注销相关账号。';

  @override
  String get legalPrivacyS7P2 =>
      '已满 14 周岁、不满 18 周岁的未成年人使用本产品,应当在监护人指导下阅读并同意本政策。监护人对未成年人使用本产品有异议或发现未成年人个人信息相关问题的,可通过第九章联系方式与我们联系,我们将优先处理。';

  @override
  String get legalPrivacyS7P3 => '涉及未成年人的举报在内容治理中享有最高处理优先级。';

  @override
  String get legalPrivacyS8Title => '八、本政策的更新';

  @override
  String get legalPrivacyS8P0 =>
      '本政策可能适时修订。修订后我们会在 App 内以公告等显著方式通知您,并更新文首的版本号与生效日期。';

  @override
  String get legalPrivacyS8P1 =>
      '处理目的、处理方式、处理的个人信息种类发生变更的,我们将重新征得您的同意,而不是默认继续。';

  @override
  String get legalPrivacyS8P2 => '我们保留本政策的历史版本,您可通过第九章的联系方式索取。';

  @override
  String get legalPrivacyS9Title => '九、如何联系我们';

  @override
  String get legalPrivacyS9P0 => '个人信息处理者:【公司名称待注册后填写】';

  @override
  String get legalPrivacyS9P1 => '注册地址:【公司注册地待定后填写】';

  @override
  String get legalPrivacyS9P2 =>
      '个人信息保护负责人邮箱:【联系邮箱待填写 —— 上线前必须替换为真实可达邮箱,与平台公约页同一个】';

  @override
  String get legalPrivacyS9P3 =>
      '我们在验证您的身份后于 15 个工作日内答复。对答复不满意的,您可以向网信、电信、公安、市场监管等部门投诉举报,或依法向人民法院提起诉讼。';

  @override
  String get legalAgreementS0Title => '一、导言';

  @override
  String get legalAgreementS0P0 =>
      '欢迎使用「方寸间」。本协议是您与【公司名称待注册后填写】(以下称\"我们\"或\"平台\")之间关于使用方寸间软件及相关服务的约定。请在注册前完整阅读本协议,特别是以加粗方式显示的免除或限制责任、权利许可、争议管辖等条款。';

  @override
  String get legalAgreementS0P1 =>
      '《方寸间平台公约》(含账号管理规则)与《方寸间隐私政策》是本协议不可分割的组成部分,与本协议具有同等效力。您接受本协议,即视为同时接受上述文件。';

  @override
  String get legalAgreementS0P2 =>
      '您通过页面点击确认、完成注册或实际使用本服务,即表示已阅读并同意本协议。如您不同意本协议,请不要注册或使用。';

  @override
  String get legalAgreementS0P3 => '本协议以中文写就并以中文为准;界面中的任何翻译仅为方便阅读提供。';

  @override
  String get legalAgreementS1Title => '二、服务说明';

  @override
  String get legalAgreementS1P0 =>
      '方寸间是一款三维空间内容工具与社区:您用手机拍摄,在设备本机重建出三维点云作品,并可选择将作品发布到社区广场与其他用户分享。';

  @override
  String get legalAgreementS1P1 =>
      '本产品的三维重建功能使用了深度合成类技术(基于人工智能模型的三维重建)。依照《互联网信息服务深度合成管理规定》,我们在此显著提示:您使用本服务制作、发布信息内容,应当依法承担信息安全义务,不得利用本服务制作、复制、发布、传播法律法规禁止的信息,不得利用本服务从事危害国家安全和利益、损害国家形象、侵害社会公共利益、扰乱经济和社会秩序、侵犯他人合法权益等活动。';

  @override
  String get legalAgreementS1P2 =>
      '依照上述规定,平台对发布的作品文件采取技术标识措施(生成方式标识内嵌于模型文件中)。您不得删除、篡改、隐匿该标识。';

  @override
  String get legalAgreementS1P3 =>
      '服务的具体形态(功能、界面、规则)可能随产品迭代调整;涉及您重大权益的调整按第十二章的程序进行。';

  @override
  String get legalAgreementS1P4 =>
      '我们授予您一项个人的、不可转让、不可转授权、非排他的许可,供您为非商业目的下载、安装并使用本软件。';

  @override
  String get legalAgreementS1P5 =>
      '请通过官方渠道(如 App Store)获取本软件;使用非官方渠道获取的版本可能存在安全风险,由此产生的后果由您自行承担。';

  @override
  String get legalAgreementS1P6 => '使用本服务所需的终端设备与网络流量费用由您自行承担。';

  @override
  String get legalAgreementS1P7 =>
      '本服务面向中华人民共和国大陆地区用户提供,我们不保证本服务在其他司法辖区的可用性与适当性。';

  @override
  String get legalAgreementS2Title => '三、账号注册与管理';

  @override
  String get legalAgreementS2P0 =>
      '1. 年龄要求:您必须年满 14 周岁方可注册和使用本服务。不满 18 周岁的,还应当由监护人陪同阅读本协议并取得监护人同意。';

  @override
  String get legalAgreementS2P1 =>
      '2. 真实身份认证:依照法律规定,注册需要基于移动电话号码完成真实身份认证。未完成认证的,无法注册及使用发布、点赞等信息发布类功能。';

  @override
  String get legalAgreementS2P2 =>
      '3. 账号信息规范:您设置的昵称、账号 ID、简介等账号信息不得违反法律法规和平台公约,不得假冒、仿冒、恶意关联党政军机关、企事业单位、新闻媒体或社会知名人士,不得使用可能被误认为平台官方身份的名称;含\"中国\"\"国家\"等字样或涉及国旗国徽等标识的,平台将按国家有关规定从严核验,并有权要求您补充证明材料或不予通过。';

  @override
  String get legalAgreementS2P3 =>
      '4. 账号归属与安全:账号仅限您本人使用。未经平台书面同意,不得赠与、出借、出租、转让、售卖、继承账号或以其他方式许可他人使用。通过您的账号实施的一切行为,视为您本人的行为,由您承担相应责任。您应妥善保管登录凭据;发现账号被他人冒用、盗用的,请立即通过第十四章的联系方式通知平台,平台可视情况采取临时冻结等保护措施。因您保管不善导致的损失由您自行承担,但因平台原因导致的除外。';

  @override
  String get legalAgreementS2P4 =>
      '5. 账号注销:您可以随时在\"设置 → 账号\"中注销账号,注销流程与数据处理见《方寸间隐私政策》。';

  @override
  String get legalAgreementS3Title => '四、用户行为规范';

  @override
  String get legalAgreementS3P0 =>
      '1. 您不得利用本服务制作、复制、发布、传播含有下列内容的信息:反对宪法确定的基本原则的;危害国家安全,泄露国家秘密,颠覆国家政权,破坏国家统一的;损害国家荣誉和利益的;歪曲、丑化、亵渎、否定英雄烈士事迹和精神的;宣扬恐怖主义、极端主义或者煽动实施恐怖活动、极端主义活动的;煽动民族仇恨、民族歧视,破坏民族团结的;破坏国家宗教政策,宣扬邪教和封建迷信的;散布谣言,扰乱经济秩序和社会秩序的;散布淫秽、色情、赌博、暴力、凶杀、恐怖或者教唆犯罪的;侮辱或者诽谤他人,侵害他人名誉、隐私和其他合法权益的;法律、行政法规禁止的其他内容。';

  @override
  String get legalAgreementS3P1 =>
      '2. 您应当防范和抵制制作、复制、发布含有下列内容的不良信息:使用夸张标题,内容与标题严重不符的;炒作绯闻、丑闻、劣迹的;不当评述自然灾害、重大事故等灾难的;带有性暗示、性挑逗等易使人产生性联想的;展现血腥、惊悚、残忍等致人身心不适的;煽动人群歧视、地域歧视的;宣扬低俗、庸俗、媚俗内容的;可能引发未成年人模仿不安全行为和违反社会公德行为、诱导未成年人不良嗜好的;其他对网络生态造成不良影响的内容。';

  @override
  String get legalAgreementS3P2 =>
      '3. 三维作品的特别规范:拍摄并公开发布涉及他人住宅、办公场所等非公开空间的三维重建,应当事先取得权利人同意;画面或点云中可识别到特定他人的,应当取得该他人同意。不得发布涉及国家安全敏感区域、军事设施等法律法规禁止测绘、拍摄场所的三维重建。';

  @override
  String get legalAgreementS3P3 =>
      '4. 您不得从事下列行为:利用技术手段批量注册账号;对本产品进行反向工程、破解或绕过技术保护措施(法律法规允许的除外);未经授权抓取、下载、复制其他用户的作品用于本服务之外的用途;以自动化手段高频调用本服务或采集数据;干扰、破坏本服务的正常运行;制作、传播病毒、木马等恶意程序,或未经授权访问平台系统、他人账号;发布垃圾信息、恶意营销信息;以平台名义行事,或对外宣称与平台存在合作、代理等关系误导他人。';

  @override
  String get legalAgreementS3P4 =>
      '5. 三维拍摄需要您在现场移动。请注意周围环境与自身及他人安全,不要在道路、高处边缘等危险环境中拍摄。';

  @override
  String get legalAgreementS4Title => '五、内容发布与审核';

  @override
  String get legalAgreementS4P0 =>
      '1. 先审后发:您发布的作品需经平台审核,审核通过后才会出现在社区广场;审核期间作品对其他用户不可见,您可以随时删除。';

  @override
  String get legalAgreementS4P1 =>
      '2. 发布即公开:作品通过审核后,作品内容、您的昵称、账号 ID 及发布时的 IP 属地将对所有用户(含未登录访客)公开可见。IP 属地展示是法定要求,无法关闭,详见《方寸间隐私政策》。';

  @override
  String get legalAgreementS4P2 =>
      '3. 本协议所称\"内容\"包括您在本服务中上传、发布的三维点云模型、三维重建数据、缩略图、标题、描述、账号资料以及其他任何信息。';

  @override
  String get legalAgreementS4P3 =>
      '4. 您对发布的内容独立承担全部法律责任。您保证对发布的内容享有合法权利或已取得合法授权;因您发布的内容引发第三方主张权利,导致平台遭受损失的,您应当赔偿。';

  @override
  String get legalAgreementS4P4 =>
      '5. 第三方就您发布的内容向平台主张权利时,平台有权依法先行下架相关内容并通知您;您可按第八章的渠道提交不侵权声明与权利证明进行申诉。';

  @override
  String get legalAgreementS5Title => '六、知识产权';

  @override
  String get legalAgreementS5P0 =>
      '1. 平台软件及其所含的界面设计、程序代码、商标标识等知识产权归我们或相应权利人所有。未经许可,您不得复制、修改、传播或用于任何商业目的。';

  @override
  String get legalAgreementS5P1 =>
      '2. 您在本服务中发布的作品(含三维点云模型及其衍生的缩略图)的知识产权归您或依法享有权利的权利人所有,不因发布行为而转移。';

  @override
  String get legalAgreementS5P2 =>
      '3. 为向您提供服务并改进产品,您授予平台一项全球范围内、免费、非独家的许可,包括对内容的复制权、信息网络传播权、改编权、汇编权、展示权及制作衍生内容的权利。本款所称内容,指您上传至本服务的内容,包括发布到社区广场的作品,以及未来云端存储功能中您存储的内容,含三维点云、网格模型、缩略图、标题、描述。上述权利仅用于:(1)运营所必需:存储、备份、传输、分发、公开展示(仅限您选择公开发布的内容)及格式适配等技术处理,并可将上述处理委托给受本协议约束的云服务商执行;(2)将您已公开发布的作品用于本产品各终端版本及应用商店页面的展示与推介;(3)我们内部的科学研究、技术开发与改进,包括但不限于各类人工智能算法与模型的训练、评测与优化(如三维重建相关算法与模型),不论采用现在已知或日后开发的技术与形式。';

  @override
  String get legalAgreementS5P3 =>
      '4. 对外提供研究数据:我们如需在学术论文、公开数据集或科研合作中对外提供研究数据,仅使用经匿名化处理、无法识别您的身份且不能复原的数据;需要以可识别您身份的形式对外提供的,我们将另行征得您的单独同意。';

  @override
  String get legalAgreementS5P4 =>
      '5. 许可的期限与终止:上述许可自内容上传时生效。您删除相应内容,或注销账号(指您依照第三章第 5 条及《方寸间隐私政策》第六章,主动申请删除账号及其项下个人信息的行为)后,除法律法规另有规定或本协议另有约定(如依法下架内容的封存留存)外,许可即告终止,我们将停止在新的研究与模型训练中使用该内容;但在此之前已完成的研究成果与已训练完成的模型不受影响。';

  @override
  String get legalAgreementS5P5 =>
      '6. 为更好地保护您的权益,您同意平台有权自行或委托第三方,对您上传发布且享有知识产权的内容遭受第三方侵权的行为进行维权,形式包括但不限于监测侵权行为、发送维权函、提起诉讼或仲裁、调解、和解等。您可以随时书面通知平台撤回本款维权授权。';

  @override
  String get legalAgreementS5P6 =>
      '7. 您认为本服务中的内容侵犯您的合法权益的,可按第八章的渠道通知我们,并提供权属证明与初步侵权证据;我们将依法及时处理。';

  @override
  String get legalAgreementS5P7 =>
      '8. 平台在开发、运营本服务过程中产生的、不包含您作品内容本身的数据与成果(如统计数据、日志、经匿名化处理的分析结果、算法与模型参数、研究成果),由平台在法律法规允许的范围内享有权利。本条不改变第 2 条约定的作品归属。';

  @override
  String get legalAgreementS6Title => '七、违规处置与申诉';

  @override
  String get legalAgreementS6P0 =>
      '1. 您违反本协议、平台公约或法律法规的,平台有权视情节轻重依法依约采取下列一项或多项措施:警示提醒、限期改正、限制账号功能、暂停使用、关闭账号、禁止重新注册。违规作品将被下架,其文件从公开位置移出。';

  @override
  String get legalAgreementS6P1 =>
      '2. 采取上述措施时,平台会通过站内通知等方式告知您理由。平台将保存有关记录,并依法向有关主管部门报告。';

  @override
  String get legalAgreementS6P2 =>
      '3. 申诉:您对处置结果有异议的,可通过第十四章的联系方式提出申诉,并提供相应说明与证据。我们在收到申诉后 15 个工作日内复核并答复。';

  @override
  String get legalAgreementS6P3 => '4. 平台将依照国家规定逐步建立账号信用管理制度,根据账号信用情况提供相应服务。';

  @override
  String get legalAgreementS7Title => '八、投诉与举报';

  @override
  String get legalAgreementS7P0 =>
      '1. 每个作品页面均提供举报入口。您也可以通过第十四章的联系方式投诉、举报违法违规内容或行为。';

  @override
  String get legalAgreementS7P1 =>
      '2. 我们建立公众投诉举报受理机制,及时受理并处理投诉举报。涉及未成年人的举报优先处理;收到未成年人或其监护人关于网络欺凌内容的通知后,我们将及时采取删除、屏蔽等必要措施。';

  @override
  String get legalAgreementS8Title => '九、服务的变更、中断与终止';

  @override
  String get legalAgreementS8P0 =>
      '1. 平台可能因法律法规变化、监管要求、技术升级或运营调整变更、中断部分或全部服务;因系统维护、故障、不可抗力导致服务中断的,平台将尽合理努力及时恢复。';

  @override
  String get legalAgreementS8P1 =>
      '2. 平台决定停止全部服务运营的,将提前 30 日在 App 内公告,并在停止运营前为您提供作品文件的导出通道。同时建议您平时对重要作品自行备份。';

  @override
  String get legalAgreementS8P2 =>
      '3. 平台发生合并、分立、被收购等情形需要向承继方转移服务的,将依法通知您;承继方将继续受本协议及《方寸间隐私政策》约束,否则将重新征得您的同意。';

  @override
  String get legalAgreementS8P3 => '4. 服务终止后,平台将按《方寸间隐私政策》对您的个人信息进行删除或匿名化处理。';

  @override
  String get legalAgreementS8P4 =>
      '5. 平台可将本服务的部分运营、技术支持工作委托给关联公司或专业服务商执行,平台仍就本协议向您承担责任。';

  @override
  String get legalAgreementS9Title => '十、免责声明与责任限制';

  @override
  String get legalAgreementS9P0 =>
      '1. 本服务按\"现状\"和\"可得到\"的状态提供。在法律允许的范围内,平台不对服务无中断、无错误、完全安全作出保证;三维重建的效果受拍摄环境、设备性能等因素影响,平台不保证重建结果符合您的特定预期。本产品的三维重建由人工智能技术实现,现阶段技术存在难以完全避免的局限,重建结果可能存在误差、缺失或失真。';

  @override
  String get legalAgreementS9P1 =>
      '2. 因不可抗力(自然灾害、罢工、网络基础设施故障、监管政策变化等)、第三方原因(基础电信服务中断、第三方服务商故障等)或您自身原因导致的损失,平台在法律允许的范围内不承担责任。';

  @override
  String get legalAgreementS9P2 =>
      '3. 在法律允许的最大范围内,平台不对任何间接性、后果性、惩罚性损失承担责任;平台就本协议项下服务对您承担的赔偿责任总额,不超过您因使用本服务而向平台实际支付的费用总额(当前服务免费,则以法律规定的实际损失为限)。本条不适用于因平台故意或重大过失造成的损害,也不排除依法不得免除的责任。';

  @override
  String get legalAgreementS9P3 =>
      '4. 其他用户发布的内容仅代表其本人观点,不代表平台立场;您与其他用户之间的纠纷,可请求平台依据本协议协助处理,但平台不承担纠纷双方的民事责任。您通过本服务获取的任何内容与文件,请自行判断其适用性并承担使用风险;本服务如含指向第三方的链接或内容,该第三方内容不受平台控制,平台不对其准确性、安全性负责。';

  @override
  String get legalAgreementS9P4 =>
      '5. 平台依法对发布内容进行审核。审核不构成平台对内容合法性、真实性或质量的保证或背书,不免除发布者的法律责任。';

  @override
  String get legalAgreementS9P5 =>
      '6. 因平台违反法律法规或本协议约定给您造成损失的,平台依法承担相应的赔偿责任;因您违反法律法规或本协议给平台或第三方造成损失的,您亦应依法承担赔偿责任。';

  @override
  String get legalAgreementS10Title => '十一、未成年人条款';

  @override
  String get legalAgreementS10P0 =>
      '1. 本服务仅面向年满 14 周岁的用户。不满 14 周岁的未成年人不得注册或使用。';

  @override
  String get legalAgreementS10P1 =>
      '2. 已满 14 周岁、不满 18 周岁的未成年人使用本服务,应当取得监护人同意并在其指导下使用。监护人未同意的,可通过第十四章的联系方式通知平台,平台将依法处理相关账号。';

  @override
  String get legalAgreementS10P2 =>
      '3. 平台不制作、不推送诱导未成年人沉迷的内容,不设置任何诱导性打赏或消费功能;发现可能影响未成年人身心健康的内容,平台将依法处置。';

  @override
  String get legalAgreementS10P3 => '4. 发布含有未成年人形象的作品,应当依法取得其监护人的同意。';

  @override
  String get legalAgreementS11Title => '十二、协议的修改与通知';

  @override
  String get legalAgreementS11P0 =>
      '1. 我们可能因法律法规变化、监管要求或服务调整修改本协议。修改后的协议将在生效前至少 7 日在 App 内公示;对您权利义务有重大影响的修改,公示不少于 15 日。';

  @override
  String get legalAgreementS11P1 =>
      '2. 您不同意修改内容的,有权停止使用本服务并注销账号,注销前的权利义务按修改前的协议执行;公示期满后您继续使用本服务的,视为接受修改后的协议。我们不会将修改设定为默认同意的选项。';

  @override
  String get legalAgreementS11P2 => '3. 我们保留本协议的历史版本,您可通过第十四章的联系方式索取。';

  @override
  String get legalAgreementS11P3 =>
      '4. 平台向您发出的通知,可以通过 App 内公告、系统通知、页面提示、您绑定的手机号或电子邮箱等方式作出,自发布或发送之日视为送达;您向平台发出的通知,应通过第十四章公布的联系方式作出。';

  @override
  String get legalAgreementS12Title => '十三、法律适用与争议解决';

  @override
  String get legalAgreementS12P0 =>
      '1. 本协议的订立、效力、解释与争议解决,适用中华人民共和国(为本协议之目的,不含港澳台地区)法律。';

  @override
  String get legalAgreementS12P1 =>
      '2. 因本协议产生的争议,双方应友好协商;协商不成的,任何一方均可向【公司注册地待定后填写】有管辖权的人民法院提起诉讼。';

  @override
  String get legalAgreementS12P2 => '3. 本协议任一条款被认定无效或不可执行的,不影响其余条款的效力。';

  @override
  String get legalAgreementS12P3 => '4. 本协议标题仅为方便阅读而设,不作为解释条款含义的依据。';

  @override
  String get legalAgreementS12P4 => '5. 您与平台均为独立主体,本协议不在双方之间构成合伙、代理、雇佣或担保关系。';

  @override
  String get legalAgreementS12P5 => '6. 本协议及其组成文件构成双方就相关事项的完整约定。';

  @override
  String get legalAgreementS13Title => '十四、联系我们';

  @override
  String get legalAgreementS13P0 => '运营者:【公司名称待注册后填写】';

  @override
  String get legalAgreementS13P1 =>
      '联系邮箱:【联系邮箱待填写 —— 上线前必须替换为真实可达邮箱,与平台公约页、隐私政策同一个】';

  @override
  String get legalAgreementS13P2 => '我们在收到您的意见、投诉或申诉后 15 个工作日内处理并反馈。';

  @override
  String get legalRulesS0Title => '一、账号与名称';

  @override
  String get legalRulesS0P0 =>
      '昵称可以重复,ID 全站唯一 —— 这与微信、抖音、小红书的结构一致:昵称用来展示,ID 用来让别人找到你。';

  @override
  String get legalRulesS0P1 =>
      '昵称最多 20 个字,支持中文、英文与 emoji。首尾空格会被自动去除,中间连续空格会合并为一个。';

  @override
  String get legalRulesS0P2 =>
      'ID 由 2–32 个小写字母、数字、点或下划线组成,不能以点或下划线开头结尾,也不能出现连续的点或下划线。';

  @override
  String get legalRulesS0P3 => '昵称与 ID 设置后 3 天内不能再次修改。';

  @override
  String get legalRulesS0P4 =>
      '不得使用可能被误认为平台官方身份的名称,包括但不限于\"官方\"\"客服\"\"管理员\"\"系统通知\"\"小助手\"及其英文对应词。';

  @override
  String get legalRulesS0P5 =>
      '名称中含有\"中国\"\"中华\"\"中央\"\"全国\"\"国家\"等内容,或涉及国旗、国徽、国歌、党旗、党徽的,将按国家有关规定从严核验。';

  @override
  String get legalRulesS0P6 => '注册需要通过真实身份信息认证。未完成认证的账号无法发布内容。';

  @override
  String get legalRulesS1Title => '二、作品发布与审核';

  @override
  String get legalRulesS1P0 => '作品发布后进入审核状态,审核通过后才会出现在社区广场,在此之前对其他用户不可见。';

  @override
  String get legalRulesS1P1 => '作品标题不超过 100 字,作品描述不超过 30 字。';

  @override
  String get legalRulesS1P2 => '不得发布法律法规禁止的内容,包括危害国家安全、淫秽色情、暴力恐怖、虚假信息、侵犯他人权益等。';

  @override
  String get legalRulesS1P3 => '拍摄涉及他人的场景并公开发布前,应当取得画面中他人的同意。';

  @override
  String get legalRulesS1P4 =>
      '作品的三维模型文件中包含生成方式标识 —— 这是《互联网信息服务深度合成管理规定》第十六条要求的技术措施,不影响你正常使用文件。';

  @override
  String get legalRulesS2Title => '三、违规处置';

  @override
  String get legalRulesS2P0 =>
      '发现违规内容或行为时,平台可以采取以下措施:警示提醒、限期改正、限制账号功能、暂停使用、关闭账号。';

  @override
  String get legalRulesS2P1 => '违规作品会被下架,其文件将从公开位置移出,已保存的链接同时失效。';

  @override
  String get legalRulesS2P2 => '你可以随时删除自己的作品。正在审核中且从未公开过的作品同样可以删除。';

  @override
  String get legalRulesS2P3 => '账号相关的操作会被记录,保存期限不少于 6 个月。';

  @override
  String get legalRulesS3Title => '四、举报与申诉';

  @override
  String get legalRulesS3P0 =>
      '每个作品页面都提供举报入口,可选择垃圾信息、骚扰、仇恨言论、色情内容、暴力、侵权、虚假信息等理由。';

  @override
  String get legalRulesS3P1 => '你也可以屏蔽某个用户,屏蔽后其作品不再出现在你的信息流中。';

  @override
  String get legalRulesS3P2 => '对处置结果有异议的,可通过下方联系方式申诉。';

  @override
  String get legalRulesS4Title => '五、联系我们';

  @override
  String get legalRulesS4P0 => '邮箱:[待填写 —— 上线前必须替换为真实可达的联系邮箱]';

  @override
  String get legalRulesS4P1 => '我们会在收到举报或申诉后尽快处理并反馈。';

  @override
  String get legalRulesFooter => '本公约描述的是产品当前的实际规则。规则调整时本页同步更新。';

  @override
  String get legalPrivacyTitle => '方寸间隐私政策';

  @override
  String get legalAgreementTitle => '方寸间用户协议';

  @override
  String get legalVersionLabel => '版本';

  @override
  String get legalEffectiveDateLabel => '生效日期';

  @override
  String get legalEffectiveDatePending => '【生效日期待上线前填写】';

  @override
  String get legalTranslationNotice => '英文译文仅供阅读参考,本文件以中文为准。';

  @override
  String get sharedViewerTitle => 'PocketWorld 3D 查看器';

  @override
  String get sharedViewerCanvasLabel => '3D作品';

  @override
  String get sharedViewerInitializing => '正在初始化…';

  @override
  String get sharedViewerLoading => '正在加载…';

  @override
  String get sharedViewerFailure => '暂时无法显示作品，请重试。';

  @override
  String get sharedViewerSkpNotice => 'SKP 转换预览：复杂结构可能存在差异。';

  @override
  String get legalStaticV11Copy0 => '窗后城隐私政策｜北京空也科技有限公司';

  @override
  String get legalStaticV11Copy2 => '返回社区';

  @override
  String get legalStaticV11Copy3 => '窗后城隐私政策';

  @override
  String get legalStaticV11Copy4 => 'V1.1 · 生效日期：2026年11月2日';

  @override
  String get legalStaticV11Copy9 =>
      '「窗后城」(以下称\"本产品\")由北京空也科技有限公司(以下称\"我们\")运营。本政策说明我们如何收集、使用、存储、保护您的个人信息,以及您享有的权利和行使方式。请您在使用本产品前仔细阅读本政策,特别是加粗显示的条款。';

  @override
  String get legalStaticV11Copy10 =>
      '① 拍摄中的源照片与运动传感器数据用于本机重建;私有云备份和社区发布上传的是您选择的最终三维模型及相关文件。审核图片由模型渲染产生,不是拍摄中的源照片;';

  @override
  String get legalStaticV11Copy11 =>
      '③ 我们会委托阿里云提供存储、通信与内容审核服务,具体处理范围见第三章;公开发布不会免除对个人信息的保护义务;';

  @override
  String get legalStaticV11Copy12 =>
      '我们在下列场景处理信息。每一项说明目的、方式与保存期限;除手机号外,其余各项均为可选,拒绝提供不影响您使用其余功能。';

  @override
  String get legalStaticV11Copy13 =>
      '· 源照片:保存在您设备内本产品的文档目录中,您可以通过系统\"文件\"应用自行查看、导出或删除。本机重建和本政策所述模型备份、发布审核流程不要求上传这些源照片;您自行导出或通过其他服务分享的行为不属于该流程。';

  @override
  String get legalStaticV11Copy14 =>
      '· 最终三维作品:未选择云端功能时保存在您的设备;您选择私有云备份或公开发布时,按下述不同目的上传。';

  @override
  String get legalStaticV11Copy15 =>
      '· 私有云备份【可选】:用于取回、下载查看和防止本地丢失。我们存储您选择备份的最终模型(如 GLB 网格 mesh、PLY 点云,以当前功能支持的格式为准)、封面及恢复所需的作品记录。备份不等于发布,不会因此进入社区广场或对其他用户公开。保存至您删除相应备份或注销账号,依法留存及备份清理限制见第四章。';

  @override
  String get legalStaticV11Copy16 =>
      '· 作品内容【可选,发布功能所必需】:仅当您主动选择公开发布时,我们收集最终三维模型(包括当前支持的 GLB 网格 mesh、PLY 点云等格式)、模型生成的封面、标题与描述。提交与审核期间作品保持非公开,审核通过并完成发布后才对所有用户(含未登录访客)公开展示。';

  @override
  String get legalStaticV11Copy17 =>
      '· 发布审核:为检查违法及不良内容,平台从提交的最终 GLB 模型生成 26 张多角度审核图,将标题、描述交由阿里云文字审核,将这 26 张模型渲染图交由阿里云图片审核。这些审核图不是原始拍摄照片;我们不因该项审核向阿里云发送拍摄过程数据、登录口令或账号联系方式。审核发现风险时可转人工核查,明确违规时拒绝发布;服务异常或结果不完整时保持非公开。暂不支持的格式不能通过该流程自动公开,应按页面提示处理。审核材料与结果按第四章保留与清理。';

  @override
  String get legalStaticV11Copy18 =>
      '· 发布时您已知悉:作品发布并通过审核后,作品内容、您的昵称、账号 ID 及发布时的 IP 属地将对所有人可见。公开发布不表示您放弃隐私或个人信息权益,也不代替作品中其他权利人的授权。';

  @override
  String get legalStaticV11Copy19 =>
      '· 科研与技术改进用途:您上传的作品内容将用于我们内部的科学研究、技术开发与改进,包括但不限于各类人工智能算法与模型的训练、评测与优化(如三维重建相关算法与模型)。对外提供研究数据时,仅使用经匿名化处理、无法识别您身份且不能复原的数据,或另行征得您的单独同意。详见《窗后城用户协议》第六章。';

  @override
  String get legalStaticV11Copy20 =>
      '本地存储说明:本产品不内嵌网页浏览器,不使用 Cookie。以下信息仅保存在您的设备本地,不会被我们读取用于本政策未载明的目的:登录凭据(保存在系统钥匙串中)、语言与界面偏好设置、浏览他人作品时的临时文件缓存(用于加快加载,可随系统清理),以及未选择上传的源照片与重建产物;您已选择备份或提交发布的内容另按第一章处理。';

  @override
  String get legalStaticV11Copy21 =>
      '· 内容审核服务商:阿里云内容安全服务。为审核您主动提交发布的作品,受托处理标题、描述及由最终模型生成的 26 张审核图,并向我们返回风险标签与审核结果;不因本项服务接收原始拍摄照片、完整三维模型、登录口令或账号联系方式。我们按内容审核目的限定提交范围,通过私有存储和短期授权链接提供审核图,不将审核图作为社区公开相册。';

  @override
  String get legalStaticV11Copy22 =>
      '· 邮件服务商:阿里云邮件推送（DirectMail）,用于发送邮箱验证码、账号找回及相关通知,按相应发送目的处理您的电子邮箱与邮件内容。';

  @override
  String get legalStaticV11Copy23 =>
      '(二)向其他个人信息处理者提供:除前述受托处理、您主动公开发布、依法履行义务或另行取得有效同意的情形外,我们不向其他处理者提供您的个人信息。经匿名化处理、无法识别特定个人且不能复原的信息,依法不属于个人信息;我们在对外科研合作中仅使用此类匿名化数据(见第一章第(三)节)。';

  @override
  String get legalStaticV11Copy24 =>
      '2. 存储期限:各类信息的保存期限已在第一章逐项写明,汇总如下 —— 账号资料(手机号/邮箱/昵称/ID/简介)保存至注销;私有备份、作品及互动记录保存至删除或注销,依法留存和备份清理限制见下款;浏览记录于注销后匿名化;统计事件 180 天;安全审计日志 180 天(重大操作 730 天);接口频次记录不超过 1 天;注册过程中的临时验证数据 10 分钟。审核模型、审核图和结果仅在审核、投诉申诉处理、必要安全保护及依法留存所需范围和期限内保存,不以便于保存为由无限期留存;期满删除或匿名化。涉及法定留存或技术上难以立即删除的,按下款限制处理。';

  @override
  String get legalStaticV11Copy25 =>
      '3. 删除限制与留存:删除或撤回后,相关作品不再作为可公开内容提供。审核证据、举报申诉材料或依法下架作品的必要副本可能因法定保存义务、正在处理的争议或存储保留锁而不能立即物理删除;我们将限制用途与访问,并在相关事由及必要保存期限届满后清理。备份中的副本按照备份轮换与删除流程清理,恢复备份时仍需执行已登记的删除要求,不得因此重新公开或恢复正常使用。法律法规规定的保存期限未届满或技术上难以实现删除的,我们将停止除存储和采取必要安全保护措施之外的处理。';

  @override
  String get legalStaticV11Copy26 =>
      '3. 删除:您可以在作品页申请删除自己的作品(含审核中的作品),并对私有云备份提出删除要求;我们将停止相关内容的公开或正常提供,取消未完成的发布处理,并执行文件清理。审核证据、保留锁和历史备份不等于即时物理擦除,其处理见第四章第 3 条;其他删除请求可通过联系方式提出。出现处理目的已实现、我们停止服务、您撤回同意、我们违法违约处理等法定情形时,我们将主动删除。法律法规规定的保存期限未届满或技术上难以实现删除的,我们将停止除存储和采取必要安全保护措施之外的处理。';

  @override
  String get legalStaticV11Copy27 => '个人信息处理者:北京空也科技有限公司';

  @override
  String get legalStaticV11Copy28 => '备案资料所载营业执照住所所在地（省市区）：北京市海淀区';

  @override
  String get legalStaticV11Copy29 => '个人信息保护负责人邮箱:wkd20040211@163.com';

  @override
  String get legalStaticV11Copy31 => '窗后城用户协议｜北京空也科技有限公司';

  @override
  String get legalStaticV11Copy32 => '窗后城用户协议';

  @override
  String get legalStaticV11Copy33 =>
      '欢迎使用「窗后城」。本协议是您与北京空也科技有限公司(以下称\"我们\"或\"平台\")之间关于使用窗后城软件及相关服务的约定。请在注册前完整阅读本协议,特别是以加粗方式显示的免除或限制责任、权利许可、争议管辖等条款。';

  @override
  String get legalStaticV11Copy34 =>
      '《窗后城平台公约》(含账号管理规则)与《窗后城隐私政策》是本协议不可分割的组成部分,与本协议具有同等效力。您接受本协议,即视为同时接受上述文件。';

  @override
  String get legalStaticV11Copy35 =>
      '窗后城是一款三维空间内容工具与社区:您可在设备本机重建三维作品,或使用当前功能支持的最终模型文件。最终模型包括 GLB 网格(mesh)、PLY 点云等,具体支持范围以对应功能页面为准。您可分别选择私有云备份或公开发布,两者不是同一操作。';

  @override
  String get legalStaticV11Copy36 =>
      '5. 账号注销:您可以随时在\"设置 → 账号\"中注销账号,注销流程与数据处理见《窗后城隐私政策》。';

  @override
  String get legalStaticV11Copy37 =>
      '1. 先审后发:您发布的作品需经平台审核,审核通过后才会出现在社区广场;审核期间作品对其他用户不可见,您可以申请撤回或删除。私有云备份不会因上传而自动变成公开作品。';

  @override
  String get legalStaticV11Copy38 =>
      '审核方式:针对最终 GLB,平台生成 26 张多角度模型渲染图,委托阿里云进行标题、描述的文字审核及审核图的图片审核。该流程不要求上传原始拍摄照片或拍摄过程数据。机审风险可转人工复核,明确违规不予发布,服务异常或结果不完整时不予自动公开。暂不支持的格式不能通过该流程自动公开;修改已提交的作品内容需要重新审核。';

  @override
  String get legalStaticV11Copy39 =>
      '2. 发布即公开:作品通过审核后,作品内容、您的昵称、账号 ID 及发布时的 IP 属地将对所有用户(含未登录访客)公开可见。公开发布不等于放弃隐私或个人信息权益,也不免除发布者取得他人授权的义务。IP 属地展示是法定要求,无法关闭,详见《窗后城隐私政策》。';

  @override
  String get legalStaticV11Copy40 =>
      '3. 本协议所称\"内容\"包括您在本服务中上传、发布的三维模型(如 GLB 网格 mesh、PLY 点云)、三维重建数据、封面和衍生审核图、标题、描述、账号资料以及其他任何信息。';

  @override
  String get legalStaticV11Copy41 =>
      '删除、撤回与证据留存:停止公开不等于所有副本即时物理擦除。审核材料、投诉申诉证据、法定留存及历史备份的限制处理和清理,按《窗后城隐私政策》第四章执行;相关副本不能因备份恢复而重新公开。';

  @override
  String get legalStaticV11Copy42 =>
      '2. 您在本服务中上传或发布的作品(含三维点云、网格模型及其衍生的封面与审核图)的知识产权归您或依法享有权利的权利人所有,不因发布行为而转移。';

  @override
  String get legalStaticV11Copy43 =>
      '3. 为向您提供服务并改进产品,您授予平台一项全球范围内、免费、非独家的许可,包括对内容的复制权、信息网络传播权、改编权、汇编权、展示权及制作衍生内容的权利。本款所称内容,指您上传至本服务的内容,包括发布到社区广场的作品,以及私有云备份(云端存储)功能中您存储的内容,含三维点云、网格模型、封面、衍生审核图、标题、描述。上述权利仅用于:(1)运营所必需:存储、备份、传输、分发、公开展示(仅限您选择公开发布的内容)及格式适配、生成审核图、文字与图片内容安全检测等技术处理,并可将相应处理委托给受约束的云服务和内容审核服务商执行;(2)将您已公开发布的作品用于本产品各终端版本及应用商店页面的展示与推介;(3)我们内部的科学研究、技术开发与改进,包括但不限于各类人工智能算法与模型的训练、评测与优化(如三维重建相关算法与模型),不论采用现在已知或日后开发的技术与形式。';

  @override
  String get legalStaticV11Copy44 =>
      '5. 许可的期限与终止:上述许可自内容上传时生效。您删除相应内容,或注销账号(指您依照第三章第 5 条及《窗后城隐私政策》第六章,主动申请删除账号及其项下个人信息的行为)后,除法律法规另有规定或本协议另有约定(如依法下架内容的封存留存)外,许可即告终止,我们将停止在新的研究与模型训练中使用该内容;但在此之前已完成的研究成果与已训练完成的模型不受影响。';

  @override
  String get legalStaticV11Copy45 =>
      '3. 平台发生合并、分立、被收购等情形需要向承继方转移服务的,将依法通知您;承继方将继续受本协议及《窗后城隐私政策》约束,否则将重新征得您的同意。';

  @override
  String get legalStaticV11Copy46 => '4. 服务终止后,平台将按《窗后城隐私政策》对您的个人信息进行删除或匿名化处理。';

  @override
  String get legalStaticV11Copy47 =>
      '2. 因本协议产生的争议,双方应友好协商;协商不成的,任何一方均可向公司住所地有管辖权的人民法院提起诉讼。';

  @override
  String get legalStaticV11Copy48 => '运营者:北京空也科技有限公司';

  @override
  String get legalStaticV11Copy49 => '联系邮箱:wkd20040211@163.com';

  @override
  String get legalStaticV11Copy50 => '窗后城平台公约｜北京空也科技有限公司';

  @override
  String get legalStaticV11Copy51 => '窗后城平台公约';

  @override
  String get legalStaticV11Copy52 =>
      '私有云备份与公开发布分开:备份不会自动进入社区。主动提交发布后进入审核状态,审核通过并完成发布后才会出现在社区广场,在此之前对其他用户不可见。';

  @override
  String get legalStaticV11Copy53 =>
      'GLB 发布审核从最终模型生成 26 张多角度渲染图,将标题、描述和这些审核图交由阿里云文字、图片审核;审核图不是原始拍摄照片。当前未支持的格式不能经此流程自动公开。';

  @override
  String get legalStaticV11Copy54 =>
      '发现风险可转人工核查,明确违规退回,服务异常或结果不完整时不自动公开;修改作品内容后需要重新审核。公开发布不等于放弃隐私或他人的合法权益。';

  @override
  String get legalStaticV11Copy55 =>
      '你可以申请撤回或删除自己的作品,包括正在审核中且从未公开过的作品。停止公开与文件物理清理分开;审核证据、争议材料及历史备份的限制处理与清理见隐私政策。';

  @override
  String get legalStaticV11Copy56 => '邮箱:wkd20040211@163.com';

  @override
  String get legalStaticV11Copy57 => '三维作品发布与审核说明｜窗后城';

  @override
  String get legalStaticV11Copy58 => '发布于2026年11月2日 · V1.1';

  @override
  String get legalStaticV11Copy59 => '私有备份与公开发布';

  @override
  String get legalStaticV11Copy60 =>
      '云端私有备份不会自动成为社区作品。只有你主动提交公开发布，并通过审核，作品才会进入公共社区。';

  @override
  String get legalStaticV11Copy61 => '审核会使用什么内容';

  @override
  String get legalStaticV11Copy62 =>
      '提交发布会上传最终 GLB 模型及作品标题、描述。云端从同一份模型生成26张不同视角的审核图片，使用阿里云文本和图片审核服务检查标题、描述和这些图片。审核图片由模型渲染生成，不是原始拍摄照片；完整模型不会发送给阿里云图片审核接口。';

  @override
  String get legalStaticV11Copy63 =>
      '26视角是当前产品的审核方案，不代表已证明覆盖模型全部表面。当前支持范围为50MB以内、可独立加载的静态 GLB；不支持的模型不会自动通过。';

  @override
  String get legalStaticV11Copy64 => '审核结果与公开访问';

  @override
  String get legalStaticV11Copy65 =>
      '审核全部通过且符合发布条件后，作品可以公开展示。存在风险的作品进入人工处理；被阻止、审核出错、证据不完整或模型不受支持时，不会自动公开。替换模型需重新审核。';

  @override
  String get legalStaticV11Copy66 =>
      '公开作品可由未登录的访客查看、分享。点赞及评论需要登录。开放授权示例保留其素材来源及授权身份。';

  @override
  String get legalStaticV11Copy67 => '撤回、删除与权利';

  @override
  String get legalStaticV11Copy68 =>
      '你可以撤回公开发布、申请删除或进行举报与申诉。审核证据、争议处置、法定留存和历史备份的处理，依照隐私政策和实际保存机制执行；公开发布不会免除你或他人的个人信息权益。';

  @override
  String get legalStaticV11Copy69 => '运营与联系';

  @override
  String get legalStaticV11Copy70 => '运营者：北京空也科技有限公司';

  @override
  String get legalStaticPrivacyIntro => '本页公布窗后城 App 的隐私政策。公开发布作品前，请同时阅读';

  @override
  String get legalStaticTermsIntro => '本页公布窗后城 App 的用户协议。公开发布作品前，请同时阅读';

  @override
  String get legalStaticRulesIntro => '本页公布窗后城 App 的平台公约。公开发布作品前，请同时阅读';

  @override
  String get legalStaticContactPrefix => '产品服务及隐私联系：';

  @override
  String get legalStaticSentenceEnd => '。';

  @override
  String get siteAuthorLoading => '正在读取作者…';

  @override
  String get siteAuthorUnavailable => '作者信息暂不可用';

  @override
  String get siteAuthorRetry => '重试';

  @override
  String get commentResizePanel => '调整评论栏宽度';

  @override
  String get commentResizePanelHint => '向左拖动加宽，向右拖动缩窄。也可使用左右方向键调整。';

  @override
  String commentPanelWidth(int width) {
    return '$width 像素';
  }

  @override
  String get siteScreenOne => '屏幕 01';

  @override
  String get siteScreenTwo => '屏幕 02';

  @override
  String get siteScreenThree => '屏幕 03';

  @override
  String get siteScreenPlaceholder => '内容待添加';

  @override
  String get siteScreenSelection => '切换屏幕';

  @override
  String get siteScreenBack => '返回社区';

  @override
  String get siteScreenStage => '精选屏幕';
}
