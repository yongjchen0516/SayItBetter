import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// 跨頁面共用的狀態。
class AppState {
  /// 目前選擇的朗讀聲音（後端的聲音名稱）。
  static final ValueNotifier<String> voice = ValueNotifier<String>('');

  /// 切換朗讀聲音並記住（下次開啟沿用）。
  static Future<void> setVoice(String v) async {
    voice.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voice', v);
    } catch (_) {}
  }

  /// 範本庫有變動時 +1，讓範本庫頁重新載入。
  static final ValueNotifier<int> templatesVersion = ValueNotifier<int>(0);

  /// 任何請求發現登入過期時設為 true，主畫面據此回到登入畫面。
  static final ValueNotifier<bool> loginExpired = ValueNotifier<bool>(false);
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 執行 API 動作，失敗時顯示訊息並回傳 null。
Future<T?> guarded<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } on LoginRequiredException catch (e) {
    AppState.loginExpired.value = true;
    if (context.mounted) showMessage(context, e.message);
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  } catch (e) {
    if (context.mounted) showMessage(context, '發生錯誤：$e');
  }
  return null;
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, '已複製');
}

/// 內容置中並限制最大寬度，手機滿版、電腦不會過寬。
class PageBody extends StatelessWidget {
  final Widget child;
  const PageBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: child,
        ),
      );
}
