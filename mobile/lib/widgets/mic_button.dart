import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 🎙️ 語音輸入按鈕。瀏覽器／裝置不支援（例如 iPhone 在 http 連線下）時整個隱藏，
/// 使用者改用手機鍵盤的聽寫功能即可。
class MicButton extends StatefulWidget {
  /// 辨識完成後以最終文字呼叫。
  final void Function(String text) onResult;
  const MicButton({super.key, required this.onResult});

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> {
  final SpeechToText _stt = SpeechToText();
  bool _available = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ok = await _stt
          .initialize(
            onStatus: (s) {
              if (!mounted) return;
              if (s == 'done' || s == 'notListening') {
                setState(() => _listening = false);
              }
            },
            onError: (_) {
              if (mounted) setState(() => _listening = false);
            },
          )
          .timeout(const Duration(seconds: 3));
      if (mounted) setState(() => _available = ok);
    } catch (_) {
      if (mounted) setState(() => _available = false);
    }
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      listenOptions: SpeechListenOptions(localeId: kIsWeb ? 'zh-TW' : 'zh_TW'),
      onResult: (r) {
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          widget.onResult(r.recognizedWords.trim());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    return IconButton.filledTonal(
      tooltip: _listening ? '停止錄音' : '語音輸入',
      onPressed: _toggle,
      isSelected: _listening,
      icon: const Icon(Icons.mic_none),
      selectedIcon: const Icon(Icons.stop),
    );
  }
}
