// Community image feed. Only published cover images are prepared here.
// Models and the shared 3D viewer load only after opening work detail.
// Naturally matched first covers reveal together; later covers retain their aspect.

import 'dart:async';
import 'dart:typed_data';
import 'community/first_pair_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'community/web_publication_page.dart';
import '../community/author_feed_priority.dart';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../community/community_service.dart';
import '../community/feed_models.dart';
import '../l10n/app_localizations.dart';
import '../util/device_log.dart';
import 'community/card_live_governor.dart';
import 'community/work_card.dart';
import 'community/masonry_layout.dart';
import 'community/masonry_policy.dart';
import 'community/community_loading.dart';
import 'community/work_detail_page.dart';
import 'design_system.dart';
import 'startup_splash_gate.dart';
import 'shared/product_model_view.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({
    super.key,
    this.service,
    this.isVisible = true,
    this.activities = const [],
    this.onActivityTap,
    this.viewerHostBuilderForTesting,
  });

  final CommunityService? service;
  final bool isVisible;
  final List<TopicActivity> activities;
  final ValueChanged<int>? onActivityTap;
  // Forward the shared renderer's existing test seam.
  // ignore: invalid_use_of_visible_for_testing_member
  final ProductModelHostBuilder? viewerHostBuilderForTesting;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with WidgetsBindingObserver {
  late CommunityService _service = widget.service ?? CommunityService();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<FeedWork>> _feed;
  StreamSubscription<String?>? _viewerSubscription;
  String? _viewerId;
  FeedWork? _publicCursor;
  int _publicRowsLoaded = 0;
  String _query = '';
  bool _foreground = true;
  bool _detailOpen = false;
  bool _refreshRequested = false;
  bool _automaticRefreshInFlight = false;
  bool _automaticRefreshScheduled = false;
  @override
  void didUpdateWidget(covariant VaultPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _service = widget.service ?? CommunityService();
      _bindViewer();
      _workUpdates.clear();
      _workUpdateGenerations.clear();
      _feed = _loadFeed();
    }
    if (!oldWidget.isVisible && widget.isVisible) _requestFeedRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) _requestFeedRefresh();
  }

  // Coalesce activation/return events, preserve hidden tabs, and never overlap
  // an automatic refresh with the initial/current feed request.
  void _requestFeedRefresh() {
    _refreshRequested = true;
    if (_automaticRefreshScheduled || _automaticRefreshInFlight) return;
    _automaticRefreshScheduled = true;
    scheduleMicrotask(() {
      _automaticRefreshScheduled = false;
      if (mounted) unawaited(_flushFeedRefresh());
    });
  }

  Future<void> _flushFeedRefresh() async {
    if (!_refreshRequested ||
        _automaticRefreshInFlight ||
        !widget.isVisible ||
        !_foreground ||
        _detailOpen) {
      return;
    }
    _automaticRefreshInFlight = true;
    final serviceAtStart = _service;
    _refreshRequested = false;
    try {
      try {
        await _feed;
      } catch (_) {
        // A return to the feed also retries a failed initial request.
      }
      if (!mounted ||
          !widget.isVisible ||
          !_foreground ||
          _detailOpen ||
          !identical(_service, serviceAtStart)) {
        _refreshRequested = true;
        return;
      }
      _refreshRequested = false;
      await _refresh();
    } catch (_) {
      // _feed retains the error so the existing retry UI can display it.
    } finally {
      _automaticRefreshInFlight = false;
      if (mounted &&
          _refreshRequested &&
          widget.isVisible &&
          _foreground &&
          !_detailOpen) {
        _requestFeedRefresh();
      }
    }
  }

  Future<void> _openWork(FeedWork work) async {
    _detailOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkDetailPage(
            work: work,
            service: _service,
            onWorkUpdated: (updated) => _onWorkUpdated(work.id, updated),
          ),
        ),
      );
    } finally {
      _detailOpen = false;
      if (mounted) {
        _requestFeedRefresh();
      }
    }
  }

  bool _viewerAllowed = StartupSplashGate.instance.isDone;
  final Map<String, FeedWork> _workUpdates = {};
  final Map<String, int> _workUpdateGenerations = {};
  int _feedGeneration = 0;
  final Set<String> _visibleFeedIds = {};

  // Source-keyed and bounded: lazy card recycling must not change proportions.
  final Map<String, double> _coverAspectRatios = {};

  void _rememberCoverAspect(FeedWork work, double ratio) {
    if (!mounted || !ratio.isFinite || ratio <= 0) return;
    final key = communityCoverSourceKey(work);
    if (_coverAspectRatios[key] == ratio) return;
    setState(() {
      if (_coverAspectRatios.length >= 256 &&
          !_coverAspectRatios.containsKey(key)) {
        _coverAspectRatios.remove(_coverAspectRatios.keys.first);
      }
      _coverAspectRatios[key] = ratio;
    });
  }

  /// [D7 2026-08-23 用户签决] 流内"只看这个人的作品"过滤。
  ///
  /// **明确不做**:头像大图、简介、关注按钮、任何计数(粉丝/关注/作品数)。
  /// 什么时候升级成真正的个人主页 —— **用信号不用时间**:出现 ≥3 个
  /// 非创始人创作者、且各自作品 ≥3 件时再做。
  String? _authorFilterId;
  String? _authorFilterName;

  /// Feed 分页(offset 翻页)。此前只拉一次 limit:20 且没有加载更多,第 21
  /// 个作品对所有人永久不可见。_hasMore=false 表示服务端给不满一页了。
  static const int _pageSize = 20;
  bool _loadingMore = false;
  bool _pageLoadFailed = false;
  bool _hasMore = true;
  bool _retainFeedWhileAppending = false;
  bool _governorRebuildPending = false;

  /// 闸 3/4/5/7 的总闸门 —— 它说不行,就一张 live 卡都没有。
  final CardLiveGovernor _governor = CardLiveGovernor();

  /// 每张卡的可见比例(VisibilityDetector 上报),用来挑焦点卡。
  final Map<String, double> _visibilityByWorkId = {};
  String? _focusedWorkId;

  /// 焦点卡必须**明显**是焦点才算数。等大的正方形卡片里,可见度最高的那张
  /// 就是最居中的那张;0.55 这个门槛保证换焦点时不会在两张各露一半的卡之间
  /// 来回横跳(每次横跳 = 一轮卸载 + 重下载解析降点)。沿用旧 PostCard 的值。
  static const double _focusThreshold = 0.55;

  /// 闸 1:全 App 同时只有这一张卡是 live 的。null = 现在一张都没有。
  String? get _liveWorkId => _governor.liveAllowed ? _focusedWorkId : null;

  final Map<String, GlobalKey> _cardKeys = {};
  final Map<String, CommunityCardMetrics> _prepared = {};
  final Map<String, CommunityCardMetrics> _measured = {};
  final _stillFrames = <String, Uint8List>{};
  final _remounting = <String, Object>{};
  final Set<String> _failedPreparation = {};
  List<String>? _firstPairSources;
  List<String>? _forcedPreparationSources;
  int _preparationOffset = 0;
  bool _advancePreparationPending = false;
  String? _preparationError;
  Timer? _preparationTimer;
  int _preparationGeneration = 0;

  void _resetPreparation() {
    _preparationGeneration++;
    _preparationTimer?.cancel();
    _preparationTimer = null;
    _cardKeys.clear();
    _prepared.clear();
    _measured.clear();
    _stillFrames.clear();
    _remounting.clear();
    _failedPreparation.clear();
    _firstPairSources = null;
    _forcedPreparationSources = null;
    _preparationOffset = 0;
    _preparationError = null;
    _advancePreparationPending = false;
  }

  void _beginPreparationDeadline() {
    if (!_viewerAllowed || _preparationTimer != null) return;
    final generation = _feedGeneration;
    _preparationTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted ||
          generation != _feedGeneration ||
          _firstPairSources != null) {
        return;
      }
      setState(() => _preparationError = '作品预览暂时无法完成，请重试。');
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _bindViewer();
    _feed = _loadFeed();
    if (kIsWeb && Uri.base.queryParameters['publish'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || Supabase.instance.client.auth.currentUser == null) {
          return;
        }
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WebPublicationPage()));
        if (mounted) await _refresh();
      });
    }
    _governor.addListener(_onGovernorChanged);
    StartupSplashGate.instance.addListener(_onStartupGateChanged);
  }

  void _bindViewer() {
    _viewerSubscription?.cancel();
    _viewerId = _service.viewerUserId;
    _viewerSubscription = _service.viewerUserChanges.listen((id) {
      if (!mounted || id == _viewerId) return;
      setState(() {
        _viewerId = id;
        _workUpdates.clear();
        _resetFocus();
        _feed = _loadFeed();
      });
    });
  }

  void _onStartupGateChanged() {
    final allowed = StartupSplashGate.instance.isDone;
    if (mounted && allowed != _viewerAllowed) {
      setState(() => _viewerAllowed = allowed);
      if (!allowed) {
        _preparationTimer?.cancel();
        _preparationTimer = null;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    StartupSplashGate.instance.removeListener(_onStartupGateChanged);
    _preparationTimer?.cancel();
    _governor.removeListener(_onGovernorChanged);
    _viewerSubscription?.cancel();
    _governor.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onGovernorChanged() {
    if (!mounted) return;
    // Masonry extent changes can emit scroll notifications during layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_governorRebuildPending) return;
      _governorRebuildPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _governorRebuildPending = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// 换 tab / 换搜索词 / 下拉刷新 —— 列表整个换了,旧的可见度读数全作废。
  void _resetFocus() {
    _visibilityByWorkId.clear();
    _focusedWorkId = null;
  }

  /// 挑焦点卡:可见度最高、且过 [_focusThreshold] 的那张。
  void _recomputeFocus() {
    String? next;
    var best = _focusThreshold;
    for (final entry in _visibilityByWorkId.entries) {
      if (entry.value > best) {
        best = entry.value;
        next = entry.key;
      }
    }
    if (next != _focusedWorkId && mounted) {
      // 闸 1/6 的现场证据:换焦点 = 旧 live 卡卸载 + 新的挂上。真机验收看这
      // 条能确认"同时只有一张"没被破坏(不该出现两条连续的挂载而无卸载)。
      DeviceLog.log(
        'FeedLive',
        '焦点卡:${_focusedWorkId ?? "无"} → ${next ?? "无"} '
            '(可见度 ${best.toStringAsFixed(2)})',
      );
      setState(() => _focusedWorkId = next);
    }
  }

  void _onWorkUpdated(String workId, FeedWork updated) {
    if (!mounted ||
        updated.id != workId ||
        (!_visibleFeedIds.contains(workId) &&
            !_workUpdates.containsKey(workId))) {
      return;
    }
    setState(() {
      _workUpdates[workId] = updated;
      _workUpdateGenerations[workId] = _feedGeneration;
    });
  }

  void _onCardVisibilityChanged(String workId, double fraction) {
    final wasVisible = (_visibilityByWorkId[workId] ?? 0) > 0;
    _visibilityByWorkId[workId] = fraction;
    if (mounted && wasVisible != (fraction > 0)) setState(() {});
    _recomputeFocus();
  }

  Future<List<FeedWork>> _loadFeed() {
    _feedGeneration++;
    _resetPreparation();
    _visibleFeedIds.clear();
    _hasMore = true;
    _loadingMore = false;
    _pageLoadFailed = false;
    _retainFeedWhileAppending = false;
    final generation = _feedGeneration;
    final viewer = _viewerId;
    _publicCursor = null;
    _publicRowsLoaded = 0;
    final page = _service.fetchPublicFeed(
      limit: _pageSize,
      sortBy: FeedSort.recent,
      authorUserId: _authorFilterId,
      query: _query.isEmpty ? null : _query,
    );
    final own =
        viewer != null && (_authorFilterId == null || _authorFilterId == viewer)
        ? _service.fetchOwnPublicFeed(query: _query.isEmpty ? null : _query)
        : Future.value(const <FeedWork>[]);
    return Future.wait([page, own]).then((results) {
      if (generation != _feedGeneration || viewer != _viewerId) return [];
      final works = results[0];
      _hasMore = works.length >= _pageSize;
      _publicCursor = works.isEmpty ? null : works.last;
      _publicRowsLoaded = works.length;
      return prioritizeAuthorFeed(works, results[1], viewer);
    });
  }

  /// 快滚到底时补下一页,静默追加(风格同 _kickPrefetch:发完不管)。
  /// offset 翻页 + 按 id 去重 —— 两页之间有新作品发布时,offset 会把上一页
  /// 的尾行再发一遍,去重后追加不闪不跳。失败不提示:用户继续滚会再触发。
  Future<void> _maybeLoadMore(List<FeedWork> current) async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _pageLoadFailed = false;
    });
    final generationAtStart = _feedGeneration;
    final feedAtStart = _feed;
    var continuePage = false;
    try {
      // [KEYSET-PAGINATION 2026-08-23] 用上一页最后一条的 (published_at, id)
      // 作游标,不再用 offset。
      //
      // offset 的病:边翻页边有新作品插到顶部时,整列下移一位,原本在 offset
      // 处的那条挪到 offset+1,第二页从下一条开始 —— **中间那条对该用户永远
      // 不出现**。下面的 id 去重挡得住重复,挡不住漏。
      //
      // 本仓修过一次同类(此前只拉一次 limit:20 且无加载更多,第 21 个作品
      // 对所有人永久不可见);这是它更隐蔽的变体。
      final last = _publicCursor;
      final cursorAt = last?.publishedAt;
      final next = await _service.fetchPublicFeed(
        limit: _pageSize,
        // 游标可用就不传 offset;查询里 published_at is not null 已经保证
        // 返回的每一条都有时间戳,这里的 null 兜底只是防御。
        offset: cursorAt == null ? _publicRowsLoaded : 0,
        sortBy: FeedSort.recent,
        authorUserId: _authorFilterId,
        query: _query.isEmpty ? null : _query,
        afterPublishedAt: cursorAt,
        afterId: cursorAt == null ? null : last!.id,
      );
      // tab / 搜索 / 下拉刷新已经换了整个列表 → 这批结果作废。
      if (!mounted || !identical(_feed, feedAtStart)) return;
      _publicRowsLoaded += next.length;
      if (next.isNotEmpty) _publicCursor = next.last;
      if (next.length < _pageSize) _hasMore = false;
      // 去重保留:keyset 之后重复已不该发生,但它零成本、且能兜住
      // "刷新与加载更多竞态"这类边角。**它挡不住漏项 —— 那是 keyset 修的。**
      final seen = current.map((w) => w.id).toSet();
      final fresh = next.where((w) => seen.add(w.id)).toList();
      if (fresh.isEmpty) {
        _hasMore = next.length >= _pageSize;
        continuePage = _hasMore;
        // A page of structurally unavailable previews can end on an empty
        // next page. Rebuild so its loading animation becomes the empty state.
        setState(() {});
        return;
      }
      setState(() {
        _retainFeedWhileAppending = true;
        _feed = Future.value(
          prioritizeAuthorFeed(
            [...current, ...fresh],
            const [],
            kIsWeb ? _viewerId : null,
          ),
        );
      });
    } catch (_) {
      // Keep metadata usable; a failed page gets an explicit retry, not a
      // metrics-driven request loop caused by removing its skeletons.
      if (mounted && generationAtStart == _feedGeneration) {
        _pageLoadFailed = true;
      }
    } finally {
      if (mounted && generationAtStart == _feedGeneration) {
        setState(() => _loadingMore = false);
        if (continuePage && identical(_feed, feedAtStart)) {
          unawaited(_maybeLoadMore(current));
        }
      }
    }
  }

  Future<void> _refresh() async {
    final next = _loadFeed();
    setState(() {
      _resetFocus();
      _feed = next;
    });
    await next;
  }

  // ignore: unused_element  —— [D2] 搜索代码按用户要求保留,只是不渲染。
  void _onQuerySubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed == _query) return;
    setState(() {
      _resetFocus();
      _query = trimmed;
      _feed = _loadFeed();
    });
  }

  // ignore: unused_element  —— [D2] 搜索代码按用户要求保留,只是不渲染。
  void _onAuthorTap(FeedWork work) {
    if (_authorFilterId == work.userId) return;
    setState(() {
      _authorFilterId = work.userId;
      _authorFilterName = work.authorDisplayName;
      _hasMore = true;
      _feed = _loadFeed();
    });
    _resetFocus();
  }

  void _clearAuthorFilter() {
    setState(() {
      _authorFilterId = null;
      _authorFilterName = null;
      _hasMore = true;
      _feed = _loadFeed();
    });
    _resetFocus();
  }

  // ignore: unused_element  —— [D2] 搜索代码按用户要求保留,只是不渲染。
  void _onClearQuery() {
    if (_query.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() {
      _resetFocus();
      _query = '';
      _feed = _loadFeed();
    });
  }

  Object? _layoutIdentity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final identity = (
          constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
          MediaQuery.textScalerOf(context).scale(13),
          MediaQuery.textScalerOf(context).scale(11),
          MediaQuery.paddingOf(context).left,
          MediaQuery.paddingOf(context).right,
          Localizations.localeOf(context),
          Directionality.of(context),
        );
        if (_layoutIdentity != null && _layoutIdentity != identity) {
          _resetPreparation();
          _resetFocus();
        }
        _layoutIdentity = identity;
        return Scaffold(
          backgroundColor: AetherColors.bg,
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    if (kIsWeb &&
                        Supabase.instance.client.auth.currentUser != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip:
                                  Localizations.localeOf(
                                        context,
                                      ).languageCode ==
                                      'zh'
                                  ? '消息'
                                  : 'Messages',
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                              onPressed: () =>
                                  Navigator.of(context).pushNamed('/messages'),
                            ),
                            IconButton(
                              tooltip: '发布作品',
                              icon: const Icon(Icons.add),
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const WebPublicationPage(),
                                  ),
                                );
                                if (mounted) await _refresh();
                              },
                            ),
                          ],
                        ),
                      ),
                    // [D1/D2/D3 2026-08-23 用户签决] 冷启动期社区首页 = **单信息流**。
                    //
                    // 砍掉的两样:
                    //   · 三个标签(热门/附近/发现)—— 公开作品个位数,空标签比没有
                    //     更伤。且实测「热门」与「发现」本就是同一个流的两个排序键,
                    //     合并零信息损失。「附近」的文案是"敬请期待"——**一句没兑现
                    //     的承诺比一个空标签更糟**。
                    //   · 顶部搜索框 —— 几件作品搜什么。
                    //
                    // ⚠️ 搜索的**代码全部保留**(_SearchBar / _searchController /
                    // _query / _onQuerySubmitted / _onClearQuery / service 的 query
                    // 参数),只是不渲染。用户明确要求"先留着别删"。
                    // 恢复 = 把下面这个 Padding 的注释解开。
                    //
                    // if (false) Padding(
                    //   padding: const EdgeInsets.fromLTRB(AetherSpacing.lg,
                    //       AetherSpacing.md, AetherSpacing.lg, AetherSpacing.sm),
                    //   child: _SearchBar(
                    //     controller: _searchController,
                    //     hasQuery: _query.isNotEmpty,
                    //     onSubmitted: _onQuerySubmitted,
                    //     onClear: _onClearQuery,
                    //   ),
                    // ),
                    // [D7] 作者过滤条 —— 只在过滤生效时占位,平时零高度。
                    // 它就是"只看这个人"这个状态的**唯一** UI:没有头像、没有简介、
                    // 没有关注、没有任何计数。
                    if (_authorFilterId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AetherSpacing.lg,
                          AetherSpacing.md,
                          AetherSpacing.lg,
                          AetherSpacing.sm,
                        ),
                        child: _AuthorFilterBar(
                          name: _authorFilterName ?? '',
                          onClear: _clearAuthorFilter,
                        ),
                      ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: _buildFeed(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 主题卡只在**没有作者过滤**时出现 —— 「本周精选」是策展,
  /// 在"只看某个人"的视图里没有意义。
  bool get _showTopicCard =>
      (widget.activities.isNotEmpty || kShowCommunityTopicCard) &&
      _authorFilterId == null;

  Widget _buildFeed() {
    final sourceFeed = _feed;
    return FutureBuilder<List<FeedWork>>(
      future: sourceFeed,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done &&
            !(_retainFeedWhileAppending && snap.hasData)) {
          return const _LoadingState();
        }
        if (snap.hasError) {
          return _ErrorState(
            message: AppL10n.of(context).communityFeedLoadFailed,
            onRetry: _refresh,
          );
        }
        final rawWorks = snap.data ?? const <FeedWork>[];
        final fetchedWorks = prioritizeAuthorFeed(
          rawWorks,
          const [],
          kIsWeb ? _viewerId : null,
        );
        final works = fetchedWorks.map((work) {
          final update = _workUpdates[work.id];
          // Only a newer fetch can acknowledge a local mutation. Rebuilding
          // the same raw page must not replace an optimistic value with itself.
          if (update != null &&
              (_workUpdateGenerations[work.id] ?? _feedGeneration) <
                  _feedGeneration &&
              work.likedByMe == update.likedByMe) {
            _workUpdates.remove(work.id);
            _workUpdateGenerations.remove(work.id);
            return work;
          }
          return update == null
              ? work
              : work.copyWith(
                  likedByMe: update.likedByMe,
                  likesCount: update.likesCount,
                  viewsCount: update.viewsCount,
                  commentCount: update.commentCount,
                );
        }).toList();
        _visibleFeedIds
          ..clear()
          ..addAll(works.map((work) => work.id));
        if (snap.connectionState == ConnectionState.done) {
          _retainFeedWhileAppending = false;
        }
        if (works.isEmpty) {
          if (fetchedWorks.isNotEmpty && _hasMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && identical(_feed, sourceFeed)) {
                unawaited(_maybeLoadMore(fetchedWorks));
              }
            });
            return const _LoadingState();
          }
          return const _EmptyState();
        }
        if (_preparationError != null) {
          return _ErrorState(message: _preparationError!, onRetry: _refresh);
        }
        if (_firstPairSources == null && _pageLoadFailed) {
          return _ErrorState(
            message: AppL10n.of(context).communityFeedLoadFailed,
            onRetry: () => _maybeLoadMore(fetchedWorks),
          );
        }
        if (_firstPairSources == null) {
          final staged = _forcedPreparationSources == null
              ? works
                    .skip(_preparationOffset)
                    .take(CardViewerRegistry.cap)
                    .toList()
              : works
                    .where(
                      (w) => _forcedPreparationSources!.contains(
                        communityCoverSourceKey(w),
                      ),
                    )
                    .toList();
          final liveOrder = communityFirstPairOrder(works, _prepared);
          final needed = works.length < 2 ? works.length : 2;
          if (liveOrder != null &&
              liveOrder.take(needed).every((w) => _isPrepared(w))) {
            _firstPairSources = liveOrder
                .take(needed)
                .map(communityCoverSourceKey)
                .toList();
            _preparationTimer?.cancel();
          } else {
            _beginPreparationDeadline();
            final settled =
                staged.isNotEmpty &&
                staged.every((w) {
                  final source = communityCoverSourceKey(w);
                  return _prepared.containsKey(source) ||
                      _failedPreparation.contains(source);
                });
            if (settled && !_advancePreparationPending && !_loadingMore) {
              _advancePreparationPending = true;
              final generation = _feedGeneration;
              final preparation = _preparationGeneration;
              final exhausted =
                  _preparationOffset + staged.length >= works.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted ||
                    generation != _feedGeneration ||
                    preparation != _preparationGeneration) {
                  return;
                }
                final knownOrder = communityFirstPairOrder(works, _measured);
                setState(() {
                  _advancePreparationPending = false;
                  if (knownOrder != null &&
                      knownOrder
                          .take(needed)
                          .every(
                            (w) => _measured.containsKey(
                              communityCoverSourceKey(w),
                            ),
                          )) {
                    _forcedPreparationSources = knownOrder
                        .take(needed)
                        .map(communityCoverSourceKey)
                        .toList();
                    _prepared.removeWhere(
                      (source, _) =>
                          !_forcedPreparationSources!.contains(source),
                    );
                  } else if (_preparationOffset + staged.length <
                      works.length) {
                    _preparationOffset += staged.length;
                    _prepared.clear();
                  } else if (!_hasMore) {
                    _preparationError = '作品预览暂时无法完成，请重试。';
                  }
                });
                if (_hasMore &&
                    _forcedPreparationSources == null &&
                    exhausted) {
                  unawaited(_maybeLoadMore(fetchedWorks));
                }
              });
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                _hiddenPreparation(staged, works),
                const Positioned.fill(child: _LoadingState()),
              ],
            );
          }
        }
        final pairSources = _firstPairSources!;
        final displayWorks = <FeedWork>[
          for (final source in pairSources)
            ...works.where((w) => communityCoverSourceKey(w) == source),
          ...works.where(
            (w) => !pairSources.contains(communityCoverSourceKey(w)),
          ),
        ];
        final readyWorks = <FeedWork>[];
        for (final work in displayWorks) {
          if (!_isPrepared(work)) break;
          readyWorks.add(work);
        }
        final nextPending = readyWorks.length < displayWorks.length
            ? communityCoverSourceKey(displayWorks[readyWorks.length])
            : null;
        final failedNext =
            nextPending != null && _failedPreparation.contains(nextPending);
        final pending = failedNext
            ? <FeedWork>[]
            : displayWorks
                  .skip(readyWorks.length)
                  .where(
                    (w) =>
                        !_isPrepared(w) &&
                        !_failedPreparation.contains(
                          communityCoverSourceKey(w),
                        ),
                  )
                  .take(CardViewerRegistry.cap)
                  .toList();
        final held = displayWorks
            .skip(readyWorks.length)
            .where(_isPrepared)
            .toList();
        final showLoading =
            _loadingMore ||
            (!failedNext && readyWorks.length < displayWorks.length);
        final remountFailed = _remounting.keys.any(_failedPreparation.contains);
        final footer = _pageLoadFailed
            ? Center(
                child: TextButton(
                  onPressed: () => unawaited(_maybeLoadMore(fetchedWorks)),
                  child: Text(AppL10n.of(context).authRetry),
                ),
              )
            : failedNext
            ? SizedBox(
                height: 64,
                child: Center(
                  child: TextButton(
                    onPressed: _retryVisibleMedia,
                    child: const Text('Retry'),
                  ),
                ),
              )
            : showLoading
            ? const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()),
              )
            : null;
        // 闸 5:滚动中不转,停下静止 300ms 才起转。判定放在这里而不是卡片里
        // —— 只有列表看得见滚动,卡片看不见。
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) {
            // Filtering can leave the initial page shorter than the viewport.
            // Layout metrics arrive even when there has been no scroll gesture.
            if (!_pageLoadFailed &&
                n.metrics.extentAfter < 1200 &&
                snap.connectionState == ConnectionState.done &&
                identical(_feed, sourceFeed)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && identical(_feed, sourceFeed)) {
                  unawaited(_maybeLoadMore(fetchedWorks));
                }
              });
            }
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) {
                _governor.onScrollStart();
              } else if (n is ScrollEndNotification) {
                _governor.onScrollEnd();
              }
              // 距底不足 1200px(约三张卡)就补下一页;去重和竞态在
              // _maybeLoadMore 里兜着,这里只管触发。
              if (!_pageLoadFailed &&
                  n.metrics.extentAfter < 1200 &&
                  snap.connectionState == ConnectionState.done &&
                  identical(_feed, sourceFeed)) {
                unawaited(_maybeLoadMore(fetchedWorks));
              }
              return false; // 别拦,RefreshIndicator 还要用这些通知
            },
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CommunityMasonry(
                        header: _showTopicCard
                            ? TopicCard(
                                autoPlay: _governor.liveAllowed,
                                activities: widget.activities,
                                onActivityTap: widget.onActivityTap,
                              )
                            : null,
                        itemCount: readyWorks.length,
                        footer: _remounting.isEmpty ? footer : null,
                        itemBuilder: (context, index) =>
                            _buildWorkCard(readyWorks[index], displayWorks),
                      ),
                      _hiddenPreparation([...held, ...pending], displayWorks),
                    ],
                  ),
                ),
                if (_remounting.isNotEmpty)
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: remountFailed
                          ? TextButton(
                              onPressed: _retryVisibleMedia,
                              child: const Text('Retry'),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isPrepared(FeedWork work) {
    final source = communityCoverSourceKey(work);
    return _prepared.containsKey(source);
  }

  void _rememberStill(String source, Uint8List? bytes) {
    if (bytes == null) return;
    _stillFrames.remove(source);
    _stillFrames[source] = bytes;
    while (_stillFrames.length > 24 ||
        _stillFrames.values.fold<int>(0, (n, b) => n + b.length) >
            16 * 1024 * 1024) {
      final victim = _stillFrames.keys.firstWhere(
        (key) => !(_firstPairSources?.contains(key) ?? false),
        orElse: () => _stillFrames.keys.first,
      );
      _stillFrames.remove(victim);
    }
  }

  Widget _hiddenPreparation(List<FeedWork> pending, List<FeedWork> works) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final width =
              (constraints.maxWidth - kCommunitySideInset * 2 - 4) / 2;
          return Offstage(
            offstage: true,
            child: TickerMode(
              enabled: true,
              child: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final work in pending)
                          _buildWorkCard(work, works, preparing: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

  void _retryVisibleMedia() {
    setState(() {
      for (final source in _failedPreparation) {
        _cardKeys.remove(source);
        if (!_remounting.containsKey(source)) _prepared.remove(source);
        _stillFrames.remove(source);
        _remounting.remove(source);
      }
      _failedPreparation.clear();
    });
  }

  Widget _buildWorkCard(
    FeedWork work,
    List<FeedWork> works, {
    bool preparing = false,
  }) {
    final source = communityCoverSourceKey(work);
    final generation = _feedGeneration;
    final preparation = _preparationGeneration;
    return WorkCard(
      key: _cardKeys.putIfAbsent(
        source,
        () => GlobalKey(debugLabel: 'community-$generation-${work.id}'),
      ),
      work: work,
      service: _service,
      viewerHostBuilderForTesting: widget.viewerHostBuilderForTesting,
      preparedStillBytes: _stillFrames[source],
      showMissingCover: true,
      coverAspectRatio:
          _coverAspectRatios[source] ??
          (_measured[source] == null
              ? null
              : _measured[source]!.viewerSize.width /
                    _measured[source]!.viewerSize.height),
      onCoverAspectRatioChanged: (ratio) => _rememberCoverAspect(work, ratio),
      isFocused: _liveWorkId == work.id,
      rotationAllowed: _governor.liveAllowed,
      viewerAllowed: _viewerAllowed,
      prepareWhileHidden: preparing,
      revealed: !preparing,
      onPrepared: (metrics) {
        if (!mounted ||
            generation != _feedGeneration ||
            preparation != _preparationGeneration ||
            !identical(
              metrics.readinessToken,
              _cardKeys[source]?.currentState,
            )) {
          return;
        }
        setState(() {
          _rememberStill(source, metrics.stillFrameBytes);
          _prepared[source] = metrics.layoutOnly;
          _measured[source] = metrics.layoutOnly;
          _failedPreparation.remove(source);
          _remounting.remove(source);
        });
      },
      onPreparationFailed: (_) {
        if (!mounted ||
            generation != _feedGeneration ||
            preparation != _preparationGeneration) {
          return;
        }
        setState(() => _failedPreparation.add(source));
      },
      onPreparationStarted: (token) {
        if (mounted &&
            generation == _feedGeneration &&
            preparation == _preparationGeneration &&
            _prepared.containsKey(source) &&
            identical(token, _cardKeys[source]?.currentState)) {
          setState(() => _remounting[source] = token);
        }
      },
      onPreparationDisposed: (token) {
        if (mounted && identical(_remounting[source], token)) {
          setState(() => _remounting.remove(source));
        }
      },
      onWorkUpdated: (updated) => _onWorkUpdated(work.id, updated),
      onAuthorTap: _onAuthorTap,
      onVisibilityChanged: (fraction) {
        if (preparing) return;
        _onCardVisibilityChanged(work.id, fraction);
      },
      onTap: () => _openWork(work),
    );
  }
}

// ignore: unused_element  —— [D2] 搜索代码按用户要求保留,只是不渲染。
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.hasQuery,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AetherColors.bgElevated,
        borderRadius: BorderRadius.circular(AetherRadii.pill),
        border: Border.all(color: AetherColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: AetherSpacing.md),
          const Icon(
            Icons.search_rounded,
            size: 18,
            color: AetherColors.textTertiary,
          ),
          const SizedBox(width: AetherSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: AetherTextStyles.body,
              decoration: InputDecoration(
                hintText: l.communitySearchHint,
                hintStyle: AetherTextStyles.body.copyWith(
                  color: AetherColors.textTertiary,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (hasQuery)
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AetherSpacing.md),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AetherColors.textTertiary,
                ),
              ),
            )
          else
            const SizedBox(width: AetherSpacing.md),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 160),
        const Icon(
          Icons.view_in_ar_rounded,
          size: 56,
          color: AetherColors.textTertiary,
        ),
        const SizedBox(height: AetherSpacing.lg),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              l.communityEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AetherColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 160),
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: AetherColors.danger,
        ),
        const SizedBox(height: AetherSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AetherColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AetherSpacing.lg),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: Text(AppL10n.of(context).authRetry),
          ),
        ),
      ],
    );
  }
}

/// [D9(a) 2026-08-23] 主题卡的内容**客户端硬编码**,不建表、不发请求。
///
/// 三选一里选 (a) 的理由:D6 已定为**常青人工精选**(不是限时活动),换得不频繁;
/// 冷启动期最贵的是工时不是发版。等真需要按周换,再升到独立的 topics 表。
///
/// 顺带解决了 D10(判定时机):没有请求 ⇒ 不存在"跟首屏一起请求拖慢首屏"
/// 还是"独立异步请求导致置顶卡晚于列表出现"的取舍。
///
/// **关掉它 = 把这里改成 false**,列表会自动退回纯作品流(itemCount 不再 +1)。
const bool kShowCommunityTopicCard = true;

/// 流内第一张卡:常青人工精选。
///
/// 与作品卡**同宽同层**,跟着一起滚、可以滑走 —— 这是 D5 的核心:
/// 它是"流里的一张卡",不是"压在流上面的一层"。
///
/// 文案走 l10n(communityTopicTitle / communityTopicBody),中英各一份。
/// ⚠️ 公开(而非 `_TopicCard`)是为了让 widget 测试能直接 pump 它。
/// 它本来也是个正经的可复用卡片,没有私有的理由 —— 本文件其余
/// `_LoadingState` / `_EmptyState` 之类仍是私有,因为没人从外面用。
/// 置顶栏的高宽比。
///
/// [2026-08-24 用户签决] **2.5:1**,即移动端 banner 的主流出稿尺寸 750×300。
///
/// 定这个数走了两步,中间被用户自己推翻过一次,值得留着:
///   ① 用户圈出想要的大小并说「至少达到我画红圈的大小」,还点名「去看看
///      网易云音乐或者其他 app 的置顶栏」。红框实测约 840×450 px ≈ 1.87:1,
///      **比行业主流的 2.5:1 高得多**。按"至少"这个字面,我取了 16:9。
///   ② 于是把 2.5:1 / 16:9 / 3:2 / 4:3 四个候选按 361pt 的真实卡片宽度画成
///      一页,让用户在**手机上按真实大小**看。看完他选了 2.5:1 ——
///      比自己圈的那块还矮 49pt。
///
/// 也就是说「至少达到红框」是隔着截图估出来的意向,不是看到实物后的判断;
/// 真实尺寸摆在眼前时判断变了。**以 ② 为准**,别再拿 ① 的那条线当地板。
///
/// 原来是内容自适应高度(361pt 宽下约 99pt),2.5:1 给到 144pt。
const double kTopicCardAspect = 2.5;

/// Activity artwork uses the 16:9 frame selected in the full-phone comparison.
const double kTopicActivityAspect = 16 / 9;

/// 自动翻页间隔。网易云那类 banner 的常规节奏。
const Duration kTopicAutoPlayInterval = Duration(seconds: 5);

class TopicActivity {
  const TopicActivity({required this.title, required this.image});

  final String title;
  final ImageProvider image;
}

/// 流内第一张卡:常青人工精选,**可翻页**。
///
/// 与作品卡**同宽同层**,跟着一起滚、可以滑走 —— 这是 D5 的核心:
/// 它是"流里的一张卡",不是"压在流上面的一层"。做成轮播不违反 D5:
/// 它照样在流里、照样滑得走,只是自己内部多了几页。
///
/// 文案走 l10n,中英各一份。
/// ⚠️ 公开(而非 `_TopicCard`)是为了让 widget 测试能直接 pump 它。
class TopicCard extends StatefulWidget {
  /// 自动翻页。
  ///
  /// ⚠️ **默认 false**,由调用方接热闸传 true(与 [SkeletonBox.animate] 一个
  /// 路子)。两个理由:
  ///   ① 一屏已经跑着 live 3D viewer,自动轮播是叠上去的第二个常驻 ticker,
  ///     热是本项目的硬约束,不该由一个卡片自己决定开不开;
  ///   ② 默认开会让所有直接 pump 这张卡的 widget 测试在 pumpAndSettle 上挂死
  ///     —— 周期性 Timer 永远 settle 不了。默认关就没有这个陷阱。
  final bool autoPlay;
  final List<TopicActivity> activities;
  final ValueChanged<int>? onActivityTap;

  const TopicCard({
    super.key,
    this.autoPlay = false,
    this.activities = const [],
    this.onActivityTap,
  });

  @override
  State<TopicCard> createState() => _TopicCardState();
}

class _TopicSlide {
  final IconData icon;
  final String title;
  final String body;
  const _TopicSlide(this.icon, this.title, this.body);
}

class _TopicCardState extends State<TopicCard> {
  final PageController _pc = PageController();
  Timer? _auto;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _syncAutoPlay();
  }

  @override
  void didUpdateWidget(covariant TopicCard old) {
    super.didUpdateWidget(old);
    if (widget.autoPlay != old.autoPlay) _syncAutoPlay();
  }

  void _syncAutoPlay() {
    _auto?.cancel();
    if (!widget.autoPlay) return;
    _auto = Timer.periodic(kTopicAutoPlayInterval, (_) {
      if (!mounted || !_pc.hasClients) return;
      final n = widget.activities.isEmpty
          ? _slides(context).length
          : widget.activities.length;
      if (n < 2) return;
      _pc.animateToPage(
        (_page + 1) % n,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pc.dispose();
    super.dispose();
  }

  List<_TopicSlide> _slides(BuildContext context) {
    final l = AppL10n.of(context);
    return [
      _TopicSlide(
        Icons.auto_awesome_rounded,
        l.communityTopicTitle,
        l.communityTopicBody,
      ),
      _TopicSlide(
        Icons.camera_alt_rounded,
        l.communityTopicCaptureTitle,
        l.communityTopicCaptureBody,
      ),
      _TopicSlide(
        Icons.threed_rotation_rounded,
        l.communityTopicViewerTitle,
        l.communityTopicViewerBody,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.activities.isEmpty
        ? _slides(
            context,
          ).map((slide) => _TopicSlideView(slide: slide)).toList()
        : [
            for (var i = 0; i < widget.activities.length; i++)
              InkWell(
                onTap: widget.onActivityTap == null
                    ? null
                    : () => widget.onActivityTap!(i),
                child: Image(
                  image: widget.activities[i].image,
                  semanticLabel: widget.activities[i].title,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
          ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCommunityCardRadius),
      child: AspectRatio(
        aspectRatio: widget.activities.isEmpty
            ? kTopicCardAspect
            : kTopicActivityAspect,
        child: ColoredBox(
          color: AetherColors.bgElevated,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pc,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => slides[i],
              ),
              if (slides.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: widget.activities.isEmpty
                      ? AetherSpacing.lg
                      : AetherSpacing.md,
                  child: _TopicDots(count: slides.length, index: _page),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicSlideView extends StatelessWidget {
  final _TopicSlide slide;

  const _TopicSlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 底部留出圆点的位置,否则正文会压在圆点上。
      padding: const EdgeInsets.fromLTRB(
        AetherSpacing.lg,
        AetherSpacing.lg,
        AetherSpacing.lg,
        AetherSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(slide.icon, size: 18, color: AetherColors.textPrimary),
              const SizedBox(width: AetherSpacing.sm),
              Flexible(
                child: Text(
                  slide.title,
                  style: AetherTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AetherColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AetherSpacing.sm),
          // 2.5:1 在 361pt 宽下只有 144pt 高,扣掉上下 padding 与圆点区,正文
          // 只剩三行的余地。英文那几条明显更长(中文 28 字 vs 英文 106 字符),
          // 溢出在固定高度的盒子里就是那条黄黑斜纹。Flexible + ellipsis 兜住。
          Flexible(
            child: Text(
              slide.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AetherTextStyles.body.copyWith(
                fontSize: 13,
                color: AetherColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicDots extends StatelessWidget {
  final int count;
  final int index;

  const _TopicDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on ? AetherColors.textPrimary : AetherColors.borderStrong,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

/// 主题卡的骨架版。
///
/// [D7] 作者过滤条。整个"只看这个人的作品"就只有这一条 —— 刻意到此为止。
///
/// 明确不做:头像大图、简介、关注按钮、粉丝/关注/作品数。
/// 依据见方案 §6:早做个人主页的三家(Roblox ~250 账号 / pixiv 三周破万 /
/// Instagram 首日 2.5 万)规模不可类比;与我们最像的 Sketchfab 是上线约
/// 7 个月后才有个人主页 URL 的,且**初期卡片连作者名都没有**。
class _AuthorFilterBar extends StatelessWidget {
  final String name;
  final VoidCallback onClear;

  const _AuthorFilterBar({required this.name, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AetherSpacing.md),
      decoration: BoxDecoration(
        color: AetherColors.bgElevated,
        borderRadius: BorderRadius.circular(AetherRadii.pill),
        border: Border.all(color: AetherColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.communityOnlyAuthor(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AetherTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AetherColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AetherSpacing.sm,
                vertical: AetherSpacing.xs,
              ),
              child: Text(
                l.communityClearAuthorFilter,
                style: AetherTextStyles.body.copyWith(
                  fontSize: 13,
                  color: AetherColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
