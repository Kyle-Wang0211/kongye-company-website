import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../../l10n/app_localizations.dart';

class StreamingPointCloudView extends StatefulWidget {
  const StreamingPointCloudView({super.key, required this.source});
  final Uri source;
  @override
  State<StreamingPointCloudView> createState() =>
      _StreamingPointCloudViewState();
}

class _StreamingPointCloudViewState extends State<StreamingPointCloudView> {
  static int _nextView = 0;
  late final String _viewType;
  late final web.HTMLIFrameElement _frame;
  late final JSFunction _listener;
  bool _ready = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'pw-point-cloud-stream-${_nextView++}';
    _frame = web.HTMLIFrameElement()
      ..title = '3D'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0'
      ..style.display = 'block'
      ..style.backgroundColor = '#000';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    _listener = ((web.MessageEvent event) {
      if (!mounted ||
          event.origin != web.window.location.origin ||
          event.source != _frame.contentWindow)
        return;
      final data = event.data.dartify();
      if (data is! Map || data['protocol'] != 'PW_POINT_CLOUD_STREAM_V1')
        return;
      if (data['type'] == 'ready') {
        setState(() {
          _ready = true;
          _failed = false;
        });
      } else if (data['type'] == 'error') {
        setState(() {
          _ready = false;
          _failed = true;
        });
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
    _load();
  }

  void _load() {
    _ready = false;
    _failed = false;
    _frame.src = Uri.parse(web.window.location.origin)
        .resolve('/pointcloud-viewer/index.html')
        .replace(queryParameters: {'source': widget.source.toString()})
        .toString();
  }

  @override
  void didUpdateWidget(covariant StreamingPointCloudView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _load();
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _frame.src = 'about:blank';
    _frame.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_ready)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppL10n.of(context).communityCloudLoadFailed,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        TextButton(
                          onPressed: () => setState(_load),
                          child: Text(AppL10n.of(context).communityRetry),
                        ),
                      ],
                    )
                  : const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}
