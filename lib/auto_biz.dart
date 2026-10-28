// Kinh doanh tự động cho nhà hàng riêng: thuê nhân viên, quán tự mở cửa 8h–22h theo giờ thật,
// tiền vào két, hàng hoá tiêu hao, tinh thần nhân viên, vệ sinh, sự kiện bất ngờ mỗi ngày.
import 'dart:math';
import 'garden_engine.dart' show hash01;

/// Vị trí nhân viên: (id, emoji, tên, giá thuê mỗi cấp, lương/giờ mỗi cấp, cấp tối đa, mô tả)
const staffTypes = [
  ('chef', '🧑‍🍳', 'Đầu bếp', 300, 6, 5, 'Mỗi cấp nấu thêm 5 khách/giờ'),
  ('waiter', '🧑‍💼', 'Phục vụ', 250, 5, 5, 'Mỗi cấp phục vụ thêm 6 khách/giờ'),
  ('manager', '👔', 'Quản lý', 600, 10, 3, 'Két chứa nhiều hơn, nhân viên đỡ chán, cấp 2 tự nhập hàng'),
  ('cleaner', '🧹', 'Tạp vụ', 150, 4, 3, 'Quán bẩn chậm hơn'),
];

/// Sự kiện trong ngày: (id, emoji, tên, mô tả, hệ số khách, hệ số phục vụ, số giờ, đóng cửa)
const bizEvents = [
  ('tour', '🚌', 'Đoàn khách du lịch', 'Một xe khách du lịch ghé quán, khách gấp đôi', 2.0, 1.0, 3, false),
  ('kol', '📸', 'KOL quay video review', 'Một người nổi tiếng quay clip ở quán, khách tăng mạnh', 1.6, 1.0, 6, false),
  ('sick', '🤒', 'Nhân viên ốm', 'Một nhân viên xin nghỉ ốm, phục vụ chậm một nửa', 1.0, 0.5, 6, false),
  ('price', '📈', 'Giá thực phẩm tăng', 'Hôm nay nhập hàng đắt gấp rưỡi', 1.0, 1.0, 14, false),
  ('power', '⚡', 'Mất điện khu phố', 'Quán phải đóng cửa 2 tiếng', 1.0, 1.0, 2, true),
  ('inspect', '🧪', 'Kiểm tra vệ sinh ATTP', 'Đoàn kiểm tra ghé: quán bẩn sẽ bị phạt', 1.0, 1.0, 1, false),
  ('festival', '🎉', 'Phố đi bộ mở lễ hội', 'Đường Hoà Xuân đông nghịt người', 1.5, 1.0, 5, false),
  ('rival', '🏪', 'Quán đối thủ khai trương', 'Quán mới gần đó giảm giá 50%, khách vơi đi', 0.7, 1.0, 8, false),
  ('raise', '💬', 'Nhân viên xin tăng lương', 'Cả quán đề nghị tăng 10% lương, bạn quyết định nhé', 1.0, 1.0, 14, false),
  ('review', '⭐', 'Đánh giá 5 sao', 'Một khách viết bài khen quán, nhân viên phấn khởi', 1.2, 1.0, 6, false),
];

/// Tính cách nhân viên: (id, nhãn, ×phục vụ, ×tiền, ×bẩn, ×chán)
const staffTraits = [
  ('cham', '💪 Chăm chỉ', 1.10, 1.0, 1.0, 1.0),
  ('muon', '⏰ Hay đi muộn', 0.88, 1.0, 1.0, 0.9),
  ('kheo', '😄 Khéo ăn nói', 1.0, 1.10, 1.0, 1.0),
  ('vung', '🫣 Hơi vụng về', 1.0, 1.0, 1.3, 1.0),
  ('nhanh', '⚡ Nhanh nhẹn', 1.15, 1.0, 1.0, 1.2),
  ('vui', '🎶 Vui tính', 1.0, 1.05, 1.0, 0.7),
];

const staffNames = ['Tuấn', 'Lan', 'Hùng', 'Mai', 'Phúc', 'Thảo', 'Khoa', 'Vy', 'Minh', 'Hà', 'Long', 'Trang', 'Quân', 'Ngân', 'Bảo', 'Yến'];

/// Món hợp thời tiết: món nóng (lẩu, canh, nướng) đắt khách khi mưa/lạnh; món tươi mát khi nắng nóng
bool dishIsWarm(String id) => ['lau', 'kimchi', 'galbi', 'bachi', 'chim', 'heo', 'suon', 'mi_xao', 'ha_cao'].any(id.contains);
bool dishIsFresh(String id) => ['hau', 'tom', 'cua', 'melon', 'mango', 'dragon', 'cf_da', 'tra', 'sinh'].any(id.contains);

class Biz {
  // ---- nhân viên có tên, tính cách, tay nghề (giờ làm)
  Map<String, Map<String, dynamic>> emp = {};
  // ---- món chủ lực của tuần
  String featured = '';
  int featuredWeek = 0;
  // ---- nguyên liệu từ vườn (bán đắt hơn), số lần thu hoạch đã lấy
  double farm = 0;
  int farmClaimed = 0;
  // ---- khách quen, doanh thu tuần (thi với quán người kia)
  double regulars = 0;
  int week = 0;
  double weekRev = 0, lastWeekRev = 0;
  int prizeWeek = 0;

  static int weekOf(DateTime d) => d.difference(DateTime(2026, 1, 5)).inDays ~/ 7;

  /// Tạo hồ sơ cho nhân viên mới thuê
  void hire(String role, Random r) {
    emp[role] ??= {'n': staffNames[r.nextInt(staffNames.length)], 't': r.nextInt(staffTraits.length), 'xp': 0.0};
  }

  (String, String, int)? person(String role) {
    final e = emp[role];
    if (e == null) return null;
    final tr = staffTraits[((e['t'] as num).toInt()) % staffTraits.length];
    final xp = (e['xp'] as num).toDouble();
    return (e['n'].toString(), tr.$2, (min(20.0, xp / 5)).round());
  }

  double _trait(int k) {
    var m = 1.0;
    for (final e in emp.entries) {
      if (lv(e.key) <= 0) continue;
      final tr = staffTraits[((e.value['t'] as num).toInt()) % staffTraits.length];
      m *= [tr.$3, tr.$4, tr.$5, tr.$6][k];
    }
    return m;
  }

  double get _skill {
    var sum = 0.0, n = 0;
    for (final e in emp.entries) {
      if (lv(e.key) <= 0) continue;
      sum += min(0.2, (e.value['xp'] as num).toDouble() / 500);
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  Map<String, int> staff = {'chef': 0, 'waiter': 0, 'manager': 0, 'cleaner': 0};
  double morale = 70, clean = 90, stock = 20, wageMul = 1;
  double cash = 0;
  int last = 0; // lần tính gần nhất (ms)
  int giftAt = 0; // đã nhận quà/cổ vũ tới thời điểm này
  int decided = 0; // ngày (yyyymmdd) đã quyết định chuyện tăng lương
  int inspected = 0; // ngày đã bị kiểm tra
  List<String> log = [];

  int lv(String id) => staff[id] ?? 0;
  bool get hired => lv('chef') > 0 && lv('waiter') > 0;
  double get cashCap => 600.0 + 700 * lv('manager');

  Map<String, dynamic> toJson() => {
        'st': staff,
        'mo': morale,
        'cl': clean,
        'sk': stock,
        'wm': wageMul,
        'ca': cash,
        'la': last,
        'ga': giftAt,
        'de': decided,
        'in': inspected,
        'lg': log.take(30).toList(),
        'em': emp,
        'fe': featured,
        'fw': featuredWeek,
        'fa': farm,
        'fc': farmClaimed,
        're': regulars,
        'wk': week,
        'wr': weekRev,
        'lw': lastWeekRev,
        'pw': prizeWeek,
      };

  static Biz fromJson(dynamic j) {
    final b = Biz();
    if (j is! Map) return b;
    b.staff = {...b.staff, ...Map<String, int>.from((j['st'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ?? {})};
    b.morale = (j['mo'] as num?)?.toDouble() ?? 70;
    b.clean = (j['cl'] as num?)?.toDouble() ?? 90;
    b.stock = (j['sk'] as num?)?.toDouble() ?? 20;
    b.wageMul = (j['wm'] as num?)?.toDouble() ?? 1;
    b.cash = (j['ca'] as num?)?.toDouble() ?? 0;
    b.last = (j['la'] as num?)?.toInt() ?? 0;
    b.giftAt = (j['ga'] as num?)?.toInt() ?? 0;
    b.decided = (j['de'] as num?)?.toInt() ?? 0;
    b.inspected = (j['in'] as num?)?.toInt() ?? 0;
    b.log = List<String>.from((j['lg'] as List?) ?? const []);
    b.emp = {
      for (final e in ((j['em'] as Map?) ?? const {}).entries) e.key.toString(): Map<String, dynamic>.from(e.value as Map),
    };
    b.featured = (j['fe'] ?? '').toString();
    b.featuredWeek = (j['fw'] as num?)?.toInt() ?? 0;
    b.farm = (j['fa'] as num?)?.toDouble() ?? 0;
    b.farmClaimed = (j['fc'] as num?)?.toInt() ?? 0;
    b.regulars = (j['re'] as num?)?.toDouble() ?? 0;
    b.week = (j['wk'] as num?)?.toInt() ?? 0;
    b.weekRev = (j['wr'] as num?)?.toDouble() ?? 0;
    b.lastWeekRev = (j['lw'] as num?)?.toDouble() ?? 0;
    b.prizeWeek = (j['pw'] as num?)?.toInt() ?? 0;
    return b;
  }

  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Sự kiện của ngày [d] (giống nhau mỗi lần tính): (sự kiện, giờ bắt đầu) hoặc null
  static (int, double)? eventOf(String owner, DateTime d) {
    final k = '$owner-${dayKey(d)}';
    if (hash01('bz-$k') < 0.2) return null; // ~20% số ngày yên ả
    final i = (hash01('bze-$k') * bizEvents.length).floor() % bizEvents.length;
    final h = 9 + hash01('bzh-$k') * 10; // 9h–19h
    return (i, h);
  }

  void _say(DateTime at, String s) {
    final hh = at.hour.toString().padLeft(2, '0'), mm = at.minute.toString().padLeft(2, '0');
    log.insert(0, '$hh:$mm $s');
    if (log.length > 30) log.removeLast();
  }

  /// Chi phí nhập 20 phần hàng
  int restockCost(double avgPrice, DateTime now, String owner) {
    final ev = eventOf(owner, now);
    final pricey = ev != null && bizEvents[ev.$1].$1 == 'price' && now.hour + now.minute / 60 >= ev.$2;
    return (20 * avgPrice * 0.3 * (pricey ? 1.5 : 1)).round();
  }

  /// Tính quán chạy từ lần trước tới [now]. [gifts]: quà/cổ vũ của người kia (thời điểm, số tiền; 0 = cổ vũ)
  void run(int now, {required String owner, required int rank, required double avgPrice, required double crowd, List<(int, int)> gifts = const [], bool warm = false, bool hot = false}) {
    if (last == 0) {
      last = now;
      return;
    }
    // quà và lời cổ vũ từ người kia
    for (final g in gifts) {
      if (g.$1 <= giftAt) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(g.$1);
      if (g.$2 > 0) {
        cash += g.$2;
        _say(at, '🎁 Được tặng ${g.$2}💰 vào két');
      } else {
        morale = min(100.0, morale + 12);
        _say(at, '📣 Được cổ vũ, nhân viên vui hẳn lên');
      }
      giftAt = max(giftAt, g.$1);
    }
    final from = max(last, now - 48 * 3600000); // tối đa tính bù 2 ngày
    const stepH = 0.25;
    var t = from;
    while (t < now) {
      final dt = min(stepH, (now - t) / 3600000);
      final at = DateTime.fromMillisecondsSinceEpoch(t);
      final hour = at.hour + at.minute / 60;
      final open = hour >= 8 && hour < 22;
      // sự kiện trong ngày
      var dMul = 1.0, cMul = 1.0, closed = false;
      final ev = eventOf(owner, at);
      if (ev != null && hired) {
        final e = bizEvents[ev.$1];
        final inEv = hour >= ev.$2 && hour < ev.$2 + e.$7;
        final dk = dayKey(at);
        if (inEv) {
          dMul = e.$5;
          cMul = e.$6;
          closed = e.$8;
        }
        if (e.$1 == 'inspect' && hour >= ev.$2 && inspected != dk) {
          inspected = dk;
          if (clean < 50) {
            cash -= 300;
            morale = max(0.0, morale - 10);
            _say(at, '🧪 Kiểm tra ATTP: quán bẩn, bị phạt 300💰');
          } else {
            morale = min(100.0, morale + 5);
            _say(at, '🧪 Kiểm tra ATTP: quán sạch, được khen');
          }
        }
        if (e.$1 == 'raise' && hour >= ev.$2 + e.$7 && decided != dk) {
          decided = dk;
          morale = max(0.0, morale - 20);
          _say(at, '💬 Không trả lời đề nghị tăng lương, nhân viên buồn');
        }
        if ((e.$1 == 'kol' || e.$1 == 'review') && (hour - ev.$2).abs() < dt) {
          morale = min(100.0, morale + 10);
          _say(at, '${e.$2} ${e.$3}!');
        }
      }
      if (open && hired && !closed) {
        if (stock <= 0 && lv('manager') >= 2) {
          final cost = restockCost(avgPrice, at, owner);
          if (cash >= cost) {
            cash -= cost;
            stock += 20;
            _say(at, '📦 Quản lý tự nhập 20 phần hàng (−$cost💰)');
          }
        }
        // món chủ lực hợp thời tiết, khách quen
        var fMul = 1.0;
        if (featured.isNotEmpty && ((warm && dishIsWarm(featured)) || (hot && dishIsFresh(featured)))) fMul = 1.2;
        final demand = (4 + 2 * rank) * crowd * dMul * fMul * (1 + min(0.5, regulars / 100));
        final lateMul = hour < 8.5 && _trait(0) < 1 ? 0.5 : 1.0; // nhân viên hay đi muộn
        final cap = min(5.0 * lv('chef'), 6.0 * lv('waiter')) * (0.5 + 0.5 * morale / 100) * cMul * _trait(0) * (1 + _skill) * lateMul;
        final served = min(min(demand, cap) * dt, stock);
        stock -= served;
        final fromFarm = min(served, farm); // hàng nhà trồng bán trước, đắt hơn 15%
        farm -= fromFarm;
        final featBonus = featured.isNotEmpty ? 1.05 : 1.0;
        final income = (served + fromFarm * 0.15) * avgPrice * featBonus * (1 + 0.08 * (rank - 1)) * (0.7 + 0.3 * clean / 100) * _trait(1);
        // doanh thu tuần
        final wk = weekOf(at);
        if (wk != week) {
          lastWeekRev = week == wk - 1 ? weekRev : 0;
          weekRev = 0;
          week = wk;
        }
        weekRev += income;
        // tay nghề tăng theo giờ làm
        for (final e in emp.values) {
          e['xp'] = (e['xp'] as num).toDouble() + dt;
        }
        // khách quen: hài lòng thì quay lại, quán bẩn/nhân viên chán thì mất khách
        if (morale > 60 && clean > 60) {
          final r0 = regulars;
          regulars = min(50.0, regulars + served * 0.03);
          if (r0 < 10 && regulars >= 10) _say(at, '🤝 Quán đã có 10 khách quen, họ rủ thêm bạn bè tới');
          if (r0 < 30 && regulars >= 30) _say(at, '🤝 30 khách quen! Quán nổi tiếng cả khu phố');
        } else if (morale < 30 || clean < 40) {
          regulars = max(0.0, regulars - dt * 0.5);
        }
        final wages = (6 * lv('chef') + 5 * lv('waiter') + 10 * lv('manager') + 4 * lv('cleaner')) * wageMul * dt;
        final before = cash;
        cash = min(cashCap, cash + income) - wages;
        if (before < cashCap && cash + wages >= cashCap) _say(at, '💰 Két đầy! Vào thu tiền kẻo phí khách');
        clean = max(0.0, clean - served * 0.5 * (1 - 0.25 * lv('cleaner')) * _trait(2));
        final mBefore = morale;
        morale = max(0.0, morale - dt * (lv('manager') > 0 ? 0.6 : 1.2) * _trait(3));
        if (mBefore >= 15 && morale < 15 && lv('waiter') > 1) {
          staff['waiter'] = lv('waiter') - 1;
          _say(at, '😞 Một phục vụ chán việc nên nghỉ (còn cấp ${lv('waiter')})');
        }
        if (stock <= 0 && served > 0) _say(at, '📦 Hết hàng! Quán tạm ngừng bán');
      }
      t += (dt * 3600000).round();
    }
    last = now;
  }
}
