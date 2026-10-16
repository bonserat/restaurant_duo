import 'dart:math';
import 'data.dart';

double r2(double x) => (x * 100).round() / 100;
double _d(dynamic v) => (v as num).toDouble();
double _dd(dynamic v, double def) => v == null ? def : (v as num).toDouble();
Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);

class Cust {
  final Recipe recipe;
  final double maxPat;
  double pat;
  int st = 0; // 0 chờ gọi món, 1 chờ món, 2 đang ăn
  int ticketId = -1;
  double quality = 1;
  double eat = 4;
  String npc = ''; // '' = khách thường, còn lại: vip, critic, hunter, student, stranger
  double saltPref = 0; // khẩu vị: + thích đậm, − thích nhạt
  int line = 0; // câu chuyện thứ mấy của NPC
  String taste = ''; // Nhạt / Vừa / Mặn của món được mang ra
  Cust(this.recipe, this.maxPat) : pat = maxPat;

  Map<String, dynamic> toJson() => {
        'r': recipe.id,
        'mp': maxPat,
        'p': r2(pat),
        's': st,
        't': ticketId,
        'q': r2(quality),
        'e': r2(eat),
        'n': npc,
        'sp': saltPref,
        'ln': line,
        'ta': taste,
      };
  factory Cust.fromJson(Map<String, dynamic> j) {
    final c = Cust(recipeById(j['r']), _d(j['mp']));
    c.pat = _d(j['p']);
    c.st = (j['s'] as num).toInt();
    c.ticketId = (j['t'] as num).toInt();
    c.quality = _d(j['q']);
    c.eat = _d(j['e']);
    c.npc = j['n'] as String? ?? '';
    c.saltPref = _dd(j['sp'], 0);
    c.line = (j['ln'] as num?)?.toInt() ?? 0;
    c.taste = j['ta'] as String? ?? '';
    return c;
  }
}

/// Khách đứng xếp hàng ngoài cửa khi quán đã kín bàn
class OutsideGuest {
  final double maxPat;
  double pat;
  final int seed; // để mỗi người một dáng vẻ khác nhau
  OutsideGuest(this.maxPat, this.seed) : pat = maxPat;
  double get frac => (pat / maxPat).clamp(0.0, 1.0).toDouble();
  Map<String, dynamic> toJson() => {'mp': r2(maxPat), 'p': r2(pat), 's': seed};
  factory OutsideGuest.fromJson(Map<String, dynamic> j) {
    final g = OutsideGuest(_d(j['mp']), (j['s'] as num).toInt());
    g.pat = _d(j['p']);
    return g;
  }
}

class TableS {
  Cust? c;
  bool dirty = false;
  double dirtyT = 0;
  TableS();
  Map<String, dynamic> toJson() => {'c': c?.toJson(), 'd': dirty, 'dt': r2(dirtyT)};
  factory TableS.fromJson(Map<String, dynamic> j) {
    final t = TableS();
    t.c = j['c'] == null ? null : Cust.fromJson(_m(j['c']));
    t.dirty = j['d'] == true;
    t.dirtyT = _d(j['dt']);
    return t;
  }
}

class Ticket {
  final int id, table;
  final Recipe recipe;
  Ticket(this.id, this.table, this.recipe);
  Map<String, dynamic> toJson() => {'id': id, 'tb': table, 'r': recipe.id};
  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket((j['id'] as num).toInt(), (j['tb'] as num).toInt(), recipeById(j['r']));
}

/// Một vị trí bếp. Các công đoạn: nhận đơn → (thái trên thớt) → cho đủ nguyên liệu
/// → canh lửa trong lúc nấu → nêm nếm → lấy món ra quầy.
class Station {
  Station();
  Ticket? t;
  Set<String> added = {};
  List<String> board = []; // nguyên liệu đang chờ thái trên thớt
  int chopLeft = 0; // số nhát còn lại cho nguyên liệu đầu tiên trên thớt
  int mistakes = 0;
  double prog = 0, need = 0, doneT = 0;
  double heat = 0.5; // 0..1, vùng chuẩn 0.3–0.75
  double heatBad = 0; // số giây lửa không chuẩn
  double hot = 0; // số giây lửa quá to (dễ cháy bếp)
  double salt = 0, saltTarget = 2, tol = 0.8; // nêm nếm
  bool done = false, burnt = false;

  bool get cooking => t != null && added.length == t!.recipe.ings.length && board.isEmpty && !done;
  bool get chopping => board.isNotEmpty;

  /// Nhạt / Vừa / Mặn (hoặc Ngọt gắt với đồ uống – tên hiển thị do giao diện quyết định)
  String get taste => salt < saltTarget - tol ? 'Nhạt' : (salt > saltTarget + tol ? 'Đậm' : 'Vừa');

  double get quality {
    var q = mistakes >= 4 ? 0.3 : 1 - 0.2 * mistakes;
    q -= min(0.35, heatBad * 0.04); // canh lửa kém
    final sd = (salt - saltTarget).abs();
    if (sd > tol) q -= min(0.4, 0.12 + (sd - tol) * 0.2); // thiếu hoặc thừa vị
    return q.clamp(0.1, 1.0).toDouble();
  }

  void clear() {
    t = null;
    added = {};
    board = [];
    chopLeft = 0;
    mistakes = 0;
    prog = 0;
    need = 0;
    doneT = 0;
    heat = 0.5;
    heatBad = 0;
    hot = 0;
    salt = 0;
    done = false;
    burnt = false;
  }

  Map<String, dynamic> toJson() => {
        't': t?.toJson(),
        'a': added.toList(),
        'b': board,
        'cl': chopLeft,
        'm': mistakes,
        'pr': r2(prog),
        'nd': r2(need),
        'dt': r2(doneT),
        'h': r2(heat),
        'hb': r2(heatBad),
        'ho': r2(hot),
        'sa': r2(salt),
        'stg': r2(saltTarget),
        'tl': r2(tol),
        'dn': done,
        'bn': burnt,
      };
  factory Station.fromJson(Map<String, dynamic> j) {
    final s = Station();
    s.t = j['t'] == null ? null : Ticket.fromJson(_m(j['t']));
    s.added = Set<String>.from(j['a'] as List);
    s.board = List<String>.from((j['b'] as List?) ?? const []);
    s.chopLeft = (j['cl'] as num?)?.toInt() ?? 0;
    s.mistakes = (j['m'] as num).toInt();
    s.prog = _d(j['pr']);
    s.need = _d(j['nd']);
    s.doneT = _d(j['dt']);
    s.heat = _dd(j['h'], 0.5);
    s.heatBad = _dd(j['hb'], 0);
    s.hot = _dd(j['ho'], 0);
    s.salt = _dd(j['sa'], 0);
    s.saltTarget = _dd(j['stg'], 2);
    s.tol = _dd(j['tl'], 0.8);
    s.done = j['dn'] == true;
    s.burnt = j['bn'] == true;
    return s;
  }
}

class Dish {
  final int ticketId;
  final Recipe recipe;
  final double quality;
  final String taste;
  Dish(this.ticketId, this.recipe, this.quality, [this.taste = 'Vừa']);
  Map<String, dynamic> toJson() => {'t': ticketId, 'r': recipe.id, 'q': r2(quality), 'ta': taste};
  factory Dish.fromJson(Map<String, dynamic> j) =>
      Dish((j['t'] as num).toInt(), recipeById(j['r']), _d(j['q']), j['ta'] as String? ?? 'Vừa');
}

/// Sự cố đang diễn ra. [target]: số bếp (cháy) hoặc số bàn (gây gổ), -1 nếu không có.
/// [x], [y]: vị trí tương đối 0..1 trên sàn sảnh (chuột, vũng nước).
class Incident {
  final int id;
  final String type;
  int target;
  double x, y, vx, vy;
  int hp;
  double age = 0;
  Incident(this.id, this.type, this.target, this.x, this.y, this.hp, {this.vx = 0, this.vy = 0});

  Map<String, dynamic> toJson() => {'id': id, 'k': type, 'tg': target, 'x': r2(x), 'y': r2(y), 'hp': hp, 'ag': r2(age)};
  factory Incident.fromJson(Map<String, dynamic> j) {
    final i = Incident((j['id'] as num).toInt(), j['k'] as String, (j['tg'] as num).toInt(), _d(j['x']), _d(j['y']), (j['hp'] as num).toInt());
    i.age = _dd(j['ag'], 0);
    return i;
  }
}

/// Đồ trang trí đã đặt trong quán (vị trí tương đối trên sàn; đồ treo tường chỉ dùng x).
class Deco {
  final String type;
  double x, y;
  Deco(this.type, this.x, this.y);
  Map<String, dynamic> toJson() => {'k': type, 'x': r2(x), 'y': r2(y)};
  factory Deco.fromJson(Map<String, dynamic> j) => Deco(j['k'] as String, _d(j['x']), _d(j['y']));
}
