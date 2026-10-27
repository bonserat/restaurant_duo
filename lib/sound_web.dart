// Âm thanh cho bản web bằng Web Audio API: mỗi file chỉ tải + giải mã 1 lần,
// phát lại cực nhẹ nên không làm game giật như khi tạo thẻ <audio> mới mỗi lần.
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

@JS('AudioContext')
extension type _Ctx._(JSObject _) implements JSObject {
  external _Ctx();
  external JSPromise<_Buf> decodeAudioData(JSArrayBuffer data);
  external _Src createBufferSource();
  external _Gain createGain();
  external JSObject get destination;
  external String get state;
  external JSPromise<JSAny?> resume();
  external JSPromise<JSAny?> suspend();
}

extension type _Buf._(JSObject _) implements JSObject {}

extension type _Param._(JSObject _) implements JSObject {
  external set value(double v);
}

extension type _Gain._(JSObject _) implements JSObject {
  external _Param get gain;
  external JSObject connect(JSObject dest);
}

extension type _Src._(JSObject _) implements JSObject {
  external set buffer(_Buf b);
  external set loop(bool v);
  external JSObject connect(JSObject dest);
  external void start();
  external void stop();
}

class WebAudio {
  static _Ctx? _ctx;
  static bool _failed = false;
  static final Map<String, _Buf> _bufs = {};
  static final Map<String, Future<_Buf?>> _loading = {};
  static _Src? _musicSrc;
  static int _musicGen = 0;

  static bool get supported => _ensure();

  static bool _ensure() {
    if (_ctx != null) return true;
    if (_failed) return false;
    try {
      _ctx = _Ctx();
      return true;
    } catch (_) {
      _failed = true;
      return false;
    }
  }

  /// Safari chỉ cho phát tiếng sau khi người dùng chạm: gọi trong lúc xử lý cú chạm
  static void unlock() {
    final c = _ctx;
    if (c == null) return;
    try {
      if (c.state != 'running') c.resume();
    } catch (_) {}
  }

  static Future<_Buf?> _load(String asset) {
    final done = _bufs[asset];
    if (done != null) return Future.value(done);
    return _loading.putIfAbsent(asset, () async {
      try {
        final data = await rootBundle.load(asset);
        final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        final buf = await _ctx!.decodeAudioData(bytes.buffer.toJS).toDart;
        _bufs[asset] = buf;
        return buf;
      } catch (_) {
        return null;
      } finally {
        _loading.remove(asset);
      }
    });
  }

  static Future<void> preload(String asset) async {
    if (!_ensure()) return;
    await _load(asset);
  }

  static _Src? _play(_Buf b, double vol, {bool loop = false}) {
    final c = _ctx!;
    try {
      final s = c.createBufferSource();
      s.buffer = b;
      s.loop = loop;
      final g = c.createGain();
      g.gain.value = vol;
      s.connect(g);
      g.connect(c.destination);
      s.start();
      return s;
    } catch (_) {
      return null;
    }
  }

  static void sfx(String asset, double vol) {
    if (!_ensure()) return;
    unlock();
    final b = _bufs[asset];
    if (b != null) {
      _play(b, vol);
    } else {
      // chưa tải xong thì tải rồi phát (chỉ lần đầu)
      _load(asset).then((b) {
        if (b != null) _play(b, vol);
      });
    }
  }

  /// Đổi nhạc nền (asset = null: tắt nhạc)
  static void music(String? asset, double vol) {
    if (!_ensure()) return;
    final gen = ++_musicGen;
    try {
      _musicSrc?.stop();
    } catch (_) {}
    _musicSrc = null;
    if (asset == null) return;
    _load(asset).then((b) {
      if (b == null || gen != _musicGen) return;
      _musicSrc = _play(b, vol, loop: true);
    });
  }

  static void suspend() {
    try {
      _ctx?.suspend();
    } catch (_) {}
  }

  static void resume() => unlock();
}
