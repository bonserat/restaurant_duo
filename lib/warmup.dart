// Bản web: nạp sẵn font emoji và âm thanh ngay khi mở game,
// để lúc chơi không bị khựng vì phải tải giữa chừng.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'sound.dart';

/// Mọi emoji game dùng (tự sinh từ mã nguồn)
const kAllEmojis = '🎉 💧 🌽 🪣 🧹 ❤️‍🩹 🥀 ✨ 🔒 💰 🍔 🏠 🌿 🏖️ 🌙 🌸 🧧 🍃 🕊️ ☀️ 🏮 🦋 🐈 💤 🔔 💨 🌼 🌴 🪴 ⭐ 💖 💕 💗 🪩 🐀 💢 ⚡ 🔌 ⏳ 🚶 🕯️ 🍽️ 😋 ❗ 🧂 🔪 🔥 🧯 👆 ✅ 🏆 🌧️ 💪 ♪ ♫ → 🌱 🙂 📈 🌻 ⚠️ 😠 👑 😡 🐕 📰 🏹 🎒 🎁 🕵️ 🍀 😕 😤 🤢 😍 😖 👩‍🍳 👨‍🍳 🛎️ 📅 🗺️ 🛍️ 🏡 👥 🎯 🪑 📖 🔑 🤝 🏁 🔄 ⚙️ 🔊 🧰 🧐 🐾 ♥ 📱 💡 🚪 ⏱ 🆚 😬 ❓ 📋 😣 🧊 🌋 😐 ⬅ 🛠️ 💔 🤚 🍖 ↺ 😢 🔧 🎨 ✓ 🍳 🖼️ ☕ 🫘 🥛 🍵 🍓 🍯 🧋 🍹 🥤 🥐 🌾 🥚 🧈 🍫 🧀 🥖 🍪 🧁 🍰 🥟 🍚 🫓 🥩 🥬 🍜 🥫 🌮 🍅 🥑 🌶️ 🌯 🫔 🚚 🍞 🥔 🍟 🌭 🍱 🍉 🥭 🐉 🌵 🍍 🦆 🐣 🐄 🐮 🐟 🐠 🦞 🦐 🧄 🐛 🧴 🧤 💦 ⛏️ 🥵 ⛱️ 🤒 💉 🪰 🥶 🟢 🥅 🫧 ⛈️ 🍬 🐹 🦜 💐 🌳 🍸 🎹 📚 🛋️ 🗿 🕰️ ☁️ 📒 🏥 💩 🧺 ❤️ 💊';

const _sfx = ['alarm', 'angry', 'burn', 'chirp', 'chop', 'clean', 'coin', 'ding', 'door', 'drip', 'firework', 'fixed', 'goal', 'knob', 'lose', 'order', 'plop', 'powerdown', 'purr', 'serve', 'shake', 'shout', 'sizzle', 'squeak', 'tap', 'whoosh', 'win', 'woof', 'wrong'];

/// Đặt ở gốc giao diện: vẽ ẩn toàn bộ emoji một lần để trình duyệt tải font trước
class EmojiWarmup extends StatelessWidget {
  const EmojiWarmup({super.key});
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return const IgnorePointer(
      child: Opacity(
        opacity: 0,
        child: Text(kAllEmojis, style: TextStyle(fontSize: 14), maxLines: 3),
      ),
    );
  }
}

/// Tải + giải mã sẵn các tiếng hiệu ứng (chạy nền, lỗi thì bỏ qua)
Future<void> preloadSounds() async {
  if (!kIsWeb) return;
  try {
    await Sound.preload(_sfx);
  } catch (_) {}
}
