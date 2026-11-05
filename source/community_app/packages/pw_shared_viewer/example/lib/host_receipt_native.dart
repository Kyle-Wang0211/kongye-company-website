import 'dart:convert';
import 'package:flutter/foundation.dart';

void publishState(Map<String, Object?> state) =>
    debugPrint('PW_VIEWER_STATE ${jsonEncode(state)}');
void publishReady() => debugPrint('PW_VIEWER_READY');
void publishError(Object error) => debugPrint('PW_VIEWER_ERROR $error');
