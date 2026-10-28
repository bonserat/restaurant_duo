// Bản đồ phố nhìn nghiêng (2.5D isometric): mỗi quán là một ngôi nhà cắt mái,
// thấy được sàn gạch, bàn ghế, quầy bếp bên trong. Có đường, sông, cầu, cây, bồn hoa,
// xe chạy, người đi bộ. Kéo để di chuyển, chụm 2 ngón để phóng to.
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'data.dart';
import 'scene.dart' show drawPerson, Look, webTick;

// ------------------------------------------------------------------ hệ toạ độ
const double _tw = 48; // bề ngang 1 ô
const double _th = 24; // bề cao 1 ô
const int _n = 22; // lưới 22 × 22 ô
const double _ox = 540; // gốc toạ độ trên khung vẽ
const double _oy = 130;
const Size kTownSize = Size(1080, 720);

Offset _iso(double gx, double gy, [double z = 0]) => Offset(_ox + (gx - gy) * _tw / 2, _oy + (gx + gy) * _th / 2 - z);

Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy)
  ..lineTo(c.dx, c.dy)
  ..lineTo(d.dx, d.dy)
  ..close();

Path _area(double x0, double y0, double x1, double y1, [double z = 0]) => _quad(_iso(x0, y0, z), _iso(x1, y0, z), _iso(x1, y1, z), _iso(x0, y1, z));

Color _dk(Color c, [double k = 0.2]) => Color.lerp(c, Colors.black, k)!;
Color _lt(Color c, [double k = 0.2]) => Color.lerp(c, Colors.white, k)!;
Color _grey(Color c) {
  final l = (c.r * 0.3 + c.g * 0.59 + c.b * 0.11);
  return Color.from(alpha: 1, red: l * 0.9 + 0.08, green: l * 0.9 + 0.08, blue: l * 0.9 + 0.1);
}

/// Bộ màu của từng quán: sàn A, sàn B, tường, viền, khăn bàn, mái hiên
class _Look {
  final Color floorA, floorB, wall, trim, cloth, awning;
  const _Look(this.floorA, this.floorB, this.wall, this.trim, this.cloth, this.awning);
}

const _looks = {
  'cafe': _Look(Color(0xFFC8A27A), Color(0xFFB88E64), Color(0xFFF3E1C7), Color(0xFF6D4C41), Color(0xFFFFF3E0), Color(0xFFE6A15A)),
  'bakery': _Look(Color(0xFFFFFFFF), Color(0xFFF8BBD0), Color(0xFFFFE4EC), Color(0xFFB0577A), Color(0xFFFFF0F5), Color(0xFFFF80AB)),
  'chinese': _Look(Color(0xFFD84315), Color(0xFFB71C1C), Color(0xFFFFF1D6), Color(0xFF6D0F0F), Color(0xFFFFE9B0), Color(0xFFFFC107)),
  'mexican': _Look(Color(0xFFE6A57E), Color(0xFFD08B62), Color(0xFFFFE7CF), Color(0xFF1E8A8A), Color(0xFFFFF3E0), Color(0xFFFF7043)),
  'truck': _Look(Color(0xFFB0BEC5), Color(0xFF90A4AE), Color(0xFFFFFFFF), Color(0xFF37474F), Color(0xFFECEFF1), Color(0xFFFF5722)),
  'poseidon': _Look(Color(0xFFB3E5FC), Color(0xFFFFFFFF), Color(0xFFE1F5FE), Color(0xFF0D47A1), Color(0xFFF1FBFF), Color(0xFF00ACC1)),
  'goyuhan': _Look(Color(0xFF4E3B2D), Color(0xFF3E2E22), Color(0xFFFFF3E0), Color(0xFF8E1B1B), Color(0xFFFFF3E0), Color(0xFF212121)),
  'binhdan': _Look(Color(0xFFD9B77A), Color(0xFFC9A465), Color(0xFFFFF0C2), Color(0xFF6D4C1F), Color(0xFFFFF8E1), Color(0xFF558B2F)),
};

/// Một lô đất trên bản đồ
class _Lot {
  final String key; // 'cafe'… hoặc 'sig_mine' / 'sig_partner' / 'garden'
  final double x0, y0, x1, y1;
  const _Lot(this.key, this.x0, this.y0, this.x1, this.y1);
  Offset get front => _iso(x1, y1);
  double get depth => x1 + y1;
}

// Đường: Hoà Xuân (gy = 6.5), Nguyễn Phước Lan (gx = 11), Hói Kiểng 21 (gy = 17); sông ở gy 10.1–11.5
const double _r1 = 6.5, _r2 = 11, _r3 = 17, _rw = 0.7;
const double _rv0 = 10.1, _rv1 = 11.5;

const _lots = [
  _Lot('sig_mine', 2.4, 1.0, 8.4, 5.2),
  _Lot('sig_partner', 13.4, 1.0, 19.4, 5.2),
  _Lot('cafe', 1.4, 12.7, 5.4, 16.0),
  _Lot('bakery', 6.2, 12.7, 10.0, 16.0),
  _Lot('chinese', 12.4, 12.7, 16.2, 16.0),
  _Lot('mexican', 17.0, 12.7, 21.0, 16.0),
  _Lot('truck', 13.0, 18.4, 16.6, 21.2),
  _Lot('garden', 13.2, 7.7, 20.6, 9.8),
];

/// Một lô "nhà hàng riêng" trên bản đồ: của mình (bên trái) hoặc của người kia (bên phải)
class SigSpot {
  final String hitId; // id gửi về khi chạm
  final String? venueId; // null = chưa mở (đất trống)
  final String owner;
  final int rank; // hạng quán 1..5
  final bool mine;
  const SigSpot({required this.hitId, required this.venueId, required this.owner, required this.rank, required this.mine});
}

class TownMap extends StatefulWidget {
  final Set<String> owned;
  final String current;
  final bool night;
  final void Function(String venueId) onTap;
  final List<SigSpot> sigs;
  const TownMap({super.key, required this.owned, required this.current, required this.onTap, this.night = false, this.sigs = const []});
  @override
  State<TownMap> createState() => _TownMapState();
}

class _TownMapState extends State<TownMap> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  final _tc = TransformationController();
  final Map<String, Rect> _hit = {};
  String? _pressed;
  bool _placed = false;
  ui.Picture? _static;
  String _staticKey = '';

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => webTick(_clock, e))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _tc.dispose();
    _static?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ lô đất ↔ quán
  SigSpot? _sigFor(String key) {
    for (final s in widget.sigs) {
      if (key == 'sig_mine' && s.mine) return s;
      if (key == 'sig_partner' && !s.mine) return s;
    }
    return null;
  }

  /// Quán đang đặt trên lô (null = đất trống / vườn)
  String? _venueOf(_Lot l) {
    if (l.key.startsWith('sig_')) return _sigFor(l.key)?.venueId;
    if (l.key == 'garden') return null;
    return l.key;
  }

  /// id gửi lên khi chạm vào lô
  String _hitIdOf(_Lot l) {
    if (l.key.startsWith('sig_')) return _sigFor(l.key)?.hitId ?? l.key;
    return l.key;
  }

  Rect _lotRect(_Lot l) {
    final pts = [_iso(l.x0, l.y0, 60), _iso(l.x1, l.y0), _iso(l.x1, l.y1), _iso(l.x0, l.y1)];
    var r = Rect.fromPoints(pts[0], pts[1]);
    for (final p in pts) {
      r = r.expandToInclude(Rect.fromCenter(center: p, width: 1, height: 1));
    }
    return r.inflate(4);
  }

  Offset _focus() {
    for (final l in _lots) {
      if (_venueOf(l) == widget.current) return _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2);
    }
    final m = _lots.first;
    return _iso((m.x0 + m.x1) / 2, (m.y0 + m.y1) / 2);
  }

  String? _at(Offset p) {
    // ưu tiên lô ở phía trước (gần người xem hơn)
    final sorted = [..._lots]..sort((a, b) => b.depth.compareTo(a.depth));
    for (final l in sorted) {
      final id = _hitIdOf(l);
      final r = _hit[id];
      if (r != null && r.contains(p)) return id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, cons) {
        final vw = cons.maxWidth, vh = cons.maxHeight;
        final minScale = max(vw / kTownSize.width, vh / kTownSize.height);
        if (!_placed && vw > 0 && vh > 0) {
          _placed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final s = max(minScale, min(1.0, vw / 640));
            final f = _focus();
            final dx = (vw / 2 - f.dx * s).clamp(vw - kTownSize.width * s, 0.0).toDouble();
            final dy = (vh / 2 - f.dy * s).clamp(vh - kTownSize.height * s, 0.0).toDouble();
            _tc.value = Matrix4.identity()
              ..translate(dx, dy)
              ..scale(s);
          });
        }
        return InteractiveViewer(
          transformationController: _tc,
          constrained: false,
          minScale: minScale,
          maxScale: 2.2,
          boundaryMargin: EdgeInsets.zero,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => setState(() => _pressed = _at(d.localPosition)),
            onTapCancel: () => setState(() => _pressed = null),
            onTapUp: (d) {
              final id = _at(d.localPosition);
              setState(() => _pressed = null);
              if (id != null) widget.onTap(id);
            },
            child: SizedBox(width: kTownSize.width, height: kTownSize.height, child: CustomPaint(painter: _TownPainter(this))),
          ),
        );
      });

  // ------------------------------------------------------------------ vẽ
  void _paint(Canvas c, Size sz) {
    final t = _clock.value;
    final phase = realDayPhase();
    final night = widget.night || phase == 2;
    // phần tĩnh (đất, đường, nhà, cây) vẽ 1 lần rồi dùng lại cho nhẹ máy
    final key = [
      widget.owned.join(','),
      widget.current,
      night,
      for (final s in widget.sigs) '${s.venueId}${s.rank}${s.owner}',
    ].join('|');
    if (_static == null || key != _staticKey) {
      _static?.dispose();
      final rec = ui.PictureRecorder();
      _paintStatic(Canvas(rec), night);
      _static = rec.endRecording();
      _staticKey = key;
    }
    c.drawPicture(_static!);
    _paintLive(c, t, night, phase);
  }

  // ======================= PHẦN TĨNH =======================
  void _paintStatic(Canvas c, bool night) {
    final all = Offset.zero & kTownSize;
    c.drawRect(all, Paint()..color = const Color(0xFF7CC36A));
    // cỏ lốm đốm
    final rr = Random(5);
    for (var k = 0; k < 260; k++) {
      final p = Offset(rr.nextDouble() * kTownSize.width, rr.nextDouble() * kTownSize.height);
      c.drawOval(Rect.fromCenter(center: p, width: 7 + rr.nextDouble() * 8, height: 3 + rr.nextDouble() * 3), Paint()..color = const Color(0x2A2E7D32));
    }
    // nền đất của cả khu phố (khối nổi)
    c.drawPath(_area(0, 0, _n.toDouble(), _n.toDouble()), Paint()..color = const Color(0xFF8ED081));
    _sideFaces(c, 0, 0, _n.toDouble(), _n.toDouble(), 10, const Color(0xFF6D9F4E), const Color(0xFF5B8A3F));

    // vỉa hè lát gạch quanh các khối nhà
    for (final b in const [
      [0.6, 0.4, 10.0, 5.8],
      [12.0, 0.4, 21.4, 5.8],
      [0.6, 12.2, 10.0, 16.3],
      [12.0, 12.2, 21.4, 16.3],
      [12.2, 17.9, 17.2, 21.7],
    ]) {
      _plaza(c, b[0], b[1], b[2], b[3]);
    }

    // sông + cầu
    _river(c);
    // đường
    _roadH(c, _r1);
    _roadH(c, _r3);
    _roadV(c, _r2);
    _bridge(c);
    _roadName(c, 3.2, _r1, 'Đường Hoà Xuân', true);
    _roadName(c, 4.2, _r3, 'Đường Hói Kiểng 21', true);
    _roadName(c, _r2, 13.6, 'Đường Nguyễn Phước Lan', false);

    // các vật thể, vẽ từ xa tới gần
    final draws = <(double, void Function())>[];
    for (final l in _lots) {
      draws.add((l.depth, () => _drawLot(c, l, night)));
    }
    // cây, bồn hoa, đèn đường, ghế đá
    final deco = Random(11);
    final treeSpots = <Offset>[
      const Offset(1.2, 6.0), const Offset(9.4, 0.6), const Offset(20.6, 0.8), const Offset(21.2, 5.4), const Offset(0.6, 2.4),
      const Offset(1.4, 8.2), const Offset(3.6, 9.2), const Offset(7.6, 8.4), const Offset(9.6, 9.6),
      const Offset(0.7, 12.4), const Offset(10.6, 12.6), const Offset(21.7, 12.4), const Offset(21.6, 15.9),
      const Offset(1.4, 18.8), const Offset(4.2, 21.0), const Offset(8.8, 19.2), const Offset(10.0, 21.4), const Offset(19.4, 18.8), const Offset(21.0, 21.2),
      const Offset(6.4, 21.5), const Offset(17.8, 21.5),
    ];
    for (var i = 0; i < treeSpots.length; i++) {
      final p = treeSpots[i];
      final kind = i % 3; // 0 cây xanh, 1 cây ăn trái, 2 anh đào hồng
      draws.add((p.dx + p.dy, () => _tree(c, p.dx, p.dy, kind, deco.nextDouble())));
    }
    // công viên nhỏ bên trái giữa: đài phun nước, ghế, bồn hoa
    draws.add((5.6 + 8.6, () => _fountain(c, 5.6, 8.6)));
    for (final b in const [Offset(3.0, 7.9), Offset(8.4, 9.4)]) {
      draws.add((b.dx + b.dy, () => _bench(c, b.dx, b.dy)));
    }
    for (final f in const [Offset(2.2, 9.4), Offset(8.0, 7.7), Offset(4.6, 7.6), Offset(2.0, 20.0), Offset(7.6, 20.2), Offset(19.6, 20.2)]) {
      draws.add((f.dx + f.dy + 0.5, () => _flowerBed(c, f.dx, f.dy)));
    }
    // đèn đường dọc các con đường
    for (var x = 1.5; x < 22; x += 4) {
      if ((x - _r2).abs() < 1.2) continue;
      draws.add((x + _r1 - _rw - 0.15, () => _lamp(c, x, _r1 - _rw - 0.15, night)));
      draws.add((x + _r3 + _rw + 0.15, () => _lamp(c, x, _r3 + _rw + 0.15, night)));
    }
    for (var y = 2.0; y < 22; y += 4.5) {
      if ((y - _r1).abs() < 1.2 || (y - _r3).abs() < 1.2 || (y > _rv0 - 0.5 && y < _rv1 + 0.5)) continue;
      draws.add((_r2 + _rw + 0.15 + y, () => _lamp(c, _r2 + _rw + 0.15, y, night)));
    }
    // hàng rào cây xanh dọc mép các khối nhà
    for (final h in const [
      [0.8, 5.55, 2.2, 5.75],
      [8.8, 5.55, 9.9, 5.75],
      [12.1, 5.55, 13.2, 5.75],
      [19.7, 5.55, 21.3, 5.75],
      [0.8, 12.3, 1.2, 16.1],
      [21.1, 12.3, 21.3, 16.1],
    ]) {
      draws.add((h[2] + h[3], () => _box(c, h[0], h[1], h[2], h[3], 9, const Color(0xFF43A047), const Color(0xFF2E7D32), const Color(0xFF388E3C))));
    }
    draws.sort((a, b) => a.$1.compareTo(b.$1));
    for (final d in draws) {
      d.$2();
    }
  }

  void _sideFaces(Canvas c, double x0, double y0, double x1, double y1, double h, Color left, Color right) {
    // 2 mặt bên nhìn thấy được của một khối (phía trước-trái và trước-phải)
    final l = _iso(x0, y1), b = _iso(x1, y1), r = _iso(x1, y0);
    c.drawPath(_quad(l, b, b + Offset(0, h), l + Offset(0, h)), Paint()..color = left);
    c.drawPath(_quad(b, r, r + Offset(0, h), b + Offset(0, h)), Paint()..color = right);
  }

  /// Khối hộp nổi (top ở độ cao h)
  void _box(Canvas c, double x0, double y0, double x1, double y1, double h, Color top, Color left, Color right) {
    final l = _iso(x0, y1), b = _iso(x1, y1), r = _iso(x1, y0);
    c.drawPath(_quad(l, b, b - Offset(0, h), l - Offset(0, h)), Paint()..color = left);
    c.drawPath(_quad(b, r, r - Offset(0, h), b - Offset(0, h)), Paint()..color = right);
    c.drawPath(_area(x0, y0, x1, y1, h), Paint()..color = top);
  }

  void _plaza(Canvas c, double x0, double y0, double x1, double y1) {
    c.drawPath(_area(x0, y0, x1, y1), Paint()..color = const Color(0xFFE3E0D8));
    final line = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 1;
    for (var x = x0; x <= x1 + 0.01; x += 0.7) {
      c.drawLine(_iso(x, y0), _iso(x, y1), line);
    }
    for (var y = y0; y <= y1 + 0.01; y += 0.7) {
      c.drawLine(_iso(x0, y), _iso(x1, y), line);
    }
  }

  void _roadH(Canvas c, double gy) {
    c.drawPath(_area(0, gy - _rw - 0.12, _n.toDouble(), gy + _rw + 0.12), Paint()..color = const Color(0xFFD9D4C7));
    c.drawPath(_area(0, gy - _rw, _n.toDouble(), gy + _rw), Paint()..color = const Color(0xFF5E6472));
    for (var x = 0.3; x < _n; x += 1.1) {
      if ((x - _r2).abs() < 1.0) continue;
      c.drawPath(_area(x, gy - 0.05, x + 0.55, gy + 0.05), Paint()..color = const Color(0xFFFFE082));
    }
  }

  void _roadV(Canvas c, double gx) {
    c.drawPath(_area(gx - _rw - 0.12, 0, gx + _rw + 0.12, _n.toDouble()), Paint()..color = const Color(0xFFD9D4C7));
    c.drawPath(_area(gx - _rw, 0, gx + _rw, _n.toDouble()), Paint()..color = const Color(0xFF5E6472));
    for (var y = 0.3; y < _n; y += 1.1) {
      if ((y - _r1).abs() < 1.0 || (y - _r3).abs() < 1.0) continue;
      c.drawPath(_area(gx - 0.05, y, gx + 0.05, y + 0.55), Paint()..color = const Color(0xFFFFE082));
    }
    // vạch qua đường ở các ngã tư
    for (final gy in [_r1, _r3]) {
      for (var k = 0; k < 4; k++) {
        final x = gx - _rw + 0.1 + k * 0.36;
        c.drawPath(_area(x, gy - _rw - 0.5, x + 0.18, gy - _rw - 0.12), Paint()..color = const Color(0xCCFFFFFF));
      }
    }
  }

  void _river(Canvas c) {
    c.drawPath(_area(0, _rv0 - 0.15, _n.toDouble(), _rv1 + 0.15), Paint()..color = const Color(0xFFBCAAA4));
    c.drawPath(_area(0, _rv0, _n.toDouble(), _rv1), Paint()..color = const Color(0xFF5DB8E8));
    final shine = Paint()..color = const Color(0x44FFFFFF);
    for (var x = 0.5; x < _n; x += 2.3) {
      c.drawPath(_area(x, _rv0 + 0.35, x + 0.9, _rv0 + 0.45), shine);
    }
    // bè sen
    for (final x in [3.0, 7.4, 16.0, 19.8]) {
      final p = _iso(x, (_rv0 + _rv1) / 2);
      c.drawOval(Rect.fromCenter(center: p, width: 16, height: 7), Paint()..color = const Color(0xFF66BB6A));
      c.drawCircle(p + const Offset(4, -2), 2.5, Paint()..color = const Color(0xFFF48FB1));
    }
  }

  void _bridge(Canvas c) {
    final x0 = _r2 - _rw - 0.2, x1 = _r2 + _rw + 0.2;
    _box(c, x0, _rv0 - 0.3, x1, _rv1 + 0.3, 6, const Color(0xFFA1887F), const Color(0xFF6D4C41), const Color(0xFF795548));
    c.drawPath(_area(_r2 - _rw, _rv0 - 0.3, _r2 + _rw, _rv1 + 0.3, 6), Paint()..color = const Color(0xFF5E6472));
    // lan can
    for (final x in [x0, x1]) {
      final a = _iso(x, _rv0 - 0.3, 6), b = _iso(x, _rv1 + 0.3, 6);
      c.drawLine(a - const Offset(0, 8), b - const Offset(0, 8), Paint()
        ..color = const Color(0xFF8D6E63)
        ..strokeWidth = 3);
      for (var k = 0; k <= 4; k++) {
        final p = Offset.lerp(a, b, k / 4)!;
        c.drawLine(p, p - const Offset(0, 8), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 2);
      }
    }
  }

  void _roadName(Canvas c, double gx, double gy, String text, bool alongX) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    final p = _iso(gx, gy);
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(alongX ? atan2(_th, _tw) : -atan2(_th, _tw));
    final r = Rect.fromCenter(center: Offset.zero, width: tp.width + 12, height: tp.height + 4);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = const Color(0xFF1565C0));
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(1.5), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white70,
    );
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  void _tree(Canvas c, double gx, double gy, int kind, double rnd) {
    final p = _iso(gx, gy);
    final s = 15.0 + rnd * 5;
    c.drawOval(Rect.fromCenter(center: p, width: s * 1.8, height: s * 0.7), Paint()..color = const Color(0x33000000));
    c.drawRect(Rect.fromCenter(center: p - Offset(0, s * 0.45), width: s * 0.28, height: s * 0.9), Paint()..color = const Color(0xFF795548));
    final top = p - Offset(0, s * 1.35);
    final leaf = kind == 2 ? const Color(0xFFF48FB1) : const Color(0xFF43A047);
    final leaf2 = kind == 2 ? const Color(0xFFF8BBD0) : const Color(0xFF66BB6A);
    c.drawCircle(top, s * 0.9, Paint()..color = leaf);
    c.drawCircle(top + Offset(-s * 0.4, -s * 0.3), s * 0.55, Paint()..color = leaf2);
    c.drawCircle(top + Offset(s * 0.45, s * 0.1), s * 0.5, Paint()..color = _dk(leaf, 0.1));
    if (kind == 1) {
      // trái cam chín
      for (var k = 0; k < 5; k++) {
        final a = k * 1.3;
        c.drawCircle(top + Offset(cos(a) * s * 0.55, sin(a) * s * 0.45), s * 0.13, Paint()..color = const Color(0xFFFFA726));
      }
    }
  }

  void _fountain(Canvas c, double gx, double gy) {
    _box(c, gx - 0.9, gy - 0.9, gx + 0.9, gy + 0.9, 6, const Color(0xFFCFD8DC), const Color(0xFF90A4AE), const Color(0xFFB0BEC5));
    c.drawPath(_area(gx - 0.7, gy - 0.7, gx + 0.7, gy + 0.7, 6), Paint()..color = const Color(0xFF4FC3F7));
    final p = _iso(gx, gy, 6);
    c.drawRect(Rect.fromCenter(center: p - const Offset(0, 9), width: 5, height: 18), Paint()..color = const Color(0xFFB0BEC5));
    c.drawOval(Rect.fromCenter(center: p - const Offset(0, 19), width: 18, height: 7), Paint()..color = const Color(0xFFCFD8DC));
  }

  void _bench(Canvas c, double gx, double gy) {
    _box(c, gx - 0.5, gy - 0.15, gx + 0.5, gy + 0.15, 5, const Color(0xFFA1887F), const Color(0xFF6D4C41), const Color(0xFF795548));
  }

  void _flowerBed(Canvas c, double gx, double gy) {
    _box(c, gx - 0.6, gy - 0.4, gx + 0.6, gy + 0.4, 5, const Color(0xFF6D4C41), const Color(0xFF8D6E63), const Color(0xFFA1887F));
    final rr = Random((gx * 10 + gy).round());
    const cols = [Color(0xFFE91E63), Color(0xFFFFEB3B), Color(0xFFFF7043), Color(0xFFBA68C8), Color(0xFFFFFFFF)];
    for (var k = 0; k < 10; k++) {
      final p = _iso(gx - 0.5 + rr.nextDouble(), gy - 0.3 + rr.nextDouble() * 0.6, 7);
      c.drawCircle(p, 2.2, Paint()..color = cols[k % cols.length]);
    }
  }

  void _lamp(Canvas c, double gx, double gy, bool night) {
    final p = _iso(gx, gy);
    c.drawLine(p, p - const Offset(0, 26), Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = 2.2);
    c.drawCircle(p - const Offset(0, 28), 3.6, Paint()..color = night ? const Color(0xFFFFF59D) : const Color(0xFFECEFF1));
    if (night) c.drawCircle(p - const Offset(0, 28), 12, Paint()..color = const Color(0x33FFF59D));
  }

  // ----------------------------------------------------- các lô đất / quán
  void _drawLot(Canvas c, _Lot l, bool night) {
    if (l.key == 'garden') return _gardenLot(c, l);
    final vid = _venueOf(l);
    final id = _hitIdOf(l);
    _hit[id] = _lotRect(l);
    if (vid == null) return _emptyLot(c, l, l.key == 'sig_mine');
    final owned = l.key.startsWith('sig_') || widget.owned.contains(vid);
    if (vid == 'truck') return _truckLot(c, l, owned);
    _building(c, l, vid, owned, night);
  }

  /// Ngôi nhà cắt mái: sàn gạch, 2 tường sau cao, 2 tường trước thấp, bàn ghế bên trong
  void _building(Canvas c, _Lot l, String vid, bool owned, bool night) {
    final lk0 = _looks[vid] ?? _looks['cafe']!;
    final lk = owned ? lk0 : _Look(_grey(lk0.floorA), _grey(lk0.floorB), _grey(lk0.wall), _grey(lk0.trim), _grey(lk0.cloth), _grey(lk0.awning));
    final x0 = l.x0, y0 = l.y0, x1 = l.x1, y1 = l.y1;
    const wallH = 44.0, lowH = 9.0;
    // nền nhà (bậc thềm)
    _box(c, x0 - 0.15, y0 - 0.15, x1 + 0.15, y1 + 0.15, 4, _dk(lk.trim, 0.1), _dk(lk.trim, 0.35), _dk(lk.trim, 0.25));
    // sàn gạch ô cờ
    const cell = 0.5;
    var row = 0;
    for (var gy = y0; gy < y1 - 0.01; gy += cell, row++) {
      var col = 0;
      for (var gx = x0; gx < x1 - 0.01; gx += cell, col++) {
        c.drawPath(_area(gx, gy, min(gx + cell, x1), min(gy + cell, y1), 4), Paint()..color = (row + col).isEven ? lk.floorA : lk.floorB);
      }
    }
    // tường sau bên trái (dọc cạnh gx = x0) và tường sau bên phải (dọc cạnh gy = y0)
    final tl = _iso(x0, y0, 4), tr = _iso(x1, y0, 4), bl = _iso(x0, y1, 4);
    final up = const Offset(0, wallH);
    c.drawPath(_quad(bl, tl, tl - up, bl - up), Paint()..color = _dk(lk.wall, 0.12));
    c.drawPath(_quad(tl, tr, tr - up, tl - up), Paint()..color = lk.wall);
    // viền đỉnh tường
    c.drawLine(bl - up, tl - up, Paint()
      ..color = lk.trim
      ..strokeWidth = 4);
    c.drawLine(tl - up, tr - up, Paint()
      ..color = lk.trim
      ..strokeWidth = 4);
    // cửa sổ trên tường sau
    for (var k = 1; k <= 3; k++) {
      final a = Offset.lerp(tl, tr, k / 4.2)!;
      final win = _quad(a - const Offset(0, 30), a + Offset(_tw * 0.45, _th * 0.225) - const Offset(0, 30), a + Offset(_tw * 0.45, _th * 0.225) - const Offset(0, 14), a - const Offset(0, 14));
      c.drawPath(win, Paint()..color = night ? const Color(0xFFFFE082) : const Color(0xFFB3E5FC));
      c.drawPath(
        win,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = lk.trim,
      );
    }
    for (var k = 1; k <= 2; k++) {
      final a = Offset.lerp(bl, tl, k / 3)!;
      final win = _quad(a - const Offset(0, 30), a + Offset(_tw * 0.36, -_th * 0.18) - const Offset(0, 30), a + Offset(_tw * 0.36, -_th * 0.18) - const Offset(0, 14), a - const Offset(0, 14));
      c.drawPath(win, Paint()..color = night ? const Color(0xFFFFE082) : const Color(0xFFB3E5FC));
    }
    // mái hiên sọc dọc tường sau bên phải
    const stripes = 10;
    for (var k = 0; k < stripes; k++) {
      final a = Offset.lerp(tl, tr, k / stripes)! - up + const Offset(0, 4);
      final b = Offset.lerp(tl, tr, (k + 1) / stripes)! - up + const Offset(0, 4);
      c.drawPath(_quad(a, b, b + const Offset(0, 9), a + const Offset(0, 9)), Paint()..color = k.isEven ? lk.awning : Colors.white);
    }
    // quầy bếp dọc tường sau
    _box(c, x0 + 0.25, y0 + 0.2, x1 - 0.3, y0 + 0.8, 14, _lt(lk.trim, 0.55), _dk(lk.trim, 0.05), lk.trim);
    // bếp + nồi trên quầy
    for (var k = 0; k < 3; k++) {
      final p = _iso(x0 + 1.0 + k * (x1 - x0 - 1.6) / 2.5, y0 + 0.5, 18);
      c.drawOval(Rect.fromCenter(center: p, width: 13, height: 6), Paint()..color = const Color(0xFF455A64));
      c.drawRect(Rect.fromCenter(center: p - const Offset(0, 4), width: 9, height: 7), Paint()..color = const Color(0xFFB0BEC5));
    }
    // bàn ghế
    final nx = max(1, ((x1 - x0 - 0.8) / 1.5).floor()), ny = max(1, ((y1 - y0 - 1.4) / 1.3).floor());
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final gx = x0 + 0.7 + (i + 0.5) * (x1 - x0 - 1.0) / nx;
        final gy = y0 + 1.4 + (j + 0.5) * (y1 - y0 - 1.7) / ny;
        _table(c, gx, gy, lk);
      }
    }
    // tường trước thấp (để nhìn được vào trong), chừa lối vào ở giữa cạnh trước-phải
    final br = _iso(x1, y1, 4), rr = _iso(x1, y0, 4);
    final low = const Offset(0, lowH);
    c.drawPath(_quad(bl, br, br - low, bl - low), Paint()..color = _dk(lk.wall, 0.05));
    final d0 = Offset.lerp(br, rr, 0.4)!, d1 = Offset.lerp(br, rr, 0.6)!;
    c.drawPath(_quad(br, d0, d0 - low, br - low), Paint()..color = _dk(lk.wall, 0.18));
    c.drawPath(_quad(d1, rr, rr - low, d1 - low), Paint()..color = _dk(lk.wall, 0.18));
    for (final p in [bl, br, rr, tl]) {
      c.drawLine(p, p - Offset(0, p == tl ? wallH : lowH + 2), Paint()
        ..color = lk.trim
        ..strokeWidth = 3);
    }
    // thảm trước cửa
    c.drawPath(_area(x1 + 0.15, y0 + (y1 - y0) * 0.4, x1 + 0.6, y0 + (y1 - y0) * 0.6), Paint()..color = lk.awning);
    // biển hiệu trên góc tường sau
    final sp = _iso(x0, y0, 4 + wallH + 16);
    final v = venueById(vid);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sp, width: 34, height: 26), const Radius.circular(8)), Paint()..color = Colors.white);
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: sp, width: 34, height: 26), const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = lk.trim,
    );
    final tp = TextPainter(text: TextSpan(text: owned ? v.emoji : '🔒', style: const TextStyle(fontSize: 16)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, sp - Offset(tp.width / 2, tp.height / 2));
    if (!owned) c.drawPath(_area(x0 - 0.15, y0 - 0.15, x1 + 0.15, y1 + 0.15, 4), Paint()..color = const Color(0x33FFFFFF));
  }

  void _table(Canvas c, double gx, double gy, _Look lk) {
    // ghế 4 phía
    for (final o in const [Offset(-0.42, 0), Offset(0.42, 0), Offset(0, -0.42), Offset(0, 0.42)]) {
      _box(c, gx + o.dx - 0.12, gy + o.dy - 0.12, gx + o.dx + 0.12, gy + o.dy + 0.12, 7, _lt(lk.trim, 0.25), _dk(lk.trim, 0.1), lk.trim);
    }
    _box(c, gx - 0.28, gy - 0.28, gx + 0.28, gy + 0.28, 12, lk.cloth, _dk(lk.cloth, 0.15), _dk(lk.cloth, 0.08));
    final p = _iso(gx, gy, 14);
    c.drawCircle(p, 2.6, Paint()..color = const Color(0xFFE57373));
  }

  void _emptyLot(Canvas c, _Lot l, bool mine) {
    final col = mine ? const Color(0xFFFF6A47) : const Color(0xFF4C8DFF);
    _box(c, l.x0, l.y0, l.x1, l.y1, 3, const Color(0xFFD7C4A3), const Color(0xFFB59E7A), const Color(0xFFC4AD88));
    // cọc rào công trường
    final edges = [
      [l.x0, l.y0, l.x1, l.y0],
      [l.x1, l.y0, l.x1, l.y1],
      [l.x1, l.y1, l.x0, l.y1],
      [l.x0, l.y1, l.x0, l.y0],
    ];
    for (final e in edges) {
      for (var k = 0; k <= 8; k++) {
        final p = _iso(e[0] + (e[2] - e[0]) * k / 8, e[1] + (e[3] - e[1]) * k / 8, 3);
        c.drawLine(p, p - const Offset(0, 10), Paint()
          ..color = k.isEven ? col : Colors.white
          ..strokeWidth = 3);
      }
    }
    // đống gạch + biển
    _box(c, l.x0 + 1, l.y0 + 1.2, l.x0 + 2.2, l.y0 + 2.0, 10, const Color(0xFFE57373), const Color(0xFFC62828), const Color(0xFFD32F2F));
    final p = _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2, 3);
    final tp = TextPainter(text: TextSpan(text: mine ? '🏗️' : '🚧', style: const TextStyle(fontSize: 34)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height * 0.9));
  }

  void _gardenLot(Canvas c, _Lot l) {
    _hit['garden'] = _lotRect(l);
    // luống rau
    _box(c, l.x0, l.y0, l.x1, l.y1, 3, const Color(0xFF8D6E4A), const Color(0xFF6D4C30), const Color(0xFF7A5838));
    const crops = [Color(0xFF7CB342), Color(0xFFFFCA28), Color(0xFF66BB6A), Color(0xFFE53935)];
    var k = 0;
    for (var gx = l.x0 + 0.4; gx < l.x1 - 0.5; gx += 1.3, k++) {
      _box(c, gx, l.y0 + 0.3, gx + 0.9, l.y1 - 0.3, 6, const Color(0xFF5D4030), const Color(0xFF4E342E), const Color(0xFF5D4037));
      for (var gy = l.y0 + 0.5; gy < l.y1 - 0.4; gy += 0.45) {
        final p = _iso(gx + 0.45, gy, 8);
        c.drawCircle(p, 4, Paint()..color = const Color(0xFF43A047));
        c.drawCircle(p - const Offset(0, 3), 2.4, Paint()..color = crops[k % crops.length]);
      }
    }
    // hàng rào trắng
    for (var x = l.x0; x <= l.x1 + 0.01; x += 0.5) {
      final p = _iso(x, l.y1, 3);
      c.drawLine(p, p - const Offset(0, 9), Paint()
        ..color = Colors.white
        ..strokeWidth = 2.5);
    }
    c.drawLine(_iso(l.x0, l.y1, 9), _iso(l.x1, l.y1, 9), Paint()
      ..color = Colors.white
      ..strokeWidth = 2);
  }

  void _truckLot(Canvas c, _Lot l, bool owned) {
    final lk0 = _looks['truck']!;
    final body = owned ? const Color(0xFFFFFFFF) : const Color(0xFFDADADA);
    final trim = owned ? const Color(0xFFFFC107) : const Color(0xFF9E9E9E);
    final aw = owned ? lk0.awning : const Color(0xFFBDBDBD);
    final x0 = l.x0 + 0.6, x1 = l.x1 - 0.6, y0 = l.y0 + 0.8, y1 = l.y1 - 0.8;
    // bàn ghế ngoài trời
    _table(c, l.x0 + 0.5, l.y1 - 0.2, _looks['mexican']!);
    // thùng xe
    _box(c, x0, y0, x1 - 0.9, y1, 30, _lt(body, 0.1), _dk(body, 0.12), body);
    // đầu xe
    _box(c, x1 - 0.9, y0 + 0.1, x1, y1 - 0.1, 22, trim, _dk(trim, 0.2), _dk(trim, 0.08));
    // cửa bán + mái hiên
    final a = _iso(x0 + 0.3, y1, 12), b = _iso(x1 - 1.1, y1, 12);
    c.drawPath(_quad(a, b, b - const Offset(0, 12), a - const Offset(0, 12)), Paint()..color = owned ? const Color(0xFFFFF59D) : const Color(0xFFBDBDBD));
    for (var k = 0; k < 6; k++) {
      final p0 = Offset.lerp(a, b, k / 6)! - const Offset(0, 16), p1 = Offset.lerp(a, b, (k + 1) / 6)! - const Offset(0, 16);
      c.drawPath(_quad(p0, p1, p1 + const Offset(0, 6), p0 + const Offset(0, 6)), Paint()..color = k.isEven ? aw : Colors.white);
    }
    // bánh xe
    for (final gx in [x0 + 0.4, x1 - 0.4]) {
      c.drawOval(Rect.fromCenter(center: _iso(gx, y1), width: 11, height: 9), Paint()..color = const Color(0xFF263238));
    }
    final tp = TextPainter(text: TextSpan(text: owned ? '🍔' : '🔒', style: const TextStyle(fontSize: 16)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, _iso((x0 + x1) / 2 - 0.4, (y0 + y1) / 2, 36) - Offset(tp.width / 2, tp.height / 2));
  }

  // ======================= PHẦN ĐỘNG =======================
  void _paintLive(Canvas c, double t, bool night, int phase) {
    // sóng nước
    for (var k = 0; k < 8; k++) {
      final x = (k * 2.9 + t * 0.4) % _n;
      c.drawPath(_area(x, _rv0 + 0.6, x + 0.6, _rv0 + 0.68), Paint()..color = const Color(0x66FFFFFF));
    }
    // xe chạy
    const carCols = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFDD835), Color(0xFF8E24AA)];
    for (var k = 0; k < 2; k++) {
      final gx = (t * 1.1 + k * 11) % (_n + 2) - 1;
      _car(c, gx, _r1 - 0.32, true, carCols[k]);
      final gx2 = _n + 1 - ((t * 0.9 + k * 9) % (_n + 2));
      _car(c, gx2, _r3 + 0.32, true, carCols[k + 2]);
    }
    final gy = (t * 0.8) % (_n + 2) - 1;
    _car(c, _r2 + 0.32, gy, false, const Color(0xFF43A047));
    // người đi bộ trên vỉa hè
    for (var k = 0; k < 6; k++) {
      final fwd = k.isEven;
      final along = (t * 0.35 + k * 3.7) % (_n + 1) - 0.5;
      final g = fwd ? along : _n - along;
      final onR1 = k < 3;
      final yy = onR1 ? _r1 + (k == 1 ? -_rw - 0.35 : _rw + 0.35) : _r3 + (k == 4 ? -_rw - 0.35 : _rw + 0.35);
      final p = _iso(g, yy);
      drawPerson(c, p, 20, Look.seed(k * 31 + 7), walking: true, phase: t * 10 + k, facingLeft: !fwd);
    }
    // khói bếp + tên quán + ghim quán đang chọn
    for (final l in _lots) {
      final vid = _venueOf(l);
      if (l.key == 'garden') {
        _label(c, _iso((l.x0 + l.x1) / 2, l.y0, 14) - const Offset(0, 6), '🌻 Vườn chung', Colors.white, const Color(0xFF2E7D32));
        continue;
      }
      final top = _iso(l.x0, l.y0, 4 + 44 + 34);
      final sig = l.key.startsWith('sig_') ? _sigFor(l.key) : null;
      if (vid == null) {
        final mine = l.key == 'sig_mine';
        final who = sig?.owner ?? (mine ? 'Bạn' : '');
        _label(c, _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2) + const Offset(0, 22), '🏗️ Đất của $who', mine ? const Color(0xFFFF6A47) : const Color(0xFF4C8DFF), Colors.white);
        _label(c, _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2) + const Offset(0, 44), mine ? 'Chạm để mở nhà hàng riêng' : 'Chưa mở quán', Colors.white, const Color(0xFF221B3F));
        continue;
      }
      final owned = sig != null || widget.owned.contains(vid);
      final v = venueById(vid);
      if (owned) {
        // khói từ bếp
        for (var k = 0; k < 3; k++) {
          final ph = (t * 0.4 + k / 3 + l.x0 * 0.1) % 1.0;
          final p = _iso(l.x0 + 1.4, l.y0 + 0.5, 4 + 44 + 4) - Offset(-sin(ph * 6) * 4, ph * 26);
          c.drawCircle(p, 3 + 5 * ph, Paint()..color = Color.fromRGBO(255, 255, 255, 0.6 * (1 - ph)));
        }
      }
      final name = sig != null ? '${v.emoji} ${v.name.split(' – ').first}' : (owned ? '${v.emoji} ${v.name}' : '🔒 ${v.name}');
      final bg = sig != null ? (sig.mine ? const Color(0xFFFF6A47) : const Color(0xFF4C8DFF)) : (owned ? Colors.white : const Color(0xFFEEEEEE));
      final fg = sig != null ? Colors.white : (owned ? const Color(0xFF221B3F) : const Color(0xFF6E6E80));
      final lp = vid == 'truck' ? _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2, 60) : top - const Offset(0, 10);
      _label(c, lp, name, bg, fg);
      if (sig != null) {
        _label(c, lp + const Offset(0, 20), '${'⭐' * sig.rank.clamp(1, 5)} • Quán của ${sig.owner}', Colors.white, const Color(0xFF221B3F), small: true);
      } else if (!owned) {
        _label(c, lp + const Offset(0, 20), '💰 ${v.cost}', const Color(0xFFFFC23D), const Color(0xFF5A3B00), small: true);
      }
      if (vid == widget.current && (sig == null || sig.mine)) {
        final bob = sin(t * 4).abs() * 6;
        _pin(c, lp - Offset(0, 26 + bob));
      }
      if (_pressed == _hitIdOf(l)) {
        c.drawPath(_area(l.x0 - 0.2, l.y0 - 0.2, l.x1 + 0.2, l.y1 + 0.2, 4), Paint()..color = const Color(0x33FFFFFF));
      }
    }
    // mây trôi (bóng mây trên mặt đất)
    for (var k = 0; k < 3; k++) {
      final x = (t * 12 + k * 380) % (kTownSize.width + 200) - 100;
      final y = 60.0 + k * 210;
      final p = Paint()..color = const Color(0xD9FFFFFF);
      c.drawCircle(Offset(x, y), 18, p);
      c.drawCircle(Offset(x + 18, y + 4), 14, p);
      c.drawCircle(Offset(x - 18, y + 5), 13, p);
    }
    // trời theo giờ thật
    final all = Offset.zero & kTownSize;
    if (night) {
      c.drawRect(all, Paint()..color = const Color(0x55101040));
    } else if (phase == 1) {
      c.drawRect(all, Paint()..color = const Color(0x2AFF7043));
    }
  }

  void _car(Canvas c, double g, double lane, bool alongX, Color col) {
    final x0 = alongX ? g - 0.45 : lane - 0.25, x1 = alongX ? g + 0.45 : lane + 0.25;
    final y0 = alongX ? lane - 0.25 : g - 0.45, y1 = alongX ? lane + 0.25 : g + 0.45;
    _box(c, x0, y0, x1, y1, 7, col, _dk(col, 0.25), _dk(col, 0.1));
    _box(c, x0 + (alongX ? 0.2 : 0.05), y0 + (alongX ? 0.05 : 0.2), x1 - (alongX ? 0.15 : 0.05), y1 - (alongX ? 0.05 : 0.15), 13, const Color(0xFFB3E5FC), _dk(col, 0.2), _dk(col, 0.05));
  }

  void _pin(Canvas c, Offset p) {
    const r = 9.0;
    final path = Path()
      ..moveTo(p.dx, p.dy + r * 1.6)
      ..quadraticBezierTo(p.dx - r * 1.2, p.dy + r * 0.4, p.dx - r, p.dy)
      ..arcToPoint(Offset(p.dx + r, p.dy), radius: const Radius.circular(r))
      ..quadraticBezierTo(p.dx + r * 1.2, p.dy + r * 0.4, p.dx, p.dy + r * 1.6)
      ..close();
    c.drawPath(path.shift(const Offset(0, 2)), Paint()..color = const Color(0x40000000));
    c.drawPath(path, Paint()..color = const Color(0xFFFF6A47));
    c.drawCircle(p, r * 0.45, Paint()..color = Colors.white);
  }

  void _label(Canvas c, Offset center, String text, Color bg, Color fg, {bool small = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: small ? 10 : 11.5, fontWeight: FontWeight.w800, color: fg)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: center, width: tp.width + 14, height: tp.height + 6);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
    c.drawRRect(rr.shift(const Offset(0, 2)), Paint()..color = const Color(0x33000000));
    c.drawRRect(rr, Paint()..color = bg);
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
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
