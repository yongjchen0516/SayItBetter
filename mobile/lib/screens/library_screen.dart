import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../common.dart';
import '../models.dart';
import '../widgets/play_button.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const String _all = '全部';

  List<Template> _items = [];
  List<String> _scenarios = [];
  String _filter = _all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppState.templatesVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.templatesVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final api = ApiClient.instance;
    final data = await guarded(context, () async {
      final scenarios = await api.templateScenarios();
      // 篩選的場景若已不存在（例如最後一筆被刪除），退回「全部」
      final filter = scenarios.contains(_filter) ? _filter : _all;
      final items =
          await api.templates(scenario: filter == _all ? null : filter);
      return (scenarios, filter, items);
    });
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data != null) {
        _scenarios = data.$1;
        _filter = data.$2;
        _items = data.$3;
      }
    });
  }

  Future<void> _delete(Template t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除範本'),
        content: const Text('確定要刪除這筆範本嗎？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('刪除')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await guarded(context, () async {
      await ApiClient.instance.deleteTemplate(t.id);
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _edit(Template t) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditSheet(template: t),
    );
    if (saved == true) await _load();
  }

  Future<void> _export() async {
    final json = await guarded(context, ApiClient.instance.exportTemplates);
    if (json == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('匯出範本（JSON）'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
          FilledButton(
            onPressed: () => copyText(ctx, json),
            child: const Text('複製全部'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('匯入範本'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '貼上先前匯出的 JSON',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('匯入')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;

    List<dynamic> rows;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) throw const FormatException();
      rows = decoded;
    } catch (_) {
      showMessage(context, 'JSON 格式不正確，請貼上完整的匯出內容。');
      return;
    }
    final added =
        await guarded(context, () => ApiClient.instance.importTemplates(rows));
    if (added != null && mounted) {
      showMessage(context, '已匯入 $added 筆（重複的會自動略過）');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_filter),
                    initialValue: _filter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '依場景篩選',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final s in [_all, ..._scenarios])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) {
                      setState(() => _filter = v ?? _all);
                      _load();
                    },
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '備份',
                  onSelected: (v) => v == 'export' ? _export() : _import(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'export', child: Text('匯出範本')),
                    PopupMenuItem(value: 'import', child: Text('匯入範本')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('目前沒有範本。\n到「話術」頁儲存你喜歡的話術吧！',
                        textAlign: TextAlign.center))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final t = _items[i];
                            final meta = [t.scenario, t.channel, t.style]
                                .where((e) => e.isNotEmpty)
                                .join(' ・ ');
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(meta,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold)),
                                    Text(t.createdAt,
                                        style: theme.textTheme.bodySmall),
                                    const SizedBox(height: 8),
                                    SelectableText(t.content),
                                    if (t.note.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('備註：${t.note}',
                                          style: theme.textTheme.bodySmall),
                                    ],
                                    Wrap(
                                      spacing: 4,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () =>
                                              copyText(context, t.content),
                                          icon: const Icon(Icons.copy_outlined),
                                          label: const Text('複製'),
                                        ),
                                        PlayButton(text: t.content),
                                        TextButton.icon(
                                          onPressed: () => _edit(t),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('編輯'),
                                        ),
                                        TextButton.icon(
                                          onPressed: () => _delete(t),
                                          icon: const Icon(
                                              Icons.delete_outline),
                                          label: const Text('刪除'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  final Template template;
  const _EditSheet({required this.template});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _scenario =
      TextEditingController(text: widget.template.scenario);
  late final TextEditingController _style =
      TextEditingController(text: widget.template.style);
  late final TextEditingController _channel =
      TextEditingController(text: widget.template.channel);
  late final TextEditingController _content =
      TextEditingController(text: widget.template.content);
  late final TextEditingController _note =
      TextEditingController(text: widget.template.note);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_scenario, _style, _channel, _content, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_scenario.text.trim().isEmpty || _content.text.trim().isEmpty) {
      showMessage(context, '場景與話術內容不可為空。');
      return;
    }
    setState(() => _saving = true);
    final ok = await guarded(context, () async {
      await ApiClient.instance.updateTemplate(
        widget.template.id,
        scenario: _scenario.text.trim(),
        style: _style.text.trim(),
        content: _content.text.trim(),
        note: _note.text.trim(),
        channel: _channel.text.trim(),
      );
      return true;
    });
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController c, {int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 4,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('編輯範本', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _field('場景', _scenario),
            _field('風格', _style),
            _field('溝通管道', _channel),
            _field('話術內容', _content, lines: 4),
            _field('備註', _note),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '儲存中…' : '儲存修改'),
            ),
          ],
        ),
      ),
    );
  }
}
