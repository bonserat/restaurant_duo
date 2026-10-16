// Lưu & đồng bộ khu vườn chung qua bảng Supabase `garden_events`,
// và hẹn giờ thông báo trên điện thoại khi vườn cần chăm sóc.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'config.dart';
import 'data.dart';
import 'garden_engine.dart';

const kGardenId = 'nguyen-ngocanh';
const kGardenTitle = '🌻 Vườn của Nguyên & Ngọc Anh';

class GardenNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(const InitializationSettings(
        iOS: ios,
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('notif init: $e');
    }
  }

  /// Huỷ hết lịch cũ và hẹn lại danh sách mới (thời điểm, nội dung)
  static Future<void> scheduleAll(List<(DateTime, String)> list) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      var id = 100;
      for (final (when, body) in list) {
        if (when.isBefore(DateTime.now().add(const Duration(seconds: 30)))) continue;
        await _plugin.zonedSchedule(
          id++,
          kGardenTitle,
          body,
          tz.TZDateTime.from(when.toUtc(), tz.UTC),
          const NotificationDetails(
            iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: false),
            android: AndroidNotificationDetails('garden', 'Khu vườn', importance: Importance.high, priority: Priority.high),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('notif schedule: $e');
    }
  }
}

class Garden extends ChangeNotifier {
  static final instance = Garden();

  List<GEvent> _server = [];
  List<GEvent> _pending = [];
  int _lastId = 0;
  GState state = GState();
  String error = '';
  bool syncing = false;
  DateTime? lastSync;
  String who = '';
  Timer? _poll, _tick;
  bool _started = false;
  AppLifecycleListener? _life;
  final _rnd = Random();

  List<GEvent> get events {
    final keys = _server.map((e) => e.key).toSet();
    return [..._server, ..._pending.where((e) => !keys.contains(e.key))];
  }

  Set<String> get unlocked => state.unlocked;

  Future<void> start(String owner) async {
    who = owner;
    if (_started) return;
    _started = true;
    await _loadCache();
    recompute(schedule: false);
    _life = AppLifecycleListener(onResume: () => sync());
    // cập nhật đồng hồ vườn mỗi phút (nước cạn dần, cây lớn dần…)
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => recompute(schedule: false));
    await sync();
  }

  /// Màn vườn đang mở: hỏi máy chủ thường xuyên để thấy ngay việc người kia làm
  void watch(bool on) {
    _poll?.cancel();
    _poll = on ? Timer.periodic(const Duration(seconds: 6), (_) => sync()) : null;
    if (on) sync();
  }

  SupabaseClient? get _db => kSupabaseUrl.contains('YOUR_') ? null : Supabase.instance.client;
  final Set<String> _sent = {}; // đã gửi lên, chờ thấy lại từ máy chủ
  bool _scheduled = false;

  Future<void> sync() async {
    final db = _db;
    if (db == null) {
      error = 'Chưa cấu hình Supabase nên vườn chỉ lưu trên máy này';
      notifyListeners();
      return;
    }
    if (syncing) return;
    syncing = true;
    try {
      // gửi các thao tác chưa gửi được
      for (final e in [..._pending]) {
        if (_sent.contains(e.key)) continue;
        await db.from('garden_events').insert({'garden': kGardenId, 'at': e.at, 'who': e.who, 'a': e.a, 'd': e.d});
        _sent.add(e.key);
      }
      final rows = await db.from('garden_events').select('id, at, who, a, d').eq('garden', kGardenId).gt('id', _lastId).order('id', ascending: true).limit(1000);
      var changed = false;
      for (final r in rows) {
        final e = GEvent.fromJson(Map<String, dynamic>.from(r));
        _lastId = max(_lastId, e.id);
        if (!_server.any((x) => x.id == e.id)) {
          _server.add(e);
          changed = true;
        }
      }
      // thao tác đã có trên máy chủ thì bỏ khỏi hàng chờ
      final keys = _server.map((x) => x.key).toSet();
      final before = _pending.length;
      _pending.removeWhere((p) => keys.contains(p.key));
      if (_pending.length != before) changed = true;
      error = '';
      lastSync = DateTime.now();
      if (changed) await _saveCache();
      recompute(schedule: changed || !_scheduled);
    } catch (e) {
      final s = e.toString();
      if (s.contains('garden_events') || s.contains('42P01') || s.contains('PGRST205')) {
        error = 'Chưa tạo bảng garden_events trên Supabase (xem hướng dẫn) – tạm lưu trên máy này';
      } else {
        error = 'Mất kết nối – thao tác sẽ được gửi khi có mạng';
      }
      debugPrint('garden sync: $s');
      notifyListeners();
    } finally {
      syncing = false;
    }
  }

  /// Thực hiện 1 thao tác: lưu ngay tại máy rồi gửi lên máy chủ
  Future<void> act(String a, Map<String, dynamic> d) async {
    final k = '${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1 << 30)}';
    final e = GEvent(-1, DateTime.now().millisecondsSinceEpoch, who, a, {...d, 'k': k});
    _pending.add(e);
    await _saveCache();
    recompute();
    await sync();
  }

  /// Nhiều thao tác cùng lúc (ví dụ: tưới hết cả vườn)
  Future<void> actMany(List<(String, Map<String, dynamic>)> list) async {
    if (list.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < list.length; i++) {
      final (a, d) = list[i];
      final k = '${DateTime.now().microsecondsSinceEpoch}-${_rnd.nextInt(1 << 30)}-$i';
      _pending.add(GEvent(-1, now, who, a, {...d, 'k': k}));
    }
    await _saveCache();
    recompute();
    await sync();
  }

  static String newUid() => 'g${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  void recompute({bool schedule = true}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    state = simulate(events, now);
    notifyListeners();
    if (schedule) {
      _scheduled = true;
      _scheduleNotifs(now);
    }
  }

  /// Xem trước 2 ngày tới: lúc nào cây khát, vật đói, sự cố, tới ngày thu hoạch…
  /// rồi hẹn thông báo. Cả 2 máy cùng tính ra một lịch nên cả 2 người đều được báo.
  void _scheduleNotifs(int now) {
    final future = simulate(events, now + 48 * kHour, watchFrom: now);
    final raw = <(DateTime, String)>[];
    for (final a in future.alerts) {
      raw.add((_awake(DateTime.fromMillisecondsSinceEpoch(a.at)), a.text));
    }
    // dự báo thời tiết xấu lúc 7 giờ sáng
    for (var dd = 1; dd <= 2; dd++) {
      final day = DateTime.now().add(Duration(days: dd));
      final at7 = DateTime(day.year, day.month, day.day, 7);
      final w = weatherAt(at7.millisecondsSinceEpoch);
      if ((w.id == 'storm' || w.id == 'hot') && state.items.isNotEmpty) {
        raw.add((at7, '${w.emoji} Hôm nay ${w.name.toLowerCase()}: ${w.effect.toLowerCase()}. Ghé vườn xem nhé!'));
      }
    }
    raw.sort((a, b) => a.$1.compareTo(b.$1));
    // gộp các thông báo gần nhau (trong 45 phút) thành 1
    final out = <(DateTime, String)>[];
    for (final r in raw) {
      if (out.isNotEmpty && r.$1.difference(out.last.$1).inMinutes < 45) {
        final last = out.removeLast();
        out.add((last.$1, '${last.$2}\n${r.$2}'));
      } else {
        out.add(r);
      }
    }
    GardenNotifier.scheduleAll(out.take(30).toList());
  }

  /// Không báo lúc nửa đêm: dời sang 7 giờ sáng
  DateTime _awake(DateTime d) {
    if (d.hour >= 22) return DateTime(d.year, d.month, d.day + 1, 7);
    if (d.hour < 7) return DateTime(d.year, d.month, d.day, 7);
    return d;
  }

  Future<void> _loadCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('garden_cache');
      if (s == null) return;
      final m = jsonDecode(s) as Map<String, dynamic>;
      _server = (m['ev'] as List).map((e) => GEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _pending = (m['pd'] as List).map((e) => GEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      _lastId = (m['last'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'garden_cache',
        jsonEncode({
          'ev': _server.map((e) => e.toJson()).toList(),
          'pd': _pending.map((e) => e.toJson()).toList(),
          'last': _lastId,
        }),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _life?.dispose();
    super.dispose();
  }
}
