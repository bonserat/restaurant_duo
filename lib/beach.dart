// Bãi biển: một bản đồ riêng, cách chơi khác hẳn. Đào cát, đắp cát, xây tường thành
// và tháp lâu đài, đào kênh dẫn nước biển vào để cá bơi vào hồ rồi khép tường lại
// để nuôi cá. Thuỷ triều lên xuống, sóng có thể đánh sập tường xây sát mép nước.
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';
import 'sound.dart';
import 'ui.dart';

const _W = 14, _H = 14;
const _goals = [
  ('dig', '⛏️', 'Đào một con kênh dẫn nước vào bờ', 50),
  ('fishin', '🐟', 'Cho cá nhỏ bơi vào kênh', 100),
  ('tower', '🏰', 'Xây 3 tháp lâu đài', 80),
  ('wall', '🧱', 'Xây 12 đoạn tường thành', 80),
  ('pool', '🐠', 'Nuôi 3 con cá trong hồ lâu đài (khép kín)', 200),
  ('deco', '🐚', 'Trang trí 5 vỏ sò, cây cỏ, cờ', 50),
];

class _Fish {
  double x, y; // toạ độ ô (tâm ô = .5)
  int tx, ty;
  final String e;
  double stuck = 0;
  bool left = false;
  _Fish(this.x, this.y, this.e) : tx = x.floor(), ty = y.floor();
}

class BeachGame extends StatefulWidget {
  final Map<String, dynamic>? saved;
  final void Function(Map<String, dynamic>) onSave;
  final void Function(int) onEarn;
  const BeachGame({super.key, this.saved, required this.onSave, required this.onEarn});
  @override
  State<BeachGame> createState() => _BeachGameState();
}

class _BeachGameState extends State<BeachGame> {
  final rnd = Random();
  late List<List<int>> h; // độ cao cát, -3..4
  late List<List<String>> st; // '', wall, tower, rock, shell, plant, flag
  Set<int> wet = {}, sea = {};
  final List<_Fish> fish = [];
  int sand = 20;
  Map<String, bool> done = {};
  int fedAt = 0;
  double t = 0, spawnT = 2;
  String tool = 'dig';
  Timer? _timer;
  String? msg;
  double msgT = 0;
  int? lastCell;
  Size _sz = Size.zero;

  int shoreY(int x) => 9 + (sin(x * 0.6) * 0.9).round();
  double get tide => 0.55 * sin(2 * pi * t / 90); // mực nước dao động quanh 0

  @override
  void initState() {
    super.initState();
    final s = widget.saved;
    if (s != null && s['h'] is List) {
      h = [for (final r in s['h'] as List) [for (final v in r as List) (v as num).toInt()]];
      st = [for (final r in s['st'] as List) [for (final v in r as List) v.toString()]];
      sand = (s['sand'] as num?)?.toInt() ?? 20;
      done = Map<String, bool>.from((s['done'] as Map?) ?? {});
      fedAt = (s['fed'] as num?)?.toInt() ?? 0;
      wet = Set<int>.from(((s['wet'] as List?) ?? const []).map((e) => (e as num).toInt()));
      for (final f in (s['fish'] as List?) ?? const []) {
        final l = f as List;
        fish.add(_Fish((l[0] as num).toDouble(), (l[1] as num).toDouble(), l[2].toString()));
      }
    } else {
      h = List.generate(_H, (_) => List.filled(_W, 1));
      st = List.generate(_H, (_) => List.filled(_W, ''));
      for (var y = 0; y < _H; y++) {
        for (var x = 0; x < _W; x++) {
          final sy = shoreY(x);
          h[y][x] = y < sy - 1 ? (y <= 2 && (x + y) % 3 != 0 ? 2 : 1) : (y == sy - 1 ? 0 : max(-3, sy - 1 - y));
        }
      }
      for (final (x, y) in [(12, 2), (13, 3), (12, 4), (13, 5), (13, 1), (11, 1)]) {
        st[y][x] = 'rock';
        h[y][x] = 2;
      }
      for (final (x, y) in [(1, 1), (3, 0), (6, 1), (8, 0), (0, 4)]) {
        st[y][x] = 'plant';
      }
    }
    _flood();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick(0.05));
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.onSave(_toJson());
    super.dispose();
  }

  Map<String, dynamic> _toJson() => {
        'h': h,
        'st': st,
        'sand': sand,
        'done': done,
        'fed': fedAt,
        'wet': wet.toList(),
        'fish': [for (final f in fish) [double.parse(f.x.toStringAsFixed(2)), double.parse(f.y.toStringAsFixed(2)), f.e]],
      };

  bool _blocks(String s) => s == 'wall' || s == 'tower' || s == 'rock';

  /// Nước biển tràn vào mọi ô thấp hơn mực triều nối với biển; hồ đã có nước mà bị khép lại vẫn giữ nước
  void _flood() {
    final lv = tide;
    final seen = <int>{};
    final q = Queue<int>();
    for (var x = 0; x < _W; x++) {
      final i = (_H - 1) * _W + x;
      q.add(i);
      seen.add(i);
    }
    while (q.isNotEmpty) {
      final i = q.removeFirst();
      final x = i % _W, y = i ~/ _W;
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= _W || ny >= _H) continue;
        final j = ny * _W + nx;
        if (seen.contains(j) || _blocks(st[ny][nx]) || h[ny][nx] >= lv) continue;
        seen.add(j);
        q.add(j);
      }
    }
    sea = seen;
    wet = {...seen, for (final i in wet) if (h[i ~/ _W][i % _W] < 0 && !_blocks(st[i ~/ _W][i % _W])) i};
  }

  bool _inland(int i) => i ~/ _W <= shoreY(i % _W) - 2;
  bool _pool(int i) => wet.contains(i) && !sea.contains(i);

  void _say(String s) {
    msg = s;
    msgT = 2.5;
  }

  void _tick(double dt) {
    if (!mounted) return;
    t += dt;
    if (msgT > 0) msgT -= dt;
    if ((t * 20).round() % 5 == 0) _flood();
    // sóng đánh sập tường/tháp xây thấp sát mép nước khi triều lên
    if (tide > 0.35 && rnd.nextDouble() < dt * 0.15) {
      for (var y = 0; y < _H; y++) {
        for (var x = 0; x < _W; x++) {
          if ((st[y][x] == 'wall' || st[y][x] == 'tower') && h[y][x] <= 0 && _nearSea(x, y)) {
            st[y][x] = '';
            _say('🌊 Sóng lớn đánh sập ${'công trình'} sát mép nước! Xây trên cát cao hơn nhé');
            Sound.sfx('angry', vol: 0.5);
            _flood();
            y = _H;
            break;
          }
        }
      }
    }
    // cá biển xuất hiện
    spawnT -= dt;
    if (spawnT <= 0) {
      spawnT = 5 + rnd.nextDouble() * 5;
      final inSea = fish.where((f) => f.y >= _H - 3).length;
      if (inSea < 4) {
        const kinds = ['🐟', '🐠', '🐡', '🦀', '🐠'];
        fish.add(_Fish(rnd.nextInt(_W) + 0.5, _H - 0.5, kinds[rnd.nextInt(kinds.length)]));
      }
    }
    // cá bơi trong vùng nước nối liền
    for (final f in fish.toList()) {
      final ci = f.y.floor().clamp(0, _H - 1) * _W + f.x.floor().clamp(0, _W - 1);
      if (!wet.contains(ci)) {
        f.stuck += dt;
        if (f.stuck > 3) {
          fish.remove(f);
          _say('🐟 Một con cá bị mắc cạn, nhớ giữ nước cho hồ!');
        }
        continue;
      }
      f.stuck = 0;
      final tx = f.tx + 0.5, ty = f.ty + 0.5;
      final dx = tx - f.x, dy = ty - f.y;
      final d = sqrt(dx * dx + dy * dy);
      if (d < 0.05 || !wet.contains(f.ty * _W + f.tx)) {
        final opts = <(int, int)>[];
        for (final (ox, oy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = f.tx + ox, ny = f.ty + oy;
          if (nx >= 0 && ny >= 0 && nx < _W && ny < _H && wet.contains(ny * _W + nx)) opts.add((nx, ny));
        }
        if (!wet.contains(f.ty * _W + f.tx)) {
          f.tx = f.x.floor().clamp(0, _W - 1);
          f.ty = f.y.floor().clamp(0, _H - 1);
        } else if (opts.isNotEmpty && rnd.nextDouble() < 0.7) {
          // cá tò mò: ưu tiên bơi về phía bờ (vào kênh)
          opts.sort((a, b) => a.$2.compareTo(b.$2));
          final pick = rnd.nextDouble() < 0.45 ? opts.first : opts[rnd.nextInt(opts.length)];
          f.tx = pick.$1;
          f.ty = pick.$2;
        }
      } else {
        final sp = 0.9 * dt;
        f.x += dx / d * min(sp, d);
        f.y += dy / d * min(sp, d);
        if (dx.abs() > 0.01) f.left = dx < 0;
      }
    }
    _checkGoals();
    if ((t * 20).round() % 300 == 0) widget.onSave(_toJson()); // tự lưu mỗi 15 giây
    setState(() {});
  }

  bool _nearSea(int x, int y) {
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx, ny = y + dy;
      if (nx >= 0 && ny >= 0 && nx < _W && ny < _H && sea.contains(ny * _W + nx)) return true;
    }
    return false;
  }

  int _count(String s) => st.fold<int>(0, (a, r) => a + r.where((v) => v == s).length);
  int get poolFish => fish.where((f) => _pool(f.y.floor().clamp(0, _H - 1) * _W + f.x.floor().clamp(0, _W - 1))).length;

  void _checkGoals() {
    bool ok(String id) {
      switch (id) {
        case 'dig':
          return wet.any(_inland);
        case 'fishin':
          return fish.any((f) => _inland(f.y.floor().clamp(0, _H - 1) * _W + f.x.floor().clamp(0, _W - 1)));
        case 'tower':
          return _count('tower') >= 3;
        case 'wall':
          return _count('wall') >= 12;
        case 'pool':
          return poolFish >= 3;
        case 'deco':
          return _count('shell') + _count('plant') + _count('flag') >= 5;
      }
      return false;
    }

    for (final g in _goals) {
      if (done[g.$1] != true && ok(g.$1)) {
        done[g.$1] = true;
        widget.onEarn(g.$4);
        _say('🎉 ${g.$3}! +${g.$4}💰');
        Sound.sfx('goal');
      }
    }
  }

  // ------------------------------------------------------------------ thao tác
  void _apply(int x, int y) {
    final s = st[y][x];
    switch (tool) {
      case 'dig':
        if (s == 'rock') return _say('🪨 Đá to quá, không đào được');
        if (s.isNotEmpty) return _say('Dọn công trình trước khi đào');
        if (h[y][x] <= -3) return;
        h[y][x]--;
        sand++;
        Sound.sfx('tap', vol: 0.4);
        break;
      case 'pile':
        if (s == 'rock' || h[y][x] >= 4) return;
        if (sand < 1) return _say('Hết cát! Đào thêm để lấy cát');
        if (wet.contains(y * _W + x) && h[y][x] < -1) return _say('Nước sâu quá, đắp chỗ cạn trước');
        h[y][x]++;
        sand--;
        Sound.sfx('tap', vol: 0.4);
        break;
      case 'wall':
      case 'tower':
        final cost = tool == 'wall' ? 2 : 4;
        if (s.isNotEmpty) return;
        if (sea.contains(y * _W + x) && h[y][x] < -1) return _say('Không xây giữa biển sâu được');
        if (sand < cost) return _say('Cần $cost cát. Đào thêm nhé');
        sand -= cost;
        st[y][x] = tool;
        if (tool == 'tower') Sound.sfx('coin', vol: 0.5);
        break;
      case 'shell':
      case 'plant':
      case 'flag':
        if (s.isNotEmpty || wet.contains(y * _W + x)) return;
        st[y][x] = tool;
        break;
      case 'clear':
        if (s.isEmpty || s == 'rock') return;
        if (s == 'wall') sand += 1;
        if (s == 'tower') sand += 2;
        st[y][x] = '';
        break;
      case 'fish':
        // thả cá con mua ở chợ vào hồ
        if (!wet.contains(y * _W + x)) return _say('Thả cá vào chỗ có nước nhé');
        fish.add(_Fish(x + 0.5, y + 0.5, ['🐠', '🐟', '🐡'][rnd.nextInt(3)]));
        Sound.sfx('coin', vol: 0.4);
        break;
    }
    _flood();
  }

  int? _cellAt(Offset p) {
    final g = _geo(_sz);
    for (var s = _W + _H - 2; s >= 0; s--) {
      for (var x = min(_W - 1, s); x >= 0 && s - x < _H; x--) {
        final y = s - x;
        final z = h[y][x] * g.hz + (_blocks(st[y][x]) && st[y][x] != 'rock' ? 0 : 0);
        final path = Path()
          ..moveTo(g.iso(x.toDouble(), y.toDouble(), z).dx, g.iso(x.toDouble(), y.toDouble(), z).dy)
          ..lineTo(g.iso(x + 1.0, y.toDouble(), z).dx, g.iso(x + 1.0, y.toDouble(), z).dy)
          ..lineTo(g.iso(x + 1.0, y + 1.0, z).dx, g.iso(x + 1.0, y + 1.0, z).dy)
          ..lineTo(g.iso(x.toDouble(), y + 1.0, z).dx, g.iso(x.toDouble(), y + 1.0, z).dy)
          ..close();
        if (path.contains(p)) return y * _W + x;
      }
    }
    return null;
  }

  void _touch(Offset p, {bool drag = false}) {
    final i = _cellAt(p);
    if (i == null || (drag && i == lastCell)) return;
    lastCell = i;
    setState(() => _apply(i % _W, i ~/ _W));
  }

  _Geo _geo(Size sz) {
    final tw = min(sz.width / (_W + _H) * 2 * 0.96, sz.height / (_W + _H + 6) * 2 * 2 * 0.96);
    final th = tw / 2;
    final hz = th * 0.45;
    return _Geo(tw, th, hz, sz.width / 2 + (_H - _W) * tw / 4, (sz.height - (_W + _H) * th / 2) / 2 + 3 * hz);
  }

  void _feed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = poolFish;
    if (n == 0) return _say('Chưa có cá trong hồ lâu đài (hồ khép kín, không nối biển)');
    if (now - fedAt < 4 * 3600000) {
      final m = ((4 * 3600000 - (now - fedAt)) / 60000).ceil();
      return _say('Cá còn no, $m phút nữa cho ăn tiếp');
    }
    fedAt = now;
    final m = 15 * n;
    widget.onEarn(m);
    _say('🍞 Cho $n con cá ăn, khách du lịch ngắm cá bo $m💰');
    Sound.sfx('coin');
  }

  @override
  Widget build(BuildContext context) {
    const tools = [
      ('dig', '⛏️', 'Đào'),
      ('pile', '🪣', 'Đắp cát'),
      ('wall', '🧱', 'Tường (2)'),
      ('tower', '🏰', 'Tháp (4)'),
      ('flag', '🚩', 'Cờ'),
      ('shell', '🐚', 'Vỏ sò'),
      ('plant', '🌿', 'Cây cỏ'),
      ('fish', '🐠', 'Thả cá'),
      ('clear', '🧹', 'Dọn'),
    ];
    final up = tide > 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF3E9D2),
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0277BD), Color(0xFF26C6DA)])),
            child: Row(children: [
              const Text('🏖️ Bãi biển', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(width: 8),
              StatPill('🏝️', '$sand cát'),
              const SizedBox(width: 4),
              StatPill(up ? '🌊' : '🏝️', up ? 'Triều lên' : 'Triều xuống'),
              const SizedBox(width: 4),
              StatPill('🐠', '$poolFish'),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (ctx, c) {
              _sz = Size(c.maxWidth, c.maxHeight);
              return Stack(children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTapDown: (d) => _touch(d.localPosition),
                    onPanStart: (d) => _touch(d.localPosition),
                    onPanUpdate: (d) => _touch(d.localPosition, drag: true),
                    onPanEnd: (_) => lastCell = null,
                    child: CustomPaint(painter: _BeachPainter(this)),
                  ),
                ),
                // bảng mục tiêu
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 190,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(225), borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      for (final g in _goals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text('${done[g.$1] == true ? '✅' : g.$2} ${g.$3}',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: done[g.$1] == true ? Pal.muted : Pal.text, decoration: done[g.$1] == true ? TextDecoration.lineThrough : null)),
                        ),
                    ]),
                  ),
                ),
                if (msg != null && msgT > 0)
                  Align(
                    alignment: const Alignment(0, 0.9),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)]),
                      child: Text(msg!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
                    ),
                  ),
              ]);
            }),
          ),
          Container(
            height: 70,
            color: Pal.surface,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), children: [
              for (final tl in tools)
                GestureDetector(
                  onTap: () => setState(() => tool = tl.$1),
                  child: Container(
                    width: 64,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: tool == tl.$1 ? const Color(0xFFFFE0B2) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tool == tl.$1 ? const Color(0xFFE53935) : Pal.line, width: 2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(tl.$2, style: const TextStyle(fontSize: 24)),
                      Text(tl.$3, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Pal.text)),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
            child: Row(children: [
              Expanded(child: SoftButton('Cho cá ăn', emoji: '🍞', onTap: _feed)),
              const SizedBox(width: 8),
              Expanded(
                child: SoftButton('Hướng dẫn', emoji: '❓', onTap: () => _say('Đào kênh từ biển vào bờ ⛏️ → cá bơi vào → xây tường 🧱 chặn lối ra để giữ cá trong hồ. Xây trên cát cao kẻo sóng đánh sập!')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Geo {
  final double tw, th, hz, ox, oy;
  _Geo(this.tw, this.th, this.hz, this.ox, this.oy);
  Offset iso(double gx, double gy, double z) => Offset(ox + (gx - gy) * tw / 2, oy + (gx + gy) * th / 2 - z);
}

class _BeachPainter extends CustomPainter {
  final _BeachGameState s;
  _BeachPainter(this.s);

  Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  void _emoji(Canvas c, String e, Offset p, double size) {
    final tp = TextPainter(text: TextSpan(text: e, style: TextStyle(fontSize: size)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height * 0.8));
  }

  Color _sandCol(int h, bool wet) {
    if (wet) return const Color(0xFFC9A26B);
    if (h >= 3) return const Color(0xFFF7E6BF);
    if (h == 2) return const Color(0xFFF1DBA9);
    if (h == 1) return const Color(0xFFEAD096);
    if (h == 0) return const Color(0xFFE0C287);
    return const Color(0xFFD2AE74);
  }

  void _box(Canvas c, _Geo g, double x0, double y0, double x1, double y1, double z0, double z1, Color top) {
    final l0 = g.iso(x0, y1, z0), b0 = g.iso(x1, y1, z0), r0 = g.iso(x1, y0, z0);
    final l1 = g.iso(x0, y1, z1), b1 = g.iso(x1, y1, z1), r1 = g.iso(x1, y0, z1), t1 = g.iso(x0, y0, z1);
    c.drawPath(_quad(l0, b0, b1, l1), Paint()..color = Color.lerp(top, Colors.black, 0.18)!);
    c.drawPath(_quad(b0, r0, r1, b1), Paint()..color = Color.lerp(top, Colors.black, 0.08)!);
    c.drawPath(_quad(t1, r1, b1, l1), Paint()..color = top);
  }

  @override
  void paint(Canvas c, Size sz) {
    final g = s._geo(sz);
    final t = s.t;
    final lv = s.tide;
    // nền: biển xa phía dưới
    c.drawRect(Offset.zero & sz, Paint()..color = const Color(0xFFF3E9D2));
    for (var sum = 0; sum <= _W + _H - 2; sum++) {
      for (var x = max(0, sum - _H + 1); x <= min(_W - 1, sum); x++) {
        final y = sum - x;
        final hh = s.h[y][x];
        final i = y * _W + x;
        final isWet = s.wet.contains(i);
        final z = hh * g.hz;
        final bottom = -4 * g.hz;
        // mặt bên
        final zl = y + 1 < _H ? s.h[y + 1][x] * g.hz : bottom;
        final zr = x + 1 < _W ? s.h[y][x + 1] * g.hz : bottom;
        if (zl < z) c.drawPath(_quad(g.iso(x.toDouble(), y + 1.0, z), g.iso(x + 1.0, y + 1.0, z), g.iso(x + 1.0, y + 1.0, zl), g.iso(x.toDouble(), y + 1.0, zl)), Paint()..color = const Color(0xFFC79A5E));
        if (zr < z) c.drawPath(_quad(g.iso(x + 1.0, y + 1.0, z), g.iso(x + 1.0, y.toDouble(), z), g.iso(x + 1.0, y.toDouble(), zr), g.iso(x + 1.0, y + 1.0, zr)), Paint()..color = const Color(0xFFD9AE6F));
        // mặt trên
        final top = _quad(g.iso(x.toDouble(), y.toDouble(), z), g.iso(x + 1.0, y.toDouble(), z), g.iso(x + 1.0, y + 1.0, z), g.iso(x.toDouble(), y + 1.0, z));
        c.drawPath(top, Paint()..color = _sandCol(hh, isWet));
        if ((x * 7 + y * 3) % 5 == 0 && !isWet) c.drawCircle(g.iso(x + 0.3, y + 0.6, z), 1.2, Paint()..color = const Color(0x55795548));
        // nước
        if (isWet) {
          final pool = !s.sea.contains(i);
          final wz = (pool ? min(lv, -0.25) : lv) * g.hz;
          final deep = hh <= -2;
          c.drawPath(_quad(g.iso(x.toDouble(), y.toDouble(), wz), g.iso(x + 1.0, y.toDouble(), wz), g.iso(x + 1.0, y + 1.0, wz), g.iso(x.toDouble(), y + 1.0, wz)),
              Paint()..color = deep ? const Color(0xDD1E88C9) : (pool ? const Color(0xCC4FC3F7) : const Color(0xBB29B6F6)));
          // bọt sóng ở mép nước
          for (final (dx, dy, a, b) in const [(0, -1, (0.0, 0.0), (1.0, 0.0)), (-1, 0, (0.0, 0.0), (0.0, 1.0)), (1, 0, (1.0, 0.0), (1.0, 1.0)), (0, 1, (0.0, 1.0), (1.0, 1.0))]) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= _W || ny >= _H) continue;
            if (s.wet.contains(ny * _W + nx)) continue;
            final al = (150 + 100 * sin(t * 3 + x + y)).round().clamp(0, 255);
            c.drawLine(g.iso(x + a.$1, y + a.$2, wz), g.iso(x + b.$1, y + b.$2, wz), Paint()
              ..color = Color.fromARGB(al, 255, 255, 255)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round);
          }
          if ((x + y + (t * 0.6).floor()) % 6 == 0 && !pool) {
            final p = g.iso(x + 0.5, y + 0.5, wz);
            c.drawLine(p - Offset(g.tw * 0.15, 0), p + Offset(g.tw * 0.15, 0), Paint()
              ..color = const Color(0x88FFFFFF)
              ..strokeWidth = 1.4);
          }
        }
        // công trình
        final so = s.st[y][x];
        switch (so) {
          case 'wall':
            _box(c, g, x + 0.08, y + 0.08, x + 0.92, y + 0.92, z, z + g.hz * 1.8, const Color(0xFFEBD3A1));
            for (final (a, b) in const [(0.1, 0.1), (0.62, 0.1), (0.1, 0.62), (0.62, 0.62)]) {
              _box(c, g, x + a, y + b, x + a + 0.28, y + b + 0.28, z + g.hz * 1.8, z + g.hz * 2.4, const Color(0xFFEBD3A1));
            }
            break;
          case 'tower':
            _box(c, g, x + 0.12, y + 0.12, x + 0.88, y + 0.88, z, z + g.hz * 4.2, const Color(0xFFEFD9A9));
            for (final (a, b) in const [(0.12, 0.12), (0.6, 0.12), (0.12, 0.6), (0.6, 0.6)]) {
              _box(c, g, x + a, y + b, x + a + 0.28, y + b + 0.28, z + g.hz * 4.2, z + g.hz * 5.0, const Color(0xFFEFD9A9));
            }
            final pole = g.iso(x + 0.5, y + 0.5, z + g.hz * 5.0);
            c.drawLine(pole, pole - Offset(0, g.hz * 4), Paint()
              ..color = const Color(0xFF6D4C41)
              ..strokeWidth = 1.6);
            const flags = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFFFDD835)];
            final fc = flags[(x * 3 + y) % 3];
            final wave = sin(t * 5 + x) * 2;
            c.drawPath(_quad(pole - Offset(0, g.hz * 4), pole - Offset(-g.tw * 0.28, g.hz * 4 - wave), pole - Offset(-g.tw * 0.28, g.hz * 2.8 - wave), pole - Offset(0, g.hz * 2.8)), Paint()..color = fc);
            break;
          case 'rock':
            final p = g.iso(x + 0.5, y + 0.5, z);
            c.drawOval(Rect.fromCenter(center: p - Offset(0, g.th * 0.5), width: g.tw * 0.9, height: g.th * 1.6), Paint()..color = const Color(0xFF8D6E63));
            c.drawOval(Rect.fromCenter(center: p - Offset(g.tw * 0.1, g.th * 0.75), width: g.tw * 0.5, height: g.th * 0.9), Paint()..color = const Color(0xFFA1887F));
            break;
          case 'shell':
            _emoji(c, '🐚', g.iso(x + 0.5, y + 0.5, z), g.tw * 0.4);
            break;
          case 'plant':
            _emoji(c, '🌿', g.iso(x + 0.5, y + 0.5, z), g.tw * 0.5);
            break;
          case 'flag':
            final p = g.iso(x + 0.5, y + 0.5, z);
            c.drawLine(p, p - Offset(0, g.hz * 5), Paint()
              ..color = const Color(0xFF6D4C41)
              ..strokeWidth = 1.6);
            c.drawPath(_quad(p - Offset(0, g.hz * 5), p - Offset(-g.tw * 0.3, g.hz * 5 - sin(t * 5 + y) * 2), p - Offset(-g.tw * 0.3, g.hz * 3.6), p - Offset(0, g.hz * 3.6)), Paint()..color = const Color(0xFFE53935));
            break;
        }
      }
    }
    // cá
    for (final f in s.fish) {
      final ci = f.y.floor().clamp(0, _H - 1) * _W + f.x.floor().clamp(0, _W - 1);
      final pool = !s.sea.contains(ci);
      final wz = (pool ? min(lv, -0.25) : lv) * g.hz;
      final p = g.iso(f.x, f.y, wz) + Offset(0, sin(t * 4 + f.x) * 1.5);
      c.save();
      c.translate(p.dx, p.dy);
      if (!f.left) c.scale(-1, 1);
      if (f.stuck > 0) c.rotate(sin(t * 20) * 0.6);
      _emoji(c, f.e, Offset.zero, g.tw * 0.42);
      c.restore();
    }
    // xẻng + xô đồ chơi trang trí góc bãi
    _emoji(c, '⛱️', g.iso(1.5, 6.5, s.h[6][1] * g.hz), g.tw * 0.9);
  }

  @override
  bool shouldRepaint(covariant _BeachPainter oldDelegate) => true;
}
