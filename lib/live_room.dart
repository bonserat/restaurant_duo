// Xem trực tiếp nhà hàng riêng đang tự vận hành: nhân viên thuê nấu/phục vụ,
// lượng khách theo con số thật của quán lúc đó, cùng các hoạt động sinh hoạt vui
// (sinh nhật, tiệc, mua bàn ghế mới, đặt hàng, diệt chuột, phát tờ rơi...).
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'data.dart';
import 'models.dart';
import 'scene.dart';

/// (id, emoji, câu mô tả: {c} = đầu bếp, {w} = phục vụ, {t} = số bàn)
const bizActivities = [
  ('birthday', '🎂', 'Đang tổ chức sinh nhật cho khách bàn {t}'),
  ('party', '🎉', 'Tiệc công ty đặt kín quán, nhạc xập xình'),
  ('furniture', '🪑', 'Quán vừa mua thêm bộ bàn ghế mới'),
  ('order', '📦', '{c} đang gọi điện đặt thêm nguyên liệu'),
  ('rat', '🐭', 'Tạp vụ đang đuổi chuột trong quán'),
  ('ads', '📣', '{w} đang phát tờ rơi mời khách ngoài cửa'),
  ('music', '🎸', 'Nhóm nhạc đường phố ghé hát tặng khách'),
  ('clean', '🧽', 'Nhân viên đang lau dọn bàn ghế sạch bong'),
];

int _h(String s) {
  var h = 2166136261;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 16777619) & 0x7fffffff;
  }
  return h;
}

/// Hoạt động đang diễn ra (đổi mỗi 20 phút, giống nhau trên mọi máy)
int bizActivityAt(String owner, DateTime d) => _h('$owner-${d.year}-${d.month}-${d.day}-${d.hour}-${d.minute ~/ 20}') % bizActivities.length;

class LiveBizRoom extends StatefulWidget {
  final String venueId, owner, chefName, waiterName;
  final int tables; // số bàn của quán
  final int target; // số bàn có khách lúc này (theo lượng khách thật)
  final bool open;
  final bool buffet;
  final List<String> menu; // món của quán
  final String status; // dòng trạng thái: số khách, khách/giờ
  final String? event; // sự kiện trong ngày đang diễn ra
  const LiveBizRoom({
    super.key,
    required this.venueId,
    required this.owner,
    required this.chefName,
    required this.waiterName,
    required this.tables,
    required this.target,
    required this.open,
    required this.buffet,
    required this.menu,
    required this.status,
    this.event,
  });
  @override
  State<LiveBizRoom> createState() => _LiveBizRoomState();
}

class _LiveBizRoomState extends State<LiveBizRoom> {
  final rnd = Random();
  late List<TableS> tables;
  final stations = [Station(), Station()];
  final Map<int, double> _wait = {}; // thời gian còn lại của trạng thái hiện tại theo bàn
  final List<Incident> incidents = [];
  final List<OutsideGuest> outside = [];
  Timer? _timer;
  double _ph = 0;
  int _seq = 0;
  int _act = 0;

  int get _nTables => widget.tables + (bizActivities[_act].$1 == 'furniture' ? 1 : 0);
  int get _want {
    if (!widget.open) return 0;
    final a = bizActivities[_act].$1;
    if (a == 'party') return _nTables;
    if (a == 'birthday') return max(widget.target, 2);
    return min(widget.target, _nTables);
  }

  @override
  void initState() {
    super.initState();
    _act = bizActivityAt(widget.owner, DateTime.now());
    tables = List.generate(_nTables, (_) => TableS());
    // vào xem là thấy quán đang có khách ngay
    for (var i = 0; i < min(_want, tables.length); i++) {
      _seat(i, st: 2 - (i % 3 == 2 ? 1 : 0));
    }
    _setupActivity();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick(0.25));
  }

  void _setupActivity() {
    incidents.clear();
    outside.clear();
    if (!widget.open) return;
    switch (bizActivities[_act].$1) {
      case 'rat':
        incidents.add(Incident(1, 'rat', -1, 0.4, 0.55, 2));
        break;
      case 'ads':
        for (var k = 0; k < 3; k++) {
          outside.add(OutsideGuest(60, 100 + k * 17));
        }
        break;
    }
  }

  void _seat(int i, {int st = 0}) {
    if (widget.menu.isEmpty) return;
    final r = recipeById(widget.menu[rnd.nextInt(widget.menu.length)]);
    final c = Cust(r, 60);
    c.st = st;
    c.ticketId = ++_seq;
    tables[i].c = c;
    tables[i].dirty = false;
    _wait[i] = st == 2 ? 4 + rnd.nextDouble() * 6 : 1.5 + rnd.nextDouble() * 2;
    if (st == 1) _cook(i, c);
  }

  void _cook(int i, Cust c) {
    for (final s in stations) {
      if (s.t == null) {
        s.t = Ticket(c.ticketId, i, c.recipe);
        s.added = {...c.recipe.ings};
        s.need = 4;
        s.prog = 0;
        s.heat = 0.55;
        return;
      }
    }
  }

  void _tick(double dt) {
    if (!mounted) return;
    _ph += dt;
    final now = bizActivityAt(widget.owner, DateTime.now());
    if (now != _act) {
      _act = now;
      _setupActivity();
    }
    while (tables.length < _nTables) {
      tables.add(TableS());
    }
    // chuột chạy quanh, phát tờ rơi thì khách ngoài cửa lần lượt vào
    for (final x in incidents) {
      x.x = 0.5 + 0.35 * sin(_ph * 0.9);
      x.y = 0.5 + 0.25 * cos(_ph * 0.7);
    }
    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      final c = t.c;
      _wait[i] = (_wait[i] ?? 0) - dt;
      if (c == null) {
        if (t.dirty) {
          t.dirtyT += dt;
          if (t.dirtyT > 2.5) {
            t.dirty = false;
            t.dirtyT = 0;
          }
        }
        continue;
      }
      if (_wait[i]! > 0) continue;
      if (c.st == 0) {
        if (widget.buffet) {
          c.st = 2;
          _wait[i] = 7 + rnd.nextDouble() * 6;
        } else {
          c.st = 1;
          _cook(i, c);
          _wait[i] = 99;
        }
      } else if (c.st == 2) {
        t.c = null;
        t.dirty = true;
        t.dirtyT = 0;
      }
    }
    // bếp nấu xong thì phục vụ mang ra bàn
    for (final s in stations) {
      final tk = s.t;
      if (tk == null) continue;
      s.prog += dt;
      if (s.prog >= s.need) {
        final c = tk.table < tables.length ? tables[tk.table].c : null;
        if (c != null && c.ticketId == tk.id) {
          c.st = 2;
          _wait[tk.table] = 6 + rnd.nextDouble() * 6;
        }
        s.clear();
      }
    }
    // khách đi đơn đã chờ nấu mà bếp còn trống
    for (var i = 0; i < tables.length; i++) {
      final c = tables[i].c;
      if (c != null && c.st == 1 && !stations.any((s) => s.t?.id == c.ticketId)) _cook(i, c);
    }
    // khách mới vào cho đủ lượng khách thật của quán
    final occ = tables.where((t) => t.c != null).length;
    if (occ < _want && rnd.nextDouble() < 0.12) {
      final free = [for (var i = 0; i < tables.length; i++) if (tables[i].c == null && !tables[i].dirty) i];
      if (free.isNotEmpty) {
        _seat(free[rnd.nextInt(free.length)]);
        if (outside.isNotEmpty) outside.removeAt(0);
        if (bizActivities[_act].$1 == 'ads' && outside.length < 2) outside.add(OutsideGuest(60, rnd.nextInt(999)));
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _text() {
    final a = bizActivities[_act];
    final busy = [for (var i = 0; i < tables.length; i++) if (tables[i].c != null) i + 1];
    final tb = busy.isEmpty ? 1 : busy.first;
    return '${a.$2} ${a.$3.replaceAll('{c}', widget.chefName).replaceAll('{w}', widget.waiterName).replaceAll('{t}', '$tb')}';
  }

  Widget _float(String e, double ax, double ay, double size, double sp, double amp) => Align(
        alignment: Alignment(ax + 0.03 * sin(_ph * sp), ay + amp * sin(_ph * sp + ax * 3)),
        child: Text(e, style: TextStyle(fontSize: size)),
      );

  List<Widget> _fx() {
    if (!widget.open) return const [];
    switch (bizActivities[_act].$1) {
      case 'birthday':
        return [_float('🎈', -0.55, -0.1, 26, 1.6, 0.05), _float('🎈', -0.35, -0.2, 22, 1.9, 0.06), _float('🎂', -0.45, 0.25, 26, 3, 0.01), _float('🥳', -0.2, 0.15, 20, 2.4, 0.03)];
      case 'party':
        return [for (var k = 0; k < 6; k++) _float(k.isEven ? '🎉' : '🎊', -0.8 + k * 0.32, -0.3 + 0.12 * ((k * 7) % 3), 20, 1.5 + k * 0.3, 0.08), _float('🪩', 0.1, -0.45, 26, 1, 0.02)];
      case 'furniture':
        return [_float('✨', 0.55, 0.45, 22, 2.5, 0.04), _float('🪑', 0.62, 0.55, 20, 1.5, 0.02), _float('🆕', 0.75, 0.38, 18, 2, 0.03)];
      case 'order':
        return [_float('📞', -0.7, -0.55, 22, 2.8, 0.03), _float('📦', -0.5, -0.4, 22, 1.4, 0.02), _float('🚚', 0.85, 0.85, 22, 1, 0.01)];
      case 'rat':
        return [_float('🧹', 0.1 + 0.35 * sin(_ph * 0.9) * 0.9, 0.35, 24, 6, 0.03), _float('💨', 0.25, 0.3, 16, 4, 0.05)];
      case 'ads':
        return [_float('📣', 0.05, 0.8, 26, 3, 0.02), _float('📄', -0.15, 0.7, 18, 2, 0.06), _float('📄', 0.25, 0.75, 18, 2.6, 0.06)];
      case 'music':
        return [_float('🎸', 0.6, 0.6, 26, 2, 0.02), _float('🎵', 0.5, 0.35, 18, 2.5, 0.08), _float('🎶', 0.72, 0.3, 18, 3, 0.08)];
      case 'clean':
        return [_float('✨', -0.3, 0.3, 20, 3, 0.05), _float('🧽', 0.2, 0.45, 20, 4, 0.03), _float('✨', 0.4, 0.2, 16, 2, 0.05)];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final chip = BoxDecoration(color: Colors.white.withAlpha(235), borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)]);
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: IsoRoom(
            tables: tables,
            stations: stations,
            counter: const [],
            selDishId: null,
            activeStation: -1,
            hasOrders: false,
            venueId: widget.venueId,
            waiterLook: castLook(widget.waiterName, 'waiter'),
            chefLook: castLook(widget.chefName, 'chef'),
            waiterName: widget.waiterName,
            chefName: widget.chefName,
            incidents: incidents,
            outside: outside,
            buffet: widget.buffet,
            trays: widget.buffet ? [for (final id in widget.menu.take(4)) (id, 6)] : const [],
            chef2Look: castLook(widget.waiterName, 'chef'),
            onTable: (_) {},
            onDish: (_) {},
            onStation: (_) {},
            onHeat: (_, __) {},
            onIncident: (_) {},
            onPet: (_) {},
          ),
        ),
      ),
      ..._fx(),
      Positioned(
        left: 8,
        right: 8,
        top: 8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: chip,
            child: Text('🔴 Trực tiếp • ${widget.status}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF221B3F))),
          ),
          if (widget.open) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: chip,
              child: Text(_text(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF221B3F))),
            ),
          ],
          if (widget.event != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: chip.copyWith(color: const Color(0xFFFFF3CD)),
              child: Text(widget.event!, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF5D4037))),
            ),
          ],
        ]),
      ),
    ]);
  }
}
