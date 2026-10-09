import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../api_client.dart';

/// 控制嵌入頁面 /avatar/index.html（3D 角色＋語音）的橋接層。
/// 指令以 postMessage 送出；事件（辨識文字、播放狀態…）從 [events] 取得。
class AvatarController {
  static int _counter = 0;

  final String viewType = 'avatar-view-${_counter++}';
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final Completer<bool> _ready = Completer<bool>();
  web.HTMLIFrameElement? _iframe;
  JSFunction? _listener;

  /// 頁面載入完成時完成；值為「瀏覽器是否支援語音辨識」。
  Future<bool> get ready => _ready.future;
  Stream<Map<String, dynamic>> get events => _events.stream;

  AvatarController() {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final frame = web.HTMLIFrameElement()
        ..src = '${ApiClient.instance.base}/avatar/index.html'
        ..allow = 'microphone; autoplay';
      frame.style
        ..border = 'none'
        ..width = '100%'
        ..height = '100%';
      _iframe = frame;
      return frame;
    });

    _listener = ((web.MessageEvent e) {
      if (e.origin != web.window.location.origin &&
          e.origin != ApiClient.instance.base) {
        return;
      }
      final data = e.data.dartify();
      if (data is! Map) return;
      final msg = data.map((k, v) => MapEntry(k.toString(), v));
      if (msg['type'] == 'ready' && !_ready.isCompleted) {
        _ready.complete(msg['sttSupported'] == true);
      }
      _events.add(msg);
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  void send(Map<String, Object?> message) {
    final win = _iframe?.contentWindow;
    if (win == null) return;
    win.postMessage(message.jsify(), ApiClient.instance.base.toJS);
  }

  /// [gender]：'female' 或 'male'，決定角色外觀（與載入哪個 VRM）。
  void setPersona(String persona, String gender) =>
      send({'type': 'setPersona', 'persona': persona, 'gender': gender});
  void setEmotion(String emotion) =>
      send({'type': 'setEmotion', 'emotion': emotion});
  void speak(String url, String emotion) =>
      send({'type': 'speak', 'url': url, 'emotion': emotion});
  void stopSpeaking() => send({'type': 'stopSpeaking'});
  void startListening() => send({'type': 'startListening'});
  void stopListening() => send({'type': 'stopListening'});

  void dispose() {
    stopSpeaking();
    stopListening();
    if (_listener != null) {
      web.window.removeEventListener('message', _listener);
    }
    _events.close();
  }
}

class AvatarView extends StatelessWidget {
  final AvatarController controller;
  const AvatarView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      HtmlElementView(viewType: controller.viewType);
}
