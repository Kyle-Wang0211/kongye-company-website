import 'dart:js_interop';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Mount the website's original HTML, styles and carousel inside the feed.
class WebsiteFeaturedScreens extends StatefulWidget {
  const WebsiteFeaturedScreens({super.key});

  @override
  State<WebsiteFeaturedScreens> createState() => _WebsiteFeaturedScreensState();
}

class _WebsiteFeaturedScreensState extends State<WebsiteFeaturedScreens> {
  web.HTMLIFrameElement? _frame;
  web.ResizeObserver? _attachmentObserver;
  late final JSFunction _listener;
  double _height = 240;

  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      if (!mounted ||
          _frame == null ||
          event.origin != web.window.location.origin ||
          event.source != _frame!.contentWindow) {
        return;
      }
      final data = event.data.dartify();
      if (data is! Map || data['protocol'] != 'PW_FEATURED_SCREENS_V1') return;
      final height = data['height'];
      if (height is! num || !height.isFinite || height < 80 || height > 800) {
        return;
      }
      if ((_height - height).abs() > 1) {
        setState(() => _height = height.toDouble());
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _attachmentObserver?.disconnect();
    _frame?.src = 'about:blank';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _height,
    child: HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (element) {
        _frame = (element as web.HTMLIFrameElement)
          ..title = '精选屏幕'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.border = '0'
          ..style.display = 'block';
        final frame = _frame!;
        // Platform views create the element before attaching it to the DOM.
        // Start iframe navigation only once the browser has a live frame.
        _attachmentObserver?.disconnect();
        _attachmentObserver = web.ResizeObserver(
          (
                JSArray<web.ResizeObserverEntry> entries,
                web.ResizeObserver observer,
              ) {
                if (!frame.isConnected) return;
                observer.disconnect();
                frame.src = Uri.base
                    .resolve('/miniprogram-featured.html?mini=1')
                    .toString();
              }
              .toJS,
        )..observe(frame);
      },
    ),
  );
}
