import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'town.dart';
import 'ui.dart';
import 'dishes.dart';
import 'garden_store.dart';
import 'garden_engine.dart' show GEvent;
import 'garden_ui.dart';
import 'warmup.dart';
import 'crowd.dart';
import 'auto_biz.dart';

bool get onlineConfigured => !kSupabaseUrl.contains('YOUR_');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (onlineConfigured) {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  }
  await Sound.init();
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: appTheme(), home: const GamePage()));
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  Random rnd = Random(); // thi đấu: 2 máy dùng chung 1 hạt giống → khách đến giống nhau
  final net = Net();
  final codeCtl = TextEditingController();
  Timer? timer, netTimer;

  // menu, create, lobby, join, wait, play, end, shop
  String screen = 'menu';
  String hubTab = 'map'; // map | shop | home | online

  // --- Chế độ chơi ---
  String mode = 'local'; // local (1 máy) | pending (đang chờ người kia) | host | guest
  static const duoRoom = 'nguyen-ngocanh'; // phòng cố định của 2 máy, không cần nhập mã
  int myJoinAt = 0;
  String peerName = '';
  String myRole = 'both'; // chef | waiter | both
  String createRole = 'chef';
  String gameType = 'coop'; // coop: 1 đầu bếp + 1 phục vụ | race: mỗi người 1 quán, thi bán nhiều món
  String createGame = 'coop';
  bool paused = false;
  // Điểm của đối thủ (chế độ thi đấu)
  int oppServed = 0, oppEarned = 0;
  // Thi đấu tính điểm: mỗi khách được phục vụ = số sao (1–5), mỗi khách bỏ về = −2
  int starSum = 0, oppStars = 0, oppLost = 0;
  int get score => starSum - 2 * lost;
  int get oppScore => oppStars - 2 * oppLost;
  /// > 0: mình dẫn. So điểm → nếu bằng thì so số khách → rồi so tiền
  int get raceDiff => score != oppScore ? score - oppScore : (served != oppServed ? served - oppServed : earned - oppEarned);
  String oppScr = 'wait';
  String roomCode = '', netStatus = '';
  bool guestJoined = false, joined = false;
  DateTime lastPeer = DateTime.now();
  List<dynamic>? _bk; // sao lưu dữ liệu của khách khi vào phòng người khác
  Map<String, dynamic>? _raceBk; // thi đấu: sao lưu quán của mình trong lúc chơi ở "sân chung"
  int endGoal = 0; // mục tiêu của ngày vừa kết thúc

  // ---- Nhà hàng riêng (Poseidon / Goyuhan / Bình Dần) + quảng cáo + lượng khách ----
  String sig = ''; // loại nhà hàng riêng đã mở ('' = chưa)
  int sigRank = 1; // hạng quán 1..5 sao
  Map<String, int> ads = {}; // quảng cáo: id → chạy tới (trước) ngày này
  double crowdMul = 1; // hệ số khách của ngày đang chơi
  // ---- Nhà hàng Trung: buffet tự chọn. Khách tự lấy món ở quầy, hết món thì đầu bếp nấu thêm ----
  bool get buffet => venue.id == 'chinese';
  List<String> trayIds = [];
  List<int> trayQty = [];
  List<double> trayQ = [];
  static const trayMax = 8;
  String tableLabel(int tb) => tb < 0 ? 'Buffet' : 'Bàn ${tb + 1}';
  List<CrowdFactor> crowdFactors = [];
  String get partnerName => owner == kNgocAnh ? kNguyen : kNgocAnh;
  bool adOn(String id) => day < (ads[id] ?? 0);
  int get sigUpCost => 500 * sigRank;
  Biz biz = Biz(); // nhà hàng riêng vận hành tự động
  int cheerDay = 0; // ngày đã cổ vũ quán người kia

  double get _sigAvgPrice {
    if (sig.isEmpty) return 100;
    final rs = venueById(sig).recipes.where((r) => recipes.contains(r.id)).toList();
    if (rs.isEmpty) return 100;
    return rs.map((r) => r.price).reduce((a, b) => a + b) / rs.length;
  }

  /// Tính tiền/hàng/sự kiện của nhà hàng tự động tới hiện tại
  void bizRun() {
    if (sig.isEmpty || _raceBk != null || remote) return;
    final gifts = <(int, int)>[
      for (final e in Garden.instance.events)
        if ((e.a == 'cheer' || e.a == 'gift') && e.d['to'] == owner) (e.at, e.a == 'gift' ? ((e.d['m'] as num?)?.toInt() ?? 0) : 0),
    ];
    final crowd = Crowd.total(Crowd.factors(venueId: sig, sig: true, sigRank: sigRank, ads: const {}, day: day));
    final w = Crowd.weather;
    final now = DateTime.now().millisecondsSinceEpoch;
    biz.run(now, owner: owner, rank: sigRank, avgPrice: _sigAvgPrice, crowd: crowd, gifts: gifts,
        warm: w != null && (w.rain || w.storm || w.temp < 24), hot: w != null && w.temp >= 31);
    // gửi doanh thu tuần cho người kia xem (tối đa 30 phút/lần)
    if (biz.hired && now - _revPubAt > 30 * 60000) {
      _revPubAt = now;
      Garden.instance.act('rev', {'own': owner, 'wk': biz.week, 'v': biz.weekRev.round(), 'lw': biz.lastWeekRev.round()});
    }
    // thưởng thắng cuộc thi doanh thu tuần trước
    final pr = partnerRev();
    if (biz.week > 0 && biz.prizeWeek != biz.week && pr != null && biz.lastWeekRev > 0) {
      final theirLast = pr.$1 == biz.week ? pr.$3 : (pr.$1 == biz.week - 1 ? pr.$2 : 0);
      if (biz.lastWeekRev > theirLast) {
        biz.prizeWeek = biz.week;
        money += 300;
        biz.log.insert(0, '🏆 Thắng cuộc thi doanh thu tuần trước! +300💰');
      }
    }
  }

  int _revPubAt = 0;

  /// Doanh thu của quán người kia: (tuần, tuần này, tuần trước)
  (int, int, int)? partnerRev() {
    GEvent? last;
    for (final e in Garden.instance.events) {
      if (e.a == 'rev' && e.d['own'] == partnerName && (last == null || e.at >= last.at)) last = e;
    }
    if (last == null) return null;
    int v(String k) => (last!.d[k] as num?)?.toInt() ?? 0;
    return (v('wk'), v('v'), v('lw'));
  }

  /// Số phần nông sản từ vườn chưa lấy (mỗi lần thu hoạch = 6 phần)
  int get farmAvail {
    final total = Garden.instance.state.harvests.values.fold<int>(0, (a, b) => a + b);
    return max(0, total * 6 - biz.farmClaimed * 6);
  }
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
  List<OutsideGuest> outsideQ = []; // khách chờ ngoài cửa khi quán kín bàn
  int guestStation = -1; // bếp mà máy khách đang chọn (máy chủ dùng activeStation)
  int get myStation => remote ? guestStation : activeStation;

  Venue get venue => venueById(venueId);
  int lvl(String id) => lv[id] ?? 0;
  /// 0 ở ngày đầu → 1 từ ngày 13: dùng để tăng độ khó từ từ
  /// Số khách tối đa đứng chờ ngoài cửa (ngày sau đông hơn)
  int get maxOutside => 3 + (ease * 5).round(); // cấp 20: 8 người xếp hàng

  /// Khách ngoài cửa chờ được bao lâu (giây) trước khi bực mình bỏ đi
  double get outsidePat => 32 - 12 * ease + 3 * lvl('decor') + (petOn('parrot') ? 5 : 0);

  static const maxLevel = 20; // từ ngày 20 trở đi là khó nhất
  // ---- Độ khó: 'auto' = tăng dần theo ngày; easy / normal / hard = giữ cố định ----
  String diff = 'auto';
  String hostDiff = 'auto';
  String get diffNow => remote ? hostDiff : diff;
  static const diffModes = [
    ('easy', '🌱', 'Dễ', 'Thong thả như ngày đầu'),
    ('normal', '🙂', 'Vừa', 'Như khoảng ngày 8'),
    ('hard', '🔥', 'Khó', 'Cấp 20: khách nườm nượp'),
    ('auto', '📈', 'Tăng dần', 'Khó lên mỗi ngày, tới cấp 20'),
  ];

  /// Ngày dùng để tính độ khó (mục tiêu, tốc độ khách, độ kiên nhẫn…)
  int effDay(int d) {
    switch (diffNow) {
      case 'easy':
        return min(d, 2);
      case 'normal':
        return min(d, 8);
      case 'hard':
        return max(d, maxLevel);
      default:
        return d;
    }
  }

  double get ease => ((effDay(day) - 1) / (maxLevel - 1)).clamp(0.0, 1.0).toDouble();
  int goalFor(int d0) {
    final d = min(effDay(d0), maxLevel); // mục tiêu cũng dừng tăng ở cấp 20
    return 80 + d * 50 + (d > 6 ? (d - 6) * 20 : 0);
  }
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
  String tasteWord(String taste, [String? recipeId]) =>
      taste == 'Đậm' ? ((recipeId == null ? sweetVenue : isSweet(recipeId)) ? 'ngọt gắt' : 'mặn') : taste.toLowerCase();

  /// Món đang được chọn để nấu (để biết cần đường hay muối)
  String? get focusRecipeId {
    final i = myStation;
    if (i >= 0 && i < stations.length && stations[i].t != null) return stations[i].t!.recipe.id;
    for (final s in stations) {
      if (s.t != null) return s.t!.recipe.id;
    }
    return null;
  }
  /// Khách trong chế độ hợp tác: chỉ hiển thị, mọi thao tác gửi lên chủ phòng
  bool get remote => mode == 'guest' && gameType == 'coop';
  bool get race => mode != 'local' && gameType == 'race';
  /// Thi đấu có đối thủ thật (khách luôn có chủ phòng; chủ phòng cần khách đã vào)
  bool get hasOpp => race && (mode == 'guest' || guestJoined);
  String get shopBack => mode == 'host' ? 'lobby' : (mode == 'guest' ? 'wait' : 'menu');
  bool get peerLost {
    if (mode == 'local' || mode == 'pending') return false;
    if (mode == 'host' && !guestJoined) return false;
    if (mode == 'guest' && !joined) return false;
    return DateTime.now().difference(lastPeer).inSeconds > 7;
  }

  @override
  void initState() {
    super.initState();
    recipes.addAll(venueById('cafe').recipes.where((r) => r.unlock == 0).map((r) => r.id));
    WidgetsBinding.instance.addObserver(this);
    Garden.instance.addListener(_onGarden);
    load();
    Future.delayed(const Duration(seconds: 2), preloadSounds);
    Crowd.fetchWeather().then((_) {
      if (mounted) setState(() {});
    });
    // đồng hồ thật: cập nhật mỗi 30 giây (trời sáng/tối, giờ trên thanh trên cùng)
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && screen != 'play') {
        bizRun();
        setState(() {});
      }
    });
  }

  // Khu vườn chung đổi (người kia vừa chăm sóc / thu hoạch) → cập nhật thực đơn
  int _gardenMenuN = -1;
  int _gardenCare = 0;
  void _onGarden() {
    final n = Garden.instance.unlocked.length;
    final care = Garden.instance.state.needCare;
    var changed = false;
    if (n != _gardenMenuN) {
      _gardenMenuN = n;
      changed = true;
    }
    if (care != _gardenCare) {
      // vườn vừa có thêm việc cần làm → nhắc ngay trong app (trừ lúc đang bán hàng)
      if (care > _gardenCare && mounted && screen != 'play' && hubTab != 'garden') {
        snack('🌻 Khu vườn có $care chỗ cần chăm sóc, ghé vườn nhé!');
      }
      _gardenCare = care;
      changed = true;
    }
    final ps = Garden.instance.sigOf(partnerName);
    final pk = ps == null ? '' : '${ps.$1}${ps.$2}';
    if (pk != _partnerSigKey) {
      _partnerSigKey = pk; // quán của người kia vừa mở / lên hạng → vẽ lại bản đồ
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  String _partnerSigKey = '';

  /// Món từ vườn đã mở (thu hoạch ít nhất 1 lần) – bán ở mọi quán
  List<Recipe> get gardenMenu => gardenRecipes.where((r) => Garden.instance.unlocked.contains(r.id.substring(2))).toList();

  /// Kệ nguyên liệu: của quán + nguyên liệu cho các món từ vườn
  List<Ing> get shelfNow {
    final list = [...venue.shelf];
    final need = gardenMenu.expand((r) => r.ings).toSet();
    for (final g in gardenIngs) {
      if (need.contains(g.id) && !list.any((x) => x.id == g.id)) list.add(g);
    }
    return list;
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
    sig = '';
    sigRank = 1;
    ads = {};
    biz = Biz();
    cheerDay = 0;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    // Chế độ thử nghiệm cho máy chụp màn hình tự động: ?demo=1&v=<quán>&t=<số bàn>
    final q = kIsWeb ? Uri.base.queryParameters : const <String, String>{};
    if (q['demo'] == 'map' || q['demo'] == 'room') {
      owner = kNguyen;
      await loadData();
      if (q['own'] != '0') owned.addAll(['cafe', 'bakery', 'chinese', 'mexican', 'truck', 'goyuhan']);
      sig = q['own'] == '0' ? '' : 'goyuhan';
      Sound.setEnabled(false);
      if (mounted) setState(() => screen = 'menu');
      if (q['demo'] == 'room') {
        final v = q['v'] ?? 'goyuhan';
        owned.add(v);
        venueId = v;
        WidgetsBinding.instance.addPostFrameCallback((_) => showRoomSheet(v));
      }
      return;
    }
    if (q['demo'] == '1') {
      owner = kNguyen;
      await loadData();
      final v = q['v'];
      if (v != null && venues.any((x) => x.id == v)) {
        venueId = v;
        recipes.addAll(venueById(v).recipes.map((r) => r.id));
        if (isSigVenue(v)) sig = v;
      }
      lv['tables'] = int.tryParse(q['t'] ?? '') ?? 4;
      lv['stations'] = 2;
      day = 6;
      Sound.setEnabled(false);
      mode = 'local';
      startDay();
      return;
    }
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
    Garden.instance.start(owner);
    Garden.instance.who = owner;
    final p = await SharedPreferences.getInstance();
    var s = p.getString('save_$owner');
    if (s == null && !(p.getBool('migrated') ?? false)) {
      s = p.getString('save'); // bản lưu cũ trước khi có chủ quán
      await p.setBool('migrated', true);
    }
    resetData();
    if (s != null) applySave(jsonDecode(s) as Map<String, dynamic>);
    if (mounted) setState(() {});
  }

  /// Nạp dữ liệu quán từ bản lưu (dạng map)
  void applySave(Map<String, dynamic> m) {
    {
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
      diff = m['diff'] ?? 'auto';
      sig = m['sig'] ?? '';
      sigRank = m['sigRank'] ?? 1;
      ads = Map<String, int>.from(m['ads'] ?? {});
      biz = Biz.fromJson(m['biz']);
      cheerDay = m['cheer'] ?? 0;
    }
  }

  /// Dữ liệu quán của mình để lưu
  Map<String, dynamic> saveMap() => {
        'money': money,
        'day': day,
        'lv': lv,
        'recipes': recipes.toList(),
        'owned': owned.toList(),
        'venue': venueId,
        'style': style,
        'styles': styles.toList(),
        'pets': pets.toList(),
        'petHappy': petHappy,
        'decos': decos.map((d) => d.toJson()).toList(),
        'tablePos': posJson(tablePos),
        'light': light,
        'npc': npcVisits,
        'diff': diff,
        'sig': sig,
        'sigRank': sigRank,
        'ads': ads,
        'biz': biz.toJson(),
        'cheer': cheerDay,
      };

  // ---------- Thi đấu công bằng: cả 2 chơi trong cùng 1 quán (của chủ phòng) ----------
  /// Cấu hình "sân thi đấu" chủ phòng gửi cho người kia
  Map<String, dynamic> raceCfg(int seed) => {
        'seed': seed,
        'vn': venueId,
        'lv': lv,
        'rc': recipes.toList(),
        'sy': style,
        'li': light,
        'pt': pets.where((id) => (petHappy[id] ?? 0) >= 40).toList(),
        'de': decos.map((d) => d.toJson()).toList(),
        'tp': posJson(tablePos),
        'day': day,
        'df': diff,
        'own': owner,
        'sr': sigRank,
        'cm': crowdMul,
      };

  /// Máy khách: tạm cất quán của mình, dùng đúng quán + đồ đạc + cấp độ của chủ phòng
  void enterRaceCfg(Map<String, dynamic> c) {
    _raceBk ??= jsonDecode(jsonEncode(saveMap())) as Map<String, dynamic>; // bản sao độc lập
    venueId = (c['vn'] ?? venueId).toString();
    lv = Map<String, int>.from(((c['lv'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
    recipes = Set<String>.from((c['rc'] as List?) ?? recipes.toList());
    style = (c['sy'] ?? style).toString();
    light = (c['li'] ?? light).toString();
    final pt = List<String>.from((c['pt'] as List?) ?? const []);
    pets = pt.toSet();
    petHappy = {for (final id in pt) id: 100};
    decos = parseDecos(c['de']);
    tablePos = parsePos(c['tp']);
    day = (c['day'] as num?)?.toInt() ?? day;
    diff = (c['df'] ?? diff).toString();
    rnd = Random((c['seed'] as num?)?.toInt() ?? 1);
    raceHost = (c['own'] ?? '').toString();
    sig = isSigVenue(venueId) ? venueId : '';
    sigRank = (c['sr'] as num?)?.toInt() ?? 1;
    crowdMul = (c['cm'] as num?)?.toDouble() ?? 1;
    crowdFactors = [CrowdFactor('🏁', 'Lượng khách theo quán của ${raceHost.isEmpty ? 'chủ phòng' : raceHost}', crowdMul - 1)];
  }

  /// Trả lại quán của mình (giữ số tiền đã kiếm được trong ván)
  void exitRaceCfg() {
    final bk = _raceBk;
    if (bk == null) return;
    final keep = money;
    resetData();
    applySave(bk);
    money = keep;
    _raceBk = null;
  }

  String raceHost = '';

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
    final raceBk = _raceBk;
    if (raceBk != null) {
      await p.setString('save_$owner', jsonEncode({...raceBk, 'money': money}));
      return;
    }
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
      jsonEncode({...saveMap(), 'money': m0, 'day': d0, 'venue': v0}),
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
        'df': diff,
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
        'oq': outsideQ.map((e) => e.toJson()).toList(),
        'cm': r2(crowdMul),
        'tri': trayIds,
        'trq': trayQty,
        'act': activeStation,
        'msg': msg,
        'mt': r2(msgT),
        'sl': starsLog,
      };

  Map<String, dynamic> raceStatus() => {'t': 'race', 'scr': screen, 'sv': served, 'ea': earned, 'ss': starSum, 'ls': lost, 'tl': r2(timeLeft), 'day': day, 'own': owner};

  void applySnapshot(Map<String, dynamic> m) {
    var reward = false;
    List<T> lst<T>(String k, T Function(Map<String, dynamic>) f) => (m[k] as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    setState(() {
      myRole = 'both';
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
      hostDiff = m['df'] as String? ?? 'auto';
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
      outsideQ = m['oq'] == null ? [] : lst('oq', OutsideGuest.fromJson);
      crowdMul = (m['cm'] as num?)?.toDouble() ?? 1;
      trayIds = List<String>.from((m['tri'] as List?) ?? const []);
      trayQty = [for (final x in (m['trq'] as List?) ?? const []) (x as num).toInt()];
      trayQ = List.filled(trayIds.length, 0.8);
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
    oppStars = (m['ss'] as num?)?.toInt() ?? 0;
    oppLost = (m['ls'] as num?)?.toInt() ?? 0;
    oppScr = m['scr'] as String? ?? 'wait';
    oppOwner = m['own'] as String? ?? oppOwner;
    playResult();
  }

  void onNet(Map<String, dynamic> m) {
    lastPeer = DateTime.now();
    final t = m['t'];
    final who = m['own'];
    if (who is String && who.isNotEmpty) peerName = who;
    if (mode == 'pending') {
      // Hai máy cùng vào phòng chờ: máy vào trước làm chủ phòng
      if (t == 'hello') {
        final at = (m['at'] as num?)?.toInt() ?? 0;
        final iFirst = myJoinAt < at || (myJoinAt == at && owner.compareTo(peerName) <= 0);
        if (iFirst) {
          becomeHost();
        } else {
          becomeGuest();
        }
      } else if (t == 'join') {
        becomeHost();
      } else if (t == 'state' || t == 'race') {
        becomeGuest();
        onNet(m);
      }
      return;
    }
    if (mode == 'host') {
      if (t == 'join' || t == 'hello') {
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
        if (screen != 'play') guestJoined = false; // người kia rời phòng: chờ họ vào lại
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
        if (gameType == 'race' && screen != 'play') {
          startDay(cfg: m['cfg'] is Map ? Map<String, dynamic>.from(m['cfg'] as Map) : null);
        }
      } else if (t == 'bye') {
        leaveRoom(notice: 'Chủ phòng đã rời phòng');
      }
    }
  }

  /// Chạy thao tác của máy khách mà không làm đổi bếp đang chọn trên máy chủ
  void _keepActive(VoidCallback f) {
    final keep = activeStation;
    f();
    activeStation = keep;
  }

  void applyAction(Map<String, dynamic> m) {
    switch (m['a']) {
      case 'table':
        onTable((m['i'] as num).toInt(), (m['d'] as num?)?.toInt());
        break;
      case 'station':
        _keepActive(() => onStation((m['i'] as num).toInt()));
        break;
      case 'ing':
        _keepActive(() => onIngredient(m['id'] as String, (m['st'] as num?)?.toInt()));
        break;
      case 'heat':
        _keepActive(() => onHeat((m['i'] as num).toInt(), (m['d'] as num).toDouble()));
        break;
      case 'inc':
        onIncident((m['id'] as num).toInt(), m['tool'] as String?);
        break;
    }
    if (screen == 'play') net.send(snapshot());
    setState(() {});
  }

  /// Vào phòng chờ chung của 2 máy (không cần mã). Ai vào trước làm chủ phòng.
  Future<void> enterDuo() async {
    if (!onlineConfigured) return snack('Chưa điền Supabase trong lib/config.dart');
    roomCode = duoRoom;
    mode = 'pending';
    peerName = '';
    myJoinAt = DateTime.now().millisecondsSinceEpoch;
    guestJoined = false;
    joined = false;
    oppScr = 'wait';
    lastPeer = DateTime.now();
    netStatus = 'Đang kết nối…';
    setState(() {});
    await net.connect(roomCode, onNet, () {
      if (mounted) setState(() => netStatus = 'Đang chờ người kia vào phòng…');
      net.send({'t': 'hello', 'at': myJoinAt, 'own': owner});
    }, (e) {
      if (mounted) setState(() => netStatus = 'Lỗi kết nối: $e');
    });
    netTimer?.cancel();
    netTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mode == 'pending') {
        net.send({'t': 'hello', 'at': myJoinAt, 'own': owner});
      } else if (mode == 'host') {
        net.send(race ? raceStatus() : snapshot());
      } else if (mode == 'guest') {
        net.send({'t': 'join', 'own': owner}); // vừa là xin vào, vừa là ping
        if (race) net.send(raceStatus());
      }
      if (mounted) setState(() {});
    });
  }

  void becomeHost() {
    mode = 'host';
    gameType = createGame;
    myRole = 'both';
    oppScr = 'wait';
    guestJoined = true;
    lastPeer = DateTime.now();
    Sound.sfx('door', vol: 0.6);
    setState(() => screen = 'lobby');
    net.send(race ? raceStatus() : snapshot());
  }

  void becomeGuest() {
    _bk = [money, day, venueId];
    mode = 'guest';
    gameType = 'coop'; // sẽ biết đúng loại khi nhận tin đầu tiên từ chủ phòng
    oppScr = 'wait';
    joined = false;
    lastPeer = DateTime.now();
    netStatus = 'Đang vào phòng${peerName.isEmpty ? '' : ' của $peerName'}…';
    Sound.sfx('door', vol: 0.6);
    setState(() {});
    net.send({'t': 'join', 'own': owner});
  }

  Future<void> leaveRoom({String? notice}) async {
    net.send({'t': 'bye'});
    await Future.delayed(const Duration(milliseconds: 300));
    netTimer?.cancel();
    timer?.cancel();
    await net.disconnect();
    exitRaceCfg();
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
        if (mode == 'guest' || mode == 'pending') {
          leaveRoom();
        } else if (hubTab != 'map') {
          setState(() => hubTab = 'map');
        } else {
          SystemNavigator.pop();
        }
        break;
      case 'shop':
        setState(() => screen = shopBack);
        break;
      case 'profile':
        if (owner.isEmpty) {
          SystemNavigator.pop();
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
  void startDay({Map<String, dynamic>? cfg}) {
    Map<String, dynamic>? sendCfg;
    final fromHost = race && mode != 'host' && cfg != null;
    if (!fromHost) {
      // lượng khách hôm nay: thời tiết thật, lịch, sự kiện phố, quảng cáo, hạng quán
      crowdFactors = Crowd.factors(venueId: venueId, sig: isSigVenue(venueId), sigRank: sigRank, ads: ads, day: day);
      crowdMul = Crowd.total(crowdFactors);
    }
    if (race && mode == 'host') {
      final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
      rnd = Random(seed);
      sendCfg = raceCfg(seed);
      raceHost = owner;
    } else if (race && cfg != null) {
      enterRaceCfg(cfg);
    } else if (!race) {
      rnd = Random();
    }
    tables = List.generate(min(4 + lvl('tables'), venue.maxTables), (_) => TableS());
    if (buffet) {
      trayIds = venue.recipes.where((r) => recipes.contains(r.id)).map((r) => r.id).take(4).toList();
      trayQty = List.filled(trayIds.length, 3);
      trayQ = List.filled(trayIds.length, 0.8);
    } else {
      trayIds = [];
      trayQty = [];
      trayQ = [];
    }
    stations = List.generate(2 + lvl('stations'), (_) => Station());
    queue = [];
    counter = [];
    incidents = [];
    outsideQ = [];
    incT = 25 + rnd.nextDouble() * 15;
    tool = null;
    earned = 0;
    served = 0;
    lost = 0;
    starSum = 0;
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
      oppStars = 0;
      oppLost = 0;
      oppScr = 'play';
      if (mode == 'host') net.send({'t': 'start', 'cfg': sendCfg});
      net.send(raceStatus());
    } else if (mode == 'host') {
      net.send(snapshot());
    }
  }

  void endDay() {
    timer?.cancel();
    endGoal = goal;
    if (earned >= goal) money += 50;
    exitRaceCfg(); // thi đấu xong: về lại quán của mình
    day++;
    // thú cưng đói dần qua mỗi ngày, nhớ cho ăn và vuốt ve
    for (final id in pets) {
      petHappy[id] = max(0, (petHappy[id] ?? 50) - 20);
    }
    incidents = [];
    outsideQ = [];
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
    final avail = [...venue.recipes.where((r) => recipes.contains(r.id)), ...gardenMenu];
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
    if (npc == null && adOn('tv') && rnd.nextDouble() < 0.06) {
      npc = npcTypes.firstWhere((n) => n.id == 'vip', orElse: () => npcTypes.first); // quảng cáo tivi kéo khách VIP
    }
    var r = avail[rnd.nextInt(avail.length)];
    if (buffet && trayIds.isNotEmpty) r = recipeById(trayIds[rnd.nextInt(trayIds.length)]);
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
        // càng về sau khách càng đông, có lúc đến cả nhóm 2 người
        // cấp càng cao càng hay đến theo nhóm; gần cấp 20 có cả nhóm 3 người
        final roll = rnd.nextDouble();
        final arrivals = effDay(day) < 4 ? 1 : (ease > 0.7 && roll < 0.25 * ease ? 3 : (roll < 0.55 * ease ? 2 : 1));
        for (var k = 0; k < arrivals; k++) {
          if (free.isNotEmpty) {
            spawnCustomer(free.removeAt(rnd.nextInt(free.length)), maxPat);
          } else if (outsideQ.length < maxOutside) {
            // quán kín bàn: khách đứng xếp hàng ngoài cửa
            outsideQ.add(OutsideGuest(outsidePat, rnd.nextInt(1 << 20)));
            if (outsideQ.length == 1) say('🚶 Quán kín bàn rồi, khách đang xếp hàng ngoài cửa!');
          }
        }
        spawnT = max(1.4, (5 + rnd.nextDouble() * 4) * (1.5 - 0.9 * ease) * venue.spawnMul / crowdMul); // khách đến thưa lúc đầu, dày dần
      }
    }

    // Khách xếp hàng ngoài cửa: có bàn trống sạch thì mời vào, chờ lâu quá thì bỏ đi
    if (outsideQ.isNotEmpty) {
      if (timeLeft <= 0) {
        outsideQ.clear(); // hết giờ: đóng cửa, khách ngoài cửa về nhà
      } else {
        for (final g in outsideQ) {
          g.pat -= dt * (petOn('cat') ? 0.9 : 1.0);
        }
        final gone = outsideQ.where((g) => g.pat <= 0).length;
        if (gone > 0) {
          outsideQ.removeWhere((g) => g.pat <= 0);
          lost += gone;
          for (var k = 0; k < gone; k++) {
            starsLog.add(1);
          }
          say('😠 Khách đứng chờ ngoài cửa lâu quá nên bỏ đi rồi!');
        }
        final free = [
          for (var i = 0; i < tables.length; i++)
            if (tables[i].c == null && !tables[i].dirty) i
        ];
        while (outsideQ.isNotEmpty && free.isNotEmpty) {
          final g = outsideQ.removeAt(0);
          // khách đã chờ lâu ngoài cửa vào bàn sẽ kém kiên nhẫn hơn
          spawnCustomer(free.removeAt(0), maxPat * (0.55 + 0.45 * g.frac));
        }
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

    if (buffet) {
      for (final t in tables) {
        final c = t.c;
        if (c != null && c.st == 0) {
          final k = trayIds.indexOf(c.recipe.id);
          if (k >= 0 && trayQty[k] > 0) {
            trayQty[k]--;
            c.st = 2;
            c.quality = trayQ[k];
            c.taste = 'Vừa';
            c.eat = 4;
          }
        }
        if (t.dirty && t.dirtyT > 3) t.dirty = false; // nhân viên buffet tự dọn
      }
      for (var k = 0; k < trayIds.length; k++) {
        final want = -1 - k;
        if (trayQty[k] <= 2 && !queue.any((q) => q.table == want) && !stations.any((st) => st.t?.table == want)) {
          queue.add(Ticket(++ticketSeq, want, recipeById(trayIds[k])));
          if (trayQty[k] == 0) say('🍱 Quầy buffet hết ${recipeById(trayIds[k]).name}! Nấu thêm ngay');
        }
      }
    }

    // Bếp: canh lửa, nấu, chờ lấy món
    final fireSt = incidents.where((x) => x.type == 'fire').map((x) => x.target).toSet();
    for (var si = 0; si < stations.length; si++) {
      final s = stations[si];
      if (s.t == null) continue;
      if (s.t!.table >= 0 && !tables.any((t) => t.c?.ticketId == s.t!.id)) {
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
      win = raceDiff >= 0;
    } else {
      win = earned >= (endGoal > 0 ? endGoal : goalFor(day - 1));
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
    if (isSigVenue(venueId) && sigRank > 1) gain = (gain * (1 + 0.08 * (sigRank - 1))).round(); // quán càng sao càng đắt khách
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
          special = '📰 Cô Lan chê món ${c.taste == 'Vừa' ? 'chưa ngon' : tasteWord(c.taste, c.recipe.id)} trên blog… ${bonus}💰';
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
    starSum += stars;
    starsLog.add(stars);
    final luck = lucky ? ' 🍀 May mắn x1.5!' : '';
    if (special != null) {
      say('$special$luck', 4);
    } else if (c.quality < 0.6) {
      say('😡 Món ăn dở quá!');
    } else if (c.taste == 'Nhạt' || c.taste == 'Đậm') {
      say('😕 Món hơi ${tasteWord(c.taste, c.recipe.id)}… +$gain$luck');
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
    if (c.st == 0 && buffet) return; // buffet: khách tự lấy món
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

  int cutOf(String id) => shelfNow.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '?', '?')).cut;

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
      final cu = tk.table >= 0 && tk.table < tables.length ? tables[tk.table].c : null;
      s.saltTarget = tk.recipe.salt + (cu?.saltPref ?? 0); // khẩu vị riêng của khách
      s.tol = 0.9 - 0.35 * ease;
      s.heat = 0.5;
    } else if (s.chopping) {
      chop(s);
    } else if (s.done && s.t!.table < 0) {
      // món buffet: đổ thẳng ra khay
      final k = -1 - s.t!.table;
      if (k < trayQty.length) {
        final q = s.burnt ? min(s.quality, 0.35) : s.quality;
        final old = trayQty[k];
        trayQty[k] = min(trayMax, old + 5);
        trayQ[k] = old == 0 ? q : (trayQ[k] * old + q * 5) / (old + 5);
        say('🍱 Đã châm thêm ${s.t!.recipe.name} ra quầy buffet');
      }
      s.clear();
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

  void doStation(int i) {
    if (remote) guestStation = i;
    _act({'a': 'station', 'i': i}, () => onStation(i));
  }

  void doIngredient(String id, [int? st]) {
    var si = st ?? (remote ? guestStation : null);
    if (remote && (si == null || si < 0 || si >= stations.length || stations[si].t == null)) {
      // máy khách chưa chọn bếp: cho vào bếp đầu tiên đang cần nguyên liệu này
      final cand = [for (var i = 0; i < stations.length; i++) if (stations[i].t?.recipe.ings.contains(id) ?? false) i];
      if (cand.isNotEmpty && st == null) si = cand.first;
    }
    if (remote && si != null) guestStation = si;
    _act({'a': 'ing', 'id': id, 'st': si}, () => onIngredient(id, si));
  }

  void doHeat(int i, double d) {
    if (remote) guestStation = i;
    _act({'a': 'heat', 'i': i, 'd': d}, () => onHeat(i, d));
  }

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
    var stage = false; // màn "sân khấu" nền tối
    switch (screen) {
      case 'lobby':
        body = lobbyScreen();
        stage = true;
        break;
      case 'wait':
        body = waitScreen();
        stage = true;
        break;
      case 'play':
        body = playScreen();
        break;
      case 'end':
        body = endScreen();
        stage = true;
        break;
      case 'shop':
        body = shopScreen();
        break;
      case 'profile':
        body = profileScreen();
        stage = true;
        break;
      default:
        body = hubScreen();
    }
    final inner = Column(children: [
      if (peerLost)
        Container(
          width: double.infinity,
          color: Pal.danger,
          padding: const EdgeInsets.all(6),
          child: Text(race ? '⚠️ Mất kết nối với hàng xóm…' : '⚠️ Mất kết nối với hàng xóm… ván tạm dừng',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        ),
      Expanded(child: body),
    ]);
    final topInset = MediaQuery.of(context).padding.top;
    final hub = screen != 'play' && !stage;
    final Widget page = stage
        ? StageBackground(child: SafeArea(child: inner))
        : Column(children: [
            Container(height: topInset, color: Pal.ink),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: screen == 'menu' ? inner : SafeArea(top: false, child: inner),
              ),
            ),
          ]);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: Scaffold(
        backgroundColor: hub ? Pal.bg : Pal.ink,
        body: Stack(children: [
          Positioned.fill(child: page),
          // bản web: tải sẵn font emoji ngay từ đầu cho mượt
          const Positioned(left: 0, right: 0, top: 0, child: EmojiWarmup()),
        ]),
      ),
    );
  }

  Widget bigButton(String text, VoidCallback? onTap, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: GButton(text, onTap: onTap, colors: color == null ? const [Pal.coral, Pal.coral2] : [color, color]),
      );

  String roleName(String r) => r == 'chef' ? '${castNA ? '👩‍🍳' : '👨‍🍳'} $chefName (Đầu bếp)' : '🛎️ $waiterName (Phục vụ)';

  // =====================================================================
  //  TRUNG TÂM: thanh trên + 4 mục (Bản đồ, Cửa hàng, Quán của tôi, Chơi đôi)
  // =====================================================================
  Widget ownerBadge({double size = 46}) {
    final na = owner == kNgocAnh;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: na ? const [Color(0xFFFF9EC4), Color(0xFFFFC7A8)] : const [Color(0xFF8EC5FF), Color(0xFFB6F0D8)]),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ClipOval(
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            top: -size * 0.33,
            left: (size - size * 1.9) / 2,
            child: PersonAvatar(look: na ? ngocAnhLook : nguyenLook, role: '', height: size * 2.38),
          ),
        ]),
      ),
    );
  }

  Widget hubHeader() => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 10, 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Pal.ink, Pal.ink2]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: Row(children: [
          GestureDetector(onTap: () => setState(() => screen = 'profile'), child: ownerBadge()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shopName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatPill('💰', '$money'),
                StatPill('📅', 'Ngày $day'),
                StatPill(realDayEmoji(), realDayLabel()),
              ]),
            ]),
          ),
          RoundIcon(Icons.menu_book_rounded, onTap: showGuide, tip: 'Hướng dẫn'),
          const SizedBox(width: 6),
          RoundIcon(Icons.tune_rounded, onTap: showSettings, tip: 'Cài đặt'),
        ]),
      );

  Widget hubScreen() {
    Widget content;
    switch (hubTab) {
      case 'shop':
        content = shopTabs();
        break;
      case 'home':
        content = homeTabs();
        break;
      case 'online':
        content = onlineTab();
        break;
      case 'garden':
        content = GardenTab(
          money: money,
          pay: (c) {
            final ok = pay(c);
            if (ok) {
              save();
              setState(() {});
            }
            return ok;
          },
          earn: (m) {
            setState(() => money += m);
            save();
          },
          toast: snack,
        );
        break;
      default:
        content = mapTab();
    }
    return Column(children: [
      hubHeader(),
      Expanded(child: content),
      Padding(
        padding: EdgeInsets.only(top: 6, bottom: MediaQuery.of(context).padding.bottom),
        child: HubDock(
          current: hubTab,
          onSelect: (id) => setState(() => hubTab = id),
          items: [
            ('map', '🗺️', 'Bản đồ'),
            ('shop', '🛍️', 'Cửa hàng'),
            ('home', '🏡', 'Quán tôi'),
            ('garden', '🌻', _gardenCare > 0 ? 'Vườn ($_gardenCare)' : 'Vườn'),
            ('online', '👥', 'Chơi đôi'),
          ],
        ),
      ),
    ]);
  }

  // ---------- Bản đồ ----------
  Widget mapTab() {
    final nTables = min(4 + lvl('tables'), venue.maxTables);
    final nRecipes = venue.recipes.where((r) => recipes.contains(r.id)).length;
    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        bottom: 200,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
          child: TownMap(owned: owned, current: venueId, night: style == 'night' || realDayPhase() == 2, onTap: onVenueTap, sigs: sigSpots()),
        ),
      ),
      Positioned(
        top: 10,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: Colors.white.withAlpha(235), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)]),
            child: const Text('👆 Chạm quán để chọn • kéo, chụm 2 ngón để xem phố', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.text, fontSize: 12.5)),
          ),
        ),
      ),
      Positioned(
        left: 12,
        right: 12,
        bottom: 6,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Pal.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x33221B3F), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              EmojiTile(venue.emoji, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(venue.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Pal.text)),
                  const SizedBox(height: 2),
                  Text('🎯 Mục tiêu $goal💰  •  🪑 $nTables bàn  •  📖 $nRecipes món', style: const TextStyle(color: Pal.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            crowdRow(),
            if (isSigVenue(venueId) && venueId == sig) ...[
              const SizedBox(height: 6),
              SoftButton('Quán ${'⭐' * sigRank} • nâng hạng quán', emoji: '🏅', onTap: showSigManage),
            ],
            const SizedBox(height: 8),
            GButton('Mở cửa ngày $day', emoji: '▶', onTap: () {
              mode = 'local';
              myRole = 'both';
              startDay();
            }),
          ]),
        ),
      ),
    ]);
  }

  // =====================================================================
  //  NHÀ HÀNG RIÊNG + LƯỢNG KHÁCH + QUẢNG CÁO
  // =====================================================================
  List<SigSpot> sigSpots() {
    final p = Garden.instance.sigOf(partnerName);
    return [
      SigSpot(hitId: sig.isEmpty ? 'sig_mine' : sig, venueId: sig.isEmpty ? null : sig, owner: owner.isEmpty ? 'Bạn' : owner, rank: sigRank, mine: true),
      SigSpot(hitId: 'sig_partner', venueId: p?.$1, owner: partnerName, rank: p?.$2 ?? 1, mine: false),
    ];
  }

  void _publishSig() {
    if (sig.isEmpty || owner.isEmpty) return;
    Garden.instance.act('sig', {'own': owner, 'v': sig, 'r': sigRank});
  }

  /// Dòng "Khách hôm nay" trên thẻ quán
  Widget crowdRow() {
    final f = Crowd.factors(venueId: venueId, sig: isSigVenue(venueId), sigRank: sigRank, ads: ads, day: day);
    final m = Crowd.total(f);
    return Material(
      color: m >= 1 ? const Color(0xFFE6F7EF) : const Color(0xFFFFEDE6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: showCrowd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Text('📈 Khách hôm nay ${Crowd.fmt(m)}', style: TextStyle(fontWeight: FontWeight.w900, color: m >= 1 ? Pal.mint : Pal.coral, fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: Text(f.map((x) => x.emoji).join(' '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15))),
            const Text('📣 Quảng cáo ›', style: TextStyle(color: Pal.coral, fontWeight: FontWeight.w900, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  /// Bảng chi tiết lượng khách + mua quảng cáo
  void showCrowd() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Lượng khách hôm nay', emoji: '📈', builder: (ctx, setS) {
      final f = Crowd.factors(venueId: venueId, sig: isSigVenue(venueId), sigRank: sigRank, ads: ads, day: day);
      final m = Crowd.total(f);
      final w = Crowd.weather;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Text('Khách đến ${venue.emoji} ${venue.name} hôm nay: ${Crowd.fmt(m)} so với bình thường',
            style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
        const SizedBox(height: 4),
        Text(
          w == null
              ? '🌡️ ${Crowd.weatherErr.isEmpty ? 'Đang lấy thời tiết Đà Nẵng…' : Crowd.weatherErr}'
              : '🌡️ Thời tiết thật tại Hoà Xuân, Đà Nẵng: ${w.emoji} ${w.text}, ${w.temp.round()}°C',
          style: const TextStyle(color: Pal.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (f.isEmpty) const Text('Hôm nay bình thường, không có gì đặc biệt.', style: TextStyle(color: Pal.muted)),
        for (final x in f)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Text(x.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(child: Text(x.label, style: const TextStyle(color: Pal.text, fontSize: 13))),
              Text(x.pct, style: TextStyle(fontWeight: FontWeight.w900, color: x.delta >= 0 ? Pal.mint : Pal.danger)),
            ]),
          ),
        const SectionTitle('📣 Quảng cáo', sub: 'Tính theo số ngày mở cửa, mua thêm để kéo dài'),
        for (final a in adTypes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Text(a.$2, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.$3, style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
                    Text('Khách +${(a.$5 * 100).round()}% trong ${a.$6} ngày${a.$1 == 'tv' ? ' • kéo cả khách VIP' : ''}',
                        style: const TextStyle(color: Pal.muted, fontSize: 12)),
                    if (adOn(a.$1))
                      Text('Đang chạy, còn ${(ads[a.$1] ?? day) - day} ngày', style: const TextStyle(color: Pal.mint, fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
                ),
                PriceButton(a.$4, afford: money >= a.$4, onTap: () {
                  if (!pay(a.$4)) return;
                  Sound.sfx('coin');
                  setState(() => ads[a.$1] = max(ads[a.$1] ?? 0, day) + a.$6);
                  save();
                  setS(() {});
                  snack('${a.$2} Đã chạy ${a.$3.toLowerCase()} trong ${a.$6} ngày!');
                }),
              ]),
            ),
          ),
        const Text('Thời tiết lấy thật từ Open-Meteo. Cuối tuần, ngày lương, ngày lễ theo lịch thật. Sự kiện phố là sự kiện trong game.',
            style: TextStyle(color: Pal.muted, fontSize: 11)),
      ]);
    });
  }

  /// Chọn 1 trong 3 kiểu nhà hàng riêng
  void openSigPicker() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Mở nhà hàng riêng', emoji: '🏗️', builder: (ctx, setS) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        const Text('Mỗi người chỉ chọn được 1 kiểu. Mở xong thì nâng hạng dần để quán đông khách, bán đắt hơn.',
            style: TextStyle(color: Pal.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        for (final id in sigVenueIds) _sigCard(ctx, id),
      ]);
    });
  }

  Widget _sigCard(BuildContext ctx, String id) {
    final v = venueById(id);
    final afford = money >= v.cost;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            EmojiTile(v.emoji, size: 48),
            const SizedBox(width: 10),
            Expanded(child: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Pal.text))),
          ]),
          const SizedBox(height: 6),
          Text(sigBlurb[id] ?? '', style: const TextStyle(color: Pal.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in v.recipes)
              Column(mainAxisSize: MainAxisSize.min, children: [
                DishIcon(r.id, size: 52),
                SizedBox(
                  width: 72,
                  child: Text(r.name, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ]),
          ]),
          const SizedBox(height: 10),
          GButton(
            afford ? 'Mở quán • 💰 ${v.cost}' : 'Cần thêm 💰 ${v.cost - money}',
            emoji: '🔑',
            onTap: afford
                ? () {
                    if (!pay(v.cost)) return;
                    Sound.sfx('goal');
                    setState(() {
                      sig = id;
                      sigRank = 1;
                      owned.add(id);
                      recipes.addAll(v.recipes.where((r) => r.unlock == 0).map((r) => r.id));
                      venueId = id;
                      activeStation = -1;
                    });
                    save();
                    _publishSig();
                    Navigator.pop(ctx);
                    snack('🎉 Khai trương ${v.name}! Món mới mở thêm ở 🛍️ Cửa hàng.');
                  }
                : null,
          ),
        ]),
      ),
    );
  }

  Widget _meter(String label, double v, Color col, String right) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 96, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Pal.text))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: v.clamp(0.0, 1.0).toDouble(), minHeight: 9, backgroundColor: const Color(0xFFF0EAE0), color: col),
            ),
          ),
          SizedBox(width: 62, child: Text(right, textAlign: TextAlign.right, style: const TextStyle(color: Pal.muted, fontSize: 11.5, fontWeight: FontWeight.w700))),
        ]),
      );

  /// Phần "Kinh doanh tự động" trong bảng quản lý nhà hàng riêng
  List<Widget> bizPanel(StateSetter setS) {
    bizRun();
    final now = DateTime.now();
    final b = biz;
    void done(String msg) {
      save();
      setS(() {});
      setState(() {});
      if (msg.isNotEmpty) snack(msg);
    }

    final ev = Biz.eventOf(owner, now);
    final evData = ev == null ? null : bizEvents[ev.$1];
    final evStarted = ev != null && now.hour + now.minute / 60 >= ev.$2;
    final dk = Biz.dayKey(now);
    final restock = b.restockCost(_sigAvgPrice, now, owner);
    final open = now.hour >= 8 && now.hour < 22;
    return [
      const SectionTitle('🏪 Kinh doanh tự động', sub: 'Thuê nhân viên, quán tự mở cửa 8h–22h kể cả khi bạn tắt game'),
      if (!b.hired)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Cần ít nhất 1 đầu bếp và 1 phục vụ để quán tự chạy.', style: TextStyle(color: Pal.coral, fontWeight: FontWeight.w700)),
        ),
      AppCard(
        child: Column(children: [
          Row(children: [
            Text(b.hired ? (open ? '🟢 Đang mở cửa' : '🌙 Đã đóng cửa (mở 8h–22h)') : '⚪ Chưa có nhân viên',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
            const Spacer(),
            Text('💰 ${b.cash.round()} / ${b.cashCap.round()}', style: TextStyle(fontWeight: FontWeight.w900, color: b.cash < 0 ? Pal.danger : Pal.gold)),
          ]),
          const SizedBox(height: 8),
          _meter('😊 Tinh thần', b.morale / 100, b.morale < 30 ? Pal.danger : Pal.mint, '${b.morale.round()}%'),
          _meter('🧽 Vệ sinh', b.clean / 100, b.clean < 50 ? Pal.danger : Pal.sky, '${b.clean.round()}%'),
          _meter('📦 Hàng hoá', b.stock / 40, b.stock < 5 ? Pal.danger : Pal.gold, '${b.stock.round()} phần'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            SoftButton('Thu tiền', emoji: '💰', onTap: b.cash <= 0
                ? null
                : () {
                    final m = b.cash.round();
                    money += m;
                    b.cash = 0;
                    Sound.sfx('coin');
                    done('💰 Thu về $m💰');
                  }),
            SoftButton('Nhập hàng −$restock', emoji: '📦', onTap: () {
              if (!pay(restock)) return;
              b.stock += 20;
              done('📦 Đã nhập 20 phần hàng');
            }),
            SoftButton('Thưởng −100', emoji: '🎁', onTap: () {
              if (!pay(100)) return;
              b.morale = min(100.0, b.morale + 25);
              done('🎁 Nhân viên vui hẳn lên!');
            }),
            SoftButton('Tổng vệ sinh −60', emoji: '🧽', onTap: () {
              if (!pay(60)) return;
              b.clean = 100;
              done('🧽 Quán sạch bong');
            }),
          ]),
        ]),
      ),
      ..._bizExtras(setS, done),
      if (evData != null) ...[
        const SizedBox(height: 8),
        AppCard(
          color: const Color(0xFFFFF8E1),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${evData.$2} Hôm nay: ${evData.$3} (${ev!.$2.floor()}h)', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
            Text(evData.$4, style: const TextStyle(color: Pal.muted, fontSize: 12.5)),
            if (evData.$1 == 'raise' && evStarted && b.decided != dk) ...[
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: SoftButton('Đồng ý +10%', emoji: '✅', onTap: () {
                    b.decided = dk;
                    b.wageMul *= 1.1;
                    b.morale = min(100.0, b.morale + 20);
                    done('Nhân viên rất vui vì được tăng lương');
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SoftButton('Từ chối', emoji: '✋', onTap: () {
                    b.decided = dk;
                    b.morale = max(0.0, b.morale - 15);
                    done('Nhân viên hơi buồn…');
                  }),
                ),
              ]),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 8),
      for (final st in staffTypes)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Text(st.$2, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${st.$3} • cấp ${b.lv(st.$1)}/${st.$6}', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
                  if (b.lv(st.$1) > 0 && b.person(st.$1) != null)
                    Text('${b.person(st.$1)!.$1} • ${b.person(st.$1)!.$2} • tay nghề +${b.person(st.$1)!.$3}%',
                        style: const TextStyle(color: Pal.mint, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  Text('${st.$7} • lương ${st.$5}💰/giờ mỗi cấp', style: const TextStyle(color: Pal.muted, fontSize: 11.5)),
                ]),
              ),
              if (b.lv(st.$1) < st.$6)
                PriceButton(st.$4 * (b.lv(st.$1) + 1), afford: money >= st.$4 * (b.lv(st.$1) + 1), onTap: () {
                  if (!pay(st.$4 * (b.lv(st.$1) + 1))) return;
                  b.staff[st.$1] = b.lv(st.$1) + 1;
                  b.hire(st.$1, Random());
                  if (b.last == 0) b.last = DateTime.now().millisecondsSinceEpoch;
                  Sound.sfx('coin');
                  done('${st.$2} Đã thuê ${st.$3.toLowerCase()} cấp ${b.lv(st.$1)}');
                })
              else
                const Tag('Tối đa'),
            ]),
          ),
        ),
      if (b.log.isNotEmpty) ...[
        const SectionTitle('📒 Nhật ký quán'),
        for (final l in b.log.take(8)) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(l, style: const TextStyle(color: Pal.muted, fontSize: 12))),
      ],
    ];
  }

  /// Món chủ lực, nông sản từ vườn, khách quen, cuộc thi doanh thu tuần
  List<Widget> _bizExtras(StateSetter setS, void Function(String) done) {
    final b = biz;
    final wk = Biz.weekOf(DateTime.now());
    final menu = venueById(sig).recipes.where((r) => recipes.contains(r.id)).toList();
    final w = Crowd.weather;
    final warm = w != null && (w.rain || w.storm || w.temp < 24), hot = w != null && w.temp >= 31;
    final canPick = b.featuredWeek != wk;
    final pr = partnerRev();
    final theirs = pr == null ? 0 : (pr.$1 == wk ? pr.$2 : 0);
    final mine = b.week == wk ? b.weekRev.round() : 0;
    return [
      const SizedBox(height: 8),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🍽️ Món chủ lực của tuần', style: TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
          Text(
            canPick
                ? 'Chọn 1 món (mỗi tuần 1 lần): bán đắt hơn 5%, hợp thời tiết thì khách tăng 20%. ${warm ? 'Hôm nay mưa/mát: món nóng đắt khách.' : (hot ? 'Hôm nay nắng nóng: món tươi mát đắt khách.' : '')}'
                : 'Tuần này đã chọn: ${b.featured.isEmpty ? '' : recipeById(b.featured).name}',
            style: const TextStyle(color: Pal.muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in menu)
              GestureDetector(
                onTap: !canPick
                    ? null
                    : () {
                        b.featured = r.id;
                        b.featuredWeek = wk;
                        done('🍽️ Món chủ lực tuần này: ${r.name}');
                      },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: b.featured == r.id ? const Color(0xFFFFEDE6) : Pal.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: b.featured == r.id ? Pal.coral : Pal.line, width: b.featured == r.id ? 2 : 1),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DishIcon(r.id, size: 40),
                    Text(dishIsWarm(r.id) ? '🔥 nóng' : (dishIsFresh(r.id) ? '❄️ mát' : '•'), style: const TextStyle(fontSize: 10)),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _meter('🤝 Khách quen', b.regulars / 50, Pal.berry, '${b.regulars.round()} người'),
          const Text('Khách hài lòng (nhân viên vui, quán sạch) sẽ thành khách quen và rủ bạn bè tới: tối đa +50% khách.',
              style: TextStyle(color: Pal.muted, fontSize: 11.5)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text('🌻 Nông sản từ vườn: ${b.farm.round()} phần trong kho, $farmAvail phần chờ lấy (bán đắt hơn 15%)',
                  style: const TextStyle(color: Pal.text, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            SoftButton('Lấy', emoji: '🧺', onTap: farmAvail <= 0
                ? null
                : () {
                    final n = farmAvail;
                    b.farm += n;
                    b.stock += n;
                    b.farmClaimed += n ~/ 6;
                    done('🧺 Đã lấy $n phần nông sản từ vườn');
                  }),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      AppCard(
        color: const Color(0xFFEAF1FF),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🏆 Thi doanh thu tuần này', style: TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text('${owner.isEmpty ? 'Bạn' : owner}: $mine💰', style: TextStyle(fontWeight: FontWeight.w900, color: mine >= theirs ? Pal.mint : Pal.text))),
            Expanded(child: Text('$partnerName: $theirs💰', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w900, color: theirs > mine ? Pal.mint : Pal.text))),
          ]),
          const Text('Hết tuần, quán nào bán nhiều hơn được thưởng 300💰.', style: TextStyle(color: Pal.muted, fontSize: 11.5)),
        ]),
      ),
    ];
  }

  /// Quản lý nhà hàng riêng: nâng hạng, quảng cáo
  void showSigManage() {
    Sound.sfx('tap');
    final v = venueById(sig);
    showGameSheet(context, title: v.name, emoji: v.emoji, builder: (ctx, setS) {
      final maxed = sigRank >= 5;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Center(child: Text('⭐' * sigRank + '☆' * (5 - sigRank), style: const TextStyle(fontSize: 30))),
        Center(child: Text('Hạng $sigRank / 5', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text))),
        const SizedBox(height: 8),
        Text(
          'Mỗi hạng: khách +6%, món bán đắt hơn 8%. Hiện tại: khách +${(sigRank - 1) * 6}%, giá +${(sigRank - 1) * 8}%.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Pal.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        GButton(
          maxed ? 'Đã đạt hạng cao nhất' : (money >= sigUpCost ? 'Lên hạng ${sigRank + 1} • 💰 $sigUpCost' : 'Cần thêm 💰 ${sigUpCost - money}'),
          emoji: '⭐',
          onTap: maxed || money < sigUpCost
              ? null
              : () {
                  if (!pay(sigUpCost)) return;
                  Sound.sfx('goal');
                  setState(() => sigRank++);
                  save();
                  _publishSig();
                  setS(() {});
                  snack('⭐ ${v.name} lên hạng $sigRank!');
                },
        ),
        const SizedBox(height: 10),
        SoftButton('Quảng cáo & lượng khách', emoji: '📣', onTap: () {
          Navigator.pop(ctx);
          showCrowd();
        }),
        ...bizPanel(setS),
      ]);
    });
  }

  /// Xem nhà hàng riêng của người kia
  void showPartnerSig() {
    Sound.sfx('tap');
    final p = Garden.instance.sigOf(partnerName);
    showGameSheet(context, title: 'Quán của $partnerName', emoji: p == null ? '🚧' : venueById(p.$1).emoji, builder: (ctx, setS) {
      if (p == null) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Text('$partnerName chưa mở nhà hàng riêng. Khi mở xong, quán sẽ hiện ở đây trên bản đồ của bạn.', style: const TextStyle(color: Pal.text)),
        );
      }
      final v = venueById(p.$1);
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Text(v.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Pal.text)),
        Text('${'⭐' * p.$2} • Hạng ${p.$2}/5', style: const TextStyle(color: Pal.muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final r in v.recipes) DishIcon(r.id, size: 52)]),
        const SizedBox(height: 10),
        Text(
          'Muốn cùng làm ở quán này: để $partnerName chọn quán này, vào 👥 Chơi đôi trước (làm chủ phòng) và chọn Hợp tác hoặc Thi đấu, rồi bạn vào sau.',
          style: const TextStyle(color: Pal.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SoftButton(cheerDay == Biz.dayKey(DateTime.now()) ? 'Đã cổ vũ hôm nay' : 'Cổ vũ nhân viên', emoji: '📣',
                onTap: cheerDay == Biz.dayKey(DateTime.now())
                    ? null
                    : () {
                        cheerDay = Biz.dayKey(DateTime.now());
                        Garden.instance.act('cheer', {'to': partnerName});
                        save();
                        setS(() {});
                        snack('📣 Đã cổ vũ quán của $partnerName: nhân viên bên đó vui hơn');
                      }),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SoftButton('Tặng 100💰', emoji: '🎁', onTap: () {
              if (!pay(100)) return;
              Garden.instance.act('gift', {'to': partnerName, 'm': 100});
              save();
              setState(() {});
              snack('🎁 Đã gửi 100💰 vào két quán của $partnerName');
            }),
          ),
        ]),
      ]);
    });
  }

  /// Xem trước phòng chơi bên trong quán (không có khách)
  Widget roomPreview(String id, int nTables) {
    final staffed = isSigVenue(id) && id == sig && biz.hired;
    final wName = staffed ? (biz.person('waiter')?.$1 ?? 'Phục vụ') : waiterName;
    final cName = staffed ? (biz.person('chef')?.$1 ?? 'Đầu bếp') : chefName;
    return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 300,
          child: IgnorePointer(
            child: IsoRoom(
              tables: List.generate(nTables, (_) => TableS()),
              stations: List.generate(2 + lvl('stations'), (_) => Station()),
              counter: const [],
              selDishId: null,
              activeStation: -1,
              hasOrders: false,
              venueId: id,
              style: style,
              light: light,
              waiterLook: castLook(wName, 'waiter'),
              chefLook: castLook(cName, 'chef'),
              waiterName: wName,
              chefName: cName,
              tablePos: tablePos,
              decos: decos,
              pets: pets.toList(),
              onTable: (_) {},
              onDish: (_) {},
              onStation: (_) {},
              onHeat: (_, __) {},
              onIncident: (_) {},
              onPet: (_) {},
            ),
          ),
        ),
      );
  }

  /// Chạm vào quán trên bản đồ: hiện phòng chơi + nút mở cửa
  void showRoomSheet(String id) {
    final v = venueById(id);
    showGameSheet(context, title: v.name, emoji: v.emoji, builder: (ctx, setS) {
      final n = min(4 + lvl('tables'), v.maxTables);
      final nRec = v.recipes.where((r) => recipes.contains(r.id)).length;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        roomPreview(id, n),
        const SizedBox(height: 10),
        Text('🪑 $n bàn  •  📖 $nRec món  •  🎯 mục tiêu $goal💰', textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        crowdRow(),
        const SizedBox(height: 10),
        GButton('Mở cửa ngày $day', emoji: '▶', onTap: () {
          Navigator.pop(ctx);
          mode = 'local';
          myRole = 'both';
          startDay();
        }),
        if (isSigVenue(id) && id == sig) ...[
          const SizedBox(height: 8),
          GButton(biz.hired ? 'Nhân viên & kinh doanh tự động' : 'Thuê nhân viên cho quán', emoji: '👥', onTap: () {
            Navigator.pop(ctx);
            showSigManage();
          }),
          if (!biz.hired)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Cần thuê ít nhất 1 Đầu bếp + 1 Phục vụ thì quán mới tự mở cửa 8h–22h', textAlign: TextAlign.center, style: TextStyle(color: Pal.muted, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          SoftButton('Quán ${'⭐' * sigRank} • nâng hạng quán', emoji: '🏅', onTap: () {
            Navigator.pop(ctx);
            showSigManage();
          }),
        ],
      ]);
    });
  }

  void onVenueTap(String id) {
    if (id == 'garden') {
      Sound.sfx('tap');
      return setState(() => hubTab = 'garden');
    }
    if (id == 'sig_mine') {
      if (sig.isEmpty) return openSigPicker();
      id = sig;
    }
    if (id == 'sig_partner') return showPartnerSig();
    final v = venueById(id);
    if (owned.contains(id)) {
      Sound.sfx('door', vol: 0.6);
      setState(() {
        venueId = id;
        activeStation = -1;
      });
      save();
      showRoomSheet(id);
      return;
    }
    Sound.sfx('tap');
    final busy = v.spawnMul < 0.8 ? 'rất đông' : (v.spawnMul < 1 ? 'đông' : 'vừa phải');
    showGameSheet(context, title: v.name, emoji: v.emoji, builder: (ctx, setS) {
      final afford = money >= v.cost;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
        roomPreview(v.id, 4),
        const SizedBox(height: 10),
        Text('Tối đa ${v.maxTables} bàn • ${v.recipes.length} món • khách đến $busy', style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in v.recipes)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                DishIcon(r.id, size: 28),
                const SizedBox(width: 4),
                Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
        const SizedBox(height: 18),
        GButton(
          afford ? 'Mua quán • 💰 ${v.cost}' : 'Cần thêm 💰 ${v.cost - money}',
          emoji: '🔑',
          onTap: afford
              ? () {
                  if (pay(v.cost)) {
                    Sound.sfx('coin');
                    setState(() {
                      owned.add(v.id);
                      recipes.addAll(v.recipes.where((r) => r.unlock == 0).map((r) => r.id));
                      venueId = v.id;
                      activeStation = -1;
                    });
                    save();
                    Navigator.pop(ctx);
                    snack('🎉 Đã khai trương ${v.name}!');
                  }
                }
              : null,
        ),
      ]);
    });
  }

  // ---------- Chơi đôi ----------
  Widget _modeCard(String id, String emoji, String title, String desc) {
    final sel = createGame == id;
    return GestureDetector(
      onTap: () {
        Sound.sfx('tap');
        setState(() => createGame = id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFEAF1FF) : Pal.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: sel ? Pal.sky : Pal.line, width: sel ? 2.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Pal.text)),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(fontSize: 12, color: Pal.muted, height: 1.3)),
        ]),
      ),
    );
  }

  Widget _roleCard(String r) {
    final sel = createRole == r;
    final name = r == 'chef' ? chefName : waiterName;
    return GestureDetector(
      onTap: () {
        Sound.sfx('tap');
        setState(() => createRole = r);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFFFEDE6) : Pal.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: sel ? Pal.coral : Pal.line, width: sel ? 2.5 : 1),
        ),
        child: Column(children: [
          PersonAvatar(look: castLook(name, r), role: r, height: 96),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
          Text(r == 'chef' ? 'Đầu bếp' : 'Phục vụ', style: const TextStyle(color: Pal.muted, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget onlineTab() {
    final waiting = mode == 'pending' || mode == 'guest';
    final other = owner == kNguyen ? kNgocAnh : kNguyen;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ownerBadge(size: 48),
            const SizedBox(width: 6),
            const Text('🤝', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 6),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.bg, border: Border.all(color: Pal.line, width: 2)),
              child: ClipOval(
                child: Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned(
                    top: -48 * 0.33,
                    left: (48 - 48 * 1.9) / 2,
                    child: PersonAvatar(look: other == kNgocAnh ? ngocAnhLook : nguyenLook, role: '', height: 48 * 2.38),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Chơi 2 máy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Pal.text)),
                Text('Hai máy cùng bấm "Vào phòng chờ" là tự gặp nhau, không cần mã.', style: const TextStyle(color: Pal.muted, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _modeCard('coop', '🤝', 'Hợp tác', 'Chung một quán, cùng thấy bếp và sảnh: ai cũng nấu và phục vụ được')),
            const SizedBox(width: 10),
            Expanded(child: _modeCard('race', '🏁', 'Thi đấu', 'Cùng một quán, cùng đồ đạc và độ khó – ai bán nhiều món hơn thắng')),
          ]),
          const SizedBox(height: 10),
          const Text('Người vào phòng chờ trước sẽ làm chủ phòng và chọn kiểu chơi.',
              style: TextStyle(color: Pal.muted, fontSize: 12)),
          const SizedBox(height: 14),
          if (waiting)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Pal.sky)),
                const SizedBox(width: 12),
                Expanded(child: Text(netStatus, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.text))),
                SoftButton('Huỷ', onTap: () => leaveRoom(), tint: Pal.danger),
              ]),
            )
          else
            GButton('Vào phòng chờ', emoji: '👥', onTap: enterDuo, colors: const [Pal.sky, Color(0xFF7B6CFF)]),
        ]),
      ),
    ]);
  }

  // ---------- Cài đặt & hướng dẫn (bảng trượt) ----------
  Widget castCards(VoidCallback refresh) {
    Widget opt(bool na) {
      final sel = ngocAnhChef == na;
      final chef = na ? kNgocAnh : kNguyen, waiter = na ? kNguyen : kNgocAnh;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            Sound.sfx('tap');
            setState(() => ngocAnhChef = na);
            save();
            refresh();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFFFFEDE6) : Pal.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: sel ? Pal.coral : Pal.line, width: sel ? 2.5 : 1),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                PersonAvatar(look: castLook(chef, 'chef'), role: 'chef', height: 80),
                PersonAvatar(look: castLook(waiter, 'waiter'), role: 'waiter', height: 80),
              ]),
              Text('$chef nấu', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
              Text('$waiter phục vụ', style: const TextStyle(color: Pal.muted, fontSize: 12)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [opt(false), const SizedBox(width: 10), opt(true)]);
  }

  Widget diffCards(VoidCallback refresh) {
    Widget opt((String, String, String, String) m) {
      final (id, emoji, name, sub) = m;
      final sel = diff == id;
      return GestureDetector(
        onTap: () {
          Sound.sfx('tap');
          setState(() => diff = id);
          save();
          refresh();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFFFFEDE6) : Pal.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: sel ? Pal.coral : Pal.line, width: sel ? 2.5 : 1),
          ),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
                Text(sub, style: const TextStyle(color: Pal.muted, fontSize: 11.5), maxLines: 2),
              ]),
            ),
          ]),
        ),
      );
    }

    return Column(children: [
      Row(children: [Expanded(child: opt(diffModes[0])), const SizedBox(width: 8), Expanded(child: opt(diffModes[1]))]),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: opt(diffModes[2])), const SizedBox(width: 8), Expanded(child: opt(diffModes[3]))]),
    ]);
  }

  void confirmResetDay(BuildContext ctx, VoidCallback refresh) {
    if (mode != 'local' || screen == 'play') {
      snack('Hãy rời phòng chơi đôi / kết thúc ngày trước khi đếm lại');
      return;
    }
    showDialog(
      context: ctx,
      builder: (dc) => AlertDialog(
        title: const Text('Đếm lại từ ngày 1?'),
        content: Text('Quán quay về ngày 1 (đang ở ngày $day). Tiền, món, quán và đồ trang trí vẫn giữ nguyên.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Thôi')),
          TextButton(
            onPressed: () {
              Navigator.pop(dc);
              setState(() => day = 1);
              save();
              refresh();
              snack('🔄 Đã quay về ngày 1');
            },
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
  }

  void showSettings() {
    showGameSheet(context, title: 'Cài đặt', emoji: '⚙️', builder: (ctx, setS) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(children: [
            const Text('🔊', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Âm thanh & nhạc nền', style: TextStyle(fontWeight: FontWeight.w800, color: Pal.text))),
            Switch(
              value: Sound.enabled,
              activeTrackColor: Pal.coral,
              onChanged: (v) {
                Sound.setEnabled(v);
                save();
                setS(() {});
                setState(() {});
              },
            ),
          ]),
        ),
        SectionTitle('Độ khó', sub: 'Ngày $day • đang chơi cấp ${min(effDay(day), maxLevel)}/$maxLevel • tiền và đồ đã mua vẫn giữ nguyên'),
        diffCards(() => setS(() {})),
        const SizedBox(height: 8),
        SoftButton('Đếm lại từ ngày 1', emoji: '🔄', onTap: () => confirmResetDay(ctx, () => setS(() {}))),
        const SectionTitle('Ai nấu ăn?', sub: 'Áp dụng cho mọi chế độ chơi'),
        castCards(() => setS(() {})),
        const SectionTitle('Chủ quán của máy này'),
        AppCard(
          onTap: () {
            Navigator.pop(ctx);
            setState(() => screen = 'profile');
          },
          child: Row(children: [
            ownerBadge(size: 40),
            const SizedBox(width: 12),
            Expanded(child: Text(shopName, style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text))),
            const Text('Đổi', style: TextStyle(color: Pal.coral, fontWeight: FontWeight.w900)),
            const Icon(Icons.chevron_right_rounded, color: Pal.coral),
          ]),
        ),
      ]);
    });
  }

  Widget _guideCard(String emoji, String title, List<String> lines, {bool numbered = false, Color tint = Pal.coral}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              EmojiTile(emoji, tint: tint, size: 40),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Pal.text))),
            ]),
            const SizedBox(height: 10),
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (numbered)
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 8, top: 1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                    )
                  else
                    Padding(padding: const EdgeInsets.only(right: 8, top: 7), child: Container(width: 6, height: 6, decoration: BoxDecoration(color: tint, shape: BoxShape.circle))),
                  Expanded(child: Text(lines[i], style: const TextStyle(color: Pal.text, height: 1.4))),
                ]),
              ),
          ]),
        ),
      );

  void showGuide() {
    final pauseIt = screen == 'play' && mode == 'local' && !paused;
    if (pauseIt) setState(() => paused = true);
    final season = 'muối (món mặn) hoặc đường (món ngọt)';
    showGameSheet(context, title: 'Cách chơi', emoji: '📖', builder: (ctx, setS) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        _guideCard('👨‍🍳', 'Đầu bếp • $chefName', [
          'Chạm vào một bếp trống để nhận order mới.',
          'Kéo nguyên liệu từ kệ thả vào bếp (hoặc chạm vào nguyên liệu).',
          'Nguyên liệu có 🔪 nằm trên thớt: chạm vào bếp để thái từng nhát.',
          'Khi nấu, chạm núm − / + trên bếp để giữ kim lửa trong vùng xanh. Lửa quá to lâu sẽ cháy bếp.',
          'Chạm hoặc kéo gia vị ở kệ cho vạch nêm nằm trong vùng xanh: thiếu thì nhạt, thừa thì mặn.',
          'Món chín: chạm bếp để đưa ra quầy trước khi cháy.',
        ], numbered: true),
        _guideCard('🛎️', 'Phục vụ • $waiterName', [
          'Khách giơ tay ❗: chạm vào bàn để nhận order.',
          'Chạm món ở quầy ra món, rồi chạm đúng bàn đang chờ món đó.',
          'Khách ăn xong để lại bàn bẩn: chạm để dọn.',
          'Nhìn qua cửa sổ để biết khách sắp vào quán.',
        ], numbered: true, tint: Pal.mint),
        _guideCard('🧰', 'Sự cố (từ ngày 2)', [
          for (final it in incidentTypes) '${it.emoji} ${it.name}: ${it.hint} (${it.hp} lần).',
        ], tint: Pal.danger),
        _guideCard('⭐', 'Khách đặc biệt', [
          '👑 Ông Bảy (VIP): gọi món đắt nhất, trả gấp đôi, ít kiên nhẫn.',
          '🧐 Cô Lan (phê bình): món ngon và vừa vị thì viết bài khen, có thưởng.',
          '🏹 Chú Tư (thợ săn): mê thịt, thích ăn đậm.',
          '🎒 Bé Na (học sinh): gọi món rẻ, rất kiên nhẫn, thích ăn nhạt.',
          '🕵️ Người lạ bí ẩn: hiếm gặp, hài lòng sẽ để lại phong bì.',
        ], tint: Pal.gold),
        _guideCard('🐾', 'Thú cưng', [
          for (final p in petTypes) '${p.emoji} ${p.name}: ${p.perk}.',
          'Giữ thú cưng từ 40♥ trở lên để chúng giúp quán. Chạm vào thú cưng trong lúc chơi để vuốt ve.',
        ], tint: Pal.berry),
        _guideCard('🏗️', 'Nhà hàng riêng', [
          'Trên bản đồ có 2 lô đất ở hàng đầu: bên trái của bạn, bên phải của người kia.',
          'Chọn 1 trong 3 kiểu: 🦀 Poseidon buffet cua hải sản, 🥓 Goyuhan buffet nướng Hàn Quốc, 🐦 Bình Dần chim đồng, heo tộc.',
          'Nâng hạng quán (1–5 sao): mỗi hạng khách +6%, món đắt hơn 8%. Mở thêm món ở 🛍️ Cửa hàng.',
          'Quán của người kia hiện trên bản đồ của bạn, kèm số sao.',
        ], tint: Pal.coral),
        _guideCard('📈', 'Lượng khách mỗi ngày', [
          'Thời tiết thật ở Đà Nẵng: mưa thì ít khách (trừ quán nướng, quán nhậu lại đông), trời đẹp thì đông.',
          'Lịch thật: cuối tuần, đầu/cuối tháng có lương, ngày lễ thì đông khách.',
          'Sự kiện trong phố mỗi ngày: hội chợ, bóng đá, sửa đường, triều cường…',
          'Quảng cáo: 📄 tờ rơi, 📻 báo đài, 📺 tivi giúp đông khách thêm vài ngày.',
        ], tint: Pal.sky),
        _guideCard('🌻', 'Khu vườn chung', [
          'Vườn dùng chung cho cả Nguyên và Ngọc Anh: ai chăm cũng được, cả hai đều thấy.',
          'Gieo cây ở ruộng, nuôi vịt/bò trong chuồng, thả cá hồi/tôm hùm xuống hồ. Cây con lớn theo ngày thật.',
          'Mỗi ngày: tưới cây 💧, cho ăn 🌽, dọn chuồng/thay nước 🧹. Bón phân/vitamin giúp lớn nhanh hơn.',
          'Thời tiết đổi mỗi ngày: nắng gắt làm cây khát nhanh, mưa bão dễ gây úng và nhiễm lạnh.',
          'Gặp sâu bệnh, cỏ dại, bệnh gia súc… phải vào xử lý thì mới lớn tiếp. Mục 🌻 Vườn hiện số chỗ đang cần chăm.',
          'Thu hoạch lần đầu mở món mới (Vịt quay, Bò Wagyu, Tôm hùm…) bán được ở mọi quán.',
        ], tint: Pal.mint),
        _guideCard('🏁', 'Thi đấu tính điểm', [
          'Hai người thi trong cùng một quán (của chủ phòng): cùng món, cùng đồ đạc, cùng độ khó, khách đến như nhau.',
          'Mỗi khách phục vụ xong được số điểm bằng số sao (1–5). Mỗi khách bỏ về bị trừ 2 điểm.',
          'Nhiều điểm hơn thì thắng. Bằng điểm thì so số khách, rồi so tiền.',
        ], tint: Pal.gold),
        _guideCard('👥', 'Chơi đôi', [
          '👥 Cả hai máy vào tab Chơi đôi, bấm "Vào phòng chờ" là tự gặp nhau. Người vào trước làm chủ phòng và bấm Bắt đầu.',
          '🤝 Hợp tác: 2 máy, một người nấu, một người phục vụ, chung một quán.',
          '🏁 Thi đấu: Nguyên ở nhà hàng của Nguyên, Ngọc Anh ở nhà hàng của Ngọc Anh, ai bán nhiều món hơn thắng.',
          '📱 Một máy: một người lo cả bếp lẫn sảnh, hoặc hai người ngồi cạnh nhau.',
        ], tint: Pal.sky),
        _guideCard('💡', 'Mẹo', [
          'Những ngày đầu khách đến thưa và kiên nhẫn, càng về sau càng đông.',
          'Đồ trang trí và đèn đẹp giúp khách chờ lâu hơn.',
          'Tiền và tiến trình được lưu tự động, kể cả khi thoát app.',
        ], tint: Pal.ink2),
      ]);
    }).then((_) {
      if (pauseIt && mounted) setState(() => paused = false);
    });
  }

  // ---------- Sảnh chờ online ----------
  Widget codeTiles(String code) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final ch in code.split(''))
          Container(
            width: 56,
            height: 66,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 5))],
            ),
            child: Text(ch, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Pal.ink)),
          ),
      ]);

  Widget _stageStatus(bool ok, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withAlpha(24), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withAlpha(40))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ok
              ? const Text('✅', style: TextStyle(fontSize: 18))
              : const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget lobbyScreen() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Tag(race ? '🏁 PHÒNG THI ĐẤU' : '🤝 PHÒNG HỢP TÁC', color: Pal.gold),
            const SizedBox(height: 18),
            Text('${owner.isEmpty ? 'Bạn' : owner} 🤝 ${peerName.isEmpty ? 'người kia' : peerName}',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(race ? 'Hai người thi trong cùng quán của bạn: cùng món, cùng đồ đạc, cùng độ khó' : 'Chơi tại $shopName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            if (!race)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Cả hai cùng thấy bếp và sảnh\nAi cũng nấu và phục vụ được',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.4)),
              ),
            const SizedBox(height: 18),
            _stageStatus(
              guestJoined && !peerLost,
              !guestJoined
                  ? 'Đang chờ ${peerName.isEmpty ? 'người kia' : peerName} vào phòng…'
                  : (peerLost ? 'Mất kết nối với ${peerName.isEmpty ? 'người kia' : peerName}…' : '${peerName.isEmpty ? 'Người kia' : peerName} đã vào phòng!'),
            ),
            if (netStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(netStatus, style: const TextStyle(color: Colors.white38, fontSize: 12))),
            const SizedBox(height: 20),
            GButton('Bắt đầu ngày $day', emoji: '▶', onTap: guestJoined && !peerLost ? startDay : null),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              SoftButton('Cửa hàng', emoji: '🛍️', tint: Colors.white, onTap: () => setState(() => screen = 'shop')),
              SoftButton('Đóng phòng', emoji: '🚪', tint: Colors.white, onTap: () => leaveRoom()),
            ]),
          ]),
        ),
      );

  Widget waitScreen() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Tag(race ? '🏁 THI ĐẤU' : '🤝 HỢP TÁC', color: Pal.gold),
            const SizedBox(height: 14),
            Text('Đã vào phòng${hostOwner.isEmpty ? '' : ' của $hostOwner'}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(race ? 'Thi trong quán của ${peerName.isEmpty ? 'chủ phòng' : peerName}: cùng món, cùng đồ, cùng độ khó' : 'Cùng nấu và phục vụ với ${hostOwner.isEmpty ? 'chủ phòng' : hostOwner}', style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 18),
            _stageStatus(false, race ? 'Chờ chủ phòng bắt đầu… trong lúc chờ có thể mua sắm cho quán của bạn' : 'Chờ chủ phòng bắt đầu ngày mới…'),
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              if (race) SoftButton('Cửa hàng', emoji: '🛍️', tint: Colors.white, onTap: () => setState(() => screen = 'shop')),
              SoftButton('Rời phòng', emoji: '🚪', tint: Colors.white, onTap: () => leaveRoom()),
            ]),
          ]),
        ),
      );

  // --- Màn chơi ---
  Widget _hudIcon(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 5),
        child: Material(
          color: Colors.white.withAlpha(30),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Sound.sfx('tap');
              onTap();
            },
            child: SizedBox(width: 34, height: 34, child: Icon(icon, color: Colors.white, size: 19)),
          ),
        ),
      );

  Widget hud(String role) {
    final frac = (earned / goal).clamp(0.0, 1.0).toDouble();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Pal.ink, Pal.ink2])),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // vòng tiến độ mục tiêu ngày
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: frac, strokeWidth: 4, color: frac >= 1 ? Pal.mint2 : Pal.gold, backgroundColor: Colors.white24),
              Text(frac >= 1 ? '🎯' : '${(frac * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(role, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Wrap(spacing: 5, runSpacing: 3, children: [
                StatPill('💰', '$money'),
                StatPill('⏱', '${max(0, timeLeft).ceil()}s', color: timeLeft < 15 ? Pal.danger : null),
                StatPill('🎯', '$earned/$goal', color: earned >= goal ? Pal.mint : null),
                if (race) StatPill('🍽️', '$served', color: Pal.sky),
                StatPill('📈', Crowd.fmt(crowdMul), color: crowdMul > 1.05 ? Pal.mint : (crowdMul < 0.95 ? Pal.danger : null)),
                if (outsideQ.isNotEmpty) StatPill('🚶', '${outsideQ.length}', color: outsideQ.any((g) => g.frac < 0.35) ? Pal.danger : Pal.gold),
              ]),
            ]),
          ),
          _hudIcon(Icons.menu_book_rounded, showGuide),
          _hudIcon(Sound.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, () {
            setState(() => Sound.setEnabled(!Sound.enabled));
            save();
          }),
          _hudIcon(Icons.close_rounded, confirmExit),
        ]),
        SizedBox(
          height: 18,
          child: AnimatedOpacity(
            opacity: msgT > 0 ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(msg, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.gold, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }

  /// Thanh điểm của đối thủ (thi đấu)
  Widget oppBar() {
    final lead = raceDiff;
    final st = peerLost ? 'mất kết nối' : (oppScr == 'end' ? 'đã xong ngày' : 'đang chơi');
    return Container(
      width: double.infinity,
      color: lead > 0 ? Colors.green.shade700 : (lead < 0 ? Colors.red.shade700 : Colors.blueGrey.shade700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        '🏅 Bạn $score điểm  🆚  ${oppOwner.isEmpty ? 'Đối thủ' : oppOwner} $oppScore điểm ($st)   ${lead > 0 ? '👑 Dẫn trước' : (lead < 0 ? '😬 Đang thua' : '🤝 Hoà')}',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget playScreen() {
    // 1 máy hoặc thi đấu: một người lo cả bếp lẫn sảnh.
    // Bếp ở trên, sảnh ở dưới, cùng một hướng nhìn: ô "Quầy ra món" của sảnh nằm sát bếp.
    // Mọi chế độ (1 máy, hợp tác, thi đấu): bếp ở trên, sảnh ở dưới.
    // Hợp tác 2 máy: cả hai cùng thấy và cùng làm được mọi việc.
    final Widget col = Column(children: [
      hud(race ? '🏁 THI ĐẤU' : (mode == 'local' ? '🍽️ $chefName & $waiterName' : '🤝 $chefName & $waiterName')),
      if (race) oppBar(),
      ticketRail(compact: true),
      recipeBar(),
      cookBar(),
      // bếp + sảnh chung một căn phòng nhìn nghiêng
      Expanded(child: isoRoom()),
      toolBar(null),
      ingredientShelf(compact: true),
    ]);
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
            outside: outsideQ,
            tool: tool,
            onTable: doTable,
            onDish: onDish,
            onIncident: doIncident,
            onPet: doPet,
          ),
        ),
      ]);

  // --- Đầu bếp ---
  String ingEmoji(String id) => shelfNow.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '❓', '?')).emoji;

  Widget kitchenScene({bool island = false}) => KitchenScene(
        stations: stations,
        activeStation: myStation,
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
        island: island,
      );

  /// Màn chơi 2.5D: bếp và sảnh chung một căn phòng (mỗi quán một sơ đồ riêng)
  Widget isoRoom() => IsoRoom(
        tables: tables,
        stations: stations,
        counter: counter,
        selDishId: selDishId,
        activeStation: myStation,
        hasOrders: queue.isNotEmpty,
        venueId: venueId,
        style: styleNow,
        light: lightNow,
        waiterLook: castLook(waiterName, 'waiter'),
        chefLook: castLook(chefName, 'chef'),
        waiterName: waiterName,
        chefName: chefName,
        tablePos: tablePosNow,
        decos: decosNow,
        pets: petsNow,
        incidents: incidents,
        outside: outsideQ,
        tool: tool,
        burnTime: burnTime,
        onTable: doTable,
        onDish: onDish,
        onStation: doStation,
        onHeat: doHeat,
        onIncident: doIncident,
        onPet: doPet,
        buffet: buffet,
        trays: [for (var k = 0; k < trayIds.length; k++) (trayIds[k], trayQty[k])],
        chef2Look: castLook(waiterName, 'chef'),
      );

  /// Thanh chỉnh lửa + độ nêm của bếp đang chọn (chỉ hiện khi đang nấu)
  Widget cookBar() {
    var i = myStation;
    if (i < 0 || i >= stations.length || !stations[i].cooking) {
      i = stations.indexWhere((s) => s.cooking);
    }
    if (i < 0) return const SizedBox.shrink();
    final s = stations[i];
    final rid = s.t?.recipe.id;
    const maxSalt = 5.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: const BoxDecoration(color: Pal.surface, border: Border(bottom: BorderSide(color: Pal.line))),
      child: Row(children: [
        Text('Bếp ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Pal.text)),
        const SizedBox(width: 6),
        _roundBtn('−', Pal.sky, () => doHeat(i, -0.2), size: 30),
        const SizedBox(width: 4),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.heat < 0.3 ? '🧊 Lửa nhỏ' : (s.heat <= 0.75 ? '🔥 Lửa vừa' : '🌋 Lửa to!'),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: s.heat > 0.75 ? Pal.danger : Pal.text)),
            _gauge(s.heat, 0.3, 0.75, marker: s.heat > 0.75 ? Pal.danger : Pal.ink),
          ]),
        ),
        const SizedBox(width: 4),
        _roundBtn('+', Pal.coral, () => doHeat(i, 0.2), size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${seasonEmojiFor(rid, venueId)} ${seasonNameFor(rid, venueId)}: ${s.taste == 'Vừa' ? 'vừa miệng' : (s.taste == 'Nhạt' ? 'còn nhạt' : 'quá tay')}',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Pal.text)),
            _gauge(s.salt / maxSalt, (s.saltTarget - s.tol) / maxSalt, (s.saltTarget + s.tol) / maxSalt),
          ]),
        ),
      ]),
    );
  }

  Widget kitchenBody({bool compact = false, bool tools = true}) => Column(children: [
        ticketRail(compact: compact),
        recipeBar(),
        if (tools) toolBar(true),
        Expanded(child: kitchenScene()),
        ingredientShelf(compact: compact),
      ]);

  /// Thanh công thức: món của bếp đang chọn hiện thật to (hình món, tên món, bàn,
  /// từng nguyên liệu kèm tên). Các bếp khác đang nấu hiện thành nút nhỏ bên phải để đổi.
  Widget recipeBar() {
    final busy = [for (var i = 0; i < stations.length; i++) if (stations[i].t != null) i];
    final focus = busy.contains(myStation) ? myStation : (busy.isEmpty ? -1 : busy.first);
    return Container(
      height: busy.isEmpty ? 44 : 86,
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFFFFF7E8), border: Border(bottom: BorderSide(color: Pal.line))),
      child: busy.isEmpty
          ? Center(
              child: Text(queue.isEmpty ? '📖 Công thức món sẽ hiện ở đây khi có order' : '👆 Chạm vào bếp để nhận order, công thức sẽ hiện ở đây',
                  style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w700, fontSize: 13)),
            )
          : Row(children: [
              Expanded(child: _recipeGroup(focus)),
              if (busy.length > 1)
                Container(
                  padding: const EdgeInsets.only(right: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final i in busy)
                        if (i != focus) _miniStation(i),
                    ]),
                  ),
                ),
            ]),
    );
  }

  /// Nút nhỏ của một bếp khác đang nấu: chạm để xem công thức của bếp đó
  Widget _miniStation(int i) {
    final s = stations[i];
    return GestureDetector(
      onTap: () => setState(() {
        if (remote) {
          guestStation = i;
        } else {
          activeStation = i;
        }
      }),
      child: Container(
        width: 50,
        margin: const EdgeInsets.only(left: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          DishIcon(s.t!.recipe.id, size: 36, burnt: s.burnt),
          Text(s.done ? (s.burnt ? '🔥' : '✅') : (s.t!.table < 0 ? '🍱' : 'B${s.t!.table + 1}'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Pal.muted, height: 1.1)),
        ]),
      ),
    );
  }

  Widget _recipeGroup(int i) {
    final s = stations[i];
    final r = s.t!.recipe;
    Widget chip(String id) {
      final got = s.added.contains(id);
      final onBoard = s.board.contains(id);
      final ing = shelfNow.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '❓', '?'));
      return GestureDetector(
        onTap: got || s.cooking || s.done ? null : () => doIngredient(id, i),
        child: Container(
          width: 54,
          margin: const EdgeInsets.only(left: 5),
          padding: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: got ? const Color(0xFFDDF6EF) : (onBoard ? const Color(0xFFFFF0C2) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: got ? Pal.mint : (onBoard ? Pal.gold : Pal.line), width: 2),
          ),
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Opacity(opacity: got ? 0.45 : 1, child: Text(ing.emoji, style: const TextStyle(fontSize: 32, height: 1.1))),
              Text(ing.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Pal.text, height: 1.1)),
            ]),
            if (got) const Positioned(right: -6, top: -6, child: Text('✅', style: TextStyle(fontSize: 14))),
            if (onBoard) const Positioned(right: -6, top: -6, child: Text('🔪', style: TextStyle(fontSize: 14))),
          ]),
        ),
      );
    }

    return GestureDetector(
      onTap: () => doStation(i),
      child: Container(
        margin: const EdgeInsets.fromLTRB(6, 5, 2, 5),
        padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F0FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Pal.sky, width: 2),
        ),
        child: Row(children: [
          DishIcon(r.id, size: 56, burnt: s.burnt),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Pal.text, height: 1.1)),
              Text(tableLabel(s.t!.table), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Pal.muted)),
            ]),
          ),
          Expanded(
            child: s.done
                ? Center(
                    child: Text(s.burnt ? '🔥 Cháy rồi! Chạm đưa ra quầy' : '✅ Chín rồi! Chạm đưa ra quầy',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: s.burnt ? Pal.danger : Pal.mint)),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final id in r.ings) chip(id),
                      if (s.cooking) const Padding(padding: EdgeInsets.only(left: 8), child: Text('🔥 Đang nấu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Pal.coral))),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  /// Một thanh duy nhất ở trên cùng: các order đang chờ + thành phần món của bếp đang nấu.
  /// Chưa có gì thì chỉ hiện một dòng nhắc.
  Widget orderBar() {
    final hasActive = activeStation >= 0 && activeStation < stations.length && stations[activeStation].t != null;
    if (queue.isEmpty) return stationPanel();
    return Container(
      decoration: const BoxDecoration(color: Pal.surface, border: Border(bottom: BorderSide(color: Pal.line, width: 1.5))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 62,
          color: const Color(0xFFFFF7E8),
          padding: const EdgeInsets.only(left: 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: Pal.coral, borderRadius: BorderRadius.circular(12)),
              child: Text('📋 ${queue.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            Expanded(
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4), children: [
                for (final tk in queue) _ticketCard(tk),
              ]),
            ),
          ]),
        ),
        stationPanel(top: hasActive),
      ]),
    );
  }

  // ---------- Bảng thao tác bếp: biểu tượng lớn, dễ bấm ----------
  Widget _gauge(double value, double z0, double z1, {Color marker = Pal.ink}) => LayoutBuilder(builder: (ctx, cons) {
        final w = cons.maxWidth;
        return SizedBox(
          height: 16,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: 0, right: 0, top: 4, height: 8, child: Container(decoration: BoxDecoration(color: const Color(0xFFECE6DD), borderRadius: BorderRadius.circular(4)))),
            Positioned(
              left: w * z0.clamp(0.0, 1.0),
              width: max(4.0, w * (z1 - z0).clamp(0.0, 1.0)),
              top: 4,
              height: 8,
              child: Container(decoration: BoxDecoration(color: Pal.mint2, borderRadius: BorderRadius.circular(4))),
            ),
            Positioned(
              left: (w * value.clamp(0.0, 1.0)) - 3,
              top: 0,
              width: 6,
              height: 16,
              child: Container(decoration: BoxDecoration(color: marker, borderRadius: BorderRadius.circular(3))),
            ),
          ]),
        );
      });

  Widget _roundBtn(String label, Color col, VoidCallback onTap, {double size = 40}) => Material(
        color: col,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: Text(label, style: TextStyle(color: Colors.white, fontSize: size * 0.55, fontWeight: FontWeight.w900, height: 1))),
          ),
        ),
      );

  Widget _ingSlot(Station s, int si, String id) {
    final got = s.added.contains(id);
    final onBoard = s.board.contains(id);
    final cut = shelfNow.firstWhere((e) => e.id == id, orElse: () => const Ing('?', '❓', '?')).cut;
    return GestureDetector(
      onTap: got ? null : () => doIngredient(id, si),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: got ? const Color(0xFFDDF6EF) : (onBoard ? const Color(0xFFFFF0C2) : Pal.surface),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: got ? Pal.mint : (onBoard ? Pal.gold : Pal.line), width: 2),
        ),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Opacity(opacity: got ? 0.45 : 1, child: Text(ingEmoji(id), style: const TextStyle(fontSize: 26))),
          if (got) const Positioned(right: -4, top: -6, child: Text('✅', style: TextStyle(fontSize: 14))),
          if (!got && cut > 0) Positioned(right: -4, top: -6, child: Text(onBoard ? '🔪' : '🔪$cut', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
        ]),
      ),
    );
  }

  Widget stationPanel({bool top = true}) {
    final i = activeStation;
    Widget box(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const BoxDecoration(color: Pal.surface, border: Border(bottom: BorderSide(color: Pal.line, width: 1.5))),
          child: child,
        );
    if (i < 0 || i >= stations.length || stations[i].t == null) {
      return box(SizedBox(
        height: queue.isEmpty ? 40 : 30,
        child: Row(children: [
          Text(queue.isEmpty ? '💤' : '👆', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              queue.isNotEmpty ? 'Chạm vào một bếp trống để nhận order' : 'Chưa có order nào, chờ phục vụ ghi món…',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.text),
            ),
          ),
        ]),
      ));
    }
    final s = stations[i];
    final tk = s.t!;
    final r = tk.recipe;
    Widget main;
    if (s.done) {
      main = Row(children: [
        Expanded(
          child: Text(s.burnt ? 'Món bị cháy… vẫn phải mang ra 😣' : 'Món đã chín! Mang ra quầy kẻo nguội ✨',
              style: TextStyle(fontWeight: FontWeight.w800, color: s.burnt ? Pal.danger : Pal.text)),
        ),
        const SizedBox(width: 8),
        GButton('Ra quầy', emoji: '🛎️', height: 46, expand: false, onTap: () => doStation(i), colors: s.burnt ? const [Pal.danger, Color(0xFFFF8A80)] : const [Pal.mint, Pal.mint2]),
      ]);
    } else if (s.cooking) {
      final hz = s.heat < 0.3 ? '🧊 Lửa nhỏ' : (s.heat <= 0.75 ? '🔥 Lửa vừa' : '🌋 Lửa to!');
      main = Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Đang nấu • còn ${max(0.0, s.need - s.prog).ceil()}s', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(value: s.need <= 0 ? 0 : (s.prog / s.need).clamp(0.0, 1.0), minHeight: 9, color: Pal.coral, backgroundColor: const Color(0xFFFBE3D9)),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        _roundBtn('−', Pal.sky, () => doHeat(i, -0.2)),
        const SizedBox(width: 6),
        SizedBox(
          width: 64,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(hz, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Pal.text)),
            _gauge(s.heat, 0.3, 0.75, marker: s.heat > 0.75 ? Pal.danger : Pal.ink),
          ]),
        ),
        const SizedBox(width: 6),
        _roundBtn('+', Pal.coral, () => doHeat(i, 0.2)),
      ]);
    } else {
      main = Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final id in r.ings) Padding(padding: const EdgeInsets.only(right: 6, top: 6), child: _ingSlot(s, i, id)),
            ]),
          ),
        ),
        if (s.chopping) ...[
          const SizedBox(width: 8),
          GButton('Thái ×${s.chopLeft}', emoji: '🔪', height: 46, expand: false, onTap: () => doStation(i), colors: const [Color(0xFFFFB020), Pal.gold]),
        ],
      ]);
    }
    final sweet = isSweet(r.id);
    final taste = s.taste == 'Vừa' ? '😋 Vừa' : (s.taste == 'Nhạt' ? '😐 Nhạt' : (sweet ? '😖 Ngọt gắt' : '😖 Mặn'));
    return box(Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          DishIcon(r.id, size: 54, burnt: s.burnt),
          Text(tableLabel(tk.table), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Pal.muted)),
        ]),
        const SizedBox(width: 8),
        Expanded(child: SizedBox(height: 52, child: Align(alignment: Alignment.centerLeft, child: main))),
      ]),
      if (!s.done) ...[
        const SizedBox(height: 6),
        Row(children: [
          GestureDetector(
            onTap: () => doIngredient('salt', i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFE7F1FF), borderRadius: BorderRadius.circular(12)),
              child: Text('${seasonEmojiFor(r.id, venueId)} Nêm ${seasonNameFor(r.id, venueId).toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.sky)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _gauge(s.salt / 5, (s.saltTarget - s.tol) / 5, (s.saltTarget + s.tol) / 5)),
          const SizedBox(width: 10),
          SizedBox(width: 78, child: Text(taste, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: s.taste == 'Vừa' ? Pal.mint : Pal.coral))),
        ]),
      ],
    ]));
  }

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
        height: compact ? 60 : 68,
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
    final c = tk.table >= 0 && tk.table < tables.length ? tables[tk.table].c : null;
    final frac = c == null ? 0.0 : (c.pat / c.maxPat).clamp(0.0, 1.0);
    return Transform.rotate(
      angle: ((tk.id % 3) - 1) * 0.04,
      child: Container(
        width: 60,
        margin: const EdgeInsets.fromLTRB(3, 3, 3, 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Pal.line),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          DishIcon(tk.recipe.id, size: 26),
          Text(tableLabel(tk.table), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
      for (final ing in shelfNow) _shelfItem(ing.id, ing.emoji, ing.cut > 0 ? '${ing.name} 🔪' : ing.name, compact),
      _shelfItem('salt', seasonEmojiFor(focusRecipeId, venueId), seasonNameFor(focusRecipeId, venueId), compact, special: true),
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
        padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Pal.ink, Pal.ink2]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        ),
        child: Row(children: [
          RoundIcon(Icons.arrow_back_rounded, onTap: onBackTap, tip: 'Quay lại'),
          const SizedBox(width: 10),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
          StatPill('💰', '$money'),
        ]),
      );

  // ---------- Chọn chủ quán ----------
  Widget profileScreen() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text('🍽️ Nhà Hàng Đôi', style: TextStyle(color: Pal.gold, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
            const SizedBox(height: 8),
            const Text('Máy này là của ai?', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text(
              'Mỗi người có một nhà hàng riêng: tiền, nâng cấp, thú cưng và cách bố trí đều lưu riêng.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _ownerCard(kNguyen, nguyenLook, 'chef')),
              const SizedBox(width: 14),
              Expanded(child: _ownerCard(kNgocAnh, ngocAnhLook, 'waiter')),
            ]),
            const SizedBox(height: 18),
            if (owner.isNotEmpty) SoftButton('Quay lại', emoji: '⬅', tint: Colors.white, onTap: () => setState(() => screen = 'menu')),
          ]),
        ),
      );

  Widget _ownerCard(String name, Look look, String role) {
    final sel = owner == name;
    final na = name == kNgocAnh;
    return GestureDetector(
      onTap: () {
        Sound.sfx('tap');
        chooseOwner(name);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: na ? const [Color(0xFFFFE1EC), Colors.white] : const [Color(0xFFDDEBFF), Colors.white],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: sel ? Pal.gold : Colors.transparent, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 8))],
        ),
        child: Column(children: [
          PersonAvatar(look: look, role: role, height: 160),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Pal.text)),
          const SizedBox(height: 2),
          Text('Nhà hàng của $name', textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted, fontSize: 12.5)),
          if (sel) const Padding(padding: EdgeInsets.only(top: 8), child: Tag('Đang chọn', color: Pal.coral)),
        ]),
      ),
    );
  }

  // ---------- Quán của tôi: bố trí + thú cưng ----------
  Widget homeTabs() => DefaultTabController(
        length: 2,
        child: Column(children: [
          const PillTabs(['🛠️ Bố trí quán', '🐾 Thú cưng']),
          Expanded(
            child: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [layoutPane(), petsPane()]),
          ),
        ]),
      );

  Widget petsPane() => ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            'Từ 40♥ trở lên thú cưng mới giúp quán. Mỗi ngày trôi qua giảm 20♥. Trong lúc chơi, chạm vào thú cưng để vuốt ve.',
            style: TextStyle(color: Pal.muted, fontSize: 12.5, height: 1.4),
          ),
        ),
        for (final p in petTypes) _petCard(p),
      ]);

  Widget _petCard(PetType p) {
    final has = pets.contains(p.id);
    final hp = petHappy[p.id] ?? 0;
    final voice = p.id == 'dog' ? 'woof' : (p.id == 'parrot' ? 'chirp' : (p.id == 'hamster' ? 'squeak' : 'purr'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EmojiTile(p.emoji, tint: Pal.berry, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Pal.text))),
                if (!has) PriceButton(p.cost, afford: money >= p.cost, onTap: () {
                  if (pay(p.cost)) {
                    Sound.sfx(voice);
                    setState(() {
                      pets.add(p.id);
                      petHappy[p.id] = 80;
                    });
                    save();
                  }
                }),
              ]),
              const SizedBox(height: 2),
              Text(p.perk, style: const TextStyle(color: Pal.muted, fontSize: 12.5, height: 1.3)),
              if (has) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Text(hp >= 40 ? '💖' : '💔', style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: hp / 100, minHeight: 10, color: hp >= 40 ? Pal.berry : Pal.muted, backgroundColor: const Color(0xFFFBE3EC)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$hp♥', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  SoftButton('Vuốt ve', emoji: '🤚', tint: Pal.berry, onTap: () {
                    Sound.sfx(voice);
                    setState(() => petHappy[p.id] = hp >= 60 ? hp : min(60, hp + 8));
                    save();
                  }),
                  SoftButton('Cho ăn • 5💰', emoji: '🍖', tint: Pal.coral, onTap: () {
                    if (pay(5)) {
                      Sound.sfx('coin');
                      setState(() => petHappy[p.id] = min(100, hp + 30));
                      save();
                    }
                  }),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget layoutPane() {
    final n = min(4 + lvl('tables'), venue.maxTables);
    return Column(children: [
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(14, 6, 14, 4), children: [
          for (final lm in lightModes)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(lm[1]),
                selected: light == lm[0],
                showCheckmark: false,
                onSelected: (_) {
                  Sound.sfx('tap');
                  setState(() => light = lm[0]);
                  save();
                },
              ),
            ),
        ]),
      ),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
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
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
        child: Row(children: [
          Expanded(child: Text('${decos.length} đồ trang trí • kéo để di chuyển, nhấn giữ để cất', style: const TextStyle(fontSize: 12, color: Pal.muted))),
          TextButton(
            onPressed: () {
              setState(() => tablePos = List<Offset?>.filled(12, null));
              save();
            },
            child: const Text('↺ Xếp lại bàn', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    ]);
  }

  // ---------- Kết thúc ngày ----------
  Widget raceResult() {
    if (oppScr != 'end') {
      return _stageStatus(false, 'Đang chờ hàng xóm phục vụ nốt khách…');
    }
    final diff = raceDiff;
    final title = diff > 0 ? '🏆 Bạn thắng!' : (diff < 0 ? '😢 ${oppOwner.isEmpty ? 'Đối thủ' : oppOwner} thắng' : '🤝 Hoà!');
    Widget col(String who, int sc, int sv, int ss, int ls, int ea, bool lead) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: lead ? const Color(0xFFFFF4D6) : Pal.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: lead ? Pal.gold : Pal.line, width: lead ? 2 : 1),
            ),
            child: Column(children: [
              Text(who, style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
              const SizedBox(height: 4),
              Text('🏅 $sc điểm', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Pal.text)),
              const SizedBox(height: 4),
              Text('🍽️ $sv khách • ⭐ $ss sao', style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
              Text('😠 $ls bỏ về (−${ls * 2})', style: TextStyle(color: ls > 0 ? Pal.danger : Pal.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
              Text('💰 $ea', style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
          ),
        );
    return AppCard(
      child: Column(children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Pal.text)),
        const SizedBox(height: 10),
        Row(children: [
          col(owner.isEmpty ? 'Bạn' : owner, score, served, starSum, lost, earned, diff > 0),
          const SizedBox(width: 10),
          col(oppOwner.isEmpty ? 'Đối thủ' : oppOwner, oppScore, oppServed, oppStars, oppLost, oppEarned, diff < 0),
        ]),
        const SizedBox(height: 8),
        const Text('Điểm = tổng số sao khách chấm − 2 điểm mỗi khách bỏ về', style: TextStyle(color: Pal.muted, fontSize: 11.5)),
      ]),
    );
  }

  Widget _statTile(String emoji, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(color: Colors.white.withAlpha(22), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withAlpha(35))),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget endScreen() {
    final avg = starsLog.isEmpty ? 0.0 : starsLog.reduce((a, b) => a + b) / starsLog.length;
    final prevGoal = endGoal > 0 ? endGoal : goalFor(day - 1); // mục tiêu của ngày vừa chơi
    final reached = earned >= prevGoal;
    final isGuest = mode == 'guest';
    final bk = _bk;
    final raceDone = hasOpp && oppScr == 'end';
    // Thắng: thi đấu thì phải hơn hàng xóm, còn lại là đạt mục tiêu ngày
    final win = raceDone ? raceDiff > 0 : !hasOpp && reached;
    final sad = raceDone ? raceDiff < 0 : !hasOpp && !reached;
    final waitOpp = hasOpp && oppScr == 'play' && !peerLost;
    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(children: [
          Tag('HẾT NGÀY ${day - 1}', color: Pal.gold),
          if (win || sad)
            DancingCouple(
              happy: win,
              left: castLook(chefName, 'chef'),
              right: castLook(waiterName, 'waiter'),
              leftName: chefName,
              rightName: waiterName,
              height: 170,
            ),
          Text(reached ? 'Đạt mục tiêu! +50💰 thưởng' : 'Chưa đạt mục tiêu',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (race) ...[raceResult(), const SizedBox(height: 14)],
          Row(children: [
            _statTile('💰', '$earned', 'Thu nhập / $prevGoal'),
            const SizedBox(width: 8),
            _statTile('🍽️', '$served', 'Đã phục vụ'),
            const SizedBox(width: 8),
            _statTile('🚶', '$lost', 'Bỏ về'),
            const SizedBox(width: 8),
            _statTile('⭐', avg.toStringAsFixed(1), 'Đánh giá'),
          ]),
          const SizedBox(height: 12),
          Text(
            remote && bk != null ? 'Quán của bạn cũng nhận +$earned💰 • tổng ${bk[0]}💰' : 'Tổng tiền quán: $money💰 • đã lưu',
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          if (isGuest)
            _stageStatus(false, 'Chờ chủ phòng bắt đầu ngày tiếp theo…')
          else
            GButton(waitOpp ? 'Chờ hàng xóm xong ngày' : 'Ngày tiếp theo', emoji: waitOpp ? '⏳' : '▶', onTap: waitOpp ? null : startDay),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
            if (!isGuest || race)
              SoftButton('Cửa hàng', emoji: '🛍️', tint: Colors.white, onTap: () {
                if (mode == 'local') {
                  setState(() {
                    screen = 'menu';
                    hubTab = 'shop';
                  });
                } else {
                  setState(() => screen = 'shop');
                }
              }),
            SoftButton(mode == 'local' ? 'Về bản đồ' : 'Rời phòng', emoji: mode == 'local' ? '🗺️' : '🚪', tint: Colors.white, onTap: () {
              if (mode == 'local') {
                setState(() {
                  screen = 'menu';
                  hubTab = 'map';
                });
              } else {
                leaveRoom();
              }
            }),
          ]),
        ]),
      ),
    );
    if (!win) return content;
    return Stack(children: [content, const Positioned.fill(child: ConfettiLayer())]);
  }

  // ---------- Cửa hàng ----------
  Widget shopScreen() => Column(children: [
        _topBar('🛍️ Cửa hàng', () => setState(() => screen = shopBack)),
        Expanded(child: shopTabs()),
      ]);

  Widget _list(List<Widget> items, {String? note}) => ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12), children: [
        if (note != null) Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 10), child: Text(note, style: const TextStyle(color: Pal.muted, fontSize: 12.5))),
        ...items,
      ]);

  Widget shopTabs() => DefaultTabController(
        length: 4,
        child: Column(children: [
          const PillTabs(['🔧 Nâng cấp', '📖 Món ăn', '🪴 Trang trí', '🎨 Hoạt cảnh']),
          Expanded(
            child: TabBarView(children: [
              _list([
                for (final u in upgrades)
                  ShopRow(
                    emoji: u.emoji,
                    title: u.name,
                    sub: '${u.desc}\nCấp ${lvl(u.id)}/${u.max}',
                    trailing: lvl(u.id) >= u.max
                        ? const Tag('TỐI ĐA')
                        : PriceButton(u.cost(lvl(u.id)), afford: money >= u.cost(lvl(u.id)), onTap: () {
                            if (pay(u.cost(lvl(u.id)))) {
                              Sound.sfx('coin');
                              lv[u.id] = lvl(u.id) + 1;
                              save();
                              setState(() {});
                            }
                          }),
                  ),
              ]),
              _list(note: 'Món của ${venue.emoji} ${venue.name}. Đổi quán trên bản đồ để xem món của quán khác.', [
                for (final r in venue.recipes)
                  ShopRow(
                    emoji: r.emoji,
                    leading: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(color: const Color(0xFFFFF1E2), borderRadius: BorderRadius.circular(18)),
                      child: DishIcon(r.id, size: 60),
                    ),
                    title: r.name,
                    tint: Pal.mint,
                    sub: '${r.ings.map(ingEmoji).join(' ')}  •  ⏱ ${r.cook}s  •  bán ${r.price}💰',
                    trailing: recipes.contains(r.id)
                        ? const Tag('✓ Đã có')
                        : PriceButton(r.unlock, afford: money >= r.unlock, onTap: () {
                            if (pay(r.unlock)) {
                              Sound.sfx('coin');
                              recipes.add(r.id);
                              save();
                              setState(() {});
                            }
                          }),
                  ),
                for (final r in gardenRecipes)
                  ShopRow(
                    emoji: r.emoji,
                    leading: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(color: const Color(0xFFEAF7E4), borderRadius: BorderRadius.circular(18)),
                      child: DishIcon(r.id, size: 60),
                    ),
                    title: r.name,
                    tint: Pal.mint,
                    sub: '🌻 Món từ vườn • bán ${r.price}💰 ở mọi quán',
                    trailing: gardenMenu.contains(r) ? const Tag('✓ Đã có') : const Tag('🌻 Thu hoạch', color: Pal.gold),
                  ),
              ]),
              _list(note: 'Mua xong vào 🏡 Quán tôi → Bố trí để kéo thả. Mỗi món giúp khách chờ lâu hơn.', [
                for (final dt in decoTypes)
                  ShopRow(
                    emoji: dt.emoji,
                    leading: DecoPreview(type: dt.id, size: 64),
                    title: dt.name,
                    tint: Pal.gold,
                    sub: '${dt.wall ? 'Treo tường' : 'Đặt trên sàn'} • đang có ${decos.where((d) => d.type == dt.id).length}',
                    trailing: PriceButton(dt.cost, afford: money >= dt.cost, onTap: () {
                      if (pay(dt.cost)) {
                        Sound.sfx('coin');
                        decos.add(Deco(dt.id, 0.15 + rnd.nextDouble() * 0.7, dt.wall ? 0 : 0.2 + rnd.nextDouble() * 0.6));
                        save();
                        setState(() {});
                        snack('Đã mua ${dt.name}! Vào 🏡 Quán tôi để sắp xếp.');
                      }
                    }),
                  ),
              ]),
              _list([
                for (final st in sceneStyles)
                  ShopRow(
                    emoji: st.emoji,
                    title: st.name,
                    tint: Pal.sky,
                    sub: '${st.desc}. Có nhạc nền riêng.',
                    highlight: st.id == style,
                    trailing: styles.contains(st.id)
                        ? (st.id == style
                            ? const Tag('Đang dùng', color: Pal.coral)
                            : SoftButton('Chọn', tint: Pal.sky, onTap: () {
                                style = st.id;
                                save();
                                setState(() {});
                              }))
                        : PriceButton(st.cost, afford: money >= st.cost, onTap: () {
                            if (pay(st.cost)) {
                              Sound.sfx('coin');
                              styles.add(st.id);
                              style = st.id;
                              save();
                              setState(() {});
                            }
                          }),
                  ),
              ]),
            ]),
          ),
        ]),
      );
}
