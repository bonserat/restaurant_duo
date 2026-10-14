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

class _GamePageState extends State<GamePage> {
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
  int get decorLv => mode == 'guest' ? hostDecor : lvl('decor');
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
    load();
  }

  @override
  void dispose() {
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
    if (mode == 'guest') return; // khách không ghi đè dữ liệu của mình
    final p = await SharedPreferences.getInstance();
    await p.setString('save', jsonEncode({'money': money, 'day': day, 'lv': lv, 'recipes': recipes.toList(), 'owned': owned.toList(), 'venue': venueId}));
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

  void applySnapshot(Map<String, dynamic> m) {
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
      final scr = m['scr'];
      screen = (scr == 'play' || scr == 'end') ? scr : 'wait';
    });
  }

  void onNet(Map<String, dynamic> m) {
    lastPeer = DateTime.now();
    final t = m['t'];
    if (mode == 'host') {
      if (t == 'join') {
        guestJoined = true;
        net.send(snapshot());
        setState(() {});
      } else if (t == 'act') {
        applyAction(m);
      } else if (t == 'bye') {
        lastPeer = DateTime(2000);
        setState(() {});
      }
    } else if (mode == 'guest') {
      if (t == 'state') {
        applySnapshot(m);
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
    myRole = createRole;
    guestJoined = false;
    lastPeer = DateTime.now();
    netStatus = 'Đang kết nối...';
    setState(() => screen = 'lobby');
    await net.connect(roomCode, onNet, () {
      if (mounted) setState(() => netStatus = 'Phòng đã mở');
      net.send(snapshot());
    }, (e) {
      if (mounted) setState(() => netStatus = 'Lỗi kết nối: $e');
    });
    netTimer?.cancel();
    netTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mode == 'host') net.send(snapshot());
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
      if (mode == 'guest') net.send({'t': 'join'}); // vừa là xin vào, vừa là ping
      if (mounted) setState(() {});
    });
  }

  Future<void> leaveRoom({String? notice}) async {
    net.send({'t': 'bye'});
    await Future.delayed(const Duration(milliseconds: 300));
    netTimer?.cancel();
    timer?.cancel();
    await net.disconnect();
    if (mode == 'guest' && _bk != null) {
      money = _bk![0];
      day = _bk![1];
      venueId = _bk![2];
      _bk = null;
    }
    mode = 'local';
    myRole = 'both';
    guestJoined = false;
    joined = false;
    roomCode = '';
    selDishId = null;
    if (!mounted) return;
    setState(() => screen = 'menu');
    if (notice != null) snack(notice);
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
    setState(() => screen = 'play');
    if (mode == 'host') net.send(snapshot());
  }

  void endDay() {
    timer?.cancel();
    if (earned >= goal) money += 50;
    day++;
    save();
    setState(() => screen = 'end');
    if (mode == 'host') net.send(snapshot());
  }

  void tick(double dt) {
    if (screen != 'play' || mode == 'guest') return;
    if (peerLost) {
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
    if (mode == 'host' && tickN % 2 == 0) net.send(snapshot());
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
    if (mode == 'guest') {
      net.send({'t': 'act', 'a': 'table', 'i': i, 'd': selDishId});
    } else {
      onTable(i, selDishId);
      if (mode == 'host') net.send(snapshot());
    }
    if (waiting) selDishId = null;
    setState(() {});
  }

  void doStation(int i) {
    if (mode == 'guest') {
      net.send({'t': 'act', 'a': 'station', 'i': i});
    } else {
      onStation(i);
      if (mode == 'host') net.send(snapshot());
    }
    setState(() {});
  }

  void doIngredient(String id) {
    if (mode == 'guest') {
      net.send({'t': 'act', 'a': 'ing', 'id': id});
    } else {
      onIngredient(id);
      if (mode == 'host') net.send(snapshot());
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
    return Scaffold(
      backgroundColor: const Color(0xFFFFF3E0),
      body: SafeArea(
        child: Column(children: [
          if (peerLost)
            Container(
              width: double.infinity,
              color: Colors.red,
              padding: const EdgeInsets.all(6),
              child: const Text('⚠️ Mất kết nối với hàng xóm… ván tạm dừng', style: TextStyle(color: Colors.white), textAlign: TextAlign.center),
            ),
          Expanded(child: body),
        ]),
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

  String roleName(String r) => r == 'chef' ? '👨‍🍳 Đầu bếp' : '🛎️ Phục vụ';

  // --- Menu & phòng ---
  Widget menuScreen() => Center(
        child: SingleChildScrollView(
          child: Column(children: [
            const Text('🍽️', style: TextStyle(fontSize: 64)),
            const Text('Nhà Hàng Đôi', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            Text('Ngày $day  •  💰 $money  •  ${venue.emoji} ${venue.name}'),
            const SizedBox(height: 16),
            bigButton('🌐 Tạo phòng (mời hàng xóm)', () => setState(() => screen = 'create')),
            bigButton('🔑 Vào phòng bằng mã', () => setState(() => screen = 'join'), color: Colors.indigo),
            bigButton('📱 Chơi chung 1 máy', () {
              mode = 'local';
              myRole = 'both';
              startDay();
            }, color: Colors.green),
            bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '👨‍🍳 ĐẦU BẾP: chạm bếp nhận đơn → chạm đúng nguyên liệu → chờ chín → chạm bếp lấy món ra quầy (đừng để cháy!).\n\n'
                '🛎️ PHỤC VỤ: chạm khách để nhận món → chạm món ở quầy rồi chạm đúng bàn để phục vụ → chạm bàn bẩn để dọn.\n\n'
                'Chơi online: một người tạo phòng, người kia nhập mã 4 ký tự. Tiền và tiến trình được lưu trên máy chủ phòng.',
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
      );

  Widget createScreen() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Bạn muốn đóng vai nào?', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            for (final r in ['chef', 'waiter'])
              ChoiceChip(label: Text(roleName(r), style: const TextStyle(fontSize: 16)), selected: createRole == r, onSelected: (_) => setState(() => createRole = r)),
          ]),
          const SizedBox(height: 6),
          Text('Hàng xóm sẽ nhận vai còn lại: ${roleName(createRole == 'chef' ? 'waiter' : 'chef')}'),
          const SizedBox(height: 16),
          bigButton('Tạo phòng', createRoom),
          bigButton('Quay lại', () => setState(() => screen = 'menu'), color: Colors.grey),
        ]),
      );

  Widget lobbyScreen() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Mã phòng', style: TextStyle(fontSize: 16)),
          Text(roomCode, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, letterSpacing: 8)),
          Text('Bạn: ${roleName(myRole)}  •  Hàng xóm: ${roleName(myRole == 'chef' ? 'waiter' : 'chef')}'),
          const SizedBox(height: 8),
          Text(guestJoined ? '✅ Hàng xóm đã vào phòng!' : '⏳ Đang chờ hàng xóm nhập mã...', style: const TextStyle(fontSize: 16)),
          Text(netStatus, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          bigButton('▶ Bắt đầu ngày $day', guestJoined ? startDay : null),
          bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
          bigButton('Đóng phòng', () => leaveRoom(), color: Colors.grey),
        ]),
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('✅', style: TextStyle(fontSize: 56)),
          Text('Đã vào phòng $roomCode', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text('Vai của bạn: ${roleName(myRole)}', style: const TextStyle(fontSize: 18)),
          const Padding(padding: EdgeInsets.all(16), child: Text('Chờ chủ phòng bắt đầu ngày mới...\n(họ có thể đang mua sắm trong cửa hàng)', textAlign: TextAlign.center)),
          bigButton('Rời phòng', () => leaveRoom(), color: Colors.grey),
        ]),
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
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 4, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(role, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            _chip('📅 $day'),
            _chip('💰 $money'),
            _chip('⏱ ${max(0, timeLeft).ceil()}s', color: timeLeft < 15 ? Colors.red.shade400 : null),
            _chip('🎯 $earned/$goal', color: earned >= goal ? Colors.green.shade600 : null),
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

  Widget playScreen() {
    if (mode == 'local') {
      return Column(children: [
        Expanded(child: RotatedBox(quarterTurns: 2, child: waiterPanel())),
        Container(height: 3, color: Colors.black),
        Expanded(child: chefPanel()),
      ]);
    }
    return myRole == 'chef' ? chefPanel() : waiterPanel();
  }

  // --- Phục vụ ---
  Widget waiterPanel() => Column(children: [
        hud('🛎️ PHỤC VỤ'),
        Expanded(
          child: DiningScene(
            tables: tables,
            counter: counter,
            selDishId: selDishId,
            venueId: venueId,
            decor: decorLv,
            onTable: doTable,
            onDish: onDish,
          ),
        ),
      ]);

  // --- Đầu bếp ---
  String ingEmoji(String id) => venue.shelf.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '❓', '?')).emoji;

  Widget chefPanel() => Column(children: [
        hud('👨‍🍳 ĐẦU BẾP'),
        ticketRail(),
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
        ingredientShelf(),
      ]);

  /// Thanh treo phiếu order
  Widget ticketRail() => Container(
        height: 66,
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
        margin: const EdgeInsets.fromLTRB(3, 4, 3, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDE7),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          Text(tk.recipe.emoji, style: const TextStyle(fontSize: 20)),
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
  Widget ingredientShelf() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA1887F), Color(0xFF6D4C41)]),
          border: Border(top: BorderSide(color: Color(0xFF4E342E), width: 4)),
        ),
        child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (final ing in venue.shelf)
            Material(
              color: const Color(0xFFFFF8E1),
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => doIngredient(ing.id),
                child: SizedBox(
                  width: 56,
                  height: 54,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(ing.emoji, style: const TextStyle(fontSize: 24)),
                    Text(ing.name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
            ),
        ]),
      );

  // --- Kết thúc ngày ---
  Widget endScreen() {
    final avg = starsLog.isEmpty ? 0.0 : starsLog.reduce((a, b) => a + b) / starsLog.length;
    final prevGoal = 150 + (day - 1) * 60; // day đã tăng sau khi kết thúc ngày
    final reached = earned >= prevGoal;
    final isGuest = mode == 'guest';
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(reached ? '🎉 Đạt mục tiêu! (+50 thưởng)' : '😅 Chưa đạt mục tiêu', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text('Thu nhập ngày: $earned / $prevGoal'),
        Text('Đã phục vụ: $served   •   Khách bỏ về: $lost'),
        Text('Đánh giá TB: ${avg.toStringAsFixed(1)} ⭐'),
        Text('Tổng tiền quán: 💰 $money'),
        const SizedBox(height: 20),
        if (isGuest)
          const Padding(padding: EdgeInsets.all(8), child: Text('Chờ chủ phòng chọn bước tiếp theo...'))
        else ...[
          bigButton('🛒 Cửa hàng', () => setState(() => screen = 'shop'), color: Colors.teal),
          bigButton('▶ Ngày tiếp theo', startDay),
        ],
        bigButton(mode == 'local' ? 'Menu' : 'Rời phòng', () {
          if (mode == 'local') {
            setState(() => screen = 'menu');
          } else {
            leaveRoom();
          }
        }, color: Colors.grey),
      ]),
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
          IconButton(onPressed: () => setState(() => screen = mode == 'host' ? 'lobby' : 'menu'), icon: const Icon(Icons.arrow_back, color: Colors.white)),
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
