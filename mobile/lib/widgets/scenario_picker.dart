import 'package:flutter/material.dart';

const String customScenarioLabel = '✏️ 自訂場景…';

/// 預設場景下拉選單，選到「自訂」時出現文字框。
/// 目前有效的場景文字（自訂但未輸入時為空字串）透過 [onChanged] 回報。
class ScenarioPicker extends StatefulWidget {
  final List<String> scenarios;
  final ValueChanged<String> onChanged;
  const ScenarioPicker(
      {super.key, required this.scenarios, required this.onChanged});

  @override
  State<ScenarioPicker> createState() => _ScenarioPickerState();
}

class _ScenarioPickerState extends State<ScenarioPicker> {
  late String _choice = widget.scenarios.first;
  final TextEditingController _custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _emit() =>
      widget.onChanged(_choice == customScenarioLabel ? _custom.text.trim() : _choice);

  @override
  Widget build(BuildContext context) {
    final items = [...widget.scenarios, customScenarioLabel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _choice,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '溝通情境',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final s in items) DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _choice = v);
            _emit();
          },
        ),
        if (_choice == customScenarioLabel) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _custom,
            decoration: const InputDecoration(
              labelText: '請描述你的自訂場景',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
        ],
      ],
    );
  }
}
