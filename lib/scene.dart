// Cảnh nhà hàng 2D vẽ bằng CustomPainter: nhân vật biết đi, ngồi, gọi món, ăn;
// bếp có lửa, hơi nước, khói. Không cần thêm thư viện hay file ảnh nào.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'data.dart';
import 'dishes.dart';
import 'models.dart';
import 'sound.dart';

// =====================================================================
//  TIỆN ÍCH VẼ
// =====================================================================
final Map<String, TextPainter> _tpCache = {};

TextPainter _text(String s, double size, {Color color = const Color(0xFF000000), bool bold = false}) {
  final sz = max(6.0, size).roundToDouble();
  final key = '$s|$sz|${color.hashCode}|$bold';
  if (_tpCache.length > 400) _tpCache.clear();
  return _tpCache.putIfAbsent(
    key,
    () => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: sz, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );
}

Color _a(Color c, double o) => c.withAlpha((o.clamp(0.0, 1.0) * 255).round());
Color _dk(Color c, [double k = 0.25]) => Color.lerp(c, Colors.black, k)!;
Color _lt(Color c, [double k = 0.25]) => Color.lerp(c, Colors.white, k)!;

void _emoji(Canvas c, String e, Offset center, double size, {double alpha = 1}) {
  if (alpha <= 0.01) return;
  final tp = _text(e, size);
  final o = center - Offset(tp.width / 2, tp.height / 2);
  if (alpha >= 0.99) {
    tp.paint(c, o);
    return;
  }
  c.saveLayer(Rect.fromLTWH(o.dx - 2, o.dy - 2, tp.width + 4, tp.height + 4), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
  tp.paint(c, o);
  c.restore();
}

void _pill(Canvas c, String s, Offset center, double size, {Color bg = Colors.white, Color fg = const Color(0xFF3E2723), Color? border}) {
  final tp = _text(s, size, color: fg, bold: true);
  final rect = Rect.fromCenter(center: center, width: tp.width + size * 1.1, height: tp.height + size * 0.6);
  final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
  c.drawRRect(rr.shift(const Offset(0, 1.5)), Paint()..color = const Color(0x33000000));
  c.drawRRect(rr, Paint()..color = bg);
  if (border != null) {
    c.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = border);
  }
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

void _bubble(Canvas c, Offset center, double bw, double bh, Color fill, {Color? border}) {
  final rect = Rect.fromCenter(center: center, width: bw, height: bh);
  final rr = RRect.fromRectAndRadius(rect, Radius.circular(bh * 0.35));
  final tail = Path()
    ..moveTo(rect.left + bw * 0.18, rect.bottom - 2)
    ..lineTo(rect.left - bw * 0.15, rect.bottom + bh * 0.3)
    ..lineTo(rect.left + bw * 0.45, rect.bottom - 2)
    ..close();
  c.drawRRect(rr.shift(const Offset(0, 2)), Paint()..color = const Color(0x33000000));
  final p = Paint()..color = fill;
  c.drawPath(tail, p);
  c.drawRRect(rr, p);
  if (border != null) {
    c.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = border);
  }
}

// =====================================================================
//  MÀU THEO TỪNG LOẠI QUÁN
// =====================================================================
class VTheme {
  final Color floorA, floorB, wall, trim, wood, cloth, accent;
  const VTheme(this.floorA, this.floorB, this.wall, this.trim, this.wood, this.cloth, this.accent);
}

const Map<String, VTheme> _themes = {
  'cafe': VTheme(Color(0xFFEAD7B7), Color(0xFFDCC49C), Color(0xFF9C6B4E), Color(0xFF5D3A26), Color(0xFF8D5B3C), Color(0xFFFFF6E5), Color(0xFFE6A15A)),
  'bakery': VTheme(Color(0xFFFCE4EC), Color(0xFFF8D0DE), Color(0xFFF4A7B9), Color(0xFFB0577A), Color(0xFFC48A6A), Color(0xFFFFFFFF), Color(0xFFFF80AB)),
  'chinese': VTheme(Color(0xFFF3E0C0), Color(0xFFE8CFA2), Color(0xFFB71C1C), Color(0xFF6D0F0F), Color(0xFF6D3B1F), Color(0xFFFFE9B0), Color(0xFFFFC107)),
  'mexican': VTheme(Color(0xFFF6D7B0), Color(0xFFE9BF8C), Color(0xFF1E8A8A), Color(0xFF0D5555), Color(0xFFA0522D), Color(0xFFFFF3E0), Color(0xFFFF7043)),
  'truck': VTheme(Color(0xFFB0BEC5), Color(0xFFA2B1B9), Color(0xFFFFC107), Color(0xFF37474F), Color(0xFF78909C), Color(0xFFECEFF1), Color(0xFFFF5722)),
};

VTheme vtheme(String id) => _themes[id] ?? _themes['cafe']!;

/// Hoạt cảnh trang trí nhà hàng (chọn trong Cửa hàng)
class SceneStyle {
  final String id, name, emoji, desc;
  final int cost;
  const SceneStyle(this.id, this.name, this.emoji, this.desc, this.cost);
}

const sceneStyles = [
  SceneStyle('classic', 'Cổ điển', '🏠', 'Màu theo từng loại quán, cờ dây rực rỡ', 0),
  SceneStyle('garden', 'Sân vườn', '🌿', 'Sàn cỏ xanh, dây lá, bướm bay', 80),
  SceneStyle('beach', 'Biển xanh', '🏖️', 'Sàn cát, sóng vỗ, chim hải âu', 150),
  SceneStyle('night', 'Đêm lung linh', '🌙', 'Đèn dây lấp lánh, nến trên bàn, đom đóm', 220),
  SceneStyle('sakura', 'Hoa anh đào', '🌸', 'Tông hồng, cánh hoa rơi', 300),
  SceneStyle('tet', 'Tết sum vầy', '🧧', 'Đèn lồng đỏ, hoa mai vàng rơi', 380),
];

const Map<String, VTheme> _styleThemes = {
  'garden': VTheme(Color(0xFFA5D6A7), Color(0xFF96CB98), Color(0xFF7CB342), Color(0xFF4E342E), Color(0xFF8D6E63), Color(0xFFFFFDE7), Color(0xFFFFB74D)),
  'beach': VTheme(Color(0xFFFFE6B8), Color(0xFFFAD9A0), Color(0xFF4FC3F7), Color(0xFF0277BD), Color(0xFFBCAAA4), Color(0xFFFFFFFF), Color(0xFF26C6DA)),
  'night': VTheme(Color(0xFF55507A), Color(0xFF4B4670), Color(0xFF1A237E), Color(0xFF0D1240), Color(0xFF5D4037), Color(0xFFFFF8E1), Color(0xFFFFD54F)),
  'sakura': VTheme(Color(0xFFFFF0F5), Color(0xFFFCE4EC), Color(0xFFF8BBD0), Color(0xFFAD1457), Color(0xFFD7A8A0), Color(0xFFFFFFFF), Color(0xFFF06292)),
  'tet': VTheme(Color(0xFFFFF3E0), Color(0xFFFFE0B2), Color(0xFFC62828), Color(0xFFFFC107), Color(0xFF8D2C1E), Color(0xFFFFF8E1), Color(0xFFFFC107)),
};

VTheme themeFor(String venueId, String style) => _styleThemes[style] ?? vtheme(venueId);

double _fr(double x) => x - x.floorToDouble();

// =====================================================================
//  NHÂN VẬT
// =====================================================================
const _skins = [Color(0xFFFFDBB4), Color(0xFFF1C27D), Color(0xFFE0AC69), Color(0xFFC68642), Color(0xFF8D5524)];
const _hairs = [Color(0xFF2B1B17), Color(0xFF4E342E), Color(0xFF8D6E63), Color(0xFFD4A35A), Color(0xFF212121), Color(0xFFB0413E)];
const _shirts = [
  Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFF81C784), Color(0xFFFFB74D),
  Color(0xFFBA68C8), Color(0xFF4DB6AC), Color(0xFFF06292), Color(0xFF9575CD),
];
const _pants = [Color(0xFF37474F), Color(0xFF3949AB), Color(0xFF5D4037), Color(0xFF455A64)];

const _skirts = [Color(0xFFF48FB1), Color(0xFF9FA8DA), Color(0xFFFFCC80), Color(0xFFA5D6A7), Color(0xFFCE93D8)];
const _bows = [Color(0xFFE91E63), Color(0xFFFF7043), Color(0xFF7E57C2), Color(0xFF29B6F6)];

class Look {
  final Color skin, hair, shirt, pants; // nữ: pants = màu váy
  final int hairStyle; // 0 ngắn, 1 búi, 2 dài, 3 dài + mái (nữ chính), 4 vuốt mái (nam chính)
  final bool female;
  final Color? bow; // nơ cài tóc
  const Look(this.skin, this.hair, this.shirt, this.pants, this.hairStyle, {this.female = false, this.bow});
  factory Look.seed(int seed) {
    final r = Random(seed);
    final female = r.nextBool();
    final skin = _skins[r.nextInt(_skins.length)];
    final hair = _hairs[r.nextInt(_hairs.length)];
    final shirt = _shirts[r.nextInt(_shirts.length)];
    if (female) {
      return Look(skin, hair, shirt, _skirts[r.nextInt(_skirts.length)], 1 + r.nextInt(3),
          female: true, bow: r.nextInt(3) == 0 ? _bows[r.nextInt(_bows.length)] : null);
    }
    return Look(skin, hair, shirt, _pants[r.nextInt(_pants.length)], r.nextInt(3) == 0 ? 4 : 0);
  }
}

const kNguyen = 'Nguyên';
const kNgocAnh = 'Ngọc Anh';

/// Ngọc Anh phục vụ: tóc đen dài có mái, nơ hồng, áo trắng, váy hồng
const ngocAnhLook = Look(Color(0xFFFFE3D3), Color(0xFF2A1A16), Color(0xFFFFFFFF), Color(0xFFF06292), 3, female: true, bow: Color(0xFFE91E63));
/// Ngọc Anh làm bếp: đồng phục trắng, váy hồng, tóc buộc dưới mũ
const ngocAnhChefLook = Look(Color(0xFFFFE3D3), Color(0xFF2A1A16), Color(0xFFFFFFFF), Color(0xFFF48FB1), 3, female: true);
/// Nguyên làm bếp: tóc đen vuốt, đồng phục bếp trắng
const nguyenLook = Look(Color(0xFFF3C9A3), Color(0xFF1B1B1B), Color(0xFFFFFFFF), Color(0xFF37474F), 4);
/// Nguyên phục vụ: gile xanh than, nơ đỏ
const nguyenWaiterLook = Look(Color(0xFFF3C9A3), Color(0xFF1B1B1B), Color(0xFF263238), Color(0xFF212121), 4);

/// Bộ đồ theo người + vai
Look castLook(String name, String role) => name == kNgocAnh
    ? (role == 'chef' ? ngocAnhChefLook : ngocAnhLook)
    : (role == 'chef' ? nguyenLook : nguyenWaiterLook);

/// Vẽ một người kiểu chibi. [p] là điểm chân (hoặc hông nếu [sitting]), [s] ≈ chiều cao.
/// mood: 0 vui, 1 bình thường, 2 tức giận. role: '', 'waiter', 'chef'. [name]: bảng tên trên đầu.
void drawPerson(
  Canvas c,
  Offset p,
  double s,
  Look lk, {
  bool walking = false,
  double phase = 0,
  bool sitting = false,
  int mood = 0,
  bool armUp = false,
  bool facingLeft = false,
  String role = '',
  double bob = 0,
  bool chew = false,
  String? carry,
  double stir = -1,
  String? name,
}) {
  final u = s / 10;
  final fem = lk.female;
  final fill = Paint()..isAntiAlias = true;
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, u * 0.18)
    ..color = const Color(0x40000000);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, u * 0.25)
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFF3E2723);

  if (!sitting) {
    c.drawOval(Rect.fromCenter(center: p, width: 5 * u, height: 1.3 * u), Paint()..color = const Color(0x30000000));
  }
  c.save();
  c.translate(p.dx, p.dy - bob);
  if (facingLeft) c.scale(-1, 1);
  final sw = walking ? sin(phase) : 0.0;
  final hip = sitting ? 0.0 : -3.0 * u;

  // --- Chân ---
  if (!sitting) {
    for (final side in const [-1.0, 1.0]) {
      c.save();
      c.translate(side * 0.8 * u, hip);
      c.rotate(side * sw * 0.5);
      fill.color = fem ? lk.skin : lk.pants;
      final lw = fem ? 0.95 * u : 1.2 * u;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-lw / 2, -0.2 * u, lw, 3.0 * u), Radius.circular(lw / 2)), fill);
      fill.color = fem ? (lk.bow ?? const Color(0xFF8D4E5A)) : const Color(0xFF3E2723);
      c.drawOval(Rect.fromLTWH(-0.6 * u, 2.4 * u, 1.6 * u, 0.8 * u), fill);
      c.restore();
    }
  }

  // --- Tóc dài phía sau (vẽ trước thân) ---
  final top = hip - 3.6 * u;
  final hy = top - 1.6 * u;
  if (fem && role == 'chef') {
    // tóc buộc gọn phía sau
    fill.color = lk.hair;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-1.2 * u, hy - 0.2 * u, 2.4 * u, 2.6 * u), Radius.circular(1.0 * u)), fill);
  } else if (fem && (lk.hairStyle == 2 || lk.hairStyle == 3)) {
    fill.color = lk.hair;
    final len = lk.hairStyle == 3 ? 4.6 * u : 3.6 * u;
    c.drawRRect(RRect.fromLTRBAndCorners(-2.15 * u, hy - 1.2 * u, 2.15 * u, hy + len,
        topLeft: Radius.circular(2.0 * u), topRight: Radius.circular(2.0 * u), bottomLeft: Radius.circular(0.9 * u), bottomRight: Radius.circular(0.9 * u)), fill);
  }

  // --- Thân ---
  final body = RRect.fromLTRBAndCorners(
    (fem ? -1.75 : -2.0) * u, top, (fem ? 1.75 : 2.0) * u, hip + 0.4 * u,
    topLeft: Radius.circular(1.5 * u),
    topRight: Radius.circular(1.5 * u),
    bottomLeft: Radius.circular(0.6 * u),
    bottomRight: Radius.circular(0.6 * u),
  );
  fill.color = lk.shirt;
  c.drawRRect(body, fill);
  c.drawRRect(body, outline);

  // Váy (nữ)
  if (fem) {
    final sk = Path()
      ..moveTo(-1.8 * u, hip - 0.9 * u)
      ..lineTo(1.8 * u, hip - 0.9 * u)
      ..lineTo(2.7 * u, hip + (sitting ? 0.6 : 1.5) * u)
      ..quadraticBezierTo(0, hip + (sitting ? 1.0 : 1.9) * u, -2.7 * u, hip + (sitting ? 0.6 : 1.5) * u)
      ..close();
    fill.color = lk.pants;
    c.drawPath(sk, fill);
    c.drawPath(sk, outline);
    c.drawLine(Offset(-2.4 * u, hip + 1.1 * u), Offset(2.4 * u, hip + 1.1 * u), Paint()
      ..color = _a(Colors.white, 0.6)
      ..strokeWidth = max(1.0, u * 0.2));
  }

  if (role == 'waiter') {
    if (fem) {
      // Tạp dề viền hồng + nơ cổ áo
      final ap = RRect.fromRectAndRadius(Rect.fromLTRB(-1.3 * u, hip - 1.1 * u, 1.3 * u, hip + 1.3 * u), Radius.circular(0.5 * u));
      fill.color = Colors.white;
      c.drawRRect(ap, fill);
      c.drawRRect(ap, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, u * 0.22)
        ..color = const Color(0xFFF8BBD0));
      fill.color = lk.bow ?? const Color(0xFFE91E63);
      c.drawPath(Path()
        ..moveTo(0, top + 0.5 * u)
        ..lineTo(-0.85 * u, top + 0.05 * u)
        ..lineTo(-0.85 * u, top + 0.95 * u)
        ..close(), fill);
      c.drawPath(Path()
        ..moveTo(0, top + 0.5 * u)
        ..lineTo(0.85 * u, top + 0.05 * u)
        ..lineTo(0.85 * u, top + 0.95 * u)
        ..close(), fill);
      c.drawCircle(Offset(0, top + 0.5 * u), 0.25 * u, fill);
    } else {
      fill.color = Colors.white;
      c.drawPath(Path()
        ..moveTo(-0.9 * u, top + 0.2 * u)
        ..lineTo(0.9 * u, top + 0.2 * u)
        ..lineTo(0, top + 2.6 * u)
        ..close(), fill);
      fill.color = const Color(0xFFD32F2F);
      c.drawPath(Path()
        ..moveTo(0, top + 0.6 * u)
        ..lineTo(-0.8 * u, top + 0.15 * u)
        ..lineTo(-0.8 * u, top + 1.05 * u)
        ..close(), fill);
      c.drawPath(Path()
        ..moveTo(0, top + 0.6 * u)
        ..lineTo(0.8 * u, top + 0.15 * u)
        ..lineTo(0.8 * u, top + 1.05 * u)
        ..close(), fill);
      fill.color = Colors.white;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-1.7 * u, hip - 1.4 * u, 1.7 * u, hip + 1.6 * u), Radius.circular(0.3 * u)), fill);
    }
  } else if (role == 'chef') {
    fill.color = const Color(0xFFB0BEC5);
    for (final yy in const [1.2, 2.2, 3.0]) {
      c.drawCircle(Offset(-0.6 * u, top + yy * u), 0.18 * u, fill);
      c.drawCircle(Offset(0.6 * u, top + yy * u), 0.18 * u, fill);
    }
    fill.color = const Color(0xFFE53935);
    c.drawPath(Path()
      ..moveTo(-0.9 * u, top)
      ..lineTo(0.9 * u, top)
      ..lineTo(0, top + 0.9 * u)
      ..close(), fill);
  }

  // --- Tay ---
  for (final side in const [-1.0, 1.0]) {
    double a = sitting ? -side * 0.25 : -side * 0.15 - side * sw * 0.6;
    if (side > 0) {
      if (armUp) a = -2.5;
      if (carry != null) a = -1.35;
      if (stir >= 0) a = -1.0 + 0.35 * sin(stir);
    }
    c.save();
    c.translate(side * (fem ? 1.55 : 1.75) * u, top + 0.9 * u);
    c.rotate(a);
    fill.color = lk.shirt;
    final aw = fem ? 0.95 * u : 1.1 * u;
    final arm = RRect.fromRectAndRadius(Rect.fromLTWH(-aw / 2, -0.3 * u, aw, 3.0 * u), Radius.circular(aw / 2));
    c.drawRRect(arm, fill);
    c.drawRRect(arm, outline);
    fill.color = lk.skin;
    c.drawCircle(Offset(0, 2.9 * u), 0.55 * u, fill);
    c.restore();
  }

  // --- Khay món ---
  if (carry != null) {
    final hand = Offset((fem ? 1.55 : 1.75) * u + 2.83 * u, top + 0.9 * u + 0.63 * u);
    fill.color = const Color(0xFFCFD8DC);
    c.drawOval(Rect.fromCenter(center: hand + Offset(0, -0.4 * u), width: 3.8 * u, height: 0.9 * u), fill);
    c.drawOval(Rect.fromCenter(center: hand + Offset(0, -0.4 * u), width: 3.8 * u, height: 0.9 * u), outline);
    drawDish(c, carry, hand + Offset(0, -1.6 * u), 3.2 * u);
  }

  // --- Đầu ---
  final hr = 1.8 * u; // bán kính đầu (to một chút cho dễ thương)
  fill.color = lk.skin;
  c.drawRect(Rect.fromLTWH(-0.45 * u, top - 0.6 * u, 0.9 * u, 0.8 * u), fill);
  c.drawCircle(Offset(0, hy), hr, fill);
  c.drawCircle(Offset(0, hy), hr, outline);

  // Tóc phía trước
  fill.color = lk.hair;
  if (role != 'chef') {
    c.drawArc(Rect.fromCircle(center: Offset(0, hy - 0.1 * u), radius: hr + 0.12 * u), pi, pi, true, fill);
    if (fem) {
      // mái thưa + tóc mai hai bên
      for (final x in const [-1.15, -0.4, 0.4, 1.15]) {
        c.drawCircle(Offset(x * u, hy - 0.55 * u), 0.55 * u, fill);
      }
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-2.0 * u, hy - 0.8 * u, 0.6 * u, 2.6 * u), Radius.circular(0.3 * u)), fill);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(1.4 * u, hy - 0.8 * u, 0.6 * u, 2.6 * u), Radius.circular(0.3 * u)), fill);
      if (lk.hairStyle == 1) c.drawCircle(Offset(0, hy - 2.1 * u), 0.85 * u, fill);
    } else if (lk.hairStyle == 4) {
      // tóc vuốt mái
      c.drawPath(Path()
        ..moveTo(-1.9 * u, hy - 0.3 * u)
        ..quadraticBezierTo(-1.2 * u, hy - 2.9 * u, 1.4 * u, hy - 2.4 * u)
        ..quadraticBezierTo(2.2 * u, hy - 1.6 * u, 1.9 * u, hy - 0.5 * u)
        ..quadraticBezierTo(0.6 * u, hy - 1.6 * u, -1.9 * u, hy - 0.3 * u)
        ..close(), fill);
    }
  } else {
    // đội mũ bếp: chỉ thấy tóc mai (nữ: thêm mái thưa)
    c.drawRect(Rect.fromLTWH(-1.75 * u, hy - 1.1 * u, 0.45 * u, (fem ? 2.0 : 1.2) * u), fill);
    c.drawRect(Rect.fromLTWH(1.3 * u, hy - 1.1 * u, 0.45 * u, (fem ? 2.0 : 1.2) * u), fill);
    if (fem) {
      for (final x in const [-0.8, 0.0, 0.8]) {
        c.drawCircle(Offset(x * u, hy - 0.8 * u), 0.5 * u, fill);
      }
    }
  }
  // Nơ cài tóc
  if (lk.bow != null && role != 'chef') {
    fill.color = lk.bow!;
    final bc = Offset(1.25 * u, hy - 1.55 * u);
    c.drawPath(Path()
      ..moveTo(bc.dx, bc.dy)
      ..lineTo(bc.dx - 0.9 * u, bc.dy - 0.55 * u)
      ..lineTo(bc.dx - 0.9 * u, bc.dy + 0.55 * u)
      ..close(), fill);
    c.drawPath(Path()
      ..moveTo(bc.dx, bc.dy)
      ..lineTo(bc.dx + 0.9 * u, bc.dy - 0.55 * u)
      ..lineTo(bc.dx + 0.9 * u, bc.dy + 0.55 * u)
      ..close(), fill);
    c.drawCircle(bc, 0.28 * u, Paint()..color = _lt(lk.bow!, 0.3));
  }

  // Mắt to long lanh
  final ey = hy + 0.35 * u;
  for (final sx in const [-1.0, 1.0]) {
    final ec = Offset(sx * 0.68 * u, ey);
    c.drawOval(Rect.fromCenter(center: ec, width: 0.8 * u, height: 0.95 * u), Paint()..color = Colors.white);
    c.drawCircle(ec + Offset(0, 0.06 * u), 0.33 * u, Paint()..color = const Color(0xFF3E2723));
    c.drawCircle(ec + Offset(0.1 * u, -0.1 * u), 0.11 * u, Paint()..color = Colors.white);
    if (fem) {
      c.drawLine(ec + Offset(sx * 0.38 * u, -0.3 * u), ec + Offset(sx * 0.62 * u, -0.55 * u), line);
    }
  }
  // Lông mày
  if (mood == 2) {
    c.drawLine(Offset(-1.05 * u, hy - 0.5 * u), Offset(-0.3 * u, hy - 0.15 * u), line);
    c.drawLine(Offset(1.05 * u, hy - 0.5 * u), Offset(0.3 * u, hy - 0.15 * u), line);
  } else if (!fem) {
    final brow = Paint()
      ..color = lk.hair
      ..strokeWidth = max(1.2, u * 0.32)
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(-1.0 * u, hy - 0.45 * u), Offset(-0.38 * u, hy - 0.5 * u), brow);
    c.drawLine(Offset(1.0 * u, hy - 0.45 * u), Offset(0.38 * u, hy - 0.5 * u), brow);
  }
  // Má hồng
  if (fem || mood == 0) {
    final cheek = Paint()..color = fem ? const Color(0x66FF8A80) : const Color(0x44FF6F61);
    c.drawOval(Rect.fromCenter(center: Offset(-1.1 * u, hy + 0.95 * u), width: 0.75 * u, height: 0.45 * u), cheek);
    c.drawOval(Rect.fromCenter(center: Offset(1.1 * u, hy + 0.95 * u), width: 0.75 * u, height: 0.45 * u), cheek);
  }
  // Miệng
  final my = hy + 1.05 * u;
  final lip = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(1.0, u * 0.22)
    ..strokeCap = StrokeCap.round
    ..color = fem ? const Color(0xFFD84367) : const Color(0xFF3E2723);
  if (chew) {
    c.drawOval(Rect.fromCenter(center: Offset(0, my), width: 0.7 * u, height: 0.5 * u), Paint()..color = const Color(0xFF8D3B3B));
  } else if (mood == 0) {
    c.drawArc(Rect.fromCenter(center: Offset(0, my - 0.3 * u), width: 1.1 * u, height: 0.8 * u), 0.25, pi - 0.5, false, lip);
  } else if (mood == 1) {
    c.drawLine(Offset(-0.4 * u, my), Offset(0.4 * u, my), lip);
  } else {
    c.drawArc(Rect.fromCenter(center: Offset(0, my + 0.3 * u), width: 1.1 * u, height: 0.8 * u), pi + 0.25, pi - 0.5, false, lip);
  }

  // Mũ đầu bếp
  if (role == 'chef') {
    fill.color = Colors.white;
    final hat = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-1.5 * u, hy - 3.25 * u, 3.0 * u, 1.9 * u), Radius.circular(0.3 * u)))
      ..addOval(Rect.fromCircle(center: Offset(-1.0 * u, hy - 3.35 * u), radius: 0.95 * u))
      ..addOval(Rect.fromCircle(center: Offset(0, hy - 3.85 * u), radius: 1.05 * u))
      ..addOval(Rect.fromCircle(center: Offset(1.0 * u, hy - 3.35 * u), radius: 0.95 * u));
    c.drawPath(hat, fill);
    c.drawPath(hat, outline);
    fill.color = const Color(0xFFECEFF1);
    c.drawRect(Rect.fromLTWH(-1.65 * u, hy - 1.8 * u, 3.3 * u, 0.6 * u), fill);
  }
  c.restore();

  // Bảng tên (không bị lật khi nhân vật quay trái)
  if (name != null) {
    final headTop = p.dy - bob + hy - hr - (role == 'chef' ? 3.0 * u : 0.3 * u);
    _pill(
      c,
      name,
      Offset(p.dx, headTop - 0.9 * u),
      max(9.0, u * 1.05),
      bg: fem ? const Color(0xFFFCE4EC) : const Color(0xFFE3F2FD),
      fg: fem ? const Color(0xFFC2185B) : const Color(0xFF1565C0),
    );
  }
}

// =====================================================================
//  TRANG TRÍ ĐỘNG THEO HOẠT CẢNH
// =====================================================================
/// Dải trang trí phía trên tường (cao [band])
void _ambientBack(Canvas c, double w, double band, String style, double t, VTheme th) {
  switch (style) {
    case 'garden':
      c.drawLine(Offset(0, band * 0.3), Offset(w, band * 0.3), Paint()
        ..color = const Color(0xFF33691E)
        ..strokeWidth = 2);
      var k = 0;
      for (double x = 10; x < w; x += 26) {
        _emoji(c, k.isEven ? '🌿' : '🍃', Offset(x, band * 0.55 + sin(t * 1.5 + k) * 1.5), band * 0.75);
        k++;
      }
      break;
    case 'beach':
      c.drawRect(Rect.fromLTWH(0, 0, w, band), Paint()..color = const Color(0xFFB3E5FC));
      final wave = Path()..moveTo(0, band);
      for (double x = 0; x <= w; x += 6) {
        wave.lineTo(x, band * 0.55 + sin(x * 0.05 + t * 2.2) * band * 0.14);
      }
      wave
        ..lineTo(w, band)
        ..close();
      c.drawPath(wave, Paint()..color = const Color(0xFF0288D1));
      _emoji(c, '🕊️', Offset((t * 28) % (w + 40) - 20, band * 0.3 + sin(t * 3) * 2), band * 0.5);
      _emoji(c, '☀️', Offset(w - band * 0.6, band * 0.32), band * 0.5);
      break;
    case 'night':
      _lightString(c, w, band, t, const [Color(0xFFFFEB3B), Color(0xFFFF80AB), Color(0xFF80D8FF), Color(0xFFB9F6CA)]);
      _emoji(c, '🌙', Offset(w * 0.5, band * 0.45), band * 0.55);
      break;
    case 'sakura':
      var k = 0;
      for (double x = 14; x < w; x += 34) {
        _emoji(c, '🌸', Offset(x, band * (k.isEven ? 0.4 : 0.65)), band * 0.6);
        k++;
      }
      break;
    case 'tet':
      c.drawLine(Offset(0, band * 0.12), Offset(w, band * 0.12), Paint()
        ..color = const Color(0xFFFFC107)
        ..strokeWidth = 2);
      final n = max(3, (w / 70).floor());
      for (var k = 0; k < n; k++) {
        final x = w * (k + 0.5) / n + sin(t * 2 + k) * 3;
        c.drawLine(Offset(w * (k + 0.5) / n, band * 0.12), Offset(x, band * 0.35), Paint()
          ..color = const Color(0xFFFFC107)
          ..strokeWidth = 1.2);
        _emoji(c, k.isEven ? '🏮' : '🧧', Offset(x, band * 0.62), band * 0.6);
      }
      break;
    default: // classic: cờ dây
      final cols = [th.accent, Colors.white, _lt(th.wall, 0.4), const Color(0xFFFFD54F)];
      c.drawLine(Offset(0, band * 0.15), Offset(w, band * 0.15), Paint()
        ..color = th.trim
        ..strokeWidth = 1.5);
      var k = 0;
      for (double x = 0; x < w; x += 20) {
        final sway = sin(t * 2 + k * 0.7) * 1.5;
        c.drawPath(
          Path()
            ..moveTo(x + 2, band * 0.15)
            ..lineTo(x + 18, band * 0.15)
            ..lineTo(x + 10 + sway, band * 0.8)
            ..close(),
          Paint()..color = cols[k % cols.length],
        );
        k++;
      }
  }
}

void _lightString(Canvas c, double w, double band, double t, List<Color> cols) {
  final seg = w / 3;
  final wire = Path()..moveTo(0, band * 0.2);
  for (double x = 0; x <= w; x += 4) {
    wire.lineTo(x, band * 0.2 + sin(pi * (x % seg) / seg) * band * 0.45);
  }
  c.drawPath(wire, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = const Color(0xFF263238));
  var k = 0;
  for (double x = 10; x < w; x += 20) {
    final y = band * 0.2 + sin(pi * (x % seg) / seg) * band * 0.45 + 3;
    final a = 0.45 + 0.55 * sin(t * 3 + k * 1.3).abs();
    final col = cols[k % cols.length];
    c.drawCircle(Offset(x, y), 7, Paint()..color = _a(col, a * 0.3));
    c.drawCircle(Offset(x, y), 3, Paint()..color = _a(col, 0.4 + 0.6 * a));
    k++;
  }
}

/// Lớp hiệu ứng nổi phía trước (bướm, đom đóm, cánh hoa rơi)
void _ambientFront(Canvas c, double w, double h, double top, String style, double t, double r) {
  switch (style) {
    case 'garden':
      for (var k = 0; k < 3; k++) {
        final x = (t * (22 + k * 6) + k * 137) % (w + 40) - 20;
        final y = top + (h - top) * (0.15 + 0.6 * _fr(k * 0.37 + 0.2)) + sin(t * 3 + k) * 14;
        _emoji(c, '🦋', Offset(x, y), r * 0.55);
      }
      break;
    case 'night':
      for (var k = 0; k < 12; k++) {
        final x = _fr(k * 0.618) * w + sin(t * 0.5 + k) * 30;
        final y = top + _fr(k * 0.37 + 0.1) * (h - top) + cos(t * 0.7 + k * 2) * 18;
        final a = 0.3 + 0.7 * sin(t * 2.5 + k).abs();
        c.drawCircle(Offset(x, y), 9, Paint()..color = _a(const Color(0xFFFFF59D), a * 0.25));
        c.drawCircle(Offset(x, y), 2.5, Paint()..color = _a(const Color(0xFFFFF59D), a));
      }
      break;
    case 'sakura':
    case 'tet':
      final col = style == 'sakura' ? const Color(0xFFF8BBD0) : const Color(0xFFFFD54F);
      final n = style == 'sakura' ? 22 : 14;
      for (var k = 0; k < n; k++) {
        final x = (_fr(k * 0.618) * w + sin(t * 0.8 + k) * 30 + t * 12) % w;
        final y = (t * (24 + (k % 5) * 7) + _fr(k * 0.37) * h) % (h + 20) - 10;
        c.save();
        c.translate(x, y);
        c.rotate(t * 2 + k);
        c.drawOval(Rect.fromCenter(center: Offset.zero, width: 8, height: 4.5), Paint()..color = _a(col, 0.85));
        c.restore();
      }
      break;
  }
}

/// Mèo con đi dạo trong quán
// ignore: unused_element
void _drawCat(Canvas c, double w, double y, double r, double t) {
  const period = 26.0;
  final ph = (t % period) / period;
  double pos;
  bool moving, right;
  if (ph < 0.4) {
    pos = ph / 0.4;
    moving = true;
    right = true;
  } else if (ph < 0.5) {
    pos = 1;
    moving = false;
    right = true;
  } else if (ph < 0.9) {
    pos = 1 - (ph - 0.5) / 0.4;
    moving = true;
    right = false;
  } else {
    pos = 0;
    moving = false;
    right = false;
  }
  final x = w * 0.08 + pos * w * 0.84;
  c.drawOval(Rect.fromCenter(center: Offset(x, y + r * 0.3), width: r * 0.8, height: r * 0.2), Paint()..color = const Color(0x22000000));
  c.save();
  c.translate(x, y - (moving ? sin(t * 14).abs() * 2 : 0));
  if (right) c.scale(-1, 1);
  _emoji(c, '🐈', Offset.zero, r * 0.85);
  c.restore();
  if (!moving) _emoji(c, '💤', Offset(x + r * 0.4, y - r * 0.6 - sin(t * 2).abs() * 3), r * 0.4, alpha: 0.8);
}

// =====================================================================
//  KHÁCH ĐẶC BIỆT: bộ đồ riêng + bong bóng kể chuyện
// =====================================================================
const Map<String, Look> _npcLooks = {
  'vip': Look(Color(0xFFF1C27D), Color(0xFF9E9E9E), Color(0xFF212121), Color(0xFF212121), 4),
  'critic': Look(Color(0xFFFFDBB4), Color(0xFF6D4C41), Color(0xFF7E57C2), Color(0xFF4A148C), 1, female: true),
  'hunter': Look(Color(0xFFC68642), Color(0xFF3E2723), Color(0xFF558B2F), Color(0xFF5D4037), 0),
  'student': Look(Color(0xFFFFE0CC), Color(0xFF2B1B17), Color(0xFFFFFFFF), Color(0xFF1E88E5), 2, female: true, bow: Color(0xFF1E88E5)),
  'stranger': Look(Color(0xFFE0AC69), Color(0xFF212121), Color(0xFF37474F), Color(0xFF263238), 0),
};

Look custLook(String npc, int seed) => _npcLooks[npc] ?? Look.seed(seed);

/// Bong bóng lời thoại có xuống dòng, đáy ở [anchor]
void _speech(Canvas c, String text, Offset anchor, double maxW, double fs, {Color bg = Colors.white, Color fg = const Color(0xFF3E2723)}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: fs, color: fg, height: 1.25)),
    textDirection: TextDirection.ltr,
    maxLines: 3,
    ellipsis: '…',
  )..layout(maxWidth: maxW);
  final rect = Rect.fromLTWH(anchor.dx - tp.width / 2 - fs * 0.6, anchor.dy - tp.height - fs * 1.4, tp.width + fs * 1.2, tp.height + fs * 0.9);
  final rr = RRect.fromRectAndRadius(rect, Radius.circular(fs * 0.8));
  c.drawRRect(rr.shift(const Offset(0, 2)), Paint()..color = const Color(0x33000000));
  c.drawPath(
    Path()
      ..moveTo(anchor.dx - fs * 0.5, rect.bottom - 1)
      ..lineTo(anchor.dx, anchor.dy)
      ..lineTo(anchor.dx + fs * 0.5, rect.bottom - 1)
      ..close(),
    Paint()..color = bg,
  );
  c.drawRRect(rr, Paint()..color = bg);
  tp.paint(c, Offset(rect.left + fs * 0.6, rect.top + fs * 0.45));
}

/// Vị trí đi dạo của thú cưng (đi qua đi lại, thỉnh thoảng nghỉ)
(Offset, bool, bool) _wander(double t, double w, double y, double period, double offset) {
  final ph = ((t + offset) % period) / period;
  double pos;
  bool moving, right;
  if (ph < 0.4) {
    pos = ph / 0.4;
    moving = true;
    right = true;
  } else if (ph < 0.5) {
    pos = 1;
    moving = false;
    right = true;
  } else if (ph < 0.9) {
    pos = 1 - (ph - 0.5) / 0.4;
    moving = true;
    right = false;
  } else {
    pos = 0;
    moving = false;
    right = false;
  }
  return (Offset(w * 0.08 + pos * w * 0.84, y), moving, right);
}

// =====================================================================
//  BỐ CỤC SẢNH: đảo bếp ở giữa, bàn xếp vòng quanh
// =====================================================================
/// Đảo bếp (toạ độ tương đối trên phần sàn của sảnh)
const islandRel = Rect.fromLTRB(0.29, 0.37, 0.74, 0.60);

double diningWallH(double h) => max(64.0, h * 0.2);

/// Khung đảo bếp tính bằng pixel trong một sảnh kích thước [sz]
Rect islandRectFor(Size sz) {
  final top = diningWallH(sz.height) + 6;
  final fh = sz.height - top;
  return Rect.fromLTRB(sz.width * islandRel.left, top + fh * islandRel.top, sz.width * islandRel.right, top + fh * islandRel.bottom);
}

const maxTablesLayout = 10;

/// Số cột, số hàng bàn
(int, int) _grid(int n) {
  final cols = n <= 4 ? max(n, 1) : (n <= 6 ? 3 : 4);
  return (cols, max(1, (n / cols).ceil()));
}

/// Cỡ bàn theo lưới
double tableRadius(double w, double floorH, int n) {
  final (cols, rows) = _grid(n);
  return min(min(0.86 * w / cols * 0.27, floorH / rows * 0.24), 46.0);
}

/// Vị trí mặc định của bàn thứ [i] trong [n] bàn (toạ độ tương đối trên sàn).
/// Bàn xếp lưới ở 86% bên trái, chừa lối đi bên phải dẫn từ cửa vào.
Offset defaultTablePos(int i, int n) {
  final (cols, rows) = _grid(n);
  return Offset(0.86 * (i % cols + 0.5) / cols, (i ~/ cols + 0.56) / rows);
}

// =====================================================================
//  SẢNH NHÀ HÀNG (vai PHỤC VỤ)
// =====================================================================
// Khách đi ngoài phố (thấy qua cửa sổ) rồi mới vào cửa; khách về thì ra cửa rồi đi tiếp ngoài phố
const _outside = 1.2, _outOutside = 1.2;

/// Lưới tìm đường trên sàn: người và thú cưng đi vòng quanh bàn, đảo bếp, đồ trang trí
class _Nav {
  final double cell, x0, y0;
  final int cols, rows;
  final List<bool> blocked;
  _Nav(this.cell, this.x0, this.y0, this.cols, this.rows, this.blocked);

  factory _Nav.build(Rect area, double cell, List<Rect> obstacles) {
    final cols = max(1, (area.width / cell).floor());
    final rows = max(1, (area.height / cell).floor());
    final b = List<bool>.filled(cols * rows, false);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final p = Offset(area.left + (x + 0.5) * cell, area.top + (y + 0.5) * cell);
        for (final o in obstacles) {
          if (o.contains(p)) {
            b[y * cols + x] = true;
            break;
          }
        }
      }
    }
    return _Nav(cell, area.left, area.top, cols, rows, b);
  }

  int? _idx(Offset p) {
    final cx = ((p.dx - x0) / cell).floor(), cy = ((p.dy - y0) / cell).floor();
    if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) return null;
    return cy * cols + cx;
  }

  Offset _center(int i) => Offset(x0 + (i % cols + 0.5) * cell, y0 + (i ~/ cols + 0.5) * cell);

  bool free(Offset p) {
    final i = _idx(p);
    return i != null && !blocked[i];
  }

  int? _nearest(Offset p) {
    final i = _idx(p);
    if (i != null && !blocked[i]) return i;
    int? best;
    var bd = double.infinity;
    for (var k = 0; k < blocked.length; k++) {
      if (blocked[k]) continue;
      final d = (_center(k) - p).distanceSquared;
      if (d < bd) {
        bd = d;
        best = k;
      }
    }
    return best;
  }

  Offset nearestFree(Offset p) {
    final i = _nearest(p);
    return i == null ? p : (free(p) ? p : _center(i));
  }

  bool _los(Offset a, Offset b) {
    final n = max(1, ((b - a).distance / (cell * 0.35)).ceil());
    for (var k = 1; k < n; k++) {
      if (!free(Offset.lerp(a, b, k / n)!)) return false;
    }
    return true;
  }

  /// Đường đi từ [from] tới [to] (không gồm điểm đầu). Điểm đích bị chặn thì dừng ở ô trống gần nhất.
  List<Offset> path(Offset from, Offset to) {
    final s = _nearest(from), g = _nearest(to);
    if (s == null || g == null) return [to];
    final goal = free(to) ? to : _center(g);
    if (s == g) return [goal];
    final n = blocked.length;
    final gs = List<double>.filled(n, double.infinity);
    final prev = List<int>.filled(n, -1);
    final closed = List<bool>.filled(n, false);
    final open = <int>[s];
    gs[s] = 0;
    final gc = _center(g);
    double hfun(int i) => (_center(i) - gc).distance / cell;
    var found = false;
    while (open.isNotEmpty) {
      var bi = 0;
      var bf = double.infinity;
      for (var k = 0; k < open.length; k++) {
        final f = gs[open[k]] + hfun(open[k]);
        if (f < bf) {
          bf = f;
          bi = k;
        }
      }
      final cur = open.removeAt(bi);
      if (cur == g) {
        found = true;
        break;
      }
      if (closed[cur]) continue;
      closed[cur] = true;
      final cx = cur % cols, cy = cur ~/ cols;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx, ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
          final ni = ny * cols + nx;
          if (blocked[ni] || closed[ni]) continue;
          // không cắt góc vật cản
          if (dx != 0 && dy != 0 && (blocked[cy * cols + nx] || blocked[ny * cols + cx])) continue;
          final ng = gs[cur] + (dx != 0 && dy != 0 ? 1.414 : 1.0);
          if (ng < gs[ni]) {
            gs[ni] = ng;
            prev[ni] = cur;
            open.add(ni);
          }
        }
      }
    }
    if (!found) return [goal];
    final cells = <Offset>[];
    for (var k = g; k != -1 && k != s; k = prev[k]) {
      cells.insert(0, _center(k));
    }
    final pts = <Offset>[from, ...cells];
    pts[pts.length - 1] = goal;
    // rút gọn: bỏ các điểm thừa khi nhìn thẳng được tới điểm xa hơn
    final out = <Offset>[];
    var i = 0;
    while (i < pts.length - 1) {
      var j = pts.length - 1;
      while (j > i + 1 && !_los(pts[i], pts[j])) {
        j--;
      }
      out.add(pts[j]);
      i = j;
    }
    return out;
  }
}

double _pathLen(List<Offset> p) {
  var l = 0.0;
  for (var k = 1; k < p.length; k++) {
    l += (p[k] - p[k - 1]).distance;
  }
  return l;
}

/// Điểm trên đường đi sau quãng [dist]; trả kèm hướng (true = đang đi sang trái)
(Offset, bool) _along(List<Offset> p, double dist) {
  if (p.isEmpty) return (Offset.zero, false);
  var d = dist;
  for (var k = 1; k < p.length; k++) {
    final seg = (p[k] - p[k - 1]).distance;
    if (d <= seg && seg > 0) return (Offset.lerp(p[k - 1], p[k], d / seg)!, p[k].dx < p[k - 1].dx);
    d -= seg;
  }
  return (p.last, p.length > 1 && p.last.dx < p[p.length - 2].dx);
}

class _Leaver {
  final int table, seed;
  final double t0;
  final bool happy;
  final String npc;
  List<Offset> path = [];
  double dur = 1.3; // thời gian đi trong quán tới cửa
  _Leaver(this.table, this.seed, this.t0, this.happy, [this.npc = '']);
}

class _Coin {
  final int table;
  final double t0;
  _Coin(this.table, this.t0);
}

class _Item {
  final double y;
  final VoidCallback draw;
  _Item(this.y, this.draw);
}

class DiningScene extends StatefulWidget {
  final List<TableS> tables;
  final List<Dish> counter;
  final int? selDishId;
  final String venueId, style;
  final int decor;
  final Look waiterLook;
  final String waiterName;
  final void Function(int) onTable;
  final void Function(Dish) onDish;
  final List<Offset?> tablePos; // vị trí bàn tự sắp xếp (tỉ lệ trên sàn)
  final List<Deco> decos;
  final String light;
  final List<String> pets;
  final List<Incident> incidents;
  final List<OutsideGuest> outside; // khách xếp hàng ngoài cửa
  final String? tool; // dụng cụ đang cầm
  final void Function(int)? onIncident;
  final void Function(String)? onPet;
  const DiningScene({
    super.key,
    required this.tables,
    required this.counter,
    required this.selDishId,
    required this.venueId,
    required this.decor,
    required this.onTable,
    required this.onDish,
    this.style = 'classic',
    this.waiterLook = ngocAnhLook,
    this.waiterName = kNgocAnh,
    this.tablePos = const [],
    this.decos = const [],
    this.light = 'day',
    this.pets = const [],
    this.incidents = const [],
    this.outside = const [],
    this.tool,
    this.onIncident,
    this.onPet,
  });

  @override
  State<DiningScene> createState() => _DiningSceneState();
}

class _DiningSceneState extends State<DiningScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  double get _t => _clock.value;

  // Người phục vụ (toạ độ tỉ lệ 0..1 để không lệch khi đổi kích thước)
  Offset _wp = Offset.zero; // vị trí người phục vụ (pixel)
  List<Offset> _wPath = [];
  bool _placed = false, _walking = false, _left = false;
  // Tìm đường
  _Nav? _nav;
  String _navKey = '';
  final Map<int, List<Offset>> _inPath = {};
  List<double> _seatAt = [];
  final Map<String, List<Offset>> _petPath = {};
  final Map<String, Offset> _petGoal = {};
  final Map<String, double> _petPlanAt = {};
  double _phase = 0, _wipeUntil = -1;

  // Theo dõi thay đổi để chạy hoạt cảnh
  List<bool> _occ = [], _dirtyP = [];
  List<int> _stP = [];
  List<double> _arr = [], _cleanAt = [], _serveAt = [];
  List<int> _seed = [];
  int _seedN = 0;
  final List<_Leaver> _leavers = [];
  final List<_Coin> _coins = [];
  List<String> _npcP = [];
  List<bool> _rang = [];
  final Map<int, String> _incP = {};
  // Thú cưng
  final Map<String, Offset> _petPos = {};
  final Map<String, bool> _petLeft = {};
  final Map<String, double> _petHeartAt = {};
  final Map<String, bool> _petMoving = {};
  bool _catBeside = false;
  double _lastPT = 0;

  // Bố cục (tính lại mỗi khung hình)
  Size _size = Size.zero;
  double _r = 20, _s = 48, _wallH = 60, _floorTop = 70;
  List<Offset> _tc = [];
  List<Rect> _hit = [];
  List<Rect> _slots = [];
  Offset _door = Offset.zero;

  @override
  void initState() {
    super.initState();
    _sync(initial: true);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant DiningScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _sync({bool initial = false}) {
    final tb = widget.tables;
    var first = initial;
    final n = tb.length;
    if (_occ.length != n) {
      _occ = List.filled(n, false);
      _dirtyP = List.filled(n, false);
      _stP = List.filled(n, -1);
      _arr = List.filled(n, -10.0);
      _cleanAt = List.filled(n, -10.0);
      _serveAt = List.filled(n, -10.0);
      _seed = List.filled(n, 0);
      _npcP = List.filled(n, '');
      _rang = List.filled(n, true);
      _seatAt = List.filled(n, -10.0);
      _inPath.clear();
      _leavers.clear();
      _coins.clear();
      first = true;
    }
    for (var i = 0; i < n; i++) {
      final occ = tb[i].c != null;
      if (occ && !_occ[i]) {
        _seed[i] = ++_seedN * 7919 + i * 31;
        _arr[i] = first ? -10.0 : _t;
        _rang[i] = first;
        _seatAt[i] = first ? -10.0 : _t + 1e6; // biết đường đi rồi mới tính giờ ngồi
        _inPath.remove(i);
      } else if (!occ && _occ[i] && !first) {
        final happy = tb[i].dirty; // được phục vụ xong thì bàn bẩn
        final lv = _Leaver(i, _seed[i], _t, happy, _npcP[i]);
        if (i < _tc.length) {
          final seat = _seat(i);
          final ap = _approach(i, _door);
          lv.path = [seat, ap, ...(_nav?.path(ap, _door) ?? [_door])];
          lv.dur = _pathLen(lv.path) / _custSpeed;
        }
        _leavers.add(lv);
        if (happy) _coins.add(_Coin(i, _t));
        Sound.sfx(happy ? 'coin' : 'angry');
      }
      _occ[i] = occ;
      final cu = tb[i].c;
      if (cu != null) _npcP[i] = cu.npc;

      final dirty = tb[i].dirty;
      if (!first && _dirtyP[i] && !dirty) {
        _cleanAt[i] = _t; // vừa dọn bàn
        _wipeUntil = _t + 0.7;
        Sound.sfx('clean');
      }
      _dirtyP[i] = dirty;

      final stv = tb[i].c?.st ?? -1;
      if (!first && _stP[i] == 1 && stv == 2) {
        _serveAt[i] = _t; // vừa mang món ra
        Sound.sfx('serve');
      }
      if (!first && _stP[i] == 0 && stv == 1) Sound.sfx('order');
      _stP[i] = stv;
    }
    // Âm thanh sự cố ở sảnh (bếp tự lo sự cố của bếp)
    final now = <int, String>{for (final x in widget.incidents) x.id: x.type};
    for (final e in now.entries) {
      if (!_incP.containsKey(e.key) && !first) {
        if (e.value == 'rat') Sound.sfx('squeak');
        if (e.value == 'leak') Sound.sfx('drip');
        if (e.value == 'brawl') Sound.sfx('shout');
      }
    }
    for (final e in _incP.entries) {
      if (!now.containsKey(e.key) && !first && (e.value == 'rat' || e.value == 'leak' || e.value == 'brawl')) Sound.sfx('fixed');
    }
    _incP
      ..clear()
      ..addAll(now);
  }

  void _onTick(Duration e) {
    final t = e.inMicroseconds / 1e6;
    final dt = (t - _t).clamp(0.0, 0.1).toDouble();
    if (_size != Size.zero && _wPath.isNotEmpty) {
      var step = max(_size.width, 300.0) * 0.75 * dt;
      while (step > 0 && _wPath.isNotEmpty) {
        final d = _wPath.first - _wp;
        final dist = d.distance;
        if (d.dx.abs() > 2) _left = d.dx < 0;
        if (dist <= step) {
          _wp = _wPath.removeAt(0);
          step -= dist;
        } else {
          _wp = _wp + d / dist * step;
          step = 0;
        }
      }
      _walking = true;
      _phase += dt * 14;
    } else {
      _walking = false;
    }
    _leavers.removeWhere((l) => t - l.t0 > l.dur + _outOutside);
    for (var i = 0; i < _rang.length && i < _arr.length; i++) {
      if (!_rang[i] && t - _arr[i] >= _outside) {
        _rang[i] = true;
        Sound.sfx('door', vol: 0.55);
      }
    }
    _coins.removeWhere((c) => t - c.t0 > 1.5);
    _clock.value = t;
  }

  double get _custSpeed => max(_size.width, 300.0) * 0.45;

  void _goTo(Offset px) {
    final w = _size.width, h = _size.height;
    if (w < 40 || h < 40) return;
    final nav = _nav;
    _wPath = nav == null ? [px] : nav.path(_wp, px);
  }

  /// Chỗ đứng cạnh bàn [i] (không đứng đè lên bàn), chọn phía gần [from] nhất
  Offset _approach(int i, Offset from) {
    final ct = _tc[i], r = _r;
    final cands = [
      ct + Offset(r * 1.6, -r * 0.5),
      ct - Offset(r * 1.6, r * 0.5),
      ct + Offset(0, r * 1.3),
      ct - Offset(0, r * 2.3),
      ct + Offset(r * 1.6, r * 0.6),
      ct + Offset(-r * 1.6, r * 0.6),
    ];
    final nav = _nav;
    Offset? best;
    var bd = double.infinity;
    for (final p in cands) {
      if (nav != null && !nav.free(p)) continue;
      final d = (p - from).distance;
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    return best ?? (nav?.nearestFree(cands.first) ?? cands.first);
  }

  /// Dựng lại lưới vật cản khi bố cục thay đổi
  void _buildNav(double w, double h, double floorTop, double floorH, double r, List<Offset> plants) {
    final key = '${w.round()}x${h.round()}|${_tc.map((o) => '${o.dx.round()},${o.dy.round()}').join(';')}|'
        '${widget.decos.map((d) => '${d.type}${(d.x * 100).round()},${(d.y * 100).round()}').join(';')}|${plants.length}';
    if (key == _navKey && _nav != null) return;
    _navKey = key;
    final pad = r * 0.32; // khoảng hở để người không chạm sát đồ vật
    final obs = <Rect>[
      for (final ct in _tc) Rect.fromLTRB(ct.dx - r * 1.15 - pad, ct.dy - r * 1.6 - pad, ct.dx + r * 1.15 + pad, ct.dy + r * 0.75 + pad),
    ];
    for (final d in widget.decos) {
      final dt = decoById(d.type);
      if (dt.wall) continue;
      final base = Offset(d.x * w, floorTop + d.y * floorH) + Offset(0, r * 0.35);
      final sz = r * dt.size * 1.6;
      final wide = dt.id == 'bar' ? 1.9 : (dt.id == 'sofa' ? 1.5 : (dt.id == 'fish' ? 1.3 : 0.8));
      obs.add(Rect.fromLTRB(base.dx - sz * wide / 2 - pad, base.dy - sz * 0.45 - pad, base.dx + sz * wide / 2 + pad, base.dy + pad * 0.5));
    }
    for (final p in plants) {
      obs.add(Rect.fromCenter(center: p + Offset(0, r * 0.1), width: r * 1.1 + pad * 2, height: r * 0.7 + pad * 2));
    }
    final cell = max(8.0, r * 0.42);
    final area = Rect.fromLTRB(r * 0.3, floorTop + 2, w - r * 0.3, h - 2);
    _nav = _Nav.build(area, cell, obs);
    // vị trí đang đứng nếu bị kẹt thì dời ra ô trống
    if (_placed) _wp = _nav!.nearestFree(_wp);
    _inPath.clear();
  }

  Offset _incPos(Incident x) => Offset(x.x * _size.width, _floorTop + x.y * (_size.height - _floorTop));

  void _tap(TapUpDetails d) {
    final p = d.localPosition;
    // 1) Sự cố ở sảnh: chuột, vũng nước (bàn gây gổ chỉ khi đang cầm dụng cụ)
    for (final x in widget.incidents) {
      if (x.type == 'rat' || x.type == 'leak') {
        if ((p - _incPos(x)).distance < _r * (x.type == 'rat' ? 1.1 : 1.3)) {
          widget.onIncident?.call(x.id);
          return;
        }
      } else if (x.type == 'brawl' && widget.tool != null && x.target < _hit.length && _hit[x.target].contains(p)) {
        widget.onIncident?.call(x.id);
        return;
      }
    }
    // 2) Vuốt ve thú cưng
    for (final e in _petPos.entries) {
      if ((p - e.value).distance < _r * 0.8) {
        _petHeartAt[e.key] = _t;
        Sound.sfx(e.key == 'dog' ? 'woof' : (e.key == 'parrot' ? 'chirp' : (e.key == 'hamster' ? 'squeak' : 'purr')));
        widget.onPet?.call(e.key);
        return;
      }
    }
    for (var j = 0; j < _slots.length && j < widget.counter.length; j++) {
      if (_slots[j].inflate(4).contains(p)) {
        widget.onDish(widget.counter[j]);
        _goTo(Offset(_slots[j].center.dx, _wallH + _s * 0.55));
        return;
      }
    }
    for (var i = 0; i < _hit.length && i < widget.tables.length; i++) {
      if (_hit[i].contains(p)) {
        widget.onTable(i);
        _goTo(_approach(i, _wp));
        return;
      }
    }
  }

  Offset _seat(int i) => _tc[i] + Offset(0, -_r * 0.3);

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _tap,
        child: SizedBox.expand(child: CustomPaint(painter: _DiningPainter(this))),
      );

  void _paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    if (w < 40 || h < 40) return;
    _size = sz;
    final style = widget.style;
    final th = themeFor(widget.venueId, style);
    final tb = widget.tables;
    final n = tb.length;
    final t = _t;

    // ---------- Bố cục ----------
    final wallH = diningWallH(h);
    _wallH = wallH;
    final band = wallH * 0.22;
    final floorTop = wallH + 6;
    final floorH = h - floorTop;
    final r = tableRadius(w, floorH, n);
    final s = r * 2.4;
    _r = r;
    _s = s;
    _floorTop = floorTop;
    _tc = [];
    _hit = [];
    for (var i = 0; i < n; i++) {
      final o = (i < widget.tablePos.length ? widget.tablePos[i] : null) ?? defaultTablePos(i, n);
      final ct = Offset(o.dx * w, floorTop + o.dy * floorH);
      _tc.add(ct);
      _hit.add(Rect.fromCenter(center: ct - Offset(0, r * 0.4), width: r * 2.8, height: r * 3.2));
    }
    final cx0 = w * 0.03, cx1 = w * 0.56;
    final slotW = (cx1 - cx0) / 6;
    _slots = [for (var j = 0; j < 6; j++) Rect.fromLTWH(cx0 + slotW * j, wallH * 0.3, slotW, wallH * 0.7)];
    _door = Offset(w * 0.895, wallH + s * 0.35);
    _door = Offset(w * 0.895, floorTop + 4);

    // ---------- Sàn ----------
    final tile = max(24.0, w / 9);
    c.drawRect(Rect.fromLTWH(0, wallH, w, h - wallH), Paint()..color = th.floorA);
    final pb = Paint()..color = th.floorB;
    for (var y = 0; wallH + y * tile < h; y++) {
      for (var x = 0; x * tile < w; x++) {
        if ((x + y).isOdd) c.drawRect(Rect.fromLTWH(x * tile, wallH + y * tile, tile, tile), pb);
      }
    }
    // Thảm giữa sảnh
    final rug = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.06, floorTop + 8, w * 0.94, h - 8), const Radius.circular(18));
    c.drawRRect(rug, Paint()..color = _a(th.accent, 0.10));
    c.drawRRect(rug.deflate(6), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _a(th.accent, 0.25));

    // ---------- Tường ----------
    c.drawRect(Rect.fromLTWH(0, 0, w, wallH), Paint()..color = th.wall);
    final stripe = Paint()..color = _a(Colors.white, 0.07);
    for (double x = 0; x < w; x += 18) {
      c.drawRect(Rect.fromLTWH(x, 0, 9, wallH), stripe);
    }
    _ambientBack(c, w, band, style, t, th);
    final shadeR = Rect.fromLTWH(0, wallH, w, 10);
    c.drawRect(
      shadeR,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_a(Colors.black, 0.18), _a(Colors.black, 0)],
        ).createShader(shadeR),
    );

    // Ô cửa nhìn vào bếp
    final win = RRect.fromRectAndRadius(Rect.fromLTRB(cx0 + 4, wallH * 0.26, cx1 - 4, wallH * 0.6), const Radius.circular(8));
    c.drawRRect(win, Paint()..color = th.trim);
    final winIn = win.deflate(3);
    c.drawRRect(
      winIn,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6D4C41), Color(0xFF2E1F17)],
        ).createShader(winIn.outerRect),
    );
    for (var k = 0; k < 3; k++) {
      final lx = winIn.left + winIn.width * (k + 0.5) / 3;
      final ly = winIn.top + winIn.height * 0.35;
      c.drawLine(Offset(lx, winIn.top), Offset(lx, ly), Paint()
        ..color = Colors.black54
        ..strokeWidth = 1.5);
      c.drawCircle(Offset(lx, ly), wallH * 0.11, Paint()..color = _a(const Color(0xFFFFE082), 0.15 + 0.05 * sin(t * 2 + k)));
      c.drawCircle(Offset(lx, ly), wallH * 0.035, Paint()..color = const Color(0xFFFFE082));
    }

    // Quầy ra món
    final ledge = Rect.fromLTRB(cx0, wallH * 0.56, cx1, wallH * 0.72);
    c.drawRRect(RRect.fromRectAndRadius(ledge, const Radius.circular(4)), Paint()..color = _lt(th.wood, 0.2));
    c.drawRect(Rect.fromLTRB(cx0, ledge.bottom, cx1, wallH), Paint()..color = _dk(th.wood, 0.15));
    final lbl = _text('🔔 QUẦY RA MÓN', min(wallH * 0.12, 12.0), color: _a(Colors.white, 0.85), bold: true);
    lbl.paint(c, Offset((cx0 + cx1) / 2 - lbl.width / 2, (ledge.bottom + wallH) / 2 - lbl.height / 2));

    final pr = min(slotW * 0.4, wallH * 0.2);
    for (var j = 0; j < widget.counter.length && j < 6; j++) {
      final d = widget.counter[j];
      final pc = Offset(_slots[j].center.dx, ledge.top + ledge.height * 0.35);
      if (d.ticketId == widget.selDishId) {
        c.drawOval(Rect.fromCenter(center: pc, width: pr * 2.4, height: pr * 0.9), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.greenAccent);
        continue;
      }
      final bad = d.quality < 0.6;
      if (bad) c.drawOval(Rect.fromCenter(center: pc, width: pr * 2.4, height: pr * 0.8), Paint()..color = const Color(0x66FF5252));
      final bob = sin(t * 3 + j) * 1.2;
      drawDish(c, d.recipe.id, pc - Offset(0, pr * 0.55 + bob), min(slotW * 0.92, pr * 2.4), t: t);
      if (bad) _emoji(c, '💨', pc + Offset(pr * 0.95, -pr * 1.3), pr * 0.7);
    }

    // Đồ treo tường (tự sắp xếp)
    for (final d in widget.decos) {
      final dt = decoById(d.type);
      if (!dt.wall) continue;
      drawWallDeco(c, dt.id, Offset(d.x * w, wallH * (dt.id == 'light' || dt.id == 'lantern' ? 0.2 : 0.17)), wallH * 0.36, t);
    }

    // Cửa sổ nhìn ra phố + cửa kính: thấy khách đi tới, người qua đường
    _drawStreetFront(c, w, wallH, s, t, th);
    c.drawRect(Rect.fromLTWH(0, wallH - 4, w, 5), Paint()..color = th.trim);

    // ---------- Tìm đường ----------
    final plants = [
      Offset(r * 0.7, h - r * 0.5),
      Offset(w - r * 0.7, h - r * 0.5),
      Offset(w * 0.75, wallH + r * 0.4),
      Offset(w * 0.5, h - r * 0.4),
    ].take(min(widget.decor, 4)).toList();
    _buildNav(w, h, floorTop, floorH, r, plants);
    if (!_placed) {
      _placed = true;
      _wp = _nav?.nearestFree(Offset(w * 0.6, floorTop + floorH * 0.3)) ?? Offset(w * 0.6, floorTop + floorH * 0.3);
    }
    final custSp = _custSpeed;
    for (var i = 0; i < n; i++) {
      if (tb[i].c == null || _seatAt[i] < 0 || _inPath.containsKey(i)) continue;
      final ap = _approach(i, _door);
      final path = [_door, ...(_nav?.path(_door, ap) ?? [ap]), _seat(i)];
      _inPath[i] = path;
      _seatAt[i] = _arr[i] + _outside + _pathLen(path) / custSp;
    }

    // ---------- Vẽ theo chiều sâu (y nhỏ vẽ trước) ----------
    final items = <_Item>[];
    for (var i = 0; i < n; i++) {
      items.add(_Item(_tc[i].dy, () => _drawTable(c, i, t, th)));
    }
    for (var i = 0; i < n; i++) {
      final path = _inPath[i];
      if (tb[i].c != null && path != null && t < _seatAt[i] && t - _arr[i] >= _outside) {
        final (p, left) = _along(path, (t - _arr[i] - _outside) * custSp);
        final npc = tb[i].c!.npc;
        final look = custLook(npc, _seed[i]);
        final ss = npc == 'student' ? s * 0.82 : s;
        items.add(_Item(p.dy, () => drawPerson(c, p, ss, look, walking: true, phase: t * 13 + i, facingLeft: left)));
      }
    }
    for (final l in _leavers) {
      if (l.table >= n || t - l.t0 > l.dur || l.path.isEmpty) continue;
      final (p, left) = _along(l.path, (t - l.t0) * custSp);
      final look = custLook(l.npc, l.seed);
      items.add(_Item(
        p.dy,
        () => drawPerson(c, p, s, look,
            walking: true, phase: t * 13, facingLeft: left, mood: l.happy ? 0 : 2, armUp: l.happy && sin(t * 9) > -0.3),
      ));
    }
    final plantEmoji = style == 'tet' ? '🌼' : (style == 'beach' ? '🌴' : (style == 'sakura' ? '🌸' : '🪴'));
    for (var k = 0; k < widget.decor && k < plants.length; k++) {
      final pp = plants[k];
      items.add(_Item(pp.dy, () {
        if (style == 'classic' || style == 'garden' || style == 'night') {
          drawFloorDeco(c, k.isEven ? 'plant' : 'flower', pp + Offset(0, r * 0.3), r * 1.6, t);
        } else {
          _emoji(c, k.isEven ? plantEmoji : '🌿', pp - Offset(0, r * 0.4), r * 1.3);
        }
      }));
    }
    // Đồ trang trí trên sàn (tự sắp xếp)
    for (final d in widget.decos) {
      final dt = decoById(d.type);
      if (dt.wall) continue;
      final dp = Offset(d.x * w, floorTop + d.y * floorH);
      items.add(_Item(dp.dy, () => _drawDeco(c, dt, dp, r, t)));
    }
    // Thú cưng
    _updatePets(t, w, h, floorTop, floorH, r);
    for (final e in _petPos.entries) {
      final id = e.key;
      final pp = e.value;
      items.add(_Item(pp.dy, () => _drawPet(c, id, pp, r, t)));
    }

    String? carry;
    for (final d in widget.counter) {
      if (d.ticketId == widget.selDishId) carry = d.recipe.id;
    }
    final wp = _wp;
    final wiping = t < _wipeUntil && !_walking;
    items.add(_Item(
      wp.dy,
      () => drawPerson(c, wp, s, widget.waiterLook,
          walking: _walking,
          phase: _phase,
          facingLeft: _left,
          role: 'waiter',
          carry: wiping ? null : carry,
          stir: wiping ? t * 22 : -1,
          name: widget.waiterName),
    ));

    items.sort((a, b) => a.y.compareTo(b.y));
    for (final it in items) {
      it.draw();
    }

    _ambientFront(c, w, h, floorTop, style, t, r);
    _drawLight(c, w, h, t);
    _drawDiningIncidents(c, w, h, t);

    // ---------- Lớp trên cùng: bong bóng, hiệu ứng ----------
    for (var i = 0; i < n; i++) {
      _drawOverlay(c, i, t);
    }
    for (final cn in _coins) {
      if (cn.table >= n) continue;
      final k = ((t - cn.t0) / 1.5).clamp(0.0, 1.0).toDouble();
      final base = _tc[cn.table];
      _emoji(c, '💰', base - Offset(0, r * 0.8 + k * r * 1.6), r * 0.8, alpha: 1 - k);
      for (var j = 0; j < 3; j++) {
        final hp = base + Offset((j - 1) * r * 0.7 + sin(t * 5 + j) * 5, -r * 0.5 - k * r * (1.3 + 0.35 * j));
        _emoji(c, j == 1 ? '⭐' : '💖', hp, r * 0.45, alpha: 1 - k);
      }
    }
  }

  void _updatePets(double t, double w, double h, double floorTop, double floorH, double r) {
    final dt = (t - _lastPT).clamp(0.0, 0.1).toDouble();
    _lastPT = t;
    final ids = widget.pets;
    _petPos.removeWhere((k, _) => !ids.contains(k));
    // bàn có khách sốt ruột nhất: mèo tới nằm cạnh
    var catT = -1;
    var bestF = 2.0;
    for (var i = 0; i < widget.tables.length && i < _tc.length; i++) {
      final c = widget.tables[i].c;
      if (c == null || c.st >= 2) continue;
      final f = c.pat / c.maxPat;
      if (f < bestF) {
        bestF = f;
        catT = i;
      }
    }
    Incident? rat;
    for (final x in widget.incidents) {
      if (x.type == 'rat') rat = x;
    }
    for (final id in ids) {
      Offset target;
      switch (id) {
        case 'cat':
          target = catT >= 0 ? _tc[catT] + Offset(-r * 1.25, r * 0.55) : _wander(t, w, h - r * 0.45, 26, 0).$1;
          break;
        case 'dog':
          target = rat != null ? _incPos(rat) : _wander(t, w, h - r * 1.6, 21, 9).$1;
          break;
        case 'hamster':
          target = Offset(w - r * 0.9, floorTop + floorH * 0.72); // lồng hamster sát tường phải
          break;
        case 'parrot':
          target = Offset(w * 0.8, floorTop + r * 0.25);
          break;
        default:
          target = _wander(t, w, h - r, 30, 5).$1;
      }
      final nav = _nav;
      final fixed = id == 'hamster' || id == 'parrot';
      var cur = _petPos[id] ?? (fixed || nav == null ? target : nav.nearestFree(target));
      // lập lại đường đi khi đích đổi chỗ (chó đuổi chuột: cập nhật thường xuyên)
      final goal = _petGoal[id];
      final replan = goal == null || (goal - target).distance > r * 0.6 || (id == 'dog' && rat != null && t - (_petPlanAt[id] ?? 0) > 0.5);
      if (replan) {
        _petGoal[id] = target;
        _petPlanAt[id] = t;
        _petPath[id] = fixed || nav == null ? [target] : nav.path(cur, target);
      }
      final path = _petPath[id] ?? [target];
      final fast = id == 'dog' && rat != null;
      var step = max(w, 300.0) * (fast ? 0.55 : 0.3) * dt;
      var moving = false;
      while (step > 0 && path.isNotEmpty) {
        final d = path.first - cur;
        final dist = d.distance;
        if (dist < 0.5) {
          path.removeAt(0);
          continue;
        }
        moving = true;
        if (d.dx.abs() > 1) _petLeft[id] = d.dx < 0;
        if (dist <= step) {
          cur = path.removeAt(0);
          step -= dist;
        } else {
          cur = cur + d / dist * step;
          step = 0;
        }
      }
      _petMoving[id] = moving;
      _petPos[id] = cur;
      if (id == 'cat') _catBeside = catT >= 0 && path.isEmpty;
    }
  }

  void _drawPet(Canvas c, String id, Offset p, double r, double t) {
    final pt = petById(id);
    final moving = _petMoving[id] ?? false;
    final size = id == 'dog' ? r * 1.0 : (id == 'cat' ? r * 0.85 : r * 0.7);
    c.drawOval(Rect.fromCenter(center: p + Offset(0, size * 0.35), width: size * 0.9, height: size * 0.22), Paint()..color = const Color(0x22000000));
    if (id == 'hamster') {
      final cage = RRect.fromRectAndRadius(Rect.fromCenter(center: p, width: r * 1.3, height: r * 1.0), Radius.circular(r * 0.2));
      c.drawRRect(cage, Paint()..color = const Color(0x33FFFFFF));
      c.drawRRect(cage, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF90A4AE));
      final wc = p + Offset(r * 0.25, 0);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFB0BEC5);
      c.drawCircle(wc, r * 0.34, ring);
      for (var k = 0; k < 3; k++) {
        final a = t * 8 + k * 2.09;
        c.drawLine(wc, wc + Offset(cos(a), sin(a)) * r * 0.34, ring);
      }
      _emoji(c, pt.emoji, wc + Offset(0, r * 0.1 - sin(t * 16).abs() * 2), size * 0.8);
    } else if (id == 'parrot') {
      final perch = Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      c.drawLine(p + Offset(-r * 0.5, r * 0.28), p + Offset(r * 0.5, r * 0.28), perch);
      c.drawLine(p + Offset(0, r * 0.28), p + Offset(0, r * 1.0), perch);
      final flap = 1 + 0.12 * sin(t * 10).abs();
      _emoji(c, pt.emoji, p - Offset(0, sin(t * 3).abs() * 3), size * flap);
    } else {
      c.save();
      c.translate(p.dx, p.dy - (moving ? sin(t * 14).abs() * 2 : 0));
      if (!(_petLeft[id] ?? true)) c.scale(-1, 1);
      _emoji(c, pt.emoji, Offset.zero, size);
      c.restore();
      if (!moving && id == 'cat') {
        _emoji(c, _catBeside ? '💕' : '💤', p + Offset(size * 0.45, -size * 0.7 - sin(t * 2).abs() * 3), size * 0.4, alpha: 0.85);
      }
    }
    final kh = t - (_petHeartAt[id] ?? -10);
    if (kh < 1.2) {
      for (var j = 0; j < 3; j++) {
        _emoji(c, '💗', p + Offset((j - 1) * size * 0.45 + sin(t * 6 + j) * 3, -size * 0.6 - kh * size * (1 + 0.3 * j)), size * 0.4, alpha: 1 - kh / 1.2);
      }
    }
  }

  void _drawDeco(Canvas c, DecoType dt, Offset p, double r, double t) {
    drawFloorDeco(c, dt.id, p + Offset(0, r * 0.35), r * dt.size * 1.6, t, wood: themeFor(widget.venueId, widget.style).wood);
  }

  void _drawLight(Canvas c, double w, double h, double t) {
    switch (widget.light) {
      case 'warm':
        c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x22FFA726));
        break;
      case 'romantic':
        c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x3A2A0A3A));
        for (final p in _tc) {
          c.drawCircle(p, _r * 1.6, Paint()..color = _a(const Color(0xFFFFCC80), 0.10 + 0.03 * sin(t * 3 + p.dx)));
        }
        break;
      case 'disco':
        const cols = [Color(0xFFFF4081), Color(0xFF40C4FF), Color(0xFFFFEB3B), Color(0xFF69F0AE)];
        for (var k = 0; k < 4; k++) {
          final cp = Offset(w * (0.5 + 0.4 * sin(t * 0.9 + k * 1.7)), _floorTop + (h - _floorTop) * (0.5 + 0.4 * cos(t * 0.7 + k * 2.3)));
          c.drawCircle(cp, _r * 2.2, Paint()..color = _a(cols[k], 0.16));
        }
        _emoji(c, '🪩', Offset(w * 0.5, 12), 18);
        break;
    }
  }

  void _drawDiningIncidents(Canvas c, double w, double h, double t) {
    final r = _r;
    final fs = max(9.0, r * 0.3);
    for (final x in widget.incidents) {
      final it = incidentType(x.type);
      switch (x.type) {
        case 'rat':
          {
            final p = _incPos(x);
            c.save();
            c.translate(p.dx, p.dy - sin(t * 20).abs() * 2);
            if (sin(t * 0.8 + x.id) > 0) c.scale(-1, 1);
            _emoji(c, '🐀', Offset.zero, r * 0.85);
            c.restore();
            _pill(c, '${it.toolEmoji}×${x.hp}', p - Offset(0, r * 0.85), fs, bg: const Color(0xFFFFEBEE), fg: const Color(0xFFC62828));
          }
          break;
        case 'leak':
          {
            final p = _incPos(x);
            final grow = min(x.age, 20.0) * 0.06;
            c.drawOval(Rect.fromCenter(center: p, width: r * (1.6 + grow * 2), height: r * (0.55 + grow * 0.7)), Paint()..color = _a(const Color(0xFF4FC3F7), 0.55));
            c.drawOval(Rect.fromCenter(center: p - Offset(r * 0.2, r * 0.05), width: r * 0.5, height: r * 0.15), Paint()..color = _a(Colors.white, 0.5));
            c.drawLine(Offset(p.dx - 7, _wallH - 2), Offset(p.dx + 7, _wallH - 2), Paint()
              ..color = const Color(0xFF546E7A)
              ..strokeWidth = 4);
            for (var k = 0; k < 2; k++) {
              final ph = (t * 1.2 + k * 0.5) % 1.0;
              c.drawCircle(Offset(p.dx, _wallH + (p.dy - _wallH) * ph), 3, Paint()..color = _a(const Color(0xFF0288D1), 0.8));
            }
            _pill(c, '💧 ${it.toolEmoji}×${x.hp}', p - Offset(0, r * 0.7), fs, bg: const Color(0xFFE1F5FE), fg: const Color(0xFF01579B));
          }
          break;
        case 'brawl':
          {
            if (x.target >= _tc.length) break;
            final ct = _tc[x.target];
            final pulse = 0.5 + 0.5 * sin(t * 10);
            c.drawOval(
              Rect.fromCenter(center: ct, width: r * (2.8 + pulse * 0.4), height: r * (1.5 + pulse * 0.2)),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = _a(const Color(0xFFFF1744), 0.5 + 0.5 * pulse),
            );
            _emoji(c, '💢', _seat(x.target) + Offset(-r * 0.9, -_s * 0.6), r * 0.6 * (0.9 + 0.2 * pulse));
            _pill(c, '${it.toolEmoji}×${x.hp}', ct + Offset(0, r * 0.95), fs, bg: const Color(0xFFFFEBEE), fg: const Color(0xFFC62828));
          }
          break;
        case 'power':
          c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x66000000));
          _pill(c, '⚡ Mất điện! Đầu bếp bật cầu dao 🔌', Offset(w / 2, _floorTop + 14), 11, bg: const Color(0xFFFFF59D));
          break;
      }
    }
  }

  /// Cửa sổ lớn nhìn ra phố và cửa kính. Khách sắp vào đi ngang qua cửa sổ tới cửa,
  /// khách ra về đi ngược lại; thỉnh thoảng có người qua đường.
  void _drawStreetFront(Canvas c, double w, double wallH, double s, double t, VTheme th) {
    final style = widget.style;
    final win = Rect.fromLTRB(w * 0.59, wallH * 0.24, w * 0.79, wallH * 0.92);
    final dr = Rect.fromLTRB(w * 0.82, wallH * 0.2, w * 0.97, wallH);
    final glass = Rect.fromLTRB(dr.left + dr.width * 0.14, dr.top + dr.height * 0.08, dr.right - dr.width * 0.14, dr.top + dr.height * 0.78);
    final tb = widget.tables;
    final doorX = dr.center.dx;

    // Cửa đang mở khi có người bước qua
    var open = false;
    for (var i = 0; i < tb.length && i < _arr.length; i++) {
      final dt = t - _arr[i];
      if (tb[i].c != null && dt > _outside - 0.3 && dt < _outside + 0.35) open = true;
    }
    for (final l in _leavers) {
      final dt = t - l.t0;
      if (dt > l.dur - 0.35 && dt < l.dur + 0.3) open = true;
    }

    // khung
    c.drawRRect(RRect.fromRectAndRadius(win.inflate(4), const Radius.circular(6)), Paint()..color = th.trim);
    c.drawRect(dr.inflate(3), Paint()..color = th.trim);
    if (!open) c.drawRect(dr, Paint()..shader = _vg(_lt(th.wood, 0.05), _dk(th.wood, 0.2)).createShader(dr));

    // ---- phố bên ngoài (cắt theo cửa sổ + kính cửa) ----
    final view = Path()
      ..addRRect(RRect.fromRectAndRadius(win, const Radius.circular(4)))
      ..addRect(open ? dr : glass);
    c.save();
    c.clipPath(view);
    final all = Rect.fromLTRB(win.left, win.top, dr.right, dr.bottom);
    final List<Color> sky;
    switch (style) {
      case 'night':
        sky = const [Color(0xFF1A237E), Color(0xFF3949AB)];
        break;
      case 'sakura':
        sky = const [Color(0xFFF8BBD0), Color(0xFFFFF0F5)];
        break;
      case 'beach':
        sky = const [Color(0xFF29B6F6), Color(0xFFB3E5FC)];
        break;
      case 'tet':
        sky = const [Color(0xFFFFCC80), Color(0xFFFFF8E1)];
        break;
      default:
        sky = const [Color(0xFF90CAF9), Color(0xFFE3F2FD)];
    }
    c.drawRect(all, Paint()..shader = _vg(sky[0], sky[1]).createShader(all));
    final night = style == 'night';
    // nhà phố phía xa
    final rr = Random(3);
    var bx = all.left - 6;
    while (bx < all.right) {
      final bw = all.height * (0.35 + rr.nextDouble() * 0.3);
      final bh = all.height * (0.35 + rr.nextDouble() * 0.35);
      final b = Rect.fromLTWH(bx, all.bottom - all.height * 0.24 - bh, bw, bh);
      c.drawRect(b, Paint()..color = night ? const Color(0xFF283593) : Color.lerp(sky[0], const Color(0xFF78909C), 0.45)!);
      for (var k = 0; k < 4; k++) {
        final wr = Rect.fromLTWH(b.left + bw * (0.18 + 0.4 * (k % 2)), b.top + bh * (0.15 + 0.3 * (k ~/ 2)), bw * 0.2, bh * 0.14);
        c.drawRect(wr, Paint()..color = night ? _a(const Color(0xFFFFE082), 0.5 + 0.5 * sin(t * 0.7 + k + bx).abs()) : const Color(0x66FFFFFF));
      }
      bx += bw + 3;
    }
    if (style == 'sakura' || style == 'tet') {
      for (var k = 0; k < 6; k++) {
        final ph = (t * 0.35 + k / 6) % 1.0;
        final px = all.left + all.width * _fr(k * 0.37 + t * 0.05);
        c.drawOval(Rect.fromCenter(center: Offset(px, all.top + ph * all.height), width: 5, height: 3), Paint()..color = style == 'sakura' ? const Color(0xFFF06292) : const Color(0xFFFFC107));
      }
    }
    // vỉa hè
    final walk = Rect.fromLTRB(all.left, all.bottom - all.height * 0.24, all.right, all.bottom);
    c.drawRect(walk, Paint()..color = night ? const Color(0xFF5C6BC0) : const Color(0xFFD7CCC8));
    for (double x = walk.left; x < walk.right; x += 14) {
      c.drawLine(Offset(x, walk.top), Offset(x - 5, walk.bottom), Paint()
        ..color = const Color(0x22000000)
        ..strokeWidth = 1);
    }
    // cột đèn đường
    final lp = Offset(win.left + win.width * 0.12, walk.top);
    c.drawLine(lp, lp - Offset(0, all.height * 0.62), Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = 2.5);
    final bulb = lp - Offset(-4, all.height * 0.62);
    if (night) _glow(c, bulb, all.height * 0.3, const Color(0xFFFFF59D), 0.6);
    c.drawCircle(bulb, 3.5, Paint()..color = night ? const Color(0xFFFFF59D) : const Color(0xFFECEFF1));

    final ps = all.height * 0.95; // người ngoài phố trông nhỏ hơn (ở xa)
    final footY = all.bottom - all.height * 0.05;
    // người qua đường
    for (var k = 0; k < 3; k++) {
      final period = 9.0 + k * 3.5;
      final tt = t + k * 4.1;
      final cyc = (tt / period).floor();
      final ph = (tt % period) / period;
      if (ph > 0.55) continue; // nghỉ giữa các lượt
      final dir = (cyc + k).isEven ? 1.0 : -1.0;
      final kk = ph / 0.55;
      final x = dir > 0 ? all.left - 20 + kk * (all.width + 40) : all.right + 20 - kk * (all.width + 40);
      drawPerson(c, Offset(x, footY), ps, Look.seed(k * 97 + cyc * 13), walking: true, phase: t * 11 + k, facingLeft: dir < 0);
    }
    // khách đang tới
    for (var i = 0; i < tb.length && i < _arr.length; i++) {
      final cu = tb[i].c;
      final dt = t - _arr[i];
      if (cu == null || dt < 0 || dt >= _outside) continue;
      final k = Curves.easeOut.transform((dt / _outside).clamp(0.0, 1.0).toDouble());
      final x = all.left - 18 + k * (doorX - all.left + 18);
      final ss = cu.npc == 'student' ? ps * 0.82 : ps;
      drawPerson(c, Offset(x, footY), ss, custLook(cu.npc, _seed[i]), walking: true, phase: t * 12 + i);
    }
    // khách xếp hàng ngoài cửa (quán kín bàn): người đầu hàng đứng sát cửa
    final queueHeads = <(Offset, double)>[];
    final gap = ps * 0.36;
    for (var k = 0; k < widget.outside.length; k++) {
      final g = widget.outside[k];
      final x = doorX - ps * 0.1 - k * gap;
      if (x < all.left - 10) break;
      final f = g.frac;
      final mood = f > 0.6 ? 0 : (f > 0.3 ? 1 : 2);
      // sốt ruột thì nhún chân, dậm chân
      final fidget = f < 0.3 ? sin(t * 14 + k) * 1.5 : 0.0;
      drawPerson(c, Offset(x + fidget, footY), ps, custLook('', g.seed), mood: mood);
      queueHeads.add((Offset(x, footY - ps * 0.98), f));
    }
    // khách ra về
    for (final l in _leavers) {
      final dt = t - l.t0 - l.dur;
      if (dt < 0 || dt >= _outOutside) continue;
      final k = Curves.easeIn.transform((dt / _outOutside).clamp(0.0, 1.0).toDouble());
      final x = doorX - k * (doorX - all.left + 24);
      drawPerson(c, Offset(x, footY), ps, custLook(l.npc, l.seed), walking: true, phase: t * 12, facingLeft: true, mood: l.happy ? 0 : 2, armUp: l.happy && sin(t * 9) > 0);
    }
    c.restore();

    // biểu cảm của khách chờ ngoài cửa (vẽ ngoài vùng cắt để không bị che)
    for (final (p, f) in queueHeads) {
      if (f < 0.3) {
        _emoji(c, '💢', p + Offset(ps * 0.12, -ps * 0.05 + sin(t * 8) * 1.5), ps * 0.3);
      } else if (f < 0.6) {
        _emoji(c, '⏳', p + Offset(ps * 0.12, -ps * 0.02), ps * 0.22);
      }
    }
    if (widget.outside.isNotEmpty) {
      final n = widget.outside.length;
      final angry = widget.outside.any((g) => g.frac < 0.3);
      final label = _text('🚶 $n đang chờ', max(10.0, wallH * 0.13), color: Colors.white, bold: true);
      final pill = Rect.fromCenter(center: Offset((win.left + dr.right) / 2, wallH + label.height * 0.9), width: label.width + 14, height: label.height + 6);
      c.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)), Paint()..color = angry ? const Color(0xFFE53935) : const Color(0xCC37474F));
      label.paint(c, pill.center - Offset(label.width / 2, label.height / 2));
    }

    // ---- kính, song cửa, tay nắm ----
    final refl = Paint()..color = const Color(0x40FFFFFF);
    for (final g in [win, open ? Rect.zero : glass]) {
      if (g == Rect.zero) continue;
      c.drawPath(
        Path()
          ..moveTo(g.left + g.width * 0.15, g.top)
          ..lineTo(g.left + g.width * 0.32, g.top)
          ..lineTo(g.left + g.width * 0.05, g.bottom)
          ..lineTo(g.left - g.width * 0.12, g.bottom)
          ..close(),
        refl,
      );
    }
    final bar = Paint()
      ..color = th.trim
      ..strokeWidth = 3;
    c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), bar);
    c.drawLine(Offset(win.left, win.top + win.height * 0.38), Offset(win.right, win.top + win.height * 0.38), bar);
    // bậu cửa sổ + chậu hoa nhỏ
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(win.left - 6, win.bottom, win.right + 6, win.bottom + 6), const Radius.circular(2)), Paint()..color = _lt(th.trim, 0.2));
    if (open) {
      // cánh cửa mở hé vào trong
      final panel = Path()
        ..moveTo(dr.left, dr.top)
        ..lineTo(dr.left + dr.width * 0.28, dr.top + dr.height * 0.08)
        ..lineTo(dr.left + dr.width * 0.28, dr.bottom + dr.height * 0.04)
        ..lineTo(dr.left, dr.bottom)
        ..close();
      c.drawPath(panel, Paint()..color = _dk(th.wood, 0.1));
      c.drawPath(panel, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _dk(th.wood, 0.4));
    } else {
      c.drawRect(glass, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _dk(th.wood, 0.3));
      c.drawCircle(Offset(dr.right - dr.width * 0.2, dr.top + dr.height * 0.86), max(2.0, dr.width * 0.06), Paint()..color = const Color(0xFFFFD54F));
    }
    // chuông gió trên cửa
    final ring = open ? sin(t * 25) * 0.4 : sin(t * 1.5) * 0.06;
    c.save();
    c.translate(doorX, dr.top - 2);
    c.rotate(ring);
    _emoji(c, '🔔', Offset(0, wallH * 0.07), wallH * 0.12);
    c.restore();
    // thảm chùi chân
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(doorX, wallH + 6), width: dr.width * 1.15, height: 10), const Radius.circular(3)),
      Paint()..color = _a(th.accent, 0.85),
    );
  }

  void _drawTable(Canvas c, int i, double t, VTheme th) {
    final tb = widget.tables[i];
    final ct = _tc[i];
    final r = _r;
    final cu = tb.c;
    final seated = cu != null && t >= _seatAt[i];

    // Ghế (phía sau bàn)
    final chair = RRect.fromRectAndRadius(Rect.fromCenter(center: ct + Offset(0, -r * 0.95), width: r * 1.3, height: r * 1.3), Radius.circular(r * 0.25));
    c.drawRRect(chair, Paint()..color = _dk(th.wood, 0.15));
    c.drawRRect(chair.deflate(r * 0.12), Paint()..color = _lt(th.accent, 0.15));

    if (cu != null && seated) {
      final frac = (cu.pat / cu.maxPat).clamp(0.0, 1.0);
      final mood = cu.st == 2 ? 0 : (frac < 0.35 ? 2 : (frac < 0.6 ? 1 : 0));
      final justServed = t - _serveAt[i] < 0.6;
      final brawl = widget.incidents.any((x) => x.type == 'brawl' && x.target == i);
      final shake = brawl ? sin(t * 40) * r * 0.06 : 0.0;
      drawPerson(
        c,
        _seat(i) + Offset(shake, 0),
        cu.npc == 'student' ? _s * 0.82 : _s,
        custLook(cu.npc, _seed[i]),
        sitting: true,
        mood: brawl ? 2 : mood,
        armUp: cu.st == 0 || justServed || (brawl && sin(t * 8) > 0),
        chew: cu.st == 2 && !justServed && sin(t * 12) > 0,
        bob: cu.st == 0 ? sin(t * 6).abs() * r * 0.08 : (justServed ? sin(t * 20).abs() * r * 0.1 : 0.0),
      );
    }

    // Mặt bàn
    final glow = cu != null && cu.st == 1 && widget.selDishId != null && widget.selDishId == cu.ticketId;
    c.drawOval(Rect.fromCenter(center: ct + Offset(0, r * 0.85), width: r * 2.1, height: r * 0.45), Paint()..color = const Color(0x2A000000));
    c.drawRect(Rect.fromCenter(center: ct + Offset(0, r * 0.5), width: r * 0.28, height: r * 0.7), Paint()..color = _dk(th.wood, 0.35));
    final top = Rect.fromCenter(center: ct, width: r * 2.3, height: r * 1.15);
    c.drawOval(top.shift(Offset(0, r * 0.14)), Paint()..color = _dk(th.wood, 0.2));
    c.drawOval(top, Paint()..color = th.cloth);
    c.drawOval(top.deflate(r * 0.12), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, r * 0.04)
      ..color = _a(th.accent, 0.5));
    if (widget.style == 'night') {
      final cp = ct + Offset(-r * 0.72, -r * 0.05);
      c.drawCircle(cp, r * 0.45, Paint()..color = _a(const Color(0xFFFFE082), 0.18 + 0.08 * sin(t * 6 + i)));
      _emoji(c, '🕯️', cp, r * 0.38);
    } else if (widget.style == 'garden' || widget.style == 'sakura') {
      _emoji(c, widget.style == 'garden' ? '🌼' : '🌸', ct + Offset(-r * 0.72, -r * 0.05), r * 0.32);
    }
    if (glow) {
      final pulse = 0.5 + 0.5 * sin(t * 8);
      c.drawOval(top.inflate(3 + pulse * 3), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _a(const Color(0xFF00E676), 0.6 + 0.4 * pulse));
    }

    if (tb.dirty) {
      _emoji(c, '🍽️', ct + Offset(-r * 0.3, -r * 0.05), r * 0.65);
      c.drawOval(Rect.fromCenter(center: ct + Offset(r * 0.38, r * 0.12), width: r * 0.5, height: r * 0.22), Paint()..color = _a(const Color(0xFF795548), 0.35));
      final crumb = Paint()..color = const Color(0xFF8D6E63);
      c.drawCircle(ct + Offset(r * 0.5, -r * 0.15), r * 0.06, crumb);
      c.drawCircle(ct + Offset(r * 0.25, -r * 0.25), r * 0.05, crumb);
    } else if (cu != null && seated && cu.st == 2) {
      // món vừa mang ra thì "nảy" lên
      final ks = t - _serveAt[i];
      final pop = ks < 0.45 ? 1 + 0.6 * sin(ks / 0.45 * pi) : 1.0;
      drawDish(c, cu.recipe.id, ct - Offset(0, r * 0.18 * pop), r * 1.25 * pop, t: t);
      final ph = (t * 0.9 + i * 0.3) % 1.0;
      c.drawCircle(ct + Offset(sin(ph * 6) * r * 0.15, -r * 0.5 - ph * r * 0.6), r * 0.12 * (1 + ph), Paint()..color = _a(Colors.white, 0.5 * (1 - ph)));
    }

    final lab = _text('${i + 1}', r * 0.34, color: _dk(th.wood, 0.4), bold: true);
    lab.paint(c, ct + Offset(r * 0.78 - lab.width / 2, -lab.height / 2));
  }

  void _drawOverlay(Canvas c, int i, double t) {
    final tb = widget.tables[i];
    final cu = tb.c;
    final r = _r;
    final ct = _tc[i];

    // Hiệu ứng vừa dọn bàn: lấp lánh + bọt xà phòng
    final kc = t - _cleanAt[i];
    if (kc >= 0 && kc < 1.0) {
      final a = 1 - kc;
      for (var j = 0; j < 6; j++) {
        final ang = j * pi / 3 + 0.3 + kc;
        final rad = r * (0.4 + kc * 1.5);
        _emoji(c, '✨', ct + Offset(cos(ang) * rad, sin(ang) * rad * 0.6 - r * 0.2), r * 0.45, alpha: a);
      }
      for (var j = 0; j < 4; j++) {
        c.drawCircle(ct + Offset((j - 1.5) * r * 0.45 + sin(t * 6 + j) * 3, -kc * r * 1.4 - j * 3), r * (0.1 + 0.03 * j), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _a(const Color(0xFF4FC3F7), a));
      }
      if (kc < 0.8) _pill(c, '✨ Sạch bóng!', ct - Offset(0, r * 1.4 + kc * r * 0.5), max(9.0, r * 0.3), bg: const Color(0xFFE0F7FA), fg: const Color(0xFF006064));
    }

    if (tb.dirty) {
      final pulse = 0.88 + 0.12 * sin(t * 5);
      final bc = ct + Offset(r * 0.9, -r * 1.7);
      _bubble(c, bc, r * 1.0 * pulse, r * 0.9 * pulse, Colors.white);
      _emoji(c, '🧹', bc, r * 0.6 * pulse);
      return;
    }
    if (cu == null || t < _seatAt[i]) return;

    // Khách đặc biệt: bảng tên và câu chuyện khi vừa ngồi xuống
    final npc = npcById(cu.npc);
    if (npc != null) {
      final head = _seat(i) - Offset(0, (cu.npc == 'student' ? _s * 0.82 : _s) * 0.8);
      _pill(c, '${npc.emoji} ${npc.name}', head, max(9.0, r * 0.28), bg: const Color(0xFFFFF8E1), fg: const Color(0xFF6D4C41));
      final since = t - _seatAt[i];
      if (since < 4.5) {
        _speech(c, npc.lines[min(cu.line, npc.lines.length - 1)], head - Offset(0, r * 0.4), max(130.0, r * 4.5), max(10.0, r * 0.3));
      }
    }

    // Vừa được mang món: vòng sáng + bong bóng 😋
    final ks = t - _serveAt[i];
    if (cu.st == 2) {
      if (ks >= 0 && ks < 1.3) {
        final a = (1 - ks / 1.3).clamp(0.0, 1.0).toDouble();
        c.drawOval(Rect.fromCenter(center: ct, width: r * (2.3 + ks * 2.0), height: r * (1.15 + ks * 1.0)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _a(const Color(0xFFFFD54F), a));
        final bc = _seat(i) + Offset(r * 1.2, -_s * 0.6 - ks * r * 0.3);
        _bubble(c, bc, r * 1.1, r * 0.95, Colors.white);
        _emoji(c, '😋', bc, r * 0.6);
      }
      return;
    }
    final frac = (cu.pat / cu.maxPat).clamp(0.0, 1.0).toDouble();
    final sel = widget.selDishId != null && widget.selDishId == cu.ticketId;
    final bw = r * 1.35, bh = r * 1.1;
    final bounce = cu.st == 0 ? sin(t * 7).abs() * r * 0.12 : 0.0;
    final bc = _seat(i) + Offset(r * 1.2, -_s * 0.6 - bounce);
    _bubble(c, bc, bw, bh, sel ? const Color(0xFFC8E6C9) : Colors.white, border: sel ? Colors.green : null);
    if (cu.st == 0) {
      _emoji(c, '❗', bc, r * 0.6);
    } else {
      drawDish(c, cu.recipe.id, bc, r * 1.0);
    }

    final barR = Rect.fromLTWH(bc.dx - bw / 2, bc.dy + bh / 2 + 3, bw, max(4.0, r * 0.14));
    c.drawRRect(RRect.fromRectAndRadius(barR, const Radius.circular(3)), Paint()..color = const Color(0x55000000));
    final Color col = frac < 0.35 ? const Color(0xFFFF5252) : (frac < 0.6 ? const Color(0xFFFF9800) : const Color(0xFF8BC34A));
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(barR.left, barR.top, barR.width * frac, barR.height), const Radius.circular(3)),
      Paint()..color = col,
    );
  }
}

class _DiningPainter extends CustomPainter {
  final _DiningSceneState st;
  _DiningPainter(this.st) : super(repaint: st._clock);
  @override
  void paint(Canvas canvas, Size size) => st._paint(canvas, size);
  @override
  bool shouldRepaint(covariant _DiningPainter oldDelegate) => true;
}

// =====================================================================
//  NHÀ BẾP (vai ĐẦU BẾP)
// =====================================================================
class KitchenScene extends StatefulWidget {
  final List<Station> stations;
  final int activeStation;
  final bool hasOrders;
  final String venueId, style;
  final double burnTime;
  final Look chefLook;
  final String chefName;
  final String Function(String) ingEmoji;
  final void Function(int) onStation;
  final List<Incident> incidents;
  final String seasonEmoji;
  final void Function(int)? onIncident;
  final void Function(int, double)? onHeat; // vặn lửa − / +
  final void Function(int, String)? onDrop; // kéo nguyên liệu thả vào bếp
  final bool island; // đảo bếp nhỏ gọn đặt giữa sảnh
  const KitchenScene({
    super.key,
    required this.stations,
    required this.activeStation,
    required this.hasOrders,
    required this.venueId,
    required this.ingEmoji,
    required this.onStation,
    this.style = 'classic',
    this.burnTime = 7,
    this.chefLook = nguyenLook,
    this.chefName = kNguyen,
    this.incidents = const [],
    this.seasonEmoji = '🧂',
    this.onIncident,
    this.onHeat,
    this.onDrop,
    this.island = false,
  });

  @override
  State<KitchenScene> createState() => _KitchenSceneState();
}

class _KitchenSceneState extends State<KitchenScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  double _cx = -1; // vị trí x của đầu bếp (pixel)
  bool _walking = false, _left = true;
  double _phase = 0, _cheerUntil = -1;
  int _target = 0;
  Size _size = Size.zero;
  // Theo dõi để chạy hoạt cảnh "nấu xong" và "mang ra quầy"
  List<bool> _doneP = [], _burntP = [], _cookP = [];
  List<int> _addedP = [], _mistP = [];
  List<double> _doneAt = [], _sentAt = [];
  List<String> _lastEmoji = [], _sentEmoji = [];
  List<int> _chopKey = [];
  List<double> _saltP = [], _heatP = [], _knifeAt = [], _shakeAt = [];
  final Map<int, String> _incP = {};
  int _hoverSt = -1; // bếp đang được kéo nguyên liệu tới
  Rect _fuse = Rect.zero; // hộp cầu dao
  double _ox = 0, _cw = 1; // lề trái và bề rộng mỗi bếp (các bếp được dồn gọn vào giữa)

  @override
  void initState() {
    super.initState();
    _sync(initial: true);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant KitchenScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _sync({bool initial = false}) {
    final st = widget.stations;
    final n = st.length;
    var first = initial;
    final t = _clock.value;
    if (_doneP.length != n) {
      _doneP = List.filled(n, false);
      _burntP = List.filled(n, false);
      _cookP = List.filled(n, false);
      _addedP = List.filled(n, 0);
      _mistP = List.filled(n, 0);
      _doneAt = List.filled(n, -10.0);
      _sentAt = List.filled(n, -10.0);
      _lastEmoji = List.filled(n, '');
      _sentEmoji = List.filled(n, '');
      _chopKey = List.filled(n, 0);
      _saltP = List.filled(n, 0.0);
      _heatP = List.filled(n, 0.5);
      _knifeAt = List.filled(n, -10.0);
      _shakeAt = List.filled(n, -10.0);
      first = true;
    }
    for (var i = 0; i < n; i++) {
      final d = st[i].done;
      if (!first && d && !_doneP[i]) {
        _doneAt[i] = t;
        _cheerUntil = t + 0.9;
        Sound.sfx('ding');
      }
      if (!first && _doneP[i] && st[i].t == null) {
        _sentAt[i] = t;
        _sentEmoji[i] = _lastEmoji[i];
        Sound.sfx('whoosh', vol: 0.8);
      }
      if (!first) {
        if (st[i].burnt && !_burntP[i]) Sound.sfx('burn');
        if (st[i].cooking && !_cookP[i]) Sound.sfx('sizzle', vol: 0.7);
        if (st[i].added.length > _addedP[i]) Sound.sfx('plop');
        if (st[i].mistakes > _mistP[i]) Sound.sfx('wrong');
      }
      _burntP[i] = st[i].burnt;
      _cookP[i] = st[i].cooking;
      _addedP[i] = st[i].added.length;
      _mistP[i] = st[i].mistakes;
      // thái, nêm, vặn lửa
      final key = st[i].board.length * 100 + st[i].chopLeft;
      if (!first && key < _chopKey[i] && (st[i].chopLeft < _chopKey[i] % 100 || st[i].board.length < _chopKey[i] ~/ 100)) {
        _knifeAt[i] = t;
        Sound.sfx('chop');
      }
      _chopKey[i] = key;
      if (!first && st[i].salt > _saltP[i] + 0.01) {
        _shakeAt[i] = t;
        Sound.sfx('shake');
      }
      _saltP[i] = st[i].salt;
      if (!first && (st[i].heat - _heatP[i]).abs() > 0.12) Sound.sfx('knob', vol: 0.6);
      _heatP[i] = st[i].heat;
      final tk = st[i].t;
      if (tk != null) _lastEmoji[i] = tk.recipe.id;
      _doneP[i] = d;
    }
    // Âm thanh sự cố trong bếp
    final now = <int, String>{for (final x in widget.incidents) x.id: x.type};
    for (final e in now.entries) {
      if (!_incP.containsKey(e.key) && !first) {
        if (e.value == 'fire') Sound.sfx('alarm');
        if (e.value == 'power') Sound.sfx('powerdown');
      }
    }
    for (final e in _incP.entries) {
      if (!now.containsKey(e.key) && !first && (e.value == 'fire' || e.value == 'power')) Sound.sfx('fixed');
    }
    _incP
      ..clear()
      ..addAll(now);
  }

  int _stationAt(double x) {
    final n = widget.stations.length;
    if (n == 0 || _size.width <= 0 || _cw <= 0) return -1;
    return min(max(((x - _ox) / _cw).floor(), 0), n - 1);
  }

  int get _chefAt {
    final n = widget.stations.length;
    if (n == 0) return 0;
    final a = widget.activeStation;
    if (a >= 0 && a < n) return a;
    return min(max(_target, 0), n - 1);
  }

  void _onTick(Duration e) {
    final t = e.inMicroseconds / 1e6;
    final dt = (t - _clock.value).clamp(0.0, 0.1).toDouble();
    final n = widget.stations.length;
    if (_size != Size.zero && n > 0) {
      final cellW = _cw;
      final tx = _ox + cellW * (_chefAt + 0.5) + cellW * (widget.island ? 0.0 : 0.3);
      if (_cx < 0) _cx = tx;
      final d = tx - _cx;
      final step = max(_size.width, 300.0) * 0.8 * dt;
      if (d.abs() > 1) {
        _cx += d.abs() <= step ? d : d.sign * step;
        _walking = true;
        _left = d < 0;
        _phase += dt * 14;
      } else {
        _walking = false;
      }
    }
    _clock.value = t;
  }

  void _tap(TapUpDetails d) {
    final p = d.localPosition;
    // 1) Hộp cầu dao khi mất điện
    if (_fuse.inflate(8).contains(p)) {
      for (final x in widget.incidents) {
        if (x.type == 'power') {
          widget.onIncident?.call(x.id);
          return;
        }
      }
    }
    final i = _stationAt(p.dx);
    if (i < 0) return;
    _target = i;
    // 2) Bếp đang cháy
    for (final x in widget.incidents) {
      if (x.type == 'fire' && x.target == i) {
        widget.onIncident?.call(x.id);
        return;
      }
    }
    // 3) Núm vặn lửa (đang nấu): nửa trái giảm, nửa phải tăng
    final s = widget.stations[i];
    final h = _size.height;
    if (!widget.island && s.cooking && p.dy > h * 0.36 && p.dy < h * 0.53) {
      widget.onHeat?.call(i, p.dx < _ox + _cw * (i + 0.5) ? -0.2 : 0.2);
      return;
    }
    // 4) Thao tác bếp: nhận đơn / thái / lấy món
    widget.onStation(i);
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
        onMove: (det) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          _hoverSt = _stationAt(box.globalToLocal(det.offset + const Offset(28, 28)).dx);
        },
        onLeave: (_) => _hoverSt = -1,
        onAcceptWithDetails: (det) {
          final box = context.findRenderObject() as RenderBox?;
          _hoverSt = -1;
          if (box == null) return;
          final i = _stationAt(box.globalToLocal(det.offset + const Offset(28, 28)).dx);
          if (i >= 0) {
            _target = i;
            widget.onDrop?.call(i, det.data);
          }
        },
        builder: (ctx, cand, rej) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _tap,
          child: SizedBox.expand(child: CustomPaint(painter: _KitchenPainter(this))),
        ),
      );

  void _paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    if (w < 40 || h < 40) return;
    _size = sz;
    final th = themeFor(widget.venueId, widget.style);
    final st = widget.stations;
    final n = st.length;
    final t = _clock.value;

    // Tường gạch men
    final wallB = h * 0.62;
    c.drawRect(Rect.fromLTWH(0, 0, w, wallB), Paint()..color = widget.style == 'night' ? const Color(0xFFDCD8E8) : const Color(0xFFF4F0EA));
    final grout = Paint()
      ..color = const Color(0xFFDDD5C8)
      ..strokeWidth = 1;
    const tw = 34.0, tth = 17.0;
    for (var row = 0; row * tth < wallB; row++) {
      final y = row * tth;
      c.drawLine(Offset(0, y), Offset(w, y), grout);
      final off = row.isOdd ? tw / 2 : 0.0;
      for (double x = off; x < w; x += tw) {
        c.drawLine(Offset(x, y), Offset(x, min(y + tth, wallB)), grout);
      }
    }
    // Sàn
    c.drawRect(Rect.fromLTWH(0, wallB, w, h - wallB), Paint()..color = const Color(0xFF8F8F8F));
    const ft = 28.0;
    final fp = Paint()..color = const Color(0xFF7C7C7C);
    for (var y = 0; wallB + y * ft < h; y++) {
      for (var x = 0; x * ft < w; x++) {
        if ((x + y).isOdd) c.drawRect(Rect.fromLTWH(x * ft, wallB + y * ft, ft, ft), fp);
      }
    }
    c.drawRect(Rect.fromLTWH(0, wallB - 6, w, 6), Paint()..color = th.wall);
    if (n == 0) return;

    final cellW = w / n;
    _cw = cellW;
    _ox = 0;
    for (var i = 0; i < n; i++) {
      _drawStove(c, i, cellW, h, t);
    }

    // Đầu bếp
    final cs = min(h * 0.45, cellW * 0.95);
    if (_cx < 0) _cx = cellW * (_chefAt + 0.5) + cellW * 0.3;
    final at = _chefAt;
    final cheer = t < _cheerUntil && !_walking;
    final stirring = !_walking && !cheer && at < n && st[at].cooking;
    final anyBurnt = st.any((x) => x.burnt);
    drawPerson(
      c,
      Offset(_cx, h * 0.97),
      cs,
      widget.chefLook,
      role: 'chef',
      walking: _walking,
      phase: _phase,
      facingLeft: _walking ? _left : true,
      mood: anyBurnt ? 2 : 0,
      armUp: cheer,
      bob: cheer ? sin((_cheerUntil - t) / 0.9 * pi).abs() * cs * 0.08 : 0.0,
      stir: stirring ? t * 8 : -1,
      name: widget.chefName,
    );

    if (_hoverSt >= 0 && _hoverSt < n) {
      final hr = RRect.fromRectAndRadius(Rect.fromLTWH(cellW * _hoverSt + 3, 3, cellW - 6, h - 6), const Radius.circular(14));
      c.drawRRect(hr, Paint()..color = _a(const Color(0xFF66BB6A), 0.15));
      c.drawRRect(hr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF66BB6A));
    }

    // Hộp cầu dao (góc trên phải)
    final power = widget.incidents.any((x) => x.type == 'power');
    if (power) c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x8C000000));
    _fuse = Rect.fromLTWH(w - 44, 4, 38, 30);
    final blink = power && sin(t * 10) > 0;
    c.drawRRect(RRect.fromRectAndRadius(_fuse, const Radius.circular(5)), Paint()..color = blink ? const Color(0xFFFF5252) : const Color(0xFF78909C));
    c.drawRRect(RRect.fromRectAndRadius(_fuse.deflate(3), const Radius.circular(3)), Paint()..color = const Color(0xFF37474F));
    _emoji(c, '⚡', _fuse.center, 16);
    if (power) _pill(c, '⚡ Mất điện! Chọn 🔌 rồi chạm cầu dao', Offset(w / 2, h * 0.5), min(13.0, w * 0.035), bg: const Color(0xFFFFF59D));
  }

  void _drawStove(Canvas c, int i, double cellW, double h, double t) {
    final s = widget.stations[i];
    final x0 = cellW * i;
    final cx = x0 + cellW / 2;
    final pad = max(4.0, cellW * 0.06);
    final active = i == widget.activeStation;
    final topY = h * 0.40, botY = h * 0.80;
    final body = Rect.fromLTRB(x0 + pad, topY, x0 + cellW - pad, botY);
    final tk = s.t;
    final fs = min(h * 0.055, cellW * 0.13);

    if (active) {
      final hl = RRect.fromRectAndRadius(Rect.fromLTRB(x0 + 2, 2, x0 + cellW - 2, botY + 4), const Radius.circular(14));
      c.drawRRect(hl, Paint()..color = _a(const Color(0xFF42A5F5), 0.12));
      c.drawRRect(hl, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF42A5F5));
    }

    // Thân bếp
    var steel = const Color(0xFFB0BEC5);
    if (s.done) steel = s.burnt ? const Color(0xFFEF9A9A) : const Color(0xFFA5D6A7);
    c.drawRRect(RRect.fromRectAndRadius(body.shift(const Offset(0, 3)), const Radius.circular(8)), Paint()..color = const Color(0x33000000));
    c.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(8)), Paint()..color = steel);
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(body.left - 2, topY - 4, body.right + 2, topY + h * 0.04), const Radius.circular(4)),
      Paint()..color = const Color(0xFF37474F),
    );
    if (s.cooking) {
      // núm vặn lửa: − bên trái, + bên phải
      final kr = max(9.0, h * 0.045);
      for (final side in const [-1.0, 1.0]) {
        final kc = Offset(cx + side * body.width * 0.3, topY + h * 0.075);
        c.drawCircle(kc, kr, Paint()..color = const Color(0xFF263238));
        c.drawCircle(kc, kr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = side < 0 ? const Color(0xFF4FC3F7) : const Color(0xFFFF7043));
        final lab = _text(side < 0 ? '−' : '+', kr * 1.3, color: Colors.white, bold: true);
        lab.paint(c, kc - Offset(lab.width / 2, lab.height / 2));
      }
    } else {
      for (var k = 0; k < 3; k++) {
        c.drawCircle(Offset(body.left + body.width * (0.25 + 0.25 * k), topY + h * 0.075), max(2.5, h * 0.018), Paint()..color = const Color(0xFF455A64));
      }
    }
    final ov = Rect.fromLTRB(body.left + body.width * 0.12, topY + h * 0.13, body.right - body.width * 0.12, botY - h * 0.04);
    c.drawLine(Offset(ov.left + 6, ov.top - h * 0.025), Offset(ov.right - 6, ov.top - h * 0.025), Paint()
      ..color = const Color(0xFF546E7A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
    c.drawRRect(RRect.fromRectAndRadius(ov, const Radius.circular(6)), Paint()..color = const Color(0xFF263238));
    if (s.cooking) {
      c.drawRRect(RRect.fromRectAndRadius(ov.deflate(3), const Radius.circular(4)), Paint()..color = _a(const Color(0xFFFF7043), 0.35 + 0.15 * sin(t * 6 + i)));
    }

    // Lửa + nồi
    final potW = min(cellW * 0.55, h * 0.26), potH = h * 0.10;
    final potRect = Rect.fromCenter(center: Offset(cx, topY - h * 0.03 - potH / 2), width: potW, height: potH);
    if (s.cooking) {
      for (var k = -1; k <= 1; k++) {
        final fl = 1 + 0.25 * sin(t * 18 + k * 2.0 + i);
        final fx = cx + k * potW * 0.28;
        final fh = h * (0.015 + 0.05 * s.heat) * fl; // lửa to nhỏ theo núm vặn
        final flame = Path()
          ..moveTo(fx - fh * 0.5, topY - 1)
          ..quadraticBezierTo(fx, topY - fh * 1.9, fx + fh * 0.5, topY - 1)
          ..close();
        c.drawPath(flame, Paint()..color = const Color(0xFFFF9800));
        c.drawCircle(Offset(fx, topY - fh * 0.35), fh * 0.22, Paint()..color = const Color(0xFFFFEB3B));
      }
    }
    final potColor = s.burnt ? const Color(0xFF212121) : const Color(0xFF78909C);
    // nắp nồi rung khi đang nấu
    final shake = s.cooking ? sin(t * 30 + i) * 1.2 : 0.0;
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(potRect.right - 2, potRect.top + potH * 0.2, potW * 0.22, potH * 0.18), const Radius.circular(3)),
      Paint()..color = const Color(0xFF5D4037),
    );
    c.drawRRect(
      RRect.fromRectAndCorners(
        potRect,
        bottomLeft: Radius.circular(potH * 0.4),
        bottomRight: Radius.circular(potH * 0.4),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..color = potColor,
    );
    c.drawOval(Rect.fromCenter(center: potRect.topCenter + Offset(shake, 0), width: potW, height: potH * 0.35), Paint()..color = _dk(potColor, 0.3));
    c.drawRect(Rect.fromLTWH(potRect.left + potW * 0.12, potRect.top + potH * 0.3, potW * 0.08, potH * 0.45), Paint()..color = _a(Colors.white, 0.35));

    // Nguyên liệu đã thả vào nồi
    if (tk != null && !s.done && !s.cooking && s.added.isNotEmpty) {
      var k = 0;
      for (final id in tk.recipe.ings) {
        if (!s.added.contains(id)) continue;
        _emoji(c, widget.ingEmoji(id), potRect.topCenter + Offset((k - (s.added.length - 1) / 2) * potH * 0.45, -potH * 0.15), potH * 0.45);
        k++;
      }
    }

    // Hơi nước / khói
    if (s.cooking || s.done) {
      final smoke = s.burnt;
      for (var k = 0; k < 3; k++) {
        final ph = (t * (smoke ? 0.6 : 0.8) + k / 3 + i * 0.17) % 1.0;
        final sp = potRect.topCenter + Offset(sin(ph * 6 + k) * potW * 0.2, -ph * h * 0.16);
        c.drawCircle(
          sp,
          potH * (0.25 + 0.35 * ph) * (smoke ? 1.5 : 1),
          Paint()..color = _a(smoke ? const Color(0xFF424242) : Colors.white, (1 - ph) * (smoke ? 0.7 : 0.6)),
        );
      }
    }
    if (s.done && tk != null) {
      final b = sin(t * 5).abs() * h * 0.015;
      drawDish(c, tk.recipe.id, potRect.topCenter - Offset(0, potW * 0.36 + b), potW * 1.15, t: t, burnt: s.burnt);
      if (!s.burnt) {
        _emoji(c, '✨', potRect.topCenter + Offset(potW * 0.45, -potH * 1.0), potH * 0.55, alpha: 0.4 + 0.6 * sin(t * 6).abs());
      }
    }

    // Hoạt cảnh "Nấu xong!": vòng sáng + sao bung ra + chuông
    final kd = t - _doneAt[i];
    if (kd >= 0 && kd < 1.0) {
      final a = 1 - kd;
      final ctr = potRect.topCenter;
      c.drawCircle(ctr, potW * 0.3 + kd * cellW * 0.45, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + 4 * a
        ..color = _a(const Color(0xFFFFD54F), a));
      for (var j = 0; j < 8; j++) {
        final ang = j * pi / 4 + kd;
        final rad = potW * 0.3 + kd * cellW * 0.5;
        _emoji(c, '⭐', ctr + Offset(cos(ang) * rad, sin(ang) * rad * 0.7), potH * 0.5, alpha: a);
      }
      final sc = kd < 0.25 ? 0.6 + kd / 0.25 * 0.6 : 1.2 - min(0.2, kd - 0.25);
      _pill(c, '🔔 Xong rồi!', ctr - Offset(0, potH * 1.9), fs * 0.9 * sc, bg: const Color(0xFFFFF59D));
    }
    // Hoạt cảnh mang món ra quầy: món bay lên
    final ks = t - _sentAt[i];
    if (ks >= 0 && ks < 0.7 && _sentEmoji[i].isNotEmpty) {
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, (1 - ks / 0.7).clamp(0.0, 1.0).toDouble()));
      drawDish(c, _sentEmoji[i], potRect.topCenter - Offset(0, potW * 0.36 + ks * h * 0.35), potW * 1.15 * (1 + ks * 0.3), t: t);
      c.restore();
    }

    // Đồng hồ lửa: vùng xanh là lửa chuẩn
    if (s.cooking) {
      final g = Rect.fromLTWH(body.left + 3, ov.top, 7, ov.height);
      c.drawRRect(RRect.fromRectAndRadius(g, const Radius.circular(3)), Paint()..color = const Color(0xFF263238));
      c.drawRect(Rect.fromLTRB(g.left, g.bottom - g.height * 0.75, g.right, g.bottom - g.height * 0.3), Paint()..color = _a(const Color(0xFF66BB6A), 0.6));
      final hy = g.bottom - g.height * s.heat;
      final Color hc = s.heat < 0.3 ? const Color(0xFF4FC3F7) : (s.heat <= 0.75 ? const Color(0xFF66BB6A) : const Color(0xFFFF5252));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(g.left - 2, hy - 2.5, g.right + 2, hy + 2.5), const Radius.circular(2)), Paint()..color = hc);
    }

    // Thớt: chạm bếp để thái từng nhát
    if (s.chopping) {
      final bd = Rect.fromCenter(center: Offset(cx + 4, ov.center.dy + h * 0.01), width: ov.width * 0.95, height: ov.height * 0.62);
      c.drawRRect(RRect.fromRectAndRadius(bd, const Radius.circular(8)), Paint()..color = const Color(0xFFBC8A5F));
      c.drawRRect(RRect.fromRectAndRadius(bd.deflate(3), const Radius.circular(6)), Paint()..color = const Color(0xFFD7A86E));
      final item = s.board.first;
      final isz = min(bd.height * 0.7, bd.width * 0.35);
      final cutTotal = max(1, s.chopLeft);
      _emoji(c, widget.ingEmoji(item), Offset(bd.left + bd.width * 0.3, bd.center.dy), isz);
      // miếng đã thái
      for (var k = 0; k < 3 - min(3, cutTotal - 1); k++) {
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bd.left + bd.width * (0.62 + 0.1 * k), bd.center.dy + isz * 0.25), width: isz * 0.22, height: isz * 0.14), const Radius.circular(2)),
          Paint()..color = const Color(0xFFE57373),
        );
      }
      final kn = t - _knifeAt[i];
      final down = kn < 0.12;
      _emoji(c, '🔪', Offset(bd.left + bd.width * 0.55, bd.center.dy - (down ? isz * 0.05 : isz * 0.45 + sin(t * 4).abs() * 3)), isz * 0.8);
      _pill(c, '🔪 Chạm để thái ×${s.chopLeft}${s.board.length > 1 ? '  (+${s.board.length - 1})' : ''}', Offset(cx, bd.bottom + fs * 0.6), fs * 0.7, bg: const Color(0xFFFFF3E0));
    }

    // Cháy bếp
    for (final x in widget.incidents) {
      if (x.type != 'fire' || x.target != i) continue;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x0 + 2, h * 0.12, x0 + cellW - 2, botY), const Radius.circular(12)), Paint()..color = _a(const Color(0xFFFF6D00), 0.22 + 0.1 * sin(t * 12)));
      for (var k = 0; k < 5; k++) {
        final fx = x0 + cellW * (0.15 + 0.175 * k);
        final fh = h * (0.18 + 0.08 * sin(t * 14 + k * 1.7));
        final path = Path()
          ..moveTo(fx - cellW * 0.09, topY + h * 0.05)
          ..quadraticBezierTo(fx + sin(t * 9 + k) * 6, topY - fh, fx + cellW * 0.09, topY + h * 0.05)
          ..close();
        c.drawPath(path, Paint()..color = k.isEven ? const Color(0xFFFF6D00) : const Color(0xFFFFAB00));
      }
      for (var k = 0; k < 3; k++) {
        final ph = (t * 0.5 + k / 3) % 1.0;
        c.drawCircle(Offset(cx + sin(ph * 5 + k) * cellW * 0.2, topY - h * 0.15 - ph * h * 0.2), cellW * (0.08 + 0.1 * ph), Paint()..color = _a(const Color(0xFF424242), 0.6 * (1 - ph)));
      }
      _pill(c, '🔥 CHÁY! 🧯×${x.hp}', Offset(cx, topY + h * 0.2), fs * 0.85, bg: const Color(0xFFFFCDD2), fg: const Color(0xFFB71C1C));
    }

    // Thông tin đơn
    if (tk == null) {
      final b = widget.hasOrders ? sin(t * 6).abs() * 3 : 0.0;
      _pill(
        c,
        widget.hasOrders ? '👆 Nhận đơn' : 'Bếp trống',
        Offset(cx, h * 0.09 - b),
        fs * 0.9,
        bg: widget.hasOrders ? const Color(0xFFFFF59D) : Colors.white,
        fg: widget.hasOrders ? const Color(0xFF3E2723) : const Color(0xFF9E9E9E),
      );
      return;
    }
    drawDish(c, tk.recipe.id, Offset(cx - fs * 1.9, h * 0.07), fs * 2.3, t: t);
    _pill(c, 'B${tk.table + 1}', Offset(cx + fs * 0.6, h * 0.07), fs);
    if (!s.done) {
      final ings = tk.recipe.ings;
      final isz = min(cellW * 0.8 / ings.length, h * 0.075);
      for (var k = 0; k < ings.length; k++) {
        final ip = Offset(cx + (k - (ings.length - 1) / 2) * isz * 1.15, h * 0.175);
        final got = s.added.contains(ings[k]);
        final onBoard = s.board.contains(ings[k]);
        c.drawCircle(ip, isz * 0.58, Paint()..color = got ? const Color(0xFFC8E6C9) : (onBoard ? const Color(0xFFFFE082) : Colors.white));
        c.drawCircle(ip, isz * 0.58, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = got ? Colors.green : const Color(0xFFBDBDBD));
        _emoji(c, widget.ingEmoji(ings[k]), ip, isz * 0.75, alpha: got ? 0.35 : 1);
      }
    }
    // Thanh nêm nếm: vùng xanh là vừa miệng (mỗi lần rắc không đều tay)
    if (!s.burnt) {
      const maxSalt = 5.0;
      final mb = Rect.fromCenter(center: Offset(cx + fs * 0.6, h * 0.255), width: cellW * 0.62, height: max(5.0, h * 0.022));
      c.drawRRect(RRect.fromRectAndRadius(mb, const Radius.circular(3)), Paint()..color = const Color(0xFFECEFF1));
      final z0 = ((s.saltTarget - s.tol) / maxSalt).clamp(0.0, 1.0).toDouble();
      final z1 = ((s.saltTarget + s.tol) / maxSalt).clamp(0.0, 1.0).toDouble();
      c.drawRect(Rect.fromLTRB(mb.left + mb.width * z0, mb.top, mb.left + mb.width * z1, mb.bottom), Paint()..color = _a(const Color(0xFF66BB6A), 0.7));
      final sx = mb.left + mb.width * (s.salt / maxSalt).clamp(0.0, 1.0).toDouble();
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx, mb.center.dy), width: 4, height: mb.height + 6), const Radius.circular(2)), Paint()..color = const Color(0xFF3E2723));
      final shaking = t - _shakeAt[i] < 0.3;
      _emoji(c, widget.seasonEmoji, Offset(mb.left - fs * 0.8, mb.center.dy - (shaking ? sin(t * 40) * 3 : 0)), fs * 1.0);
    }

    // Trạng thái trên cửa lò
    String label;
    Color bg;
    if (s.done) {
      label = s.burnt ? '🔥 Cháy!' : '✅ Lấy món!';
      bg = s.burnt ? const Color(0xFFFFCDD2) : const Color(0xFFC8E6C9);
    } else if (s.cooking) {
      label = '⏳ ${max(0.0, s.need - s.prog).ceil()}s';
      bg = const Color(0xFFFFE0B2);
    } else if (s.chopping) {
      label = '';
      bg = Colors.white;
    } else {
      label = 'Kéo / chạm nguyên liệu';
      bg = Colors.white;
    }
    if (label.isNotEmpty) _pill(c, label, Offset(cx + 4, ov.center.dy - h * 0.02), fs * 0.72, bg: bg);

    final bar = Rect.fromLTWH(ov.left + 5, ov.bottom - 9, ov.width - 10, 5);
    double? frac;
    Color barC = const Color(0xFFFFB300);
    if (s.cooking) {
      frac = s.need <= 0 ? 0.0 : (s.prog / s.need).clamp(0.0, 1.0).toDouble();
    } else if (s.done && !s.burnt) {
      frac = (1 - s.doneT / widget.burnTime).clamp(0.0, 1.0).toDouble(); // thời gian còn lại trước khi cháy
      barC = const Color(0xFFFF5252);
    }
    if (frac != null) {
      c.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = const Color(0x55FFFFFF));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * frac, bar.height), const Radius.circular(3)), Paint()..color = barC);
    }
  }
}

class _KitchenPainter extends CustomPainter {
  final _KitchenSceneState st;
  _KitchenPainter(this.st) : super(repaint: st._clock);
  @override
  void paint(Canvas canvas, Size size) => st._paint(canvas, size);
  @override
  bool shouldRepaint(covariant _KitchenPainter oldDelegate) => true;
}

// =====================================================================
//  ĂN MỪNG: pháo hoa + giấy màu, và Nguyên & Ngọc Anh nhảy múa
// =====================================================================
const _confColors = [Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFF40C4FF), Color(0xFFE040FB), Color(0xFFFF6E40)];

/// Lớp giấy màu (và pháo hoa) phủ lên màn hình, không chặn thao tác chạm.
/// [duration] > 0: chỉ bắn một đợt rồi tắt dần; <= 0: rơi mãi.
class ConfettiLayer extends StatefulWidget {
  final double duration;
  final bool fireworks;
  final bool sound;
  const ConfettiLayer({super.key, this.duration = 0, this.fireworks = true, this.sound = true});
  @override
  State<ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<ConfettiLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  int _boom = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _clock.value = e.inMicroseconds / 1e6;
      // mỗi quả pháo hoa nổ một tiếng (chỉ ~8 quả đầu cho đỡ ồn)
      final k = (_clock.value / 0.7).floor();
      if (widget.fireworks && widget.sound && k != _boom && k < 8) {
        _boom = k;
        Sound.sfx('firework', vol: 0.45);
      }
      if (widget.duration > 0 && _clock.value > widget.duration + 1.2) _ticker.stop();
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: SizedBox.expand(child: CustomPaint(painter: _ConfettiPainter(this))));
}

class _ConfettiPainter extends CustomPainter {
  final _ConfettiLayerState st;
  _ConfettiPainter(this.st) : super(repaint: st._clock);

  @override
  void paint(Canvas c, Size sz) {
    final t = st._clock.value;
    final w = sz.width, h = sz.height;
    final dur = st.widget.duration;
    final fade = dur > 0 ? (1 - (t - dur)).clamp(0.0, 1.0).toDouble() : 1.0;
    if (fade <= 0) return;

    // Pháo hoa
    if (st.widget.fireworks) {
      const period = 0.7;
      final kNow = (t / period).floor();
      for (var k = max(0, kNow - 2); k <= kNow; k++) {
        final tb = t - k * period;
        if (tb < 0 || tb > 1.4) continue;
        final rr = Random(k * 7 + 3);
        final cen = Offset(w * (0.15 + 0.7 * rr.nextDouble()), h * (0.10 + 0.35 * rr.nextDouble()));
        final col = _confColors[rr.nextInt(_confColors.length)];
        final a = (1 - tb / 1.4) * fade;
        final rad = tb * min(w, h) * 0.28 * (1 - tb * 0.25);
        final trail = Paint()
          ..color = _a(col, a * 0.6)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        for (var j = 0; j < 20; j++) {
          final ang = j * 2 * pi / 20;
          final p1 = cen + Offset(cos(ang) * rad, sin(ang) * rad + tb * tb * 30);
          final p0 = cen + Offset(cos(ang) * rad * 0.75, sin(ang) * rad * 0.75 + tb * tb * 22);
          c.drawLine(p0, p1, trail);
          c.drawCircle(p1, 4.5, Paint()..color = _a(col, a * 0.5));
          c.drawCircle(p1, 2.4, Paint()..color = _a(Colors.white, a));
        }
        if (tb < 0.15) c.drawCircle(cen, 4 + 18 * (1 - tb / 0.15), Paint()..color = _a(Colors.white, 0.8 * fade));
      }
    }

    // Giấy màu
    final rnd = Random(42);
    for (var k = 0; k < 90; k++) {
      final x0 = rnd.nextDouble() * w;
      final vy = 70 + rnd.nextDouble() * 110;
      final off = rnd.nextDouble();
      final rot = (rnd.nextDouble() - 0.5) * 8;
      final size = 5 + rnd.nextDouble() * 5;
      final col = _confColors[k % _confColors.length];
      final y = dur > 0 ? -20 - off * h * 0.6 + t * vy * 1.4 : (off * (h + 40) + t * vy) % (h + 40) - 20;
      if (y < -20 || y > h + 20) continue;
      final x = x0 + sin(t * 2 + k) * 18;
      final flip = cos(t * 4 + k).abs();
      c.save();
      c.translate(x, y);
      c.rotate(t * rot);
      c.drawRect(Rect.fromCenter(center: Offset.zero, width: size, height: size * 0.5 * (0.3 + flip)), Paint()..color = _a(col, fade));
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

/// Hai nhân vật đứng cạnh nhau: vui thì nhảy múa giơ tay, buồn thì cúi mặt.
class DancingCouple extends StatefulWidget {
  final bool happy;
  final Look left, right;
  final String leftName, rightName, leftRole, rightRole;
  final double height;
  const DancingCouple({
    super.key,
    required this.happy,
    required this.left,
    required this.right,
    required this.leftName,
    required this.rightName,
    this.leftRole = 'chef',
    this.rightRole = 'waiter',
    this.height = 170,
  });
  @override
  State<DancingCouple> createState() => _DancingCoupleState();
}

class _DancingCoupleState extends State<DancingCouple> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);

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

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(painter: _CouplePainter(this)),
      );
}

class _CouplePainter extends CustomPainter {
  final _DancingCoupleState st;
  _CouplePainter(this.st) : super(repaint: st._clock);

  @override
  void paint(Canvas c, Size sz) {
    final t = st._clock.value;
    final wd = st.widget;
    final s = sz.height * 0.66;
    final y = sz.height * 0.97;
    final xl = sz.width / 2 - s * 0.45, xr = sz.width / 2 + s * 0.45;
    if (wd.happy) {
      final jl = sin(t * 7).abs() * s * 0.12;
      final jr = sin(t * 7 + pi / 2).abs() * s * 0.12;
      drawPerson(c, Offset(xl, y), s, wd.left, role: wd.leftRole, armUp: sin(t * 7) > -0.2, bob: jl, mood: 0, name: wd.leftName);
      drawPerson(c, Offset(xr, y), s, wd.right, role: wd.rightRole, armUp: sin(t * 7 + pi / 2) > -0.2, bob: jr, mood: 0, facingLeft: true, name: wd.rightName);
      final hp = 0.9 + 0.15 * sin(t * 8);
      _emoji(c, '💕', Offset(sz.width / 2, y - s * 0.95), s * 0.2 * hp);
      _emoji(c, '🏆', Offset(sz.width / 2, y - s * 0.35 - sin(t * 4).abs() * s * 0.05), s * 0.28);
    } else {
      drawPerson(c, Offset(xl, y), s, wd.left, role: wd.leftRole, mood: 1, name: wd.leftName);
      drawPerson(c, Offset(xr, y), s, wd.right, role: wd.rightRole, mood: 1, facingLeft: true, name: wd.rightName);
      _emoji(c, '🌧️', Offset(sz.width / 2, y - s * 1.05 + sin(t * 2) * 2), s * 0.22);
      _emoji(c, '💪', Offset(sz.width / 2, y - s * 0.4), s * 0.2);
    }
  }

  @override
  bool shouldRepaint(covariant _CouplePainter oldDelegate) => true;
}

// =====================================================================
//  CHÂN DUNG NHÂN VẬT (màn chọn chủ quán)
// =====================================================================
class PersonAvatar extends StatelessWidget {
  final Look look;
  final String role;
  final String? name;
  final double height;
  const PersonAvatar({super.key, required this.look, required this.role, this.name, this.height = 150});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: height * 0.8,
        height: height,
        child: CustomPaint(painter: _AvatarPainter(look, role, name)),
      );
}

class _AvatarPainter extends CustomPainter {
  final Look look;
  final String role;
  final String? name;
  _AvatarPainter(this.look, this.role, this.name);
  @override
  void paint(Canvas c, Size sz) => drawPerson(c, Offset(sz.width / 2, sz.height * 0.97), sz.height * 0.74, look, role: role, name: name);
  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) => oldDelegate.look != look || oldDelegate.name != name;
}

// =====================================================================
//  BỐ TRÍ QUÁN: kéo thả bàn ghế và đồ trang trí tự do
// =====================================================================
class LayoutEditor extends StatefulWidget {
  final int tableCount;
  final List<Offset?> tablePos;
  final List<Deco> decos;
  final String venueId, style, light;
  final void Function(List<Offset?> tablePos, List<Deco> decos) onChanged;
  final void Function(int decoIndex)? onRemoveDeco;
  const LayoutEditor({
    super.key,
    required this.tableCount,
    required this.tablePos,
    required this.decos,
    required this.venueId,
    required this.style,
    required this.light,
    required this.onChanged,
    this.onRemoveDeco,
  });
  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  late List<Offset> _pos;
  int _drag = -1; // >= 0: bàn; <= -2: đồ trang trí số -(_drag + 2)
  Size _size = Size.zero;
  double _r = 24, _wallH = 70, _floorTop = 76;

  @override
  void initState() {
    super.initState();
    _initPos();
    _ticker = createTicker((e) => _clock.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void didUpdateWidget(covariant LayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableCount != widget.tableCount || oldWidget.tablePos != widget.tablePos) _initPos();
  }

  void _initPos() {
    final n = widget.tableCount;
    _pos = [
      for (var i = 0; i < n; i++) (i < widget.tablePos.length ? widget.tablePos[i] : null) ?? defaultTablePos(i, n)
    ];
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  double get _floorH => _size.height - _floorTop;
  Offset _px(Offset rel) => Offset(rel.dx * _size.width, _floorTop + rel.dy * _floorH);
  Offset _decoPx(Deco d) => decoById(d.type).wall ? Offset(d.x * _size.width, _wallH * 0.17) : _px(Offset(d.x, d.y));

  int _hitTest(Offset p) {
    for (var k = widget.decos.length - 1; k >= 0; k--) {
      final d = widget.decos[k];
      final dt = decoById(d.type);
      final ctr = dt.wall ? _decoPx(d) : _decoPx(d) - Offset(0, _r * dt.size * 0.55);
      final rad = dt.wall ? _wallH * 0.3 : _r * max(0.9, dt.size * 0.95);
      if ((p - ctr).distance < rad) return -(k + 2);
    }
    for (var i = _pos.length - 1; i >= 0; i--) {
      if ((p - (_px(_pos[i]) - Offset(0, _r * 0.4))).distance < _r * 1.4) return i;
    }
    return -1;
  }

  void _emit() {
    final out = List<Offset?>.filled(12, null);
    for (var i = 0; i < _pos.length && i < 12; i++) {
      out[i] = _pos[i];
    }
    widget.onChanged(out, widget.decos);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _drag = _hitTest(d.localPosition),
        onPanUpdate: (d) {
          if (_drag == -1 || _size == Size.zero) return;
          final dx = d.delta.dx / _size.width, dy = d.delta.dy / max(1.0, _floorH);
          if (_drag >= 0) {
            final o = _pos[_drag];
            _pos[_drag] = Offset((o.dx + dx).clamp(0.06, 0.94).toDouble(), (o.dy + dy).clamp(0.08, 0.95).toDouble());
          } else {
            final dd = widget.decos[-(_drag + 2)];
            dd.x = (dd.x + dx).clamp(0.04, 0.96).toDouble();
            if (!decoById(dd.type).wall) dd.y = (dd.y + dy).clamp(0.04, 0.97).toDouble();
          }
        },
        onPanEnd: (_) {
          if (_drag != -1) _emit();
          _drag = -1;
        },
        onLongPressStart: (d) {
          final k = _hitTest(d.localPosition);
          if (k <= -2) widget.onRemoveDeco?.call(-(k + 2));
        },
        child: SizedBox.expand(child: CustomPaint(painter: _EditorPainter(this))),
      );

  void _paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    if (w < 40 || h < 40) return;
    _size = sz;
    final t = _clock.value;
    final th = themeFor(widget.venueId, widget.style);
    _wallH = max(70.0, h * 0.2);
    _floorTop = _wallH + 6;
    final n = max(1, _pos.length);
    _r = tableRadius(w, _floorH, n);
    final r = _r;

    // sàn + tường
    final tile = max(24.0, w / 9);
    c.drawRect(Rect.fromLTWH(0, _wallH, w, h - _wallH), Paint()..color = th.floorA);
    final pb = Paint()..color = th.floorB;
    for (var y = 0; _wallH + y * tile < h; y++) {
      for (var x = 0; x * tile < w; x++) {
        if ((x + y).isOdd) c.drawRect(Rect.fromLTWH(x * tile, _wallH + y * tile, tile, tile), pb);
      }
    }
    c.drawRect(Rect.fromLTWH(0, 0, w, _wallH), Paint()..color = th.wall);
    _ambientBack(c, w, _wallH * 0.22, widget.style, t, th);
    c.drawRect(Rect.fromLTWH(0, _wallH - 4, w, 5), Paint()..color = th.trim);
    final hint = _text('Kéo để di chuyển • nhấn giữ đồ trang trí để cất đi', 11, color: _a(Colors.white, 0.9), bold: true);
    hint.paint(c, Offset(w / 2 - hint.width / 2, _wallH * 0.55));

    // vẽ theo chiều sâu
    final items = <_Item>[];
    for (var i = 0; i < _pos.length; i++) {
      final ct = _px(_pos[i]);
      items.add(_Item(ct.dy, () {
        final sel = _drag == i;
        final chair = RRect.fromRectAndRadius(Rect.fromCenter(center: ct + Offset(0, -r * 0.95), width: r * 1.3, height: r * 1.3), Radius.circular(r * 0.25));
        c.drawRRect(chair, Paint()..color = _dk(th.wood, 0.15));
        c.drawRRect(chair.deflate(r * 0.12), Paint()..color = _lt(th.accent, 0.15));
        final top = Rect.fromCenter(center: ct, width: r * 2.3, height: r * 1.15);
        c.drawOval(top.shift(Offset(0, r * 0.14)), Paint()..color = _dk(th.wood, 0.2));
        c.drawOval(top, Paint()..color = th.cloth);
        if (sel) {
          c.drawOval(top.inflate(4), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF42A5F5));
        }
        final lab = _text('${i + 1}', r * 0.45, color: _dk(th.wood, 0.4), bold: true);
        lab.paint(c, ct - Offset(lab.width / 2, lab.height / 2));
      }));
    }
    for (var k = 0; k < widget.decos.length; k++) {
      final d = widget.decos[k];
      final dt = decoById(d.type);
      final p = _decoPx(d);
      final sel = _drag == -(k + 2);
      if (dt.wall) {
        drawWallDeco(c, dt.id, p, _wallH * 0.36, t);
        if (sel) c.drawCircle(p, _wallH * 0.26, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF42A5F5));
        continue;
      }
      items.add(_Item(p.dy, () {
        final sz2 = r * dt.size;
        drawFloorDeco(c, dt.id, p + Offset(0, r * 0.35), r * dt.size * 1.6, t, wood: th.wood);
        if (sel) c.drawCircle(p - Offset(0, sz2 * 0.4), sz2 * 0.9, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF42A5F5));
      }));
    }
    items.sort((a, b) => a.y.compareTo(b.y));
    for (final it in items) {
      it.draw();
    }

    // xem trước ánh sáng
    switch (widget.light) {
      case 'warm':
        c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x22FFA726));
        break;
      case 'romantic':
        c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0x3A2A0A3A));
        break;
      case 'disco':
        const cols2 = [Color(0xFFFF4081), Color(0xFF40C4FF), Color(0xFFFFEB3B), Color(0xFF69F0AE)];
        for (var k = 0; k < 4; k++) {
          final cp = Offset(w * (0.5 + 0.4 * sin(t * 0.9 + k * 1.7)), _floorTop + _floorH * (0.5 + 0.4 * cos(t * 0.7 + k * 2.3)));
          c.drawCircle(cp, r * 2.2, Paint()..color = _a(cols2[k], 0.16));
        }
        break;
    }
  }
}

class _EditorPainter extends CustomPainter {
  final _LayoutEditorState st;
  _EditorPainter(this.st) : super(repaint: st._clock);
  @override
  void paint(Canvas canvas, Size size) => st._paint(canvas, size);
  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) => true;
}

// =====================================================================
//  ĐỒ TRANG TRÍ VẼ TAY: to, có hào quang và lấp lánh
// =====================================================================
void _sparkle(Canvas c, Offset p, double size, double alpha, [Color col = Colors.white]) {
  if (alpha <= 0.02) return;
  final path = Path()
    ..moveTo(p.dx, p.dy - size)
    ..quadraticBezierTo(p.dx, p.dy, p.dx + size, p.dy)
    ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + size)
    ..quadraticBezierTo(p.dx, p.dy, p.dx - size, p.dy)
    ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - size)
    ..close();
  c.drawCircle(p, size * 0.9, Paint()..color = _a(col, alpha * 0.25));
  c.drawPath(path, Paint()..color = _a(col, alpha));
}

void _glow(Canvas c, Offset center, double radius, Color col, double strength) {
  final rect = Rect.fromCircle(center: center, radius: radius);
  c.drawCircle(
    center,
    radius,
    Paint()..shader = RadialGradient(colors: [_a(col, strength), _a(col, 0)]).createShader(rect),
  );
}

/// Lấp lánh quanh đồ vật (3 ngôi sao nhấp nháy lệch pha)
void _twinkles(Canvas c, Rect box, double t, double seed, [Color col = Colors.white]) {
  for (var k = 0; k < 3; k++) {
    final ph = (t * 0.8 + k / 3 + seed) % 1.0;
    final a = sin(ph * pi);
    final px = box.left + box.width * _fr(seed * 3.7 + k * 0.41);
    final py = box.top + box.height * _fr(seed * 5.3 + k * 0.29 + (t * 0.8 + k / 3 + seed).floor() * 0.37);
    _sparkle(c, Offset(px, py), box.width * 0.07 * (0.6 + 0.4 * a), a * 0.95, col);
  }
}

LinearGradient _vg(Color a, Color b) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a, b]);

/// Đồ đặt trên sàn. [p] là điểm chạm sàn (giữa đáy), [s] là chiều cao đồ vật.
void drawFloorDeco(Canvas c, String id, Offset p, double s, double t, {Color wood = const Color(0xFF8D5B3C)}) {
  final seed = (p.dx * 0.013 + p.dy * 0.007) % 1.0;
  c.drawOval(Rect.fromCenter(center: p, width: s * 0.95, height: s * 0.2), Paint()..color = const Color(0x30000000));
  final box = Rect.fromLTRB(p.dx - s * 0.5, p.dy - s, p.dx + s * 0.5, p.dy);
  switch (id) {
    case 'plant':
      {
        _glow(c, p - Offset(0, s * 0.6), s * 0.6, const Color(0xFF8BC34A), 0.25);
        // lá: nhiều phiến hình giọt toả ra, đung đưa
        for (var k = 0; k < 7; k++) {
          final ang = -pi / 2 + (k - 3) * 0.38 + sin(t * 1.6 + k) * 0.05;
          final len = s * (0.55 + 0.12 * ((k * 37) % 3));
          c.save();
          c.translate(p.dx, p.dy - s * 0.38);
          c.rotate(ang + pi / 2);
          final leaf = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(s * 0.14, -len * 0.5, 0, -len)
            ..quadraticBezierTo(-s * 0.14, -len * 0.5, 0, 0)
            ..close();
          final rect = Rect.fromLTWH(-s * 0.14, -len, s * 0.28, len);
          c.drawPath(leaf, Paint()..shader = _vg(k.isEven ? const Color(0xFF9CCC65) : const Color(0xFF66BB6A), const Color(0xFF2E7D32)).createShader(rect));
          c.drawLine(Offset.zero, Offset(0, -len * 0.9), Paint()
            ..color = const Color(0x553E7D32)
            ..strokeWidth = 1);
          c.restore();
        }
        // chậu đất nung
        final pot = Path()
          ..moveTo(p.dx - s * 0.26, p.dy - s * 0.38)
          ..lineTo(p.dx + s * 0.26, p.dy - s * 0.38)
          ..lineTo(p.dx + s * 0.19, p.dy)
          ..lineTo(p.dx - s * 0.19, p.dy)
          ..close();
        c.drawPath(pot, Paint()..shader = _vg(const Color(0xFFE07A4F), const Color(0xFFA9462B)).createShader(box));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - s * 0.3, p.dy - s * 0.44, p.dx + s * 0.3, p.dy - s * 0.34), Radius.circular(s * 0.03)), Paint()..color = const Color(0xFFF08A5D));
        _twinkles(c, box, t, seed);
      }
      break;
    case 'flower':
      {
        _glow(c, p - Offset(0, s * 0.65), s * 0.55, const Color(0xFFFF80AB), 0.3);
        final heads = [Offset(-0.18, -0.78), Offset(0.02, -0.92), Offset(0.2, -0.76), Offset(-0.05, -0.66), Offset(0.13, -0.6)];
        const cols = [Color(0xFFFF5C8A), Color(0xFFFFD54F), Color(0xFFBA68C8), Color(0xFFFF8A65), Color(0xFFFFFFFF)];
        for (var k = 0; k < heads.length; k++) {
          final hp = p + Offset(heads[k].dx * s + sin(t * 1.5 + k) * s * 0.01, heads[k].dy * s);
          c.drawLine(p - Offset(0, s * 0.4), hp, Paint()
            ..color = const Color(0xFF558B2F)
            ..strokeWidth = max(1.5, s * 0.02));
          for (var j = 0; j < 5; j++) {
            final a = j * 2 * pi / 5 + t * 0.3;
            c.drawCircle(hp + Offset(cos(a), sin(a)) * s * 0.055, s * 0.05, Paint()..color = cols[k]);
          }
          c.drawCircle(hp, s * 0.035, Paint()..color = const Color(0xFFFFB300));
        }
        // bình thuỷ tinh
        final vase = RRect.fromRectAndCorners(Rect.fromLTRB(p.dx - s * 0.17, p.dy - s * 0.45, p.dx + s * 0.17, p.dy),
            topLeft: Radius.circular(s * 0.05), topRight: Radius.circular(s * 0.05), bottomLeft: Radius.circular(s * 0.14), bottomRight: Radius.circular(s * 0.14));
        c.drawRRect(vase, Paint()..color = const Color(0x8890CAF9));
        c.drawRRect(vase, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xCCFFFFFF));
        c.drawRect(Rect.fromLTWH(p.dx - s * 0.11, p.dy - s * 0.38, s * 0.04, s * 0.28), Paint()..color = const Color(0x99FFFFFF));
        _twinkles(c, box, t, seed, const Color(0xFFFFF59D));
      }
      break;
    case 'tree':
      {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - s * 0.06, p.dy - s * 0.5, p.dx + s * 0.06, p.dy - s * 0.12), Radius.circular(s * 0.03)), Paint()..color = const Color(0xFF795548));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - s * 0.2, p.dy - s * 0.16, p.dx + s * 0.2, p.dy), Radius.circular(s * 0.04)), Paint()..shader = _vg(const Color(0xFFECEFF1), const Color(0xFFB0BEC5)).createShader(box));
        final sway = sin(t * 1.1) * s * 0.012;
        const blobs = [Offset(0, -0.72), Offset(-0.22, -0.6), Offset(0.22, -0.6), Offset(-0.12, -0.85), Offset(0.14, -0.86), Offset(0, -0.55)];
        for (var k = 0; k < blobs.length; k++) {
          final bc = p + Offset(blobs[k].dx * s + sway, blobs[k].dy * s);
          final rr = s * (k == 0 ? 0.26 : 0.19);
          c.drawCircle(bc, rr, Paint()..shader = RadialGradient(center: const Alignment(-0.4, -0.5), colors: const [Color(0xFF81C784), Color(0xFF2E7D32)]).createShader(Rect.fromCircle(center: bc, radius: rr)));
        }
        // dây đèn tiên lấp lánh trên tán cây
        const fairy = [Color(0xFFFFF59D), Color(0xFFFFCC80), Color(0xFFFF8A80), Color(0xFFB9F6CA)];
        for (var k = 0; k < 9; k++) {
          final a = k * 0.7 + 0.3;
          final lp = p + Offset(sin(a * 2.3) * s * 0.3 + sway, -s * (0.55 + 0.32 * _fr(k * 0.37)));
          final al = 0.4 + 0.6 * sin(t * 3 + k * 1.3).abs();
          c.drawCircle(lp, s * 0.05, Paint()..color = _a(fairy[k % 4], al * 0.35));
          c.drawCircle(lp, s * 0.018, Paint()..color = _a(fairy[k % 4], al));
        }
      }
      break;
    case 'bar':
      {
        final w = s * 1.9;
        // kệ chai phía sau
        final shelf = Rect.fromLTRB(p.dx - w * 0.42, p.dy - s * 1.05, p.dx + w * 0.42, p.dy - s * 0.55);
        c.drawRRect(RRect.fromRectAndRadius(shelf, Radius.circular(s * 0.05)), Paint()..color = _dk(wood, 0.35));
        const bottles = [Color(0xFF66BB6A), Color(0xFFFFB74D), Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFFBA68C8), Color(0xFFFFF176)];
        for (var k = 0; k < 6; k++) {
          final bx = shelf.left + shelf.width * (0.1 + 0.16 * k);
          final bh = s * (0.28 + 0.06 * (k % 3));
          final br = Rect.fromLTWH(bx - s * 0.04, shelf.bottom - bh - s * 0.03, s * 0.08, bh);
          c.drawRRect(RRect.fromRectAndRadius(br, Radius.circular(s * 0.03)), Paint()..color = _a(bottles[k], 0.9));
          c.drawRect(Rect.fromLTWH(bx - s * 0.015, br.top - s * 0.06, s * 0.03, s * 0.07), Paint()..color = _a(bottles[k], 0.9));
          c.drawRect(Rect.fromLTWH(bx - s * 0.03, br.top + bh * 0.2, s * 0.015, bh * 0.5), Paint()..color = const Color(0x88FFFFFF));
        }
        // biển neon
        final neon = 0.6 + 0.4 * sin(t * 4).abs();
        _glow(c, Offset(p.dx, shelf.top - s * 0.08), s * 0.35, const Color(0xFFFF4081), 0.4 * neon);
        final tp = _text('BAR', s * 0.16, color: _a(const Color(0xFFFF80AB), 0.6 + 0.4 * neon), bold: true);
        tp.paint(c, Offset(p.dx - tp.width / 2, shelf.top - s * 0.08 - tp.height / 2));
        // quầy
        final body = RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - w / 2, p.dy - s * 0.48, p.dx + w / 2, p.dy), Radius.circular(s * 0.06));
        c.drawRRect(body, Paint()..shader = _vg(_lt(wood, 0.1), _dk(wood, 0.35)).createShader(body.outerRect));
        for (var k = 1; k < 5; k++) {
          c.drawLine(Offset(body.left + w * k / 5, body.top + s * 0.08), Offset(body.left + w * k / 5, body.bottom - s * 0.04), Paint()
            ..color = _a(Colors.black, 0.15)
            ..strokeWidth = 1.5);
        }
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(body.left - s * 0.05, body.top - s * 0.06, body.right + s * 0.05, body.top + s * 0.05), Radius.circular(s * 0.04)), Paint()..shader = _vg(const Color(0xFFFFE0B2), const Color(0xFFBCAAA4)).createShader(body.outerRect));
        // ly cocktail trên quầy
        for (var k = 0; k < 2; k++) {
          final gx = p.dx + (k == 0 ? -w * 0.25 : w * 0.28);
          final gy = body.top - s * 0.06;
          c.drawPath(Path()
            ..moveTo(gx - s * 0.08, gy - s * 0.16)
            ..lineTo(gx + s * 0.08, gy - s * 0.16)
            ..lineTo(gx, gy - s * 0.06)
            ..close(), Paint()..color = k == 0 ? const Color(0xCCFF8A65) : const Color(0xCC4FC3F7));
          c.drawLine(Offset(gx, gy - s * 0.06), Offset(gx, gy), Paint()
            ..color = const Color(0xCCFFFFFF)
            ..strokeWidth = 1.5);
        }
        _twinkles(c, Rect.fromLTRB(p.dx - w / 2, p.dy - s * 1.1, p.dx + w / 2, p.dy - s * 0.4), t, seed, const Color(0xFFFFE082));
      }
      break;
    case 'piano':
      {
        final w = s * 1.2;
        final body = Path()
          ..moveTo(p.dx - w * 0.5, p.dy - s * 0.25)
          ..lineTo(p.dx - w * 0.5, p.dy - s * 0.55)
          ..quadraticBezierTo(p.dx - w * 0.5, p.dy - s * 0.95, p.dx, p.dy - s * 0.92)
          ..quadraticBezierTo(p.dx + w * 0.55, p.dy - s * 0.9, p.dx + w * 0.5, p.dy - s * 0.4)
          ..lineTo(p.dx + w * 0.5, p.dy - s * 0.25)
          ..close();
        c.drawPath(body, Paint()..shader = _vg(const Color(0xFF424242), const Color(0xFF0D0D0D)).createShader(box.inflate(s * 0.3)));
        // nắp mở
        c.drawLine(Offset(p.dx - w * 0.3, p.dy - s * 0.85), Offset(p.dx + w * 0.1, p.dy - s * 1.2), Paint()
          ..color = const Color(0xFF212121)
          ..strokeWidth = s * 0.06
          ..strokeCap = StrokeCap.round);
        c.drawPath(body, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x66FFFFFF));
        // phím đàn
        final keys = Rect.fromLTRB(p.dx - w * 0.5, p.dy - s * 0.3, p.dx + w * 0.5, p.dy - s * 0.18);
        c.drawRect(keys, Paint()..color = Colors.white);
        for (var k = 0; k < 10; k++) {
          final kx = keys.left + keys.width * (k + 0.7) / 10.5;
          if (k % 7 == 2 || k % 7 == 6) continue;
          c.drawRect(Rect.fromLTWH(kx, keys.top, keys.width / 22, keys.height * 0.6), Paint()..color = Colors.black);
        }
        // chân đàn
        for (final x in [-0.42, 0.42]) {
          c.drawRect(Rect.fromLTWH(p.dx + x * w - s * 0.025, p.dy - s * 0.18, s * 0.05, s * 0.18), Paint()..color = const Color(0xFF1A1A1A));
        }
        // nốt nhạc bay
        for (var k = 0; k < 3; k++) {
          final ph = (t * 0.45 + k / 3 + seed) % 1.0;
          final np = p + Offset(w * 0.3 + sin(ph * 6 + k) * s * 0.15, -s * (0.9 + ph * 0.8));
          final tp = _text(k.isEven ? '♪' : '♫', s * 0.22, color: _a(const Color(0xFFFFD54F), 1 - ph), bold: true);
          tp.paint(c, np - Offset(tp.width / 2, tp.height / 2));
        }
        _sparkle(c, p + Offset(-w * 0.2, -s * 0.8), s * 0.06, 0.5 + 0.5 * sin(t * 3).abs());
      }
      break;
    case 'fish':
      {
        final tank = Rect.fromLTRB(p.dx - s * 0.65, p.dy - s * 0.95, p.dx + s * 0.65, p.dy - s * 0.15);
        _glow(c, tank.center, s * 0.9, const Color(0xFF4FC3F7), 0.25);
        c.drawRect(Rect.fromLTRB(tank.left + s * 0.05, tank.bottom, tank.right - s * 0.05, p.dy), Paint()..color = _dk(wood, 0.2));
        final rr = RRect.fromRectAndRadius(tank, Radius.circular(s * 0.06));
        c.save();
        c.clipRRect(rr);
        c.drawRect(tank, Paint()..shader = _vg(const Color(0xFF81D4FA), const Color(0xFF0277BD)).createShader(tank));
        // cát + rong
        c.drawRect(Rect.fromLTRB(tank.left, tank.bottom - s * 0.1, tank.right, tank.bottom), Paint()..color = const Color(0xFFFFE0B2));
        for (var k = 0; k < 4; k++) {
          final sx = tank.left + tank.width * (0.12 + 0.25 * k);
          final weed = Path()..moveTo(sx, tank.bottom - s * 0.08);
          for (var j = 1; j <= 6; j++) {
            weed.lineTo(sx + sin(t * 2 + j + k) * s * 0.04, tank.bottom - s * 0.08 - j * s * 0.06);
          }
          c.drawPath(weed, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.035
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF43A047));
        }
        // cá bơi
        const fc = [Color(0xFFFF7043), Color(0xFFFFEB3B), Color(0xFFF06292)];
        for (var k = 0; k < 3; k++) {
          final ph = (t * (0.12 + 0.04 * k) + k * 0.33) % 1.0;
          final dir = ph < 0.5 ? 1.0 : -1.0;
          final fx = tank.left + tank.width * (ph < 0.5 ? ph * 2 : 2 - ph * 2);
          final fy = tank.top + tank.height * (0.3 + 0.18 * k) + sin(t * 2 + k) * s * 0.03;
          c.save();
          c.translate(fx, fy);
          c.scale(dir, 1);
          c.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 0.2, height: s * 0.11), Paint()..color = fc[k]);
          c.drawPath(Path()
            ..moveTo(-s * 0.08, 0)
            ..lineTo(-s * 0.16, -s * 0.06)
            ..lineTo(-s * 0.16, s * 0.06)
            ..close(), Paint()..color = fc[k]);
          c.drawCircle(Offset(s * 0.05, -s * 0.01), s * 0.015, Paint()..color = Colors.black);
          c.restore();
        }
        for (var k = 0; k < 4; k++) {
          final ph = (t * 0.6 + k / 4) % 1.0;
          c.drawCircle(Offset(tank.left + tank.width * (0.2 + 0.2 * k) + sin(ph * 8) * 3, tank.bottom - ph * tank.height), s * 0.02 + ph * s * 0.015, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = _a(Colors.white, 1 - ph));
        }
        c.drawRect(Rect.fromLTWH(tank.left + s * 0.08, tank.top, s * 0.06, tank.height), Paint()..color = const Color(0x44FFFFFF));
        c.restore();
        c.drawRRect(rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFF455A64));
      }
      break;
    case 'books':
      {
        final sh = Rect.fromLTRB(p.dx - s * 0.5, p.dy - s * 1.1, p.dx + s * 0.5, p.dy);
        c.drawRRect(RRect.fromRectAndRadius(sh, Radius.circular(s * 0.04)), Paint()..shader = _vg(_lt(wood, 0.05), _dk(wood, 0.3)).createShader(sh));
        const spines = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFDD835), Color(0xFF43A047), Color(0xFF8E24AA), Color(0xFFFF7043), Color(0xFF00897B)];
        for (var row = 0; row < 3; row++) {
          final top = sh.top + s * 0.06 + row * s * 0.34;
          c.drawRect(Rect.fromLTRB(sh.left + s * 0.05, top, sh.right - s * 0.05, top + s * 0.3), Paint()..color = _dk(wood, 0.55));
          var x = sh.left + s * 0.07;
          var k = row * 3;
          while (x < sh.right - s * 0.12) {
            final bw = s * (0.07 + 0.03 * (k % 3));
            final bh = s * (0.2 + 0.05 * ((k * 7) % 3));
            c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, top + s * 0.29 - bh, bw, bh), Radius.circular(s * 0.01)), Paint()..color = spines[k % spines.length]);
            c.drawRect(Rect.fromLTWH(x, top + s * 0.29 - bh * 0.7, bw, s * 0.015), Paint()..color = const Color(0x66FFFFFF));
            x += bw + s * 0.015;
            k++;
          }
        }
        _sparkle(c, Offset(sh.right - s * 0.1, sh.top + s * 0.08), s * 0.06, 0.4 + 0.6 * sin(t * 2.5 + seed * 9).abs(), const Color(0xFFFFF59D));
      }
      break;
    case 'sofa':
      {
        final w = s * 1.5;
        const velvet = Color(0xFF7E57C2);
        final back = RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - w * 0.46, p.dy - s * 0.75, p.dx + w * 0.46, p.dy - s * 0.3), Radius.circular(s * 0.14));
        c.drawRRect(back, Paint()..shader = _vg(_lt(velvet, 0.15), _dk(velvet, 0.2)).createShader(back.outerRect));
        for (final x in [-0.17, 0.17]) {
          c.drawCircle(Offset(p.dx + x * w, p.dy - s * 0.55), s * 0.025, Paint()..color = _dk(velvet, 0.4));
        }
        final seat = RRect.fromRectAndRadius(Rect.fromLTRB(p.dx - w * 0.45, p.dy - s * 0.36, p.dx + w * 0.45, p.dy - s * 0.08), Radius.circular(s * 0.1));
        c.drawRRect(seat, Paint()..shader = _vg(_lt(velvet, 0.3), velvet).createShader(seat.outerRect));
        for (final side in [-1.0, 1.0]) {
          final arm = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx + side * w * 0.47, p.dy - s * 0.3), width: s * 0.22, height: s * 0.48), Radius.circular(s * 0.1));
          c.drawRRect(arm, Paint()..shader = _vg(_lt(velvet, 0.2), _dk(velvet, 0.25)).createShader(arm.outerRect));
        }
        // gối
        final pil = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx - w * 0.22, p.dy - s * 0.42), width: s * 0.28, height: s * 0.24), Radius.circular(s * 0.08));
        c.drawRRect(pil, Paint()..color = const Color(0xFFFFD54F));
        final pil2 = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(p.dx + w * 0.22, p.dy - s * 0.42), width: s * 0.28, height: s * 0.24), Radius.circular(s * 0.08));
        c.drawRRect(pil2, Paint()..color = const Color(0xFFFF8A80));
        for (final x in [-0.38, 0.38]) {
          c.drawRect(Rect.fromLTWH(p.dx + x * w - s * 0.03, p.dy - s * 0.09, s * 0.06, s * 0.09), Paint()..color = const Color(0xFF4E342E));
        }
        _twinkles(c, Rect.fromLTRB(p.dx - w / 2, p.dy - s * 0.8, p.dx + w / 2, p.dy - s * 0.2), t, seed);
      }
      break;
    case 'statue':
      {
        _glow(c, p - Offset(0, s * 0.7), s * 0.55, const Color(0xFFFFD54F), 0.3 + 0.1 * sin(t * 2));
        final ped = Rect.fromLTRB(p.dx - s * 0.24, p.dy - s * 0.35, p.dx + s * 0.24, p.dy);
        c.drawRect(ped, Paint()..shader = _vg(const Color(0xFFF5F5F5), const Color(0xFFBDBDBD)).createShader(ped));
        c.drawRect(Rect.fromLTRB(ped.left - s * 0.04, ped.top - s * 0.05, ped.right + s * 0.04, ped.top), Paint()..color = const Color(0xFFE0E0E0));
        c.drawRect(Rect.fromLTRB(ped.left - s * 0.04, ped.bottom - s * 0.05, ped.right + s * 0.04, ped.bottom), Paint()..color = const Color(0xFFE0E0E0));
        // tượng bán thân bằng đá + vòng nguyệt quế vàng
        const stone = [Color(0xFFECEFF1), Color(0xFF90A4AE)];
        final bust = Path()
          ..moveTo(p.dx - s * 0.2, p.dy - s * 0.4)
          ..quadraticBezierTo(p.dx - s * 0.2, p.dy - s * 0.62, p.dx, p.dy - s * 0.62)
          ..quadraticBezierTo(p.dx + s * 0.2, p.dy - s * 0.62, p.dx + s * 0.2, p.dy - s * 0.4)
          ..close();
        c.drawPath(bust, Paint()..shader = _vg(stone[0], stone[1]).createShader(box));
        c.drawRect(Rect.fromLTWH(p.dx - s * 0.05, p.dy - s * 0.72, s * 0.1, s * 0.12), Paint()..color = stone[1]);
        final head = Offset(p.dx, p.dy - s * 0.82);
        c.drawCircle(head, s * 0.14, Paint()..shader = RadialGradient(center: const Alignment(-0.4, -0.4), colors: stone).createShader(Rect.fromCircle(center: head, radius: s * 0.14)));
        for (var k = 0; k < 7; k++) {
          final a = pi + 0.2 + k * 0.45;
          c.drawOval(Rect.fromCenter(center: head + Offset(cos(a), sin(a)) * s * 0.14, width: s * 0.07, height: s * 0.04), Paint()..color = const Color(0xFFFFC107));
        }
        _twinkles(c, Rect.fromLTRB(p.dx - s * 0.4, p.dy - s * 1.05, p.dx + s * 0.4, p.dy - s * 0.4), t, seed, const Color(0xFFFFF59D));
      }
      break;
    default:
      _emoji(c, decoById(id).emoji, p - Offset(0, s * 0.5), s);
  }
}

/// Đồ treo tường, [p] là tâm đồ vật, [s] là kích thước
void drawWallDeco(Canvas c, String id, Offset p, double s, double t) {
  final seed = (p.dx * 0.017) % 1.0;
  switch (id) {
    case 'frame':
      {
        final outer = Rect.fromCenter(center: p, width: s * 1.25, height: s * 0.95);
        c.drawRect(outer.shift(const Offset(2, 3)), Paint()..color = const Color(0x40000000));
        c.drawRect(outer, Paint()..shader = LinearGradient(colors: const [Color(0xFFFFE082), Color(0xFFC8962B), Color(0xFFFFE082)]).createShader(outer));
        final inner = outer.deflate(s * 0.1);
        c.save();
        c.clipRect(inner);
        c.drawRect(inner, Paint()..shader = _vg(const Color(0xFFFFCC80), const Color(0xFF81D4FA)).createShader(inner));
        c.drawCircle(Offset(inner.left + inner.width * 0.7, inner.top + inner.height * 0.35), s * 0.1, Paint()..color = const Color(0xFFFFF176));
        c.drawPath(
          Path()
            ..moveTo(inner.left, inner.bottom)
            ..quadraticBezierTo(inner.left + inner.width * 0.3, inner.top + inner.height * 0.45, inner.left + inner.width * 0.6, inner.bottom)
            ..close(),
          Paint()..color = const Color(0xFF66BB6A),
        );
        c.drawPath(
          Path()
            ..moveTo(inner.left + inner.width * 0.35, inner.bottom)
            ..quadraticBezierTo(inner.left + inner.width * 0.7, inner.top + inner.height * 0.55, inner.right, inner.bottom)
            ..close(),
          Paint()..color = const Color(0xFF388E3C),
        );
        // vệt sáng lướt qua mặt kính
        final ph = (t * 0.25 + seed) % 1.0;
        final gx = inner.left - inner.width * 0.3 + ph * inner.width * 1.6;
        c.drawPath(
          Path()
            ..moveTo(gx, inner.top)
            ..lineTo(gx + s * 0.12, inner.top)
            ..lineTo(gx - s * 0.08, inner.bottom)
            ..lineTo(gx - s * 0.2, inner.bottom)
            ..close(),
          Paint()..color = const Color(0x55FFFFFF),
        );
        c.restore();
      }
      break;
    case 'clock':
      {
        // quả lắc
        final sw = sin(t * 3) * 0.35;
        c.save();
        c.translate(p.dx, p.dy + s * 0.25);
        c.rotate(sw);
        c.drawLine(Offset.zero, Offset(0, s * 0.45), Paint()
          ..color = const Color(0xFFC8962B)
          ..strokeWidth = 2);
        c.drawCircle(Offset(0, s * 0.45), s * 0.08, Paint()..color = const Color(0xFFFFC107));
        c.restore();
        c.drawCircle(p + const Offset(1.5, 2.5), s * 0.42, Paint()..color = const Color(0x40000000));
        c.drawCircle(p, s * 0.42, Paint()..shader = _vg(const Color(0xFF8D6E63), const Color(0xFF4E342E)).createShader(Rect.fromCircle(center: p, radius: s * 0.42)));
        c.drawCircle(p, s * 0.34, Paint()..color = const Color(0xFFFFF8E1));
        for (var k = 0; k < 12; k++) {
          final a = k * pi / 6;
          c.drawLine(p + Offset(cos(a), sin(a)) * s * 0.28, p + Offset(cos(a), sin(a)) * s * 0.32, Paint()
            ..color = const Color(0xFF5D4037)
            ..strokeWidth = k % 3 == 0 ? 2.5 : 1.2);
        }
        final hand = Paint()
          ..color = const Color(0xFF3E2723)
          ..strokeCap = StrokeCap.round;
        final mA = t * 0.6 - pi / 2, hA = t * 0.05 - pi / 2;
        c.drawLine(p, p + Offset(cos(hA), sin(hA)) * s * 0.17, hand..strokeWidth = 3);
        c.drawLine(p, p + Offset(cos(mA), sin(mA)) * s * 0.26, hand..strokeWidth = 2);
        c.drawCircle(p, s * 0.035, Paint()..color = const Color(0xFFC62828));
      }
      break;
    case 'lantern':
      {
        final sw = sin(t * 1.8 + seed * 6) * 0.12;
        c.drawLine(Offset(p.dx, p.dy - s * 0.7), Offset(p.dx, p.dy - s * 0.42), Paint()
          ..color = const Color(0xFF5D4037)
          ..strokeWidth = 1.5);
        c.save();
        c.translate(p.dx, p.dy - s * 0.42);
        c.rotate(sw);
        final pulse = 0.75 + 0.25 * sin(t * 2.5 + seed * 5);
        _glow(c, Offset(0, s * 0.4), s * 0.75, const Color(0xFFFF5252), 0.35 * pulse);
        final body = Rect.fromCenter(center: Offset(0, s * 0.4), width: s * 0.7, height: s * 0.55);
        c.drawOval(body, Paint()..shader = RadialGradient(colors: [Color.lerp(const Color(0xFFFF8A65), const Color(0xFFFFE082), pulse * 0.5)!, const Color(0xFFC62828)]).createShader(body));
        for (var k = 1; k < 4; k++) {
          final x = body.left + body.width * k / 4;
          c.drawLine(Offset(x, body.top + s * 0.04), Offset(x, body.bottom - s * 0.04), Paint()
            ..color = const Color(0x55B71C1C)
            ..strokeWidth = 1.2);
        }
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, body.top), width: s * 0.36, height: s * 0.08), Radius.circular(s * 0.02)), Paint()..color = const Color(0xFFFFC107));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, body.bottom), width: s * 0.36, height: s * 0.08), Radius.circular(s * 0.02)), Paint()..color = const Color(0xFFFFC107));
        // tua rua
        for (var k = -1; k <= 1; k++) {
          c.drawLine(Offset(k * s * 0.04, body.bottom + s * 0.04), Offset(k * s * 0.05 + sw * s * 0.1, body.bottom + s * 0.28), Paint()
            ..color = const Color(0xFFFFB300)
            ..strokeWidth = 1.5);
        }
        c.restore();
      }
      break;
    case 'light':
      {
        c.drawLine(Offset(p.dx, p.dy - s * 0.7), Offset(p.dx, p.dy - s * 0.2), Paint()
          ..color = const Color(0xFF37474F)
          ..strokeWidth = 1.5);
        final pulse = 0.85 + 0.15 * sin(t * 2 + seed * 7);
        // quầng sáng toả xuống
        final cone = Path()
          ..moveTo(p.dx - s * 0.2, p.dy + s * 0.05)
          ..lineTo(p.dx + s * 0.2, p.dy + s * 0.05)
          ..lineTo(p.dx + s * 0.75, p.dy + s * 1.4)
          ..lineTo(p.dx - s * 0.75, p.dy + s * 1.4)
          ..close();
        c.drawPath(cone, Paint()..shader = _vg(_a(const Color(0xFFFFF59D), 0.35 * pulse), _a(const Color(0xFFFFF59D), 0)).createShader(Rect.fromLTRB(p.dx - s, p.dy, p.dx + s, p.dy + s * 1.4)));
        _glow(c, p + Offset(0, s * 0.08), s * 0.45, const Color(0xFFFFF176), 0.5 * pulse);
        final shade = Path()
          ..moveTo(p.dx - s * 0.12, p.dy - s * 0.22)
          ..lineTo(p.dx + s * 0.12, p.dy - s * 0.22)
          ..lineTo(p.dx + s * 0.32, p.dy + s * 0.06)
          ..lineTo(p.dx - s * 0.32, p.dy + s * 0.06)
          ..close();
        c.drawPath(shade, Paint()..shader = _vg(const Color(0xFF26A69A), const Color(0xFF00695C)).createShader(Rect.fromLTRB(p.dx - s * 0.3, p.dy - s * 0.22, p.dx + s * 0.3, p.dy + s * 0.06)));
        c.drawCircle(p + Offset(0, s * 0.08), s * 0.08, Paint()..color = const Color(0xFFFFFDE7));
      }
      break;
    default:
      _emoji(c, decoById(id).emoji, p, s);
  }
}

/// Đồ trang trí vẽ trong ô nhỏ (dùng ở cửa hàng)
class DecoPreview extends StatefulWidget {
  final String type;
  final double size;
  const DecoPreview({super.key, required this.type, this.size = 64});
  @override
  State<DecoPreview> createState() => _DecoPreviewState();
}

class _DecoPreviewState extends State<DecoPreview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
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

  @override
  Widget build(BuildContext context) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A2F66), Color(0xFF221B3F)]),
          borderRadius: BorderRadius.circular(widget.size * 0.28),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * 0.28),
          child: CustomPaint(painter: _DecoPreviewPainter(widget.type, _clock)),
        ),
      );
}

class _DecoPreviewPainter extends CustomPainter {
  final String type;
  final ValueNotifier<double> clock;
  _DecoPreviewPainter(this.type, this.clock) : super(repaint: clock);
  @override
  void paint(Canvas c, Size sz) {
    final dt = decoById(type);
    final t = clock.value;
    if (dt.wall) {
      final s = sz.height * (type == 'light' ? 0.6 : 0.62);
      drawWallDeco(c, type, Offset(sz.width / 2, sz.height * (type == 'light' || type == 'lantern' ? 0.42 : 0.5)), s, t);
    } else {
      final wide = type == 'bar' || type == 'sofa' || type == 'fish';
      final s = sz.height * (type == 'bar' ? 0.5 : (wide ? 0.62 : 0.78));
      drawFloorDeco(c, type, Offset(sz.width / 2, sz.height * 0.9), s, t);
    }
  }

  @override
  bool shouldRepaint(covariant _DecoPreviewPainter oldDelegate) => true;
}
