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
import 'sound.dart';

bool get onlineConfigured => !kSupabaseUrl.contains('YOUR_');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (onlineConfigured) {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  }
  await Sound.init();
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
  String hostStyle = 'classic';
  bool hostCast = false;
  // Hiệu ứng ăn mừng khi đạt mục tiêu giữa ván
  bool goalHit = false;
  bool resultPlayed = false;
  DateTime? goalBurstAt;
  int goalBurstKey = 0;

  // --- Lưu trữ ---
  int money = 0, day = 1;
  Map<String, int> lv = {};
  Set<String> recipes = {};
  Set<String> owned = {'cafe'};
  String venueId = 'cafe';
  String style = 'classic'; // hoạt cảnh nhà hàng
  Set<String> styles = {'classic'};
  bool ngocAnhChef = false; // false: Nguyên nấu, Ngọc Anh phục vụ | true: ngược lại
  String owner = ''; // chủ quán của máy này: Nguyên hoặc Ngọc Anh (mỗi người một nhà hàng riêng)
  Set<String> pets = {'cat'};
  Map<String, int> petHappy = {'cat': 70};
  List<Deco> decos = [];
  List<Offset?> tablePos = List<Offset?>.filled(12, null); // vị trí bàn tự sắp (null = mặc định)
  String light = 'day';
  Map<String, int> npcVisits = {};
  // Thông tin quán của chủ phòng (khi mình đang giúp ở chế độ hợp tác)
  String hostOwner = '', hostLight = 'day', oppOwner = '';
  List<String> hostPets = [];
  List<Deco> hostDecos = [];
  List<Offset?> hostTablePos = List<Offset?>.filled(12, null);

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
  List<Incident> incidents = [];
  int incSeq = 0;
  double incT = 30;
  String? tool; // dụng cụ đang cầm (mỗi máy tự chọn)

  Venue get venue => venueById(venueId);
  int lvl(String id) => lv[id] ?? 0;
  /// 0 ở ngày đầu → 1 từ ngày 13: dùng để tăng độ khó từ từ
  double get ease => ((day - 1) / 12).clamp(0.0, 1.0).toDouble();
  int goalFor(int d) => 80 + d * 50 + (d > 6 ? (d - 6) * 20 : 0);
  int get goal => goalFor(day);
  double get burnTime => 12 - 5 * ease; // giây món chín chờ trước khi cháy
  String get styleNow => remote ? hostStyle : style;
  bool get castNA => remote ? hostCast : ngocAnhChef;
  String get chefName => castNA ? kNgocAnh : kNguyen;
  String get waiterName => castNA ? kNguyen : kNgocAnh;
  int get decorLv => remote ? hostDecor : lvl('decor');
  String get ownerNow => remote ? hostOwner : owner;
  String get shopName => ownerNow.isEmpty ? 'Nhà Hàng Đôi' : 'Nhà hàng của $ownerNow';
  bool petOn(String id) => pets.contains(id) && (petHappy[id] ?? 0) >= 40;
  List<String> get petsNow => remote ? hostPets : pets.toList();
  List<Deco> get decosNow => remote ? hostDecos : decos;
  List<Offset?> get tablePosNow => remote ? hostTablePos : tablePos;
  String get lightNow => remote ? hostLight : light;
  bool incOn(String type) => incidents.any((x) => x.type == type);
  bool get sweetVenue => seasonName(venueId) == 'Đường';
  String tasteWord(String taste) => taste == 'Đậm' ? (sweetVenue ? 'ngọt gắt' : 'mặn') : taste.toLowerCase();
  /// Khách trong chế độ hợp tác: chỉ hiển thị, mọi thao tác gửi lên chủ phòng
  bool get remote => mode == 'guest' && gameType == 'coop';
  bool get race => mode != 'local' && gameType == 'race';
  /// Thi đấu có đối thủ thật (khách luôn có chủ phòng; chủ phòng cần khách đã vào)
  bool get hasOpp => race && (mode == 'guest' || guestJoined);
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
    // Thoát ra màn hình chính / tắt app → lưu ngay, tạm dừng nhạc
    if (state == AppLifecycleState.resumed) {
      Sound.resume();
    } else {
      save();
      Sound.pause();
    }
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

  List<Offset?> parsePos(dynamic v) {
    final out = List<Offset?>.filled(12, null);
    if (v is List) {
      for (var i = 0; i < v.length && i < 12; i++) {
        final e = v[i];
        if (e is List && e.length == 2) out[i] = Offset((e[0] as num).toDouble(), (e[1] as num).toDouble());
      }
    }
    return out;
  }

  List<dynamic> posJson(List<Offset?> ps) => [for (final o in ps) o == null ? null : [r2(o.dx), r2(o.dy)]];

  List<Deco> parseDecos(dynamic v) => [
        if (v is List)
          for (final e in v) Deco.fromJson(Map<String, dynamic>.from(e as Map))
      ];

  void resetData() {
    money = 0;
    day = 1;
    lv = {};
    recipes = venueById('cafe').recipes.where((r) => r.unlock == 0).map((r) => r.id).toSet();
    owned = {'cafe'};
    venueId = 'cafe';
    style = 'classic';
    styles = {'classic'};
    pets = {'cat'};
    petHappy = {'cat': 70};
    decos = [];
    tablePos = List<Offset?>.filled(12, null);
    light = 'day';
    npcVisits = {};
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    owner = p.getString('owner') ?? '';
    Sound.setEnabled(p.getBool('sound') ?? true);
    ngocAnhChef = p.getBool('cast') ?? false;
    if (owner.isEmpty) {
      if (mounted) setState(() => screen = 'profile');
      return;
    }
    await loadData();
  }

  /// Tải dữ liệu nhà hàng của [owner] (mỗi chủ quán một bản lưu riêng)
  Future<void> loadData() async {
    final p = await SharedPreferences.getInstance();
    var s = p.getString('save_$owner');
    if (s == null && !(p.getBool('migrated') ?? false)) {
      s = p.getString('save'); // bản lưu cũ trước khi có chủ quán
      await p.setBool('migrated', true);
    }
    resetData();
    if (s != null) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      money = m['money'] ?? 0;
      day = m['day'] ?? 1;
      lv = Map<String, int>.from(m['lv'] ?? {});
      recipes = Set<String>.from(m['recipes'] ?? recipes);
      owned = Set<String>.from(m['owned'] ?? owned);
      venueId = m['venue'] ?? 'cafe';
      style = m['style'] ?? 'classic';
      styles = Set<String>.from(m['styles'] ?? ['classic']);
      pets = Set<String>.from(m['pets'] ?? ['cat']);
      petHappy = Map<String, int>.from(m['petHappy'] ?? {'cat': 70});
      decos = parseDecos(m['decos']);
      tablePos = parsePos(m['tablePos']);
      light = m['light'] ?? 'day';
      npcVisits = Map<String, int>.from(m['npc'] ?? {});
    }
    if (mounted) setState(() {});
  }

  Future<void> chooseOwner(String o) async {
    if (owner.isNotEmpty && owner != o) await save();
    owner = o;
    final p = await SharedPreferences.getInstance();
    await p.setString('owner', o);
    await loadData();
    if (mounted) setState(() => screen = 'menu');
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sound', Sound.enabled);
    await p.setBool('cast', ngocAnhChef);
    if (owner.isEmpty) return;
    var m0 = money, d0 = day, v0 = venueId;
    if (remote) {
      // Đang ở quán của người khác: lưu dữ liệu quán của MÌNH (đã sao lưu khi vào phòng)
      final bk = _bk;
      if (bk == null) return;
      m0 = bk[0] as int;
      d0 = bk[1] as int;
      v0 = bk[2] as String;
    }
    await p.setString(
      'save_$owner',
      jsonEncode({
        'money': m0,
        'day': d0,
        'lv': lv,
        'recipes': recipes.toList(),
        'owned': owned.toList(),
        'venue': v0,
        'style': style,
        'styles': styles.toList(),
        'pets': pets.toList(),
        'petHappy': petHappy,
        'decos': decos.map((d) => d.toJson()).toList(),
        'tablePos': posJson(tablePos),
        'light': light,
        'npc': npcVisits,
      }),
    );
  }

  void say(String m, [double sec = 3]) {
    msg = m;
    msgT = sec;
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
        'sy': style,
        'cn': ngocAnhChef,
        'own': owner,
        'li': light,
        'pt': pets.where((id) => (petHappy[id] ?? 0) > 0).toList(),
        'tp': posJson(tablePos),
        'de': decos.map((d) => d.toJson()).toList(),
        'inc': incidents.map((e) => e.toJson()).toList(),
        'tb': tables.map((e) => e.toJson()).toList(),
        'q': queue.map((e) => e.toJson()).toList(),
        'st': stations.map((e) => e.toJson()).toList(),
        'ct': counter.map((e) => e.toJson()).toList(),
        'act': activeStation,
        'msg': msg,
        'mt': r2(msgT),
        'sl': starsLog,
      };

  Map<String, dynamic> raceStatus() => {'t': 'race', 'scr': screen, 'sv': served, 'ea': earned, 'tl': r2(timeLeft), 'day': day, 'own': owner};

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
      hostStyle = m['sy'] as String? ?? 'classic';
      hostCast = m['cn'] == true;
      hostOwner = m['own'] as String? ?? '';
      hostLight = m['li'] as String? ?? 'day';
      hostPets = List<String>.from((m['pt'] as List?) ?? const []);
      hostTablePos = parsePos(m['tp']);
      hostDecos = parseDecos(m['de']);
      incidents = m['inc'] == null ? [] : lst('inc', Incident.fromJson);
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
      if (scr == 'play' && screen != 'play') resultPlayed = false;
      screen = (scr == 'play' || scr == 'end') ? scr : 'wait';
    });
    checkGoal();
    if (screen == 'end') playResult();
    if (reward) save();
  }

  void applyRace(Map<String, dynamic> m) {
    oppServed = (m['sv'] as num?)?.toInt() ?? 0;
    oppEarned = (m['ea'] as num?)?.toInt() ?? 0;
    oppScr = m['scr'] as String? ?? 'wait';
    oppOwner = m['own'] as String? ?? oppOwner;
    playResult();
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
        onIngredient(m['id'] as String, (m['st'] as num?)?.toInt());
        break;
      case 'heat':
        onHeat((m['i'] as num).toInt(), (m['d'] as num).toDouble());
        break;
      case 'inc':
        onIncident((m['id'] as num).toInt(), m['tool'] as String?);
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
      case 'pets':
      case 'layout':
        setState(() => screen = 'menu');
        break;
      case 'profile':
        if (owner.isEmpty) {
          SystemNavigator.pop();
        } else {
          setState(() => screen = 'menu');
        }
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
    tables = List.generate(min(4 + lvl('tables'), venue.maxTables), (_) => TableS());
    stations = List.generate(2 + lvl('stations'), (_) => Station());
    queue = [];
    counter = [];
    incidents = [];
    incT = 25 + rnd.nextDouble() * 15;
    tool = null;
    earned = 0;
    served = 0;
    lost = 0;
    starsLog = [];
    timeLeft = 120 - 25 * ease; // ngày đầu dài 120 giây
    goalHit = false;
    goalBurstAt = null;
    spawnT = 1;
    activeStation = -1;
    selDishId = null;
    msg = '';
    msgT = 0;
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) => tick(0.1));
    paused = false;
    resultPlayed = false;
    setState(() => screen = 'play');
    if (day == 2) say('⚠️ Từ hôm nay có thể xảy ra sự cố! Chọn đúng dụng cụ rồi chạm vào chỗ có sự cố.', 5);
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
    // thú cưng đói dần qua mỗi ngày, nhớ cho ăn và vuốt ve
    for (final id in pets) {
      petHappy[id] = max(0, (petHappy[id] ?? 50) - 20);
    }
    incidents = [];
    tool = null;
    save();
    setState(() => screen = 'end');
    playResult();
    if (race) {
      net.send(raceStatus());
    } else if (mode == 'host') {
      net.send(snapshot());
    }
  }

  void spawnCustomer(int ti, double maxPat) {
    final avail = venue.recipes.where((r) => recipes.contains(r.id)).toList();
    if (avail.isEmpty) return;
    NpcType? npc;
    if (day >= 2) {
      var roll = rnd.nextDouble();
      for (final n in npcTypes) {
        if (roll < n.chance) {
          npc = n;
          break;
        }
        roll -= n.chance;
      }
    }
    var r = avail[rnd.nextInt(avail.length)];
    if (npc != null) {
      final sorted = [...avail]..sort((a, b) => a.price.compareTo(b.price));
      if (npc.id == 'vip') r = sorted.last; // VIP gọi món đắt nhất
      if (npc.id == 'student') r = sorted.first; // học sinh gọi món rẻ nhất
      if (npc.id == 'hunter') {
        final meaty = avail.where((x) => x.ings.contains('meat')).toList();
        if (meaty.isNotEmpty) r = meaty[rnd.nextInt(meaty.length)]; // thợ săn mê thịt
      }
    }
    final c = Cust(r, maxPat * (npc?.patMul ?? 1));
    if (npc != null) {
      c.npc = npc.id;
      c.saltPref = npc.saltPref;
      final v = npcVisits[npc.id] ?? 0;
      c.line = min(v, npc.lines.length - 1);
      npcVisits[npc.id] = v + 1;
      say('${npc.emoji} ${npc.name} (${npc.title}) vừa tới!');
    }
    tables[ti].c = c;
  }

  void tick(double dt) {
    if (screen != 'play' || remote || paused) return;
    if (peerLost && !race) {
      setState(() {}); // tạm dừng khi đối tác mất kết nối
      return;
    }
    timeLeft -= dt;
    if (msgT > 0) msgT -= dt;
    final power = incOn('power');
    // khách kiên nhẫn hơn ở những ngày đầu; trang trí và vẹt giúp khách chờ lâu hơn
    final maxPat = 90 - 35 * ease + 8 * lvl('decor') + min(10, decos.length) + (petOn('parrot') ? 10 : 0);

    if (timeLeft > 0) {
      spawnT -= dt;
      if (spawnT <= 0) {
        final free = [
          for (var i = 0; i < tables.length; i++)
            if (tables[i].c == null && !tables[i].dirty) i
        ];
        if (free.isNotEmpty) spawnCustomer(free[rnd.nextInt(free.length)], maxPat);
        spawnT = max(2.5, (5 + rnd.nextDouble() * 4) * (1.5 - 0.6 * ease) * venue.spawnMul); // khách đến thưa lúc đầu, dày dần
      }
    }

    // Sự cố làm khách sốt ruột hơn, mèo giúp khách bình tĩnh
    final brawlTables = incidents.where((x) => x.type == 'brawl').map((x) => x.target).toSet();
    var drain = 1.0;
    if (incOn('rat')) drain *= 1.4;
    if (incOn('leak')) drain *= 1.25;
    if (power) drain *= 1.15;
    if (brawlTables.isNotEmpty) drain *= 1.5;
    if (petOn('cat')) drain *= 0.85;
    final catT = catTable();

    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      final c = t.c;
      if (c != null) {
        if (c.st < 2) {
          var d = brawlTables.contains(i) ? 1.0 : drain;
          if (i == catT) d *= 0.5;
          c.pat -= dt * d;
          if (c.pat <= 0) {
            queue.removeWhere((x) => x.id == c.ticketId);
            lost++;
            starsLog.add(1);
            say(c.npc == 'vip' ? '👑 Ông Bảy bực mình bỏ về!' : '😡 Chờ lâu quá, tôi đi đây!');
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

    // Bếp: canh lửa, nấu, chờ lấy món
    final fireSt = incidents.where((x) => x.type == 'fire').map((x) => x.target).toSet();
    for (var si = 0; si < stations.length; si++) {
      final s = stations[si];
      if (s.t == null) continue;
      if (!tables.any((t) => t.c?.ticketId == s.t!.id)) {
        s.clear();
        continue;
      }
      if (power || fireSt.contains(si)) continue; // mất điện / đang cháy: bếp ngừng
      if (s.cooking) {
        // lửa tự bùng lên dần, người chơi vặn núm − / + để giữ trong vùng xanh
        s.heat = (s.heat + (rnd.nextDouble() - 0.3) * dt * (0.18 + 0.3 * ease)).clamp(0.0, 1.0).toDouble();
        final rate = s.heat < 0.3 ? 0.45 : (s.heat <= 0.75 ? 1.0 : 1.3);
        if (s.heat < 0.3 || s.heat > 0.75) s.heatBad += dt;
        if (s.heat > 0.92) {
          s.hot += dt;
        } else {
          s.hot = max(0.0, s.hot - dt);
        }
        if (s.hot > 2.5) {
          addIncident('fire', target: si);
          s.hot = 0;
          s.heat = 0.55;
        }
        s.prog += dt * rate;
        if (s.prog >= s.need) s.done = true;
      } else if (s.done) {
        s.doneT += dt;
        if (s.doneT > burnTime) s.burnt = true;
      }
    }

    updateIncidents(dt);

    counter.removeWhere((d) => !tables.any((t) => t.c?.ticketId == d.ticketId));
    if (selDishId != null && !counter.any((d) => d.ticketId == selDishId)) selDishId = null;

    if (timeLeft <= 0 && tables.every((t) => t.c == null)) {
      endDay();
      return;
    }
    checkGoal();
    tickN++;
    if (race) {
      if (tickN % 5 == 0) net.send(raceStatus());
    } else if (mode == 'host' && tickN % 2 == 0) {
      net.send(snapshot());
    }
    setState(() {});
  }

  /// Bàn có khách sốt ruột nhất – mèo sẽ tới nằm cạnh
  int catTable() {
    if (!petOn('cat')) return -1;
    var best = -1;
    var bestF = 2.0;
    for (var i = 0; i < tables.length; i++) {
      final c = tables[i].c;
      if (c == null || c.st >= 2) continue;
      final f = c.pat / c.maxPat;
      if (f < bestF) {
        bestF = f;
        best = i;
      }
    }
    return best;
  }

  // ---------- Sự cố ----------
  void addIncident(String type, {int target = -1}) {
    if (type == 'fire') {
      if (incidents.any((x) => x.type == 'fire' && x.target == target)) return;
    } else if (incOn(type)) {
      return;
    }
    final it = incidentType(type);
    incidents.add(Incident(
      ++incSeq,
      type,
      target,
      0.2 + rnd.nextDouble() * 0.6,
      0.25 + rnd.nextDouble() * 0.6,
      it.hp,
      vx: (rnd.nextDouble() - 0.5) * 0.6,
      vy: (rnd.nextDouble() - 0.5) * 0.5,
    ));
    say('${it.emoji} ${it.name}! ${it.hint}', 5);
  }

  void randomIncident() {
    if (incidents.length >= 2) return;
    final opts = <String>['power', 'rat', 'leak'];
    final cook = [
      for (var i = 0; i < stations.length; i++)
        if (stations[i].cooking) i
    ];
    if (cook.isNotEmpty) opts.add('fire');
    final wait = [
      for (var i = 0; i < tables.length; i++)
        if (tables[i].c != null && tables[i].c!.st < 2) i
    ];
    if (wait.isNotEmpty) opts.add('brawl');
    opts.removeWhere(incOn);
    if (opts.isEmpty) return;
    final k = opts[rnd.nextInt(opts.length)];
    if (k == 'fire') {
      addIncident(k, target: cook[rnd.nextInt(cook.length)]);
    } else if (k == 'brawl') {
      addIncident(k, target: wait[rnd.nextInt(wait.length)]);
    } else {
      addIncident(k);
    }
  }

  void updateIncidents(double dt) {
    for (final inc in [...incidents]) {
      inc.age += dt;
      switch (inc.type) {
        case 'rat':
          inc.x += inc.vx * dt;
          inc.y += inc.vy * dt;
          if (inc.x < 0.05 || inc.x > 0.95) inc.vx = -inc.vx;
          if (inc.y < 0.1 || inc.y > 0.95) inc.vy = -inc.vy;
          inc.x = inc.x.clamp(0.05, 0.95).toDouble();
          inc.y = inc.y.clamp(0.1, 0.95).toDouble();
          if (rnd.nextDouble() < dt * 0.6) {
            inc.vx = (rnd.nextDouble() - 0.5) * 0.6;
            inc.vy = (rnd.nextDouble() - 0.5) * 0.5;
          }
          if (petOn('dog') && inc.age > 4) {
            inc.hp--;
            inc.age = 0;
            say('🐕 Chó Vàng đuổi chuột giúp bạn!');
          }
          break;
        case 'brawl':
          if (inc.target >= tables.length || tables[inc.target].c == null) {
            incidents.remove(inc);
            break;
          }
          if (inc.age > 14) {
            final c = tables[inc.target].c!;
            queue.removeWhere((x) => x.id == c.ticketId);
            lost++;
            starsLog.add(1);
            tables[inc.target].c = null;
            incidents.remove(inc);
            for (final t in tables) {
              final o = t.c;
              if (o != null && o.st < 2) o.pat -= 5;
            }
            say('💢 Khách gây gổ bỏ về, cả quán mất vui!');
          }
          break;
        case 'fire':
          if (inc.age > 10) {
            incidents.remove(inc);
            if (inc.target < stations.length) {
              final s = stations[inc.target];
              final tk = s.t;
              s.clear();
              if (tk != null) queue.insert(0, tk);
            }
            money = max(0, money - 15);
            say('🔥 Bếp cháy hỏng món! Mất 15💰, phải nấu lại.');
          }
          break;
      }
      if (inc.hp <= 0) incidents.remove(inc);
    }
    if (day >= 2 && timeLeft > 10) {
      incT -= dt;
      if (incT <= 0) {
        randomIncident();
        final luck = (petOn('dog') ? 1.15 : 1.0) * (petOn('hamster') ? 1.1 : 1.0);
        incT = ((40 - 18 * ease) + rnd.nextDouble() * 20) * luck;
      }
    }
  }

  void onIncident(int id, String? tl) {
    final idx = incidents.indexWhere((x) => x.id == id);
    if (idx < 0) return;
    final inc = incidents[idx];
    final it = incidentType(inc.type);
    if (tl != it.tool) {
      say('Cần dùng ${it.toolEmoji} ${it.toolName}!');
      return;
    }
    inc.hp--;
    if (inc.hp <= 0) {
      incidents.removeAt(idx);
      say('✅ Đã xử lý: ${it.name}');
      if (inc.type == 'brawl' && inc.target < tables.length) {
        final c = tables[inc.target].c;
        if (c != null) c.pat = min(c.maxPat, c.pat + 10);
      }
    }
  }

  void checkGoal() {
    if (screen == 'play' && !goalHit && earned >= goal) {
      goalHit = true;
      goalBurstAt = DateTime.now();
      goalBurstKey++;
      Sound.sfx('goal');
    }
  }

  /// Nhạc thắng / thua khi hết ngày (thi đấu: chờ biết kết quả của đối thủ)
  void playResult() {
    if (resultPlayed || screen != 'end') return;
    bool win;
    if (hasOpp) {
      if (oppScr != 'end') return;
      final diff = served != oppServed ? served - oppServed : earned - oppEarned;
      win = diff >= 0;
    } else {
      win = earned >= goalFor(day - 1);
    }
    resultPlayed = true;
    Sound.sfx(win ? 'win' : 'lose');
  }

  void finishCustomer(TableS t, Cust c) {
    final frac = (c.pat / c.maxPat).clamp(0.0, 1.0);
    final dirtyN = tables.where((x) => x.dirty).length;
    final clean = 1 - dirtyN / tables.length;
    final raw = frac * 2.2 + c.quality * 2.0 + clean * 0.8;
    final stars = raw.round().clamp(1, 5);
    final npc = npcById(c.npc);
    var gain = (c.recipe.price * (0.6 + 0.1 * stars)).round();
    if (stars >= 4) gain += (c.recipe.price * 0.25 * (1 + 0.2 * lvl('decor'))).round();
    gain = (gain * (npc?.payMul ?? 1)).round();
    if (petOn('hamster')) gain = (gain * 1.05).round();
    var lucky = false;
    if (petOn('dog') && rnd.nextDouble() < 0.15) {
      gain = (gain * 1.5).round();
      lucky = true;
    }
    var bonus = 0;
    String? special;
    switch (c.npc) {
      case 'vip':
        if (stars <= 2) gain = (gain * 0.5).round();
        special = stars >= 4 ? '👑 Ông Bảy rất hài lòng, trả gấp đôi!' : '👑 Ông Bảy chê phục vụ chưa xứng tầm.';
        break;
      case 'critic':
        if (stars >= 4 && c.taste == 'Vừa') {
          bonus = c.recipe.price * 2;
          special = '📰 Cô Lan viết bài khen quán! +$bonus💰';
        } else {
          bonus = -min(30, money);
          special = '📰 Cô Lan chê món ${c.taste == 'Vừa' ? 'chưa ngon' : tasteWord(c.taste)} trên blog… ${bonus}💰';
        }
        break;
      case 'hunter':
        special = c.taste == 'Nhạt' ? '🏹 Chú Tư: "Nhạt quá, chú đi rừng mà!"' : '🏹 Chú Tư: "Đậm đà, đúng ý chú!"';
        break;
      case 'student':
        special = '🎒 Bé Na: "Ngon quá, mai con lại tới!"';
        break;
      case 'stranger':
        if (stars >= 4) {
          bonus = 50 + rnd.nextInt(101);
          special = '🎁 Người lạ để lại phong bì $bonus💰 rồi biến mất…';
        } else {
          special = '🕵️ Người lạ lặng lẽ rời đi…';
        }
        break;
    }
    money = max(0, money + gain + bonus);
    earned += gain + bonus;
    served++;
    starsLog.add(stars);
    final luck = lucky ? ' 🍀 May mắn x1.5!' : '';
    if (special != null) {
      say('$special$luck', 4);
    } else if (c.quality < 0.6) {
      say('😡 Món ăn dở quá!');
    } else if (c.taste == 'Nhạt' || c.taste == 'Đậm') {
      say('😕 Món hơi ${tasteWord(c.taste)}… +$gain$luck');
    } else if (frac < 0.35) {
      say('😤 Phục vụ chậm quá!');
    } else if (clean < 0.6) {
      say('🤢 Quán bẩn quá!');
    } else if (stars >= 4) {
      say('😍 Rất hài lòng! +$gain$luck');
    } else {
      say('🙂 Tạm ổn. +$gain$luck');
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
        c.taste = d.taste;
        c.eat = 4;
      } else {
        say('Sai bàn rồi!');
      }
    }
  }

  int cutOf(String id) => venue.shelf.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '?', '?')).cut;

  /// Một nhát dao trên thớt
  void chop(Station s) {
    if (s.board.isEmpty) return;
    s.chopLeft--;
    if (s.chopLeft <= 0) {
      s.added.add(s.board.removeAt(0));
      s.chopLeft = s.board.isEmpty ? 0 : cutOf(s.board.first);
    }
  }

  void onStation(int i) {
    if (i < 0 || i >= stations.length) return;
    final s = stations[i];
    activeStation = i;
    if (s.t == null) {
      if (queue.isEmpty) return;
      final tk = queue.removeAt(0);
      s.t = tk;
      s.need = tk.recipe.cook * (1 - 0.15 * lvl('stove'));
      final cu = tk.table < tables.length ? tables[tk.table].c : null;
      s.saltTarget = tk.recipe.salt + (cu?.saltPref ?? 0); // khẩu vị riêng của khách
      s.tol = 0.9 - 0.35 * ease;
      s.heat = 0.5;
    } else if (s.chopping) {
      chop(s);
    } else if (s.done) {
      if (counter.length >= 6) {
        say('Quầy đầy rồi!');
        return;
      }
      final q = s.burnt ? min(s.quality, 0.35) : s.quality;
      counter.add(Dish(s.t!.id, s.t!.recipe, q, s.taste));
      s.clear();
    }
  }

  /// Cho nguyên liệu (hoặc gia vị 'salt') vào bếp [st] (mặc định: bếp đang chọn)
  void onIngredient(String id, [int? st]) {
    final si = st ?? activeStation;
    if (si < 0 || si >= stations.length) return;
    activeStation = si;
    final s = stations[si];
    if (s.t == null || s.burnt) return;
    if (id == 'salt') {
      s.salt += 0.7 + rnd.nextDouble() * 0.6; // mỗi lần rắc không đều tay
      return;
    }
    if (s.cooking || s.done) return;
    if (s.t!.recipe.ings.contains(id)) {
      if (s.added.contains(id) || s.board.contains(id)) return;
      final cut = cutOf(id);
      if (cut > 0) {
        s.board.add(id); // cần thái trước
        if (s.board.length == 1) s.chopLeft = cut;
      } else {
        s.added.add(id);
      }
    } else {
      s.mistakes++;
      s.need += 1.0;
      say('Nhầm nguyên liệu! 😖');
    }
  }

  void onHeat(int i, double d) {
    if (i < 0 || i >= stations.length) return;
    final s = stations[i];
    activeStation = i;
    if (!s.cooking) return;
    s.heat = (s.heat + d).clamp(0.0, 1.0).toDouble();
  }

  void onPet(String id) {
    if (remote || !pets.contains(id)) return;
    petHappy[id] = min(100, (petHappy[id] ?? 50) + 4);
  }

  // ---------- Thao tác từ giao diện (tự chọn: chạy tại chỗ hoặc gửi lên host) ----------
  void _act(Map<String, dynamic> m, VoidCallback local) {
    if (remote) {
      net.send({'t': 'act', ...m});
    } else {
      local();
      if (mode == 'host' && !race) net.send(snapshot());
    }
    setState(() {});
  }

  void doTable(int i) {
    final waiting = i < tables.length && tables[i].c?.st == 1;
    if (waiting && selDishId != null && tables[i].c?.ticketId != selDishId) Sound.sfx('wrong');
    final dish = selDishId;
    _act({'a': 'table', 'i': i, 'd': dish}, () => onTable(i, dish));
    if (waiting) selDishId = null;
  }

  void doStation(int i) => _act({'a': 'station', 'i': i}, () => onStation(i));

  void doIngredient(String id, [int? st]) => _act({'a': 'ing', 'id': id, 'st': st}, () => onIngredient(id, st));

  void doHeat(int i, double d) => _act({'a': 'heat', 'i': i, 'd': d}, () => onHeat(i, d));

  void doIncident(int id) {
    final inc = incidents.where((x) => x.id == id).toList();
    if (inc.isEmpty) return;
    final tl = tool;
    if (tl == null) {
      final it = incidentType(inc.first.type);
      setState(() => say('Chọn ${it.toolEmoji} ${it.toolName} ở thanh dụng cụ trước nhé!'));
      Sound.sfx('wrong');
      return;
    }
    _act({'a': 'inc', 'id': id, 'tool': tl}, () => onIncident(id, tl));
  }

  void doPet(String id) {
    onPet(id);
    setState(() {});
  }

  void onDish(Dish d) {
    Sound.sfx('tap');
    setState(() => selDishId = selDishId == d.ticketId ? null : d.ticketId);
  }

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
    // Đang chơi: nhạc theo hoạt cảnh; các màn khác: nhạc menu
    Sound.music(screen == 'play' ? styleNow : 'menu');
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
      case 'profile':
        body = profileScreen();
        break;
      case 'pets':
        body = petsScreen();
        break;
      case 'layout':
        body = layoutScreen();
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
            onPressed: onTap == null
                ? null
                : () {
                    Sound.sfx('tap');
                    onTap?.call();
                  },
            child: Text(text, style: const TextStyle(fontSize: 17)),
          ),
        ),
      );

  String roleName(String r) => r == 'chef' ? '${castNA ? '👩‍🍳' : '👨‍🍳'} $chefName (Đầu bếp)' : '🛎️ $waiterName (Phục vụ)';

  /// Nút đổi ai nấu – ai phục vụ
  Widget castPicker() => Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
        ChoiceChip(
          label: const Text('👨‍🍳 Nguyên nấu, Ngọc Anh phục vụ'),
          selected: !ngocAnhChef,
          onSelected: (_) {
            setState(() => ngocAnhChef = false);
            save();
          },
        ),
        ChoiceChip(
          label: const Text('👩‍🍳 Ngọc Anh nấu, Nguyên phục vụ'),
          selected: ngocAnhChef,
          onSelected: (_) {
            setState(() => ngocAnhChef = true);
            save();
          },
        ),
      ]);

  // --- Menu & phòng ---
  Widget menuScreen() => Center(
        child: SingleChildScrollView(
          child: Column(children: [
            Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(8), child: soundBtn(light: false))),
            const Text('🍽️', style: TextStyle(fontSize: 56)),
            Text(shopName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const Text('Nhà Hàng Đôi • $kNguyen 👨 & $kNgocAnh 👩', style: TextStyle(fontSize: 14, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
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
            bigButton('🐾 Thú cưng', () => setState(() => screen = 'pets'), color: Colors.pink.shade400),
            bigButton('🛠️ Bố trí quán', () => setState(() => screen = 'layout'), color: Colors.brown),
            bigButton('👤 Đổi chủ quán', () => setState(() => screen = 'profile'), color: Colors.blueGrey),
            const SizedBox(height: 8),
            const Text('Ai nấu ăn?', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: castPicker()),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '👨‍🍳 $chefName – ĐẦU BẾP: chạm bếp nhận đơn → kéo (hoặc chạm) nguyên liệu vào bếp → chạm bếp để thái trên thớt 🔪 → '
                'khi nấu, vặn núm − / + giữ lửa trong vùng xanh → rắc gia vị cho vạch nằm trong vùng xanh (thiếu thì nhạt, thừa thì mặn) → chạm bếp lấy món ra quầy.\n\n'
                '🛎️ $waiterName – PHỤC VỤ: chạm khách để nhận order → chạm món ở quầy rồi chạm đúng bàn → chạm bàn bẩn để dọn.\n\n'
                '🧰 SỰ CỐ (từ ngày 2): cháy bếp, mất điện, chuột, rò nước, khách gây gổ. Chọn đúng dụng cụ ở thanh 🧰 rồi chạm vào chỗ có sự cố.\n\n'
                '⭐ Khách đặc biệt: Ông Bảy (VIP), Cô Lan (phê bình), Chú Tư (thợ săn), Bé Na (học sinh), Người lạ bí ẩn – mỗi người một khẩu vị và câu chuyện.\n\n'
                '🤝 Hợp tác: 2 máy, một người nấu, một người phục vụ chung 1 quán.\n'
                '🏁 Thi đấu: 2 máy, Nguyên chơi ở nhà hàng của Nguyên, Ngọc Anh ở nhà hàng của Ngọc Anh, ai bán được nhiều món hơn thì thắng.\n\n'
                'Những ngày đầu khách đến thưa và kiên nhẫn, càng về sau càng đông và khó hơn.\n'
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
            const Text('Ai nấu ăn?', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: castPicker()),
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
            Text(race ? 'Mỗi người chơi ở nhà hàng của mình' : '🏠 Chơi tại $shopName', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (!race) Text('Bạn: ${roleName(myRole)}  •  Hàng xóm: ${roleName(myRole == 'chef' ? 'waiter' : 'chef')}'),
            const SizedBox(height: 8),
            Text(guestJoined ? '✅ Hàng xóm đã vào phòng!' : '⏳ Đang chờ hàng xóm nhập mã...', style: const TextStyle(fontSize: 16)),
            Text(netStatus, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            bigButton('▶ Bắt đầu ngày $day', guestJoined ? startDay : null),
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
  Widget soundBtn({bool light = true}) => InkWell(
        onTap: () {
          setState(() => Sound.setEnabled(!Sound.enabled));
          save();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: light ? Colors.white24 : Colors.black12, shape: BoxShape.circle),
          child: Icon(Sound.enabled ? Icons.volume_up : Icons.volume_off, color: light ? Colors.white : Colors.brown, size: 19),
        ),
      );

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
            soundBtn(),
            const SizedBox(width: 4),
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
    final st = peerLost ? 'mất kết nối' : (oppScr == 'end' ? 'đã xong ngày' : 'đang chơi');
    return Container(
      width: double.infinity,
      color: lead > 0 ? Colors.green.shade700 : (lead < 0 ? Colors.red.shade700 : Colors.blueGrey.shade700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        '🆚 ${oppOwner.isEmpty ? 'Hàng xóm' : 'Nhà hàng của $oppOwner'}: 🍽️ $oppServed món • 💰 $oppEarned ($st)   ${lead > 0 ? '👑 Bạn dẫn trước' : (lead < 0 ? '😬 Bạn đang thua' : '🤝 Hoà')}',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget playScreen() {
    // 1 máy hoặc thi đấu: một người lo cả bếp lẫn sảnh.
    // Bếp ở trên, sảnh ở dưới, cùng một hướng nhìn: ô "Quầy ra món" của sảnh nằm sát bếp.
    Widget col;
    if (mode == 'local' || race) {
      col = Column(children: [
        hud(race ? '🏁 THI ĐẤU' : '🍽️ $chefName & $waiterName'),
        if (race) oppBar(),
        Expanded(flex: 4, child: kitchenBody(compact: true, tools: false)),
        toolBar(null),
        Expanded(flex: 7, child: diningBody(tools: false)),
      ]);
    } else {
      col = Column(children: [
        hud(myRole == 'chef' ? '${castNA ? '👩‍🍳' : '👨‍🍳'} $chefName' : '🛎️ $waiterName'),
        Expanded(child: myRole == 'chef' ? kitchenBody() : diningBody()),
      ]);
    }
    final at = goalBurstAt;
    final burst = at != null && DateTime.now().difference(at).inMilliseconds < 3500;
    if (!burst) return col;
    return Stack(children: [
      col,
      Positioned.fill(child: ConfettiLayer(key: ValueKey(goalBurstKey), duration: 2.5, fireworks: false)),
      Align(
        alignment: const Alignment(0, -0.35),
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('b$goalBurstKey'),
            tween: Tween(begin: 0.3, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF7043)]),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: const Text('🎯 ĐẠT MỤC TIÊU NGÀY! 🎉', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    ]);
  }

  // --- Phục vụ ---
  Widget diningBody({bool tools = true}) => Column(children: [
        if (tools) toolBar(false),
        Expanded(
          child: DiningScene(
            tables: tables,
            counter: counter,
            selDishId: selDishId,
            venueId: venueId,
            decor: decorLv,
            style: styleNow,
            waiterLook: castLook(waiterName, 'waiter'),
            waiterName: waiterName,
            tablePos: tablePosNow,
            decos: decosNow,
            light: lightNow,
            pets: petsNow,
            incidents: incidents,
            tool: tool,
            onTable: doTable,
            onDish: onDish,
            onIncident: doIncident,
            onPet: doPet,
          ),
        ),
      ]);

  // --- Đầu bếp ---
  String ingEmoji(String id) => venue.shelf.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '❓', '?')).emoji;

  Widget kitchenBody({bool compact = false, bool tools = true}) => Column(children: [
        ticketRail(compact: compact),
        if (tools) toolBar(true),
        Expanded(
          child: KitchenScene(
            stations: stations,
            activeStation: activeStation,
            hasOrders: queue.isNotEmpty,
            venueId: venueId,
            style: styleNow,
            burnTime: burnTime,
            chefLook: castLook(chefName, 'chef'),
            chefName: chefName,
            ingEmoji: ingEmoji,
            onStation: doStation,
            incidents: incidents,
            seasonEmoji: seasonEmoji(venueId),
            onIncident: doIncident,
            onHeat: doHeat,
            onDrop: (i, id) => doIngredient(id, i),
          ),
        ),
        ingredientShelf(compact: compact),
      ]);

  /// Thanh dụng cụ xử lý sự cố. [kitchen] null = tất cả dụng cụ (chơi 1 máy)
  Widget toolBar(bool? kitchen) {
    final types = incidentTypes.where((x) => kitchen == null || x.kitchen == kitchen).toList();
    final alert = incidents.any((x) => kitchen == null || incidentType(x.type).kitchen == kitchen);
    return Container(
      height: 38,
      color: alert ? const Color(0xFF5D2A2A) : const Color(0xFF37474F),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          Text(alert ? '⚠️' : '🧰', style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 6),
          for (final it in types)
            Padding(padding: const EdgeInsets.only(right: 6), child: _toolChip(it, kitchen == null)),
        ]),
      ),
    );
  }

  Widget _toolChip(IncidentType it, bool short) {
    final sel = tool == it.tool;
    final need = incidents.any((x) => x.type == it.id);
    return GestureDetector(
      onTap: () {
        Sound.sfx('tap');
        setState(() => tool = sel ? null : it.tool);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? Colors.amber : (need ? Colors.red.shade400 : Colors.white24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2),
        ),
        child: Text(
          short ? it.toolEmoji : '${it.toolEmoji} ${it.toolName}',
          style: TextStyle(fontSize: short ? 16 : 12, color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

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

  /// Kệ nguyên liệu bằng gỗ: chạm để cho vào bếp đang chọn, hoặc kéo lên thả vào bếp bất kỳ
  Widget ingredientShelf({bool compact = false}) {
    final items = <Widget>[
      for (final ing in venue.shelf) _shelfItem(ing.id, ing.emoji, ing.cut > 0 ? '${ing.name} 🔪' : ing.name, compact),
      _shelfItem('salt', seasonEmoji(venueId), seasonName(venueId), compact, special: true),
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(4, compact ? 5 : 8, 4, compact ? 5 : 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA1887F), Color(0xFF6D4C41)]),
        border: Border(top: BorderSide(color: Color(0xFF4E342E), width: 4)),
      ),
      child: compact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final w in items) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: w),
              ]),
            )
          : Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: items),
    );
  }

  Widget _shelfItem(String id, String emoji, String name, bool compact, {bool special = false}) {
    final tile = Material(
      color: special ? const Color(0xFFE1F5FE) : const Color(0xFFFFF8E1),
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => doIngredient(id),
        child: SizedBox(
          width: compact ? 48 : 58,
          height: compact ? 46 : 54,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: TextStyle(fontSize: compact ? 20 : 24)),
            Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
    return Draggable<String>(
      data: id,
      affinity: Axis.vertical, // kéo lên để thả vào bếp, kéo ngang vẫn cuộn được kệ
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 56, height: 56, child: Center(child: Text(emoji, style: const TextStyle(fontSize: 40)))),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  // =====================================================================
  //  MÀN HÌNH: CHỦ QUÁN, THÚ CƯNG, BỐ TRÍ
  // =====================================================================
  Widget _topBar(String title, VoidCallback onBackTap) => Container(
        color: Colors.teal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(children: [
          IconButton(onPressed: onBackTap, icon: const Icon(Icons.arrow_back, color: Colors.white)),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          Padding(padding: const EdgeInsets.only(right: 12), child: Text('💰 $money', style: const TextStyle(color: Colors.white, fontSize: 16))),
        ]),
      );

  Widget profileScreen() => Center(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 16),
            const Text('Máy này là của ai?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Mỗi người có một nhà hàng riêng: tiền, nâng cấp, thú cưng và cách bố trí đều lưu riêng. Chơi 2 máy thì mỗi máy chọn một người.',
                textAlign: TextAlign.center,
              ),
            ),
            Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center, children: [
              _ownerCard(kNguyen, nguyenLook, 'chef'),
              _ownerCard(kNgocAnh, ngocAnhLook, 'waiter'),
            ]),
            const SizedBox(height: 12),
            if (owner.isNotEmpty) bigButton('⬅ Quay lại', () => setState(() => screen = 'menu'), color: Colors.grey),
          ]),
        ),
      );

  Widget _ownerCard(String name, Look look, String role) {
    final sel = owner == name;
    return GestureDetector(
      onTap: () {
        Sound.sfx('tap');
        chooseOwner(name);
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? Colors.orange.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? Colors.deepOrange : Colors.grey.shade300, width: sel ? 3 : 1),
        ),
        child: Column(children: [
          PersonAvatar(look: look, role: role, name: name, height: 150),
          const SizedBox(height: 6),
          Text('Nhà hàng của $name', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget petsScreen() => Column(children: [
        _topBar('🐾 Thú cưng – $shopName', () => setState(() => screen = 'menu')),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            const Text(
              'Vuốt ve (tới 60♥) và cho ăn (tới 100♥) để thú cưng vui vẻ. Từ 40♥ trở lên thú cưng mới giúp quán. Mỗi ngày trôi qua thú cưng giảm 20♥. '
              'Trong lúc chơi, chạm vào thú cưng để vuốt ve.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            for (final p in petTypes) _petCard(p),
          ]),
        ),
      ]);

  Widget _petCard(PetType p) {
    final has = pets.contains(p.id);
    final hp = petHappy[p.id] ?? 0;
    final voice = p.id == 'dog' ? 'woof' : (p.id == 'parrot' ? 'chirp' : (p.id == 'hamster' ? 'squeak' : 'purr'));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              Text(p.perk, style: const TextStyle(fontSize: 12)),
              if (has) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Text('${hp >= 40 ? '😊' : '😿'} $hp♥  '),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: hp / 100,
                        minHeight: 8,
                        color: hp >= 40 ? Colors.pink : Colors.grey,
                        backgroundColor: Colors.pink.shade50,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  OutlinedButton(
                    onPressed: () {
                      Sound.sfx(voice);
                      setState(() => petHappy[p.id] = hp >= 60 ? hp : min(60, hp + 8));
                      save();
                    },
                    child: const Text('🤚 Vuốt ve'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (pay(5)) {
                        Sound.sfx('coin');
                        setState(() => petHappy[p.id] = min(100, hp + 30));
                        save();
                      }
                    },
                    child: const Text('🍖 Cho ăn (5💰)'),
                  ),
                ]),
              ],
            ]),
          ),
          if (!has)
            ElevatedButton(
              onPressed: () {
                if (pay(p.cost)) {
                  Sound.sfx(voice);
                  setState(() {
                    pets.add(p.id);
                    petHappy[p.id] = 80;
                  });
                  save();
                }
              },
              child: Text('💰${p.cost}'),
            ),
        ]),
      ),
    );
  }

  Widget layoutScreen() {
    final n = min(4 + lvl('tables'), venue.maxTables);
    return Column(children: [
      _topBar('🛠️ Bố trí – $shopName', () => setState(() => screen = 'menu')),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            const Text('Ánh sáng: '),
            for (final lm in lightModes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(lm[1]),
                  selected: light == lm[0],
                  onSelected: (_) {
                    setState(() => light = lm[0]);
                    save();
                  },
                ),
              ),
          ]),
        ),
      ),
      Expanded(
        child: LayoutEditor(
          tableCount: n,
          tablePos: tablePos,
          decos: decos,
          venueId: venueId,
          style: style,
          light: light,
          onChanged: (tp, ds) {
            setState(() {
              tablePos = tp;
              decos = ds;
            });
            save();
          },
          onRemoveDeco: (k) {
            if (k < 0 || k >= decos.length) return;
            final d = decos.removeAt(k);
            final dt = decoById(d.type);
            final refund = dt.cost ~/ 2;
            setState(() => money += refund);
            save();
            snack('Đã cất ${dt.name}, nhận lại $refund💰');
          },
        ),
      ),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Expanded(child: Text('${decos.length} đồ trang trí • mua thêm ở Cửa hàng', style: const TextStyle(fontSize: 12))),
          TextButton(
            onPressed: () {
              setState(() => tablePos = List<Offset?>.filled(12, null));
              save();
            },
            child: const Text('↺ Xếp bàn mặc định'),
          ),
        ]),
      ),
    ]);
  }

  // --- Kết thúc ngày ---
  Widget raceResult() {
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
    final prevGoal = goalFor(day - 1); // day đã tăng sau khi kết thúc ngày
    final reached = earned >= prevGoal;
    final isGuest = mode == 'guest';
    final bk = _bk;
    final raceDone = hasOpp && oppScr == 'end';
    final raceDiff = served != oppServed ? served - oppServed : earned - oppEarned;
    // Thắng: thi đấu thì phải hơn hàng xóm, còn lại là đạt mục tiêu ngày
    final win = raceDone ? raceDiff > 0 : !hasOpp && reached;
    final sad = raceDone ? raceDiff < 0 : !hasOpp && !reached;
    final content = Center(
      child: SingleChildScrollView(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (win || sad)
            DancingCouple(
              happy: win,
              left: castLook(chefName, 'chef'),
              right: castLook(waiterName, 'waiter'),
              leftName: chefName,
              rightName: waiterName,
              height: 170,
            ),
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
              hasOpp && oppScr == 'play' && !peerLost ? '⏳ Chờ hàng xóm xong ngày' : '▶ Ngày tiếp theo',
              hasOpp && oppScr == 'play' && !peerLost ? null : startDay,
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
    if (!win) return content;
    return Stack(children: [content, const Positioned.fill(child: ConfettiLayer())]);
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
          header('🪑 Đồ trang trí (kéo thả ở "Bố trí quán")'),
          for (final dt in decoTypes)
            ListTile(
              leading: Text(dt.emoji, style: const TextStyle(fontSize: 28)),
              title: Text(dt.name),
              subtitle: Text('${dt.wall ? 'Treo tường' : 'Đặt trên sàn'} • đang có ${decos.where((d) => d.type == dt.id).length} • khách chờ lâu hơn 1 giây/món'),
              trailing: ElevatedButton(
                onPressed: () {
                  if (pay(dt.cost)) {
                    decos.add(Deco(dt.id, 0.15 + rnd.nextDouble() * 0.7, dt.wall ? 0 : 0.2 + rnd.nextDouble() * 0.6));
                    save();
                    setState(() {});
                    snack('Đã mua ${dt.name}! Vào 🛠️ Bố trí quán để kéo thả.');
                  }
                },
                child: Text('💰${dt.cost}'),
              ),
            ),
          header('🎨 Hoạt cảnh nhà hàng'),
          for (final st in sceneStyles)
            ListTile(
              leading: Text(st.emoji, style: const TextStyle(fontSize: 28)),
              title: Text(st.name),
              subtitle: Text(st.desc),
              selected: st.id == style,
              trailing: styles.contains(st.id)
                  ? (st.id == style
                      ? const Text('Đang dùng')
                      : OutlinedButton(
                          onPressed: () {
                            style = st.id;
                            save();
                            setState(() {});
                          },
                          child: const Text('Chọn')))
                  : ElevatedButton(
                      onPressed: () {
                        if (pay(st.cost)) {
                          styles.add(st.id);
                          style = st.id;
                          save();
                          setState(() {});
                        }
                      },
                      child: Text('💰${st.cost}')),
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