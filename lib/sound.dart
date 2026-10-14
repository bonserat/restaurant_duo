// Âm thanh: hiệu ứng (assets/sfx) + nhạc nền theo hoạt cảnh (assets/music).
// Mọi lời gọi đều "an toàn": lỗi âm thanh không bao giờ làm hỏng game.
import 'package:audioplayers/audioplayers.dart';

class Sound {
  static bool enabled = true;
  static double musicVol = 0.35;
  static double sfxVol = 0.85;

  static final AudioPlayer _music = AudioPlayer();
  static final List<AudioPlayer> _pool = List.generate(6, (_) => AudioPlayer());
  static int _next = 0;
  static String? _track;
  static final Map<String, DateTime> _last = {};
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      await _music.setReleaseMode(ReleaseMode.loop);
      for (final p in _pool) {
        await p.setReleaseMode(ReleaseMode.stop);
      }
    } catch (_) {}
  }

  static void _safe(Future<void> Function() f) {
    try {
      f().catchError((_) {});
    } catch (_) {}
  }

  /// Phát một hiệu ứng: door, order, plop, wrong, sizzle, ding, burn, whoosh,
  /// serve, coin, angry, clean, tap, goal, win, lose, firework
  static void sfx(String name, {double vol = 1}) {
    if (!enabled) return;
    final now = DateTime.now();
    final l = _last[name];
    if (l != null && now.difference(l).inMilliseconds < 70) return; // tránh dồn tiếng
    _last[name] = now;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    final v = (sfxVol * vol).clamp(0.0, 1.0).toDouble();
    _safe(() async {
      await p.stop();
      await p.play(AssetSource('sfx/$name.wav'), volume: v);
    });
  }

  /// Đổi nhạc nền: menu, classic, garden, beach, night, sakura, tet. null = tắt.
  static void music(String? track) {
    if (track == _track) return;
    _track = track;
    _safe(() async {
      await _music.stop();
      if (track != null && enabled) {
        await _music.play(AssetSource('music/$track.wav'), volume: musicVol);
      }
    });
  }

  static void setEnabled(bool v) {
    if (v == enabled) return;
    enabled = v;
    final t = _track;
    if (v) {
      _track = null;
      music(t);
    } else {
      _safe(() => _music.stop());
    }
  }

  static void pause() => _safe(() => _music.pause());

  static void resume() {
    if (enabled && _track != null) _safe(() => _music.resume());
  }
}
