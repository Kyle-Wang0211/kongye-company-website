import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/current_user.dart';
import '../../community/web_messaging_repository.dart';
import '../../community/account_work_library_repository.dart';
import 'account_work_library_page.dart';
import '../../community/web_social_api.dart';
import '../../community/public_work_repository.dart';
import '../../community/community_service.dart';
import '../../config/endpoint_config.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_root_view.dart';
import '../design_system.dart';
import '../community/work_detail_page.dart';
import '../community/web_publication_page.dart';
import '../community/public_profile_entry.dart';
import 'community_capabilities.dart';
import 'web_favorites_page.dart';
import 'web_messaging_entry.dart';
import 'web_profile_edit_entry.dart';
import 'web_account_workflow_repository.dart';
import 'web_account_privacy_page.dart';
import 'web_publication_status_page.dart';
import 'web_report_history_page.dart';
import 'web_report_review_page.dart';

/// Root navigation is account-owned after the first authenticated identity.
/// Initial login keeps the public reading route beneath the sign-in flow.
class CommunityAccountNavigationIdentity {
  String? _previousAccount;
  int _epoch = 0;

  Key keyFor(CurrentUser user) {
    final owner = user.signedInUser?.id.rawValue;
    final account = owner == null
        ? null
        : '${user.deployment.namespace}:$owner';
    if (_previousAccount != null && _previousAccount != account) _epoch++;
    _previousAccount = account;
    return ValueKey(_epoch);
  }
}

/// Private account destination remains behind the current Auth startup state.
Route<void>? communityFavoritesRoute(RouteSettings settings, CurrentUser user) {
  if (!const {'/favorites', '/likes', '/history'}.contains(settings.name) ||
      (settings.name == '/favorites' && !CommunityCapabilities.favorites)) {
    return null;
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        final state = user.state;
        if (state case CurrentUserServiceUnavailable(:final reason)) {
          return CommunityServiceUnavailableView(
            currentUser: user,
            reason: reason,
          );
        }
        final owner = user.signedInUser?.id.rawValue;
        if (owner == null) {
          return state is CurrentUserSignedOut
              ? AuthRootView(currentUser: user)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        return WebFavoritesAccountEntry(
          key: ValueKey('${user.deployment.namespace}:$owner:${settings.name}'),
          user: user,
          ownerId: owner,
          kind: switch (settings.name) {
            '/likes' => AccountWorkLibraryKind.likes,
            '/history' => AccountWorkLibraryKind.history,
            _ => null,
          },
        );
      },
    ),
  );
}

/// Reuses the account startup gate for inbox and profile-originated messages.
Route<void>? communityMessagingRoute(
  RouteSettings settings,
  CurrentUser user, {
  WebMessagingRepository? repository,
}) {
  if (settings.name != '/messages') return null;
  final peer = settings.arguments is WebMessagingPeer
      ? settings.arguments as WebMessagingPeer
      : null;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        final state = user.state;
        if (state case CurrentUserServiceUnavailable(:final reason)) {
          return CommunityServiceUnavailableView(
            currentUser: user,
            reason: reason,
          );
        }
        final owner = user.signedInUser?.id.rawValue;
        if (owner == null) {
          return state is CurrentUserSignedOut
              ? AuthRootView(currentUser: user)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        return WebMessagingEntry(
          key: ValueKey(
            '${user.deployment.namespace}:$owner:messages:${peer?.id ?? ''}',
          ),
          user: user,
          ownerId: owner,
          peerId: peer?.id,
          peerName: peer?.displayName,
          repository: repository,
        );
      },
    ),
  );
}

/// Account pages remain behind the same live Auth state as inbox and favorites.
Route<void>? communityAccountRoute(
  RouteSettings settings,
  CurrentUser user, {
  Widget Function(BuildContext context, String ownerId)? pageBuilder,
}) {
  if (!const {
    '/publish',
    '/profile-edit',
    '/publications',
    '/reports',
    '/privacy',
    '/report-review',
  }.contains(settings.name)) {
    return null;
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => AnimatedBuilder(
      animation: user,
      builder: (context, _) {
        final state = user.state;
        if (state case CurrentUserServiceUnavailable(:final reason)) {
          return CommunityServiceUnavailableView(
            currentUser: user,
            reason: reason,
          );
        }
        final owner = user.signedInUser?.id.rawValue;
        if (owner == null) {
          return state is CurrentUserSignedOut
              ? AuthRootView(currentUser: user)
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
        }
        return KeyedSubtree(
          key: ValueKey('${user.deployment.namespace}:$owner:${settings.name}'),
          child:
              pageBuilder?.call(context, owner) ??
              _WebAccountDestination(
                user: user,
                ownerId: owner,
                destination: settings.name!,
              ),
        );
      },
    ),
  );
}

class _WebAccountDestination extends StatefulWidget {
  const _WebAccountDestination({
    required this.user,
    required this.ownerId,
    required this.destination,
  });
  final CurrentUser user;
  final String ownerId, destination;
  @override
  State<_WebAccountDestination> createState() => _WebAccountDestinationState();
}

class _WebAccountDestinationState extends State<_WebAccountDestination> {
  late final WebAccountWorkflowRepository _repository;
  bool get _current =>
      mounted && widget.user.signedInUser?.id.rawValue == widget.ownerId;

  @override
  void initState() {
    super.initState();
    _repository = WebAccountWorkflowRepository(
      client: Supabase.instance.client,
      accountId: widget.ownerId,
    );
  }

  Future<void> _openWork(String id) async {
    if (!_current) return;
    try {
      final work = await PublicWorkRepository(
        Supabase.instance.client,
      ).fetch(id);
      if (!mounted || !_current) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => WorkDetailPage(
            work: work,
            service: CommunityService(),
            onAuthorTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => PublicProfileEntry(
                  user: widget.user,
                  userId: work.userId,
                  seedWork: work,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted && _current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('作品暂不可访问，请刷新状态后重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.destination) {
    '/publish' => const WebPublicationPage(),
    '/profile-edit' => WebProfileEditEntry(
      user: widget.user,
      ownerId: widget.ownerId,
    ),
    '/privacy' => WebAccountPrivacyPage(
      accountId: widget.ownerId,
      accountLabel: widget.user.signedInUser?.displayName,
      loadBlockedUsers: _repository.blockedUsers,
      onUnblock: _repository.unblock,
      onRequestDeletion: _repository.requestDeletion,
    ),
    '/reports' => WebReportHistoryPage(
      accountId: widget.ownerId,
      loader: _repository.reports,
    ),
    '/report-review' => WebReportReviewPage(
      accountId: widget.ownerId,
      loader: _repository.reviewQueue,
      onClaim: _repository.claimReport,
      onTransition: _repository.transitionReport,
      onRestoreWork: _repository.restoreWork,
      onOpenWork: _openWork,
    ),
    _ => WebPublicationStatusPage(
      accountId: widget.ownerId,
      loader: _loadPublications,
      onOpen: _openWork,
      onWithdraw: _repository.withdraw,
    ),
  };

  Future<List<WebPublicationSummary>> _loadPublications() async {
    if (!_current) throw StateError('Account changed');
    final client = Supabase.instance.client;
    if (client.auth.currentUser?.id != widget.ownerId) {
      throw StateError('Account changed');
    }
    final rows = await client
        .from('works')
        .select(
          'id,user_id,title,moderation_status,visibility,published_at,deleted_at',
        )
        .eq('user_id', widget.ownerId)
        .order('created_at', ascending: false);
    if (!_current || client.auth.currentUser?.id != widget.ownerId) {
      throw StateError('Account changed');
    }
    return rows
        .map((row) {
          final moderation = row['moderation_status'] as String;
          final removed = row['deleted_at'] != null || moderation == 'removed';
          final stage = removed
              ? 'removed'
              : moderation == 'withdrawn'
              ? 'withdrawn'
              : moderation == 'ok'
              ? row['visibility'] == 'public' && row['published_at'] != null
                    ? 'published'
                    : 'private'
              : moderation;
          return WebPublicationSummary(
            id: row['id'] as String,
            title: row['title'] as String? ?? '',
            stage: stage,
            updatedAt: DateTime.tryParse(row['published_at'] as String? ?? ''),
            canWithdraw: !removed && moderation != 'withdrawn',
          );
        })
        .toList(growable: false);
  }
}

class CommunityServiceUnavailableView extends StatelessWidget {
  const CommunityServiceUnavailableView({
    super.key,
    required this.currentUser,
    required this.reason,
  });

  final CurrentUser currentUser;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      backgroundColor: AetherColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.authServiceUnavailable,
                  textAlign: TextAlign.center,
                  style: AetherTextStyles.body,
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: currentUser,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: currentUser.isRetryingInit
                            ? null
                            : () => unawaited(currentUser.retryServiceInit()),
                        child: Text(l.authRetry),
                      ),
                      if (currentUser.nextAutoRetryAt != null ||
                          currentUser.isRetryingInit) ...[
                        const SizedBox(height: 12),
                        Text(
                          l.authAutoRetrying,
                          textAlign: TextAlign.center,
                          style: AetherTextStyles.caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Current account binding for the existing favorites API and public work viewer.
class WebFavoritesAccountEntry extends StatefulWidget {
  const WebFavoritesAccountEntry({
    super.key,
    required this.user,
    required this.ownerId,
    this.api,
    this.kind,
  });
  final AccountWorkLibraryKind? kind;
  final CurrentUser user;
  final String ownerId;
  final WebSocialApi? api;

  @override
  State<WebFavoritesAccountEntry> createState() =>
      _WebFavoritesAccountEntryState();
}

class _WebFavoritesAccountEntryState extends State<WebFavoritesAccountEntry> {
  late final WebSocialApi _api;
  bool get _current =>
      mounted && widget.user.signedInUser?.id.rawValue == widget.ownerId;

  @override
  void initState() {
    super.initState();
    final deployment = widget.user.deployment;
    final endpoint = EndpointConfigResolver.current;
    final origin = Uri.parse(endpoint?.supabaseUrl ?? deployment.supabaseUrl);
    _api =
        widget.api ??
        WebSocialApi(
          apiOrigin: origin,
          supabaseOrigin: origin,
          publishableKey: endpoint?.supabaseAnonKey ?? deployment.anonKey,
          region: deployment.region.name,
          authNamespace: deployment.namespace,
          favoritesEnabled: true,
          accessToken: () {
            if (!_current) return null;
            final auth = Supabase.instance.client.auth;
            return auth.currentUser?.id == widget.ownerId
                ? auth.currentSession?.accessToken
                : null;
          },
          currentUserId: () => _current ? widget.ownerId : null,
        );
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    if (!_current) throw const WebSocialUnavailableException('session_changed');
    final result = await operation();
    if (!_current) throw const WebSocialUnavailableException('session_changed');
    return result;
  }

  Future<List<WebFavoriteItem>> _load() => _guard(() async {
    final author = Localizations.localeOf(context).languageCode == 'zh'
        ? '创作者'
        : 'Creator';
    final items = <WebFavoriteItem>[];
    final cursors = <String>{};
    WebFavoriteCursor? cursor;
    do {
      final page = await _guard(
        () => _api.listFavorites(limit: 100, before: cursor),
      );
      // Existing API remains authoritative for saved membership and order.
      // Public summaries are a bulk, best-effort cover/name enhancement.
      Map<String, AccountWorkLibraryItem> summaries = const {};
      try {
        summaries = await _guard(
          () =>
              AccountWorkLibraryRepository(
                client: Supabase.instance.client,
                ownerId: widget.ownerId,
              ).visibleWorkSummaries(
                page.items.map((item) => item.workId).toList(),
              ),
        );
      } catch (_) {
        if (!_current) rethrow;
      }
      final service = summaries.isEmpty ? null : CommunityService();
      items.addAll(
        page.items.map((item) {
          final summary = summaries[item.workId];
          final path = summary?.thumbnailStoragePath;
          return WebFavoriteItem(
            id: item.workId,
            title: item.title,
            author: summary?.authorDisplayName.trim().isNotEmpty == true
                ? summary!.authorDisplayName
                : author,
            thumbnailUrl: path == null || path.isEmpty
                ? null
                : service?.thumbnailUrlFor(path),
          );
        }),
      );
      cursor = page.next;
      if (cursor != null &&
          !cursors.add('${cursor.savedAt}:${cursor.workId}')) {
        throw const WebSocialUnavailableException('invalid_cursor');
      }
    } while (cursor != null);
    return items;
  });

  Future<void> _open(String id) async {
    try {
      final work = await _guard(
        () => PublicWorkRepository(Supabase.instance.client).fetch(id),
      );
      if (!mounted || !_current) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkDetailPage(
            work: work,
            service: CommunityService(),
            onAuthorTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => PublicProfileEntry(
                  user: widget.user,
                  userId: work.userId,
                  seedWork: work,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !_current) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '作品暂不可访问'
                : 'This work is unavailable',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.kind != null
      ? AccountWorkLibraryPage(
          accountId: widget.ownerId,
          kind: widget.kind!,
          loadPage: (cursor) => _guard(
            () => AccountWorkLibraryRepository(
              client: Supabase.instance.client,
              ownerId: widget.ownerId,
            ).load(widget.kind!, before: cursor),
          ),
          thumbnailUrlFor: (path) => CommunityService().thumbnailUrlFor(path),
          onOpen: _open,
        )
      : WebFavoritesPage(
          accountId: widget.ownerId,
          loadFavorites: _load,
          onOpen: _open,
          onSetFavorite: (id, saved) => _guard(() async {
            await _api.setFavorite(id, saved);
          }),
        );
}
