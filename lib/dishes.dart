// Món ăn vẽ tay: mỗi món một hình riêng, đúng với tên món.
// Mọi hình vẽ trong hệ toạ độ 100×100 (tâm ở giữa), sau đó phóng theo [size].
import 'dart:math';
import 'package:flutter/material.dart';

Color _al(Color c, double o) => c.withAlpha((o.clamp(0.0, 1.0) * 255).round());
Paint _p(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;
Paint _st(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;
Paint _grad(Rect r, List<Color> cols, {bool vertical = true}) => Paint()
  ..shader = LinearGradient(
    begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
    end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
    colors: cols,
  ).createShader(r);

/// Vẽ món [id] với tâm [p], kích thước [size]. [burnt]: món bị cháy (tối màu, khói).
void drawDish(Canvas c, String id, Offset p, double size, {double t = 0, bool burnt = false}) {
  final bounds = Rect.fromCenter(center: p, width: size * 1.3, height: size * 1.3);
  if (burnt) {
    c.saveLayer(bounds, Paint()..colorFilter = const ColorFilter.mode(Color(0xA0201010), BlendMode.srcATop));
  } else {
    c.save();
  }
  c.translate(p.dx, p.dy);
  c.scale(size / 100);
  switch (id) {
    case 'cf_den':
      _cfDen(c, t);
      break;
    case 'cf_sua':
      _cfSua(c, t);
      break;
    case 'cf_da':
      _cfDa(c, t);
      break;
    case 'tra_dau':
      _traDau(c, t);
      break;
    case 'sinh_to':
      _sinhTo(c, t);
      break;
    case 'banh_mi':
      _banhMi(c);
      break;
    case 'cookie':
      _cookie(c);
      break;
    case 'cupcake':
      _cupcake(c);
      break;
    case 'cheesecake':
      _cheesecake(c);
      break;
    case 'com_chien':
      _comChien(c, t);
      break;
    case 'mi_xao':
      _miXao(c, t);
      break;
    case 'ha_cao':
      _haCao(c, t);
      break;
    case 'suon':
      _suon(c, t);
      break;
    case 'taco':
      _taco(c);
      break;
    case 'burrito':
      _burrito(c);
      break;
    case 'nachos':
      _nachos(c);
      break;
    case 'guac':
      _guac(c);
      break;
    case 'quesa':
      _quesa(c);
      break;
    case 'fries':
      _fries(c, 0, 0, 1);
      break;
    case 'hotdog':
      _hotdog(c);
      break;
    case 'burger':
      _burger(c, 0, 0, 1);
      break;
    case 'combo':
      _combo(c);
      break;
    case 'r_melon':
      _gMelon(c, t);
      break;
    case 'r_mango':
      _gMango(c, t);
      break;
    case 'r_dragon':
      _gDragon(c, t);
      break;
    case 'r_pine':
      _gPine(c, t);
      break;
    case 'r_duck':
      _gDuck(c, t);
      break;
    case 'r_beef':
      _gBeef(c, t);
      break;
    case 'r_salmon':
      _gSalmon(c, t);
      break;
    case 'r_lobster':
      _gLobster(c, t);
      break;
    default:
      _plate(c);
  }
  c.restore();
  if (burnt) {
    for (var k = 0; k < 2; k++) {
      final ph = (t * 0.6 + k * 0.5) % 1.0;
      c.drawCircle(p + Offset((k - 0.5) * size * 0.25, -size * (0.2 + ph * 0.4)), size * (0.08 + 0.1 * ph), _p(_al(const Color(0xFF424242), 0.55 * (1 - ph))));
    }
  }
}

// ------------------------------------------------------------------ đồ đựng
void _shadow(Canvas c, double y, double w) => c.drawOval(Rect.fromCenter(center: Offset(0, y), width: w, height: w * 0.18), _p(const Color(0x30000000)));

void _plate(Canvas c, {double y = 18, double w = 96, Color rim = Colors.white}) {
  _shadow(c, y + 6, w * 0.95);
  final outer = Rect.fromCenter(center: Offset(0, y), width: w, height: w * 0.34);
  c.drawOval(outer, _p(rim));
  c.drawOval(outer, _st(const Color(0x22000000), 1.2));
  c.drawOval(Rect.fromCenter(center: Offset(0, y), width: w * 0.72, height: w * 0.22), _p(const Color(0xFFF1F1F1)));
}

/// Hơi nóng bốc lên
void _steam(Canvas c, double t, double x, double y, {int n = 3, double h = 26}) {
  for (var k = 0; k < n; k++) {
    final ph = (t * 0.7 + k / n) % 1.0;
    final path = Path()..moveTo(x + (k - (n - 1) / 2) * 9, y);
    for (var j = 1; j <= 6; j++) {
      path.lineTo(x + (k - (n - 1) / 2) * 9 + sin(j * 1.2 + t * 3 + k) * 3, y - j * h / 6 * (0.6 + 0.4 * ph));
    }
    c.drawPath(path, _st(_al(Colors.white, 0.75 * (1 - ph * 0.6)), 2.6));
  }
}

/// Ly thuỷ tinh cao, trả về hình dạng lòng ly để đổ nước
Path _tallGlass(double top, double bottom, double wTop, double wBot) => Path()
  ..moveTo(-wTop / 2, top)
  ..lineTo(wTop / 2, top)
  ..lineTo(wBot / 2, bottom - 4)
  ..quadraticBezierTo(wBot / 2, bottom, wBot / 2 - 4, bottom)
  ..lineTo(-wBot / 2 + 4, bottom)
  ..quadraticBezierTo(-wBot / 2, bottom, -wBot / 2, bottom - 4)
  ..close();

void _glassShine(Canvas c, double top, double bottom, double w) {
  c.drawLine(Offset(-w * 0.32, top + 6), Offset(-w * 0.28, bottom - 8), _st(const Color(0x88FFFFFF), 3));
}

void _ice(Canvas c, double x, double y, double s, double rot) {
  c.save();
  c.translate(x, y);
  c.rotate(rot);
  final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s, height: s), Radius.circular(s * 0.25));
  c.drawRRect(r, _p(const Color(0x99FFFFFF)));
  c.drawRRect(r, _st(const Color(0xCCFFFFFF), 1));
  c.restore();
}

void _strawberry(Canvas c, double x, double y, double s, {double rot = 0}) {
  c.save();
  c.translate(x, y);
  c.rotate(rot);
  final body = Path()
    ..moveTo(0, s * 0.55)
    ..cubicTo(-s * 0.6, s * 0.1, -s * 0.5, -s * 0.45, 0, -s * 0.35)
    ..cubicTo(s * 0.5, -s * 0.45, s * 0.6, s * 0.1, 0, s * 0.55)
    ..close();
  c.drawPath(body, _grad(Rect.fromCenter(center: Offset.zero, width: s, height: s), const [Color(0xFFFF5252), Color(0xFFC62828)]));
  for (var k = 0; k < 6; k++) {
    c.drawCircle(Offset((k % 3 - 1) * s * 0.18, -s * 0.1 + (k ~/ 3) * s * 0.22), s * 0.035, _p(const Color(0xFFFFF59D)));
  }
  for (var k = -1; k <= 1; k++) {
    c.drawOval(Rect.fromCenter(center: Offset(k * s * 0.13, -s * 0.38), width: s * 0.22, height: s * 0.1), _p(const Color(0xFF43A047)));
  }
  c.restore();
}

// ------------------------------------------------------------------ quán cà phê
void _cfDen(Canvas c, double t) {
  _shadow(c, 34, 80);
  c.drawOval(Rect.fromCenter(center: const Offset(0, 28), width: 80, height: 20), _p(Colors.white));
  c.drawOval(Rect.fromCenter(center: const Offset(0, 28), width: 80, height: 20), _st(const Color(0x22000000), 1));
  // quai cốc
  c.drawArc(Rect.fromCenter(center: const Offset(26, 4), width: 22, height: 22), -pi / 2, pi, false, _st(Colors.white, 6));
  final cup = Path()
    ..moveTo(-28, -12)
    ..lineTo(28, -12)
    ..quadraticBezierTo(26, 26, 0, 26)
    ..quadraticBezierTo(-26, 26, -28, -12)
    ..close();
  c.drawPath(cup, _grad(const Rect.fromLTRB(-28, -12, 28, 26), const [Colors.white, Color(0xFFE0E0E0)], vertical: false));
  c.drawOval(Rect.fromCenter(center: const Offset(0, -12), width: 56, height: 14), _p(const Color(0xFF3E2723)));
  c.drawOval(Rect.fromCenter(center: const Offset(-6, -13), width: 20, height: 4), _p(const Color(0x55A1887F)));
  _steam(c, t, 0, -20);
}

void _cfSua(Canvas c, double t) {
  _shadow(c, 36, 60);
  final glass = _tallGlass(-10, 34, 46, 38);
  c.save();
  c.clipPath(glass);
  c.drawRect(const Rect.fromLTRB(-30, 18, 30, 40), _p(const Color(0xFFFFF3D6))); // sữa đặc
  c.drawRect(const Rect.fromLTRB(-30, 0, 30, 18), _grad(const Rect.fromLTRB(-30, 0, 30, 18), const [Color(0xFF6D3B1F), Color(0xFF9C6644)]));
  c.restore();
  c.drawPath(glass, _p(const Color(0x33FFFFFF)));
  c.drawPath(glass, _st(const Color(0xAAFFFFFF), 1.6));
  _glassShine(c, -10, 34, 46);
  // phin nhôm trên miệng ly
  c.drawOval(Rect.fromCenter(center: const Offset(0, -10), width: 54, height: 10), _p(const Color(0xFFB0BEC5)));
  final phin = RRect.fromRectAndRadius(const Rect.fromLTRB(-17, -36, 17, -10), const Radius.circular(3));
  c.drawRRect(phin, _grad(phin.outerRect, const [Color(0xFFECEFF1), Color(0xFF90A4AE)], vertical: false));
  c.drawOval(Rect.fromCenter(center: const Offset(0, -36), width: 38, height: 9), _p(const Color(0xFFCFD8DC)));
  c.drawCircle(const Offset(0, -40), 3, _p(const Color(0xFF90A4AE)));
  // giọt cà phê
  final ph = (t * 1.4) % 1.0;
  c.drawCircle(Offset(0, -6 + ph * 8), 1.8, _p(_al(const Color(0xFF3E2723), 1 - ph)));
}

void _cfDa(Canvas c, double t) {
  _shadow(c, 42, 52);
  final glass = _tallGlass(-36, 42, 46, 36);
  c.save();
  c.clipPath(glass);
  c.drawRect(const Rect.fromLTRB(-30, -24, 30, 44), _grad(const Rect.fromLTRB(-30, -24, 30, 44), const [Color(0xFFC8A27A), Color(0xFF8D5B3C)]));
  _ice(c, -9, -16, 15, 0.2);
  _ice(c, 8, -12, 14, -0.3);
  _ice(c, -2, 2, 14, 0.5);
  _ice(c, 10, 14, 12, 0.1);
  c.restore();
  c.drawPath(glass, _p(const Color(0x22FFFFFF)));
  c.drawPath(glass, _st(const Color(0xAAFFFFFF), 1.6));
  _glassShine(c, -36, 42, 46);
  // ống hút
  c.drawLine(const Offset(6, -24), const Offset(16, -50), _st(const Color(0xFF2E7D32), 5));
  // giọt nước đọng
  for (var k = 0; k < 3; k++) {
    c.drawCircle(Offset(14 - k * 4.0, -2.0 + k * 12), 1.6, _p(const Color(0xBBFFFFFF)));
  }
}

void _traDau(Canvas c, double t) {
  _shadow(c, 42, 52);
  final glass = _tallGlass(-36, 42, 48, 36);
  c.save();
  c.clipPath(glass);
  c.drawRect(const Rect.fromLTRB(-30, -26, 30, 44), _grad(const Rect.fromLTRB(-30, -26, 30, 44), const [Color(0xFFFFAB91), Color(0xFFE53935)]));
  _ice(c, -8, -18, 14, 0.3);
  _ice(c, 9, -10, 13, -0.2);
  for (var k = 0; k < 3; k++) {
    c.drawCircle(Offset(-10 + k * 10.0, 22.0 + (k % 2) * 8), 5, _p(const Color(0xFFB71C1C)));
  }
  c.restore();
  c.drawPath(glass, _p(const Color(0x22FFFFFF)));
  c.drawPath(glass, _st(const Color(0xAAFFFFFF), 1.6));
  _glassShine(c, -36, 42, 48);
  // lát dâu cài miệng ly + lá bạc hà
  _strawberry(c, 22, -38, 20, rot: 0.6);
  c.drawOval(Rect.fromCenter(center: const Offset(-14, -40), width: 14, height: 7), _p(const Color(0xFF66BB6A)));
  c.drawLine(const Offset(-4, -26), const Offset(-12, -52), _st(const Color(0xFFFFFFFF), 4));
}

void _sinhTo(Canvas c, double t) {
  _shadow(c, 42, 50);
  final glass = Path()
    ..moveTo(-24, -20)
    ..lineTo(24, -20)
    ..quadraticBezierTo(22, 30, 10, 38)
    ..lineTo(-10, 38)
    ..quadraticBezierTo(-22, 30, -24, -20)
    ..close();
  c.drawPath(glass, _grad(const Rect.fromLTRB(-24, -20, 24, 38), const [Color(0xFFF48FB1), Color(0xFFE91E63)]));
  c.drawLine(const Offset(-10, 38), const Offset(10, 38), _st(const Color(0xFFFFFFFF), 3));
  c.drawLine(const Offset(0, 38), const Offset(0, 44), _st(const Color(0xCCFFFFFF), 4));
  c.drawOval(Rect.fromCenter(center: const Offset(0, 45), width: 30, height: 6), _p(const Color(0xCCFFFFFF)));
  // kem tươi
  for (final o in const [Offset(-14, -22), Offset(0, -26), Offset(14, -22), Offset(-6, -32), Offset(7, -33), Offset(0, -38)]) {
    c.drawCircle(o, 10, _p(const Color(0xFFFFFDF7)));
  }
  c.drawCircle(const Offset(-4, -36), 3, _p(Colors.white));
  _strawberry(c, 3, -48, 18);
  // ống hút sọc
  c.save();
  c.translate(16, -30);
  c.rotate(0.35);
  c.drawRect(const Rect.fromLTWH(-3, -26, 6, 30), _p(Colors.white));
  for (var k = 0; k < 4; k++) {
    c.drawRect(Rect.fromLTWH(-3, -24 + k * 7.0, 6, 3), _p(const Color(0xFFE91E63)));
  }
  c.restore();
  _glassShine(c, -20, 30, 44);
}

// ------------------------------------------------------------------ tiệm bánh
void _banhMi(Canvas c) {
  _plate(c, y: 20);
  c.save();
  c.translate(-4, 6);
  c.rotate(-0.28);
  final loaf = RRect.fromRectAndRadius(const Rect.fromLTRB(-40, -13, 40, 13), const Radius.circular(13));
  c.drawRRect(loaf, _grad(loaf.outerRect, const [Color(0xFFF2B866), Color(0xFFC07A2E)]));
  for (var k = 0; k < 4; k++) {
    final x = -24 + k * 16.0;
    c.drawLine(Offset(x - 4, -6), Offset(x + 6, 5), _st(const Color(0xFFFFE0A3), 3));
  }
  c.drawLine(const Offset(-32, -8), const Offset(30, -8), _st(const Color(0x55FFFFFF), 2));
  c.restore();
  // miếng bơ đang chảy
  final butter = RRect.fromRectAndRadius(const Rect.fromLTWH(14, -14, 18, 12), const Radius.circular(3));
  c.drawRRect(butter, _p(const Color(0xFFFFE082)));
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, -14, 18, 4), const Radius.circular(2)), _p(const Color(0xFFFFF8E1)));
  c.drawOval(Rect.fromCenter(center: const Offset(24, -1), width: 16, height: 5), _p(const Color(0xCCFFE082)));
}

void _cookieOne(Canvas c, Offset o, double r, int seed) {
  c.drawCircle(o + const Offset(0, 2), r, _p(const Color(0xFF9C6A3A)));
  c.drawCircle(o, r, _grad(Rect.fromCircle(center: o, radius: r), const [Color(0xFFE8B06A), Color(0xFFC88A44)]));
  final rr = Random(seed);
  for (var k = 0; k < 6; k++) {
    final a = rr.nextDouble() * 2 * pi;
    final d = rr.nextDouble() * r * 0.7;
    c.drawCircle(o + Offset(cos(a) * d, sin(a) * d * 0.8), r * 0.13, _p(const Color(0xFF4E2A12)));
  }
}

void _cookie(Canvas c) {
  _plate(c, y: 22);
  _cookieOne(c, const Offset(-18, 14), 20, 1);
  _cookieOne(c, const Offset(18, 12), 20, 2);
  _cookieOne(c, const Offset(0, -2), 22, 3);
}

void _cupcake(Canvas c) {
  _shadow(c, 40, 60);
  // giấy lót sọc
  final cup = Path()
    ..moveTo(-26, 2)
    ..lineTo(26, 2)
    ..lineTo(18, 38)
    ..lineTo(-18, 38)
    ..close();
  c.drawPath(cup, _p(const Color(0xFFFFFFFF)));
  c.save();
  c.clipPath(cup);
  for (var k = 0; k < 7; k++) {
    final x = -26 + k * 8.5;
    c.drawPath(
      Path()
        ..moveTo(x, 2)
        ..lineTo(x + 4.5, 2)
        ..lineTo(x + 3.5, 38)
        ..lineTo(x - 0.5, 38)
        ..close(),
      _p(const Color(0xFFF48FB1)),
    );
  }
  c.restore();
  // kem xoắn 3 tầng
  for (final l in const [(4.0, 60.0, 16.0), (-8.0, 46.0, 14.0), (-19.0, 30.0, 12.0)]) {
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, l.$1), width: l.$2, height: l.$3), Radius.circular(l.$3 / 2));
    c.drawRRect(r, _grad(r.outerRect, const [Color(0xFFFFD1E3), Color(0xFFF48FB1)]));
  }
  c.drawCircle(const Offset(-8, -12), 3, _p(const Color(0x88FFFFFF)));
  // rắc cốm màu
  const sp = [Color(0xFF42A5F5), Color(0xFFFFEB3B), Color(0xFF66BB6A), Color(0xFFFFFFFF)];
  final rr = Random(4);
  for (var k = 0; k < 10; k++) {
    final x = -22 + rr.nextDouble() * 44, y = -16 + rr.nextDouble() * 22;
    c.save();
    c.translate(x, y);
    c.rotate(rr.nextDouble() * pi);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-3, -1, 6, 2), const Radius.circular(1)), _p(sp[k % 4]));
    c.restore();
  }
  _strawberry(c, 0, -32, 20);
}

void _cheesecake(Canvas c) {
  _plate(c, y: 22);
  // lát bánh hình tam giác nhìn chéo
  final top = Path()
    ..moveTo(-34, 0)
    ..lineTo(26, -14)
    ..lineTo(34, 4)
    ..close();
  final side = Path()
    ..moveTo(-34, 0)
    ..lineTo(34, 4)
    ..lineTo(34, 24)
    ..lineTo(-34, 22)
    ..close();
  final back = Path()
    ..moveTo(34, 4)
    ..lineTo(26, -14)
    ..lineTo(26, 6)
    ..lineTo(34, 24)
    ..close();
  c.drawPath(side, _grad(const Rect.fromLTRB(-34, 0, 34, 24), const [Color(0xFFFFF3C4), Color(0xFFFFE08A)]));
  c.drawPath(back, _p(const Color(0xFFF5D88A)));
  c.drawPath(
    Path()
      ..moveTo(-34, 18)
      ..lineTo(34, 20)
      ..lineTo(34, 24)
      ..lineTo(-34, 22)
      ..close(),
    _p(const Color(0xFFB07A3C)),
  ); // đế bánh quy
  c.drawPath(top, _p(const Color(0xFFFFF8E1)));
  // sốt dâu chảy
  final sauce = Path()
    ..moveTo(-24, -2)
    ..quadraticBezierTo(0, -12, 26, -12)
    ..lineTo(32, 2)
    ..lineTo(30, 10)
    ..quadraticBezierTo(27, 12, 26, 6)
    ..lineTo(8, 2)
    ..lineTo(6, 9)
    ..quadraticBezierTo(3, 11, 2, 4)
    ..lineTo(-20, 1)
    ..close();
  c.drawPath(sauce, _p(const Color(0xFFD32F2F)));
  c.drawOval(Rect.fromCenter(center: const Offset(10, -8), width: 10, height: 3), _p(const Color(0x88FFFFFF)));
  _strawberry(c, 18, -20, 16, rot: 0.3);
  c.drawOval(Rect.fromCenter(center: const Offset(-6, -10), width: 10, height: 5), _p(const Color(0xFF66BB6A)));
}

// ------------------------------------------------------------------ nhà hàng Trung
void _comChien(Canvas c, double t) {
  _plate(c, y: 20, w: 100);
  final mound = Path()
    ..moveTo(-38, 18)
    ..quadraticBezierTo(-36, -18, 0, -20)
    ..quadraticBezierTo(36, -18, 38, 18)
    ..close();
  c.drawPath(mound, _grad(const Rect.fromLTRB(-38, -20, 38, 18), const [Color(0xFFFFE08A), Color(0xFFE8B04A)]));
  final rr = Random(7);
  for (var k = 0; k < 40; k++) {
    final x = -32 + rr.nextDouble() * 64;
    final yTop = -18 + (x.abs() / 38) * (x.abs() / 38) * 30;
    final y = yTop + rr.nextDouble() * (16 - yTop);
    c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4, height: 2.6), _p(const Color(0xFFFFF5D1)));
  }
  final bits = [const Color(0xFFFFC107), const Color(0xFF7CB342), const Color(0xFFFF7043), const Color(0xFF43A047)];
  for (var k = 0; k < 22; k++) {
    final x = -30 + rr.nextDouble() * 60;
    final yTop = -16 + (x.abs() / 38) * (x.abs() / 38) * 30;
    final y = yTop + rr.nextDouble() * (14 - yTop);
    c.drawCircle(Offset(x, y), k % 4 == 0 ? 3.4 : 2.4, _p(bits[k % 4]));
  }
  // hành lá + lát dưa leo trang trí
  c.drawLine(const Offset(-6, -20), const Offset(4, -26), _st(const Color(0xFF66BB6A), 2.5));
  c.drawLine(const Offset(2, -20), const Offset(10, -25), _st(const Color(0xFF43A047), 2.5));
  c.drawOval(Rect.fromCenter(center: const Offset(36, 22), width: 14, height: 8), _p(const Color(0xFF8BC34A)));
  c.drawOval(Rect.fromCenter(center: const Offset(36, 22), width: 9, height: 5), _p(const Color(0xFFDCEDC8)));
  _steam(c, t, 0, -24, n: 2, h: 20);
}

void _miXao(Canvas c, double t) {
  _plate(c, y: 20, w: 100);
  // đĩa mì vun cao
  final mound = Path()
    ..moveTo(-38, 16)
    ..quadraticBezierTo(-32, -16, 0, -18)
    ..quadraticBezierTo(32, -16, 38, 16)
    ..close();
  c.drawPath(mound, _grad(const Rect.fromLTRB(-38, -18, 38, 16), const [Color(0xFFF6CF86), Color(0xFFD69A45)]));
  // sợi mì xoăn
  final rr = Random(21);
  for (var k = 0; k < 34; k++) {
    final x = -30 + rr.nextDouble() * 60;
    final yTop = -15 + (x / 36) * (x / 36) * 28;
    final y = yTop + 3 + rr.nextDouble() * (12 - yTop);
    final w = 10 + rr.nextDouble() * 14, h = 5 + rr.nextDouble() * 6;
    c.drawArc(Rect.fromCenter(center: Offset(x, y), width: w, height: h), rr.nextDouble() * pi * 2, pi * 1.2, false,
        _st(k % 3 == 0 ? const Color(0xFFC98A3C) : const Color(0xFFFFE3A8), 2.2));
  }
  // thịt + cải + cà rốt
  for (final o in const [Offset(-14, -6), Offset(10, -9), Offset(20, 4), Offset(-22, 6)]) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(o.dx * 0.04);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 13, height: 7), const Radius.circular(2)), _p(const Color(0xFF8D4A2B)));
    c.drawLine(const Offset(-4, -1), const Offset(4, -1), _st(const Color(0x55FFFFFF), 1.2));
    c.restore();
  }
  for (final o in const [Offset(-4, -13), Offset(2, 4), Offset(28, -2)]) {
    c.drawOval(Rect.fromCenter(center: o, width: 15, height: 8), _p(const Color(0xFF66BB6A)));
    c.drawLine(o - const Offset(6, 0), o + const Offset(6, 0), _st(const Color(0xFFC5E1A5), 1.4));
  }
  for (final o in const [Offset(-10, 6), Offset(12, -2), Offset(-28, 0)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 7, height: 3.4), const Radius.circular(1.5)), _p(const Color(0xFFFF7043)));
  }
  // đũa
  c.drawLine(const Offset(18, -26), const Offset(44, 14), _st(const Color(0xFF8D6E63), 3));
  c.drawLine(const Offset(24, -28), const Offset(48, 10), _st(const Color(0xFF8D6E63), 3));
  _steam(c, t, -4, -18, n: 2, h: 18);
}

void _haCao(Canvas c, double t) {
  _shadow(c, 30, 90);
  // xửng tre
  final rim = Rect.fromCenter(center: const Offset(0, 12), width: 92, height: 40);
  c.drawOval(rim.shift(const Offset(0, 8)), _p(const Color(0xFFA1783F)));
  c.drawOval(rim, _p(const Color(0xFFD9B26F)));
  c.drawOval(rim.deflate(5), _p(const Color(0xFFF3DFA8)));
  for (var k = -3; k <= 3; k++) {
    c.drawLine(Offset(k * 11.0, 0), Offset(k * 11.0, 26), _st(const Color(0x33A1783F), 1));
  }
  // 3 viên há cảo trong suốt thấy nhân tôm hồng
  for (final o in const [Offset(-22, 8), Offset(20, 8), Offset(0, 0)]) {
    final body = Path()
      ..moveTo(o.dx - 17, o.dy + 8)
      ..quadraticBezierTo(o.dx - 18, o.dy - 14, o.dx, o.dy - 16)
      ..quadraticBezierTo(o.dx + 18, o.dy - 14, o.dx + 17, o.dy + 8)
      ..close();
    c.drawPath(body, _p(const Color(0xF2FFFDF8)));
    c.drawOval(Rect.fromCenter(center: Offset(o.dx, o.dy - 1), width: 18, height: 12), _p(const Color(0x99FF8A80)));
    c.drawPath(body, _st(const Color(0x22000000), 1));
    for (var k = -2; k <= 2; k++) {
      c.drawLine(Offset(o.dx + k * 4.0, o.dy - 14), Offset(o.dx + k * 3.0, o.dy - 8), _st(const Color(0x33000000), 1));
    }
    c.drawCircle(Offset(o.dx - 6, o.dy - 8), 2.5, _p(const Color(0xAAFFFFFF)));
  }
  _steam(c, t, 0, -18);
}

void _suon(Canvas c, double t) {
  _plate(c, y: 20, w: 100);
  c.drawOval(Rect.fromCenter(center: const Offset(0, 20), width: 70, height: 16), _p(const Color(0x88D84315))); // sốt
  // miếng sườn nằm ngang, xương thò ra hai bên xen kẽ
  for (final r in const [(0.0, 10.0, 1.45), (-4.0, 0.0, -1.5), (4.0, -10.0, 1.6), (-2.0, -19.0, -1.42)]) {
    c.save();
    c.translate(r.$1, r.$2);
    c.rotate(r.$3);
    final meat = RRect.fromRectAndRadius(const Rect.fromLTRB(-8, -15, 8, 15), const Radius.circular(7));
    c.drawRRect(meat, _grad(meat.outerRect, const [Color(0xFFE8590C), Color(0xFFA51D1D)], vertical: false));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-2.6, -24, 2.6, -12), const Radius.circular(2.6)), _p(const Color(0xFFFFF8E1)));
    c.drawCircle(const Offset(0, -24), 3.4, _p(const Color(0xFFFFF8E1)));
    c.drawOval(Rect.fromCenter(center: const Offset(-3, 0), width: 4, height: 16), _p(const Color(0x66FFFFFF)));
    c.restore();
  }
  // mè rang + hành lá
  final rr = Random(5);
  for (var k = 0; k < 16; k++) {
    c.drawOval(Rect.fromCenter(center: Offset(-20 + rr.nextDouble() * 40, -24 + rr.nextDouble() * 38), width: 3, height: 1.8), _p(const Color(0xFFFFF8E1)));
  }
  for (final o in const [Offset(-12, -22), Offset(8, -14), Offset(14, 4), Offset(-14, 6)]) {
    c.drawCircle(o, 2.6, _p(const Color(0xFF43A047)));
    c.drawCircle(o, 1.2, _p(const Color(0xFFA5D6A7)));
  }
  _steam(c, t, 0, -30, n: 2, h: 18);
}

// ------------------------------------------------------------------ nhà hàng Mexico
void _tacoOne(Canvas c, double x, double y, double rot) {
  c.save();
  c.translate(x, y);
  c.rotate(rot);
  // nhân
  c.drawOval(Rect.fromCenter(center: const Offset(0, -12), width: 50, height: 16), _p(const Color(0xFF7B3F1C)));
  for (var k = 0; k < 7; k++) {
    c.drawCircle(Offset(-20 + k * 6.6, -16 + (k % 2) * 3.0), 5, _p(const Color(0xFF7CB342)));
  }
  for (final o in const [Offset(-10, -18), Offset(6, -19), Offset(16, -15)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 6, height: 6), const Radius.circular(1.5)), _p(const Color(0xFFE53935)));
  }
  for (var k = 0; k < 6; k++) {
    c.drawLine(Offset(-16 + k * 6.0, -20), Offset(-12 + k * 6.0, -14), _st(const Color(0xFFFFD54F), 2));
  }
  // vỏ taco hình chữ U
  final shell = Path()
    ..moveTo(-27, -12)
    ..quadraticBezierTo(-27, 18, 0, 18)
    ..quadraticBezierTo(27, 18, 27, -12)
    ..quadraticBezierTo(24, -4, 0, -4)
    ..quadraticBezierTo(-24, -4, -27, -12)
    ..close();
  c.drawPath(shell, _grad(const Rect.fromLTRB(-27, -12, 27, 18), const [Color(0xFFFFD54F), Color(0xFFE0A030)]));
  for (var k = 0; k < 5; k++) {
    c.drawCircle(Offset(-14 + k * 7.0, 6 + (k % 2) * 4.0), 1.4, _p(const Color(0x66A0522D)));
  }
  c.restore();
}

void _taco(Canvas c) {
  _plate(c, y: 24, w: 100);
  _tacoOne(c, -16, 10, -0.12);
  _tacoOne(c, 18, 6, 0.15);
  c.drawOval(Rect.fromCenter(center: const Offset(36, 26), width: 14, height: 9), _p(const Color(0xFF8BC34A)));
  c.drawOval(Rect.fromCenter(center: const Offset(36, 26), width: 7, height: 4), _p(const Color(0xFFDCEDC8)));
}

void _burrito(Canvas c) {
  _plate(c, y: 22, w: 100);
  for (final b in const [(-14.0, 4.0, -0.25), (16.0, 10.0, 0.2)]) {
    c.save();
    c.translate(b.$1, b.$2);
    c.rotate(b.$3);
    final wrap = RRect.fromRectAndRadius(const Rect.fromLTRB(-24, -14, 18, 14), const Radius.circular(12));
    c.drawRRect(wrap, _grad(wrap.outerRect, const [Color(0xFFFFF0CF), Color(0xFFE8C58A)]));
    for (final o in const [Offset(-14, -6), Offset(-4, 6), Offset(6, -4)]) {
      c.drawCircle(o, 2, _p(const Color(0x66A0522D)));
    }
    // mặt cắt lộ nhân
    final cut = Rect.fromCenter(center: const Offset(18, 0), width: 16, height: 28);
    c.drawOval(cut, _p(const Color(0xFFF3DDB0)));
    c.drawOval(cut.deflate(2.5), _p(const Color(0xFFFFFFFF)));
    c.drawCircle(const Offset(17, -6), 3, _p(const Color(0xFF6D2E14)));
    c.drawCircle(const Offset(20, 2), 3, _p(const Color(0xFF7CB342)));
    c.drawCircle(const Offset(16, 6), 2.6, _p(const Color(0xFFE53935)));
    c.drawCircle(const Offset(19, -1), 2.2, _p(const Color(0xFFFFD54F)));
    c.drawCircle(const Offset(15, 0), 2.2, _p(const Color(0xFF5D4037)));
    c.restore();
  }
}

void _nachos(Canvas c) {
  _plate(c, y: 22, w: 100);
  final rr = Random(9);
  for (var k = 0; k < 11; k++) {
    final x = -32 + rr.nextDouble() * 64, y = -12 + rr.nextDouble() * 28;
    c.save();
    c.translate(x, y);
    c.rotate(rr.nextDouble() * pi * 2);
    final chip = Path()
      ..moveTo(0, -13)
      ..lineTo(12, 9)
      ..lineTo(-12, 9)
      ..close();
    c.drawPath(chip, _p(k.isEven ? const Color(0xFFFFCA28) : const Color(0xFFF9A825)));
    c.drawPath(chip, _st(const Color(0x33A0522D), 1));
    c.restore();
  }
  // phô mai chảy
  final cheese = Path()..moveTo(-30, -2);
  for (var x = -30.0; x <= 30; x += 5) {
    cheese.lineTo(x, -2 + sin(x * 0.4) * 6);
  }
  c.drawPath(cheese, _st(const Color(0xFFFFB300), 6));
  c.drawPath(cheese, _st(const Color(0xFFFFE082), 2));
  // ớt jalapeño + cà chua
  for (final o in const [Offset(-16, -8), Offset(8, 4), Offset(22, -6)]) {
    c.drawCircle(o, 4.5, _p(const Color(0xFF558B2F)));
    c.drawCircle(o, 2.4, _p(const Color(0xFFC5E1A5)));
  }
  for (final o in const [Offset(-6, 8), Offset(16, 10), Offset(-24, 6)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 5, height: 5), const Radius.circular(1)), _p(const Color(0xFFE53935)));
  }
}

void _guac(Canvas c) {
  _shadow(c, 34, 84);
  // bánh tortilla cắm vào chén
  for (final ch in const [(-24.0, -14.0, -0.6), (22.0, -16.0, 0.5), (2.0, -22.0, 0.05)]) {
    c.save();
    c.translate(ch.$1, ch.$2);
    c.rotate(ch.$3);
    final chip = Path()
      ..moveTo(0, -16)
      ..lineTo(11, 10)
      ..lineTo(-11, 10)
      ..close();
    c.drawPath(chip, _p(const Color(0xFFFFCA28)));
    c.restore();
  }
  // chén đá
  final bowl = Path()
    ..moveTo(-40, 0)
    ..quadraticBezierTo(-36, 32, 0, 32)
    ..quadraticBezierTo(36, 32, 40, 0)
    ..close();
  c.drawPath(bowl, _grad(const Rect.fromLTRB(-40, 0, 40, 32), const [Color(0xFF616161), Color(0xFF303030)]));
  for (final o in const [Offset(-20, 14), Offset(8, 22), Offset(24, 10), Offset(-6, 26)]) {
    c.drawCircle(o, 1.6, _p(const Color(0x55FFFFFF)));
  }
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: 80, height: 18), _p(const Color(0xFF424242)));
  // sốt bơ xanh
  final dip = Path()
    ..moveTo(-36, 0)
    ..quadraticBezierTo(-20, -14, 0, -12)
    ..quadraticBezierTo(22, -16, 36, 0)
    ..quadraticBezierTo(0, 8, -36, 0)
    ..close();
  c.drawPath(dip, _grad(const Rect.fromLTRB(-36, -16, 36, 8), const [Color(0xFFAED581), Color(0xFF689F38)]));
  for (final o in const [Offset(-14, -4), Offset(6, -6), Offset(18, -2)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 4, height: 4), const Radius.circular(1)), _p(const Color(0xFFE53935)));
  }
  for (final o in const [Offset(-4, -2), Offset(12, -8), Offset(-22, -4)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 4, height: 3), const Radius.circular(1)), _p(const Color(0xFFFFFFFF)));
  }
  c.drawCircle(const Offset(-10, -8), 2.5, _p(const Color(0x66FFFFFF)));
}

void _quesa(Canvas c) {
  _plate(c, y: 22, w: 100);
  for (final w in const [(-18.0, 8.0, -0.2), (16.0, 10.0, 0.25), (0.0, -6.0, 0.0)]) {
    c.save();
    c.translate(w.$1, w.$2);
    c.rotate(w.$3);
    // phô mai chảy ra mép
    c.drawPath(
      Path()
        ..moveTo(-20, 10)
        ..quadraticBezierTo(-18, 16, -12, 14)
        ..quadraticBezierTo(-6, 18, 0, 13)
        ..lineTo(0, 10)
        ..close(),
      _p(const Color(0xFFFFC107)),
    );
    final wedge = Path()
      ..moveTo(-22, 10)
      ..lineTo(22, 10)
      ..quadraticBezierTo(18, -18, 0, -20)
      ..close();
    c.drawPath(wedge, _grad(const Rect.fromLTRB(-22, -20, 22, 10), const [Color(0xFFFFE0A0), Color(0xFFE6A84A)]));
    for (var k = 0; k < 3; k++) {
      c.drawLine(Offset(-10 + k * 9.0, 6), Offset(-2 + k * 9.0, -10), _st(const Color(0x8890581E), 2.4));
    }
    c.restore();
  }
  // chén salsa
  c.drawOval(Rect.fromCenter(center: const Offset(34, 0), width: 22, height: 12), _p(Colors.white));
  c.drawOval(Rect.fromCenter(center: const Offset(34, -1), width: 16, height: 7), _p(const Color(0xFFD84315)));
}

// ------------------------------------------------------------------ xe đồ ăn
void _fries(Canvas c, double x, double y, double s) {
  c.save();
  c.translate(x, y);
  c.scale(s);
  _shadow(c, 38, 56);
  // que khoai
  final rr = Random(12);
  for (var k = 0; k < 11; k++) {
    final fx = -20 + k * 4.0 + rr.nextDouble() * 2;
    final top = -40 + rr.nextDouble() * 16;
    final rot = (fx / 24) * 0.25;
    c.save();
    c.translate(fx, 0);
    c.rotate(rot);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-3, top, 3, 4), const Radius.circular(1.5)), _grad(Rect.fromLTRB(-3, top, 3, 4), const [Color(0xFFFFE082), Color(0xFFF9A825)]));
    c.restore();
  }
  // hộp giấy đỏ
  final box = Path()
    ..moveTo(-26, -8)
    ..quadraticBezierTo(0, 2, 26, -8)
    ..lineTo(18, 38)
    ..lineTo(-18, 38)
    ..close();
  c.drawPath(box, _grad(const Rect.fromLTRB(-26, -8, 26, 38), const [Color(0xFFEF5350), Color(0xFFC62828)]));
  c.drawCircle(const Offset(0, 18), 7, _p(const Color(0xFFFFD54F)));
  c.drawCircle(const Offset(0, 18), 4, _p(const Color(0xFFEF5350)));
  c.drawLine(const Offset(-18, 2), const Offset(-14, 30), _st(const Color(0x44FFFFFF), 3));
  c.restore();
}

void _hotdog(Canvas c) {
  _plate(c, y: 22, w: 100);
  c.save();
  c.rotate(-0.12);
  // bánh mì dưới
  final bun = RRect.fromRectAndRadius(const Rect.fromLTRB(-42, -2, 42, 20), const Radius.circular(11));
  c.drawRRect(bun, _grad(bun.outerRect, const [Color(0xFFF6C27A), Color(0xFFC98A3C)]));
  // xúc xích
  final dog = RRect.fromRectAndRadius(const Rect.fromLTRB(-46, -10, 46, 6), const Radius.circular(8));
  c.drawRRect(dog, _grad(dog.outerRect, const [Color(0xFFE57355), Color(0xFFA63A22)]));
  c.drawLine(const Offset(-38, -6), const Offset(36, -6), _st(const Color(0x55FFFFFF), 2));
  // mù tạt + tương cà ziczac
  final mus = Path()..moveTo(-36, -4);
  for (var k = 0; k < 9; k++) {
    mus.lineTo(-32 + k * 8.0, k.isEven ? -9 : 0);
  }
  c.drawPath(mus, _st(const Color(0xFFFFD600), 3.2));
  final ket = Path()..moveTo(-34, -1);
  for (var k = 0; k < 9; k++) {
    ket.lineTo(-30 + k * 8.0, k.isEven ? 1 : -6);
  }
  c.drawPath(ket, _st(const Color(0xFFD50000), 2.2));
  // mép bánh trên
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-42, 4, 42, 12), const Radius.circular(5)), _p(const Color(0xFFF2B866)));
  c.restore();
}

void _burger(Canvas c, double x, double y, double s) {
  c.save();
  c.translate(x, y);
  c.scale(s);
  _shadow(c, 36, 84);
  // bánh dưới
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-36, 18, 36, 32), const Radius.circular(7)), _grad(const Rect.fromLTRB(-36, 18, 36, 32), const [Color(0xFFF2B866), Color(0xFFC98A3C)]));
  // thịt
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-38, 6, 38, 20), const Radius.circular(7)), _grad(const Rect.fromLTRB(-38, 6, 38, 20), const [Color(0xFF6D3A1F), Color(0xFF3E1F0E)]));
  // phô mai chảy
  c.drawPath(
    Path()
      ..moveTo(-38, 4)
      ..lineTo(38, 4)
      ..lineTo(34, 10)
      ..lineTo(26, 16)
      ..lineTo(20, 9)
      ..lineTo(-6, 9)
      ..lineTo(-12, 17)
      ..lineTo(-18, 9)
      ..lineTo(-36, 9)
      ..close(),
    _p(const Color(0xFFFFC107)),
  );
  // cà chua
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-34, -2, 34, 5), const Radius.circular(3)), _p(const Color(0xFFE53935)));
  // xà lách
  final lettuce = Path()..moveTo(-40, -2);
  for (var k = 0; k <= 16; k++) {
    lettuce.lineTo(-40 + k * 5.0, k.isEven ? -6 : 2);
  }
  lettuce
    ..lineTo(40, -6)
    ..lineTo(-40, -6)
    ..close();
  c.drawPath(lettuce, _p(const Color(0xFF7CB342)));
  // bánh trên có mè
  final top = Path()
    ..moveTo(-38, -4)
    ..quadraticBezierTo(-38, -36, 0, -36)
    ..quadraticBezierTo(38, -36, 38, -4)
    ..close();
  c.drawPath(top, _grad(const Rect.fromLTRB(-38, -36, 38, -4), const [Color(0xFFF8C77E), Color(0xFFD38C35)]));
  for (final o in const [Offset(-18, -24), Offset(-4, -30), Offset(10, -26), Offset(22, -18), Offset(-26, -14), Offset(4, -18), Offset(-10, -14)]) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(o.dx * 0.05);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 5, height: 2.6), _p(const Color(0xFFFFF8E1)));
    c.restore();
  }
  c.drawOval(Rect.fromCenter(center: const Offset(-14, -28), width: 16, height: 5), _p(const Color(0x55FFFFFF)));
  c.restore();
}

void _combo(Canvas c) {
  final tray = RRect.fromRectAndRadius(const Rect.fromLTRB(-50, 14, 50, 38), const Radius.circular(8));
  _shadow(c, 40, 100);
  c.drawRRect(tray, _grad(tray.outerRect, const [Color(0xFFEF5350), Color(0xFFB71C1C)]));
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-46, 16, 46, 26), const Radius.circular(6)), _p(const Color(0x33FFFFFF)));
  _fries(c, 28, -6, 0.62);
  _burger(c, -14, -2, 0.62);
}

// ------------------------------------------------------------------ món từ khu vườn
void _melonWedge(Canvas c, double x, double y, double s, double rot) {
  c.save();
  c.translate(x, y);
  c.rotate(rot);
  final rind = Path()
    ..moveTo(-s * 0.5, 0)
    ..arcToPoint(Offset(s * 0.5, 0), radius: Radius.circular(s * 0.5), clockwise: false)
    ..close();
  c.drawPath(rind, _p(const Color(0xFF2E7D32)));
  final white = Path()
    ..moveTo(-s * 0.44, 0)
    ..arcToPoint(Offset(s * 0.44, 0), radius: Radius.circular(s * 0.44), clockwise: false)
    ..close();
  c.drawPath(white, _p(const Color(0xFFE8F5C8)));
  final red = Path()
    ..moveTo(-s * 0.4, 0)
    ..arcToPoint(Offset(s * 0.4, 0), radius: Radius.circular(s * 0.4), clockwise: false)
    ..close();
  c.drawPath(red, _grad(Rect.fromLTRB(-s * 0.4, 0, s * 0.4, s * 0.4), const [Color(0xFFFF5252), Color(0xFFE53935)]));
  for (var k = 0; k < 5; k++) {
    final a = 0.5 + k * 0.5;
    c.drawOval(Rect.fromCenter(center: Offset(cos(a) * s * 0.22, sin(a) * s * 0.2), width: s * 0.05, height: s * 0.08), _p(const Color(0xFF212121)));
  }
  c.restore();
}

void _gMelon(Canvas c, double t) {
  _shadow(c, 40, 56);
  final glass = _tallGlass(-26, 38, 50, 40);
  c.save();
  c.clipPath(glass);
  c.drawRect(const Rect.fromLTRB(-30, -14, 30, 40), _grad(const Rect.fromLTRB(-30, -14, 30, 40), const [Color(0xFFFF6F6F), Color(0xFFD32F2F)]));
  c.drawRect(const Rect.fromLTRB(-30, -16, 30, -12), _p(const Color(0x66FFCDD2)));
  c.restore();
  _ice(c, -10, -6, 13, 0.3);
  _ice(c, 8, 2, 12, -0.4);
  _ice(c, -2, 14, 11, 0.7);
  c.drawPath(glass, _p(const Color(0x22FFFFFF)));
  c.drawPath(glass, _st(const Color(0xAAFFFFFF), 1.6));
  // miếng dưa hấu cài miệng ly
  _melonWedge(c, -16, -26, 34, 3.6);
  // ống hút
  c.save();
  c.translate(12, -30);
  c.rotate(0.3);
  c.drawRect(const Rect.fromLTWH(-3, -22, 6, 34), _p(const Color(0xFF66BB6A)));
  c.restore();
  _glassShine(c, -24, 34, 46);
}

void _gMango(Canvas c, double t) {
  _shadow(c, 42, 50);
  final glass = Path()
    ..moveTo(-24, -18)
    ..lineTo(24, -18)
    ..quadraticBezierTo(22, 30, 10, 38)
    ..lineTo(-10, 38)
    ..quadraticBezierTo(-22, 30, -24, -18)
    ..close();
  c.drawPath(glass, _grad(const Rect.fromLTRB(-24, -18, 24, 38), const [Color(0xFFFFD54F), Color(0xFFFF9800)]));
  c.drawLine(const Offset(-20, 2), const Offset(20, 2), _st(const Color(0x55FFF59D), 3));
  c.drawLine(const Offset(0, 38), const Offset(0, 44), _st(const Color(0xCCFFFFFF), 4));
  c.drawOval(Rect.fromCenter(center: const Offset(0, 45), width: 30, height: 6), _p(const Color(0xCCFFFFFF)));
  // xoài cắt hạt lựu trên mặt
  for (final o in const [Offset(-12, -22), Offset(0, -25), Offset(12, -22), Offset(-6, -30), Offset(7, -31)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 11, height: 10), const Radius.circular(3)), _p(const Color(0xFFFFB300)));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o - const Offset(1, 1.5), width: 6, height: 4), const Radius.circular(2)), _p(const Color(0x88FFF59D)));
  }
  // lá bạc hà
  c.drawOval(Rect.fromCenter(center: const Offset(-2, -38), width: 12, height: 6), _p(const Color(0xFF43A047)));
  c.drawOval(Rect.fromCenter(center: const Offset(6, -37), width: 10, height: 5), _p(const Color(0xFF66BB6A)));
  c.save();
  c.translate(16, -28);
  c.rotate(0.35);
  c.drawRect(const Rect.fromLTWH(-3, -24, 6, 30), _p(Colors.white));
  for (var k = 0; k < 4; k++) {
    c.drawRect(Rect.fromLTWH(-3, -22 + k * 7.0, 6, 3), _p(const Color(0xFFFF9800)));
  }
  c.restore();
  _glassShine(c, -18, 30, 44);
}

void _dragonCube(Canvas c, double x, double y, double s) {
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: s, height: s * 0.85), Radius.circular(s * 0.25)), _p(const Color(0xFFD81B60)));
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x - s * 0.1, y - s * 0.12), width: s * 0.5, height: s * 0.3), Radius.circular(s * 0.12)), _p(const Color(0x55FF80AB)));
  for (var k = 0; k < 4; k++) {
    c.drawCircle(Offset(x + (k % 2 - 0.5) * s * 0.4, y + (k ~/ 2 - 0.5) * s * 0.35), s * 0.06, _p(const Color(0xFF212121)));
  }
}

void _gDragon(Canvas c, double t) {
  _shadow(c, 34, 92);
  // nửa quả thanh long phía sau
  c.save();
  c.translate(26, -6);
  c.rotate(0.35);
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: 40, height: 30), _p(const Color(0xFFEC407A)));
  for (var k = 0; k < 5; k++) {
    final a = -1.2 + k * 0.6;
    c.drawPath(
      Path()
        ..moveTo(cos(a) * 18, sin(a) * 13)
        ..lineTo(cos(a) * 26, sin(a) * 18 - 4)
        ..lineTo(cos(a + 0.25) * 18, sin(a + 0.25) * 13)
        ..close(),
      _p(const Color(0xFF8BC34A)),
    );
  }
  c.drawOval(Rect.fromCenter(center: const Offset(-2, 0), width: 32, height: 22), _p(const Color(0xFFC2185B)));
  for (var k = 0; k < 10; k++) {
    c.drawCircle(Offset(-12 + (k % 5) * 5.0, -4 + (k ~/ 5) * 7.0), 1.1, _p(const Color(0xFF212121)));
  }
  c.restore();
  // bát sữa chua
  final bowl = Path()
    ..moveTo(-40, 4)
    ..quadraticBezierTo(-36, 34, 0, 36)
    ..quadraticBezierTo(36, 34, 40, 4)
    ..close();
  c.drawPath(bowl, _grad(const Rect.fromLTRB(-40, 4, 40, 36), const [Color(0xFFE3F2FD), Color(0xFF90CAF9)]));
  c.drawOval(Rect.fromCenter(center: const Offset(0, 4), width: 80, height: 18), _p(const Color(0xFFBBDEFB)));
  c.drawOval(Rect.fromCenter(center: const Offset(0, 3), width: 72, height: 14), _p(const Color(0xFFFFFDF5)));
  _dragonCube(c, -18, -2, 13);
  _dragonCube(c, -3, -6, 14);
  _dragonCube(c, 13, -1, 13);
  _dragonCube(c, 4, 4, 12);
  c.drawCircle(const Offset(-26, 4), 4, _p(const Color(0xFF7E57C2)));
  c.drawCircle(const Offset(24, 6), 4, _p(const Color(0xFF7E57C2)));
  c.drawOval(Rect.fromCenter(center: const Offset(-6, -14), width: 10, height: 5), _p(const Color(0xFF43A047)));
}

void _gPine(Canvas c, double t) {
  _plate(c, y: 24, w: 100);
  // lá dứa
  for (var k = 0; k < 5; k++) {
    final a = -0.9 + k * 0.32;
    c.save();
    c.translate(36, -2);
    c.rotate(a);
    c.drawPath(
      Path()
        ..moveTo(0, -4)
        ..quadraticBezierTo(16, -6, 30, 0)
        ..quadraticBezierTo(16, 4, 0, 4)
        ..close(),
      _p(k % 2 == 0 ? const Color(0xFF388E3C) : const Color(0xFF66BB6A)),
    );
    c.restore();
  }
  // vỏ dứa bổ đôi làm thuyền
  final shell = Path()
    ..moveTo(-44, 2)
    ..quadraticBezierTo(-40, 26, 0, 28)
    ..quadraticBezierTo(38, 26, 42, 2)
    ..close();
  c.drawPath(shell, _grad(const Rect.fromLTRB(-44, 2, 42, 28), const [Color(0xFFE0A030), Color(0xFF9C6A1E)]));
  c.save();
  c.clipPath(shell);
  for (var k = 0; k < 10; k++) {
    final x = -44 + k * 10.0;
    c.drawLine(Offset(x, 2), Offset(x + 14, 30), _st(const Color(0x66704010), 1.5));
    c.drawLine(Offset(x + 14, 2), Offset(x, 30), _st(const Color(0x66704010), 1.5));
  }
  c.restore();
  c.drawOval(Rect.fromCenter(center: const Offset(-1, 2), width: 86, height: 12), _p(const Color(0xFFFFE082)));
  // cơm chiên vàng vun đầy
  final mound = Path()
    ..moveTo(-38, 4)
    ..quadraticBezierTo(-30, -24, 0, -24)
    ..quadraticBezierTo(30, -24, 36, 4)
    ..close();
  c.drawPath(mound, _grad(const Rect.fromLTRB(-38, -24, 36, 4), const [Color(0xFFFFE57F), Color(0xFFF2B33D)]));
  final rr = Random(41);
  for (var k = 0; k < 34; k++) {
    final x = -32 + rr.nextDouble() * 62;
    final y = -20 + rr.nextDouble() * 22 + (x.abs() / 36) * 8;
    c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4, height: 2.6), _p(const Color(0xFFFFF8DC)));
  }
  // miếng dứa, tôm, đậu
  for (var k = 0; k < 7; k++) {
    final x = -26 + rr.nextDouble() * 50;
    final y = -16 + rr.nextDouble() * 16;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: 7, height: 6), const Radius.circular(2)), _p(const Color(0xFFFFCA28)));
  }
  for (var k = 0; k < 6; k++) {
    c.drawCircle(Offset(-24 + rr.nextDouble() * 46, -14 + rr.nextDouble() * 14), 2.6, _p(const Color(0xFF7CB342)));
  }
  for (final o in const [Offset(-12, -18), Offset(10, -14)]) {
    c.drawArc(Rect.fromCenter(center: o, width: 14, height: 12), 0.3, 4.2, false, _st(const Color(0xFFFF7043), 4));
  }
  _steam(c, t, 0, -26, n: 2, h: 18);
}

void _gDuck(Canvas c, double t) {
  _plate(c, y: 20, w: 100);
  // lá xà lách lót đĩa
  for (var k = 0; k < 3; k++) {
    c.drawOval(Rect.fromCenter(center: Offset(-26 + k * 26.0, 16), width: 34, height: 12), _p(const Color(0xFF8BC34A)));
  }
  // thân vịt quay bóng mật ong
  final body = Rect.fromCenter(center: const Offset(-6, -2), width: 66, height: 40);
  c.drawOval(body, _grad(body, const [Color(0xFFD9692B), Color(0xFF8D3A14)]));
  c.drawOval(Rect.fromCenter(center: const Offset(-14, -12), width: 30, height: 9), _p(const Color(0x66FFD180)));
  // đùi vịt
  c.save();
  c.translate(24, 6);
  c.rotate(-0.5);
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: 26, height: 18), _grad(const Rect.fromLTRB(-13, -9, 13, 9), const [Color(0xFFCC5A20), Color(0xFF7A3010)]));
  c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, -3, 12, 6), const Radius.circular(3)), _p(const Color(0xFFFFF3E0)));
  c.drawCircle(const Offset(23, -3), 3.5, _p(const Color(0xFFFFF3E0)));
  c.drawCircle(const Offset(23, 3), 3.5, _p(const Color(0xFFFFF3E0)));
  c.restore();
  // vài lát thịt đã chặt
  for (var k = 0; k < 3; k++) {
    final o = Offset(-36 + k * 11.0, 14);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 10, height: 8), const Radius.circular(2)), _p(const Color(0xFFB04A1C)));
    c.drawRect(Rect.fromCenter(center: o + const Offset(0, 2), width: 8, height: 3), _p(const Color(0xFFFFE0B2)));
  }
  // hành lá + ớt
  c.drawLine(const Offset(-20, -22), const Offset(-8, -26), _st(const Color(0xFF43A047), 2.5));
  c.drawLine(const Offset(-14, -20), const Offset(-2, -25), _st(const Color(0xFF66BB6A), 2.5));
  c.drawCircle(const Offset(6, -20), 2.5, _p(const Color(0xFFE53935)));
  _steam(c, t, -6, -26, n: 2, h: 18);
}

void _gBeef(Canvas c, double t) {
  // thớt gỗ + chảo gang nóng
  final board = RRect.fromRectAndRadius(const Rect.fromLTRB(-48, -6, 48, 36), const Radius.circular(10));
  c.drawRRect(board.shift(const Offset(0, 4)), _p(const Color(0x30000000)));
  c.drawRRect(board, _grad(board.outerRect, const [Color(0xFFC08A55), Color(0xFF8D5A2B)]));
  final pan = Rect.fromCenter(center: const Offset(0, 10), width: 84, height: 40);
  c.drawOval(pan, _p(const Color(0xFF263238)));
  c.drawOval(pan.deflate(4), _p(const Color(0xFF37474F)));
  // miếng bò bít tết vân mỡ
  final steak = Path()
    ..moveTo(-30, 4)
    ..quadraticBezierTo(-32, -14, -6, -14)
    ..quadraticBezierTo(22, -16, 28, -2)
    ..quadraticBezierTo(30, 16, 4, 18)
    ..quadraticBezierTo(-26, 20, -30, 4)
    ..close();
  c.drawPath(steak, _grad(const Rect.fromLTRB(-32, -16, 30, 20), const [Color(0xFF8D4A2B), Color(0xFF5D2A16)]));
  c.save();
  c.clipPath(steak);
  for (var k = 0; k < 5; k++) {
    c.drawLine(Offset(-30 + k * 14.0, -16), Offset(-40 + k * 14.0, 20), _st(const Color(0xFF3E1A0C), 3));
  }
  c.drawLine(const Offset(-20, -2), const Offset(12, 6), _st(const Color(0x88FFE0C8), 1.5));
  c.drawLine(const Offset(-10, 8), const Offset(16, -6), _st(const Color(0x66FFE0C8), 1.2));
  c.restore();
  // bơ đang tan, tỏi, hương thảo
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(-4, -6), width: 12, height: 8), const Radius.circular(2)), _p(const Color(0xFFFFE082)));
  c.drawOval(Rect.fromCenter(center: const Offset(-4, -2), width: 18, height: 5), _p(const Color(0x88FFD54F)));
  for (final o in const [Offset(-30, 18), Offset(30, 16), Offset(34, 6)]) {
    c.drawOval(Rect.fromCenter(center: o, width: 9, height: 7), _p(const Color(0xFFFFF8E1)));
    c.drawLine(o - const Offset(0, 3), o + const Offset(0, 3), _st(const Color(0x33000000), 1));
  }
  c.drawLine(const Offset(14, 14), const Offset(32, -8), _st(const Color(0xFF2E7D32), 2));
  for (var k = 0; k < 6; k++) {
    final x = 16 + k * 3.0;
    final y = 12 - k * 3.6;
    c.drawLine(Offset(x, y), Offset(x - 4, y - 3), _st(const Color(0xFF388E3C), 1.6));
    c.drawLine(Offset(x, y), Offset(x + 4, y + 1), _st(const Color(0xFF388E3C), 1.6));
  }
  _steam(c, t, -2, -18, n: 3, h: 22);
}

void _gSalmon(Canvas c, double t) {
  _plate(c, y: 20, w: 100);
  // măng tây
  for (var k = 0; k < 4; k++) {
    final y = 8 + k * 4.0;
    c.drawLine(Offset(-40, y), Offset(-6, y - 6), _st(const Color(0xFF558B2F), 4));
    c.drawOval(Rect.fromCenter(center: Offset(-5, y - 6), width: 7, height: 5), _p(const Color(0xFF33691E)));
  }
  // miếng cá hồi áp chảo
  final fillet = RRect.fromRectAndRadius(const Rect.fromLTRB(-20, -16, 30, 12), const Radius.circular(10));
  c.drawRRect(fillet, _grad(fillet.outerRect, const [Color(0xFFFF8A65), Color(0xFFF4511E)]));
  c.save();
  c.clipRRect(fillet);
  for (var k = 0; k < 6; k++) {
    final x = -16 + k * 9.0;
    c.drawArc(Rect.fromCenter(center: Offset(x, -2), width: 14, height: 34), -0.8, 1.6, false, _st(const Color(0xCCFFE0D0), 1.8));
  }
  c.drawRect(const Rect.fromLTRB(-20, -16, 30, -10), _p(const Color(0x66A0400F)));
  c.restore();
  c.drawRRect(fillet, _st(const Color(0x33000000), 1));
  // lát chanh
  c.save();
  c.translate(30, 14);
  c.drawCircle(Offset.zero, 9, _p(const Color(0xFFFFEB3B)));
  c.drawCircle(Offset.zero, 7, _p(const Color(0xFFFFF59D)));
  for (var k = 0; k < 6; k++) {
    final a = k * pi / 3;
    c.drawLine(Offset.zero, Offset(cos(a) * 7, sin(a) * 7), _st(const Color(0xFFFFEB3B), 1));
  }
  c.restore();
  // rau thơm
  c.drawOval(Rect.fromCenter(center: const Offset(4, -18), width: 10, height: 5), _p(const Color(0xFF43A047)));
  c.drawOval(Rect.fromCenter(center: const Offset(10, -20), width: 8, height: 4), _p(const Color(0xFF66BB6A)));
  _steam(c, t, 6, -22, n: 2, h: 18);
}

void _gLobster(Canvas c, double t) {
  _shadow(c, 30, 96);
  final plate = Rect.fromCenter(center: const Offset(0, 22), width: 104, height: 34);
  c.drawOval(plate, _p(Colors.white));
  c.drawOval(plate, _st(const Color(0x22000000), 1.2));
  // càng tôm
  for (final s in const [-1.0, 1.0]) {
    c.save();
    c.translate(s * 24, 4);
    c.rotate(s * 1.0);
    c.drawOval(Rect.fromCenter(center: const Offset(0, -6), width: 16, height: 24), _p(const Color(0xFFD84315)));
    c.drawLine(const Offset(0, -16), Offset(s * 4, -26), _st(const Color(0xFFBF360C), 4));
    c.drawLine(const Offset(0, -16), Offset(-s * 3, -25), _st(const Color(0xFFBF360C), 3.5));
    c.restore();
  }
  // thân tôm hùm bổ đôi, phủ phô mai
  for (final s in const [-1.0, 1.0]) {
    final half = Path()
      ..moveTo(s * 2, -14)
      ..quadraticBezierTo(s * 22, -12, s * 20, 10)
      ..lineTo(s * 12, 30)
      ..lineTo(s * 2, 30)
      ..close();
    c.drawPath(half, _grad(const Rect.fromLTRB(-22, -14, 22, 30), const [Color(0xFFE64A19), Color(0xFFBF360C)]));
    final cheese = Path()
      ..moveTo(s * 4, -10)
      ..quadraticBezierTo(s * 17, -8, s * 16, 8)
      ..lineTo(s * 10, 24)
      ..lineTo(s * 4, 24)
      ..close();
    c.drawPath(cheese, _grad(const Rect.fromLTRB(-17, -10, 17, 24), const [Color(0xFFFFE082), Color(0xFFFFB300)]));
    for (var k = 0; k < 4; k++) {
      c.drawCircle(Offset(s * (7 + (k % 2) * 4.0), -4 + k * 7.0), 2, _p(const Color(0xAA8D5A1E)));
    }
  }
  // đuôi
  for (var k = 0; k < 3; k++) {
    c.drawOval(Rect.fromCenter(center: Offset((k - 1) * 7.0, 34), width: 9, height: 7), _p(const Color(0xFFD84315)));
  }
  // rau mùi tây
  c.drawCircle(const Offset(-2, -16), 3, _p(const Color(0xFF43A047)));
  c.drawCircle(const Offset(3, -18), 2.5, _p(const Color(0xFF66BB6A)));
  _steam(c, t, 0, -22, n: 2, h: 18);
}

// ------------------------------------------------------------------ widget
/// Hình món ăn dùng trong giao diện Flutter (phiếu order, cửa hàng, bảng thao tác)
class DishIcon extends StatelessWidget {
  final String id;
  final double size;
  final bool burnt;
  const DishIcon(this.id, {super.key, this.size = 40, this.burnt = false});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _DishPainter(id, burnt)));
}

class _DishPainter extends CustomPainter {
  final String id;
  final bool burnt;
  _DishPainter(this.id, this.burnt);
  @override
  void paint(Canvas canvas, Size size) => drawDish(canvas, id, size.center(Offset.zero), size.shortestSide * 0.92, t: 0.3, burnt: burnt);
  @override
  bool shouldRepaint(covariant _DishPainter oldDelegate) => oldDelegate.id != id || oldDelegate.burnt != burnt;
}
