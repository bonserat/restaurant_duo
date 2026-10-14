import 'data.dart';

double r2(double x) => (x * 100).round() / 100;
double _d(dynamic v) => (v as num).toDouble();
Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);

class Cust {
  final Recipe recipe;
  final double maxPat;
  double pat;
  int st = 0; // 0 chờ gọi món, 1 chờ món, 2 đang ăn
  int ticketId = -1;
  double quality = 1;
  double eat = 4;
  Cust(this.recipe, this.maxPat) : pat = maxPat;

  Map<String, dynamic> toJson() => {'r': recipe.id, 'mp': maxPat, 'p': r2(pat), 's': st, 't': ticketId, 'q': r2(quality), 'e': r2(eat)};
  factory Cust.fromJson(Map<String, dynamic> j) {
    final c = Cust(recipeById(j['r']), _d(j['mp']));
    c.pat = _d(j['p']);
    c.st = (j['s'] as num).toInt();
    c.ticketId = (j['t'] as num).toInt();
    c.quality = _d(j['q']);
    c.eat = _d(j['e']);
    return c;
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

class Station {
  Station();
  Ticket? t;
  Set<String> added = {};
  int mistakes = 0;
  double prog = 0, need = 0, doneT = 0;
  bool done = false, burnt = false;
  bool get cooking => t != null && added.length == t!.recipe.ings.length && !done;
  double get quality => mistakes >= 4 ? 0.3 : 1 - 0.2 * mistakes;
  void clear() {
    t = null;
    added = {};
    mistakes = 0;
    prog = 0;
    need = 0;
    doneT = 0;
    done = false;
    burnt = false;
  }

  Map<String, dynamic> toJson() => {
        't': t?.toJson(),
        'a': added.toList(),
        'm': mistakes,
        'pr': r2(prog),
        'nd': r2(need),
        'dt': r2(doneT),
        'dn': done,
        'bn': burnt,
      };
  factory Station.fromJson(Map<String, dynamic> j) {
    final s = Station();
    s.t = j['t'] == null ? null : Ticket.fromJson(_m(j['t']));
    s.added = Set<String>.from(j['a'] as List);
    s.mistakes = (j['m'] as num).toInt();
    s.prog = _d(j['pr']);
    s.need = _d(j['nd']);
    s.doneT = _d(j['dt']);
    s.done = j['dn'] == true;
    s.burnt = j['bn'] == true;
    return s;
  }
}

class Dish {
  final int ticketId;
  final Recipe recipe;
  final double quality;
  Dish(this.ticketId, this.recipe, this.quality);
  Map<String, dynamic> toJson() => {'t': ticketId, 'r': recipe.id, 'q': r2(quality)};
  factory Dish.fromJson(Map<String, dynamic> j) => Dish((j['t'] as num).toInt(), recipeById(j['r']), _d(j['q']));
}
