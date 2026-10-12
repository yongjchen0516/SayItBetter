import 'package:flutter/material.dart';

import '../common.dart';
import 'doodles.dart';
import 'play_button.dart';

/// 單一風格的話術卡片：可複製、播放語音、（選用）儲存至範本庫。
/// 卡片左上角是代表這個風格的小圓臉與貼紙標籤。
class ScriptCard extends StatelessWidget {
  final String style;
  final String text;
  final VoidCallback? onSave;

  const ScriptCard({
    super.key,
    required this.style,
    required this.text,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = moodForStyle(style);
    return Sticker(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MoodFace(mood: mood, size: 40),
              const SizedBox(width: 10),
              StickerLabel(style, color: moodColor(mood)),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(text, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => copyText(context, text),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('複製'),
              ),
              PlayButton(text: text),
              if (onSave != null)
                TextButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('儲存'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
