import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// 密碼錯誤或尚未輸入密碼（HTTP 401）。
class AuthException extends ApiException {
  AuthException() : super('密碼錯誤或尚未輸入密碼。');
}

/// 尚未用 Google 登入，或登入已過期（HTTP 401 且帶 X-Login-Required）。
class LoginRequiredException extends ApiException {
  LoginRequiredException() : super('登入已過期，請重新登入。');
}

/// 目前登入狀態：[enabled] 為後端是否啟用 Google 登入；[user] 為 null 表示未登入。
class AuthInfo {
  final bool enabled;
  final Map<String, dynamic>? user;
  AuthInfo(this.enabled, this.user);

  String get email => (user?['email'] ?? '') as String;
  String get name => (user?['name'] ?? '') as String;
}

/// 與 FastAPI 後端溝通。網頁版與後端同源，直接用目前網址；
/// 開發時若前後端不同埠，可用 --dart-define=API_BASE=http://localhost:8000 指定。
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String _baseOverride = String.fromEnvironment('API_BASE');

  final http.Client _client = http.Client();
  String password = '';

  String get base => _baseOverride.isNotEmpty ? _baseOverride : Uri.base.origin;

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$base/api$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['X-App-Password'] = password;
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      final streamed =
          await _client.send(req).timeout(const Duration(seconds: 90));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('連線逾時，請稍後再試。');
    } catch (_) {
      throw ApiException('無法連線到伺服器，請確認電腦已開啟，且手機與電腦在同一個 Wi-Fi。');
    }

    if (res.statusCode == 401) {
      if (res.headers['x-login-required'] == '1') throw LoginRequiredException();
      throw AuthException();
    }

    dynamic data;
    final text = utf8.decode(res.bodyBytes);
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = null;
      }
    }
    if (res.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      if (detail is String) throw ApiException(detail);
      if (res.statusCode == 422) throw ApiException('輸入內容不完整或格式不正確。');
      throw ApiException('請求失敗（${res.statusCode}）');
    }
    return data;
  }

  // ---- Google 登入 ----
  Future<AuthInfo> me() async {
    final j = await _request('GET', '/auth/me') as Map<String, dynamic>;
    return AuthInfo(j['enabled'] == true, j['user'] as Map<String, dynamic>?);
  }

  /// 登入是整頁導向後端，由後端轉到 Google，完成後再導回首頁。
  String get loginUrl => '$base/api/auth/login';

  Future<void> logout() => _request('POST', '/auth/logout');

  /// Google 只接受 localhost 或 HTTPS 網址登入（例如區網 IP 的 http 不行）。
  static bool get canLoginHere {
    final u = Uri.base;
    return u.scheme == 'https' || u.host == 'localhost' || u.host == '127.0.0.1';
  }

  // ---- 一般與 AI ----
  Future<Meta> meta() async =>
      Meta.fromJson(await _request('GET', '/meta') as Map<String, dynamic>);

  Future<ScriptsResult> scripts(
          String scenario, String thoughts, String channel) async =>
      ScriptsResult.fromJson(await _request('POST', '/scripts', body: {
        'scenario': scenario,
        'thoughts': thoughts,
        'channel': channel,
      }) as Map<String, dynamic>);

  Future<SimReply> simStart(
      String scenario, String thoughts, String persona,
      {String gender = ''}) async {
    final j = await _request('POST', '/sim/start', body: {
      'scenario': scenario,
      'thoughts': thoughts,
      'persona': persona,
      'gender': gender,
    }) as Map<String, dynamic>;
    return SimReply.fromJson(j);
  }

  Map<String, dynamic> _turnBody(
    String scenario,
    String thoughts,
    String persona,
    List<Map<String, String>> history,
    String reply,
    String gender,
  ) =>
      {
        'scenario': scenario,
        'thoughts': thoughts,
        'persona': persona,
        'history': history,
        'reply': reply,
        'gender': gender,
      };

  /// 只取得對方的下一句與情緒（語音通話先開口用）。
  Future<SimReply> simReply({
    required String scenario,
    required String thoughts,
    required String persona,
    required List<Map<String, String>> history,
    required String reply,
    String gender = '',
  }) async =>
      SimReply.fromJson(await _request('POST', '/sim/reply',
              body: _turnBody(scenario, thoughts, persona, history, reply, gender))
          as Map<String, dynamic>);

  /// 只取得對使用者最後一句話的點評，可與 [simReply] 平行呼叫。
  Future<Coach> simCoach({
    required String scenario,
    required String thoughts,
    required String persona,
    required List<Map<String, String>> history,
    required String reply,
    String gender = '',
  }) async =>
      Coach.fromJson(await _request('POST', '/sim/coach',
              body: _turnBody(scenario, thoughts, persona, history, reply, gender))
          as Map<String, dynamic>);

  Future<SimTurn> simTurn({
    required String scenario,
    required String thoughts,
    required String persona,
    required List<Map<String, String>> history,
    required String reply,
  }) async =>
      SimTurn.fromJson(await _request('POST', '/sim/turn', body: {
        'scenario': scenario,
        'thoughts': thoughts,
        'persona': persona,
        'history': history,
        'reply': reply,
      }) as Map<String, dynamic>);

  /// 語音播放用網址（播放器無法帶標頭，所以密碼放在 token 參數）。
  String ttsUrl(String text, String voice) =>
      Uri.parse('$base/api/tts').replace(queryParameters: {
        'text': text,
        if (voice.isNotEmpty) 'voice': voice,
        if (password.isNotEmpty) 'token': password,
      }).toString();

  // ---- 範本庫 ----
  Future<List<Template>> templates({String? scenario}) async {
    final data = await _request('GET', '/templates',
        query: scenario == null ? null : {'scenario': scenario}) as List;
    return data
        .map((e) => Template.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<String>> templateScenarios() async =>
      List<String>.from(await _request('GET', '/templates/scenarios') as List);

  Future<void> createTemplate({
    required String scenario,
    required String style,
    required String content,
    String note = '',
    String channel = '',
  }) =>
      _request('POST', '/templates', body: {
        'scenario': scenario,
        'style': style,
        'content': content,
        'note': note,
        'channel': channel,
      });

  Future<void> updateTemplate(
    int id, {
    required String scenario,
    required String style,
    required String content,
    required String note,
    required String channel,
  }) =>
      _request('PUT', '/templates/$id', body: {
        'scenario': scenario,
        'style': style,
        'content': content,
        'note': note,
        'channel': channel,
      });

  Future<void> deleteTemplate(int id) => _request('DELETE', '/templates/$id');

  Future<String> exportTemplates() async {
    final data = await _request('GET', '/templates/export');
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 回傳實際新增的筆數。
  Future<int> importTemplates(List<dynamic> rows) async {
    final j = await _request('POST', '/templates/import',
        body: {'templates': rows}) as Map<String, dynamic>;
    return j['added'] as int;
  }
}
