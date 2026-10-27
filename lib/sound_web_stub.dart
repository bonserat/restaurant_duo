// Bản không phải web: không dùng Web Audio (âm thanh đi qua audioplayers)
class WebAudio {
  static bool get supported => false;
  static void unlock() {}
  static void sfx(String asset, double vol) {}
  static void music(String? asset, double vol) {}
  static void suspend() {}
  static void resume() {}
  static Future<void> preload(String asset) async {}
}
