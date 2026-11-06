import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

void publishState(Map<String, Object?> state) =>
    web.window.setProperty('pwFlutterHostState'.toJS, jsonEncode(state).toJS);
void publishReady() =>
    web.window.setProperty('pwFlutterHostReady'.toJS, true.toJS);
void publishError(Object error) =>
    web.window.setProperty('pwFlutterHostError'.toJS, error.toString().toJS);
