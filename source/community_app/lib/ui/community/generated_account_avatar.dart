import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/current_user.dart';

import '../../auth/auth_scope.dart';
import '../../community/generated_avatar.dart';
import '../../community/generated_avatar_repository.dart';
import '../../config/backend_deployment.dart';
import '../design_system.dart';

/// A per-account official generated PNG, never selected from a fixed image pool.
/// No upload, picker, external avatar URL or client-side generator port.
class GeneratedAccountAvatar extends StatefulWidget {
  const GeneratedAccountAvatar({
    super.key,
    required this.userId,
    this.deploymentId,
    this.image,
    this.repository,
    this.fromBlockedList = false,
    this.radius = 24,
  }) : assert(radius > 0 && radius < double.infinity);
  final String userId;
  final String? deploymentId;
  final GeneratedAvatarImage? image;
  final GeneratedAvatarRepository? repository;
  final double radius;
  final bool fromBlockedList;
  @override
  State<GeneratedAccountAvatar> createState() => _GeneratedAccountAvatarState();
}

class _GeneratedAccountAvatarState extends State<GeneratedAccountAvatar> {
  GeneratedAvatarImage? _image;
  String? _requestKey;
  int _request = 0;
  CurrentUser? _authUser;
  GeneratedAvatarRepository? _defaultRepository;
  GeneratedAvatarSession? _liveSession() {
    if (!mounted) return null;
    final auth = _authUser;
    if (auth != null) {
      final viewer = auth.signedInUser?.id.rawValue;
      return viewer == null
          ? null
          : GeneratedAvatarSession(
              deploymentId: auth.deployment.id,
              viewerUserId: viewer,
            );
    }
    try {
      final viewer = Supabase.instance.client.auth.currentUser?.id;
      return viewer == null
          ? null
          : GeneratedAvatarSession(
              deploymentId: BackendDeployment.fromBuild().id,
              viewerUserId: viewer,
            );
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant GeneratedAccountAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    _authUser = context
        .dependOnInheritedWidgetOfExactType<AuthScope>()
        ?.notifier;
    final repository =
        widget.repository ??
        (_defaultRepository ??= GeneratedAvatarRepository.forSession(
          _liveSession,
        ));
    final session = repository.currentSession();
    final deployment =
        widget.deploymentId ??
        session?.deploymentId ??
        _authUser?.deployment.id ??
        BackendDeployment.fromBuild().id;
    final key =
        '$deployment\u0000${session?.viewerUserId ?? ''}\u0000${widget.userId}\u0000${widget.image?.pngSha256 ?? ''}\u0000${widget.fromBlockedList}\u0000${identityHashCode(repository)}';
    if (key == _requestKey) return;
    _requestKey = key;
    final request = ++_request;
    _image =
        session == null ||
            session.deploymentId != deployment ||
            widget.userId.trim().isEmpty
        ? null
        : widget.image;
    repository
        .load(
          deploymentId: deployment,
          userId: widget.userId,
          supplied: _image,
          fromBlockedList: widget.fromBlockedList,
        )
        .then((image) {
          if (mounted &&
              request == _request &&
              repository.currentSession() == session) {
            setState(() => _image = image);
          }
        });
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.radius * 2,
      child: ClipOval(
        child: ColoredBox(
          color: AetherColors.bgElevated,
          child: _image == null
              ? _fallback()
              : Image.memory(
                  _image!.png,
                  width: widget.radius * 2,
                  height: widget.radius * 2,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => _fallback(),
                ),
        ),
      ),
    ),
  );
  Widget _fallback() => Center(
    child: Icon(
      Icons.person_outline,
      size: widget.radius,
      color: AetherColors.textTertiary,
    ),
  );
}
