import 'package:flutter/material.dart';

class MiniProgramCreateButton extends StatelessWidget {
  const MiniProgramCreateButton({
    super.key,
    required this.onUpload,
    this.navigatorKey,
  });

  final VoidCallback onUpload;
  final GlobalKey<NavigatorState>? navigatorKey;

  Future<void> _openCreate(BuildContext context) async {
    context = navigatorKey?.currentState?.overlay?.context ?? context;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_outlined, color: Colors.black),
              title: const Text('上传'),
              subtitle: const Text('GLB / PLY'),
              onTap: () => Navigator.of(context).pop('upload'),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: Colors.black,
              ),
              title: const Text('拍摄'),
              onTap: () => Navigator.of(context).pop('capture'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'upload') {
      onUpload();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载 App'),
        content: const Text('请下载窗后城 App 进行拍摄。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      onPressed: () => _openCreate(context),
      icon: const Icon(Icons.add_rounded, size: 24, semanticLabel: '创作'),
    ),
  );
}
