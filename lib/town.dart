// Bản đồ phố: các quán nằm dọc đường, có sông, cầu, xe chạy, người đi bộ, mây bay.
// Chạm vào một quán để chọn quán muốn chơi (hoặc mua quán mới).
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'data.dart';
import 'scene.dart' show drawPerson, Look;

class _Spot {
  final String id;
  final Offset pos; // vị trí tương đối 0..1
  final Color wall, roof, awning;
  const _Spot(this.id, this.pos, this.wall, this.roof, this.awning);
}

const _spots = [
  _Spot('cafe', Offset(0.27, 0.40), Color(0xFFF3E1C7), Color(0xFF8D5B3C), Color(0xFFE6A15A)),
  _Spot('bakery', Offset(0.73, 0.40), Color(0xFFFFE4EC), Color(0xFFB0577A), Color(0xFFFF80AB)),
  _Spot('chinese', Offset(0.17, 0.80), Color(0xFFFFF1D6), Color(0xFFB71C1C), Color(0xFFFFC107)),
  _Spot('mexican', Offset(0.83, 0.80), Color(0xFFFFE7CF), Color(0xFF1E8A8A), Color(0xFFFF7043)),
  _Spot('truck', Offset(0.50, 0.81), Color(0xFFFFFFFF), Color(0xFFFFC107), Color(0xFFFF5722)),
];

class TownMap extends StatefulWidget {
  final Set<String> owned;
  final String current;
  final bool night;
  final void Function(String venueId) onTap;
  const TownMap({super.key, required this.owned, required this.current, required this.onTap, this.night = false});
  @override
  State<TownMap> createState() => _TownMapState();
}

class _TownMapState extends State<TownMap> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final Map<String, Rect> _hit = {};
  String? _pressed;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _clock.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  String? _at(Offset p) {
    for (final e in _hit.entries) {
      if (e.value.contains(p)) return e.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pressed = _at(d.localPosition),
        onTapCancel: () => _pressed = null,
        onTapUp: (d) {
          final id = _at(d.localPosition);
          _pressed = null;
          if (id != null) widget.onTap(id);
        },
        child: SizedBox.expand(child: CustomPaint(painter: _TownPainter(this))),
      );

  // ------------------------------------------------------------------ vẽ
  void _paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    if (w < 50 || h < 50) return;
    final t = _clock.value;
    final unit = min(w, h * 0.75);

    // Cỏ
    final bg = Rect.fromLTWH(0, 0, w, h);
    c.drawRect(
      bg,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFB8E3A1), Color(0xFF8ED081)]).createShader(bg),
    );
    final tuft = Paint()..color = const Color(0x2A2E7D32);
    final rr = Random(5);
    for (var k = 0; k < 70; k++) {
      c.drawCircle(Offset(rr.nextDouble() * w, rr.nextDouble() * h), 2 + rr.nextDouble() * 3, tuft);
    }

    // Sông + cầu
    final river = Path()..moveTo(0, h * 0.505);
    for (double x = 0; x <= w; x += 8) {
      river.lineTo(x, h * 0.505 + sin(x / w * pi * 2) * h * 0.02);
    }
    for (double x = w; x >= 0; x -= 8) {
      river.lineTo(x, h * 0.565 + sin(x / w * pi * 2 + 0.5) * h * 0.02);
    }
    river.close();
    c.drawPath(river, Paint()..color = const Color(0xFF6EC6F0));
    final wave = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 9; k++) {
      final x = (k * w / 8 + t * 18) % (w + 30) - 15;
      final y = h * 0.535 + sin(x / w * pi * 2 + 0.25) * h * 0.02;
      c.drawLine(Offset(x, y), Offset(x + 12, y), wave);
    }

    // Đường: một đại lộ dọc + hai phố ngang
    final road = Paint()..color = const Color(0xFF5E6472);
    final edge = Paint()..color = const Color(0xFFD9D4C7);
    final rw = unit * 0.085;
    void hRoad(double y) {
      c.drawRect(Rect.fromLTWH(0, y - rw / 2 - 3, w, rw + 6), edge);
      c.drawRect(Rect.fromLTWH(0, y - rw / 2, w, rw), road);
      for (double x = 6; x < w; x += 26) {
        c.drawRect(Rect.fromLTWH(x, y - 1.5, 13, 3), Paint()..color = const Color(0xFFFFE082));
      }
    }

    void vRoad(double x) {
      c.drawRect(Rect.fromLTWH(x - rw / 2 - 3, 0, rw + 6, h), edge);
      c.drawRect(Rect.fromLTWH(x - rw / 2, 0, rw, h), road);
      for (double y = 6; y < h; y += 26) {
        c.drawRect(Rect.fromLTWH(x - 1.5, y, 3, 13), Paint()..color = const Color(0xFFFFE082));
      }
    }

    final y1 = h * 0.12, y2 = h * 0.93, x1 = w * 0.5;
    vRoad(x1);
    hRoad(y1);
    hRoad(y2);
    // cầu qua sông
    final br = Rect.fromCenter(center: Offset(x1, h * 0.535), width: rw + 22, height: h * 0.1);
    c.drawRRect(RRect.fromRectAndRadius(br, const Radius.circular(4)), Paint()..color = const Color(0xFFA1887F));
    c.drawRect(Rect.fromCenter(center: br.center, width: rw, height: br.height), road);
    for (final sx in [br.left + 3, br.right - 3]) {
      c.drawLine(Offset(sx, br.top), Offset(sx, br.bottom), Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = 4);
    }

    // Cây
    final tr = Random(11);
    for (var k = 0; k < 16; k++) {
      final p = Offset(tr.nextDouble() * w, tr.nextDouble() * h);
      if ((p.dx - x1).abs() < rw * 1.2 || (p.dy - y1).abs() < rw || (p.dy - y2).abs() < rw || (p.dy - h * 0.535).abs() < h * 0.05) continue;
      if (_spots.any((s) => (Offset(s.pos.dx * w, s.pos.dy * h) - p).distance < unit * 0.2)) continue;
      _tree(c, p, unit * (0.035 + tr.nextDouble() * 0.02), t + k);
    }

    // Xe chạy trên đường
    for (var k = 0; k < 3; k++) {
      final dir = k.isEven ? 1.0 : -1.0;
      final yy = (k == 2 ? y2 : y1) + dir * rw * 0.22;
      final xx = dir > 0 ? (t * 55 + k * 160) % (w + 80) - 40 : w + 40 - (t * 48 + k * 130) % (w + 80);
      _car(c, Offset(xx, yy), unit * 0.06, dir, const [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFDD835)][k]);
    }
    final yy = (t * 40) % (h + 80) - 40;
    _carV(c, Offset(x1 + rw * 0.22, yy), unit * 0.06, const Color(0xFF8E24AA));

    // Quán
    _hit.clear();
    final sorted = [..._spots]..sort((a, b) => a.pos.dy.compareTo(b.pos.dy));
    for (final s in sorted) {
      final p = Offset(s.pos.dx * w, s.pos.dy * h);
      final bs = unit * 0.25;
      final own = widget.owned.contains(s.id);
      final cur = widget.current == s.id;
      final press = _pressed == s.id ? 0.94 : 1.0;
      _hit[s.id] = Rect.fromCenter(center: p - Offset(0, bs * 0.25), width: bs * 1.5, height: bs * 1.5);
      c.save();
      c.translate(p.dx, p.dy);
      c.scale(press);
      if (s.id == 'truck') {
        _truck(c, bs, s, own, t);
      } else {
        _shop(c, bs, s, own, cur, t);
      }
      c.restore();
      final v = venueById(s.id);
      _label(c, p + Offset(0, bs * 0.42), own ? '${v.emoji} ${v.name}' : '🔒 ${v.name}', own ? Colors.white : const Color(0xFFF2F2F2), own ? const Color(0xFF221B3F) : const Color(0xFF6E6E80), unit);
      if (!own) _label(c, p + Offset(0, bs * 0.42 + unit * 0.06), '💰 ${v.cost}', const Color(0xFFFFC23D), const Color(0xFF5A3B00), unit * 0.9);
      if (cur) {
        final bob = sin(t * 4).abs() * unit * 0.02;
        final pin = p - Offset(0, bs * 0.95 + bob);
        c.drawCircle(p - Offset(0, bs * 0.15), bs * (0.75 + 0.06 * sin(t * 3)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0x99FFFFFF));
        _pinMark(c, pin, unit * 0.05);
      }
    }

    // Người đi bộ trên vỉa hè
    for (var k = 0; k < 4; k++) {
      final dir = k.isEven ? 1.0 : -1.0;
      final roadY = k < 2 ? y1 : y2;
      final py = roadY + dir * (rw / 2 + 6) + (dir > 0 ? 8 : 0);
      final px = dir > 0 ? (t * 16 + k * 97) % (w + 40) - 20 : w + 20 - (t * 14 + k * 83) % (w + 40);
      drawPerson(c, Offset(px, py), unit * 0.07, Look.seed(k * 31 + 7), walking: true, phase: t * 10 + k, facingLeft: dir < 0);
    }

    // Mây
    for (var k = 0; k < 3; k++) {
      final cx = (t * (8 + k * 3) + k * w / 3) % (w + 120) - 60;
      _cloud(c, Offset(cx, h * (0.06 + 0.1 * k)), unit * (0.07 + 0.02 * k));
    }

    if (widget.night) {
      c.drawRect(bg, Paint()..color = const Color(0x55101040));
    }
  }

  void _tree(Canvas c, Offset p, double r, double t) {
    c.drawOval(Rect.fromCenter(center: p + Offset(0, r * 0.9), width: r * 1.8, height: r * 0.5), Paint()..color = const Color(0x22000000));
    c.drawRect(Rect.fromCenter(center: p + Offset(0, r * 0.55), width: r * 0.3, height: r * 0.8), Paint()..color = const Color(0xFF795548));
    final sway = sin(t * 1.3) * r * 0.05;
    c.drawCircle(p + Offset(sway, 0), r, Paint()..color = const Color(0xFF43A047));
    c.drawCircle(p + Offset(-r * 0.35 + sway, -r * 0.3), r * 0.55, Paint()..color = const Color(0xFF66BB6A));
  }

  void _car(Canvas c, Offset p, double s, double dir, Color col) {
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(dir, 1);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 1.6, height: s * 0.7), Radius.circular(s * 0.2)), Paint()..color = col);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s * 0.1, 0), width: s * 0.7, height: s * 0.55), Radius.circular(s * 0.12)), Paint()..color = const Color(0xFFB3E5FC));
    c.drawCircle(Offset(s * 0.78, -s * 0.22), s * 0.08, Paint()..color = const Color(0xFFFFF59D));
    c.drawCircle(Offset(s * 0.78, s * 0.22), s * 0.08, Paint()..color = const Color(0xFFFFF59D));
    c.restore();
  }

  void _carV(Canvas c, Offset p, double s, Color col) {
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(pi / 2);
    _car(c, Offset.zero, s, 1, col);
    c.restore();
  }

  void _cloud(Canvas c, Offset p, double r) {
    final paint = Paint()..color = const Color(0xDDFFFFFF);
    c.drawCircle(p, r, paint);
    c.drawCircle(p + Offset(r * 0.9, r * 0.2), r * 0.75, paint);
    c.drawCircle(p + Offset(-r * 0.9, r * 0.25), r * 0.7, paint);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - r * 1.5, p.dy, p.dx + r * 1.6, p.dy + r * 0.85), Radius.circular(r * 0.4)), paint);
  }

  void _pinMark(Canvas c, Offset p, double r) {
    final path = Path()
      ..moveTo(p.dx, p.dy + r * 1.6)
      ..quadraticBezierTo(p.dx - r * 1.2, p.dy + r * 0.4, p.dx - r, p.dy)
      ..arcToPoint(Offset(p.dx + r, p.dy), radius: Radius.circular(r))
      ..quadraticBezierTo(p.dx + r * 1.2, p.dy + r * 0.4, p.dx, p.dy + r * 1.6)
      ..close();
    c.drawPath(path.shift(const Offset(0, 2)), Paint()..color = const Color(0x40000000));
    c.drawPath(path, Paint()..color = const Color(0xFFFF6A47));
    c.drawCircle(p, r * 0.45, Paint()..color = Colors.white);
  }

  void _label(Canvas c, Offset center, String text, Color bg, Color fg, double unit) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: max(10.0, unit * 0.034), fontWeight: FontWeight.w800, color: fg)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: center, width: tp.width + 14, height: tp.height + 6);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    c.drawRRect(rr.shift(const Offset(0, 2)), Paint()..color = const Color(0x33000000));
    c.drawRRect(rr, Paint()..color = bg);
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Một căn nhà nhỏ (gốc toạ độ = chân nhà ở giữa)
  void _shop(Canvas c, double s, _Spot sp, bool own, bool cur, double t) {
    final wall = own ? sp.wall : const Color(0xFFDADADA);
    final roof = own ? sp.roof : const Color(0xFF9E9E9E);
    final aw = own ? sp.awning : const Color(0xFFBDBDBD);
    c.drawOval(Rect.fromCenter(center: Offset(0, s * 0.05), width: s * 1.3, height: s * 0.25), Paint()..color = const Color(0x33000000));
    final body = Rect.fromLTRB(-s * 0.5, -s * 0.62, s * 0.5, 0);
    c.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(s * 0.05)), Paint()..color = wall);
    // mái
    final r = Path()
      ..moveTo(-s * 0.6, -s * 0.6)
      ..lineTo(0, -s * 1.0)
      ..lineTo(s * 0.6, -s * 0.6)
      ..close();
    c.drawPath(r, Paint()..color = roof);
    c.drawPath(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x33000000));
    // mái hiên sọc
    const n = 6;
    for (var k = 0; k < n; k++) {
      final x0 = -s * 0.55 + k * s * 1.1 / n;
      c.drawPath(
        Path()
          ..moveTo(x0, -s * 0.42)
          ..lineTo(x0 + s * 1.1 / n, -s * 0.42)
          ..lineTo(x0 + s * 1.1 / n, -s * 0.33)
          ..arcToPoint(Offset(x0, -s * 0.33), radius: Radius.circular(s * 0.1))
          ..close(),
        Paint()..color = k.isEven ? aw : Colors.white,
      );
    }
    // cửa sổ sáng đèn
    final glow = own ? (0.75 + 0.25 * sin(t * 2 + sp.pos.dx * 10)) : 0.3;
    for (final x in [-0.3, 0.3]) {
      final win = Rect.fromCenter(center: Offset(x * s, -s * 0.18), width: s * 0.24, height: s * 0.2);
      c.drawRRect(RRect.fromRectAndRadius(win, Radius.circular(s * 0.03)), Paint()..color = Color.lerp(const Color(0xFF90A4AE), const Color(0xFFFFE082), glow)!);
    }
    // cửa
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-s * 0.1, -s * 0.28, s * 0.2, s * 0.28), Radius.circular(s * 0.04)),
      Paint()..color = own ? const Color(0xFF6D4C41) : const Color(0xFF9E9E9E),
    );
    // biển hiệu
    final v = venueById(sp.id);
    final sign = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -s * 0.53), width: s * 0.42, height: s * 0.2), Radius.circular(s * 0.06));
    c.drawRRect(sign, Paint()..color = Colors.white);
    final tp = TextPainter(text: TextSpan(text: v.emoji, style: TextStyle(fontSize: s * 0.15)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(-tp.width / 2, -s * 0.53 - tp.height / 2));
    if (!own) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-s * 0.6, -s * 1.0, s * 0.6, 0), Radius.circular(s * 0.05)), Paint()..color = const Color(0x55FFFFFF));
      final lk = TextPainter(text: TextSpan(text: '🔒', style: TextStyle(fontSize: s * 0.28)), textDirection: TextDirection.ltr)..layout();
      lk.paint(c, Offset(-lk.width / 2, -s * 0.72));
    } else {
      // khói bếp từ ống khói
      c.drawRect(Rect.fromLTWH(s * 0.22, -s * 0.95, s * 0.1, s * 0.2), Paint()..color = const Color(0xFF6D4C41));
      for (var k = 0; k < 3; k++) {
        final ph = (t * 0.4 + k / 3 + sp.pos.dx) % 1.0;
        c.drawCircle(Offset(s * 0.27 + sin(ph * 6) * s * 0.05, -s * 0.98 - ph * s * 0.4), s * (0.04 + 0.05 * ph), Paint()..color = Color.fromRGBO(255, 255, 255, 0.7 * (1 - ph)));
      }
    }
  }

  void _truck(Canvas c, double s, _Spot sp, bool own, double t) {
    final body = own ? sp.wall : const Color(0xFFDADADA);
    final trim = own ? sp.roof : const Color(0xFF9E9E9E);
    c.drawOval(Rect.fromCenter(center: Offset(0, s * 0.03), width: s * 1.5, height: s * 0.22), Paint()..color = const Color(0x33000000));
    final box = Rect.fromLTRB(-s * 0.7, -s * 0.55, s * 0.35, -s * 0.08);
    c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(s * 0.06)), Paint()..color = body);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(s * 0.35, -s * 0.4, s * 0.68, -s * 0.08), Radius.circular(s * 0.06)), Paint()..color = trim);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(s * 0.42, -s * 0.35, s * 0.62, -s * 0.22), Radius.circular(s * 0.03)), Paint()..color = const Color(0xFFB3E5FC));
    // cửa bán hàng + mái hiên
    c.drawRect(Rect.fromLTRB(-s * 0.58, -s * 0.45, s * 0.22, -s * 0.24), Paint()..color = own ? const Color(0xFFFFF59D) : const Color(0xFFBDBDBD));
    for (var k = 0; k < 6; k++) {
      c.drawRect(Rect.fromLTWH(-s * 0.62 + k * s * 0.14, -s * 0.58, s * 0.14, s * 0.08), Paint()..color = k.isEven ? (own ? sp.awning : const Color(0xFFBDBDBD)) : Colors.white);
    }
    for (final x in [-0.45, 0.45]) {
      c.drawCircle(Offset(x * s, -s * 0.06), s * 0.1, Paint()..color = const Color(0xFF263238));
      c.drawCircle(Offset(x * s, -s * 0.06), s * 0.04, Paint()..color = const Color(0xFFB0BEC5));
    }
    final tp = TextPainter(text: TextSpan(text: own ? '🍔' : '🔒', style: TextStyle(fontSize: s * 0.2)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(-s * 0.18 - tp.width / 2, -s * 0.36 - tp.height / 2));
  }
}

class _TownPainter extends CustomPainter {
  final _TownMapState st;
  _TownPainter(this.st) : super(repaint: st._clock);
  @override
  void paint(Canvas canvas, Size size) => st._paint(canvas, size);
  @override
  bool shouldRepaint(covariant _TownPainter oldDelegate) => true;
}
