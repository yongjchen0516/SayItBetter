import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 三種話術風格各有一張小圓臉：溫和＝瞇眼微笑、直接＝堅定、幽默＝眨眼大笑。
enum Mood { gentle, direct, humor, neutral }

Mood moodForStyle(String style) {
  if (style.contains('溫和') || style.contains('委婉')) return Mood.gentle;
  if (style.contains('直接') || style.contains('簡潔')) return Mood.direct;
  if (style.contains('幽默') || style.contains('圓場')) return Mood.humor;
  return Mood.neutral;
}

Color moodColor(Mood m) => switch (m) {
      Mood.gentle => Palette.coral,
      Mood.direct => Palette.sky,
      Mood.humor => Palette.cream,
      Mood.neutral => Colors.white,
    };

Color moodSoftColor(Mood m) => switch (m) {
      Mood.gentle => Palette.coralSoft,
      Mood.direct => Palette.skySoft,
      Mood.humor => Palette.creamSoft,
      Mood.neutral => Colors.white,
    };

/// 手繪感的小圓臉（線條微微抖動，像用筆畫的）。
class MoodFace extends StatelessWidget {
  final Mood mood;
  final double size;
  const MoodFace({super.key, required this.mood, this.size = 44});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _FacePainter(mood)),
      );
}

class _FacePainter extends CustomPainter {
  final Mood mood;
  _FacePainter(this.mood);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final stroke = math.max(1.8, s * 0.06);
    final line = Paint()
      ..color = Palette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dot = Paint()..color = Palette.ink;
    Offset p(double x, double y) => c + Offset(x * s, y * s);

    // 臉：不太圓的圓（疊兩個不同頻率的抖動）
    final seed = mood.index * 1.7;
    final r = s * 0.44;
    final face = Path();
    const n = 40;
    for (var i = 0; i <= n; i++) {
      final t = i / n * 2 * math.pi;
      final k = 1 + 0.03 * math.sin(3 * t + seed) + 0.015 * math.sin(7 * t + seed * 2);
      final pt = c + Offset(math.cos(t), math.sin(t)) * r * k;
      i == 0 ? face.moveTo(pt.dx, pt.dy) : face.lineTo(pt.dx, pt.dy);
    }
    face.close();
    canvas.drawPath(face, Paint()..color = moodColor(mood));
    canvas.drawPath(face, line);

    // 腮紅
    if (mood != Mood.direct) {
      final blush = Paint()..color = const Color(0x99FF7A85);
      for (final x in [-0.25, 0.25]) {
        canvas.drawOval(Rect.fromCenter(center: p(x, 0.1), width: s * 0.14, height: s * 0.08), blush);
      }
    }

    switch (mood) {
      case Mood.gentle:
        // 瞇眼（∩）＋小微笑
        for (final x in [-0.16, 0.16]) {
          canvas.drawPath(
              Path()
                ..moveTo(p(x - 0.07, -0.02).dx, p(x - 0.07, -0.02).dy)
                ..quadraticBezierTo(p(x, -0.13).dx, p(x, -0.13).dy, p(x + 0.07, -0.02).dx, p(x + 0.07, -0.02).dy),
              line);
        }
        canvas.drawPath(
            Path()
              ..moveTo(p(-0.1, 0.13).dx, p(-0.1, 0.13).dy)
              ..quadraticBezierTo(p(0, 0.23).dx, p(0, 0.23).dy, p(0.1, 0.13).dx, p(0.1, 0.13).dy),
            line);
      case Mood.direct:
        // 圓點眼＋往內壓的眉毛＋自信的一字嘴
        for (final x in [-0.16, 0.16]) {
          canvas.drawCircle(p(x, -0.02), s * 0.045, dot);
        }
        canvas.drawLine(p(-0.26, -0.17), p(-0.09, -0.13), line);
        canvas.drawLine(p(0.26, -0.17), p(0.09, -0.13), line);
        canvas.drawPath(
            Path()
              ..moveTo(p(-0.11, 0.16).dx, p(-0.11, 0.16).dy)
              ..quadraticBezierTo(p(0, 0.2).dx, p(0, 0.2).dy, p(0.11, 0.15).dx, p(0.11, 0.15).dy),
            line);
      case Mood.humor:
        // 一眼眨眼（^）一眼圓點＋張口大笑
        canvas.drawCircle(p(-0.16, -0.03), s * 0.045, dot);
        canvas.drawPath(
            Path()
              ..moveTo(p(0.09, -0.01).dx, p(0.09, -0.01).dy)
              ..lineTo(p(0.16, -0.09).dx, p(0.16, -0.09).dy)
              ..lineTo(p(0.23, -0.01).dx, p(0.23, -0.01).dy),
            line);
        final mouth = Path()
          ..moveTo(p(-0.17, 0.08).dx, p(-0.17, 0.08).dy)
          ..quadraticBezierTo(p(0, 0.4).dx, p(0, 0.4).dy, p(0.17, 0.08).dx, p(0.17, 0.08).dy)
          ..close();
        canvas.drawPath(mouth, dot);
        canvas.save();
        canvas.clipPath(mouth);
        canvas.drawCircle(p(0.02, 0.27), s * 0.08, Paint()..color = Palette.coral);
        canvas.restore();
        canvas.drawPath(mouth, line);
      case Mood.neutral:
        for (final x in [-0.15, 0.15]) {
          canvas.drawCircle(p(x, -0.03), s * 0.04, dot);
        }
        canvas.drawPath(
            Path()
              ..moveTo(p(-0.09, 0.14).dx, p(-0.09, 0.14).dy)
              ..quadraticBezierTo(p(0, 0.2).dx, p(0, 0.2).dy, p(0.09, 0.14).dx, p(0.09, 0.14).dy),
            line);
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.mood != mood;
}

/// 貼紙感外框：粗描邊＋不模糊的硬陰影，可微微傾斜。
class Sticker extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double tilt; // 弧度
  const Sticker({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(top: 8, bottom: 12, right: 4),
    this.radius = 18,
    this.tilt = 0,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Palette.ink, width: kStroke),
        boxShadow: kStickerShadow,
      ),
      child: child,
    );
    return tilt == 0 ? box : Transform.rotate(angle: tilt, child: box);
  }
}

/// 小貼紙標籤（用在風格名稱、卡片標題）。
class StickerLabel extends StatelessWidget {
  final String text;
  final Color color;
  final double tilt;
  final Widget? leading;
  const StickerLabel(this.text,
      {super.key, this.color = Palette.cream, this.tilt = -0.03, this.leading});

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: tilt,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Palette.ink, width: 2),
            boxShadow: const [BoxShadow(color: Palette.ink, offset: Offset(2, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(text,
                style: const TextStyle(
                    color: Palette.ink, fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        ),
      );
}

/// 手繪小星星（裝飾用）。
class Sparkle extends StatelessWidget {
  final double size;
  final Color color;
  const Sparkle({super.key, this.size = 18, this.color = Palette.cream});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _SparklePainter(color)),
      );
}

class _SparklePainter extends CustomPainter {
  final Color color;
  _SparklePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.15, c.dy - r * 0.15, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.15, c.dy + r * 0.15, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.15, c.dy + r * 0.15, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.15, c.dy - r * 0.15, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = Palette.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.18)
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

/// 頁面頂部的打招呼橫幅：降低「要練習」的壓力。
class GreetingBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Mood> faces;
  final Color color;
  const GreetingBanner({
    super.key,
    required this.title,
    required this.subtitle,
    this.faces = const [Mood.gentle, Mood.direct, Mood.humor],
    this.color = Palette.creamSoft,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Sticker(
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: Palette.inkSoft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34.0 * faces.length + 14,
            height: 56,
            child: Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < faces.length; i++)
                Positioned(
                  left: i * 30.0,
                  top: i.isOdd ? 0 : 12,
                  child: Transform.rotate(
                    angle: (i - 1) * 0.15,
                    child: MoodFace(mood: faces[i], size: 42),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
