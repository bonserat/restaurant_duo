// Cảnh nhà hàng 2D vẽ bằng CustomPainter: nhân vật biết đi, ngồi, gọi món, ăn;
// bếp có lửa, hơi nước, khói. Không cần thêm thư viện hay file ảnh nào.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'models.dart';

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

class Look {
  final Color skin, hair, shirt, pants;
  final int hairStyle; // 0 ngắn, 1 búi, 2 dài
  const Look(this.skin, this.hair, this.shirt, this.pants, this.hairStyle);
  factory Look.seed(int seed) {
    final r = Random(seed);
    return Look(
      _skins[r.nextInt(_skins.length)],
      _hairs[r.nextInt(_hairs.length)],
      _shirts[r.nextInt(_shirts.length)],
      _pants[r.nextInt(_pants.length)],
      r.nextInt(3),
    );
  }
}

const waiterLook = Look(Color(0xFFFFDBB4), Color(0xFF3E2723), Color(0xFF263238), Color(0xFF212121), 0);
const chefLook = Look(Color(0xFFF1C27D), Color(0xFF4E342E), Color(0xFFFFFFFF), Color(0xFF37474F), 0);

/// Vẽ một người kiểu chibi. [p] là điểm chân (hoặc hông nếu [sitting]), [s] ≈ chiều cao.
/// mood: 0 vui, 1 bình thường, 2 tức giận. role: '', 'waiter', 'chef'.
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
}) {
  final u = s / 10;
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
      fill.color = lk.pants;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-0.6 * u, -0.2 * u, 1.2 * u, 3.0 * u), Radius.circular(0.6 * u)), fill);
      fill.color = const Color(0xFF3E2723);
      c.drawOval(Rect.fromLTWH(-0.6 * u, 2.4 * u, 1.7 * u, 0.8 * u), fill);
      c.restore();
    }
  }

  // --- Thân ---
  final top = hip - 3.6 * u;
  final body = RRect.fromLTRBAndCorners(
    -2 * u, top, 2 * u, hip + 0.4 * u,
    topLeft: Radius.circular(1.5 * u),
    topRight: Radius.circular(1.5 * u),
    bottomLeft: Radius.circular(0.6 * u),
    bottomRight: Radius.circular(0.6 * u),
  );
  fill.color = lk.shirt;
  c.drawRRect(body, fill);
  c.drawRRect(body, outline);

  if (role == 'waiter') {
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
    c.translate(side * 1.75 * u, top + 0.9 * u);
    c.rotate(a);
    fill.color = lk.shirt;
    final arm = RRect.fromRectAndRadius(Rect.fromLTWH(-0.55 * u, -0.3 * u, 1.1 * u, 3.0 * u), Radius.circular(0.55 * u));
    c.drawRRect(arm, fill);
    c.drawRRect(arm, outline);
    fill.color = lk.skin;
    c.drawCircle(Offset(0, 2.9 * u), 0.6 * u, fill);
    c.restore();
  }

  // --- Khay món ---
  if (carry != null) {
    final hand = Offset(1.75 * u + 2.83 * u, top + 0.9 * u + 0.63 * u);
    fill.color = const Color(0xFFCFD8DC);
    c.drawOval(Rect.fromCenter(center: hand + Offset(0, -0.4 * u), width: 3.8 * u, height: 0.9 * u), fill);
    c.drawOval(Rect.fromCenter(center: hand + Offset(0, -0.4 * u), width: 3.8 * u, height: 0.9 * u), outline);
    _emoji(c, carry, hand + Offset(0, -1.7 * u), 2.4 * u);
  }

  // --- Đầu ---
  final hy = top - 1.6 * u;
  fill.color = lk.skin;
  c.drawRect(Rect.fromLTWH(-0.5 * u, top - 0.6 * u, u, 0.8 * u), fill);
  if (lk.hairStyle == 2) {
    fill.color = lk.hair;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-2.0 * u, hy - 1.2 * u, 4.0 * u, 3.4 * u), Radius.circular(1.2 * u)), fill);
  }
  fill.color = lk.skin;
  c.drawCircle(Offset(0, hy), 1.75 * u, fill);
  c.drawCircle(Offset(0, hy), 1.75 * u, outline);
  if (role != 'chef') {
    fill.color = lk.hair;
    c.drawArc(Rect.fromCircle(center: Offset(0, hy - 0.1 * u), radius: 1.85 * u), pi, pi, true, fill);
    if (lk.hairStyle == 1) c.drawCircle(Offset(0, hy - 2.0 * u), 0.8 * u, fill);
  }

  // Mặt
  fill.color = const Color(0xFF2B2B2B);
  c.drawCircle(Offset(-0.65 * u, hy + 0.3 * u), 0.22 * u, fill);
  c.drawCircle(Offset(0.65 * u, hy + 0.3 * u), 0.22 * u, fill);
  if (mood == 0) {
    final cheek = Paint()..color = const Color(0x55FF6F61);
    c.drawCircle(Offset(-1.05 * u, hy + 0.8 * u), 0.32 * u, cheek);
    c.drawCircle(Offset(1.05 * u, hy + 0.8 * u), 0.32 * u, cheek);
  }
  final my = hy + 1.0 * u;
  if (chew) {
    c.drawOval(Rect.fromCenter(center: Offset(0, my), width: 0.7 * u, height: 0.5 * u), fill);
  } else if (mood == 0) {
    c.drawArc(Rect.fromCenter(center: Offset(0, my - 0.3 * u), width: 1.2 * u, height: 0.8 * u), 0.2, pi - 0.4, false, line);
  } else if (mood == 1) {
    c.drawLine(Offset(-0.45 * u, my), Offset(0.45 * u, my), line);
  } else {
    c.drawArc(Rect.fromCenter(center: Offset(0, my + 0.3 * u), width: 1.2 * u, height: 0.8 * u), pi + 0.2, pi - 0.4, false, line);
    c.drawLine(Offset(-1.0 * u, hy - 0.45 * u), Offset(-0.3 * u, hy - 0.1 * u), line);
    c.drawLine(Offset(1.0 * u, hy - 0.45 * u), Offset(0.3 * u, hy - 0.1 * u), line);
  }

  // Mũ đầu bếp
  if (role == 'chef') {
    fill.color = Colors.white;
    final hat = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-1.5 * u, hy - 3.2 * u, 3.0 * u, 1.9 * u), Radius.circular(0.3 * u)))
      ..addOval(Rect.fromCircle(center: Offset(-1.0 * u, hy - 3.3 * u), radius: 0.95 * u))
      ..addOval(Rect.fromCircle(center: Offset(0, hy - 3.8 * u), radius: 1.05 * u))
      ..addOval(Rect.fromCircle(center: Offset(1.0 * u, hy - 3.3 * u), radius: 0.95 * u));
    c.drawPath(hat, fill);
    c.drawPath(hat, outline);
    fill.color = const Color(0xFFECEFF1);
    c.drawRect(Rect.fromLTWH(-1.6 * u, hy - 1.75 * u, 3.2 * u, 0.6 * u), fill);
  }
  c.restore();
}

// =====================================================================
//  SẢNH NHÀ HÀNG (vai PHỤC VỤ)
// =====================================================================
const _walkIn = 1.1, _walkOut = 1.3;

class _Leaver {
  final int table, seed;
  final double t0;
  final bool happy;
  _Leaver(this.table, this.seed, this.t0, this.happy);
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
  final String venueId;
  final int decor;
  final void Function(int) onTable;
  final void Function(Dish) onDish;
  const DiningScene({
    super.key,
    required this.tables,
    required this.counter,
    required this.selDishId,
    required this.venueId,
    required this.decor,
    required this.onTable,
    required this.onDish,
  });

  @override
  State<DiningScene> createState() => _DiningSceneState();
}

class _DiningSceneState extends State<DiningScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  double get _t => _clock.value;

  // Người phục vụ (toạ độ tỉ lệ 0..1 để không lệch khi đổi kích thước)
  Offset _wp = const Offset(0.42, 0.35), _wt = const Offset(0.42, 0.35);
  bool _placed = false, _walking = false, _left = false;
  double _phase = 0;

  // Theo dõi khách vào / ra để chạy hoạt cảnh
  List<bool> _occ = [];
  List<double> _arr = [];
  List<int> _seed = [];
  int _seedN = 0;
  final List<_Leaver> _leavers = [];
  final List<_Coin> _coins = [];

  // Bố cục (tính lại mỗi khung hình)
  Size _size = Size.zero;
  double _r = 20, _s = 48, _wallH = 60;
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
    if (_occ.length != tb.length) {
      _occ = List.filled(tb.length, false);
      _arr = List.filled(tb.length, -10.0);
      _seed = List.filled(tb.length, 0);
      _leavers.clear();
      _coins.clear();
      first = true;
    }
    for (var i = 0; i < tb.length; i++) {
      final occ = tb[i].c != null;
      if (occ && !_occ[i]) {
        _seed[i] = ++_seedN * 7919 + i * 31;
        _arr[i] = first ? -10.0 : _t;
      } else if (!occ && _occ[i] && !first) {
        final happy = tb[i].dirty; // được phục vụ xong thì bàn bẩn
        _leavers.add(_Leaver(i, _seed[i], _t, happy));
        if (happy) _coins.add(_Coin(i, _t));
      }
      _occ[i] = occ;
    }
  }

  void _onTick(Duration e) {
    final t = e.inMicroseconds / 1e6;
    final dt = (t - _t).clamp(0.0, 0.1).toDouble();
    if (_size != Size.zero) {
      final cur = Offset(_wp.dx * _size.width, _wp.dy * _size.height);
      final tgt = Offset(_wt.dx * _size.width, _wt.dy * _size.height);
      final d = tgt - cur;
      final dist = d.distance;
      final step = max(_size.width, 300.0) * 0.75 * dt;
      if (dist > 1) {
        final nc = dist <= step ? tgt : cur + d / dist * step;
        _wp = Offset(nc.dx / _size.width, nc.dy / _size.height);
        _walking = true;
        if (d.dx.abs() > 2) _left = d.dx < 0;
        _phase += dt * 14;
      } else {
        _walking = false;
      }
    }
    _leavers.removeWhere((l) => t - l.t0 > _walkOut);
    _coins.removeWhere((c) => t - c.t0 > 1.2);
    _clock.value = t;
  }

  void _goTo(Offset px) {
    final w = _size.width, h = _size.height;
    if (w < 40 || h < 40) return;
    final x = px.dx.clamp(_s * 0.3, max(_s * 0.3, w - _s * 0.3)).toDouble();
    final y = px.dy.clamp(_wallH + _s * 0.4, max(_wallH + _s * 0.4, h - 4)).toDouble();
    _wt = Offset(x / w, y / h);
  }

  void _tap(TapUpDetails d) {
    final p = d.localPosition;
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
        _goTo(_tc[i] + Offset(_r * 1.45, _r * 0.55));
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
    final th = vtheme(widget.venueId);
    final tb = widget.tables;
    final n = tb.length;
    final t = _t;

    // ---------- Bố cục ----------
    final wallH = max(64.0, h * 0.22);
    _wallH = wallH;
    final cols = n <= 4 ? max(n, 1) : 4;
    final rows = max(1, (n / cols).ceil());
    final floorTop = wallH + 6;
    final cellW = w / cols, cellH = (h - floorTop - 4) / rows;
    final r = min(min(cellW * 0.27, cellH * 0.24), 46.0);
    final s = r * 2.4;
    _r = r;
    _s = s;
    _tc = [for (var i = 0; i < n; i++) Offset(cellW * (i % cols + 0.5), floorTop + cellH * (i ~/ cols + 0.5) + s * 0.16)];
    _hit = [for (var i = 0; i < n; i++) Rect.fromLTWH(cellW * (i % cols), floorTop + cellH * (i ~/ cols), cellW, cellH)];
    final cx0 = w * 0.03, cx1 = w * 0.74;
    final slotW = (cx1 - cx0) / 6;
    _slots = [for (var j = 0; j < 6; j++) Rect.fromLTWH(cx0 + slotW * j, wallH * 0.3, slotW, wallH * 0.7)];
    _door = Offset(w * 0.87, wallH + s * 0.35);
    if (!_placed) {
      _placed = true;
      _wp = _wt = Offset(0.42, min(0.95, (wallH + s * 0.6) / h));
    }

    // ---------- Sàn ----------
    final tile = max(24.0, w / 9);
    c.drawRect(Rect.fromLTWH(0, wallH, w, h - wallH), Paint()..color = th.floorA);
    final pb = Paint()..color = th.floorB;
    for (var y = 0; wallH + y * tile < h; y++) {
      for (var x = 0; x * tile < w; x++) {
        if ((x + y).isOdd) c.drawRect(Rect.fromLTWH(x * tile, wallH + y * tile, tile, tile), pb);
      }
    }

    // ---------- Tường ----------
    c.drawRect(Rect.fromLTWH(0, 0, w, wallH), Paint()..color = th.wall);
    final stripe = Paint()..color = _a(Colors.white, 0.07);
    for (double x = 0; x < w; x += 18) {
      c.drawRect(Rect.fromLTWH(x, 0, 9, wallH), stripe);
    }
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
    final win = RRect.fromRectAndRadius(Rect.fromLTRB(cx0 + 4, wallH * 0.08, cx1 - 4, wallH * 0.6), const Radius.circular(8));
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
      final ly = winIn.top + wallH * 0.14;
      c.drawLine(Offset(lx, winIn.top), Offset(lx, ly), Paint()
        ..color = Colors.black54
        ..strokeWidth = 1.5);
      c.drawCircle(Offset(lx, ly), wallH * 0.14, Paint()..color = _a(const Color(0xFFFFE082), 0.15 + 0.05 * sin(t * 2 + k)));
      c.drawCircle(Offset(lx, ly), wallH * 0.045, Paint()..color = const Color(0xFFFFE082));
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
        // món đang nằm trên khay của người phục vụ
        c.drawOval(Rect.fromCenter(center: pc, width: pr * 2.4, height: pr * 0.9), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.greenAccent);
        continue;
      }
      final bad = d.quality < 0.6;
      c.drawOval(Rect.fromCenter(center: pc + const Offset(0, 2), width: pr * 2.3, height: pr * 0.75), Paint()..color = const Color(0x40000000));
      c.drawOval(Rect.fromCenter(center: pc, width: pr * 2.3, height: pr * 0.75), Paint()..color = bad ? const Color(0xFFFFCDD2) : Colors.white);
      final bob = sin(t * 3 + j) * 1.5;
      _emoji(c, d.recipe.emoji, pc - Offset(0, pr * 0.75 + bob), pr * 1.6);
      if (bad) _emoji(c, '💨', pc + Offset(pr * 0.95, -pr * 1.3), pr * 0.7);
    }

    // Cửa ra vào
    final dr = Rect.fromLTRB(w * 0.79, wallH * 0.1, w * 0.95, wallH);
    c.drawRect(dr.inflate(3), Paint()..color = th.trim);
    c.drawRect(dr, Paint()..color = _dk(th.wood, 0.05));
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(dr.left + dr.width * 0.2, dr.top + dr.height * 0.1, dr.width * 0.6, dr.height * 0.35), const Radius.circular(4)),
      Paint()..color = const Color(0xFFB3E5FC),
    );
    c.drawCircle(Offset(dr.right - dr.width * 0.18, dr.top + dr.height * 0.62), max(2.0, dr.width * 0.06), Paint()..color = const Color(0xFFFFD54F));
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(dr.center.dx, wallH + 6), width: dr.width * 1.15, height: 10), const Radius.circular(3)),
      Paint()..color = _a(th.accent, 0.85),
    );
    c.drawRect(Rect.fromLTWH(0, wallH - 4, w, 5), Paint()..color = th.trim);

    // ---------- Vẽ theo chiều sâu (y nhỏ vẽ trước) ----------
    final items = <_Item>[];
    for (var i = 0; i < n; i++) {
      items.add(_Item(_tc[i].dy, () => _drawTable(c, i, t)));
    }
    for (var i = 0; i < n; i++) {
      if (tb[i].c != null && t - _arr[i] < _walkIn) {
        final k = ((t - _arr[i]) / _walkIn).clamp(0.0, 1.0).toDouble();
        final seat = _seat(i);
        final p = Offset.lerp(_door, seat, Curves.easeInOut.transform(k))!;
        final look = Look.seed(_seed[i]);
        items.add(_Item(p.dy, () => drawPerson(c, p, s, look, walking: true, phase: t * 13 + i, facingLeft: seat.dx < _door.dx)));
      }
    }
    for (final l in _leavers) {
      if (l.table >= n) continue;
      final k = ((t - l.t0) / _walkOut).clamp(0.0, 1.0).toDouble();
      final from = _seat(l.table);
      final p = Offset.lerp(from, _door, Curves.easeIn.transform(k))!;
      final look = Look.seed(l.seed);
      items.add(_Item(p.dy, () => drawPerson(c, p, s, look, walking: true, phase: t * 13, facingLeft: _door.dx < from.dx, mood: l.happy ? 0 : 2)));
    }
    final plants = [
      Offset(r * 0.7, h - r * 0.5),
      Offset(w - r * 0.7, h - r * 0.5),
      Offset(w * 0.75, wallH + r * 0.4),
      Offset(w * 0.5, h - r * 0.4),
    ];
    for (var k = 0; k < widget.decor && k < plants.length; k++) {
      final pp = plants[k];
      items.add(_Item(pp.dy, () => _emoji(c, k.isEven ? '🪴' : '🌿', pp - Offset(0, r * 0.4), r * 1.1)));
    }
    String? carry;
    for (final d in widget.counter) {
      if (d.ticketId == widget.selDishId) carry = d.recipe.emoji;
    }
    final wp = Offset(_wp.dx * w, _wp.dy * h);
    items.add(_Item(wp.dy, () => drawPerson(c, wp, s, waiterLook, walking: _walking, phase: _phase, facingLeft: _left, role: 'waiter', carry: carry)));

    items.sort((a, b) => a.y.compareTo(b.y));
    for (final it in items) {
      it.draw();
    }

    // ---------- Lớp trên cùng: bong bóng, tiền ----------
    for (var i = 0; i < n; i++) {
      _drawOverlay(c, i, t);
    }
    for (final cn in _coins) {
      if (cn.table >= n) continue;
      final k = ((t - cn.t0) / 1.2).clamp(0.0, 1.0).toDouble();
      _emoji(c, '💰', _tc[cn.table] - Offset(0, r * 0.8 + k * r * 1.6), r * 0.8, alpha: 1 - k);
    }
  }

  void _drawTable(Canvas c, int i, double t) {
    final th = vtheme(widget.venueId);
    final tb = widget.tables[i];
    final ct = _tc[i];
    final r = _r;
    final cu = tb.c;
    final seated = cu != null && t - _arr[i] >= _walkIn;

    // Ghế (phía sau bàn)
    final chair = RRect.fromRectAndRadius(Rect.fromCenter(center: ct + Offset(0, -r * 0.95), width: r * 1.3, height: r * 1.3), Radius.circular(r * 0.25));
    c.drawRRect(chair, Paint()..color = _dk(th.wood, 0.15));
    c.drawRRect(chair.deflate(r * 0.12), Paint()..color = _lt(th.accent, 0.15));

    if (cu != null && seated) {
      final frac = (cu.pat / cu.maxPat).clamp(0.0, 1.0);
      final mood = cu.st == 2 ? 0 : (frac < 0.35 ? 2 : (frac < 0.6 ? 1 : 0));
      drawPerson(
        c,
        _seat(i),
        _s,
        Look.seed(_seed[i]),
        sitting: true,
        mood: mood,
        armUp: cu.st == 0,
        chew: cu.st == 2 && sin(t * 12) > 0,
        bob: cu.st == 0 ? sin(t * 6).abs() * r * 0.08 : 0.0,
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
      _emoji(c, cu.recipe.emoji, ct - Offset(0, r * 0.12), r * 0.8);
    }

    final lab = _text('${i + 1}', r * 0.34, color: _dk(th.wood, 0.4), bold: true);
    lab.paint(c, ct + Offset(r * 0.78 - lab.width / 2, -lab.height / 2));
  }

  void _drawOverlay(Canvas c, int i, double t) {
    final tb = widget.tables[i];
    final cu = tb.c;
    final r = _r;
    if (tb.dirty) {
      final pulse = 0.88 + 0.12 * sin(t * 5);
      final bc = _tc[i] + Offset(r * 0.9, -r * 1.7);
      _bubble(c, bc, r * 1.0 * pulse, r * 0.9 * pulse, Colors.white);
      _emoji(c, '🧹', bc, r * 0.6 * pulse);
      return;
    }
    if (cu == null || t - _arr[i] < _walkIn || cu.st == 2) return;
    final frac = (cu.pat / cu.maxPat).clamp(0.0, 1.0).toDouble();
    final sel = widget.selDishId != null && widget.selDishId == cu.ticketId;
    final bw = r * 1.35, bh = r * 1.1;
    final bounce = cu.st == 0 ? sin(t * 7).abs() * r * 0.12 : 0.0;
    final bc = _seat(i) + Offset(r * 1.2, -_s * 0.6 - bounce);
    _bubble(c, bc, bw, bh, sel ? const Color(0xFFC8E6C9) : Colors.white, border: sel ? Colors.green : null);
    _emoji(c, cu.st == 0 ? '❗' : cu.recipe.emoji, bc, cu.st == 0 ? r * 0.6 : r * 0.7);

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
  final String venueId;
  final String Function(String) ingEmoji;
  final void Function(int) onStation;
  const KitchenScene({
    super.key,
    required this.stations,
    required this.activeStation,
    required this.hasOrders,
    required this.venueId,
    required this.ingEmoji,
    required this.onStation,
  });

  @override
  State<KitchenScene> createState() => _KitchenSceneState();
}

class _KitchenSceneState extends State<KitchenScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  double _cx = -1; // vị trí x của đầu bếp (pixel)
  bool _walking = false, _left = true;
  double _phase = 0;
  int _target = 0;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
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
      final cellW = _size.width / n;
      final tx = cellW * (_chefAt + 0.5) + cellW * 0.3;
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
    final n = widget.stations.length;
    if (n == 0 || _size.width <= 0) return;
    final i = min(max((d.localPosition.dx / (_size.width / n)).floor(), 0), n - 1);
    _target = i;
    widget.onStation(i);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _tap,
        child: SizedBox.expand(child: CustomPaint(painter: _KitchenPainter(this))),
      );

  void _paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    if (w < 40 || h < 40) return;
    _size = sz;
    final th = vtheme(widget.venueId);
    final st = widget.stations;
    final n = st.length;
    final t = _clock.value;

    // Tường gạch men
    final wallB = h * 0.62;
    c.drawRect(Rect.fromLTWH(0, 0, w, wallB), Paint()..color = const Color(0xFFF4F0EA));
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
    for (var i = 0; i < n; i++) {
      _drawStove(c, i, cellW, h, t);
    }

    // Đầu bếp
    final cs = min(h * 0.45, cellW * 0.95);
    if (_cx < 0) _cx = cellW * (_chefAt + 0.5) + cellW * 0.3;
    final at = _chefAt;
    final stirring = !_walking && at < n && st[at].cooking;
    final anyBurnt = st.any((x) => x.burnt);
    drawPerson(
      c,
      Offset(_cx, h * 0.97),
      cs,
      chefLook,
      role: 'chef',
      walking: _walking,
      phase: _phase,
      facingLeft: _walking ? _left : true,
      mood: anyBurnt ? 2 : 0,
      stir: stirring ? t * 8 : -1,
    );
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
    for (var k = 0; k < 3; k++) {
      c.drawCircle(Offset(body.left + body.width * (0.25 + 0.25 * k), topY + h * 0.075), max(2.5, h * 0.018), Paint()..color = const Color(0xFF455A64));
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
        final fh = h * 0.035 * fl;
        final flame = Path()
          ..moveTo(fx - fh * 0.5, topY - 1)
          ..quadraticBezierTo(fx, topY - fh * 1.9, fx + fh * 0.5, topY - 1)
          ..close();
        c.drawPath(flame, Paint()..color = const Color(0xFFFF9800));
        c.drawCircle(Offset(fx, topY - fh * 0.35), fh * 0.22, Paint()..color = const Color(0xFFFFEB3B));
      }
    }
    final potColor = s.burnt ? const Color(0xFF212121) : const Color(0xFF78909C);
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
    c.drawOval(Rect.fromCenter(center: potRect.topCenter, width: potW, height: potH * 0.35), Paint()..color = _dk(potColor, 0.3));
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
      _emoji(c, tk.recipe.emoji, potRect.topCenter - Offset(0, potH * 0.55 + b), potH * 1.1);
      if (!s.burnt) {
        _emoji(c, '✨', potRect.topCenter + Offset(potW * 0.45, -potH * 1.0), potH * 0.55, alpha: 0.4 + 0.6 * sin(t * 6).abs());
      }
    }

    // Thông tin đơn
    final fs = min(h * 0.055, cellW * 0.13);
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
    _pill(c, '${tk.recipe.emoji} B${tk.table + 1}', Offset(cx, h * 0.07), fs);
    if (!s.done) {
      final ings = tk.recipe.ings;
      final isz = min(cellW * 0.8 / ings.length, h * 0.075);
      for (var k = 0; k < ings.length; k++) {
        final ip = Offset(cx + (k - (ings.length - 1) / 2) * isz * 1.15, h * 0.175);
        final got = s.added.contains(ings[k]);
        c.drawCircle(ip, isz * 0.58, Paint()..color = got ? const Color(0xFFC8E6C9) : Colors.white);
        c.drawCircle(ip, isz * 0.58, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = got ? Colors.green : const Color(0xFFBDBDBD));
        _emoji(c, widget.ingEmoji(ings[k]), ip, isz * 0.75, alpha: got ? 0.35 : 1);
      }
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
    } else {
      label = 'Chọn nguyên liệu';
      bg = Colors.white;
    }
    _pill(c, label, Offset(cx, ov.center.dy - h * 0.02), fs * 0.75, bg: bg);

    final bar = Rect.fromLTWH(ov.left + 5, ov.bottom - 9, ov.width - 10, 5);
    double? frac;
    Color barC = const Color(0xFFFFB300);
    if (s.cooking) {
      frac = s.need <= 0 ? 0.0 : (s.prog / s.need).clamp(0.0, 1.0).toDouble();
    } else if (s.done && !s.burnt) {
      frac = (1 - s.doneT / 7).clamp(0.0, 1.0).toDouble(); // thời gian còn lại trước khi cháy
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
