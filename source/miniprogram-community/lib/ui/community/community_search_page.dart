import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../community/community_search_service.dart';
import '../../community/feed_models.dart';
import '../../community/social_profile_models.dart';
import '../../l10n/app_localizations.dart';
import 'community_loading.dart';
import 'generated_account_avatar.dart';
import 'masonry_layout.dart';
import 'masonry_policy.dart';
import 'search_suggestion_list.dart';
import 'user_profile_page.dart';
import 'work_card.dart';

/// This entire search surface is shared by the App and mini-program hosts.
/// Host navigation and the existing community renderers remain their own.
class CommunitySearchPage extends StatefulWidget {
  const CommunitySearchPage({
    super.key,
    this.service,
    required this.onWorkSelected,
  });

  final CommunitySearchService? service;
  final ValueChanged<FeedWork> onWorkSelected;

  @override
  State<CommunitySearchPage> createState() => _CommunitySearchPageState();
}

class _CommunitySearchPageState extends State<CommunitySearchPage>
    with SingleTickerProviderStateMixin {
  late final _service = widget.service ?? CommunitySearchService();
  late final TabController _tabs;
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _generation = 0;
  int _selectedTab = 0;
  bool _loading = false;
  bool _failed = false;
  bool _submitted = false;
  List<String> _suggestions = const [];
  List<FeedWork> _works = const [];
  List<SocialProfile> _users = const [];
  final Map<String, Future<SocialProfile>> _relationships = {};
  final Set<String> _followInFlight = {};

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    final generation = ++_generation;
    final query = value.trim();
    setState(() {
      _submitted = false;
      _failed = false;
      _works = const [];
      _users = const [];
      _relationships.clear();
      _suggestions = const [];
      _loading = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(_loadSuggestions(query, generation));
      unawaited(_loadResults(query, generation));
    });
  }

  Future<void> _loadSuggestions(String query, int generation) async {
    try {
      final suggestions = await _service.suggest(query);
      if (!mounted || generation != _generation) return;
      setState(
        () => _suggestions = suggestions
            .take(SearchSuggestionList.maxResults)
            .toList(),
      );
    } catch (_) {
      // Suggestions are optional while the selected results request completes.
      if (mounted && generation == _generation) {
        setState(() => _suggestions = const []);
      }
    }
  }

  Future<void> _loadResults(String query, int generation) async {
    try {
      if (_selectedTab == 0) {
        final works = await _service.search(query);
        if (!mounted || generation != _generation) return;
        setState(() {
          _works = works;
          _loading = false;
        });
      } else {
        final users = await _service.users(query);
        if (!mounted || generation != _generation) return;
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _tabChanged() {
    if (_tabs.index == _selectedTab) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _controller.text.trim();
    setState(() {
      _selectedTab = _tabs.index;
      _loading = query.isNotEmpty;
      _failed = false;
    });
    if (query.isEmpty) return;
    if (!_submitted) unawaited(_loadSuggestions(query, generation));
    unawaited(_loadResults(query, generation));
  }

  Future<void> _search([String? suggestion]) async {
    final query = (suggestion ?? _controller.text).trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    final generation = ++_generation;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    setState(() {
      _submitted = true;
      _loading = true;
      _failed = false;
      _suggestions = const [];
      _works = const [];
      _users = const [];
    });
    await _loadResults(query, generation);
  }

  void _fillSuggestion(String suggestion) {
    _controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    _changed(suggestion);
    _focus.requestFocus();
  }

  void _openUser(String id) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => UserProfilePage(userId: id)));

  void _workUpdated(FeedWork updated) {
    if (!mounted) return;
    setState(
      () => _works = [
        for (final work in _works) work.id == updated.id ? updated : work,
      ],
    );
  }

  Future<void> _toggleFollow(SocialProfile profile) async {
    final id = profile.id;
    if (!_followInFlight.add(id)) return;
    setState(() {});
    try {
      if (profile.isFollowing) {
        await _service.profiles.unfollow(id);
      } else {
        await _service.profiles.follow(id);
      }
      final updated = await _service.profiles.fetchProfile(id);
      if (!mounted) return;
      setState(() {
        _relationships[id] = Future.value(updated);
        _users = [
          for (final result in _users)
            result.id == id
                ? result.copyWith(
                    followersCount: updated.followersCount,
                    isFollowing: updated.isFollowing,
                  )
                : result,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppL10n.of(context).socialActionFailed)),
      );
    } finally {
      _followInFlight.remove(id);
      if (mounted) setState(() {});
    }
  }

  Widget _followButton(SocialProfile profile) {
    if (_service.profiles.currentUserId == profile.id) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<SocialProfile>(
      future: _relationships.putIfAbsent(
        profile.id,
        () => _service.profiles.fetchProfile(profile.id),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            onPressed: () => setState(() => _relationships.remove(profile.id)),
            child: Text(_zh ? '重试' : 'Retry'),
          );
        }
        final relationship = snapshot.data;
        if (relationship == null || _followInFlight.contains(profile.id)) {
          return const SizedBox(
            width: 72,
            height: 36,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey,
                ),
              ),
            ),
          );
        }
        final labels = AppL10n.of(context);
        return FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(72, 36),
          ),
          onPressed: () => _toggleFollow(relationship),
          child: Text(
            relationship.isFollowing
                ? labels.socialFollowing
                : labels.socialFollow,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchLabel = _zh ? '搜索' : 'Search';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          cursorColor: Colors.black,
          textInputAction: TextInputAction.search,
          maxLength: 128,
          onChanged: _changed,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: AppL10n.of(context).communitySearchHint,
            counterText: '',
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: _zh ? '清除' : 'Clear',
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: () {
                      _controller.clear();
                      _changed('');
                      _focus.requestFocus();
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _controller.text.trim().isEmpty ? null : () => _search(),
            style: TextButton.styleFrom(foregroundColor: Colors.black),
            child: Text(searchLabel),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: const _SearchTabIndicator(),
          tabs: [
            Tab(text: _zh ? '作品' : 'Works'),
            Tab(text: _zh ? '用户' : 'Users'),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            if (!_submitted && _suggestions.isNotEmpty)
              SizedBox(
                height: math.min(
                  _suggestions.length * 64.0,
                  constraints.maxHeight * .35,
                ),
                child: SearchSuggestionList(
                  suggestions: _suggestions,
                  onSearch: _search,
                  onFill: _fillSuggestion,
                  fillTooltip: _zh ? '填入搜索框' : 'Use this search term',
                ),
              ),
            Expanded(child: _results()),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    if (_controller.text.trim().isEmpty) return const SizedBox.shrink();
    if (_loading) {
      if (_selectedTab == 0) {
        return CommunityMasonry(
          itemCount: 4,
          itemBuilder: (_, _) => const CommunityCardSkeleton(),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: Colors.black),
      );
    }
    if (_failed) {
      return Center(
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          onPressed: _search,
          child: Text(_zh ? '搜索暂不可用，点按重试' : 'Search unavailable. Tap to retry'),
        ),
      );
    }
    if (_selectedTab == 1) {
      if (_users.isEmpty) {
        return Center(child: Text(_zh ? '未找到相关用户' : 'No matching users'));
      }
      return ListView.builder(
        itemCount: _users.length,
        itemBuilder: (_, index) {
          final user = _users[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            leading: GeneratedAccountAvatar(
              userId: user.id,
              readPublic: true,
              radius: 24,
            ),
            title: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _zh
                        ? '粉丝 ${user.followersCount}'
                        : '${user.followersCount} followers',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _zh
                        ? '窗后城号：${user.publicAccountNumber}'
                        : 'Account number: ${user.publicAccountNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            trailing: _followButton(user),
            onTap: () => _openUser(user.id),
          );
        },
      );
    }
    if (_works.isEmpty) {
      return Center(child: Text(_zh ? '未找到相关作品' : 'No matching works'));
    }
    return CommunityMasonry(
      itemCount: _works.length,
      itemBuilder: (_, index) {
        final work = _works[index];
        return WorkCard(
          key: ValueKey(communityCoverSourceKey(work)),
          work: work,
          service: _service.workService,
          onTap: () => widget.onWorkSelected(work),
          onAuthorTap: (author) => _openUser(author.userId),
          onWorkUpdated: _workUpdated,
        );
      },
    );
  }
}

/// A fixed36×4 rounded underline, independent of the localized label width.
class _SearchTabIndicator extends Decoration {
  const _SearchTabIndicator();
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _SearchTabPainter();
}

class _SearchTabPainter extends BoxPainter {
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = Rect.fromLTWH(
      offset.dx + (size.width - 36) / 2,
      offset.dy + size.height - 4,
      36,
      4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = Colors.black,
    );
  }
}
