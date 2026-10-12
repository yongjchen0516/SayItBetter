import 'package:flutter/material.dart';

import '../api_client.dart';
import '../common.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/doodles.dart';
import '../widgets/mic_button.dart';
import '../widgets/scenario_picker.dart';
import '../widgets/script_card.dart';

class GenerateScreen extends StatefulWidget {
  final Meta meta;
  const GenerateScreen({super.key, required this.meta});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final TextEditingController _thoughts = TextEditingController();
  String _scenario = '';
  late String _channel = widget.meta.channels.first;
  bool _busy = false;

  // 產生結果當下的情境與管道（之後使用者改動表單不影響已顯示的結果）
  ScriptsResult? _result;
  String _resultScenario = '';
  String _resultChannel = '';

  @override
  void dispose() {
    _thoughts.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final thoughts = _thoughts.text.trim();
    if (_scenario.isEmpty || thoughts.isEmpty) {
      showMessage(context, '請先選擇／輸入情境，並寫下你的內心想法。');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final r = await guarded(
        context, () => ApiClient.instance.scripts(_scenario, thoughts, _channel));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) {
        _result = r;
        _resultScenario = _scenario;
        _resultChannel = _channel;
      }
    });
  }

  Future<void> _save(Script s) async {
    final ok = await guarded(
      context,
      () async {
        await ApiClient.instance.createTemplate(
          scenario: _resultScenario,
          style: s.style,
          content: s.text,
          channel: _resultChannel,
        );
        return true;
      },
    );
    if (ok == true && mounted) {
      AppState.templatesVersion.value++;
      showMessage(context, '已儲存至範本庫');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const GreetingBanner(
            title: '想說的話，交給我們整理 ✨',
            subtitle: '寫下心裡話就好，會幫你變成溫和、直接、幽默三種說法。',
          ),
          const SizedBox(height: 8),
          ScenarioPicker(
            scenarios: widget.meta.scenarios,
            onChanged: (v) => _scenario = v,
          ),
          const SizedBox(height: 16),
          Text('溝通管道', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              for (final c in widget.meta.channels)
                ButtonSegment(value: c, label: Text(c)),
            ],
            selected: {_channel},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('內心真實想法', style: theme.textTheme.labelLarge),
              ),
              MicButton(
                onResult: (t) {
                  final cur = _thoughts.text.trim();
                  _thoughts.text = cur.isEmpty ? t : '$cur $t';
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _thoughts,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '例如：同事一直約我週末聚餐，但我只想在家休息，又不想傷感情……',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'AI 思考中…' : '生成話術'),
          ),
          if (result != null) ...[
            const SizedBox(height: 28),
            Row(children: [
              const Sparkle(size: 20, color: Palette.coral),
              const SizedBox(width: 8),
              Expanded(
                child: Text('情境：$_resultScenario（$_resultChannel）',
                    style: theme.textTheme.titleMedium),
              ),
            ]),
            const SizedBox(height: 8),
            for (final s in result.scripts)
              ScriptCard(
                style: s.style,
                text: s.text,
                onSave: () => _save(s),
              ),
            const SizedBox(height: 8),
            _InfoCard(
              emoji: '🔄',
              title: '換位思考',
              color: Palette.skySoft,
              child: Text(result.perspective),
            ),
            _InfoCard(
              emoji: '💣',
              title: '溝通地雷',
              color: Palette.coralSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in result.pitfalls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '${p.mine}：',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: p.why),
                      ])),
                    ),
                ],
              ),
            ),
            _InfoCard(
              emoji: '💡',
              title: '溝通小技巧',
              color: Palette.creamSoft,
              child: Text(result.tip),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String emoji;
  final String title;
  final Color color;
  final Widget child;
  const _InfoCard(
      {required this.emoji,
      required this.title,
      required this.color,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Sticker(
      color: color,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StickerLabel('$emoji $title', color: Colors.white),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
