// Lưu & đồng bộ khu vườn chung qua bảng Supabase `garden_events`.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'data.dart';
import 'garden_engine.dart';

const kGardenId = 'nguyen-ngocanh';

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

  /// Nhà hàng riêng mà [own] đã mở (loại quán, hạng) – lấy từ sự kiện chung
  (String, int)? sigOf(String own) {
    GEvent? last;
    for (final e in events) {
      if (e.a == 'sig' && e.d['own'] == own && (last == null || e.at >= last.at)) last = e;
    }
    if (last == null) return null;
    return (last.d['v'].toString(), (last.d['r'] as num?)?.toInt() ?? 1);
  }

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
    if (schedule) _scheduled = true;
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
