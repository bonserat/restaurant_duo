// Bộ giao diện chung: màu, chủ đề và các thành phần dùng lại cho mọi màn hình.
// Phong cách "phố ẩm thực về đêm": nền kem ấm, thanh trên màu chàm đậm,
// nút chính cam san hô, tiền màu vàng, thành phần bo tròn lớn và đổ bóng mềm.
import 'package:flutter/material.dart';
import 'sound.dart';

class Pal {
  static const ink = Color(0xFF221B3F); // chàm đậm: thanh trên, chữ đậm
  static const ink2 = Color(0xFF3A2F66);
  static const bg = Color(0xFFFFF6EA); // kem ấm
  static const surface = Colors.white;
  static const line = Color(0xFFEFE2D0);
  static const text = Color(0xFF2B2440);
  static const muted = Color(0xFF8A809E);
  static const coral = Color(0xFFFF6A47); // hành động chính
  static const coral2 = Color(0xFFFF9A3D);
  static const mint = Color(0xFF1FB6A6); // hành động phụ / đã sở hữu
  static const mint2 = Color(0xFF55D6BE);
  static const gold = Color(0xFFFFC23D); // tiền
  static const berry = Color(0xFFE84A7F); // thú cưng
  static const sky = Color(0xFF4C8DFF); // online
  static const danger = Color(0xFFE5484D);
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Pal.coral, primary: Pal.coral, secondary: Pal.mint, surface: Pal.surface);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.bg,
    cardTheme: CardThemeData(
      color: Pal.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Pal.line)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: const BorderSide(color: Pal.line),
      selectedColor: const Color(0xFFFFE3D9),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Pal.text),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Pal.coral,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.text,
        side: const BorderSide(color: Pal.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Pal.text,
      unselectedLabelColor: Pal.muted,
      labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pal.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Nút lớn có nền chuyển màu
class GButton extends StatelessWidget {
  final String label;
  final String? emoji;
  final VoidCallback? onTap;
  final List<Color> colors;
  final double height;
  final bool expand;
  const GButton(this.label, {super.key, this.emoji, this.onTap, this.colors = const [Pal.coral, Pal.coral2], this.height = 54, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final child = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: off ? [const Color(0xFFD9D2C8), const Color(0xFFCFC6BA)] : colors),
        borderRadius: BorderRadius.circular(height / 2.6),
        boxShadow: off ? null : [BoxShadow(color: colors.first.withAlpha(90), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (emoji != null) ...[Text(emoji!, style: TextStyle(fontSize: height * 0.4)), const SizedBox(width: 8)],
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: height * 0.31, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        ),
      ]),
    );
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: off
            ? null
            : () {
                Sound.sfx('tap');
                onTap!();
              },
        child: child,
      ),
    );
  }
}

/// Nút phụ nền nhạt
class SoftButton extends StatelessWidget {
  final String label;
  final String? emoji;
  final VoidCallback? onTap;
  final Color tint;
  const SoftButton(this.label, {super.key, this.emoji, this.onTap, this.tint = Pal.ink2});
  @override
  Widget build(BuildContext context) => Material(
        color: tint.withAlpha(22),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap == null
              ? null
              : () {
                  Sound.sfx('tap');
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 18)), const SizedBox(width: 6)],
              Text(label, style: TextStyle(color: tint, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

/// Nút tròn nhỏ trên thanh trên cùng
class RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool dark;
  final String tip;
  const RoundIcon(this.icon, {super.key, required this.onTap, this.dark = true, this.tip = ''});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: dark ? Colors.white.withAlpha(30) : Pal.ink.withAlpha(14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Sound.sfx('tap');
              onTap();
            },
            child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 21, color: dark ? Colors.white : Pal.ink)),
          ),
        ),
      );
}

/// Viên thông số: biểu tượng + giá trị
class StatPill extends StatelessWidget {
  final String emoji, value;
  final Color? color;
  final bool dark;
  const StatPill(this.emoji, this.value, {super.key, this.color, this.dark = true});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: color ?? (dark ? Colors.white.withAlpha(28) : Pal.surface),
          borderRadius: BorderRadius.circular(20),
          border: dark ? null : Border.all(color: Pal.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                color: dark ? Colors.white : Pal.text,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      );
}

/// Thẻ nền trắng bo tròn
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? border;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.border, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: color ?? Pal.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border ?? Pal.line, width: border == null ? 1 : 2),
            ),
            child: child,
          ),
        ),
      );
}

/// Ô biểu tượng lớn bo tròn (dùng làm "ảnh" cho mục trong cửa hàng)
class EmojiTile extends StatelessWidget {
  final String emoji;
  final Color tint;
  final double size;
  const EmojiTile(this.emoji, {super.key, this.tint = Pal.coral, this.size = 56});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withAlpha(40), tint.withAlpha(16)]),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: TextStyle(fontSize: size * 0.52)),
      );
}

/// Nút mua có giá; chuyển xám khi không đủ tiền
class PriceButton extends StatelessWidget {
  final int cost;
  final bool afford;
  final VoidCallback onTap;
  const PriceButton(this.cost, {super.key, required this.afford, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          Sound.sfx(afford ? 'tap' : 'wrong');
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: afford ? Pal.gold : const Color(0xFFEDE7DF),
            borderRadius: BorderRadius.circular(14),
            boxShadow: afford ? [BoxShadow(color: Pal.gold.withAlpha(110), blurRadius: 8, offset: const Offset(0, 3))] : null,
          ),
          child: Text('💰 $cost',
              style: TextStyle(fontWeight: FontWeight.w900, color: afford ? const Color(0xFF5A3B00) : Pal.muted, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      );
}

/// Nhãn trạng thái nhỏ
class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = Pal.mint});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final String? sub;
  const SectionTitle(this.text, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Pal.text)),
          if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(color: Pal.muted, fontSize: 12.5))),
        ]),
      );
}

/// Một dòng trong cửa hàng: ô biểu tượng, tên, mô tả, hành động
class ShopRow extends StatelessWidget {
  final String emoji, title;
  final String? sub;
  final Widget trailing;
  final Color tint;
  final bool highlight;
  final Widget? leading; // thay cho ô biểu tượng (vd. hình vẽ đồ trang trí)
  const ShopRow({super.key, required this.emoji, required this.title, this.sub, required this.trailing, this.tint = Pal.coral, this.highlight = false, this.leading});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          border: highlight ? Pal.coral : null,
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            leading ?? EmojiTile(emoji, tint: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Pal.text)),
                if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: const TextStyle(color: Pal.muted, fontSize: 12.5, height: 1.3))),
              ]),
            ),
            const SizedBox(width: 8),
            trailing,
          ]),
        ),
      );
}

/// Thanh tab dạng viên thuốc
class PillTabs extends StatelessWidget implements PreferredSizeWidget {
  final List<String> tabs;
  const PillTabs(this.tabs, {super.key});
  @override
  Size get preferredSize => const Size.fromHeight(46);
  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFF1E6D7), borderRadius: BorderRadius.circular(16)),
        child: TabBar(
          isScrollable: tabs.length > 3,
          tabAlignment: tabs.length > 3 ? TabAlignment.start : TabAlignment.fill,
          indicator: BoxDecoration(
            color: Pal.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: [for (final t in tabs) Tab(text: t, height: 34)],
        ),
      );
}

/// Thanh điều hướng dưới cùng (4 mục)
class HubDock extends StatelessWidget {
  final String current;
  final void Function(String) onSelect;
  final List<(String, String, String)> items; // (id, emoji, nhãn)
  const HubDock({super.key, required this.current, required this.onSelect, required this.items});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Pal.ink,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x40221B3F), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          for (final it in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Sound.sfx('tap');
                  onSelect(it.$1);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    gradient: current == it.$1 ? const LinearGradient(colors: [Pal.coral, Pal.coral2]) : null,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedScale(
                      scale: current == it.$1 ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 220),
                      child: Text(it.$2, style: const TextStyle(fontSize: 21)),
                    ),
                    const SizedBox(height: 2),
                    Text(it.$3,
                        style: TextStyle(
                          color: current == it.$1 ? Colors.white : Colors.white.withAlpha(150),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        )),
                  ]),
                ),
              ),
            ),
        ]),
      );
}

/// Mở một bảng trượt từ dưới lên với tay nắm và tiêu đề
Future<T?> showGameSheet<T>(BuildContext context, {required String title, String? emoji, required Widget Function(BuildContext, StateSetter) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
        decoration: const BoxDecoration(color: Pal.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 44, height: 5, margin: const EdgeInsets.only(top: 10), decoration: BoxDecoration(color: Pal.line, borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(children: [
                if (emoji != null) ...[Text(emoji, style: const TextStyle(fontSize: 24)), const SizedBox(width: 8)],
                Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Pal.text))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: Pal.muted)),
              ]),
            ),
            Flexible(child: builder(ctx, setS)),
          ]),
        ),
      ),
    ),
  );
}

/// Nền chuyển màu cho các màn hình "sân khấu" (sảnh chờ, kết quả, chọn chủ quán)
class StageBackground extends StatelessWidget {
  final Widget child;
  const StageBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Pal.ink, Pal.ink2, Color(0xFF6B3F73)]),
        ),
        child: child,
      );
}
