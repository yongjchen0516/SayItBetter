// 後端 JSON 對應的資料模型。

class Meta {
  final List<String> scenarios;
  final List<String> channels;
  final List<String> personas;
  final List<String> voices;

  Meta({
    required this.scenarios,
    required this.channels,
    required this.personas,
    required this.voices,
  });

  factory Meta.fromJson(Map<String, dynamic> j) => Meta(
        scenarios: List<String>.from(j['scenarios']),
        channels: List<String>.from(j['channels']),
        personas: List<String>.from(j['personas']),
        voices: List<String>.from(j['voices']),
      );
}

class Script {
  final String style;
  final String text;
  Script({required this.style, required this.text});

  factory Script.fromJson(Map<String, dynamic> j) =>
      Script(style: j['style'] as String, text: j['text'] as String);
}

class Pitfall {
  final String mine;
  final String why;
  Pitfall({required this.mine, required this.why});

  factory Pitfall.fromJson(Map<String, dynamic> j) =>
      Pitfall(mine: j['mine'] as String, why: j['why'] as String);
}

class ScriptsResult {
  final List<Script> scripts;
  final String perspective;
  final List<Pitfall> pitfalls;
  final String tip;

  ScriptsResult({
    required this.scripts,
    required this.perspective,
    required this.pitfalls,
    required this.tip,
  });

  factory ScriptsResult.fromJson(Map<String, dynamic> j) => ScriptsResult(
        scripts: (j['scripts'] as List)
            .map((e) => Script.fromJson(e as Map<String, dynamic>))
            .toList(),
        perspective: j['perspective'] as String,
        pitfalls: (j['pitfalls'] as List)
            .map((e) => Pitfall.fromJson(e as Map<String, dynamic>))
            .toList(),
        tip: j['tip'] as String,
      );
}

/// 教練對使用者最後一句話的點評。
class Coach {
  final String strengths;
  final String improvements;
  final String betterReply;

  Coach({
    required this.strengths,
    required this.improvements,
    required this.betterReply,
  });

  factory Coach.fromJson(Map<String, dynamic> j) => Coach(
        strengths: j['strengths'] as String,
        improvements: j['improvements'] as String,
        betterReply: j['better_reply'] as String,
      );
}

/// 對方的一句台詞與當下情緒（情緒用來決定虛擬人物的表情）。
class SimReply {
  final String line;
  final String emotion;
  SimReply({required this.line, required this.emotion});

  factory SimReply.fromJson(Map<String, dynamic> j) => SimReply(
        line: (j['next_line'] ?? j['line']) as String,
        emotion: (j['emotion'] ?? 'neutral') as String,
      );
}

/// 演練中教練對使用者回覆的點評，同時帶有對方的下一句台詞。
class SimTurn {
  final String strengths;
  final String improvements;
  final String betterReply;
  final String nextLine;

  SimTurn({
    required this.strengths,
    required this.improvements,
    required this.betterReply,
    required this.nextLine,
  });

  factory SimTurn.fromJson(Map<String, dynamic> j) => SimTurn(
        strengths: j['strengths'] as String,
        improvements: j['improvements'] as String,
        betterReply: j['better_reply'] as String,
        nextLine: j['next_line'] as String,
      );
}

class Template {
  final int id;
  final String scenario;
  final String style;
  final String content;
  final String note;
  final String channel;
  final String createdAt;

  Template({
    required this.id,
    required this.scenario,
    required this.style,
    required this.content,
    required this.note,
    required this.channel,
    required this.createdAt,
  });

  factory Template.fromJson(Map<String, dynamic> j) => Template(
        id: j['id'] as int,
        scenario: j['scenario'] as String,
        style: (j['style'] ?? '') as String,
        content: j['content'] as String,
        note: (j['note'] ?? '') as String,
        channel: (j['channel'] ?? '') as String,
        createdAt: (j['created_at'] ?? '') as String,
      );
}
