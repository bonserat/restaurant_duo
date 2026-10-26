// Bộ máy khu vườn chung: mọi thao tác được lưu thành "sự kiện" (gieo hạt, tưới, cho ăn…).
// Trạng thái vườn được tính lại từ danh sách sự kiện + thời gian thật, nên 2 máy
// có cùng danh sách sự kiện sẽ luôn thấy cùng một khu vườn (kể cả sự cố, thời tiết).
import 'dart:math';
import 'data.dart';

const int kHour = 3600000;
const int kStep = 10 * 60000; // mô phỏng theo bước 10 phút
const int kSlotMs = 6 * kHour; // mỗi 6 giờ có thể phát sinh 1 sự cố

/// Nhân 2 số 32-bit, giữ 32 bit thấp – cho kết quả giống hệt nhau trên iPhone lẫn trình duyệt web
int _mul32(int a, int b) {
  final lo = (a & 0xffff) * b;
  final hi = (((a >> 16) & 0xffff) * b) & 0xffff;
  return (lo + hi * 0x10000) & 0xffffffff;
}

/// Băm chuỗi ra số thực [0,1) – giống hệt nhau trên mọi máy
double hash01(String s) {
  var h = 0x811c9dc5;
  for (final u in s.codeUnits) {
    h = (h ^ u) & 0xffffffff;
    h = _mul32(h, 0x01000193);
  }
  // trộn thêm cho đều
  h = (h ^ (h >> 15)) & 0xffffffff;
  h = _mul32(h, 0x2c1b3c6d);
  h = (h ^ (h >> 12)) & 0xffffffff;
  return (h & 0xffffff) / 0x1000000;
}

/// Ngày (theo giờ máy) của thời điểm [ms], dạng 20261016
int dayKey(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return d.year * 10000 + d.month * 100 + d.day;
}

GWeather weatherAt(int ms) {
  final r = hash01('weather-${dayKey(ms)}');
  if (r < 0.40) return gWeathers[0];
  if (r < 0.60) return gWeathers[1];
  if (r < 0.85) return gWeathers[2];
  return gWeathers[3];
}

class GEvent {
  final int id; // id trên máy chủ (âm = chưa gửi được)
  final int at;
  final String who, a;
  final Map<String, dynamic> d;
  GEvent(this.id, this.at, this.who, this.a, this.d);
  String get key => (d['k'] ?? '$id').toString();
  Map<String, dynamic> toJson() => {'id': id, 'at': at, 'who': who, 'a': a, 'd': d};
  factory GEvent.fromJson(Map<String, dynamic> j) => GEvent(
        (j['id'] as num?)?.toInt() ?? 0,
        (j['at'] as num).toInt(),
        (j['who'] ?? '').toString(),
        (j['a'] ?? '').toString(),
        j['d'] is Map ? Map<String, dynamic>.from(j['d'] as Map) : <String, dynamic>{},
      );
}

/// Ô đất / chuồng / hồ
class GSlot {
  final String id, area; // area: field | pen | pond
  final double x, y; // vị trí (tỉ lệ) trong khung vườn
  const GSlot(this.id, this.area, this.x, this.y);
}

const gSlots = [
  GSlot('f0', 'field', 0.12, 0.30),
  GSlot('f1', 'field', 0.31, 0.30),
  GSlot('f2', 'field', 0.50, 0.30),
  GSlot('f3', 'field', 0.12, 0.52),
  GSlot('f4', 'field', 0.31, 0.52),
  GSlot('f5', 'field', 0.50, 0.52),
  GSlot('p0', 'pen', 0.76, 0.27),
  GSlot('p1', 'pen', 0.90, 0.40),
  GSlot('p2', 'pen', 0.76, 0.53),
  GSlot('w0', 'pond', 0.28, 0.83),
  GSlot('w1', 'pond', 0.50, 0.86),
  GSlot('w2', 'pond', 0.72, 0.83),
];

String areaOf(String kind) => kind == 'plant' ? 'field' : (kind == 'animal' ? 'pen' : 'pond');

class GItem {
  final String uid, sp, slot;
  final int planted;
  double grow = 0; // số giờ đã được chăm tốt
  double water = 1, food = 1, dirt = 0, health = 1;
  int fertUntil = 0;
  String? prob; // khoá sự cố đang gặp
  String probType = '';
  int probAt = 0;
  int lastSlot = 0;
  bool ready = false, dead = false;
  GItem(this.uid, this.sp, this.slot, this.planted);
  Species get s => speciesById(sp);
  bool get isPlant => s.kind == 'plant';
  double get progress => (grow / s.hours).clamp(0.0, 1.0).toDouble();
  bool get thirsty => isPlant && water <= 0;
  bool get hungry => !isPlant && food <= 0;
  bool get dirty => !isPlant && dirt >= 1;
  bool get alive => !dead && !ready;

  /// Ngày tuổi để hiển thị: "Ngày 2/3"
  int get dayNo => min(s.days, (grow / 24).floor() + 1);
}

class GLog {
  final int at;
  final String who, text;
  GLog(this.at, this.who, this.text);
}

/// Một thay đổi đáng báo (dùng để hẹn thông báo)
class GAlert {
  final int at;
  final String uid, kind; // thirsty | hungry | dirty | problem | ready | weak | dead
  final String text;
  GAlert(this.at, this.uid, this.kind, this.text);
}

class GState {
  final Map<String, GItem> items = {}; // theo slot
  final Set<String> unlocked = {}; // loài đã thu hoạch ít nhất 1 lần
  final Map<String, int> harvests = {};
  final List<GLog> log = [];
  final List<GAlert> alerts = [];
  GItem? at(String slot) => items[slot];
  int get needCare => items.values.where((i) => !i.dead && (i.prob != null || i.thirsty || i.hungry || i.dirty || i.ready)).length;
}

/// Tính trạng thái vườn tại thời điểm [now] từ danh sách sự kiện.
/// Nếu [watchFrom] khác null: ghi lại các thay đổi xảy ra sau mốc đó (để hẹn thông báo).
GState simulate(List<GEvent> events, int now, {int? watchFrom}) {
  final st = GState();
  final evs = [...events]..sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.id.compareTo(b.id));
  if (evs.isEmpty) return st;
  final seen = <String>{};
  void alert(int t, GItem it, String kind, String text) {
    if (watchFrom == null || t <= watchFrom) return;
    final k = '${it.uid}|$kind|${kind == 'problem' ? it.prob : ''}';
    if (!seen.add(k)) return;
    st.alerts.add(GAlert(t, it.uid, kind, text));
  }

  GItem? byUid(String? u) {
    for (final it in st.items.values) {
      if (it.uid == u) return it;
    }
    return null;
  }

  void apply(GEvent e) {
    final d = e.d;
    final it = byUid(d['u'] as String?);
    String nm(GItem i) => '${i.s.emoji} ${i.s.name}';
    switch (e.a) {
      case 'plant':
        final slot = (d['slot'] ?? '').toString();
        final sp = (d['sp'] ?? '').toString();
        if (st.items[slot] != null || !species.any((s) => s.id == sp)) return;
        final ni = GItem((d['u'] ?? e.key).toString(), sp, slot, e.at);
        st.items[slot] = ni;
        st.log.add(GLog(e.at, e.who, '${ni.isPlant ? 'gieo' : 'thả'} ${nm(ni)}'));
        return;
    }
    if (it == null) return;
    switch (e.a) {
      case 'water':
        if (it.dead || it.ready) return;
        it.water = 1;
        st.log.add(GLog(e.at, e.who, 'tưới ${nm(it)}'));
        break;
      case 'feed':
        if (it.dead || it.ready) return;
        it.food = 1;
        st.log.add(GLog(e.at, e.who, 'cho ${nm(it)} ăn'));
        break;
      case 'clean':
        if (it.dead || it.ready) return;
        it.dirt = 0;
        st.log.add(GLog(e.at, e.who, it.s.kind == 'fish' ? 'thay nước hồ ${nm(it)}' : 'dọn chuồng ${nm(it)}'));
        break;
      case 'fert':
        if (it.dead || it.ready) return;
        it.fertUntil = e.at + 24 * kHour;
        st.log.add(GLog(e.at, e.who, it.isPlant ? 'bón phân cho ${nm(it)}' : 'cho ${nm(it)} uống vitamin'));
        break;
      case 'fix':
        if (it.prob != null && it.prob == d['pk']) {
          st.log.add(GLog(e.at, e.who, '${gProblemById(it.probType).fix.toLowerCase()} cho ${nm(it)}'));
          it.prob = null;
          it.probType = '';
          it.health = min(1.0, it.health + 0.1);
        }
        break;
      case 'harvest':
        if (!it.ready) return;
        st.items.remove(it.slot);
        st.unlocked.add(it.sp);
        st.harvests[it.sp] = (st.harvests[it.sp] ?? 0) + 1;
        st.log.add(GLog(e.at, e.who, 'thu hoạch ${nm(it)} 🎉'));
        break;
      case 'remove':
        st.items.remove(it.slot);
        st.log.add(GLog(e.at, e.who, 'dọn chỗ của ${nm(it)}'));
        break;
    }
  }

  void advance(GItem it, int t, int dtMs) {
    if (it.dead || it.ready) return;
    final dtH = dtMs / kHour;
    final w = weatherAt(t);
    final sp = it.s;
    final t1 = t + dtMs;

    // --- sự cố ngẫu nhiên (cố định theo mã cây + khung giờ, giống nhau trên 2 máy)
    final off = (hash01('off-${it.uid}') * 3 * kHour).round();
    final k = ((t1 - it.planted - off) / kSlotMs).floor();
    if (k > it.lastSlot) {
      it.lastSlot = k;
      if (it.prob == null) {
        final opts = <String>[];
        var p = 0.12;
        if (sp.kind == 'plant') {
          opts.addAll(['pest', 'weed']);
          if (w.id == 'rain' || w.id == 'storm') {
            opts.addAll(['flood', 'flood']);
            p += 0.05;
          }
          if (w.id == 'hot') {
            opts.addAll(['burn', 'burn']);
            p += 0.05;
          }
        } else if (sp.kind == 'animal') {
          opts.addAll(['sick', 'flies']);
          if (w.id == 'storm') {
            opts.addAll(['cold', 'cold']);
            p += 0.06;
          }
        } else {
          opts.addAll(['algae', 'sick']);
          if (w.id == 'hot') {
            opts.addAll(['oxygen', 'oxygen']);
            p += 0.06;
          }
        }
        if (hash01('p-${it.uid}-$k') < p) {
          it.prob = '${it.uid}#$k';
          it.probType = opts[(hash01('t-${it.uid}-$k') * opts.length).floor() % opts.length];
          it.probAt = t1;
          final gp = gProblemById(it.probType);
          alert(t1, it, 'problem', '${gp.emoji} ${sp.name} gặp sự cố: ${gp.name}! Vào ${gp.fix.toLowerCase()} ngay nhé.');
        }
      }
    }

    // --- nhu cầu hằng ngày
    if (sp.kind == 'plant') {
      if (w.id == 'rain' || w.id == 'storm') {
        it.water = 1; // trời tưới hộ
      } else {
        it.water -= dtH / (w.id == 'hot' ? 11 : 20);
      }
      if (it.water <= 0) {
        it.water = 0;
        alert(t1, it, 'thirsty', '💧 ${sp.name} khát nước rồi, vào tưới cây nhé!');
      }
    } else {
      it.food -= dtH / 20;
      it.dirt += dtH / (sp.kind == 'fish' ? 36 : 30);
      if (it.food <= 0) {
        it.food = 0;
        alert(t1, it, 'hungry', '🌽 ${sp.name} đói bụng rồi, vào cho ăn nhé!');
      }
      if (it.dirt >= 1) {
        it.dirt = 1;
        alert(t1, it, 'dirty', sp.kind == 'fish' ? '🪣 Hồ của ${sp.name} bẩn quá, cần thay nước!' : '🧹 Chuồng ${sp.name} bẩn quá, cần dọn dẹp!');
      }
    }

    final needOk = sp.kind == 'plant' ? it.water > 0 : (it.food > 0 && it.dirt < 1);
    final good = needOk && it.prob == null;
    if (good) {
      var rate = t < it.fertUntil ? 1.3 : 1.0;
      if (sp.kind == 'plant' && w.id == 'storm') rate *= 0.7;
      if (sp.kind == 'plant' && w.id == 'hot' && it.water < 0.4) rate *= 0.8;
      if (sp.kind == 'animal' && w.id == 'storm') rate *= 0.85;
      it.grow += dtH * rate;
      it.health = min(1.0, it.health + dtH / 48);
    } else {
      var loss = 0.0;
      if (!needOk) loss += dtH / 48; // bỏ bê khoảng 2 ngày mới nguy
      if (it.prob != null) loss += dtH / 40;
      final before = it.health;
      it.health -= loss;
      if (before >= 0.35 && it.health < 0.35) alert(t1, it, 'weak', '❤️‍🩹 ${sp.name} đang yếu lắm, cần chăm sóc gấp!');
      if (it.health <= 0) {
        it.health = 0;
        it.dead = true;
        alert(t1, it, 'dead', '🥀 ${sp.name} không qua khỏi vì bị bỏ bê quá lâu…');
      }
    }
    if (!it.dead && it.grow >= sp.hours) {
      it.ready = true;
      it.prob = null;
      alert(t1, it, 'ready', '✨ ${sp.name} đã lớn, thu hoạch được rồi!');
    }
  }

  var t = evs.first.at;
  var ei = 0;
  while (true) {
    while (ei < evs.length && evs[ei].at <= t) {
      apply(evs[ei]);
      ei++;
    }
    if (t >= now) break;
    final anyAlive = st.items.values.any((i) => i.alive);
    if (!anyAlive) {
      // vườn trống: nhảy thẳng tới sự kiện kế tiếp
      if (ei >= evs.length) break;
      t = min(now, max(t, evs[ei].at));
      continue;
    }
    final nt = min(now, t + kStep);
    for (final it in st.items.values) {
      advance(it, t, nt - t);
    }
    t = nt;
  }
  // sự kiện có giờ lệch về tương lai (đồng hồ 2 máy chênh nhau)
  while (ei < evs.length) {
    apply(evs[ei]);
    ei++;
  }
  return st;
}
