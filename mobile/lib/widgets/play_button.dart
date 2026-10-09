import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../common.dart';

/// 🔊 語音試聽按鈕：向後端 /api/tts 取得 mp3 並播放，再點一次停止。
class PlayButton extends StatefulWidget {
  final String text;
  final bool compact;

  /// 指定朗讀聲音；未指定時使用右上角的全域設定。
  final String? voice;
  const PlayButton(
      {super.key, required this.text, this.compact = false, this.voice});

  @override
  State<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<PlayButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s == PlayerState.playing;
        if (_playing || s == PlayerState.completed) _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing || _loading) {
      await _player.stop();
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final url = ApiClient.instance
          .ttsUrl(widget.text, widget.voice ?? AppState.voice.value);
      await _player.play(UrlSource(url));
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showMessage(context, '無法播放語音，請確認網路連線後再試。');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(_playing ? Icons.stop_circle_outlined : Icons.volume_up_outlined);
    if (widget.compact) {
      return IconButton(
        tooltip: _playing ? '停止' : '播放語音',
        onPressed: _toggle,
        icon: icon,
      );
    }
    return TextButton.icon(
      onPressed: _toggle,
      icon: icon,
      label: Text(_playing ? '停止' : '播放語音'),
    );
  }
}
