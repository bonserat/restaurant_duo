// Âm thanh: hiệu ứng (assets/sfx) + nhạc nền theo hoạt cảnh (assets/music).
// Mọi lời gọi đều "an toàn": lỗi âm thanh không bao giờ làm hỏng game.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'sound_web_stub.dart' if (dart.library.js_interop) 'sound_web.dart';

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
    if (kIsWeb && WebAudio.supported) {
      WebAudio.sfx('assets/sfx/$name.wav', (sfxVol * vol).clamp(0.0, 1.0).toDouble());
      return;
    }
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
    if (kIsWeb && WebAudio.supported) {
      WebAudio.music(track != null && enabled ? 'assets/music/$track.wav' : null, musicVol);
      return;
    }
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
    } else if (kIsWeb && WebAudio.supported) {
      WebAudio.music(null, 0);
    } else {
      _safe(() => _music.stop());
    }
  }

  /// Bản web: tải + giải mã sẵn các tiếng hiệu ứng
  static Future<void> preload(List<String> names) async {
    if (!kIsWeb || !WebAudio.supported) return;
    for (final n in names) {
      await WebAudio.preload('assets/sfx/$n.wav');
    }
  }

  static void pause() {
    if (kIsWeb && WebAudio.supported) return WebAudio.suspend();
    _safe(() => _music.pause());
  }

  static void resume() {
    if (kIsWeb && WebAudio.supported) return WebAudio.resume();
    if (enabled && _track != null) _safe(() => _music.resume());
  }
}
