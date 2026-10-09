import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'api_client.dart';
import 'common.dart';
import 'models.dart';
import 'screens/generate_screen.dart';
import 'screens/library_screen.dart';
import 'screens/simulate_screen.dart';

void main() => runApp(const CommApp());

class CommApp extends StatelessWidget {
  const CommApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Say It Better',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const AppGate(),
      );
}

/// 啟動時載入已存的密碼並向後端取得選單資料；需要密碼時顯示輸入畫面。
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  static const String _pwKey = 'app_password';
  static const String _voiceKey = 'voice';

  Meta? _meta;
  AuthInfo? _auth;
  String? _error; // 連線失敗訊息
  bool _needPassword = false;
  bool _loading = true;
  String? _passwordError;
  final TextEditingController _pw = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppState.loginExpired.addListener(_onLoginExpired);
    _boot();
  }

  @override
  void dispose() {
    AppState.loginExpired.removeListener(_onLoginExpired);
    _pw.dispose();
    super.dispose();
  }

  /// 使用中發現登入過期：重新檢查登入狀態（會回到登入畫面）。
  void _onLoginExpired() {
    if (!AppState.loginExpired.value) return;
    AppState.loginExpired.value = false;
    _connect();
  }

  Future<void> _logout() async {
    await guarded(context, ApiClient.instance.logout);
    await _connect();
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // 無痕模式等情況讀不到也不影響使用
    }
  }

  Future<void> _boot() async {
    final prefs = await _prefs();
    ApiClient.instance.password = prefs?.getString(_pwKey) ?? '';
    final savedVoice = prefs?.getString(_voiceKey) ?? '';
    await _connect(savedVoice: savedVoice);
  }

  Future<void> _connect({String savedVoice = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final meta = await ApiClient.instance.meta();
      final auth = await ApiClient.instance.me();
      final current = AppState.voice.value;
      final wanted = savedVoice.isNotEmpty ? savedVoice : current;
      AppState.voice.value =
          meta.voices.contains(wanted) ? wanted : meta.voices.first;
      final prefs = await _prefs();
      await prefs?.setString(_pwKey, ApiClient.instance.password);
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _auth = auth;
        _needPassword = false;
        _passwordError = null;
        _loading = false;
      });
    } on AuthException {
      if (!mounted) return;
      setState(() {
        _needPassword = true;
        _passwordError = ApiClient.instance.password.isEmpty ? null : '密碼錯誤，請再試一次。';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _submitPassword() async {
    ApiClient.instance.password = _pw.text.trim();
    await _connect();
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    if (_meta != null && auth != null && !_loading) {
      if (auth.enabled && auth.user == null) return const LoginScreen();
      return HomeShell(
        // 換帳號時整個主畫面重建，不會殘留上一位使用者的畫面資料
        key: ValueKey(auth.user?['sub']),
        meta: _meta!,
        auth: auth,
        onLogout: _logout,
      );
    }

    Widget body;
    if (_loading) {
      body = const CircularProgressIndicator();
    } else if (_needPassword) {
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('請輸入存取密碼', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _pw,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _submitPassword(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '密碼',
                errorText: _passwordError,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _submitPassword, child: const Text('進入')),
          ],
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? '無法連線', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _connect, child: const Text('重試')),
          ],
        ),
      );
    }
    return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: body)));
  }
}

/// 未登入時的畫面：整頁導向後端開始 Google 登入。
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canLogin = ApiClient.canLoginHere;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum_outlined, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Say It Better',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                Text('生活人際溝通輔助系統',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text('說出口之前，先練習一次。\n登入後，你的話術範本只有你自己看得到。',
                    style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                if (canLogin)
                  FilledButton.icon(
                    onPressed: () =>
                        web.window.location.href = ApiClient.instance.loginUrl,
                    icon: const Icon(Icons.login),
                    label: const Text('使用 Google 登入'),
                  )
                else
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '這個網址無法使用 Google 登入。\n'
                        'Google 只允許在 localhost 或 HTTPS 網址登入，'
                        '請在電腦上用 http://localhost:8000 開啟。手機要登入需要先部署成 HTTPS 網址。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final Meta meta;
  final AuthInfo auth;
  final Future<void> Function() onLogout;
  const HomeShell(
      {super.key, required this.meta, required this.auth, required this.onLogout});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['話術生成', '對話演練', '話術範本庫'];

  Future<void> _pickVoice() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('朗讀聲音', style: TextStyle(fontSize: 18)),
            ),
            for (final v in widget.meta.voices)
              ListTile(
                title: Text(v),
                trailing: v == AppState.voice.value
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    AppState.voice.value = chosen;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voice', chosen);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: '朗讀聲音',
            onPressed: _pickVoice,
            icon: const Icon(Icons.record_voice_over_outlined),
          ),
          if (widget.auth.enabled)
            PopupMenuButton<String>(
              tooltip: '帳號',
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (v) {
                if (v == 'logout') widget.onLogout();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.auth.name.isNotEmpty) Text(widget.auth.name),
                      Text(widget.auth.email,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout),
                    title: Text('登出'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          GenerateScreen(meta: widget.meta),
          SimulateScreen(meta: widget.meta),
          const LibraryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: '話術'),
          NavigationDestination(
              icon: Icon(Icons.theater_comedy_outlined),
              selectedIcon: Icon(Icons.theater_comedy),
              label: '演練'),
          NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks),
              label: '範本庫'),
        ],
      ),
    );
  }
}
