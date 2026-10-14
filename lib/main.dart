import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'data.dart';
import 'models.dart';
import 'net.dart';
import 'scene.dart';

bool get onlineConfigured => !kSupabaseUrl.contains('YOUR_');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (onlineConfigured) {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  }
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: GamePage()));
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  final rnd = Random();
  final net = Net();
  final codeCtl = TextEditingController();
  Timer? timer, netTimer;

  // menu, create, lobby, join, wait, play, end, shop
  String screen = 'menu';

  // --- Chế độ chơi ---
  String mode = 'local'; // local (1 máy) | host | guest
  String myRole = 'both'; // chef | waiter | both
  String createRole = 'chef';
  String gameType = 'coop'; // coop: 1 đầu bếp + 1 phục vụ | race: mỗi người 1 quán, thi bán nhiều món
  String createGame = 'coop';
  bool paused = false;
  // Điểm của đối thủ (chế độ thi đấu)
  int oppServed = 0, oppEarned = 0;
  String oppScr = 'wait';
  String roomCode = '', netStatus = '';
  bool guestJoined = false, joined = false;
  DateTime lastPeer = DateTime.now();
  List<dynamic>? _bk; // sao lưu dữ liệu của khách khi vào phòng người khác
  int tickN = 0;
  int hostDecor = 0; // cấp trang trí của chủ phòng (để khách thấy đúng cây cảnh)

  // --- Lưu trữ ---
  int money = 0, day = 1;
  Map<String, int> lv = {};
  Set<String> recipes = {};
  Set<String> owned = {'cafe'};
  String venueId = 'cafe';

  // --- Trong ván ---
  double timeLeft = 0, spawnT = 0, msgT = 0;
  int earned = 0, served = 0, lost = 0, ticketSeq = 0, activeStation = -1;
  int? selDishId; // món đang chọn ở quầy (cục bộ của người phục vụ)
  List<int> starsLog = [];
  List<TableS> tables = [];
  List<Ticket> queue = [];
  List<Station> stations = [];
  List<Dish> counter = [];
  String msg = '';

  Venue get venue => venueById(venueId);
  int lvl(String id) => lv[id] ?? 0;
  int get goal => 150 + day * 60;
  int get decorLv => remote ? hostDecor : lvl('decor');
  /// Khách trong chế độ hợp tác: chỉ hiển thị, mọi thao tác gửi lên chủ phòng
  bool get remote => mode == 'guest' && gameType == 'coop';
  bool get race => mode != 'local' && gameType == 'race';
  String get shopBack => mode == 'host' ? 'lobby' : (mode == 'guest' ? 'wait' : 'menu');
  bool get peerLost {
    if (mode == 'local') return false;
    if (mode == 'host' && !guestJoined) return false;
    if (mode == 'guest' && !joined) return false;
    return DateTime.now().difference(lastPeer).inSeconds > 7;
  }

  @override
  void initState() {
    super.initState();
    recipes.addAll(venueById('cafe').recipes.where((r) => r.unlock == 0).map((r) => r.id));
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Thoát ra màn hình chính / tắt app → lưu ngay
    if (state != AppLifecycleState.resumed) save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    save();
    timer?.cancel();
    netTimer?.cancel();
    codeCtl.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('save');
    if (s == null) return;
    final m = jsonDecode(s) as Map<String, dynamic>;
    setState(() {
      money = m['money'] ?? 0;
      day = m['day'] ?? 1;
      lv = Map<String, int>.from(m['lv'] ?? {});
      recipes = Set<String>.from(m['recipes'] ?? recipes);
      owned = Set<String>.from(m['owned'] ?? owned);
      venueId = m['venue'] ?? 'cafe';
    });
  }

  Future<void> save() async {
    var m0 = money, d0 = day, v0 = venueId;
    if (remote) {
      // Đang ở quán của người khác: lưu dữ liệu quán của MÌNH (đã sao lưu khi vào phòng)
      final bk = _bk;
      if (bk == null) return;
      m0 = bk[0] as int;
      d0 = bk[1] as int;
      v0 = bk[2] as String;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('save', jsonEncode({'money': m0, 'day': d0, 'lv': lv, 'recipes': recipes.toList(), 'owned': owned.toList(), 'venue': v0}));
  }

  void say(String m) {
    msg = m;
    msgT = 3;
  }

  void snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));

  // =====================================================================
  //  MẠNG (Supabase Realtime Broadcast)
  //  - Chủ phòng (host) chạy toàn bộ mô phỏng và gửi "state" 5 lần/giây.
  //  - Khách (guest) chỉ hiển thị state và gửi thao tác "act" lên host.
  // =====================================================================
  Map<String, dynamic> snapshot() => {
        't': 'state',
        'hr': myRole,
        'scr': screen,
        'day': day,
        'money': money,
        'tl': r2(timeLeft),
        'ea': earned,
        'sv': served,
        'ls': lost,
        'vn': venueId,
        'dc': lvl('decor'),
        'tb': tables.map((e) => e.toJson()).toList(),
        'q': queue.map((e) => e.toJson()).toList(),
        'st': stations.map((e) => e.toJson()).toList(),
        'ct': counter.map((e) => e.toJson()).toList(),
        'act': activeStation,
        'msg': msg,
        'mt': r2(msgT),
        'sl': starsLog,
      };

  Map<String, dynamic> raceStatus() => {'t': 'race', 'scr': screen, 'sv': served, 'ea': earned, 'tl': r2(timeLeft), 'day': day};

  void applySnapshot(Map<String, dynamic> m) {
    var reward = false;
    List<T> lst<T>(String k, T Function(Map<String, dynamic>) f) => (m[k] as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    setState(() {
      myRole = m['hr'] == 'chef' ? 'waiter' : 'chef';
      joined = true;
      day = (m['day'] as num).toInt();
      money = (m['money'] as num).toInt();
      timeLeft = (m['tl'] as num).toDouble();
      earned = (m['ea'] as num).toInt();
      served = (m['sv'] as num).toInt();
      lost = (m['ls'] as num).toInt();
      venueId = m['vn'];
      hostDecor = (m['dc'] as num?)?.toInt() ?? 0;
      tables = lst('tb', TableS.fromJson);
      queue = lst('q', Ticket.fromJson);
      stations = lst('st', Station.fromJson);
      counter = lst('ct', Dish.fromJson);
      activeStation = (m['act'] as num).toInt();
      msg = m['msg'] ?? '';
      msgT = (m['mt'] as num).toDouble();
      starsLog = List<int>.from((m['sl'] as List).map((e) => (e as num).toInt()));
      if (selDishId != null && !counter.any((d) => d.ticketId == selDishId)) selDishId = null;
      gameType = 'coop';
      final scr = m['scr'];
      // Hết ngày: quán của mình cũng nhận số tiền cả đội kiếm được
      final bk = _bk;
      if (scr == 'end' && screen == 'play' && bk != null) {
        bk[0] = (bk[0] as int) + earned;
        bk[1] = (bk[1] as int) + 1;
        reward = true;
      }
      screen = (scr == 'play' || scr == 'end') ? scr : 'wait';
    });
    if (reward) save();
  }

  void applyRace(Map<String, dynamic> m) {
    oppServed = (m['sv'] as num?)?.toInt() ?? 0;
    oppEarned = (m['ea'] as num?)?.toInt() ?? 0;
    oppScr = m['scr'] as String? ?? 'wait';
  }

  void onNet(Map<String, dynamic> m) {
    lastPeer = DateTime.now();
    final t = m['t'];
    if (mode == 'host') {
      if (t == 'join') {
        guestJoined = true;
        net.send(race ? raceStatus() : snapshot());
        setState(() {});
      } else if (t == 'race') {
        applyRace(m);
        setState(() {});
      } else if (t == 'act' && !race) {
        applyAction(m);
      } else if (t == 'bye') {
        lastPeer = DateTime(2000);
        setState(() {});
      }
    } else if (mode == 'guest') {
      if (t == 'state') {
        applySnapshot(m);
      } else if (t == 'race') {
        gameType = 'race';
        joined = true;
        myRole = 'both';
        applyRace(m);
        if (!['play', 'end', 'shop'].contains(screen)) screen = 'wait';
        setState(() {});
      } else if (t == 'start') {
        if (gameType == 'race' && screen != 'play') startDay();
      } else if (t == 'bye') {
        leaveRoom(notice: 'Chủ phòng đã rời phòng');
      }
    }
  }

  void applyAction(Map<String, dynamic> m) {
    switch (m['a']) {
      case 'table':
        onTable((m['i'] as num).toInt(), (m['d'] as num?)?.toInt());
        break;
      case 'station':
        onStation((m['i'] as num).toInt());
        break;
      case 'ing':
        onIngredient(m['id'] as String);
        break;
    }
    if (screen == 'play') net.send(snapshot());
    setState(() {});
  }

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> createRoom() async {
    if (!onlineConfigured) return snack('Chưa điền Supabase trong lib/config.dart');
    roomCode = _newCode();
    mode = 'host';
    gameType = createGame;
    myRole = createGame == 'race' ? 'both' : createRole;
    oppScr = 'wait';
    guestJoined = false;
    lastPeer = DateTime.now();
    netStatus = 'Đang kết nối...';
    setState(() => screen = 'lobby');
    await net.connect(roomCode, onNet, () {
      if (mounted) setState(() => netStatus = 'Phòng đã mở');
      net.send(race ? raceStatus() : snapshot());
    }, (e) {
      if (mounted) setState(() => netStatus = 'Lỗi kết nối: $e');
    });
    netTimer?.cancel();
    netTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mode == 'host') net.send(race ? raceStatus() : snapshot());
      if (mounted) setState(() {});
    });
  }

  Future<void> joinRoom() async {
    if (!onlineConfigured) return snack('Chưa điền Supabase trong lib/config.dart');
    final code = codeCtl.text.trim().toUpperCase();
    if (code.length != 4) return snack('Mã phòng gồm 4 ký tự');
    _bk = [money, day, venueId];
    roomCode = code;
    mode = 'guest';
    gameType = 'coop'; // sẽ biết đúng loại khi nhận tin đầu tiên từ chủ phòng
    oppScr = 'wait';
    joined = false;
    lastPeer = DateTime.now();
    netStatus = 'Đang kết nối...';
    setState(() {});
    await net.connect(code, onNet, () {
      if (mounted) setState(() => netStatus = 'Đang tìm phòng $code...');
      net.send({'t': 'join'});
    }, (e) {
      if (mounted) setState(() => netStatus = 'Lỗi kết nối: $e');
    });
    netTimer?.cancel();
    netTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mode == 'guest') {
        net.send({'t': 'join'}); // vừa là xin vào, vừa là ping
        if (race) net.send(raceStatus());
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> leaveRoom({String? notice}) async {
    net.send({'t': 'bye'});
    await Future.delayed(const Duration(milliseconds: 300));
    netTimer?.cancel();
    timer?.cancel();
    await net.disconnect();
    final bk = _bk;
    if (remote && bk != null) {
      // trả lại dữ liệu quán của mình (đã cộng tiền thưởng các ngày hợp tác)
      money = bk[0] as int;
      day = bk[1] as int;
      venueId = bk[2] as String;
    }
    _bk = null;
    mode = 'local';
    gameType = 'coop';
    paused = false;
    myRole = 'both';
    guestJoined = false;
    joined = false;
    roomCode = '';
    selDishId = null;
    if (!mounted) return;
    setState(() => screen = 'menu');
    save();
    if (notice != null) snack(notice);
  }

  // ---------- Thoát ván giữa chừng ----------
  Future<void> confirmExit() async {
    if (mode == 'local') setState(() => paused = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thoát ván này?'),
        content: Text(remote
            ? 'Bạn sẽ rời phòng của hàng xóm.'
            : 'Tiền đã kiếm được trong ván vẫn được lưu lại.${mode == 'local' ? '' : '\nBạn sẽ rời phòng.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Chơi tiếp')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Thoát')),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => paused = false);
    if (ok == true) await quitGame();
  }

  Future<void> quitGame() async {
    timer?.cancel();
    await save();
    if (mode == 'local') {
      if (mounted) setState(() => screen = 'menu');
    } else {
      await leaveRoom();
    }
  }

  /// Nút back hệ thống (Android) / vuốt lùi
  void onBack() {
    switch (screen) {
      case 'play':
        confirmExit();
        break;
      case 'menu':
        SystemNavigator.pop();
        break;
      case 'shop':
        setState(() => screen = shopBack);
        break;
      case 'create':
        setState(() => screen = 'menu');
        break;
      case 'join':
        if (mode == 'guest') {
          leaveRoom();
        } else {
          setState(() => screen = 'menu');
        }
        break;
      default: // lobby, wait, end
        if (mode == 'local') {
          setState(() => screen = 'menu');
        } else {
          leaveRoom();
        }
    }
  }

  // =====================================================================
  //  VÒNG ĐỜI NGÀY CHƠI (chạy ở local / host)
  // =====================================================================
  void startDay() {
    tables = List.generate(min(3 + lvl('tables'), venue.maxTables), (_) => TableS());
    stations = List.generate(2 + lvl('stations'), (_) => Station());
    queue = [];
    counter = [];
    earned = 0;
    served = 0;
    lost = 0;
    starsLog = [];
    timeLeft = 90;
    spawnT = 1;
    activeStation = -1;
    selDishId = null;
    msg = '';
    msgT = 0;
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) => tick(0.1));
    paused = false;
    setState(() => screen = 'play');
    if (race) {
      oppServed = 0;
      oppEarned = 0;
      oppScr = 'play';
      if (mode == 'host') net.send({'t': 'start'});
      net.send(raceStatus());
    } else if (mode == 'host') {
      net.send(snapshot());
    }
  }

  void endDay() {
    timer?.cancel();
    if (earned >= goal) money += 50;
    day++;
    save();
    setState(() => screen = 'end');
    if (race) {
      net.send(raceStatus());
    } else if (mode == 'host') {
      net.send(snapshot());
    }
  }

  void tick(double dt) {
    if (screen != 'play' || remote || paused) return;
    if (peerLost && !race) {
      setState(() {}); // tạm dừng khi đối tác mất kết nối
      return;
    }
    timeLeft -= dt;
    if (msgT > 0) msgT -= dt;
    final maxPat = 45.0 + 8 * lvl('decor');

    if (timeLeft > 0) {
      spawnT -= dt;
      if (spawnT <= 0) {
        final free = [
          for (var i = 0; i < tables.length; i++)
            if (tables[i].c == null && !tables[i].dirty) i
        ];
        if (free.isNotEmpty) {
          final avail = venue.recipes.where((r) => recipes.contains(r.id)).toList();
          tables[free[rnd.nextInt(free.length)]].c = Cust(avail[rnd.nextInt(avail.length)], maxPat);
        }
        spawnT = max(2.5, (4 + rnd.nextDouble() * 4) * venue.spawnMul - day * 0.15);
      }
    }

    for (final t in tables) {
      final c = t.c;
      if (c != null) {
        if (c.st < 2) {
          c.pat -= dt;
          if (c.pat <= 0) {
            queue.removeWhere((x) => x.id == c.ticketId);
            lost++;
            starsLog.add(1);
            say('😡 Chờ lâu quá, tôi đi đây!');
            t.c = null;
          }
        } else {
          c.eat -= dt;
          if (c.eat <= 0) finishCustomer(t, c);
        }
      }
      if (t.dirty) {
        t.dirtyT += dt;
        final ac = lvl('clean');
        if (ac > 0 && t.dirtyT >= 15 - 3 * ac) t.dirty = false;
      }
    }

    for (final s in stations) {
      if (s.t == null) continue;
      if (!tables.any((t) => t.c?.ticketId == s.t!.id)) {
        s.clear();
        continue;
      }
      if (s.cooking) {
        s.prog += dt;
        if (s.prog >= s.need) s.done = true;
      } else if (s.done) {
        s.doneT += dt;
        if (s.doneT > 7) s.burnt = true;
      }
    }

    counter.removeWhere((d) => !tables.any((t) => t.c?.ticketId == d.ticketId));
    if (selDishId != null && !counter.any((d) => d.ticketId == selDishId)) selDishId = null;

    if (timeLeft <= 0 && tables.every((t) => t.c == null)) {
      endDay();
      return;
    }
    tickN++;
    if (race) {
      if (tickN % 5 == 0) net.send(raceStatus());
    } else if (mode == 'host' && tickN % 2 == 0) {
      net.send(snapshot());
    }
    setState(() {});
  }

  void finishCustomer(TableS t, Cust c) {
    final frac = (c.pat / c.maxPat).clamp(0.0, 1.0);
    final dirtyN = tables.where((x) => x.dirty).length;
    final clean = 1 - dirtyN / tables.length;
    final raw = frac * 2.2 + c.quality * 2.0 + clean * 0.8;
    final stars = raw.round().clamp(1, 5);
    var gain = (c.recipe.price * (0.6 + 0.1 * stars)).round();
    if (stars >= 4) gain += (c.recipe.price * 0.25 * (1 + 0.2 * lvl('decor'))).round();
    money += gain;
    earned += gain;
    served++;
    starsLog.add(stars);
    if (c.quality < 0.6) {
      say('😡 Món ăn dở quá!');
    } else if (frac < 0.35) {
      say('😤 Phục vụ chậm quá!');
    } else if (clean < 0.6) {
      say('🤢 Quán bẩn quá!');
    } else if (stars >= 4) {
      say('😍 Rất hài lòng! +$gain');
    } else {
      say('🙂 Tạm ổn. +$gain');
    }
    t.c = null;
    t.dirty = true;
    t.dirtyT = 0;
    save(); // lưu tiền ngay sau mỗi khách
  }

  // ---------- Logic thao tác (chạy ở local / host) ----------
  void onTable(int i, int? dishId) {
    if (i < 0 || i >= tables.length) return;
    final t = tables[i];
    final c = t.c;
    if (t.dirty) {
      t.dirty = false;
      return;
    }
    if (c == null) return;
    if (c.st == 0) {
      c.st = 1;
      c.ticketId = ++ticketSeq;
      queue.add(Ticket(c.ticketId, i, c.recipe));
    } else if (c.st == 1 && dishId != null) {
      final idx = counter.indexWhere((d) => d.ticketId == dishId);
      if (idx >= 0 && counter[idx].ticketId == c.ticketId) {
        final d = counter.removeAt(idx);
        c.st = 2;
        c.quality = d.quality;
        c.eat = 4;
      } else {
        say('Sai bàn rồi!');
      }
    }
  }

  void onStation(int i) {
    if (i < 0 || i >= stations.length) return;
    final s = stations[i];
    if (s.t == null) {
      if (queue.isEmpty) return;
      final tk = queue.removeAt(0);
      s.t = tk;
      s.need = tk.recipe.cook * (1 - 0.15 * lvl('stove'));
      activeStation = i;
    } else if (s.done) {
      if (counter.length >= 6) {
        say('Quầy đầy rồi!');
        return;
      }
      counter.add(Dish(s.t!.id, s.t!.recipe, s.burnt ? min(s.quality, 0.35) : s.quality));
      s.clear();
    } else {
      activeStation = i;
    }
  }

  void onIngredient(String id) {
    if (activeStation < 0 || activeStation >= stations.length) return;
    final s = stations[activeStation];
    if (s.t == null || s.cooking || s.done) return;
    if (s.t!.recipe.ings.contains(id)) {
      s.added.add(id);
    } else {
      s.mistakes++;
      s.need += 1.0;
      say('Nhầm nguyên liệu! 😖');
    }
  }

  // ---------- Thao tác từ giao diện (tự chọn: chạy tại chỗ hoặc gửi lên host) ----------
  void doTable(int i) {
    final waiting = i < tables.length && tables[i].c?.st == 1;
    if (remote) {
      net.send({'t': 'act', 'a': 'table', 'i': i, 'd': selDishId});
    } else {
      onTable(i, selDishId);
      if (mode == 'host' && !race) net.send(snapshot());
    }
    if (waiting) selDishId = null;
    setState(() {});
  }

  void doStation(int i) {
    if (remote) {
      net.send({'t': 'act', 'a': 'station', 'i': i});
    } else {
      onStation(i);
      if (mode == 'host' && !race) net.send(snapshot());
    }
    setState(() {});
  }

  void doIngredient(String id) {
    if (remote) {
      net.send({'t': 'act', 'a': 'ing', 'id': id});
    } else {
      onIngredient(id);
      if (mode == 'host' && !race) net.send(snapshot());
    }
    setState(() {});
  }

  void onDish(Dish d) => setState(() => selDishId = selDishId == d.ticketId ? null : d.ticketId);

  bool pay(int cost) {
    if (money < cost) {
      snack('Không đủ tiền!');
      return false;
    }
    money -= cost;
    return true;
  }

  // =====================================================================
  //  GIAO DIỆN
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (screen) {
      case 'create':
        body = createScreen();
        break;
      case 'lobby':
        body = lobbyScreen();
        break;
      case 'join':
        body = joinScreen();
        break;
      case 'wait':
        body = waitScreen();
        break;
      case 'play':
        body = playScreen();
        break;
      case 'end':
        body = endScreen();
        break;
      case 'shop':
        body = shopScreen();
        break;
      default:
        body = menuScreen();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFFFF3E0),
      body: SafeArea(
        child: Column(children: [
          if (peerLost)
            Container(
              width: double.infinity,
              color: Colors.red,
              padding: const EdgeInsets.all(6),
              child: Text(race ? '⚠️ Mất kết nối với hàng xóm…' : '⚠️ Mất kết nối với hàng xóm… ván tạm dừng', style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ),
          Expanded(child: body),
        ]),
      ),
      ),
    );
  }

  Widget bigButton(String text, VoidCallback? onTap, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 280,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color ?? Colors.deepOrange,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: onTap,
            child: Text(text, style: const TextStyle(fontSize: 17)),
          ),
        ),
      );

  String roleName(String r) => r == 'chef' ? '👨‍🍳 $kChefName (Đầu bếp)' : '🛎️ $kWaiterName (Phục vụ)';

  // --- Menu & phòng ---
  Widget menuScreen() => Center(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 12),
            const Text('🍽️', style: TextStyle(fontSize: 64)),
            const Text('Nhà Hàng Đôi', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const Text('của $kChefName 👨‍🍳 & $kWaiterName 👩‍🍳', style: TextStyle(fontSize: 16, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
            Text('Ngày $day  •  💰 $money  •  ${venue.emoji} ${venue.name}'),
            const SizedBox(height: 16),
            bigButton('📱 Chơi 1 máy (1–2 người)', () {
              mode = 'local';
              myRole = 'both';
              startDay();
            }, color: Colors.green),
            bigButton('🌐 Tạo phòng (mời hàng xóm)', () => setState(() => screen = 'create')),
            bigButton('🔑 Vào phòng bằng mã', () => setState(() => screen = 'join'), color: Colors.indigo),
            bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '👨‍🍳 $kChefName – ĐẦU BẾP: chạm bếp nhận đơn → chạm đúng nguyên liệu → chờ chín → chạm bếp lấy món ra quầy (đừng để cháy!).\n\n'
                '🛎️ $kWaiterName – PHỤC VỤ: chạm khách để nhận order → chạm món ở quầy rồi chạm đúng bàn → chạm bàn bẩn để dọn.\n\n'
                '🤝 Hợp tác: 2 máy, một người nấu, một người phục vụ chung 1 quán.\n'
                '🏁 Thi đấu: 2 máy, mỗi người tự lo quán của mình, ai bán được nhiều món hơn thì thắng.\n\n'
                'Tiền và nâng cấp được lưu tự động, kể cả khi thoát app.',
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
      );

  Widget _modeCard(String id, String title, String desc) {
    final sel = createGame == id;
    return GestureDetector(
      onTap: () => setState(() => createGame = id),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: sel ? Colors.orange.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? Colors.deepOrange : Colors.grey.shade300, width: sel ? 3 : 1),
        ),
        child: Column(children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  Widget createScreen() => Center(
        child: SingleChildScrollView(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Chọn kiểu chơi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _modeCard('coop', '🤝 Hợp tác', 'Chung 1 quán: một người nấu, một người phục vụ'),
              _modeCard('race', '🏁 Thi đấu', 'Mỗi người 1 quán, ai bán nhiều món hơn thắng'),
            ]),
            const SizedBox(height: 12),
            if (createGame == 'coop') ...[
              const Text('Bạn muốn đóng vai nào?', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, children: [
                for (final r in ['chef', 'waiter'])
                  ChoiceChip(label: Text(roleName(r), style: const TextStyle(fontSize: 16)), selected: createRole == r, onSelected: (_) => setState(() => createRole = r)),
              ]),
              const SizedBox(height: 6),
              Text('Hàng xóm sẽ nhận vai còn lại: ${roleName(createRole == 'chef' ? 'waiter' : 'chef')}'),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('Mỗi người dùng quán, tiền và nâng cấp của riêng mình. Hai bên bắt đầu ngày cùng lúc.', textAlign: TextAlign.center),
              ),
            const SizedBox(height: 16),
            bigButton('Tạo phòng', createRoom),
            bigButton('⬅ Quay lại', () => setState(() => screen = 'menu'), color: Colors.grey),
          ]),
        ),
      );

  Widget lobbyScreen() => Center(
        child: SingleChildScrollView(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(race ? '🏁 Phòng thi đấu' : '🤝 Phòng hợp tác', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('Mã phòng', style: TextStyle(fontSize: 16)),
            Text(roomCode, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, letterSpacing: 8)),
            if (!race) Text('Bạn: ${roleName(myRole)}  •  Hàng xóm: ${roleName(myRole == 'chef' ? 'waiter' : 'chef')}'),
            const SizedBox(height: 8),
            Text(guestJoined ? '✅ Hàng xóm đã vào phòng!' : '⏳ Đang chờ hàng xóm nhập mã...', style: const TextStyle(fontSize: 16)),
            Text(netStatus, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            bigButton(guestJoined ? '▶ Bắt đầu ngày $day' : '▶ Chơi thử 1 mình (ngày $day)', startDay, color: guestJoined ? null : Colors.orange.shade700),
            if (!guestJoined)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('Chơi thử: bạn lo cả bếp lẫn sảnh. Hàng xóm vẫn có thể nhập mã vào phòng bất cứ lúc nào.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
            bigButton('⬅ Đóng phòng', () => leaveRoom(), color: Colors.grey),
          ]),
        ),
      );

  Widget joinScreen() => Center(
        child: SingleChildScrollView(
          child: Column(children: [
            const Text('Nhập mã phòng của hàng xóm', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              child: TextField(
                controller: codeCtl,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                style: const TextStyle(fontSize: 32, letterSpacing: 6),
                decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ''),
              ),
            ),
            if (mode == 'guest') Padding(padding: const EdgeInsets.all(8), child: Text(netStatus)),
            bigButton(mode == 'guest' ? 'Đang vào phòng...' : 'Vào phòng', mode == 'guest' ? null : joinRoom, color: Colors.indigo),
            bigButton('Quay lại', () {
              if (mode == 'guest') {
                leaveRoom();
              } else {
                setState(() => screen = 'menu');
              }
            }, color: Colors.grey),
          ]),
        ),
      );

  Widget waitScreen() => Center(
        child: SingleChildScrollView(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('✅', style: TextStyle(fontSize: 56)),
            Text('Đã vào phòng $roomCode', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(race ? '🏁 Chế độ thi đấu' : 'Vai của bạn: ${roleName(myRole)}', style: const TextStyle(fontSize: 18)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                race ? 'Chờ chủ phòng bắt đầu ngày mới...\nTrong lúc chờ bạn có thể mua sắm cho quán của mình.' : 'Chờ chủ phòng bắt đầu ngày mới...\n(họ có thể đang mua sắm trong cửa hàng)',
                textAlign: TextAlign.center,
              ),
            ),
            if (race) bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
            bigButton('⬅ Rời phòng', () => leaveRoom(), color: Colors.grey),
          ]),
        ),
      );

  // --- Màn chơi ---
  Widget _chip(String t, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color ?? Colors.white24, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget hud(String role) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3E2723), Color(0xFF6D4C41)])),
        padding: const EdgeInsets.fromLTRB(8, 5, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Wrap(spacing: 4, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(role, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                _chip('📅 $day'),
                _chip('💰 $money'),
                _chip('⏱ ${max(0, timeLeft).ceil()}s', color: timeLeft < 15 ? Colors.red.shade400 : null),
                _chip('🎯 $earned/$goal', color: earned >= goal ? Colors.green.shade600 : null),
                if (race) _chip('🍽️ $served món', color: Colors.blue.shade600),
              ]),
            ),
            // Nút thoát ván
            InkWell(
              onTap: confirmExit,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (earned / goal).clamp(0.0, 1.0),
              minHeight: 4,
              color: Colors.amber,
              backgroundColor: Colors.white24,
            ),
          ),
          SizedBox(
            height: 16,
            child: AnimatedOpacity(
              opacity: msgT > 0 ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(msg, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );

  /// Thanh điểm của đối thủ (thi đấu)
  Widget oppBar() {
    final lead = served - oppServed;
    final st = (mode == 'host' && !guestJoined) ? 'chưa vào phòng' : (peerLost ? 'mất kết nối' : (oppScr == 'end' ? 'đã xong ngày' : 'đang chơi'));
    return Container(
      width: double.infinity,
      color: lead > 0 ? Colors.green.shade700 : (lead < 0 ? Colors.red.shade700 : Colors.blueGrey.shade700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        '🆚 Hàng xóm: 🍽️ $oppServed món • 💰 $oppEarned ($st)   ${lead > 0 ? '👑 Bạn dẫn trước' : (lead < 0 ? '😬 Bạn đang thua' : '🤝 Hoà')}',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget playScreen() {
    // 1 máy hoặc thi đấu: một người lo cả bếp lẫn sảnh.
    // Bếp ở trên, sảnh ở dưới, cùng một hướng nhìn: ô "Quầy ra món" của sảnh nằm sát bếp.
    // Chủ phòng chơi thử khi chưa có ai vào: cũng hiện cả bếp lẫn sảnh.
    if (mode == 'local' || race || (mode == 'host' && !guestJoined)) {
      return Column(children: [
        hud(race ? '🏁 THI ĐẤU' : '🍽️ $kChefName & $kWaiterName'),
        if (race) oppBar(),
        Expanded(flex: 5, child: kitchenBody(compact: true)),
        Container(height: 3, color: Colors.black54),
        Expanded(flex: 6, child: diningBody()),
      ]);
    }
    return Column(children: [
      hud(myRole == 'chef' ? '👨‍🍳 $kChefName' : '🛎️ $kWaiterName'),
      Expanded(child: myRole == 'chef' ? kitchenBody() : diningBody()),
    ]);
  }

  // --- Phục vụ ---
  Widget diningBody() => DiningScene(
        tables: tables,
        counter: counter,
        selDishId: selDishId,
        venueId: venueId,
        decor: decorLv,
        onTable: doTable,
        onDish: onDish,
      );

  // --- Đầu bếp ---
  String ingEmoji(String id) => venue.shelf.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '❓', '?')).emoji;

  Widget kitchenBody({bool compact = false}) => Column(children: [
        ticketRail(compact: compact),
        Expanded(
          child: KitchenScene(
            stations: stations,
            activeStation: activeStation,
            hasOrders: queue.isNotEmpty,
            venueId: venueId,
            ingEmoji: ingEmoji,
            onStation: doStation,
          ),
        ),
        ingredientShelf(compact: compact),
      ]);

  /// Thanh treo phiếu order
  Widget ticketRail({bool compact = false}) => Container(
        height: compact ? 58 : 66,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF90A4AE), Color(0xFF607D8B)]),
        ),
        child: Stack(children: [
          Positioned(left: 0, right: 0, top: 6, child: Container(height: 4, color: const Color(0xFFCFD8DC))),
          queue.isEmpty
              ? const Center(child: Text('Chưa có order nào 💤', style: TextStyle(color: Colors.white70)))
              : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4), children: [
                  for (final tk in queue) _ticketCard(tk),
                ]),
        ]),
      );

  Widget _ticketCard(Ticket tk) {
    final c = tk.table < tables.length ? tables[tk.table].c : null;
    final frac = c == null ? 0.0 : (c.pat / c.maxPat).clamp(0.0, 1.0);
    return Transform.rotate(
      angle: ((tk.id % 3) - 1) * 0.05,
      child: Container(
        width: 60,
        margin: const EdgeInsets.fromLTRB(3, 3, 3, 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDE7),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          Text(tk.recipe.emoji, style: const TextStyle(fontSize: 18)),
          Text('Bàn ${tk.table + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 3,
              color: frac < 0.35 ? Colors.red : Colors.orange,
              backgroundColor: Colors.black12,
            ),
          ),
        ]),
      ),
    );
  }

  /// Kệ nguyên liệu bằng gỗ
  Widget ingredientShelf({bool compact = false}) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(4, compact ? 5 : 8, 4, compact ? 5 : 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA1887F), Color(0xFF6D4C41)]),
          border: Border(top: BorderSide(color: Color(0xFF4E342E), width: 4)),
        ),
        child: Wrap(alignment: WrapAlignment.center, spacing: compact ? 4 : 6, runSpacing: compact ? 4 : 6, children: [
          for (final ing in venue.shelf)
            Material(
              color: const Color(0xFFFFF8E1),
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => doIngredient(ing.id),
                child: SizedBox(
                  width: compact ? 46 : 56,
                  height: compact ? 46 : 54,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(ing.emoji, style: TextStyle(fontSize: compact ? 20 : 24)),
                    Text(ing.name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
            ),
        ]),
      );

  // --- Kết thúc ngày ---
  Widget raceResult() {
    if (mode == 'host' && !guestJoined) {
      return const Text('🧪 Chơi thử một mình – chưa có đối thủ', style: TextStyle(fontSize: 15));
    }
    if (oppScr != 'end') {
      return const Text('⏳ Đang chờ hàng xóm phục vụ nốt khách...', style: TextStyle(fontSize: 15));
    }
    final diff = served != oppServed ? served - oppServed : earned - oppEarned;
    final title = diff > 0 ? '🏆 Bạn thắng!' : (diff < 0 ? '😢 Hàng xóm thắng' : '🤝 Hoà!');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.orange, width: 2)),
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Table(defaultColumnWidth: const IntrinsicColumnWidth(), children: [
          const TableRow(children: [Text(''), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Bạn', style: TextStyle(fontWeight: FontWeight.bold))), Text('Hàng xóm', style: TextStyle(fontWeight: FontWeight.bold))]),
          TableRow(children: [const Text('🍽️ Món bán'), Center(child: Text('$served')), Center(child: Text('$oppServed'))]),
          TableRow(children: [const Text('💰 Thu nhập'), Center(child: Text('$earned')), Center(child: Text('$oppEarned'))]),
        ]),
      ]),
    );
  }

  Widget endScreen() {
    final avg = starsLog.isEmpty ? 0.0 : starsLog.reduce((a, b) => a + b) / starsLog.length;
    final prevGoal = 150 + (day - 1) * 60; // day đã tăng sau khi kết thúc ngày
    final reached = earned >= prevGoal;
    final isGuest = mode == 'guest';
    final bk = _bk;
    return Center(
      child: SingleChildScrollView(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (race) ...[raceResult(), const SizedBox(height: 16)],
          Text(reached ? '🎉 Đạt mục tiêu! (+50 thưởng)' : '😅 Chưa đạt mục tiêu', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Thu nhập ngày: $earned / $prevGoal'),
          Text('Đã phục vụ: $served   •   Khách bỏ về: $lost'),
          Text('Đánh giá TB: ${avg.toStringAsFixed(1)} ⭐'),
          if (remote && bk != null)
            Text('Quán của bạn cũng nhận +$earned 💰 (tổng: ${bk[0]})', style: const TextStyle(fontWeight: FontWeight.bold))
          else
            Text('Tổng tiền quán: 💰 $money'),
          const Text('💾 Đã lưu tiến trình', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 20),
          if (isGuest) ...[
            if (race) bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
            const Padding(padding: EdgeInsets.all(8), child: Text('Chờ chủ phòng bắt đầu ngày tiếp theo...')),
          ] else ...[
            bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
            bigButton(
              race && guestJoined && oppScr == 'play' && !peerLost ? '⏳ Chờ hàng xóm xong ngày' : '▶ Ngày tiếp theo',
              race && guestJoined && oppScr == 'play' && !peerLost ? null : startDay,
            ),
          ],
          bigButton(mode == 'local' ? '⬅ Về menu' : '⬅ Rời phòng', () {
            if (mode == 'local') {
              setState(() => screen = 'menu');
            } else {
              leaveRoom();
            }
          }, color: Colors.grey),
        ]),
      ),
    );
  }

  // --- Cửa hàng (chỉ local / host) ---
  Widget shopScreen() {
    Widget header(String t) => Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 4), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)));
    return Column(children: [
      Container(
        color: Colors.teal,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          IconButton(onPressed: () => setState(() => screen = shopBack), icon: const Icon(Icons.arrow_back, color: Colors.white)),
          Text('Cửa hàng   💰 $money', style: const TextStyle(color: Colors.white, fontSize: 20)),
        ]),
      ),
      Expanded(
        child: ListView(children: [
          header('🔧 Nâng cấp & trang trí'),
          for (final u in upgrades)
            ListTile(
              leading: Text(u.emoji, style: const TextStyle(fontSize: 28)),
              title: Text('${u.name}  (${lvl(u.id)}/${u.max})'),
              subtitle: Text(u.desc),
              trailing: lvl(u.id) >= u.max
                  ? const Text('MAX')
                  : ElevatedButton(
                      onPressed: () {
                        if (pay(u.cost(lvl(u.id)))) {
                          lv[u.id] = lvl(u.id) + 1;
                          save();
                          setState(() {});
                        }
                      },
                      child: Text('💰${u.cost(lvl(u.id))}')),
            ),
          header('📖 Công thức mới – ${venue.emoji} ${venue.name}'),
          for (final r in venue.recipes)
            ListTile(
              leading: Text(r.emoji, style: const TextStyle(fontSize: 28)),
              title: Text('${r.name}  •  💰${r.price}'),
              subtitle: Text('${r.ings.map(ingEmoji).join(' ')}   ⏱${r.cook}s'),
              trailing: recipes.contains(r.id)
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : ElevatedButton(
                      onPressed: () {
                        if (pay(r.unlock)) {
                          recipes.add(r.id);
                          save();
                          setState(() {});
                        }
                      },
                      child: Text('💰${r.unlock}')),
            ),
          header('🏪 Chi nhánh & mô hình kinh doanh'),
          for (final v in venues)
            ListTile(
              leading: Text(v.emoji, style: const TextStyle(fontSize: 28)),
              title: Text(v.name),
              subtitle: Text('Tối đa ${v.maxTables} bàn  •  ${v.recipes.length} món'),
              selected: v.id == venueId,
              trailing: owned.contains(v.id)
                  ? (v.id == venueId
                      ? const Text('Đang dùng')
                      : OutlinedButton(
                          onPressed: () {
                            venueId = v.id;
                            activeStation = -1;
                            save();
                            setState(() {});
                          },
                          child: const Text('Chuyển')))
                  : ElevatedButton(
                      onPressed: () {
                        if (pay(v.cost)) {
                          owned.add(v.id);
                          recipes.addAll(v.recipes.where((r) => r.unlock == 0).map((r) => r.id));
                          venueId = v.id;
                          save();
                          setState(() {});
                        }
                      },
                      child: Text('💰${v.cost}')),
            ),
          const SizedBox(height: 30),
        ]),
      ),
    ]);
  }
}