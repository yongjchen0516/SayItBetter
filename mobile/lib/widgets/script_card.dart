import 'package:flutter/material.dart';

import '../common.dart';
import 'play_button.dart';

/// 單一風格的話術卡片：可複製、播放語音、（選用）儲存至範本庫。
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(style,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
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
      ),
    );
  }
}
