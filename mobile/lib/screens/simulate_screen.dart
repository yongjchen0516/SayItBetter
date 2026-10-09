import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../common.dart';
import '../models.dart';
import '../widgets/avatar_view.dart';
import '../widgets/mic_button.dart';
import '../widgets/play_button.dart';
import '../widgets/scenario_picker.dart';

class _Entry {
  final String role; // 'user' | 'assistant'
  final String content;
  Coach? feedback; // 只有 user 的訊息會有點評（稍後非同步補上）
  _Entry(this.role, this.content);
}

class SimulateScreen extends StatefulWidget {
  final Meta meta;
  const SimulateScreen({super.key, required this.meta});

  @override
  State<SimulateScreen> createState() => _SimulateScreenState();
}

class _SimulateScreenState extends State<SimulateScreen> {
  // 設定階段
  final TextEditingController _background = TextEditingController();
  String _scenarioInput = '';
  late String _personaInput = widget.meta.personas.last;
  String _genderInput = 'female';
  bool _voiceSetup = true;

  // 演練階段
  bool _active = false;
  bool _busy = false;
  String _scenario = '';
  String _persona = '';
  String _gender = 'female';
  String _thoughts = '';
  final List<_Entry> _log = [];
  final TextEditingController _reply = TextEditingController();
  final ScrollController _scroll = ScrollController();

  // 語音通話（虛擬人物）
  bool _voiceMode = false;
  AvatarController? _avatar;
  StreamSubscription<Map<String, dynamic>>? _avatarSub;
  bool _sttAvailable = true;
  bool _listening = false;
  bool _speaking = false;
  String _caption = '';

  @override
  void dispose() {
    _disposeAvatar();
    _background.dispose();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 虛擬人物
  AvatarController _ensureAvatar() {
    var c = _avatar;
    if (c != null) return c;
    c = _avatar = AvatarController();
    _avatarSub = c.events.listen(_onAvatarEvent);
    return c;
  }

  void _disposeAvatar() {
    _avatarSub?.cancel();
    _avatarSub = null;
    _avatar?.dispose();
    _avatar = null;
    _listening = false;
    _speaking = false;
    _caption = '';
  }

  void _onAvatarEvent(Map<String, dynamic> m) {
    if (!mounted) return;
    switch (m['type']) {
      case 'transcript':
        final text = (m['text'] ?? '') as String;
        if (m['final'] == true) {
          setState(() => _caption = '');
          _submit(text);
        } else {
          setState(() => _caption = text);
        }
      case 'listening':
        setState(() => _listening = m['on'] == true);
      case 'sttError':
        final code = (m['code'] ?? '') as String;
        showMessage(context, (m['message'] ?? '語音辨識失敗') as String);
        setState(() {
          _listening = false;
          if (const {
            'unsupported',
            'not-allowed',
            'service-not-allowed',
            'audio-capture',
            'network',
            'language-not-supported',
          }.contains(code)) {
            _sttAvailable = false;
          }
        });
      case 'speakStart':
        setState(() => _speaking = true);
      case 'speakEnd':
        setState(() => _speaking = false);
        _listen();
      case 'speakError':
        showMessage(context, (m['message'] ?? '語音播放失敗') as String);
        setState(() => _speaking = false);
        _listen();
    }
  }

  /// 對方說完（或使用者送出訊息後）自動回到聆聽狀態，形成連續通話。
  void _listen() {
    if (!_active || !_voiceMode || !_sttAvailable) return;
    if (_busy || _speaking || _avatar == null) return;
    _avatar!.startListening();
  }

  void _toggleMic() {
    final a = _avatar;
    if (a == null) return;
    if (_listening) {
      a.stopListening();
    } else {
      a.stopSpeaking(); // 也可用來打斷對方說話
      setState(() => _speaking = false);
      a.startListening();
    }
  }

  Future<void> _toggleVoiceMode() async {
    if (_voiceMode) {
      setState(() {
        _voiceMode = false;
        _disposeAvatar();
      });
      return;
    }
    setState(() => _voiceMode = true);
    final c = _ensureAvatar();
    final stt = await c.ready
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    if (!mounted || _avatar != c) return;
    _sttAvailable = stt;
    c.setPersona(_persona, _gender);
    setState(() {});
  }

  /// 對方的聲音跟著角色性別（女→女聲、男→男聲）；找不到對應聲音時用全域設定。
  String get _partnerVoice {
    final key = _gender == 'male' ? '男' : '女';
    return widget.meta.voices.firstWhere((v) => v.startsWith(key),
        orElse: () => AppState.voice.value);
  }

  void _speakLine(String line, String emotion) {
    final a = _avatar;
    if (a == null) return;
    a.speak(ApiClient.instance.ttsUrl(line, _partnerVoice), emotion);
  }

  // ---------------------------------------------------------------- 流程
  Future<void> _start() async {
    if (_scenarioInput.isEmpty) {
      showMessage(context, '請先選擇或輸入場景。');
      return;
    }
    setState(() => _busy = true);
    final thoughts = _background.text.trim();
    final opening = await guarded(context,
        () => ApiClient.instance.simStart(_scenarioInput, thoughts, _personaInput,
            gender: _genderInput));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (opening != null) {
        _active = true;
        _scenario = _scenarioInput;
        _persona = _personaInput;
        _gender = _genderInput;
        _thoughts = thoughts;
        _log
          ..clear()
          ..add(_Entry('assistant', opening.line));
        _voiceMode = _voiceSetup;
      }
    });
    if (opening == null || !_voiceMode) return;

    final c = _ensureAvatar();
    final stt = await c.ready
        .timeout(const Duration(seconds: 10), onTimeout: () => false);
    if (!mounted || _avatar != c) return;
    _sttAvailable = stt;
    c.setPersona(_persona, _gender);
    _speakLine(opening.line, opening.emotion);
    setState(() {});
  }

  Future<void> _submit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy || !_active) return;
    _avatar?.stopSpeaking();
    _avatar?.stopListening();

    final history = [
      for (final e in _log) {'role': e.role, 'content': e.content},
    ];
    final entry = _Entry('user', text);
    setState(() {
      _busy = true;
      _speaking = false;
      _log.add(entry);
      _reply.clear();
    });
    _scrollToBottom();

    final api = ApiClient.instance;
    final replyFuture = api.simReply(
      scenario: _scenario,
      thoughts: _thoughts,
      persona: _persona,
      history: history,
      reply: text,
      gender: _gender,
    );
    final coachFuture = api.simCoach(
      scenario: _scenario,
      thoughts: _thoughts,
      persona: _persona,
      history: history,
      reply: text,
      gender: _gender,
    );

    // 點評不擋住對方開口：先掛上結果，晚到也沒關係
    unawaited(coachFuture.then((c) {
      if (!mounted) return;
      setState(() => entry.feedback = c);
      _scrollToBottom();
    }).catchError((Object e) {
      if (mounted) {
        showMessage(context, e is ApiException ? e.message : '教練點評暫時無法取得。');
      }
    }));

    final reply = await guarded(context, () => replyFuture);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (reply != null) {
        _log.add(_Entry('assistant', reply.line));
      } else {
        _log.remove(entry); // 失敗時還原，讓使用者可以重送
        _reply.text = text;
      }
    });
    _scrollToBottom();

    if (reply != null && _voiceMode) {
      _speakLine(reply.line, reply.emotion);
    } else {
      _listen();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _end() {
    setState(() {
      _active = false;
      _busy = false;
      _voiceMode = false;
      _disposeAvatar();
      _log.clear();
      _reply.clear();
    });
  }

  @override
  Widget build(BuildContext context) =>
      PageBody(child: _active ? _buildChat(context) : _buildSetup(context));

  // ---------------------------------------------------------------- 設定
  Widget _buildSetup(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ScenarioPicker(
          scenarios: widget.meta.scenarios,
          onChanged: (v) => _scenarioInput = v,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _personaInput,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '對方的性格／態度',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in widget.meta.personas)
              DropdownMenuItem(value: p, child: Text(p)),
          ],
          onChanged: (v) => setState(() => _personaInput = v ?? _personaInput),
        ),
        const SizedBox(height: 16),
        Text('對方的性別', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'female', label: Text('女生'), icon: Icon(Icons.face_3)),
            ButtonSegment(
                value: 'male', label: Text('男生'), icon: Icon(Icons.face)),
          ],
          selected: {_genderInput},
          onSelectionChanged: (s) => setState(() => _genderInput = s.first),
        ),
        const SizedBox(height: 4),
        Text('角色外觀、聲音與說話口吻都會跟著改變',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _background,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '你的背景／想法（選填）',
            helperText: '讓 AI 更貼近你的處境',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('語音通話（虛擬人物）'),
          subtitle: const Text('對方以 3D 角色出現並開口說話；電腦 Chrome 可直接用語音回答'),
          value: _voiceSetup,
          onChanged: (v) => setState(() => _voiceSetup = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _start,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(_busy ? '準備中…' : '開始演練'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 對話
  String get _statusText {
    if (_busy) return '對方思考中…';
    if (_speaking) return '對方說話中…（點麥克風可打斷）';
    if (_listening) return '聆聽中…請開始說話';
    if (_sttAvailable) return '點麥克風開始說話，或直接打字';
    return '此瀏覽器無法語音辨識，請直接打字（可用鍵盤的聽寫鍵）';
  }

  Widget _buildChat(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final avatarHeight = (box.maxHeight * 0.36).clamp(200.0, 320.0);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('$_scenario｜對方：$_persona',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: _voiceMode ? '關閉虛擬人物' : '開啟虛擬人物',
                  onPressed: _toggleVoiceMode,
                  icon: Icon(_voiceMode
                      ? Icons.face_retouching_natural
                      : Icons.face_retouching_off),
                ),
                TextButton.icon(
                  onPressed: _end,
                  icon: const Icon(Icons.call_end),
                  label: const Text('結束'),
                ),
              ],
            ),
          ),
          if (_voiceMode && _avatar != null) ...[
            SizedBox(
              height: avatarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AvatarView(controller: _avatar!),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Column(
                children: [
                  Text(_statusText,
                      style: theme.textTheme.labelLarge,
                      textAlign: TextAlign.center),
                  if (_caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('「$_caption」',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary),
                          textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ],
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              children: [
                for (final e in _log) ...[
                  _Bubble(entry: e, voice: _partnerVoice),
                  if (e.feedback != null) _FeedbackCard(coach: e.feedback!),
                ],
                if (_busy && !_voiceMode)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('對方思考中…'),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '輸入你的回覆…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_voiceMode && _avatar != null)
                    if (_sttAvailable)
                      IconButton.filledTonal(
                        tooltip: _listening ? '停止聆聽' : '說話',
                        onPressed: _toggleMic,
                        isSelected: _listening,
                        icon: const Icon(Icons.mic_none),
                        selectedIcon: const Icon(Icons.stop),
                      )
                    else
                      const SizedBox.shrink()
                  else
                    MicButton(onResult: (t) {
                      _reply.text = t;
                      _submit(t);
                    }),
                  IconButton.filled(
                    onPressed: _busy ? null : () => _submit(_reply.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _Bubble extends StatelessWidget {
  final _Entry entry;
  final String? voice; // 對方台詞的朗讀聲音
  const _Bubble({required this.entry, this.voice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = entry.role == 'user';
    final bg = mine
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final maxW = MediaQuery.of(context).size.width * 0.82;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        constraints: BoxConstraints(maxWidth: maxW > 560 ? 560 : maxW),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(entry.content, style: theme.textTheme.bodyLarge),
            if (!mine) PlayButton(text: entry.content, voice: voice),
            if (mine) const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final Coach coach;
  const _FeedbackCard({required this.coach});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.rate_review_outlined),
        title: const Text('教練點評'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            const TextSpan(
                text: '👍 優點：',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: coach.strengths),
          ])),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            const TextSpan(
                text: '🔧 可改善：',
                style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: coach.improvements),
          ])),
          const SizedBox(height: 6),
          const Text('✨ 更佳參考回覆',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(coach.betterReply),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => copyText(context, coach.betterReply),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('複製'),
              ),
              PlayButton(text: coach.betterReply),
            ],
          ),
        ],
      ),
    );
  }
}
