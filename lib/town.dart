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
            final s = max(minScale, 0.95); // mở ra đủ gần để thấy rõ từng toà nhà
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

  // ======================= KIẾN TRÚC TỪNG QUÁN =======================
  /// Đỉnh mái của từng lô (để đặt tên quán, khói)
  final Map<String, Offset> _roofTop = {};
  final Map<String, Offset> _chimney = {};

  Path _pg(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  /// 2 mặt tường nhìn thấy (trước-trái dọc gy = y1, trước-phải dọc gx = x1)
  void _walls(Canvas c, double x0, double y0, double x1, double y1, double h, Color wall, {double z = 0}) {
    final l = _iso(x0, y1, z), b = _iso(x1, y1, z), r = _iso(x1, y0, z);
    c.drawPath(_pg([l, b, b - Offset(0, h), l - Offset(0, h)]), Paint()..color = _dk(wall, 0.1));
    c.drawPath(_pg([b, r, r - Offset(0, h), b - Offset(0, h)]), Paint()..color = wall);
    c.drawLine(b, b - Offset(0, h), Paint()
      ..color = _dk(wall, 0.25)
      ..strokeWidth = 1);
  }

  /// Ô (cửa sổ/cửa) trên mặt trước-trái: từ gx a→b, cao z0→z1
  Path _onL(double y1, double a, double b, double z0, double z1) => _pg([_iso(a, y1, z0), _iso(b, y1, z0), _iso(b, y1, z1), _iso(a, y1, z1)]);

  /// Ô trên mặt trước-phải: từ gy a→b
  Path _onR(double x1, double a, double b, double z0, double z1) => _pg([_iso(x1, a, z0), _iso(x1, b, z0), _iso(x1, b, z1), _iso(x1, a, z1)]);

  void _windows(Canvas c, double x0, double y0, double x1, double y1, double z0, double z1, Color frame, bool night, {bool round = false, bool skipDoor = true}) {
    final glass = Paint()..color = night ? const Color(0xFFFFE082) : const Color(0xFFB3E5FC);
    final fr = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = frame;
    final nL = max(2, ((x1 - x0) / 0.9).floor());
    for (var k = 0; k < nL; k++) {
      final a = x0 + (k + 0.25) * (x1 - x0) / nL, b = a + 0.5 * (x1 - x0) / nL;
      final mid = (a + b) / 2;
      if (skipDoor && (mid - (x0 + x1) / 2).abs() < (x1 - x0) / nL * 0.6) continue; // chỗ cửa chính
      if (round) {
        final ctr = _iso(mid, y1, (z0 + z1) / 2);
        c.drawCircle(ctr, (z1 - z0) * 0.42, glass);
        c.drawCircle(ctr, (z1 - z0) * 0.42, fr);
      } else {
        c.drawPath(_onL(y1, a, b, z0, z1), glass);
        c.drawPath(_onL(y1, a, b, z0, z1), fr);
      }
    }
    final nR = max(1, ((y1 - y0) / 0.9).floor());
    for (var k = 0; k < nR; k++) {
      final a = y0 + (k + 0.25) * (y1 - y0) / nR, b = a + 0.5 * (y1 - y0) / nR;
      if (round) {
        final ctr = _iso(x1, (a + b) / 2, (z0 + z1) / 2);
        c.drawCircle(ctr, (z1 - z0) * 0.42, glass);
        c.drawCircle(ctr, (z1 - z0) * 0.42, fr);
      } else {
        c.drawPath(_onR(x1, a, b, z0, z1), glass);
        c.drawPath(_onR(x1, a, b, z0, z1), fr);
      }
    }
  }

  /// Cửa chính ở giữa mặt trước-trái + biển hiệu emoji phía trên
  void _door(Canvas c, double x0, double x1, double y1, double h, Color doorCol, Color awning, String emoji, {double z = 0, bool arch = false}) {
    final m = (x0 + x1) / 2;
    c.drawPath(_onL(y1, m - 0.3, m + 0.3, z, z + h * 0.62), Paint()..color = doorCol);
    if (arch) {
      final top = _iso(m, y1, z + h * 0.62);
      c.drawOval(Rect.fromCenter(center: top, width: _tw * 0.3, height: _th * 0.55), Paint()..color = doorCol);
    }
    // mái hiên sọc trên cửa
    for (var k = 0; k < 4; k++) {
      final a = m - 0.45 + k * 0.225;
      c.drawPath(_pg([_iso(a, y1, z + h * 0.78), _iso(a + 0.225, y1, z + h * 0.78), _iso(a + 0.225, y1 + 0.22, z + h * 0.66), _iso(a, y1 + 0.22, z + h * 0.66)]),
          Paint()..color = k.isEven ? awning : Colors.white);
    }
    // biển hiệu
    final sp = _iso(m, y1, z + h * 0.98);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sp, width: 22, height: 16), const Radius.circular(5)), Paint()..color = Colors.white);
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: sp, width: 22, height: 16), const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = awning,
    );
    final tp = TextPainter(text: TextSpan(text: emoji, style: const TextStyle(fontSize: 10)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, sp - Offset(tp.width / 2, tp.height / 2));
  }

  /// Mái 2 dốc, nóc chạy dọc theo gx
  void _gable(Canvas c, double x0, double y0, double x1, double y1, double h, double rise, Color roof, Color gableWall, {double over = 0.18}) {
    final a0 = x0 - over, a1 = x1 + over, b0 = y0 - over, b1 = y1 + over, ym = (y0 + y1) / 2;
    c.drawPath(_pg([_iso(a0, b0, h), _iso(a1, b0, h), _iso(a1, ym, h + rise), _iso(a0, ym, h + rise)]), Paint()..color = _dk(roof, 0.25));
    c.drawPath(_pg([_iso(x1, y0, h), _iso(x1, y1, h), _iso(x1, ym, h + rise)]), Paint()..color = gableWall);
    final front = _pg([_iso(a0, ym, h + rise), _iso(a1, ym, h + rise), _iso(a1, b1, h), _iso(a0, b1, h)]);
    c.drawPath(front, Paint()..color = roof);
    // hàng ngói
    final line = Paint()
      ..color = _dk(roof, 0.18)
      ..strokeWidth = 1;
    for (var k = 1; k < 4; k++) {
      final f = k / 4;
      c.drawLine(_iso(a0, ym + (b1 - ym) * f, h + rise * (1 - f)), _iso(a1, ym + (b1 - ym) * f, h + rise * (1 - f)), line);
    }
    c.drawLine(_iso(a0, ym, h + rise), _iso(a1, ym, h + rise), Paint()
      ..color = _dk(roof, 0.35)
      ..strokeWidth = 2.5);
  }

  /// Mái 4 mặt (nóc ngắn dọc gx nếu ridge > 0). curve > 0: mép mái cong vút (kiểu Á Đông)
  void _hip(Canvas c, double x0, double y0, double x1, double y1, double h, double rise, Color roof, {double over = 0.25, double ridge = 0.3, double curve = 0}) {
    final a0 = x0 - over, a1 = x1 + over, b0 = y0 - over, b1 = y1 + over, ym = (y0 + y1) / 2;
    final rl = x0 + (x1 - x0) * ridge, rr = x1 - (x1 - x0) * ridge;
    final r0 = _iso(rl, ym, h + rise), r1 = _iso(rr, ym, h + rise);
    final c00 = _iso(a0, b0, h + curve), c10 = _iso(a1, b0, h + curve), c11 = _iso(a1, b1, h + curve), c01 = _iso(a0, b1, h + curve);
    Path face(Offset e0, Offset e1, List<Offset> top, Offset sag) {
      final p = Path()..moveTo(e0.dx, e0.dy);
      if (curve > 0) {
        p.quadraticBezierTo(sag.dx, sag.dy, e1.dx, e1.dy);
      } else {
        p.lineTo(e1.dx, e1.dy);
      }
      for (final q in top) {
        p.lineTo(q.dx, q.dy);
      }
      return p..close();
    }

    Offset mid(double gx, double gy) => _iso(gx, gy, h - curve * 0.4);
    c.drawPath(face(c00, c10, [r1, r0], mid((a0 + a1) / 2, b0)), Paint()..color = _dk(roof, 0.3)); // sau
    c.drawPath(face(c01, c00, [r0], mid(a0, (b0 + b1) / 2)), Paint()..color = _dk(roof, 0.35)); // trái
    c.drawPath(face(c10, c11, [r1], mid(a1, (b0 + b1) / 2)), Paint()..color = _dk(roof, 0.12)); // phải
    final fr = face(c11, c01, [r0, r1], mid((a0 + a1) / 2, b1));
    c.drawPath(fr, Paint()..color = roof); // trước
    final line = Paint()
      ..color = _dk(roof, 0.2)
      ..strokeWidth = 1;
    for (var k = 1; k < 4; k++) {
      final f = k / 4;
      c.drawLine(Offset.lerp(r0, c01, f)!, Offset.lerp(r1, c11, f)!, line);
    }
    c.drawLine(r0, r1, Paint()
      ..color = _dk(roof, 0.4)
      ..strokeWidth = 2.5);
    if (curve > 0) {
      // đầu đao cong vút ở các góc
      for (final p in [c01, c11, c10]) {
        c.drawCircle(p - const Offset(0, 1.5), 2.2, Paint()..color = _dk(roof, 0.4));
      }
    }
  }

  /// Toà nhà theo kiến trúc riêng của quán, đặt gọn giữa lô (chừa sân xung quanh)
  void _building(Canvas c, _Lot l, String vid, bool owned, bool night) {
    final lk0 = _looks[vid] ?? _looks['cafe']!;
    Color g(Color x) => owned ? x : _grey(x);
    final x0 = l.x0 + 0.55, x1 = l.x1 - 0.55, y0 = l.y0 + 0.45, y1 = l.y1 - 0.75;
    final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    final v = venueById(vid);
    // sân trước: lối đi lát gạch ra đường + bồn cây
    c.drawPath(_area(l.x0 + 0.15, l.y0 + 0.15, l.x1 - 0.15, l.y1 - 0.15), Paint()..color = const Color(0xFF9CD67F));
    c.drawPath(_area(cx - 0.35, y1, cx + 0.35, l.y1 - 0.1), Paint()..color = const Color(0xFFE0D6C2));
    var roofTop = _iso(cx, cy, 70);
    var chimney = _iso(x0 + 0.5, y0 + 0.4, 50);
    switch (vid) {
      case 'cafe':
        // nhà gạch đỏ, mái ngói đen, mái hiên sọc đỏ-kem, biển hiệu, ghế băng, bảng phấn
        const h = 32.0;
        const brick = Color(0xFFB5643F);
        c.drawPath(_area(x0 - 0.25, y0 - 0.25, x1 + 0.35, y1 + 0.5), Paint()..color = g(const Color(0xFFB8B0A4)));
        _walls(c, x0, y0, x1, y1, h, g(brick));
        final bl = Paint()
          ..color = const Color(0x30000000)
          ..strokeWidth = 0.8;
        for (var z = 4.0; z < h; z += 4) {
          c.drawLine(_iso(x0, y1, z), _iso(x1, y1, z), bl);
          c.drawLine(_iso(x1, y1, z), _iso(x1, y0, z), bl);
        }
        final warm = Paint()..color = night ? const Color(0xFFFFD54F) : const Color(0xFFFFE9B0);
        final wf = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = g(const Color(0xFF5D3A1A));
        for (final pth in [_onL(y1, x0 + 0.25, cx - 0.3, 4, 19), _onR(x1, y0 + 0.3, y1 - 0.3, 4, 21)]) {
          c.drawPath(pth, warm);
          c.drawPath(pth, wf);
        }
        c.drawPath(_onL(y1, cx - 0.05, cx + 0.5, 0, 20), Paint()..color = g(const Color(0xFF8D5A2B)));
        c.drawPath(_onL(y1, cx + 0.08, cx + 0.37, 11, 17), warm);
        // mái hiên sọc
        final aw0 = x0 + 0.15, aw1 = cx - 0.2;
        for (var k = 0; k < 6; k++) {
          final a = aw0 + (aw1 - aw0) * k / 6, b = aw0 + (aw1 - aw0) * (k + 1) / 6;
          c.drawPath(_pg([_iso(a, y1, 22), _iso(b, y1, 22), _iso(b, y1 + 0.5, 14), _iso(a, y1 + 0.5, 14)]), Paint()..color = g(k.isEven ? const Color(0xFFB71C1C) : const Color(0xFFFFF3D6)));
        }
        // biển hiệu
        c.drawPath(_onL(y1, x0 + 0.15, x1 - 0.15, 24, 31), Paint()..color = g(const Color(0xFF8E1B1B)));
        _txt(c, owned ? 'COFFEE' : '🔒', _iso(cx, y1, 27.5), 7, const Color(0xFFFFF3D6));
        _gable(c, x0, y0, x1, y1, h, 24, g(const Color(0xFF3E3A44)), g(const Color(0xFFA9573A)), over: 0.22);
        // đồng hồ trên đầu hồi + ống khói
        final ck = _iso(x1, cy, h + 9);
        c.drawCircle(ck, 5, Paint()..color = Colors.white);
        c.drawCircle(ck, 5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = const Color(0xFF3E2723));
        c.drawLine(ck, ck - const Offset(0, 3.5), Paint()..color = const Color(0xFF3E2723));
        final chm = _iso(x0 + 0.5, y0 + 0.5, h + 14);
        c.drawRect(Rect.fromLTWH(chm.dx - 4, chm.dy - 10, 8, 16), Paint()..color = g(const Color(0xFF8D4A2F)));
        // biển treo ☕
        final hs = _iso(x1 + 0.15, y1 - 0.25, 22);
        c.drawLine(hs, hs + const Offset(8, 0), Paint()
          ..color = const Color(0xFF3E2723)
          ..strokeWidth = 1.5);
        c.drawRect(Rect.fromLTWH(hs.dx + 3, hs.dy + 1, 10, 9), Paint()..color = g(const Color(0xFF6D4C41)));
        // ghế băng, chậu cây, bảng phấn
        _box(c, x0 + 0.2, y1 + 0.2, x0 + 0.95, y1 + 0.4, 5, g(const Color(0xFF8D5A2B)), g(const Color(0xFF6D4321)), g(const Color(0xFF7A4B26)));
        for (final pp in [_iso(x0 + 0.05, y1 + 0.35), _iso(cx + 0.75, y1 + 0.35)]) {
          c.drawRect(Rect.fromCenter(center: pp - const Offset(0, 3), width: 7, height: 6), Paint()..color = const Color(0xFFB0532F));
          c.drawCircle(pp - const Offset(0, 9), 5.5, Paint()..color = g(const Color(0xFF43A047)));
        }
        final cb = _iso(x1 + 0.4, y1 + 0.1);
        c.drawPath(_pg([cb, cb + const Offset(8, 0), cb + const Offset(6, -16), cb + const Offset(2, -16)]), Paint()..color = const Color(0xFF263238));
        roofTop = _iso(cx, cy, h + 30);
        chimney = chm - const Offset(0, 12);
        break;
      case 'bakery':
        // nhà góc phố trắng kiểu Âu: phào chỉ, hàng bi trên mái, mái hiên xanh lượn sóng, bàn ngoài trời
        const h = 32.0;
        _box(c, x0 - 0.3, y0 - 0.3, x1 + 0.45, y1 + 0.6, 3, g(const Color(0xFFE6E0D6)), g(const Color(0xFFC9C2B6)), g(const Color(0xFFD6CFC3)));
        const wall = Color(0xFFF7F4EE);
        _walls(c, x0, y0, x1, y1, h, g(wall), z: 3);
        final gl = Paint()..color = night ? const Color(0xFFFFD54F) : const Color(0xFFFFE6C2);
        final wf = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = g(const Color(0xFF9A6236));
        for (final pth in [_onL(y1, x0 + 0.2, cx - 0.3, 6, 21), _onL(y1, cx - 0.1, cx + 0.45, 3, 22), _onL(y1, cx + 0.65, x1 - 0.2, 6, 21), _onR(x1, y0 + 0.25, y1 - 0.25, 6, 21)]) {
          c.drawPath(pth, gl);
          c.drawPath(pth, wf);
        }
        // phào chỉ + mái bằng + hàng bi
        _walls(c, x0 - 0.12, y0 - 0.12, x1 + 0.12, y1 + 0.12, 7, g(const Color(0xFFEDE5D8)), z: h + 3);
        c.drawPath(_area(x0 - 0.12, y0 - 0.12, x1 + 0.12, y1 + 0.12, h + 10), Paint()..color = g(const Color(0xFFF3ECE0)));
        final ball = Paint()..color = g(const Color(0xFFF1DFC4));
        for (var k = 0; k <= 8; k++) {
          c.drawCircle(_iso(x0 - 0.12 + (x1 - x0 + 0.24) * k / 8, y1 + 0.12, h + 12), 2.4, ball);
        }
        for (var k = 0; k < 5; k++) {
          c.drawCircle(_iso(x1 + 0.12, y0 - 0.12 + (y1 - y0 + 0.24) * k / 5, h + 12), 2.4, ball);
        }
        // mái hiên xanh lượn sóng 2 mặt
        final blue = g(const Color(0xFF86C9E6));
        void awning(List<Offset> q) {
          c.drawPath(_pg(q), Paint()..color = blue);
          for (var k = 1; k < 6; k++) {
            c.drawLine(Offset.lerp(q[0], q[1], k / 6)!, Offset.lerp(q[3], q[2], k / 6)!, Paint()
              ..color = _lt(blue, 0.35)
              ..strokeWidth = 1);
          }
          for (var k = 0; k < 8; k++) {
            c.drawCircle(Offset.lerp(q[3], q[2], (k + 0.5) / 8)!, 2.6, Paint()..color = blue);
          }
        }
        awning([_iso(x1, y0 + 0.15, 25), _iso(x1, y1 - 0.15, 25), _iso(x1 + 0.6, y1 - 0.15, 16), _iso(x1 + 0.6, y0 + 0.15, 16)]);
        awning([_iso(x0 + 0.1, y1, 25), _iso(x1 - 0.1, y1, 25), _iso(x1 - 0.1, y1 + 0.6, 16), _iso(x0 + 0.1, y1 + 0.6, 16)]);
        // đèn tường + biển tròn
        for (final lp in [_iso(x0 + 0.08, y1, 18), _iso(x1, y1 - 0.08, 18)]) {
          c.drawRect(Rect.fromCenter(center: lp, width: 4, height: 7), Paint()..color = const Color(0xFF37474F));
          c.drawRect(Rect.fromCenter(center: lp, width: 2.2, height: 4), Paint()..color = night ? const Color(0xFFFFF59D) : const Color(0xFFFFE0B2));
        }
        final sg = _iso(cx - 0.6, y1 + 0.02, 28);
        c.drawOval(Rect.fromCenter(center: sg, width: 18, height: 12), Paint()..color = g(const Color(0xFFA0643A)));
        _txt(c, owned ? v.emoji : '🔒', sg, 7, Colors.white);
        // bàn ghế ngoài trời + chậu cây
        for (final tg in [Offset(x1 + 0.35, y0 + 0.5), Offset(x1 + 0.35, cy + 0.4)]) {
          final tp0 = _iso(tg.dx, tg.dy);
          for (final dx in const [-6.0, 6.0]) {
            c.drawRect(Rect.fromLTWH(tp0.dx + dx - 2, tp0.dy - 8, 4, 8), Paint()..color = g(const Color(0xFF6D4321)));
          }
          c.drawLine(tp0, tp0 - const Offset(0, 9), Paint()
            ..color = const Color(0xFF37474F)
            ..strokeWidth = 1.5);
          c.drawOval(Rect.fromCenter(center: tp0 - const Offset(0, 9), width: 12, height: 5), Paint()..color = Colors.white);
        }
        for (final pp in [_iso(x0 - 0.1, y1 + 0.4), _iso(cx + 0.55, y1 + 0.45)]) {
          c.drawRect(Rect.fromCenter(center: pp - const Offset(0, 3), width: 8, height: 7), Paint()..color = const Color(0xFF5D4037));
          c.drawCircle(pp - const Offset(0, 9), 5, Paint()..color = g(const Color(0xFF558B2F)));
        }
        roofTop = _iso(cx, cy, h + 30);
        chimney = _iso(x0 + 0.5, y0 + 0.4, h + 10);
        break;
      case 'chinese':
        // một tầng, mái cong vút màu cam lớn, cột đỏ, vách song cửa sáng đèn, hàng đèn lồng
        const h = 26.0;
        _box(c, x0 - 0.3, y0 - 0.3, x1 + 0.3, y1 + 0.55, 4, g(const Color(0xFFEDEAE4)), g(const Color(0xFFC9C3B8)), g(const Color(0xFFD6D0C5)));
        _walls(c, x0, y0, x1, y1, h, g(const Color(0xFFE98A2E)), z: 4);
        final lat = Paint()
          ..color = g(const Color(0xFF8A2A12))
          ..strokeWidth = 1.2;
        void lattice(bool left, double a, double b) {
          c.drawPath(left ? _onL(y1, a, b, 8, h) : _onR(x1, a, b, 8, h), Paint()..color = night ? const Color(0xFFFFC14D) : g(const Color(0xFFF6B04F)));
          for (var k = 1; k < 6; k++) {
            final m = a + (b - a) * k / 6;
            c.drawLine(left ? _iso(m, y1, 8) : _iso(x1, m, 8), left ? _iso(m, y1, h) : _iso(x1, m, h), lat);
          }
          for (var z = 11.0; z < h; z += 3.5) {
            c.drawLine(left ? _iso(a, y1, z) : _iso(x1, a, z), left ? _iso(b, y1, z) : _iso(x1, b, z), lat);
          }
        }
        lattice(true, x0 + 0.25, cx - 0.5);
        lattice(true, cx + 0.5, x1 - 0.25);
        lattice(false, y0 + 0.3, y1 - 0.3);
        c.drawPath(_onL(y1, cx - 0.38, cx + 0.38, 4, h + 2), Paint()..color = g(const Color(0xFFB23A1E)));
        c.drawLine(_iso(cx, y1, 4), _iso(cx, y1, h + 2), lat);
        final col = Paint()
          ..color = g(const Color(0xFFC0392B))
          ..strokeWidth = 4;
        for (final gx in [x0, cx - 0.45, cx + 0.45, x1]) {
          c.drawLine(_iso(gx, y1, 4), _iso(gx, y1, h + 4), col);
        }
        c.drawLine(_iso(x1, cy, 4), _iso(x1, cy, h + 4), col);
        _hip(c, x0, y0, x1, y1, h + 4, 24, g(const Color(0xFFE8622A)), over: 0.6, ridge: 0.15, curve: 11);
        // hàng đèn lồng đỏ dưới mái
        for (final gx in [x0 + 0.3, x0 + 0.7, x0 + 1.1, x1 - 1.1, x1 - 0.7, x1 - 0.3]) {
          final top = _iso(gx, y1 + 0.3, h + 4);
          c.drawLine(top, top + const Offset(0, 5), Paint()..color = const Color(0xFF3E2723));
          c.drawOval(Rect.fromCenter(center: top + const Offset(0, 10), width: 7, height: 9), Paint()..color = g(const Color(0xFFE53935)));
          if (night) c.drawOval(Rect.fromCenter(center: top + const Offset(0, 10), width: 3.5, height: 5), Paint()..color = const Color(0xFFFFE082));
        }
        _txt(c, owned ? v.emoji : '🔒', _iso(cx, y1, h + 6), 9, Colors.white);
        roofTop = _iso(cx, cy, h + 42);
        chimney = _iso(x0 + 0.5, y0 + 0.4, h + 26);
        break;
      case 'mexican':
        // nhà đất nung kiểu Mexico: mái bằng, cửa vòm, mái ngói đỏ trên hiên, xương rồng
        const h = 28.0;
        _walls(c, x0, y0, x1, y1, h, g(const Color(0xFFF4C99B)));
        _windows(c, x0, y0, x1, y1, 9, 20, g(const Color(0xFF1E8A8A)), night);
        _door(c, x0, x1, y1, h, g(const Color(0xFF1E8A8A)), g(lk0.awning), owned ? v.emoji : '🔒', arch: true);
        c.drawPath(_area(x0, y0, x1, y1, h), Paint()..color = g(const Color(0xFFE8B98A)));
        c.drawPath(_pg([_iso(x0, y1, h), _iso(x1, y1, h), _iso(x1, y1, h + 4), _iso(x0, y1, h + 4)]), Paint()..color = g(const Color(0xFFD9A273)));
        c.drawPath(_pg([_iso(x1, y1, h), _iso(x1, y0, h), _iso(x1, y0, h + 4), _iso(x1, y1, h + 4)]), Paint()..color = g(const Color(0xFFE2AE80)));
        // mái ngói đỏ trên hiên trước
        c.drawPath(_pg([_iso(x0 - 0.1, y1, h * 0.72), _iso(x1 + 0.1, y1, h * 0.72), _iso(x1 + 0.1, y1 + 0.45, h * 0.55), _iso(x0 - 0.1, y1 + 0.45, h * 0.55)]), Paint()..color = g(const Color(0xFFBF5B2C)));
        for (final gx in [x0 - 0.15, x1 + 0.25]) {
          final p = _iso(gx, y1 + 0.5);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p - const Offset(0, 9), width: 6, height: 18), const Radius.circular(3)), Paint()..color = g(const Color(0xFF43A047)));
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: p - const Offset(-5, 11), width: 4, height: 8), const Radius.circular(2)), Paint()..color = g(const Color(0xFF43A047)));
        }
        roofTop = _iso(cx, cy, h + 14);
        chimney = _iso(x0 + 0.5, y0 + 0.4, h + 4);
        break;
      case 'poseidon':
        // nhà hải sản xanh trắng, cửa sổ tròn, cua lớn trên nóc, ngọn hải đăng
        const h = 32.0;
        final lt = _iso(x0 + 0.35, y0 + 0.35);
        for (var k = 0; k < 6; k++) {
          c.drawRect(Rect.fromLTWH(lt.dx - 6, lt.dy - 10 - k * 10, 12, 10), Paint()..color = g(k.isEven ? Colors.white : const Color(0xFFE53935)));
        }
        c.drawRect(Rect.fromLTWH(lt.dx - 7, lt.dy - 72, 14, 9), Paint()..color = night ? const Color(0xFFFFF59D) : g(const Color(0xFFB3E5FC)));
        c.drawPath(_pg([lt - const Offset(9, 72), lt - const Offset(-9, 72), lt - const Offset(0, 82)]), Paint()..color = g(const Color(0xFF0D47A1)));
        _walls(c, x0, y0, x1, y1, h, g(const Color(0xFFE1F5FE)));
        for (var k = 0; k < 3; k++) {
          final z = 6.0 + k * 9;
          c.drawPath(_pg([_iso(x0, y1, z), _iso(x1, y1, z), _iso(x1, y1, z + 3), _iso(x0, y1, z + 3)]), Paint()..color = g(const Color(0x330D47A1)));
        }
        _windows(c, x0, y0, x1, y1, 12, 24, g(const Color(0xFF0D47A1)), night, round: true);
        _door(c, x0, x1, y1, h, g(const Color(0xFF0D47A1)), g(const Color(0xFF00ACC1)), owned ? v.emoji : '🔒');
        c.drawPath(_area(x0, y0, x1, y1, h), Paint()..color = g(const Color(0xFF0D47A1)));
        c.drawPath(_area(x0 + 0.15, y0 + 0.15, x1 - 0.15, y1 - 0.15, h), Paint()..color = g(const Color(0xFF1565C0)));
        final crab = TextPainter(text: TextSpan(text: owned ? '🦀' : '🔒', style: const TextStyle(fontSize: 22)), textDirection: TextDirection.ltr)..layout();
        crab.paint(c, _iso(cx, cy, h + 4) - Offset(crab.width / 2, crab.height * 0.8));
        roofTop = _iso(cx, cy, h + 30);
        chimney = _iso(x1 - 0.6, y0 + 0.4, h + 2);
        break;
      case 'goyuhan':
        // nhà Hanok Hàn Quốc: tường trắng khung gỗ, mái ngói xám cong, nền đá
        const h = 24.0;
        _box(c, x0 - 0.15, y0 - 0.15, x1 + 0.15, y1 + 0.15, 6, g(const Color(0xFFBDBDBD)), g(const Color(0xFF8D8D8D)), g(const Color(0xFF9E9E9E)));
        _walls(c, x0, y0, x1, y1, h, g(const Color(0xFFFAF3E8)), z: 6);
        for (var k = 0; k <= 4; k++) {
          final p = _iso(x0 + (x1 - x0) * k / 4, y1, 6);
          c.drawLine(p, p - const Offset(0, h), Paint()
            ..color = g(const Color(0xFF6D4C41))
            ..strokeWidth = 2.5);
        }
        _windows(c, x0, y0, x1, y1, 14, 26, g(const Color(0xFF6D4C41)), night);
        _door(c, x0, x1, y1, h, g(const Color(0xFF5D4037)), g(const Color(0xFF8E1B1B)), owned ? v.emoji : '🔒', z: 6);
        _hip(c, x0, y0, x1, y1, h + 6, 16, g(const Color(0xFF455A64)), over: 0.4, ridge: 0.15, curve: 6);
        roofTop = _iso(cx, cy, h + 32);
        chimney = _iso(x0 + 0.5, y0 + 0.3, h + 22);
        break;
      case 'binhdan':
        // nhà sàn tre, mái lá dốc, chum nước, bếp củi
        const h = 22.0, stilt = 10.0;
        for (final p in [_iso(x0, y1), _iso(x1, y1), _iso(x1, y0), _iso(cx, y1), _iso(x1, cy)]) {
          c.drawLine(p, p - const Offset(0, stilt), Paint()
            ..color = g(const Color(0xFF6D4C1F))
            ..strokeWidth = 3);
        }
        c.drawPath(_area(x0 - 0.1, y0 - 0.1, x1 + 0.1, y1 + 0.1, stilt), Paint()..color = g(const Color(0xFF8D6E3F)));
        _walls(c, x0, y0, x1, y1, h, g(const Color(0xFFD9B77A)), z: stilt);
        for (var k = 1; k < 8; k++) {
          final p = _iso(x0 + (x1 - x0) * k / 8, y1, stilt);
          c.drawLine(p, p - const Offset(0, h), Paint()
            ..color = g(const Color(0x33000000))
            ..strokeWidth = 1);
        }
        _windows(c, x0, y0, x1, y1, stilt + 7, stilt + 16, g(const Color(0xFF6D4C1F)), night);
        _door(c, x0, x1, y1, h, g(const Color(0xFF5D4037)), g(const Color(0xFF558B2F)), owned ? v.emoji : '🔒', z: stilt);
        // cầu thang lên sàn
        c.drawPath(_pg([_iso(cx - 0.25, y1 + 0.6), _iso(cx + 0.25, y1 + 0.6), _iso(cx + 0.25, y1, stilt), _iso(cx - 0.25, y1, stilt)]), Paint()..color = g(const Color(0xFFA1887F)));
        _hip(c, x0, y0, x1, y1, stilt + h, 26, g(const Color(0xFFC9A44E)), over: 0.45, ridge: 0.2);
        final chum = _iso(x1 + 0.35, y0 + 0.4);
        c.drawOval(Rect.fromCenter(center: chum - const Offset(0, 6), width: 12, height: 12), Paint()..color = g(const Color(0xFF795548)));
        roofTop = _iso(cx, cy, stilt + h + 32);
        chimney = _iso(x1 + 0.4, y1 - 0.3, 6);
        break;
      default:
        const h = 28.0;
        _walls(c, x0, y0, x1, y1, h, g(lk0.wall));
        _windows(c, x0, y0, x1, y1, 9, 20, g(lk0.trim), night);
        _door(c, x0, x1, y1, h, g(lk0.trim), g(lk0.awning), owned ? v.emoji : '🔒');
        _gable(c, x0, y0, x1, y1, h, 20, g(lk0.trim), g(lk0.wall));
        roofTop = _iso(cx, cy, h + 26);
    }
    _roofTop[l.key] = roofTop;
    _chimney[l.key] = chimney;
    if (!owned) c.drawPath(_area(l.x0, l.y0, l.x1, l.y1), Paint()..color = const Color(0x22FFFFFF));
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
    // xe bán đồ ăn màu vàng: bảng hiệu nổi trên nóc, cửa bán mở, ghế nhựa xanh
    Color g(Color x) => owned ? x : _grey(x);
    final yel = g(const Color(0xFFF7B500));
    final x0 = l.x0 + 0.5, x1 = l.x1 - 0.5, y0 = l.y0 + 0.9, y1 = l.y1 - 0.9;
    final xb = x1 - 1.0;
    _box(c, x0, y0, xb, y1, 30, _lt(yel, 0.1), _dk(yel, 0.12), _dk(yel, 0.04));
    // cửa bán sáng đèn
    c.drawPath(_quad(_iso(x0 + 0.2, y1, 12), _iso(xb - 0.2, y1, 12), _iso(xb - 0.2, y1, 27), _iso(x0 + 0.2, y1, 27)), Paint()..color = const Color(0xFFFFF3E0));
    c.drawPath(_quad(_iso(x0 + 0.3, y1, 13), _iso(x0 + 0.9, y1, 13), _iso(x0 + 0.9, y1, 25), _iso(x0 + 0.3, y1, 25)), Paint()..color = const Color(0xFF263238));
    for (var k = 0; k < 8; k++) {
      final p = _iso(x0 + 1.1 + (xb - x0 - 1.4) * k / 7, y1, 20);
      c.drawCircle(p, 2, Paint()..color = const Color(0xFF4E342E));
      c.drawCircle(p, 1.2, Paint()..color = owned ? const Color(0xFFFFE082) : const Color(0xFFBDBDBD));
    }
    c.drawPath(_quad(_iso(x0 + 0.2, y1, 12), _iso(xb - 0.2, y1, 12), _iso(xb - 0.2, y1 + 0.15, 12), _iso(x0 + 0.2, y1 + 0.15, 12)), Paint()..color = _dk(yel, 0.2));
    // bảng hiệu nổi trên nóc
    final s0 = _iso(x0, y1 + 0.05, 31), s1 = _iso(xb, y1 + 0.05, 31);
    c.drawPath(_quad(s0, s1, s1 - const Offset(0, 14), s0 - const Offset(0, 14)), Paint()..color = yel);
    c.drawPath(_quad(s1, _iso(xb, y0 + 0.3, 31), _iso(xb, y0 + 0.3, 45), s1 - const Offset(0, 14)), Paint()..color = _dk(yel, 0.1));
    c.drawPath(_quad(s0 - const Offset(0, 14), s1 - const Offset(0, 14), _iso(xb, y0 + 0.3, 45), _iso(x0, y0 + 0.3, 45)), Paint()..color = _lt(yel, 0.15));
    _txt(c, owned ? 'Food & Drink' : '🔒', Offset.lerp(s0, s1, 0.5)! - const Offset(0, 7), 7.5, const Color(0xFF212121));
    // cabin
    _box(c, xb, y0 + 0.1, x1, y1 - 0.05, 21, _lt(yel, 0.1), _dk(yel, 0.12), _dk(yel, 0.04));
    final glass = Paint()..color = const Color(0xFFB3E5FC);
    c.drawPath(_quad(_iso(x1, y0 + 0.3, 11), _iso(x1, y1 - 0.25, 11), _iso(x1, y1 - 0.25, 19), _iso(x1, y0 + 0.3, 19)), glass);
    c.drawPath(_quad(_iso(xb + 0.15, y1 - 0.05, 11), _iso(x1 - 0.2, y1 - 0.05, 11), _iso(x1 - 0.2, y1 - 0.05, 19), _iso(xb + 0.15, y1 - 0.05, 19)), glass);
    // bánh xe
    for (final gx in [x0 + 0.5, x1 - 0.45]) {
      final w = _iso(gx, y1);
      c.drawOval(Rect.fromCenter(center: w, width: 12, height: 10), Paint()..color = const Color(0xFF263238));
      c.drawOval(Rect.fromCenter(center: w, width: 5, height: 4), Paint()..color = yel);
    }
    // ghế nhựa xanh + giỏ
    const gr = Color(0xFF7BC67E);
    for (final o in [Offset(x0 + 0.3, y1 + 0.55), Offset(xb - 0.5, y1 + 0.6)]) {
      _box(c, o.dx, o.dy, o.dx + 0.25, o.dy + 0.25, 7, g(gr), g(_dk(gr, 0.2)), g(_dk(gr, 0.1)));
    }
    _box(c, x1 + 0.1, y1 + 0.15, x1 + 0.4, y1 + 0.45, 10, g(const Color(0xFF8BD06A)), g(const Color(0xFF5FA046)), g(const Color(0xFF6FB255)));
  }

  void _txt(Canvas c, String s, Offset p, double size, Color col) {
    final tp = TextPainter(text: TextSpan(text: s, style: TextStyle(fontSize: size, color: col, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
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
      final top = _roofTop[l.key] ?? _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2, 70);
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
          final p = (_chimney[l.key] ?? top) - Offset(-sin(ph * 6) * 4, ph * 22);
          c.drawCircle(p, 3 + 5 * ph, Paint()..color = Color.fromRGBO(255, 255, 255, 0.6 * (1 - ph)));
        }
      }
      final name = sig != null ? '${v.emoji} ${v.name.split(' – ').first}' : (owned ? '${v.emoji} ${v.name}' : '🔒 ${v.name}');
      final bg = sig != null ? (sig.mine ? const Color(0xFFFF6A47) : const Color(0xFF4C8DFF)) : (owned ? Colors.white : const Color(0xFFEEEEEE));
      final fg = sig != null ? Colors.white : (owned ? const Color(0xFF221B3F) : const Color(0xFF6E6E80));
      final lp = vid == 'truck' ? _iso((l.x0 + l.x1) / 2, (l.y0 + l.y1) / 2, 60) : top - const Offset(0, 4);
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
