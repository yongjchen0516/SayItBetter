import 'package:comm_assistant/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ScriptsResult 解析後端 JSON', () {
    final r = ScriptsResult.fromJson({
      'scripts': [
        {'style': '溫和委婉版', 'text': 'a'},
        {'style': '直接簡潔版', 'text': 'b'},
        {'style': '幽默圓場版', 'text': 'c'},
      ],
      'perspective': 'p',
      'pitfalls': [
        {'mine': 'm', 'why': 'w'}
      ],
      'tip': 't',
    });
    expect(r.scripts.length, 3);
    expect(r.pitfalls.first.mine, 'm');
    expect(r.tip, 't');
  });

  test('SimTurn 使用 snake_case 欄位', () {
    final t = SimTurn.fromJson({
      'strengths': 's',
      'improvements': 'i',
      'better_reply': 'b',
      'next_line': 'n',
    });
    expect(t.betterReply, 'b');
    expect(t.nextLine, 'n');
  });

  test('Template 容忍缺少的選填欄位', () {
    final t = Template.fromJson({
      'id': 1,
      'scenario': 's',
      'content': 'c',
      'style': null,
      'note': null,
      'channel': null,
      'created_at': null,
    });
    expect(t.style, '');
    expect(t.channel, '');
  });
}
