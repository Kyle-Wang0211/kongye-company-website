import 'package:flutter/material.dart';
import 'community_profile_shell.dart';

/// Guards document exits while keeping pushed pages and their drafts mounted.
class CommunityNavigationController {
  final _guards = <Object, Future<bool> Function()>{};
  void registerExitGuard(Object owner, Future<bool> Function() guard) =>
      _guards[owner] = guard;
  void unregisterExitGuard(Object owner) => _guards.remove(owner);
  Future<bool> confirmDocumentExit() async {
    for (final guard in _guards.values.toList().reversed) {
      try {
        if (!await guard()) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }
}

class CommunityNavigationScope extends InheritedWidget {
  const CommunityNavigationScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final CommunityNavigationController controller;
  static CommunityNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommunityNavigationScope>();
  @override
  bool updateShouldNotify(CommunityNavigationScope oldWidget) =>
      oldWidget.controller != controller;
}

/// Lives above Navigator, so a route cannot replace the community sidebar.
class CommunityNavigationFrame extends StatelessWidget {
  const CommunityNavigationFrame({
    super.key,
    required this.controller,
    required this.child,
    required this.onHome,
    required this.onFollowing,
    required this.onMyProfile,
    required this.onMessages,
    required this.onSettings,
    this.onOpenFiling,
    this.visible = true,
    this.selectedDestination = 'profile',
  });
  final CommunityNavigationController controller;
  final Widget child;
  final bool visible;
  final String selectedDestination;
  final VoidCallback onHome, onFollowing, onMyProfile, onMessages, onSettings;
  final VoidCallback? onOpenFiling;
  @override
  Widget build(BuildContext context) => CommunityNavigationScope(
    controller: controller,
    child: CommunityProfileShell(
      visible: visible,
      selectedDestination: selectedDestination,
      onHome: onHome,
      onFollowing: onFollowing,
      onMyProfile: onMyProfile,
      onMessages: onMessages,
      onSettings: onSettings,
      onOpenFiling: onOpenFiling,
      // Scope route BlockSemantics to the content so it cannot hide navigation.
      child: Semantics(container: true, explicitChildNodes: true, child: child),
    ),
  );
}

/// Unnamed conversation/detail routes inherit their owning named destination.
class CommunitySidebarRouteObserver extends NavigatorObserver
    with ChangeNotifier {
  final _names = <Route<dynamic>, String>{};
  String _currentRoute = '/';
  String get currentRoute => _currentRoute;
  Route<dynamic>? _currentRouteObject;
  Route<dynamic>? get currentRouteObject => _currentRouteObject;
  int _revision = 0;
  bool _closed = false;
  void _setRoute(String name) {
    if (_closed || name == _currentRoute) return;
    _currentRoute = name;
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_closed && revision == _revision) notifyListeners();
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name ?? _names[previousRoute] ?? _currentRoute;
    _names[route] = name;
    _currentRouteObject = route;
    _setRoute(name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _names.remove(route);
    _currentRouteObject = previousRoute;
    _setRoute(_names[previousRoute] ?? previousRoute?.settings.name ?? '/');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final name = newRoute?.settings.name ?? _names[oldRoute] ?? _currentRoute;
    if (oldRoute != null) _names.remove(oldRoute);
    if (newRoute != null) _names[newRoute] = name;
    if (identical(_currentRouteObject, oldRoute)) {
      _currentRouteObject = newRoute;
      _setRoute(name);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _names.remove(route);
    if (identical(_currentRouteObject, route)) {
      _currentRouteObject = previousRoute;
      _setRoute(_names[previousRoute] ?? previousRoute?.settings.name ?? '/');
    }
  }

  @override
  void dispose() {
    _closed = true;
    _revision++;
    _names.clear();
    _currentRouteObject = null;
    super.dispose();
  }
}

const _profileRoutes = {
  '/profile',
  '/profile-edit',
  '/favorites',
  '/likes',
  '/history',
  '/privacy',
  '/reports',
  '/report-review',
  '/publications',
};
String _effectiveRoute(Uri entry, String route) =>
    route == '/' && entry.fragment.startsWith('/') ? entry.fragment : route;
bool communitySidebarVisible(Uri entry, String route) {
  final name = _effectiveRoute(entry, route);
  if (name == '/messages' ||
      _profileRoutes.contains(name) ||
      Uri.tryParse(name)?.queryParameters.containsKey('profile') == true ||
      name == '/publish') {
    return true;
  }
  return !entry.queryParameters.containsKey('auth') &&
      !entry.queryParameters.containsKey('work');
}

String communitySidebarDestination(Uri entry, String route, {String? ownerId}) {
  final name = _effectiveRoute(entry, route);
  if (name == '/messages') return 'messages';
  if (_profileRoutes.contains(name)) return 'profile';
  final target =
      Uri.tryParse(name)?.queryParameters['profile'] ??
      entry.queryParameters['profile'];
  if (target != null) return target == ownerId ? 'profile' : '';
  return name == '/' ? 'hot' : '';
}

/// Destination highlighting can be inherited; deduplication uses actual settings.
bool communityInboxIsTop(RouteSettings? top) =>
    top?.name == '/messages' && top?.arguments == null;
bool communityOwnProfileIsTop(Uri entry, RouteSettings? top, String ownerId) {
  if (top == null) return false;
  if (top.name == '/profile') return true;
  if (top.name == '/') return entry.queryParameters['profile'] == ownerId;
  return Uri.tryParse(top.name ?? '')?.queryParameters['profile'] == ownerId;
}
