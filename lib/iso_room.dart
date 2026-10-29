// Màn chơi nhìn nghiêng 2.5D: bếp và sảnh chung một căn phòng.
// Mỗi quán có sơ đồ + đồ đạc riêng (bể hải sản, bàn nướng than, chõng tre, tủ bánh…).
part of 'scene.dart';

/// Bố cục riêng của từng quán
class _RoomPlan {
  final String table; // round | square | long | grill | booth | mat
  final List<double> cols; // các cột bàn theo phương ngang (v)
  final String special; // đồ đặc trưng trên tường trái
  final Color kitchenA, kitchenB; // sàn khu bếp
  const _RoomPlan(this.table, this.cols, this.special, this.kitchenA, this.kitchenB);
}

const _plans = {
  'cafe': _RoomPlan('round', [-1.9, 0, 1.9], 'books', Color(0xFFEFEBE9), Color(0xFFD7CCC8)),
  'bakery': _RoomPlan('cloth', [-1.9, 0, 1.9], 'cakes', Color(0xFFFFFFFF), Color(0xFFFCE4EC)),
  'chinese': _RoomPlan('ming', [-1.9, 0, 1.9], 'lanterns', Color(0xFFFFF3E0), Color(0xFFFFE0B2)),
  'mexican': _RoomPlan('iron', [-1.8, 0.3, 2.0], 'cactus', Color(0xFFFFF3E0), Color(0xFFFFCCBC)),
  'truck': _RoomPlan('plastic', [-1.6, 1.6], 'menu', Color(0xFFECEFF1), Color(0xFFCFD8DC)),
  'poseidon': _RoomPlan('booth', [-1.8, 0.2, 2.0], 'tank', Color(0xFFE1F5FE), Color(0xFFB3E5FC)),
  'goyuhan': _RoomPlan('grill', [-1.9, 0, 1.9], 'hanok', Color(0xFFECEFF1), Color(0xFFB0BEC5)),
  'binhdan': _RoomPlan('mat', [-1.9, 0, 1.9], 'bamboo', Color(0xFFF1E3C6), Color(0xFFE0CDA3)),
};

class _IWalker {
  final int seed;
  final String npc;
  final List<Offset> path; // toạ độ lưới
  final double t0, dur;
  final bool happy;
  _IWalker(this.seed, this.npc, this.path, this.t0, this.dur, this.happy);
}

class IsoRoom extends StatefulWidget {
  final List<TableS> tables;
  final List<Station> stations;
  final List<Dish> counter;
  final int? selDishId;
  final int activeStation;
  final bool hasOrders;
  final String venueId, style, light;
  final Look waiterLook, chefLook;
  final String waiterName, chefName;
  final List<Offset?> tablePos;
  final List<Deco> decos;
  final List<String> pets;
  final List<Incident> incidents;
  final List<OutsideGuest> outside;
  final String? tool;
  final double burnTime;
  final bool buffet; // nhà hàng buffet: quầy món tự chọn, 2 đầu bếp
  final List<(String, int)> trays; // món trên quầy buffet và số phần còn lại
  final Look? chef2Look;
  final void Function(int) onTable;
  final void Function(Dish) onDish;
  final void Function(int) onStation;
  final void Function(int, double) onHeat;
  final void Function(int) onIncident;
  final void Function(String) onPet;
  const IsoRoom({
    super.key,
    required this.tables,
    required this.stations,
    required this.counter,
    required this.selDishId,
    required this.activeStation,
    required this.hasOrders,
    required this.venueId,
    required this.onTable,
    required this.onDish,
    required this.onStation,
    required this.onHeat,
    required this.onIncident,
    required this.onPet,
    this.style = 'classic',
    this.light = 'day',
    this.waiterLook = ngocAnhLook,
    this.chefLook = nguyenLook,
    this.waiterName = kNgocAnh,
    this.chefName = kNguyen,
    this.tablePos = const [],
    this.decos = const [],
    this.pets = const [],
    this.incidents = const [],
    this.outside = const [],
    this.tool,
    this.burnTime = 8,
    this.buffet = false,
    this.trays = const [],
    this.chef2Look,
  });
  @override
  State<IsoRoom> createState() => _IsoRoomState();
}

class _IsoRoomState extends State<IsoRoom> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  double get _t => _clock.value;
  Size _size = Size.zero;

  // ---- hình học
  static const double _g = 12; // phòng 12 × 12 ô
  double _tw = 50, _th = 25, _ox = 0, _oy = 0, _wallH = 70;

  Offset _p(double gx, double gy, [double z = 0]) => Offset(_ox + (gx - gy) * _tw / 2, _oy + (gx + gy) * _th / 2 - z);
  Offset _uv(double u, double v) => Offset(u + v, u - v); // (u: sâu, v: ngang) → (gx, gy)
  Offset _pg(Offset g, [double z = 0]) => _p(g.dx, g.dy, z);

  Path _area(double x0, double y0, double x1, double y1, [double z = 0]) {
    final a = _p(x0, y0, z), b = _p(x1, y0, z), c = _p(x1, y1, z), d = _p(x0, y1, z);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
  }

  Path _poly(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  /// Khối hộp nổi: mặt trên ở độ cao h (pixel)
  void _box(Canvas c, double x0, double y0, double x1, double y1, double h, Color top, {double z = 0}) {
    final l = _p(x0, y1, z), b = _p(x1, y1, z), r = _p(x1, y0, z);
    c.drawPath(_poly([l, b, b - Offset(0, h), l - Offset(0, h)]), Paint()..color = _dk(top, 0.22));
    c.drawPath(_poly([b, r, r - Offset(0, h), b - Offset(0, h)]), Paint()..color = _dk(top, 0.1));
    c.drawPath(_area(x0, y0, x1, y1, z + h), Paint()..color = top);
  }

  // ---- bố cục
  _RoomPlan get _plan => _plans[widget.venueId] ?? _plans['cafe']!;

  /// Tâm bếp i (toạ độ lưới)
  Offset _stove(int i) => Offset(1.35 + i * 1.22, 0.62);
  Offset _chefSpot(int i) => Offset(_stove(i).dx, 1.75);

  /// Khoá vẽ: mọi thứ phía trước quầy ra món (gy > 3) vẽ sau quầy
  double _zk(Offset g) => g.dy > 3.0 ? 100 + g.dx + g.dy : g.dx + g.dy;

  /// Ô để món trên quầy ra món
  Offset _slot(int j) => Offset(1.7 + j * 0.72, 2.92);

  Offset _table(int i) {
    final tp = i < widget.tablePos.length ? widget.tablePos[i] : null;
    if (tp != null) {
      final v = ((tp.dx - 0.5) * 6).clamp(-2.6, 2.6).toDouble();
      final u = (4.7 + tp.dy * 6.3).clamp(4.6, 11.0).toDouble();
      return _uv(u, v);
    }
    // 3 hàng đầu đủ cột; phòng hẹp dần về phía cửa nên hàng cuối chỉ đặt bàn ở giữa
    const rows = [5.4, 7.3, 9.2];
    final cols = _plan.cols;
    final per = cols.length;
    if (i < per * rows.length) {
      final row = i ~/ per, col = i % per;
      return _uv(rows[row], cols[col] + (row.isOdd ? 0.3 : 0));
    }
    final k = i - per * rows.length;
    return _uv(10.9, const [0.0, -0.8, 0.8][k % 3]);
  }

  Offset _seat(int i) => _table(i) - const Offset(0.42, 0.42); // ghế phía sau bàn
  /// Chỗ phục vụ đứng cạnh bàn (ô trống gần nhất phía trước bàn)
  Offset _approach(int i) {
    _buildBlock();
    final g = _table(i);
    for (final o in const [Offset(0.75, 0.0), Offset(0.0, 0.75), Offset(0.75, 0.75), Offset(-0.75, 0.0), Offset(0.0, -0.75)]) {
      final c = _cellOf(g + o);
      if (_free(c.$1, c.$2)) return g + o;
    }
    final c = _nearFree(_cellOf(g));
    return _cellCenter(c.$1, c.$2);
  }
  Offset get _door => _uv(_g - 0.2, 0);
  Offset get _waiterHome => const Offset(5.3, 3.75);

  // ---- tìm đường: lưới 0.5 ô, chặn bàn ghế, quầy, bếp, đồ trang trí
  static const double _cell = 0.5;
  static const int _gn = 24; // 12 ô / 0.5
  List<bool> _block = List.filled(_gn * _gn, false);
  String _blockKey = '';

  void _buildBlock() {
    final key = '${widget.tables.length}|${widget.tablePos}|${widget.decos.length}|${widget.venueId}';
    if (key == _blockKey) return;
    _blockKey = key;
    final b = List.filled(_gn * _gn, false);
    void mark(double x0, double y0, double x1, double y1) {
      for (var j = max(0, (y0 / _cell).floor()); j <= min(_gn - 1, (y1 / _cell).floor()); j++) {
        for (var i = max(0, (x0 / _cell).floor()); i <= min(_gn - 1, (x1 / _cell).floor()); i++) {
          b[j * _gn + i] = true;
        }
      }
    }

    // tường: chừa 1 hàng sát tường
    for (var k = 0; k < _gn; k++) {
      b[k] = true;
      b[k * _gn] = true;
    }
    mark(0, 0, 6.5, 1.3); // quầy bếp + bếp
    mark(0, 1.2, 0.95, 4.0); // tủ lạnh, bồn rửa
    mark(1.15, 2.5, 6.3, 3.35); // quầy ra món
    for (var i = 0; i < widget.tables.length; i++) {
      final g = _table(i), sg = _seat(i);
      mark(g.dx - 0.38, g.dy - 0.38, g.dx + 0.34, g.dy + 0.34);
      mark(sg.dx - 0.22, sg.dy - 0.22, sg.dx + 0.18, sg.dy + 0.18);
      if (_plan.table == 'round' || _plan.table == 'cloth' || _plan.table == 'iron' || _plan.table == 'ming' || _plan.table == 'plastic') mark(g.dx + 0.24, g.dy + 0.24, g.dx + 0.6, g.dy + 0.6);
    }
    for (final d in widget.decos) {
      if (decoById(d.type).wall) continue;
      final g = _uv(4.4 + d.y * 6.6, (d.x - 0.5) * 6.4);
      mark(g.dx - 0.3, g.dy - 0.3, g.dx + 0.3, g.dy + 0.3);
    }
    _block = b;
  }

  bool _free(int i, int j) => i >= 0 && j >= 0 && i < _gn && j < _gn && !_block[j * _gn + i];

  (int, int) _cellOf(Offset g) => (min(max((g.dx / _cell).floor(), 0), _gn - 1), min(max((g.dy / _cell).floor(), 0), _gn - 1));
  Offset _cellCenter(int i, int j) => Offset((i + 0.5) * _cell, (j + 0.5) * _cell);

  /// Ô trống gần nhất
  (int, int) _nearFree((int, int) c) {
    if (_free(c.$1, c.$2)) return c;
    for (var r = 1; r < 8; r++) {
      for (var dj = -r; dj <= r; dj++) {
        for (var di = -r; di <= r; di++) {
          if (di.abs() != r && dj.abs() != r) continue;
          if (_free(c.$1 + di, c.$2 + dj)) return (c.$1 + di, c.$2 + dj);
        }
      }
    }
    return c;
  }

  /// A* trên lưới, trả về danh sách điểm (toạ độ ô lưới phòng), đã làm mượt
  List<Offset> _route(Offset from, Offset to) {
    _buildBlock();
    final s0 = _nearFree(_cellOf(from)), s1 = _nearFree(_cellOf(to));
    final n = _gn * _gn;
    final gScore = List.filled(n, 1e9), came = List.filled(n, -1);
    final open = <int>{s0.$2 * _gn + s0.$1};
    gScore[s0.$2 * _gn + s0.$1] = 0;
    double hh(int k) => ((k % _gn) - s1.$1).abs() + ((k ~/ _gn) - s1.$2).abs() * 1.0;
    final goal = s1.$2 * _gn + s1.$1;
    var guard = 0;
    while (open.isNotEmpty && guard++ < 4000) {
      var cur = open.first;
      var best = gScore[cur] + hh(cur);
      for (final k in open) {
        final f = gScore[k] + hh(k);
        if (f < best) {
          best = f;
          cur = k;
        }
      }
      if (cur == goal) break;
      open.remove(cur);
      final ci = cur % _gn, cj = cur ~/ _gn;
      for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
          if (di == 0 && dj == 0) continue;
          final ni = ci + di, nj = cj + dj;
          if (!_free(ni, nj)) continue;
          if (di != 0 && dj != 0 && (!_free(ci + di, cj) || !_free(ci, cj + dj))) continue; // không cắt góc
          final nk = nj * _gn + ni;
          final ng = gScore[cur] + (di != 0 && dj != 0 ? 1.414 : 1.0);
          if (ng < gScore[nk]) {
            gScore[nk] = ng;
            came[nk] = cur;
            open.add(nk);
          }
        }
      }
    }
    if (came[goal] < 0 && goal != s0.$2 * _gn + s0.$1) return [to];
    final cells = <int>[];
    for (var k = goal; k >= 0 && k != s0.$2 * _gn + s0.$1; k = came[k]) {
      cells.add(k);
    }
    final pts = [for (final k in cells.reversed) _cellCenter(k % _gn, k ~/ _gn)];
    // làm mượt: bỏ điểm giữa nếu đi thẳng được
    final out = <Offset>[];
    var a = from;
    var i = 0;
    while (i < pts.length) {
      var j = pts.length - 1;
      while (j > i && !_clear(a, pts[j])) {
        j--;
      }
      out.add(pts[j]);
      a = pts[j];
      i = j + 1;
    }
    if (_free(_cellOf(to).$1, _cellOf(to).$2)) out.add(to);
    return out;
  }

  bool _clear(Offset a, Offset b) {
    final d = (b - a).distance;
    final steps = max(1, (d / (_cell * 0.4)).ceil());
    for (var k = 1; k < steps; k++) {
      final p = Offset.lerp(a, b, k / steps)!;
      final c = _cellOf(p);
      if (!_free(c.$1, c.$2)) return false;
    }
    return true;
  }

  /// Vị trí sau khi đi được quãng [dist] trên đường [path] bắt đầu từ [from]
  Offset _along(Offset from, List<Offset> path, double dist) {
    var a = from;
    for (final b in path) {
      final d = (b - a).distance;
      if (dist <= d) return Offset.lerp(a, b, d == 0 ? 1 : dist / d)!;
      dist -= d;
      a = b;
    }
    return a;
  }

  final Map<int, List<Offset>> _inPath = {};
  final Map<int, double> _pickLen = {}; // buffet: quãng đường tới quầy lấy món

  // ---- trạng thái hoạt cảnh
  List<bool> _occ = [];
  List<double> _arr = [], _seatAt = [], _serveAt = [], _cleanAt = [];
  List<int> _seed = [], _stP = [];
  List<bool> _dirtyP = [];
  List<String> _npcP = [];
  final List<_IWalker> _leavers = [];
  final List<(Offset, double)> _coins = [];
  int _seedN = 0;
  // phục vụ
  Offset _wp = const Offset(5.3, 3.75);
  List<Offset> _wPath = [];
  bool _wLeft = false;
  // đầu bếp
  double _cx = 2.0;
  int _chefGo = 0;
  bool _cLeft = false;
  // bếp
  List<bool> _doneP = [], _burntP = [], _cookP = [], _hadT = [];
  List<int> _addedP = [], _mistP = [], _chopKey = [];
  List<double> _saltP = [], _heatP = [], _doneAt = [], _sentAt = [], _knifeAt = [];
  List<String> _lastDish = [], _sentDish = [];
  int _prevActive = -1;
  final Map<int, String> _incP = {};
  final Map<String, double> _petHeart = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _sync(initial: true);
  }

  @override
  void didUpdateWidget(covariant IsoRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _onTick(Duration e) {
    final t = e.inMicroseconds / 1e6;
    if (kIsWeb && t > _t && t - _t < kWebFrame) return;
    final dt = (t - _t).clamp(0.0, 0.1).toDouble();
    // phục vụ đi theo đường
    var step = 3.4 * dt;
    while (step > 0 && _wPath.isNotEmpty) {
      final d = _wPath.first - _wp;
      final dist = d.distance;
      if ((d.dx - d.dy).abs() > 0.05) _wLeft = (d.dx - d.dy) < 0;
      if (dist <= step) {
        _wp = _wPath.removeAt(0);
        step -= dist;
      } else {
        _wp += d / dist * step;
        step = 0;
      }
    }
    // đầu bếp đi tới bếp vừa thao tác
    if (widget.stations.isNotEmpty) {
      final tx = _chefSpot(min(max(_chefGo, 0), widget.stations.length - 1)).dx;
      final d = tx - _cx;
      if (d.abs() > 0.02) {
        _cLeft = d < 0;
        _cx += d.sign * min(d.abs(), 3.0 * dt);
      }
    }
    _leavers.removeWhere((l) => t - l.t0 > l.dur + 0.2);
    _coins.removeWhere((cn) => t - cn.$2 > 1.2);
    _clock.value = t;
  }

  void _walkTo(Offset g) {
    if (_wPath.isNotEmpty && (_wPath.last - g).distance < 0.05) return;
    _wPath = _route(_wp, g);
  }

  double _walkLen(List<Offset> p, Offset from) {
    var len = 0.0;
    var a = from;
    for (final b in p) {
      len += (b - a).distance;
      a = b;
    }
    return len;
  }

  void _sync({bool initial = false}) {
    final t = _t;
    // ----- sảnh
    final tb = widget.tables;
    final n = tb.length;
    var first = initial;
    if (_occ.length != n) {
      _occ = List.filled(n, false);
      _arr = List.filled(n, -10.0);
      _seatAt = List.filled(n, -10.0);
      _serveAt = List.filled(n, -10.0);
      _cleanAt = List.filled(n, -10.0);
      _seed = List.filled(n, 0);
      _stP = List.filled(n, -1);
      _dirtyP = List.filled(n, false);
      _npcP = List.filled(n, '');
      _leavers.clear();
      _inPath.clear();
      _blockKey = '';
      first = true;
    }
    for (var i = 0; i < n; i++) {
      final occ = tb[i].c != null;
      if (occ && !_occ[i]) {
        _seed[i] = ++_seedN * 7919 + i * 31;
        _arr[i] = first ? -10.0 : t;
        var path = [..._route(_door, _seat(i) + const Offset(0.45, 0.45)), _seat(i)];
        _pickLen.remove(i);
        if (widget.buffet && widget.trays.any((x) => x.$1 == tb[i].c!.recipe.id)) {
          // buffet: ghé quầy lấy món rồi mới về bàn
          final rid = tb[i].c!.recipe.id;
          final n0 = widget.trays.length;
          final k = max(0, widget.trays.indexWhere((x) => x.$1 == rid));
          final pick = Offset(1.95 + k * (4.2 / n0), 3.65);
          final a = _route(_door, pick);
          _pickLen[i] = _walkLen(a, _door);
          path = [...a, ..._route(pick, _seat(i) + const Offset(0.45, 0.45)), _seat(i)];
        }
        _inPath[i] = path;
        _seatAt[i] = first ? -10.0 : t + _walkLen(path, _door) / 2.2;
      } else if (!occ && _occ[i] && !first) {
        final happy = tb[i].dirty;
        final path = [_seat(i), ..._route(_seat(i) + const Offset(0.45, 0.45), _door)];
        _leavers.add(_IWalker(_seed[i], _npcP[i], path, t, _walkLen(path, _seat(i)) / 2.2, happy));
        if (happy) _coins.add((_table(i), t));
        Sound.sfx(happy ? 'coin' : 'angry');
      }
      _occ[i] = occ;
      final cu = tb[i].c;
      if (cu != null) _npcP[i] = cu.npc;
      final dirty = tb[i].dirty;
      if (!first && _dirtyP[i] && !dirty) {
        _cleanAt[i] = t;
        Sound.sfx('clean');
        _walkTo(_approach(i));
      }
      _dirtyP[i] = dirty;
      final stv = cu?.st ?? -1;
      if (!first && _stP[i] == 1 && stv == 2) {
        _serveAt[i] = t;
        Sound.sfx('serve');
        _walkTo(_approach(i));
      }
      if (!first && _stP[i] == 0 && stv == 1) {
        Sound.sfx('order');
        _walkTo(_approach(i));
      }
      _stP[i] = stv;
    }
    // ----- bếp
    final st = widget.stations;
    final m = st.length;
    var kfirst = initial;
    if (_doneP.length != m) {
      _doneP = List.filled(m, false);
      _burntP = List.filled(m, false);
      _cookP = List.filled(m, false);
      _hadT = List.filled(m, false);
      _addedP = List.filled(m, 0);
      _mistP = List.filled(m, 0);
      _chopKey = List.filled(m, 0);
      _saltP = List.filled(m, 0.0);
      _heatP = List.filled(m, 0.5);
      _doneAt = List.filled(m, -10.0);
      _sentAt = List.filled(m, -10.0);
      _knifeAt = List.filled(m, -10.0);
      _lastDish = List.filled(m, '');
      _sentDish = List.filled(m, '');
      kfirst = true;
    }
    if (widget.activeStation != _prevActive) {
      _prevActive = widget.activeStation;
      if (widget.activeStation >= 0) _chefGo = widget.activeStation;
    }
    for (var i = 0; i < m; i++) {
      final s = st[i];
      final key = s.board.length * 100 + s.chopLeft;
      if (!kfirst) {
        final touched = (s.t != null && !_hadT[i]) ||
            s.added.length > _addedP[i] ||
            key < _chopKey[i] ||
            s.salt > _saltP[i] + 0.01 ||
            (s.heat - _heatP[i]).abs() > 0.12 ||
            (_doneP[i] && s.t == null);
        if (touched) _chefGo = i;
        if (s.done && !_doneP[i]) {
          _doneAt[i] = t;
          Sound.sfx('ding');
        }
        if (_doneP[i] && s.t == null) {
          _sentAt[i] = t;
          _sentDish[i] = _lastDish[i];
          Sound.sfx('whoosh', vol: 0.8);
        }
        if (s.burnt && !_burntP[i]) Sound.sfx('burn');
        if (s.cooking && !_cookP[i]) Sound.sfx('sizzle', vol: 0.7);
        if (s.added.length > _addedP[i]) Sound.sfx('plop');
        if (s.mistakes > _mistP[i]) Sound.sfx('wrong');
        if (key < _chopKey[i]) {
          _knifeAt[i] = t;
          Sound.sfx('chop');
        }
        if (s.salt > _saltP[i] + 0.01) Sound.sfx('shake');
        if ((s.heat - _heatP[i]).abs() > 0.12) Sound.sfx('knob', vol: 0.6);
      }
      _doneP[i] = s.done;
      _burntP[i] = s.burnt;
      _cookP[i] = s.cooking;
      _addedP[i] = s.added.length;
      _mistP[i] = s.mistakes;
      _chopKey[i] = key;
      _saltP[i] = s.salt;
      _heatP[i] = s.heat;
      _hadT[i] = s.t != null;
      if (s.t != null) _lastDish[i] = s.t!.recipe.id;
    }
    // ----- sự cố
    final now = <int, String>{for (final x in widget.incidents) x.id: x.type};
    if (!initial) {
      for (final e in now.entries) {
        if (!_incP.containsKey(e.key)) {
          if (e.value == 'fire') Sound.sfx('alarm');
          if (e.value == 'power') Sound.sfx('powerdown');
        }
      }
      for (final e in _incP.entries) {
        if (!now.containsKey(e.key)) Sound.sfx('fixed');
      }
    }
    _incP
      ..clear()
      ..addAll(now);
  }

  // =====================================================================
  //  CHẠM
  // =====================================================================
  Offset _incGrid(Incident x) => _uv(4.4 + x.y * 6.6, (x.x - 0.5) * 5.6);
  Offset get _fuse => _p(0, 1.3, _wallH * 0.55);
  Offset _petGrid(String id, double t) {
    final k = widget.pets.indexOf(id);
    switch (id) {
      case 'parrot':
        return _uv(_g - 1.0, -2.4);
      case 'hamster':
        return const Offset(0.7, 3.2);
      default:
        final u = 6.5 + sin(t * 0.17 + k * 2.1) * 2.3;
        final v = sin(t * 0.23 + k * 1.3) * 2.6;
        return _uv(u, v);
    }
  }

  void _onTap(Offset pos) {
    final t = _t;
    // 1) sự cố
    for (final x in widget.incidents) {
      Offset? at;
      double r = _tw * 0.6;
      switch (x.type) {
        case 'rat':
        case 'leak':
          at = _pg(_incGrid(x));
          break;
        case 'brawl':
          if (x.target < widget.tables.length) at = _pg(_table(x.target), 20);
          r = _tw * 0.8;
          break;
        case 'fire':
          if (x.target < widget.stations.length) at = _pg(_stove(x.target), 22);
          break;
        case 'power':
          at = _fuse;
          r = _tw * 0.7;
          break;
      }
      if (at != null && (pos - at).distance < r) {
        widget.onIncident(x.id);
        return;
      }
    }
    // 2) món trên quầy ra món
    for (var j = 0; j < widget.counter.length && j < 6; j++) {
      if ((pos - _pg(_slot(j), 30)).distance < _tw * 0.42) {
        widget.onDish(widget.counter[j]);
        _walkTo(_slot(j) + const Offset(0.35, 0.95));
        return;
      }
    }
    // 3) bếp
    for (var i = 0; i < widget.stations.length; i++) {
      final ctr = _pg(_stove(i), 24);
      if ((pos - ctr).distance < _tw * 0.62) {
        final s = widget.stations[i];
        _chefGo = i;
        if (s.cooking && (pos.dx - ctr.dx).abs() > _tw * 0.22) {
          widget.onHeat(i, pos.dx < ctr.dx ? -0.2 : 0.2); // chạm bên trái: nhỏ lửa, bên phải: to lửa
        } else {
          widget.onStation(i);
        }
        return;
      }
    }
    // 4) bàn
    for (var i = 0; i < widget.tables.length; i++) {
      final ct = _pg(_table(i), 12);
      final sp = _pg(_seat(i), _tw * 0.5);
      if ((pos - ct).distance < _tw * 0.75 || (pos - sp).distance < _tw * 0.55) {
        widget.onTable(i);
        _walkTo(_approach(i));
        return;
      }
    }
    // 5) thú cưng
    for (final id in widget.pets) {
      if ((pos - _pg(_petGrid(id, t), 10)).distance < _tw * 0.55) {
        _petHeart[id] = t;
        Sound.sfx(id == 'dog' ? 'woof' : (id == 'parrot' ? 'chirp' : (id == 'hamster' ? 'squeak' : 'purr')));
        widget.onPet(id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _onTap(d.localPosition),
        child: ClipRect(child: CustomPaint(painter: _IsoPainter(this), size: Size.infinite)),
      );

  // =====================================================================
  //  VẼ
  // =====================================================================
  void _layout(Size sz) {
    _size = sz;
    final w = sz.width, h = sz.height;
    _th = min((h - 10) / (_g + 3.0), w / 12.6);
    _tw = _th * 2;
    _wallH = _th * 2.6;
    final used = _g * _th + _wallH;
    _ox = w / 2;
    _oy = (h - used) / 2 + _wallH + 4;
  }

  void _paint(Canvas c, Size sz) {
    if (sz.width < 40 || sz.height < 40) return;
    if (sz != _size) _layout(sz);
    final t = _t;
    final th = themeFor(widget.venueId, widget.style);
    final plan = _plan;
    final power = widget.incidents.any((x) => x.type == 'power');
    _outside(c, sz);

    // ---- sàn
    const cell = 1.0;
    for (var gy = 0.0; gy < _g; gy += cell) {
      for (var gx = 0.0; gx < _g; gx += cell) {
        final kitchen = gx + gy < 5.4;
        final even = ((gx + gy) / cell).round().isEven;
        final col = kitchen ? (even ? plan.kitchenA : plan.kitchenB) : (even ? th.floorA : th.floorB);
        if (!kitchen && plan.table == 'cloth') {
          // gạch hoa hồng: nền trắng, hoa hồng nhuỵ vàng, nụ nhỏ ở góc
          c.drawPath(_area(gx, gy, gx + cell, gy + cell), Paint()..color = const Color(0xFFFFFAFC));
          c.drawPath(_area(gx, gy, gx + cell, gy + cell), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = const Color(0x22AD1457));
          _flower(c, _p(gx + 0.5, gy + 0.5), _tw * 0.16);
          _flower(c, _p(gx, gy), _tw * 0.07);
        } else if (!kitchen && plan.table == 'ming') {
          _encaustic(c, gx, gy);
        } else if (!kitchen && plan.table == 'iron') {
          // gạch đất nung kiểu Mexico, góc là viên gạch men xanh hoa vàng
          final odd = ((gx * 7 + gy * 3) % 5) < 2;
          c.drawPath(_area(gx, gy, gx + cell, gy + cell), Paint()..color = odd ? const Color(0xFFD9772E) : const Color(0xFFCC6A27));
          c.drawPath(_area(gx + 0.15, gy + 0.15, gx + 0.85, gy + 0.85), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7
            ..color = const Color(0x55703A10));
          c.drawPath(_area(gx, gy, gx + cell, gy + cell), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF8A7A6A));
          _talavera(c, gx, gy);
        } else {
          c.drawPath(_area(gx, gy, gx + cell, gy + cell), Paint()..color = col);
        }
      }
    }
    // thảm cửa
    c.drawPath(_area(_door.dx - 0.9, _door.dy - 0.9, _door.dx + 0.2, _door.dy + 0.2), Paint()..color = _a(th.accent, 0.8));

    // ---- tường sau
    final o0 = _p(0, 0), oR = _p(_g, 0), oL = _p(0, _g);
    final up = Offset(0, _wallH);
    c.drawPath(_poly([oL, o0, o0 - up, oL - up]), Paint()..color = _dk(th.wall, 0.12)); // tường trái
    c.drawPath(_poly([o0, oR, oR - up, o0 - up]), Paint()..color = th.wall); // tường phải
    // chân tường gỗ
    c.drawPath(_poly([oL, o0, o0 - Offset(0, _wallH * 0.18), oL - Offset(0, _wallH * 0.18)]), Paint()..color = _dk(th.wood, 0.1));
    c.drawPath(_poly([o0, oR, oR - Offset(0, _wallH * 0.18), o0 - Offset(0, _wallH * 0.18)]), Paint()..color = th.wood);
    final trim = Paint()
      ..color = th.trim
      ..strokeWidth = 4;
    c.drawLine(oL - up, o0 - up, trim);
    c.drawLine(o0 - up, oR - up, trim);
    c.drawLine(o0, o0 - up, Paint()
      ..color = _dk(th.trim, 0.2)
      ..strokeWidth = 2);
    _wallStripes(c, th);
    _wallWindow(c, 6.5, true, th);
    _wallWindow(c, 9.0, true, th);
    _wallWindow(c, 7.4, false, th);
    _wallSpecial(c, plan.special, th, t);
    // đồ treo tường (người chơi tự đặt)
    for (final d in widget.decos) {
      final dt = decoById(d.type);
      if (!dt.wall) continue;
      final gy = 3.0 + d.x * 8.5;
      drawWallDeco(c, dt.id, _p(0, gy, _wallH * 0.62), _wallH * 0.38, t);
    }
    // hộp cầu dao
    final fz = _fuse;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: fz, width: _tw * 0.32, height: _tw * 0.42), const Radius.circular(4)), Paint()..color = const Color(0xFF90A4AE));
    _emoji(c, '⚡', fz, _tw * 0.22);

    // ---- vật thể theo thứ tự xa → gần
    final draws = <(double, void Function())>[];
    // quầy bếp + bếp
    draws.add((0.9, () => _box(c, 0.25, 0.1, 6.35, 1.15, _th * 0.95, _lt(th.trim, 0.55))));
    for (var i = 0; i < widget.stations.length; i++) {
      final s = _stove(i);
      draws.add((s.dx + s.dy + 0.6, () => _drawStove(c, i, t, th)));
    }
    // tủ lạnh / bồn rửa dọc tường trái
    draws.add((1.4 + 0.3, () => _box(c, 0.1, 1.3, 0.85, 2.1, _th * 2.2, const Color(0xFFECEFF1))));
    draws.add((3.0 + 0.6, () => _box(c, 0.1, 2.3, 0.85, 3.9, _th * 0.95, _lt(th.trim, 0.45))));
    // đầu bếp
    final cs = Offset(_cx, 1.75);
    draws.add((cs.dx + cs.dy, () => _drawChef(c, cs, t)));
    // quầy ra món
    draws.add((99.5, () => _drawPass(c, t, th)));
    // bàn + khách ngồi
    for (var i = 0; i < widget.tables.length; i++) {
      final g = _table(i);
      draws.add((_zk(g), () => _drawTable(c, i, t, th)));
    }
    // khách đang đi vào
    for (var i = 0; i < widget.tables.length && i < _arr.length; i++) {
      final cu = widget.tables[i].c;
      if (cu == null || t >= _seatAt[i]) continue;
      final path = _inPath[i] ?? [_seat(i)];
      final g = _along(_door, path, (t - _arr[i]) * 2.2);
      final look = custLook(cu.npc, _seed[i]);
      final pl = _pickLen[i];
      final carry = pl != null && cu.st == 2 && (t - _arr[i]) * 2.2 >= pl ? cu.recipe.id : null;
      draws.add((_zk(g), () => drawPerson(c, _pg(g), _tw * 0.88, look, walking: true, phase: t * 11 + i, facingLeft: (_seat(i).dx - _seat(i).dy) < 0, carry: carry)));
    }
    // khách ra về
    for (final l in _leavers) {
      final g = _along(l.path.first, l.path.skip(1).toList(), (t - l.t0) * 2.2);
      draws.add((_zk(g), () => drawPerson(c, _pg(g), _tw * 0.88, custLook(l.npc, l.seed), walking: true, phase: t * 11, mood: l.happy ? 0 : 2, armUp: l.happy && sin(t * 9) > 0)));
    }
    // phục vụ (buffet: người thứ 2 cũng vào bếp nấu)
    if (widget.buffet) {
      final m = widget.stations.length;
      final int k2 = min(max(0, m - 1 - (_chefGo == m - 1 ? 1 : 0)), max(0, m - 1));
      final g2 = _chefSpot(k2);
      draws.add((g2.dx + g2.dy, () => drawPerson(c, _pg(g2), _tw * 0.92, widget.chef2Look ?? widget.waiterLook, role: 'chef', phase: t * 10, stir: t, name: widget.waiterName)));
    } else {
      draws.add((_zk(_wp) + 0.05, () => _drawWaiter(c, t)));
    }
    // đồ trang trí đặt sàn
    for (final d in widget.decos) {
      final dt = decoById(d.type);
      if (dt.wall) continue;
      final g = _uv(4.4 + d.y * 6.6, (d.x - 0.5) * 6.4);
      draws.add((_zk(g), () => drawFloorDeco(c, dt.id, _pg(g), _tw * dt.size * 0.9, t, wood: th.wood)));
    }
    // thú cưng
    for (final id in widget.pets) {
      final g = _petGrid(id, t);
      draws.add((_zk(g), () => _drawPet(c, id, g, t)));
    }
    // chuột, vũng nước
    for (final x in widget.incidents) {
      if (x.type != 'rat' && x.type != 'leak') continue;
      final g = _incGrid(x);
      draws.add((_zk(g) - (x.type == 'leak' ? 0.5 : 0), () => _drawFloorIncident(c, x, t)));
    }
    draws.sort((a, b) => a.$1.compareTo(b.$1));
    for (final d in draws) {
      d.$2();
    }

    // ---- lớp phủ: bong bóng, thanh chờ, tiền bay
    for (var i = 0; i < widget.tables.length; i++) {
      _drawOverlay(c, i, t);
    }
    for (final cn in _coins) {
      final k = (t - cn.$2) / 1.2;
      _emoji(c, '🪙', _pg(cn.$1, _tw * (0.8 + k * 1.4)), _tw * 0.4, alpha: 1 - k);
    }
    // khách chờ ngoài cửa
    if (widget.outside.isNotEmpty) {
      final angry = widget.outside.any((g) => g.frac < 0.3);
      _pill(c, '🚶 ${widget.outside.length} khách chờ ngoài cửa', _pg(_door, 6) + Offset(0, _th * 0.6), max(10.0, _tw * 0.24),
          bg: angry ? const Color(0xFFFFCDD2) : Colors.white, fg: angry ? const Color(0xFFC62828) : const Color(0xFF3E2723));
    }
    // ánh sáng theo kiểu đèn
    _drawLight(c, sz, t);
    if (power) {
      c.drawRect(Offset.zero & sz, Paint()..color = const Color(0x77000000));
      _pill(c, '⚡ Mất điện! Chọn 🔌 rồi chạm hộp cầu dao trên tường', Offset(sz.width / 2, 18), 11, bg: const Color(0xFFFFF59D));
      _emoji(c, '🔌', _fuse + Offset(0, -_tw * 0.45 - sin(t * 6).abs() * 4), _tw * 0.3);
    }
    if (widget.hasOrders && widget.stations.every((s) => s.t == null) && sin(t * 4) > -0.2) {
      _pill(c, '👆 Chạm vào bếp để nhận order', _pg(_stove(0), _th * 3.2), max(10.0, _tw * 0.22), bg: const Color(0xFFFFF59D));
    }
  }

  /// Khung cảnh bên ngoài: đường phố phía sau, vỉa hè lát gạch, bãi cỏ phía trước
  void _outside(Canvas c, Size sz) {
    c.drawRect(Offset.zero & sz, Paint()..color = const Color(0xFF7CC36A));
    // vỉa hè quanh nhà
    c.drawPath(_area(-14, -14, _g + 0.8, _g + 0.8), Paint()..color = const Color(0xFFE3E0D8));
    final line = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 1;
    for (var k = -14.0; k <= _g + 0.8; k += 1) {
      c.drawLine(_p(k, -14), _p(k, _g + 0.8), line);
      c.drawLine(_p(-14, k), _p(_g + 0.8, k), line);
    }
    // 2 con đường phía sau nhà
    final road = Paint()..color = const Color(0xFF5E6472);
    c.drawPath(_area(-14, -4.2, _g + 8, -2.0), road);
    c.drawPath(_area(-4.2, -14, -2.0, _g + 8), road);
    final dash = Paint()..color = const Color(0xFFFFE082);
    for (var k = -12.0; k < _g + 6; k += 1.4) {
      c.drawPath(_area(k, -3.15, k + 0.7, -3.05), dash);
      c.drawPath(_area(-3.15, k, -3.05, k + 0.7), dash);
    }
    // bãi cỏ phía trước
    c.drawPath(_area(_g + 0.8, -14, _g + 14, _g + 14), Paint()..color = const Color(0xFF7CC36A));
    c.drawPath(_area(-14, _g + 0.8, _g + 0.8, _g + 14), Paint()..color = const Color(0xFF7CC36A));
    // bậc thềm nền nhà
    final l = _p(0, _g), b = _p(_g, _g), r = _p(_g, 0);
    c.drawPath(_poly([l, b, b + const Offset(0, 6), l + const Offset(0, 6)]), Paint()..color = const Color(0xFFB0A898));
    c.drawPath(_poly([b, r, r + const Offset(0, 6), b + const Offset(0, 6)]), Paint()..color = const Color(0xFFC8C0B0));
    // cây + đèn đường bên ngoài
    for (final g in const [Offset(13.6, 3.0), Offset(13.6, 8.5), Offset(3.5, 13.6), Offset(9.0, 13.6)]) {
      drawPixelTree(c, _pg(g), _tw * 1.15, alt: g.dx > 13 && g.dy > 8);
    }
  }

  /// Tường sọc 2 màu + kệ chai lọ + khung tranh (như các game nhà hàng)
  void _wallStripes(Canvas c, VTheme th) {
    final a = _lt(th.wall, 0.18), b = th.wall;
    for (var k = 0.0; k < _g; k += 1.5) {
      final col = ((k / 1.5).round()).isEven ? a : b;
      // tường phải (gy = 0)
      c.drawPath(_poly([_p(k, 0, _wallH * 0.18), _p(k + 1.5, 0, _wallH * 0.18), _p(k + 1.5, 0, _wallH), _p(k, 0, _wallH)]), Paint()..color = col);
      // tường trái (gx = 0), tối hơn một chút
      c.drawPath(_poly([_p(0, k, _wallH * 0.18), _p(0, k + 1.5, _wallH * 0.18), _p(0, k + 1.5, _wallH), _p(0, k, _wallH)]), Paint()..color = _dk(col, 0.1));
    }
    // kệ chai lọ trên tường phải
    for (final gx in [10.6]) {
      final s0 = _p(gx, 0, _wallH * 0.6), s1 = _p(gx + 1.0, 0, _wallH * 0.6);
      c.drawLine(s0, s1, Paint()
        ..color = th.wood
        ..strokeWidth = 3);
      for (var k = 0; k < 4; k++) {
        final q = Offset.lerp(s0, s1, 0.15 + k * 0.23)!;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: q - Offset(0, _tw * 0.12), width: _tw * 0.08, height: _tw * 0.22), const Radius.circular(2)),
            Paint()..color = const [Color(0xFFE53935), Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF8E24AA)][k]);
      }
    }
    // khung tranh trên tường trái
    for (final gy in [9.6]) {
      final a0 = _p(0, gy, _wallH * 0.8), a1 = _p(0, gy + 1.1, _wallH * 0.8);
      final path = _poly([a0, a1, a1 + Offset(0, _wallH * 0.4), a0 + Offset(0, _wallH * 0.4)]);
      c.drawPath(path, Paint()..color = const Color(0xFFFFF8E1));
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = th.wood,
      );
      _emoji(c, '🌺', Offset.lerp(a0, a1, 0.5)! + Offset(0, _wallH * 0.2), _tw * 0.26);
    }
  }

  void _wallWindow(Canvas c, double at, bool right, VTheme th) {
    // cửa sổ trên tường: thấy trời theo giờ thật
    final phase = realDayPhase();
    final sky = phase == 2 ? const [Color(0xFF1A237E), Color(0xFF3949AB)] : (phase == 1 ? const [Color(0xFFFF8A65), Color(0xFFFFD180)] : const [Color(0xFF90CAF9), Color(0xFFE3F2FD)]);
    final a0 = right ? _p(at, 0, _wallH * 0.82) : _p(0, at, _wallH * 0.82);
    final a1 = right ? _p(at + 1.4, 0, _wallH * 0.82) : _p(0, at + 1.4, _wallH * 0.82);
    final b1 = a1 + Offset(0, _wallH * 0.48), b0 = a0 + Offset(0, _wallH * 0.48);
    final path = _poly([a0, a1, b1, b0]);
    final r = path.getBounds();
    c.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky).createShader(r));
    if (phase == 2) {
      for (var k = 0; k < 4; k++) {
        c.drawCircle(Offset.lerp(a0, b1, 0.2 + k * 0.2)! + Offset(0, -6.0 + k * 2), 1.2, Paint()..color = Colors.white);
      }
    }
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = th.trim,
    );
    c.drawLine(Offset.lerp(a0, a1, 0.5)!, Offset.lerp(b0, b1, 0.5)!, Paint()
      ..color = th.trim
      ..strokeWidth = 2);
  }

  /// Đồ đặc trưng của từng quán trên tường trái
  void _wallSpecial(Canvas c, String kind, VTheme th, double t) {
    switch (kind) {
      case 'tank':
        // bể hải sản kính lớn với cua, tôm, cá
        final a0 = _p(0, 4.2, _wallH * 0.75), a1 = _p(0, 6.6, _wallH * 0.75);
        final b0 = a0 + Offset(0, _wallH * 0.6), b1 = a1 + Offset(0, _wallH * 0.6);
        c.drawPath(_poly([a0, a1, b1, b0]), Paint()..color = const Color(0xCC4FC3F7));
        for (var k = 0; k < 4; k++) {
          final ph = (t * 0.12 + k * 0.27) % 1.0;
          final p = Offset.lerp(Offset.lerp(a0, a1, ph)!, Offset.lerp(b0, b1, ph)!, 0.3 + 0.15 * (k % 3))!;
          _emoji(c, const ['🐟', '🦀', '🦐', '🐠'][k], p, _tw * 0.26);
        }
        for (var k = 0; k < 5; k++) {
          final ph = (t * 0.6 + k * 0.2) % 1.0;
          c.drawCircle(Offset.lerp(b0, b1, 0.1 + k * 0.18)! - Offset(0, ph * _wallH * 0.55), 1.6, Paint()..color = const Color(0xAAFFFFFF));
        }
        c.drawPath(
          _poly([a0, a1, b1, b0]),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFF455A64),
        );
        break;
      case 'lanterns':
      case 'hanok':
        for (var k = 0; k < 3; k++) {
          final p = _p(0, 3.6 + k * 2.2, _wallH * 0.98) + Offset(0, sin(t * 2 + k) * 2);
          final col = kind == 'hanok' ? const Color(0xFF1565C0) : const Color(0xFFD32F2F);
          c.drawLine(p - Offset(0, _tw * 0.25), p, Paint()
            ..color = const Color(0xFF3E2723)
            ..strokeWidth = 1.2);
          c.drawOval(Rect.fromCenter(center: p + Offset(0, _tw * 0.15), width: _tw * 0.32, height: _tw * 0.38), Paint()..color = col);
          c.drawRect(Rect.fromCenter(center: p + Offset(0, _tw * 0.36), width: _tw * 0.06, height: _tw * 0.12), Paint()..color = const Color(0xFFFFC107));
        }
        if (kind == 'hanok') {
          // bảng thực đơn kiểu Hàn
          final a = _p(0, 4.6, _wallH * 0.62), b = _p(0, 6.4, _wallH * 0.62);
          c.drawPath(_poly([a, b, b + Offset(0, _wallH * 0.32), a + Offset(0, _wallH * 0.32)]), Paint()..color = const Color(0xFF263238));
          _emoji(c, '🥩', Offset.lerp(a, b, 0.3)! + Offset(0, _wallH * 0.16), _tw * 0.2);
          _emoji(c, '🍚', Offset.lerp(a, b, 0.7)! + Offset(0, _wallH * 0.16), _tw * 0.2);
        }
        break;
      case 'bamboo':
        // vách tre + nón lá
        for (var k = 0; k < 14; k++) {
          final a = _p(0, 3.0 + k * 0.42, _wallH * 0.92);
          c.drawLine(a, a + Offset(0, _wallH * 0.7), Paint()
            ..color = k.isEven ? const Color(0xFFC5A44E) : const Color(0xFFB08D3A)
            ..strokeWidth = _tw * 0.12);
        }
        for (final gy in [4.4, 7.0]) {
          final p = _p(0, gy, _wallH * 0.6);
          c.drawPath(
            Path()
              ..moveTo(p.dx - _tw * 0.32, p.dy + _tw * 0.1)
              ..lineTo(p.dx, p.dy - _tw * 0.2)
              ..lineTo(p.dx + _tw * 0.32, p.dy + _tw * 0.1)
              ..close(),
            Paint()..color = const Color(0xFFFFE0B2),
          );
        }
        break;
      case 'books':
        final a0 = _p(0, 4.2, _wallH * 0.85), a1 = _p(0, 6.2, _wallH * 0.85);
        c.drawPath(_poly([a0, a1, a1 + Offset(0, _wallH * 0.7), a0 + Offset(0, _wallH * 0.7)]), Paint()..color = _dk(th.wood, 0.1));
        const cols = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFFB300), Color(0xFF8E24AA)];
        for (var row = 0; row < 3; row++) {
          for (var k = 0; k < 9; k++) {
            final p = Offset.lerp(a0, a1, 0.06 + k * 0.1)! + Offset(0, _wallH * (0.12 + row * 0.2));
            c.drawRect(Rect.fromLTWH(p.dx, p.dy, _tw * 0.07, _wallH * 0.14), Paint()..color = cols[(k + row) % cols.length]);
          }
        }
        break;
      case 'cakes':
        final a0 = _p(0, 4.4, _wallH * 0.7), a1 = _p(0, 6.4, _wallH * 0.7);
        c.drawPath(_poly([a0, a1, a1 + Offset(0, _wallH * 0.45), a0 + Offset(0, _wallH * 0.45)]), Paint()..color = const Color(0xAAFFFFFF));
        for (var k = 0; k < 4; k++) {
          _emoji(c, const ['🎂', '🧁', '🍰', '🥐'][k], Offset.lerp(a0, a1, 0.15 + k * 0.23)! + Offset(0, _wallH * 0.22), _tw * 0.26);
        }
        break;
      case 'cactus':
        _emoji(c, '🌵', _p(0, 4.6, _wallH * 0.45), _tw * 0.6);
        _emoji(c, '👒', _p(0, 6.2, _wallH * 0.8), _tw * 0.4);
        _emoji(c, '🌶️', _p(0, 7.4, _wallH * 0.75), _tw * 0.3);
        break;
      case 'menu':
        final a = _p(0, 4.4, _wallH * 0.82), b = _p(0, 6.6, _wallH * 0.82);
        c.drawPath(_poly([a, b, b + Offset(0, _wallH * 0.42), a + Offset(0, _wallH * 0.42)]), Paint()..color = const Color(0xFF263238));
        _emoji(c, '🍔', Offset.lerp(a, b, 0.3)! + Offset(0, _wallH * 0.2), _tw * 0.22);
        _emoji(c, '🍟', Offset.lerp(a, b, 0.7)! + Offset(0, _wallH * 0.2), _tw * 0.22);
        break;
    }
  }

  void _drawStove(Canvas c, int i, double t, VTheme th) {
    final st = widget.stations[i];
    final g = _stove(i);
    final active = i == widget.activeStation;
    final fire = widget.incidents.any((x) => x.type == 'fire' && x.target == i);
    // bếp từ: thân vàng, mặt kính đen, bảng điều khiển xanh
    final zc = _th * 0.95, hb = _th * 0.26;
    final x0 = g.dx - 0.47, x1 = g.dx + 0.47;
    const y0 = 0.2, y1 = 1.04;
    _box(c, x0, y0, x1, y1, hb, const Color(0xFFFFC94A), z: zc);
    c.drawPath(_area(x0 + 0.07, y0 + 0.07, x1 - 0.07, y1 - 0.07, zc + hb), Paint()..color = const Color(0xFF1E272C));
    final pa = _p(x0 + 0.12, y1, zc + hb * 0.2), pb = _p(x1 - 0.12, y1, zc + hb * 0.2);
    final up = Offset(0, hb * 0.6);
    c.drawPath(_poly([pa, pb, pb - up, pa - up]), Paint()..color = const Color(0xFF1565C0));
    final dtx = _text(st.cooking ? '${(300 + st.heat * 700).round()}' : '0:00', max(6.0, _tw * 0.07), color: const Color(0xFFB3E5FC), bold: true);
    final dm = Offset.lerp(pa, pb, 0.5)! - up / 2;
    dtx.paint(c, dm - Offset(dtx.width / 2, dtx.height / 2));
    final top = _pg(g, zc + hb);
    c.drawOval(Rect.fromCenter(center: top, width: _tw * 0.52, height: _th * 0.44), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = st.cooking && !st.burnt ? Color.lerp(const Color(0xFFFFAB91), const Color(0xFFFF3D00), st.heat.clamp(0.0, 1.0).toDouble())! : const Color(0xFF546E7A));
    if (active) {
      c.drawOval(Rect.fromCenter(center: top, width: _tw * 0.741, height: _th * 0.624), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF4C8DFF));
    }
    // nồi xanh lá, quai đen, miệng inox
    final pot = top - Offset(0, _th * 0.273);
    final hasT = st.t != null;
    final pw = _tw * 0.43;
    const green = Color(0xFF2FA35F);
    c.drawOval(Rect.fromCenter(center: pot + Offset(0, _th * 0.117), width: pw, height: _th * 0.351), Paint()..color = _dk(green, 0.25));
    c.drawRect(Rect.fromCenter(center: pot, width: pw, height: _th * 0.234), Paint()..color = green);
    c.drawRect(Rect.fromLTWH(pot.dx - pw * 0.34, pot.dy - _th * 0.1, pw * 0.08, _th * 0.2), Paint()..color = _a(Colors.white, 0.35));
    final hp = Paint()..color = const Color(0xFF37474F);
    for (final s in const [-1.0, 1.0]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pot + Offset(s * pw * 0.56, -_th * 0.05), width: pw * 0.16, height: _th * 0.1), const Radius.circular(2)), hp);
    }
    c.drawOval(Rect.fromCenter(center: pot - Offset(0, _th * 0.117), width: pw * 1.04, height: _th * 0.33), Paint()..color = const Color(0xFFCFD8DC));
    c.drawOval(Rect.fromCenter(center: pot - Offset(0, _th * 0.117), width: pw * 0.86, height: _th * 0.25), Paint()..color = hasT ? const Color(0xFFFFCC80) : const Color(0xFFB3E5FC));
    if (st.cooking) {
      for (var k = 0; k < 2; k++) {
        final ph = (t * 0.8 + k * 0.5) % 1.0;
        c.drawCircle(pot - Offset(-(k - 0.5) * _tw * 0.14, _th * (0.3 + ph * 1.2)), _tw * (0.05 + 0.06 * ph), Paint()..color = _a(Colors.white, 0.6 * (1 - ph)));
      }
    }
    // thớt khi đang thái
    if (st.chopping) {
      final bd = _pg(Offset(g.dx + 0.15, 1.05), _th * 0.741);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: bd, width: _tw * 0.328, height: _th * 0.234), const Radius.circular(3)), Paint()..color = const Color(0xFFD7B98E));
      final ing = st.board.first;
      final ie = _ingEmoji(ing);
      _emoji(c, ie, bd - Offset(0, _th * 0.062), _tw * 0.172);
      final kt = t - _knifeAt[i];
      _emoji(c, '🔪', bd + Offset(_tw * 0.125, -_th * (0.35 + (kt < 0.2 ? 0 : 0.25))), _tw * 0.156);
      _pill(c, '🔪 ×${st.chopLeft}', bd + Offset(0, _th * 0.351), max(9.0, _tw * 0.14), bg: const Color(0xFFFFF8E1));
    }
    // món chín: hiện món trên bếp + đếm ngược trước khi cháy
    if (st.done) {
      drawDish(c, st.t!.recipe.id, pot - Offset(0, _th * 0.429), _tw * 0.585, t: t, burnt: st.burnt);
      if (!st.burnt) {
        final left = (1 - st.doneT / max(0.1, widget.burnTime)).clamp(0.0, 1.0).toDouble();
        final bar = Rect.fromCenter(center: pot - Offset(0, _th * 1.17), width: _tw * 0.484, height: 5);
        c.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = const Color(0x55000000));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * left, bar.height), const Radius.circular(3)), Paint()..color = left < 0.35 ? const Color(0xFFFF5252) : const Color(0xFF66BB6A));
        if (sin(t * 6) > 0) _emoji(c, '🔔', pot + Offset(_tw * 0.296, -_th * 0.936), _tw * 0.172);
      }
    } else if (st.cooking && st.need > 0) {
      // tiến độ nấu + đồng hồ lửa
      final pr = (st.prog / st.need).clamp(0.0, 1.0).toDouble();
      final bar = Rect.fromCenter(center: pot - Offset(0, _th * 0.819), width: _tw * 0.484, height: 5);
      c.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = const Color(0x55000000));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * pr, bar.height), const Radius.circular(3)), Paint()..color = const Color(0xFFFFB300));
      final hz = st.heat < 0.3 ? '🧊' : (st.heat <= 0.75 ? '🔥' : '🌋');
      _pill(c, '−  $hz  +', pot - Offset(0, _th * 1.287), max(9.0, _tw * 0.156), bg: st.heat > 0.75 ? const Color(0xFFFFCDD2) : Colors.white);
    } else if (hasT) {
      // món đang chờ nguyên liệu: hình món nhỏ
      drawDish(c, st.t!.recipe.id, pot - Offset(0, _th * 0.858), _tw * 0.328, t: t);
    }
    // gửi món ra quầy
    final ks = t - _sentAt[i];
    if (ks >= 0 && ks < 0.6 && _sentDish[i].isNotEmpty) {
      final p = Offset.lerp(pot, _pg(_slot(0), 30), ks / 0.6)!;
      drawDish(c, _sentDish[i], p, _tw * 0.429, t: t);
    }
    if (fire) {
      for (var k = 0; k < 4; k++) {
        _emoji(c, '🔥', pot + Offset((k - 1.5) * _tw * 0.125, -_th * (0.4 + 0.25 * sin(t * 12 + k).abs())), _tw * (0.32 + 0.06 * k % 2));
      }
      final inc = widget.incidents.firstWhere((x) => x.type == 'fire' && x.target == i);
      _pill(c, '🧯×${inc.hp}', pot - Offset(0, _th * 1.482), max(9.0, _tw * 0.156), bg: const Color(0xFFFFEBEE), fg: const Color(0xFFC62828));
    }
    final lab = _text('${i + 1}', max(8.0, _tw * 0.133), color: const Color(0xFF37474F), bold: true);
    lab.paint(c, _pg(g + const Offset(0.35, 0.45), _th * 0.39) - Offset(lab.width / 2, lab.height / 2));
  }

  String _ingEmoji(String id) {
    for (final v in venues) {
      for (final i in v.shelf) {
        if (i.id == id) return i.emoji;
      }
    }
    for (final i in gardenIngs) {
      if (i.id == id) return i.emoji;
    }
    return '🥕';
  }

  void _drawChef(Canvas c, Offset g, double t) {
    final st = widget.stations;
    final int at = min(max(_chefGo, 0), max(0, st.length - 1));
    final busy = st.isNotEmpty && (st[at].cooking || st[at].chopping);
    drawPerson(c, _pg(g), _tw * 0.92, widget.chefLook, role: 'chef', walking: (_chefSpot(at).dx - _cx).abs() > 0.03, phase: t * 10, facingLeft: _cLeft, stir: busy ? t : -1, name: widget.chefName);
  }

  void _drawWaiter(Canvas c, double t) {
    String? carry;
    for (final d in widget.counter) {
      if (d.ticketId == widget.selDishId) carry = d.recipe.id;
    }
    drawPerson(c, _pg(_wp), _tw * 0.92, widget.waiterLook, role: 'waiter', walking: _wPath.isNotEmpty, phase: t * 11, facingLeft: _wLeft, carry: carry, name: widget.waiterName);
  }

  void _drawPass(Canvas c, double t, VTheme th) {
    if (widget.buffet) return _drawBuffet(c, t, th);
    // quầy ra món: thân trắng, nẹp gỗ phát sáng, tấm gỗ logo giữa, máy POS + ly
    final h = _th * 1.2;
    _box(c, 1.25, 2.6, 6.2, 3.25, h, const Color(0xFFF7F5F2));
    final wd = _lt(th.wood, 0.1);
    final u = Offset(0, h * 0.06);
    final s0 = _p(1.25, 3.25, h * 0.7), s1 = _p(6.2, 3.25, h * 0.7);
    c.drawPath(_poly([s0, s1, s1 - u, s0 - u]), Paint()..color = wd);
    c.drawPath(_poly([s0 + u, s1 + u, s1, s0]), Paint()..color = const Color(0x55FFE082));
    final r0 = _p(6.2, 3.25, h * 0.7), r1 = _p(6.2, 2.6, h * 0.7);
    c.drawPath(_poly([r0, r1, r1 - u, r0 - u]), Paint()..color = _dk(wd, 0.1));
    // ly giấy dọc mép sau
    for (var k = 0; k < 5; k++) {
      final cp = _pg(Offset(1.55 + k * 0.22, 2.7), h);
      c.drawRect(Rect.fromLTWH(cp.dx - _tw * 0.035, cp.dy - _tw * 0.1, _tw * 0.07, _tw * 0.1), Paint()..color = Colors.white);
      c.drawRect(Rect.fromLTWH(cp.dx - _tw * 0.035, cp.dy - _tw * 0.1, _tw * 0.07, _tw * 0.02), Paint()..color = const Color(0xFFBDBDBD));
    }
    // máy POS
    final ps = _pg(const Offset(5.85, 2.75), h);
    c.drawRect(Rect.fromLTWH(ps.dx - _tw * 0.02, ps.dy - _tw * 0.14, _tw * 0.04, _tw * 0.14), Paint()..color = const Color(0xFF212121));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: ps - Offset(0, _tw * 0.24), width: _tw * 0.3, height: _tw * 0.2), const Radius.circular(2)), Paint()..color = const Color(0xFF212121));
    c.drawRect(Rect.fromCenter(center: ps - Offset(0, _tw * 0.24), width: _tw * 0.25, height: _tw * 0.15), Paint()..color = const Color(0xFF4FC3F7));
    for (var j = 0; j < 6; j++) {
      final p = _pg(_slot(j), _th * 1.2);
      c.drawOval(Rect.fromCenter(center: p, width: _tw * 0.5, height: _th * 0.36), Paint()..color = const Color(0x22000000));
    }
    for (var j = 0; j < widget.counter.length && j < 6; j++) {
      final d = widget.counter[j];
      final p = _pg(_slot(j), _th * 1.2 + _tw * 0.2);
      final sel = widget.selDishId == d.ticketId;
      if (sel) {
        c.drawCircle(p, _tw * 0.36, Paint()..color = _a(const Color(0xFF00E676), 0.35 + 0.2 * sin(t * 8)));
      }
      drawDish(c, d.recipe.id, p, _tw * 0.62, t: t);
      final bad = d.quality < 0.5;
      if (bad) _emoji(c, '💨', p + Offset(_tw * 0.25, -_tw * 0.25), _tw * 0.2);
    }
    _emoji(c, '🛎️', _pg(const Offset(1.4, 3.08), _th * 1.2 + 6), _tw * 0.22);
  }

  /// Quầy buffet: mỗi khay một món, vạch xanh/đỏ là số phần còn lại
  void _drawBuffet(Canvas c, double t, VTheme th) {
    // bàn buffet phủ khăn, rủ diềm; nồi hâm có nắp vòm, chồng đĩa, ly, bát
    final h = _th * 0.95;
    final cloth = widget.venueId == 'poseidon' ? const Color(0xFF16336B) : const Color(0xFF9E1B1B);
    _box(c, 1.25, 2.6, 6.2, 3.25, h, Colors.white);
    // mặt trước: khăn rủ với các vạt hình chữ V
    final l0 = _p(1.25, 3.25, 0), l1 = _p(6.2, 3.25, 0);
    c.drawPath(_poly([l0, l1, l1 - Offset(0, h), l0 - Offset(0, h)]), Paint()..color = cloth);
    final r1 = _p(6.2, 2.6, 0);
    c.drawPath(_poly([l1, r1, r1 - Offset(0, h), l1 - Offset(0, h)]), Paint()..color = _dk(cloth, 0.15));
    for (var k = 1; k < 7; k++) {
      final b = Offset.lerp(l0, l1, k / 7)!;
      c.drawPath(_poly([b - Offset(_tw * 0.06, 0), b + Offset(_tw * 0.06, 0), b - Offset(0, h * 0.55)]), Paint()..color = _lt(cloth, 0.55));
      c.drawCircle(b - Offset(0, h * 0.02), _tw * 0.04, Paint()..color = cloth);
    }
    // diềm trên
    for (var k = 0; k < 7; k++) {
      final a = Offset.lerp(l0, l1, k / 7)! - Offset(0, h), b = Offset.lerp(l0, l1, (k + 1) / 7)! - Offset(0, h);
      c.drawPath(Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 + _th * 0.22, b.dx, b.dy), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFD54F));
    }
    c.drawPath(_area(1.25, 2.6, 6.2, 3.25, h), Paint()..color = _lt(cloth, 0.12));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _ink;
    // chồng đĩa + ly ở đầu bàn
    final ps = _pg(const Offset(1.5, 2.9), h);
    for (var k = 0; k < 6; k++) {
      final r = Rect.fromCenter(center: ps - Offset(0, k * _th * 0.07), width: _tw * 0.3, height: _th * 0.15);
      c.drawOval(r, Paint()..color = Colors.white);
      c.drawOval(r, line);
    }
    for (final o in const [Offset(1.6, 3.12), Offset(1.82, 3.12)]) {
      final gp = _pg(o, h);
      c.drawLine(gp, gp - Offset(0, _tw * 0.07), line..strokeWidth = 1.4);
      c.drawPath(_poly([gp - Offset(_tw * 0.04, _tw * 0.07), gp - Offset(-_tw * 0.04, _tw * 0.07), gp - Offset(-_tw * 0.05, _tw * 0.18), gp - Offset(_tw * 0.05, _tw * 0.18)]), Paint()..color = const Color(0xCCB3E5FC));
    }
    final n = widget.trays.length;
    for (var k = 0; k < n; k++) {
      final (id, qty) = widget.trays[k];
      final g = Offset(1.95 + k * (4.2 / max(1, n)) + 0.2, 2.9);
      final p = _pg(g, h);
      // chân đế + lò cồn
      for (final dx in const [-1.0, 1.0]) {
        c.drawLine(p + Offset(dx * _tw * 0.2, 0), p + Offset(dx * _tw * 0.2, -_th * 0.3), Paint()
          ..color = const Color(0xFF455A64)
          ..strokeWidth = 2);
      }
      c.drawRect(Rect.fromCenter(center: p - Offset(0, _th * 0.08), width: _tw * 0.1, height: _th * 0.12), Paint()..color = const Color(0xFF263238));
      if (qty > 0) c.drawCircle(p - Offset(0, _th * 0.2), 2, Paint()..color = const Color(0xFF4FC3F7));
      // khay inox
      final pan = Rect.fromCenter(center: p - Offset(0, _th * 0.36), width: _tw * 0.52, height: _th * 0.3);
      // nắp vòm: mở ra phía sau khi còn món, đậy lại khi hết
      final dome = Rect.fromLTRB(pan.left + _tw * 0.03, pan.center.dy - _tw * (qty > 0 ? 0.42 : 0.28), pan.right - _tw * 0.03, pan.center.dy + (qty > 0 ? -_tw * 0.08 : _th * 0.05));
      if (qty > 0) {
        c.drawArc(dome, pi, pi, true, Paint()..color = const Color(0xFFB0BEC5));
        c.drawArc(dome, pi, pi, true, line);
      }
      c.drawRRect(RRect.fromRectAndRadius(pan, const Radius.circular(4)), Paint()..color = const Color(0xFFCFD8DC));
      c.drawRRect(RRect.fromRectAndRadius(pan, const Radius.circular(4)), line);
      if (qty > 0) {
        drawDish(c, id, pan.center - Offset(0, _th * 0.12), _tw * (0.4 + 0.03 * min(qty, 6)), t: t);
      } else {
        c.drawArc(dome, pi, pi, true, Paint()..color = const Color(0xFF90A4AE));
        c.drawArc(dome, pi, pi, true, line);
        c.drawCircle(Offset(dome.center.dx, dome.top - 2), 2.5, Paint()..color = _ink);
        if (sin(t * 6) > 0) _emoji(c, '❗', pan.center - Offset(0, _th * 1.0), _tw * 0.22);
      }
      // số phần còn lại
      final bar = Rect.fromCenter(center: p + Offset(0, _th * 0.25), width: _tw * 0.44, height: 4);
      c.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = const Color(0x55000000));
      final f = (qty / 8).clamp(0.0, 1.0).toDouble();
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * f, bar.height), const Radius.circular(3)),
          Paint()..color = qty <= 2 ? const Color(0xFFFF5252) : const Color(0xFF66BB6A));
      // bát món nhỏ phía trước
      if (qty > 2) {
        final bp = _pg(g + const Offset(0.0, 0.25), h);
        c.drawArc(Rect.fromCenter(center: bp, width: _tw * 0.18, height: _tw * 0.12), 0, pi, true, Paint()..color = Colors.white);
        c.drawArc(Rect.fromCenter(center: bp, width: _tw * 0.18, height: _tw * 0.12), 0, pi, true, line);
      }
    }
  }

  static const _wood = Color(0xFFC98A5A), _woodDk = Color(0xFF8A5530), _ink = Color(0xFF3E2723);

  Paint get _outline => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3
    ..color = _ink;

  /// Bàn tròn gỗ chân trụ, có bình hoa cam khi bàn trống
  void _roundTable(Canvas c, Offset g, double hTop, bool vase) {
    final base = _pg(g), top = _pg(g, hTop * 1.25);
    final r = _tw * 0.36;
    // đế + chân trụ
    c.drawOval(Rect.fromCenter(center: base, width: r * 0.9, height: r * 0.32), Paint()..color = _woodDk);
    c.drawOval(Rect.fromCenter(center: base, width: r * 0.9, height: r * 0.32), _outline);
    final col = Rect.fromLTRB(top.dx - r * 0.07, top.dy, top.dx + r * 0.07, base.dy);
    c.drawRect(col, Paint()..color = _wood);
    c.drawRect(col, _outline);
    // mặt bàn dày
    final face = Rect.fromCenter(center: top, width: r * 2, height: r * 0.62);
    c.drawOval(face.shift(Offset(0, r * 0.1)), Paint()..color = _woodDk);
    c.drawOval(face.shift(Offset(0, r * 0.1)), _outline);
    c.drawOval(face, Paint()..color = _wood);
    c.drawOval(face, _outline);
    c.drawOval(Rect.fromCenter(center: top - Offset(r * 0.3, r * 0.08), width: r * 0.7, height: r * 0.16), Paint()..color = const Color(0x55FFFFFF));
    if (vase) {
      final v = top - Offset(0, r * 0.05);
      c.drawRect(Rect.fromCenter(center: v - Offset(0, r * 0.2), width: r * 0.16, height: r * 0.36), Paint()..color = const Color(0xFFF3D9B1));
      c.drawRect(Rect.fromCenter(center: v - Offset(0, r * 0.2), width: r * 0.16, height: r * 0.36), _outline);
      final f = v - Offset(0, r * 0.58);
      for (final o in const [Offset(-0.14, 0), Offset(0.14, 0), Offset(0, -0.13), Offset(-0.07, 0.1), Offset(0.07, 0.1), Offset(0, 0)]) {
        c.drawCircle(f + Offset(o.dx * r, o.dy * r), r * 0.13, Paint()..color = o == Offset.zero ? const Color(0xFFFFD54F) : const Color(0xFFFF9800));
      }
      c.drawCircle(f, r * 0.3, _outline..strokeWidth = 1);
    }
  }

  /// Ghế bành gỗ lưng cong, 4 chân thanh mảnh choãi ra. [fromBack]: nhìn từ phía sau lưng ghế
  // ---- tiệm bánh: gạch hoa, bàn khăn hồng, ghế gỗ lưng cao
  static ui.Picture? _flowerPic;
  void _flower(Canvas c, Offset ctr, double r) {
    _flowerPic ??= () {
      final rec = ui.PictureRecorder();
      final k = Canvas(rec);
      final ln = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = const Color(0xFFAD1457);
      for (var j = 0; j < 10; j++) {
        k.save();
        k.rotate(j * pi / 5);
        final o = Rect.fromCenter(center: const Offset(0, -5.5), width: 4.4, height: 9);
        k.drawOval(o, Paint()..color = const Color(0xFFF06292));
        k.drawOval(o, ln);
        k.restore();
      }
      for (var j = 0; j < 8; j++) {
        k.save();
        k.rotate(j * pi / 4 + pi / 8);
        final o = Rect.fromCenter(center: const Offset(0, -3.2), width: 3, height: 5.6);
        k.drawOval(o, Paint()..color = const Color(0xFFF8BBD0));
        k.drawOval(o, ln);
        k.restore();
      }
      k.drawCircle(Offset.zero, 2.2, Paint()..color = const Color(0xFFF2C14E));
      return rec.endRecording();
    }();
    c.save();
    c.translate(ctr.dx, ctr.dy);
    c.scale(r / 10, r / 10 * (_th / _tw));
    c.drawPicture(_flowerPic!);
    c.restore();
  }

  void _woodChair(Canvas c, Offset p, double u, bool fromBack) {
    const wood = Color(0xFFB8682F), lite = Color(0xFFE09A5C), dark = Color(0xFF7A3F17);
    final seat = p - Offset(0, u * 0.6);
    final legP = Paint()
      ..color = dark
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final dx in const [-0.38, -0.2, 0.2, 0.38]) {
      c.drawLine(seat + Offset(dx * u, u * 0.1), p + Offset(dx * u * 1.05, dx.abs() < 0.3 ? -u * 0.08 : 0), legP);
    }
    final seatR = RRect.fromRectAndRadius(Rect.fromCenter(center: seat, width: u * 0.95, height: u * 0.38), Radius.circular(u * 0.12));
    final back = RRect.fromRectAndCorners(Rect.fromLTRB(seat.dx - u * 0.42, seat.dy - u * (fromBack ? 0.75 : 1.05), seat.dx + u * 0.42, seat.dy - u * (fromBack ? 0.0 : 0.1)),
        topLeft: Radius.circular(u * 0.3), topRight: Radius.circular(u * 0.3), bottomLeft: Radius.circular(u * 0.05), bottomRight: Radius.circular(u * 0.05));
    final hole = RRect.fromRectAndRadius(Rect.fromLTRB(back.left + u * 0.16, back.top + u * 0.3, back.right - u * 0.16, back.bottom - u * 0.12), Radius.circular(u * 0.05));
    void drawBack() {
      c.drawDRRect(back, hole, Paint()..color = wood);
      c.drawRRect(back, _outline);
      c.drawRRect(hole, _outline);
    }

    if (!fromBack) drawBack();
    c.drawRRect(seatR, Paint()..color = lite);
    c.drawRRect(seatR, _outline);
    if (fromBack) drawBack();
  }

  void _clothTable(Canvas c, Offset g, double hTop, bool glasses) {
    const pink = Color(0xFFE0457B), wood = Color(0xFFB8682F);
    // chân trụ + đế
    final base = _pg(g);
    c.drawOval(Rect.fromCenter(center: base, width: _tw * 0.3, height: _th * 0.2), Paint()..color = wood);
    c.drawOval(Rect.fromCenter(center: base, width: _tw * 0.3, height: _th * 0.2), _outline);
    final col = Rect.fromLTRB(base.dx - _tw * 0.035, _pg(g, hTop).dy, base.dx + _tw * 0.035, base.dy);
    c.drawRect(col, Paint()..color = wood);
    c.drawRect(col, _outline);
    // mặt bàn gỗ vuông
    c.drawPath(_area(g.dx - 0.3, g.dy - 0.3, g.dx + 0.3, g.dy + 0.3, hTop), Paint()..color = wood);
    // khăn hồng xoay chéo, góc rủ xuống
    final n = _pg(g + const Offset(-0.43, 0), hTop + 1),
        e = _pg(g + const Offset(0, -0.43), hTop + 1),
        s2 = _pg(g + const Offset(0.43, 0), hTop + 1),
        w = _pg(g + const Offset(0, 0.43), hTop + 1);
    final drop = Offset(0, _th * 0.45);
    c.drawPath(_poly([s2, s2 + drop, s2 - Offset(_tw * 0.06, 0)]), Paint()..color = _dk(pink, 0.18));
    c.drawPath(_poly([w, w + drop, w + Offset(_tw * 0.06, 0)]), Paint()..color = _dk(pink, 0.1));
    final top = _poly([n, e, s2, w]);
    c.drawPath(top, Paint()..color = pink);
    c.drawPath(top, _outline);
    if (glasses) {
      for (final o in const [Offset(-0.15, 0.12), Offset(0.12, -0.15)]) {
        final gp = _pg(g + o, hTop + 1);
        final gl = _poly([gp + Offset(-_tw * 0.035, 0), gp + Offset(_tw * 0.035, 0), gp + Offset(_tw * 0.05, -_tw * 0.2), gp + Offset(-_tw * 0.05, -_tw * 0.2)]);
        c.drawPath(gl, Paint()..color = const Color(0xFFB2EBF2));
        c.drawPath(gl, _outline);
        c.drawLine(gp + Offset(_tw * 0.01, -_tw * 0.18), gp + Offset(_tw * 0.03, -_tw * 0.3), Paint()
          ..color = _ink
          ..strokeWidth = 1.5);
      }
    }
  }

  // ---- nhà hàng Mexico: gạch talavera, bàn ghế gang xanh hoa văn
  void _talavera(Canvas c, double gx, double gy) {
    const d = 0.17;
    final q = _poly([_p(gx - d, gy), _p(gx, gy - d), _p(gx + d, gy), _p(gx, gy + d)]);
    c.drawPath(q, Paint()..color = const Color(0xFF1B2A6B));
    const e = 0.1;
    c.drawPath(_poly([_p(gx - e, gy), _p(gx, gy - e), _p(gx + e, gy), _p(gx, gy + e)]), Paint()..color = const Color(0xFFF5F0E6));
    final ctr = _p(gx, gy);
    for (final o in [Offset(_tw * 0.035, 0), Offset(-_tw * 0.035, 0), Offset(0, _th * 0.035), Offset(0, -_th * 0.035)]) {
      c.drawCircle(ctr + o, _tw * 0.018, Paint()..color = const Color(0xFF2E7D32));
    }
    c.drawCircle(ctr, _tw * 0.022, Paint()..color = const Color(0xFFF2B01E));
  }

  static const _iron = Color(0xFF1F5E3B), _ironLt = Color(0xFF3C8A5C);
  Paint get _ironLine => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0xFF0E3320);

  void _ironTable(Canvas c, Offset g, double hTop) {
    final top = _pg(g, hTop);
    final base = _pg(g);
    final leg = Paint()
      ..color = _iron
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    // 3 chân cong + mâm dưới
    for (final dx in const [-0.42, 0.0, 0.42]) {
      final b = base + Offset(dx * _tw * 0.55, dx == 0 ? _th * 0.12 : 0);
      final path = Path()
        ..moveTo(top.dx + dx * _tw * 0.3, top.dy + _th * 0.1)
        ..quadraticBezierTo(top.dx + dx * _tw * 0.1, (top.dy + b.dy) / 2, b.dx, b.dy);
      c.drawPath(path, leg);
      c.drawCircle(b, 1.8, Paint()..color = _iron);
    }
    final shelf = Rect.fromCenter(center: Offset.lerp(top, base, 0.55)!, width: _tw * 0.32, height: _th * 0.22);
    c.drawOval(shelf, Paint()..color = _iron);
    c.drawOval(shelf, _ironLine);
    // mặt bàn tròn chạm hoa văn
    final r = Rect.fromCenter(center: top, width: _tw * 0.82, height: _th * 0.82);
    c.drawOval(r.shift(Offset(0, _th * 0.06)), Paint()..color = const Color(0xFF123D26));
    c.drawOval(r, Paint()..color = _iron);
    c.drawOval(r, _ironLine);
    final orn = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _ironLt;
    c.drawOval(r.deflate(_tw * 0.06), orn);
    for (var k = 0; k < 8; k++) {
      final a = k * pi / 4;
      final pt = top + Offset(cos(a) * _tw * 0.22, sin(a) * _th * 0.22);
      c.drawOval(Rect.fromCenter(center: Offset.lerp(top, pt, 0.55)!, width: _tw * 0.1, height: _th * 0.1), orn);
    }
    c.drawCircle(top, _tw * 0.025, Paint()..color = const Color(0xFF0E3320));
  }

  void _ironChair(Canvas c, Offset p, double u, bool fromBack) {
    final seat = p - Offset(0, u * 0.6);
    final leg = Paint()
      ..color = _iron
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final dx in const [-0.4, -0.2, 0.2, 0.4]) {
      final b = p + Offset(dx * u * 1.15, dx.abs() < 0.3 ? -u * 0.08 : 0);
      c.drawPath(Path()
        ..moveTo(seat.dx + dx * u, seat.dy + u * 0.1)
        ..quadraticBezierTo(seat.dx + dx * u * 0.8, (seat.dy + b.dy) / 2, b.dx, b.dy), leg);
    }
    final seatR = Rect.fromCenter(center: seat, width: u * 0.95, height: u * 0.4);
    final back = Rect.fromCenter(center: seat - Offset(0, u * (fromBack ? 0.42 : 0.58)), width: u * 0.72, height: u * (fromBack ? 0.75 : 0.95));
    void drawBack() {
      c.drawOval(back, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _iron);
      final orn = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _ironLt;
      // hoa hướng dương chạm trong lưng ghế
      c.drawCircle(back.center - Offset(0, back.height * 0.12), back.width * 0.16, orn);
      c.drawCircle(back.center + Offset(back.width * 0.12, back.height * 0.18), back.width * 0.11, orn);
      c.drawLine(back.center, back.bottomCenter - Offset(0, 2), orn);
      c.drawOval(back, _ironLine);
    }

    if (!fromBack) drawBack();
    c.drawOval(seatR, Paint()..color = _iron);
    c.drawOval(seatR.deflate(u * 0.08), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _ironLt);
    c.drawOval(seatR, _ironLine);
    // tay vịn uốn
    for (final sd in const [-1.0, 1.0]) {
      c.drawPath(Path()
        ..moveTo(seat.dx + sd * u * 0.36, seat.dy - u * 0.5)
        ..quadraticBezierTo(seat.dx + sd * u * 0.6, seat.dy - u * 0.3, seat.dx + sd * u * 0.45, seat.dy), leg..strokeWidth = 2);
    }
    if (fromBack) drawBack();
  }

  // ---- nhà hàng Trung: gạch bông, bàn gỗ mặt đá, đôn vuông khung gỗ
  static ui.Picture? _tilePic;
  void _encaustic(Canvas c, double gx, double gy) {
    _tilePic ??= () {
      final rec = ui.PictureRecorder();
      final k = Canvas(rec);
      const terra = Color(0xFFC0705A), green = Color(0xFF4F8A78);
      k.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = const Color(0xFFF7F2EA));
      final ln = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = terra;
      // khung vuông góc ở 4 góc (ghép lại thành ô sao)
      for (final o in const [Offset(0, 0), Offset(100, 0), Offset(0, 100), Offset(100, 100)]) {
        k.drawRect(Rect.fromCenter(center: o, width: 36, height: 36), ln);
        k.drawCircle(o, 6, Paint()..color = green);
      }
      // ngôi sao 8 cánh ở giữa
      const ctr = Offset(50, 50);
      for (final a in const [0.0, pi / 4]) {
        k.save();
        k.translate(50, 50);
        k.rotate(a);
        k.drawRect(Rect.fromCenter(center: Offset.zero, width: 34, height: 34), Paint()..color = terra);
        k.restore();
      }
      k.save();
      k.translate(50, 50);
      k.rotate(pi / 4);
      k.drawRect(Rect.fromCenter(center: Offset.zero, width: 20, height: 20), Paint()..color = green);
      k.restore();
      k.drawCircle(ctr, 5, Paint()..color = const Color(0xFFF7F2EA));
      // lá nhỏ + chấm ở giữa cạnh
      final leaf = Paint()..color = terra;
      for (final o in const [Offset(50, 8), Offset(50, 92), Offset(8, 50), Offset(92, 50)]) {
        k.drawOval(Rect.fromCenter(center: o, width: 9, height: 9), leaf);
      }
      for (final o in const [Offset(26, 26), Offset(74, 26), Offset(26, 74), Offset(74, 74)]) {
        k.drawCircle(o, 3, Paint()..color = green);
      }
      return rec.endRecording();
    }();
    final o = _p(gx, gy);
    final a = _tw / 2 / 100, b = _th / 2 / 100;
    c.save();
    c.transform(Float64List.fromList([a, b, 0, 0, -a, b, 0, 0, 0, 0, 1, 0, o.dx, o.dy, 0, 1]));
    c.drawPicture(_tilePic!);
    c.restore();
    c.drawPath(_area(gx, gy, gx + 1, gy + 1), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x33000000));
  }

  static const _walnut = Color(0xFF8A5A3B);
  void _cubeStool(Canvas c, Offset g) {
    const s = 0.16;
    final h = _th * 0.42, thk = _th * 0.08;
    final post = Paint()
      ..color = _dk(_walnut, 0.15)
      ..strokeWidth = 2.6;
    final corners = [Offset(g.dx - s, g.dy - s), Offset(g.dx + s, g.dy - s), Offset(g.dx + s, g.dy + s), Offset(g.dx - s, g.dy + s)];
    for (var k = 0; k < 4; k++) {
      final a = corners[k], b = corners[(k + 1) % 4];
      c.drawLine(_pg(a, _th * 0.05), _pg(b, _th * 0.05), post);
    }
    for (final q in corners) {
      c.drawLine(_pg(q), _pg(q, h - thk), post);
    }
    _box(c, g.dx - s - 0.02, g.dy - s - 0.02, g.dx + s + 0.02, g.dy + s + 0.02, thk, _lt(_walnut, 0.15), z: h - thk);
    c.drawPath(_area(g.dx - s + 0.03, g.dy - s + 0.03, g.dx + s - 0.03, g.dy + s - 0.03, h), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _dk(_walnut, 0.2));
  }

  void _mingTable(Canvas c, Offset g, double hTop, bool teaSet) {
    const s = 0.34;
    final leg = Paint()
      ..color = _dk(_walnut, 0.1)
      ..strokeWidth = 3.2;
    for (final q in [Offset(g.dx - s + 0.04, g.dy - s + 0.04), Offset(g.dx + s - 0.04, g.dy - s + 0.04), Offset(g.dx + s - 0.04, g.dy + s - 0.04), Offset(g.dx - s + 0.04, g.dy + s - 0.04)]) {
      c.drawLine(_pg(q), _pg(q, hTop), leg);
    }
    final thk = _th * 0.14;
    _box(c, g.dx - s, g.dy - s, g.dx + s, g.dy + s, thk, _walnut, z: hTop - thk);
    // mặt đá cẩm thạch
    c.drawPath(_area(g.dx - s + 0.06, g.dy - s + 0.06, g.dx + s - 0.06, g.dy + s - 0.06, hTop), Paint()..color = const Color(0xFFF5F2EC));
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x66A08A6A);
    c.drawPath(Path()
      ..moveTo(_pg(Offset(g.dx - 0.25, g.dy + 0.1), hTop).dx, _pg(Offset(g.dx - 0.25, g.dy + 0.1), hTop).dy)
      ..quadraticBezierTo(_pg(g, hTop).dx, _pg(g, hTop).dy + 3, _pg(Offset(g.dx + 0.22, g.dy - 0.15), hTop).dx, _pg(Offset(g.dx + 0.22, g.dy - 0.15), hTop).dy), vein);
    if (teaSet) {
      final tp = _pg(g, hTop);
      c.drawCircle(tp - Offset(0, _tw * 0.05), _tw * 0.06, Paint()..color = const Color(0xFF2F5F5A));
      c.drawCircle(tp - Offset(0, _tw * 0.115), _tw * 0.015, Paint()..color = const Color(0xFF2F5F5A));
      for (final o in const [Offset(-0.2, 0.0), Offset(0.2, 0.0), Offset(0.0, -0.2), Offset(0.0, 0.2)]) {
        c.drawOval(Rect.fromCenter(center: _pg(g + o, hTop + 1), width: _tw * 0.07, height: _th * 0.06), Paint()..color = const Color(0xFF9ED9C4));
      }
    }
  }

  // ---- xe đồ ăn: ghế đẩu nhựa đỏ kiểu Việt Nam
  void _plasticStool(Canvas c, Offset g) {
    const sb = 0.19, st = 0.145, red = Color(0xFFE8361E);
    final h = _th * 0.5;
    Offset pt(int side, double t, double zf) {
      final s = sb + (st - sb) * zf;
      final double x, y;
      switch (side) {
        case 0:
          x = g.dx - s + 2 * s * t;
          y = g.dy + s;
          break;
        case 1:
          x = g.dx + s;
          y = g.dy + s - 2 * s * t;
          break;
        case 2:
          x = g.dx - s;
          y = g.dy - s + 2 * s * t;
          break;
        default:
          x = g.dx - s + 2 * s * t;
          y = g.dy - s;
      }
      return _p(x, y, h * zf);
    }

    Path quad(int sd, double t0, double t1, double z0, double z1) => _poly([pt(sd, t0, z0), pt(sd, t1, z0), pt(sd, t1, z1), pt(sd, t0, z1)]);
    Path face(int sd) => Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(quad(sd, 0, 1, 0, 1), Offset.zero)
      ..addPath(quad(sd, 0.2, 0.8, 0.3, 0.76), Offset.zero)
      ..addPath(quad(sd, 0.17, 0.83, 0, 0.17), Offset.zero);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF8E1A0C);
    for (final sd in const [3, 2]) {
      c.drawPath(face(sd), Paint()..color = _dk(red, 0.35));
    }
    c.drawPath(face(0), Paint()..color = _dk(red, 0.12));
    c.drawPath(face(0), edge);
    c.drawPath(face(1), Paint()..color = red);
    c.drawPath(face(1), edge);
    // mặt ngồi có vân lỗ
    final top = _poly([pt(3, 0, 1), pt(3, 1, 1), pt(0, 1, 1), pt(0, 0, 1)]);
    c.drawPath(top, Paint()..color = _lt(red, 0.12));
    c.drawPath(top, edge);
    final ins = _area(g.dx - st + 0.04, g.dy - st + 0.04, g.dx + st - 0.04, g.dy + st - 0.04, h);
    c.drawPath(ins, Paint()..color = _dk(red, 0.06));
    final dot = Paint()..color = _dk(red, 0.25);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        c.drawCircle(_p(g.dx - 0.06 + i * 0.06, g.dy - 0.06 + j * 0.06, h), 0.9, dot);
      }
    }
    // bóng nhựa
    c.drawLine(pt(1, 0.1, 0.85), pt(1, 0.9, 0.85), Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.2);
  }

  void _tubChair(Canvas c, Offset p, double u, bool fromBack) {
    const shell = Color(0xFFB9774A), inner = Color(0xFF6D3B22), cushion = Color(0xFFD99A66), leg = Color(0xFFE8B98A);
    final seat = p - Offset(0, u * 0.62);
    // chân ghế
    for (final dx in const [-0.36, -0.14, 0.14, 0.36]) {
      final top = seat + Offset(dx * u * 0.8, u * 0.12);
      final bot = p + Offset(dx * u * 1.25, (dx.abs() < 0.2 ? -0.06 : 0.04) * u);
      c.drawLine(top, bot, Paint()
        ..color = _ink
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round);
      c.drawLine(top, bot, Paint()
        ..color = leg
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round);
    }
    final seatR = Rect.fromCenter(center: seat, width: u * 0.95, height: u * 0.36);
    final back = RRect.fromRectAndCorners(
      Rect.fromLTRB(seat.dx - u * 0.5, seat.dy - u * 0.62, seat.dx + u * 0.5, seat.dy + u * 0.08),
      topLeft: Radius.circular(u * 0.32),
      topRight: Radius.circular(u * 0.32),
      bottomLeft: Radius.circular(u * 0.12),
      bottomRight: Radius.circular(u * 0.12),
    );
    if (fromBack) {
      // nhìn từ sau: thấy mặt ngoài lưng ghế che phần đệm
      c.drawOval(seatR, Paint()..color = cushion);
      c.drawOval(seatR, _outline);
      c.drawRRect(back, Paint()..color = const Color(0xFFD9A273));
      c.drawRRect(back, _outline);
      c.drawRRect(back.deflate(u * 0.08), Paint()..color = shell);
    } else {
      // nhìn từ trước: lưng ghế phía sau, lòng ghế tối, đệm ngồi sáng
      c.drawRRect(back, Paint()..color = shell);
      c.drawRRect(back, _outline);
      c.drawRRect(back.deflate(u * 0.1), Paint()..color = inner);
      c.drawOval(seatR, Paint()..color = cushion);
      c.drawOval(seatR, _outline);
      // tay vịn cong
      for (final sd in const [-1.0, 1.0]) {
        c.drawLine(seat + Offset(sd * u * 0.46, -u * 0.36), seat + Offset(sd * u * 0.44, u * 0.06), Paint()
          ..color = shell
          ..strokeWidth = u * 0.12
          ..strokeCap = StrokeCap.round);
      }
    }
  }

  void _drawTable(Canvas c, int i, double t, VTheme th) {
    final tb = widget.tables[i];
    final g = _table(i);
    final cu = tb.c;
    final kind = _plan.table;
    final seated = cu != null && t >= _seatAt[i];
    // ghế / ghế băng phía sau (khách ngồi ở đây)
    final sg = _seat(i);
    if (kind == 'booth') {
      _box(c, sg.dx - 0.4, sg.dy - 0.18, sg.dx + 0.26, sg.dy + 0.26, _th * 0.5, _dk(th.accent, 0.05));
    } else if (kind == 'mat') {
      _box(c, g.dx - 0.58, g.dy - 0.58, g.dx + 0.58, g.dy + 0.58, 3, const Color(0xFFD9B77A)); // chiếu tre
    } else if (kind == 'round') {
      _tubChair(c, _pg(sg), _tw * 0.42, false);
    } else if (kind == 'cloth') {
      _woodChair(c, _pg(sg), _tw * 0.42, false);
    } else if (kind == 'iron') {
      _ironChair(c, _pg(sg), _tw * 0.42, false);
    } else if (kind == 'ming') {
      _cubeStool(c, sg);
    } else if (kind == 'plastic') {
      _plasticStool(c, sg);
    } else {
      _box(c, sg.dx - 0.15, sg.dy - 0.15, sg.dx + 0.15, sg.dy + 0.15, _th * 0.4, _lt(th.wood, 0.1));
    }
    if (cu != null && seated) {
      final frac = (cu.pat / cu.maxPat).clamp(0.0, 1.0);
      final mood = cu.st == 2 ? 0 : (frac < 0.35 ? 2 : (frac < 0.6 ? 1 : 0));
      final brawl = widget.incidents.any((x) => x.type == 'brawl' && x.target == i);
      final justServed = t - _serveAt[i] < 0.6;
      drawPerson(
        c,
        _pg(sg) + Offset(brawl ? sin(t * 40) * 2 : 0, -_th * 0.078),
        (cu.npc == 'student' ? 0.72 : 0.86) * _tw,
        custLook(cu.npc, _seed[i]),
        sitting: true,
        mood: brawl ? 2 : mood,
        armUp: cu.st == 0 || justServed || (brawl && sin(t * 8) > 0),
        chew: cu.st == 2 && !justServed && sin(t * 12) > 0,
        bob: cu.st == 0 ? sin(t * 6).abs() * 2 : 0.0,
      );
    }
    // mặt bàn theo kiểu quán
    final glow = cu != null && cu.st == 1 && widget.selDishId != null && widget.selDishId == cu.ticketId;
    final hTop = kind == 'mat' ? _th * 0.351 : (kind == 'plastic' ? _th * 0.52 : _th * 0.663);
    switch (kind) {
      case 'round':
        _roundTable(c, g, hTop, cu == null && !tb.dirty);
        break;
      case 'cloth':
        _clothTable(c, g, hTop, cu == null && !tb.dirty);
        break;
      case 'iron':
        _ironTable(c, g, hTop);
        break;
      case 'ming':
        _mingTable(c, g, hTop, cu == null && !tb.dirty);
        break;
      case 'plastic':
        _box(c, g.dx - 0.3, g.dy - 0.3, g.dx + 0.3, g.dy + 0.3, hTop, const Color(0xFF5AA9E6));
        break;
      case 'square':
        _box(c, g.dx - 0.34, g.dy - 0.34, g.dx + 0.34, g.dy + 0.34, hTop, th.cloth);
        // mâm xoay
        c.drawOval(Rect.fromCenter(center: _pg(g, hTop + 1), width: _tw * 0.351, height: _th * 0.351), Paint()..color = _a(th.accent, 0.5));
        break;
      case 'grill':
        _box(c, g.dx - 0.38, g.dy - 0.34, g.dx + 0.38, g.dy + 0.34, hTop, const Color(0xFF5D4037));
        final p = _pg(g, hTop + 1);
        c.drawOval(Rect.fromCenter(center: p, width: _tw * 0.351, height: _th * 0.351), Paint()..color = const Color(0xFF212121));
        c.drawOval(Rect.fromCenter(center: p, width: _tw * 0.273, height: _th * 0.257), Paint()..color = cu != null && seated ? const Color(0xFFFF7043) : const Color(0xFF424242));
        if (cu != null && seated && cu.st == 2) {
          for (var k = 0; k < 2; k++) {
            final ph = (t * 0.7 + k * 0.5 + i * 0.3) % 1.0;
            c.drawCircle(p - Offset(0, ph * _tw * 0.468), _tw * (0.05 + 0.07 * ph), Paint()..color = _a(const Color(0xFFBDBDBD), 0.6 * (1 - ph)));
          }
        }
        break;
      case 'booth':
        _box(c, g.dx - 0.3, g.dy - 0.38, g.dx + 0.3, g.dy + 0.38, hTop, th.cloth);
        break;
      case 'mat':
        _box(c, g.dx - 0.34, g.dy - 0.34, g.dx + 0.34, g.dy + 0.34, hTop, const Color(0xFF8D6E3F));
        break;
    }
    final topC = _pg(g, hTop + 2);
    if (glow) {
      c.drawOval(Rect.fromCenter(center: topC, width: _tw * (1.2 + 0.1 * sin(t * 8)), height: _th * 0.936), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF00E676));
    }
    if (tb.dirty) {
      _emoji(c, '🍽️', topC - const Offset(0, 4), _tw * 0.25);
    } else if (cu != null && seated && cu.st == 2) {
      final ks = t - _serveAt[i];
      final pop = ks < 0.45 ? 1 + 0.5 * sin(ks / 0.45 * pi) : 1.0;
      drawDish(c, cu.recipe.id, topC - Offset(0, _tw * 0.094 * pop), _tw * 0.468 * pop, t: t);
    }
    if (kind == 'round') _tubChair(c, _pg(g + const Offset(0.42, 0.42)), _tw * 0.42, true);
    if (kind == 'cloth') _woodChair(c, _pg(g + const Offset(0.42, 0.42)), _tw * 0.42, true);
    if (kind == 'plastic') _plasticStool(c, g + const Offset(0.42, 0.42));
    if (kind == 'ming') _cubeStool(c, g + const Offset(0.42, 0.42));
    if (kind == 'iron') _ironChair(c, _pg(g + const Offset(0.42, 0.42)), _tw * 0.42, true);
    final lab = _text('${i + 1}', max(8.0, _tw * 0.133), color: _dk(th.wood, 0.4), bold: true);
    lab.paint(c, _pg(g + const Offset(0.55, 0.55), 2) - Offset(lab.width / 2, lab.height / 2));
  }

  void _drawOverlay(Canvas c, int i, double t) {
    final tb = widget.tables[i];
    final cu = tb.c;
    final head = _pg(_seat(i), _tw * 0.95);
    final r = _tw * 0.328;
    final kc = t - _cleanAt[i];
    if (kc >= 0 && kc < 0.9) {
      for (var j = 0; j < 5; j++) {
        final ang = j * pi * 0.4 + kc * 2;
        _emoji(c, '✨', _pg(_table(i), _th) + Offset(cos(ang), sin(ang) * 0.6) * (_tw * (0.3 + kc * 0.6)), _tw * 0.172, alpha: 1 - kc / 0.9);
      }
    }
    if (tb.dirty) {
      final bc = _pg(_table(i), _tw * 0.858) + Offset(0, -sin(t * 5).abs() * 3);
      _bubble(c, bc, r * 1.6, r * 1.4, Colors.white);
      _emoji(c, '🧹', bc, r);
      return;
    }
    if (cu == null || t < _seatAt[i]) return;
    final npc = npcById(cu.npc);
    if (npc != null) {
      _pill(c, '${npc.emoji} ${npc.name}', head - Offset(0, r * 2.2), max(9.0, _tw * 0.14), bg: const Color(0xFFFFF8E1), fg: const Color(0xFF6D4C41));
      if (t - _seatAt[i] < 4.5) {
        _speech(c, npc.lines[min(cu.line, npc.lines.length - 1)], head - Offset(0, r * 2.9), max(130.0, _tw * 2.496), max(10.0, _tw * 0.156));
      }
    }
    if (cu.st == 2) {
      final ks = t - _serveAt[i];
      if (ks >= 0 && ks < 1.3) {
        final bc = head + Offset(_tw * 0.351, -ks * 6);
        _bubble(c, bc, r * 1.7, r * 1.45, Colors.white);
        _emoji(c, '😋', bc, r);
      }
      return;
    }
    final frac = (cu.pat / cu.maxPat).clamp(0.0, 1.0).toDouble();
    final sel = widget.selDishId != null && widget.selDishId == cu.ticketId;
    final bounce = cu.st == 0 ? sin(t * 7).abs() * 3 : 0.0;
    final bc = head + Offset(_tw * 0.351, -bounce);
    final bw = r * 1.9, bh = r * 1.6;
    _bubble(c, bc, bw, bh, sel ? const Color(0xFFC8E6C9) : Colors.white, border: sel ? Colors.green : null);
    if (cu.st == 0 && !widget.buffet) {
      _emoji(c, '❗', bc, r);
    } else {
      drawDish(c, cu.recipe.id, bc, r * 1.5);
      if (widget.buffet) _emoji(c, '🍱', bc + Offset(r * 0.8, -r * 0.6), r * 0.6);
    }
    final bar = Rect.fromLTWH(bc.dx - bw / 2, bc.dy + bh / 2 + 3, bw, 4);
    c.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = const Color(0x55000000));
    final col = frac < 0.35 ? const Color(0xFFFF5252) : (frac < 0.6 ? const Color(0xFFFF9800) : const Color(0xFF8BC34A));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, bar.width * frac, bar.height), const Radius.circular(2)), Paint()..color = col);
    final brawl = widget.incidents.where((x) => x.type == 'brawl' && x.target == i);
    if (brawl.isNotEmpty) {
      _emoji(c, '💢', head + Offset(-_tw * 0.273, -_tw * 0.078), _tw * 0.234);
      _pill(c, '🍵×${brawl.first.hp}', _pg(_table(i), 0) + Offset(0, _th * 0.468), max(9.0, _tw * 0.14), bg: const Color(0xFFFFEBEE), fg: const Color(0xFFC62828));
    }
  }

  void _drawPet(Canvas c, String id, Offset g, double t) {
    final pt = petById(id);
    final p = _pg(g);
    final size = _tw * (id == 'dog' ? 0.55 : (id == 'cat' ? 0.48 : 0.4));
    c.drawOval(Rect.fromCenter(center: p, width: size * 0.9, height: size * 0.25), Paint()..color = const Color(0x22000000));
    if (id == 'parrot') {
      c.drawLine(p, p - Offset(0, _tw * 0.468), Paint()
        ..color = const Color(0xFF6D4C41)
        ..strokeWidth = 3);
      _emoji(c, pt.emoji, p - Offset(0, _tw * 0.585 + sin(t * 3).abs() * 3), size);
    } else if (id == 'hamster') {
      final cage = Rect.fromCenter(center: p - Offset(0, _th * 1.014), width: _tw * 0.351, height: _tw * 0.273);
      c.drawRRect(RRect.fromRectAndRadius(cage, const Radius.circular(4)), Paint()..color = const Color(0x55FFFFFF));
      c.drawRRect(
        RRect.fromRectAndRadius(cage, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF90A4AE),
      );
      _emoji(c, pt.emoji, cage.center - Offset(0, sin(t * 16).abs() * 2), size);
    } else {
      final dir = cos(t * 0.17 + widget.pets.indexOf(id) * 2.1);
      c.save();
      c.translate(p.dx, p.dy - size * 0.35 - sin(t * 12).abs() * 1.5);
      if (dir > 0) c.scale(-1, 1);
      _emoji(c, pt.emoji, Offset.zero, size);
      c.restore();
    }
    final kh = t - (_petHeart[id] ?? -10);
    if (kh < 1.2) _emoji(c, '💗', p - Offset(0, size * (1 + kh)), size * 0.5, alpha: 1 - kh / 1.2);
  }

  void _drawFloorIncident(Canvas c, Incident x, double t) {
    final it = incidentType(x.type);
    final p = _pg(_incGrid(x));
    final fs = max(9.0, _tw * 0.18);
    if (x.type == 'rat') {
      c.save();
      c.translate(p.dx, p.dy - _tw * 0.15 - sin(t * 20).abs() * 2);
      if (sin(t * 0.8 + x.id) > 0) c.scale(-1, 1);
      _emoji(c, '🐀', Offset.zero, _tw * 0.42);
      c.restore();
      _pill(c, '${it.toolEmoji}×${x.hp}', p - Offset(0, _tw * 0.55), fs, bg: const Color(0xFFFFEBEE), fg: const Color(0xFFC62828));
    } else {
      final grow = min(x.age, 20.0) * 0.05;
      c.drawOval(Rect.fromCenter(center: p, width: _tw * (0.9 + grow), height: _th * (0.7 + grow * 0.5)), Paint()..color = _a(const Color(0xFF4FC3F7), 0.6));
      c.drawOval(Rect.fromCenter(center: p - Offset(_tw * 0.1, 2), width: _tw * 0.25, height: _th * 0.15), Paint()..color = _a(Colors.white, 0.5));
      final ph = (t * 1.2) % 1.0;
      c.drawCircle(p - Offset(0, _tw * (1 - ph)), 2.5, Paint()..color = _a(const Color(0xFF0288D1), 0.8));
      _pill(c, '💧 ${it.toolEmoji}×${x.hp}', p - Offset(0, _tw * 0.5), fs, bg: const Color(0xFFE1F5FE), fg: const Color(0xFF01579B));
    }
  }

  void _drawLight(Canvas c, Size sz, double t) {
    final all = Offset.zero & sz;
    switch (widget.light) {
      case 'warm':
        c.drawRect(all, Paint()..color = const Color(0x22FFA726));
        break;
      case 'romantic':
        c.drawRect(all, Paint()..color = const Color(0x332A0A3A));
        for (var i = 0; i < widget.tables.length; i++) {
          c.drawCircle(_pg(_table(i), _th), _tw * 0.9, Paint()..color = _a(const Color(0xFFFFCC80), 0.12 + 0.04 * sin(t * 3 + i)));
        }
        break;
      case 'disco':
        const cols = [Color(0xFFFF4081), Color(0xFF40C4FF), Color(0xFFFFEB3B), Color(0xFF69F0AE)];
        for (var k = 0; k < 4; k++) {
          final g = _uv(7 + 2.5 * sin(t * 0.7 + k * 2.3), 2.4 * sin(t * 0.9 + k * 1.7));
          c.drawCircle(_pg(g), _tw * 0.92, Paint()..color = _a(cols[k], 0.16));
        }
        break;
    }
    // trời tối thì trong quán ấm hơn một chút
    if (realDayPhase() == 2) c.drawRect(all, Paint()..color = const Color(0x18000033));
  }
}

class _IsoPainter extends CustomPainter {
  final _IsoRoomState st;
  _IsoPainter(this.st) : super(repaint: st._clock);
  @override
  void paint(Canvas canvas, Size size) => st._paint(canvas, size);
  @override
  bool shouldRepaint(covariant _IsoPainter oldDelegate) => true;
}
