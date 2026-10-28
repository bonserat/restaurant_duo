// Màn khu vườn chung: ruộng trồng cây, chuồng gia súc, hồ cá.
import 'dart:math';
import 'package:flutter/material.dart';
import 'data.dart';
import 'dishes.dart';
import 'garden_engine.dart';
import 'garden_store.dart';
import 'sound.dart';
import 'ui.dart';

class GardenTab extends StatefulWidget {
  final int money;
  final bool Function(int) pay;
  final void Function(int) earn;
  final void Function(String) toast;
  const GardenTab({super.key, required this.money, required this.pay, required this.earn, required this.toast});
  @override
  State<GardenTab> createState() => _GardenTabState();
}

class _GardenTabState extends State<GardenTab> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  Garden get g => Garden.instance;

  void _on() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    g.addListener(_on);
    g.watch(true);
  }

  @override
  void dispose() {
    g.removeListener(_on);
    g.watch(false);
    _anim.dispose();
    super.dispose();
  }

  double get _t => _anim.value * 12;

  // ------------------------------------------------------------------ khung chính
  @override
  Widget build(BuildContext context) {
    final st = g.state;
    final now = DateTime.now().millisecondsSinceEpoch;
    final w = weatherAt(now);
    final w2 = weatherAt(now + 24 * kHour);
    return Column(children: [
      _weatherBar(w, w2),
      if (g.error.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFFFF0E6), borderRadius: BorderRadius.circular(12)),
          child: Text('⚠️ ${g.error}', style: const TextStyle(color: Pal.coral, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      _quickRow(st, w),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: LayoutBuilder(builder: (ctx, c) {
            final W = c.maxWidth, H = c.maxHeight;
            final wet = <String, double>{};
            var pondDirt = 0.0;
            for (final it in st.items.values) {
              if (it.isPlant) wet[it.slot] = it.water;
              if (it.s.kind == 'fish') pondDirt = max(pondDirt, it.dirt);
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (_, __) => CustomPaint(painter: GardenPainter(w.id, _t, wet, pondDirt)),
                  ),
                ),
                for (final s in gSlots) _slotView(s, st.at(s.id), W, H),
              ]),
            );
          }),
        ),
      ),
      _bottomStrip(st),
    ]);
  }

  Widget _weatherBar(GWeather w, GWeather w2) {
    final cols = switch (w.id) {
      'hot' => const [Color(0xFFFF8A3D), Color(0xFFFFC23D)],
      'rain' => const [Color(0xFF5B7DB1), Color(0xFF8FB3E0)],
      'storm' => const [Color(0xFF3B3F63), Color(0xFF6C6F9C)],
      _ => const [Color(0xFF4C8DFF), Color(0xFF7FD0FF)],
    };
    final sync = g.lastSync == null ? 'đang kết nối…' : 'đồng bộ ${_ago(g.lastSync!.millisecondsSinceEpoch)}';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(gradient: LinearGradient(colors: cols), borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Text(w.emoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hôm nay: ${w.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            Text(w.effect, style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.2)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Mai ${w2.emoji}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          Text('☁️ $sync', style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _quickRow(GState st, GWeather w) {
    final live = st.items.values.where((i) => i.alive).toList();
    final thirsty = live.where((i) => i.isPlant && i.water < 0.6).toList();
    final hungry = live.where((i) => !i.isPlant && i.food < 0.6).toList();
    final dirty = live.where((i) => !i.isPlant && i.dirt > 0.4).toList();
    Widget btn(String emoji, String label, List<GItem> list, String a) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: list.isEmpty ? const Color(0xFFF2EEE8) : const Color(0xFFE6F7EF),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: list.isEmpty
                    ? null
                    : () {
                        Sound.sfx('tap');
                        g.actMany([for (final i in list) (a, {'u': i.uid})]);
                        widget.toast('$emoji Đã $label ${list.length} chỗ');
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    Text(emoji, style: TextStyle(fontSize: 20, color: list.isEmpty ? const Color(0x55000000) : null)),
                    Text(list.isEmpty ? 'Ổn cả' : '$label (${list.length})',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: list.isEmpty ? Pal.muted : Pal.mint)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 0),
      child: Row(children: [
        btn('💧', 'tưới', thirsty, 'water'),
        btn('🌽', 'cho ăn', hungry, 'feed'),
        btn('🧹', 'dọn', dirty, 'clean'),
      ]),
    );
  }

  Widget _bottomStrip(GState st) {
    final logs = st.log.reversed.take(2).toList();
    final dishes = gardenRecipes.where((r) => st.unlocked.contains(r.id.substring(2))).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🍽️ Món từ vườn: ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Pal.text)),
          if (dishes.isEmpty) const Expanded(child: Text('thu hoạch lần đầu để mở món mới', style: TextStyle(color: Pal.muted, fontSize: 12))),
          if (dishes.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [for (final r in dishes) Padding(padding: const EdgeInsets.only(right: 2), child: DishIcon(r.id, size: 28))]),
              ),
            ),
          GestureDetector(
            onTap: () => _showLog(st),
            child: const Text('Nhật ký ›', style: TextStyle(color: Pal.coral, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ]),
        for (final l in logs)
          Text('• ${l.who.isEmpty ? 'Ai đó' : l.who} ${l.text} · ${_ago(l.at)}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Pal.muted, fontSize: 11.5)),
        if (logs.isEmpty) const Text('Chạm vào ô đất, chuồng hoặc hồ để bắt đầu trồng trọt, chăn nuôi', style: TextStyle(color: Pal.muted, fontSize: 11.5)),
      ]),
    );
  }

  String _ago(int ms) {
    final d = DateTime.now().millisecondsSinceEpoch - ms;
    if (d < 60000) return 'vừa xong';
    if (d < 3600000) return '${d ~/ 60000} phút trước';
    if (d < 86400000) return '${d ~/ 3600000} giờ trước';
    return '${d ~/ 86400000} ngày trước';
  }

  void _showLog(GState st) {
    showGameSheet(context, title: 'Nhật ký khu vườn', emoji: '📒', builder: (ctx, setS) {
      final logs = st.log.reversed.take(60).toList();
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
        if (logs.isEmpty) const Text('Chưa có hoạt động nào.', style: TextStyle(color: Pal.muted)),
        for (final l in logs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text('${l.who.isEmpty ? 'Ai đó' : l.who} ${l.text}  ·  ${_ago(l.at)}', style: const TextStyle(color: Pal.text)),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------------ từng ô
  String _stageEmoji(GItem it) {
    final s = it.s;
    if (it.dead) return it.isPlant ? '🥀' : '🏥';
    if (it.ready) return s.emoji;
    final p = it.progress;
    if (it.isPlant) {
      if (p < 0.3) return s.baby;
      if (p < 0.65) return s.id == 'dragon' ? '🌵' : '🌿';
      return s.id == 'dragon' ? '🌵' : '🪴';
    }
    return p < 0.5 ? s.baby : s.emoji;
  }

  Widget _slotView(GSlot slot, GItem? it, double W, double H) {
    final sw = W * (slot.area == 'field' ? 0.17 : 0.2);
    final sh = H * 0.16;
    final cx = slot.x * W, cy = slot.y * H;
    Widget body;
    if (it == null) {
      final label = slot.area == 'field' ? 'Trồng' : (slot.area == 'pen' ? 'Nuôi' : 'Thả cá');
      body = Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: const Color(0x66FFFFFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x99FFFFFF), width: 1.5)),
          child: Text('＋ $label', style: const TextStyle(color: Color(0xFF3E5B1F), fontWeight: FontWeight.w900, fontSize: 11)),
        ),
      );
    } else {
      final p = it.progress;
      final size = it.isPlant ? sh * (0.42 + 0.38 * p) : sh * (0.45 + 0.4 * p);
      final badges = <String>[
        if (it.prob != null) gProblemById(it.probType).emoji,
        if (it.thirsty) '💧',
        if (it.hungry) '🍽️',
        if (it.dirty) it.s.kind == 'fish' ? '🪣' : '💩',
      ];
      body = AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          final t = _t;
          final seed = it.uid.hashCode % 7;
          final bob = it.isPlant || it.dead ? 0.0 : sin(t * 2.4 + seed) * 3;
          final sway = it.isPlant && !it.dead ? sin(t * 1.3 + seed) * 0.05 : 0.0;
          final walk = it.s.kind == 'fish' && !it.dead ? sin(t * 0.8 + seed) * sw * 0.18 : (it.s.kind == 'animal' && !it.dead ? sin(t * 0.5 + seed) * sw * 0.08 : 0.0);
          final pulse = 1 + (it.ready ? 0.08 * sin(t * 5) : 0.0);
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            if (it.ready)
              Container(
                width: size * 1.5,
                height: size * 1.5,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0x99FFF59D), const Color(0x00FFF59D)])),
              ),
            Transform.translate(
              offset: Offset(walk, bob),
              child: Transform.rotate(
                angle: sway,
                alignment: Alignment.bottomCenter,
                child: Transform.scale(
                  scale: pulse,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(it.s.kind == 'fish' && cos(t * 0.8 + seed) < 0 ? -1.0 : 1.0, 1.0, 1.0),
                    child: Opacity(opacity: it.dead ? 0.7 : 1, child: Text(_stageEmoji(it), style: TextStyle(fontSize: size))),
                  ),
                ),
              ),
            ),
            if (it.isPlant && !it.ready && !it.dead && p >= 0.65)
              Positioned(right: sw * 0.2, top: sh * 0.12, child: Text(it.s.emoji, style: TextStyle(fontSize: size * 0.34))),
            if (it.ready) Positioned(right: sw * 0.12, top: 0, child: Text('✨', style: TextStyle(fontSize: 14 + 3 * sin(t * 6)))),
            if (badges.isNotEmpty)
              Positioned(
                left: 0,
                top: -4 - 2 * sin(t * 6).abs(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)]),
                  child: Text(badges.join(), style: const TextStyle(fontSize: 13)),
                ),
              ),
            // thanh lớn lên (màu theo sức khoẻ)
            if (!it.dead)
              Positioned(
                bottom: 0,
                left: sw * 0.15,
                right: sw * 0.15,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(color: const Color(0x66FFFFFF), borderRadius: BorderRadius.circular(3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: max(0.04, p),
                    child: Container(
                      decoration: BoxDecoration(
                        color: it.ready ? Pal.gold : (it.health > 0.6 ? const Color(0xFF43A047) : (it.health > 0.3 ? Pal.coral2 : Pal.danger)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      );
    }
    return Positioned(
      left: cx - sw / 2,
      top: cy - sh / 2,
      width: sw,
      height: sh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Sound.sfx('tap');
          if (it == null) {
            _plantSheet(slot);
          } else {
            _itemSheet(slot);
          }
        },
        child: body,
      ),
    );
  }

  // ------------------------------------------------------------------ gieo trồng
  void _plantSheet(GSlot slot) {
    final area = slot.area;
    final list = species.where((s) => areaOf(s.kind) == area).toList();
    final title = area == 'field' ? 'Gieo hạt giống' : (area == 'pen' ? 'Mua con giống' : 'Thả giống xuống hồ');
    showGameSheet(context, title: title, emoji: area == 'field' ? '🌱' : (area == 'pen' ? '🐣' : '🐠'), builder: (ctx, setS) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        const Text('Mỗi ngày nhớ chăm sóc. Thu hoạch lần đầu sẽ mở món mới cho mọi quán!', style: TextStyle(color: Pal.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Text(s.emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Pal.text)),
                    Text('Lớn sau ${s.days} ngày chăm tốt • thưởng 💰${s.reward}', style: const TextStyle(color: Pal.muted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(children: [
                      DishIcon(s.recipeId, size: 30),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          Garden.instance.unlocked.contains(s.id) ? '${recipeById(s.recipeId).name} (đã mở)' : 'Mở món: ${recipeById(s.recipeId).name}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Pal.mint),
                        ),
                      ),
                    ]),
                  ]),
                ),
                PriceButton(
                  s.cost,
                  afford: widget.money >= s.cost,
                  onTap: () {
                    if (!widget.pay(s.cost)) return;
                    Sound.sfx('coin');
                    g.act('plant', {'slot': slot.id, 'sp': s.id, 'u': Garden.newUid()});
                    Navigator.pop(ctx);
                    widget.toast('${s.emoji} Đã ${s.kind == 'plant' ? 'gieo' : 'thả'} ${s.name}! Nhớ chăm mỗi ngày nhé');
                  },
                ),
              ]),
            ),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------------ chăm sóc
  void _itemSheet(GSlot slot) {
    final first = g.state.at(slot.id);
    if (first == null) return;
    showGameSheet(context, title: first.s.name, emoji: first.s.emoji, builder: (ctx, setS) {
      return AnimatedBuilder(
        animation: g,
        builder: (_, __) {
          final it = g.state.at(slot.id);
          if (it == null || it.uid != first.uid) {
            return const Padding(padding: EdgeInsets.all(24), child: Text('Ô này đã được thu hoạch / dọn đi rồi.', style: TextStyle(color: Pal.muted)));
          }
          return _itemBody(ctx, it);
        },
      );
    });
  }

  Widget _bar(String label, double v, Color col, {String? right}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Pal.text, fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: v.clamp(0.0, 1.0).toDouble(), minHeight: 10, backgroundColor: const Color(0xFFF0EAE0), color: col),
            ),
          ),
          SizedBox(width: 46, child: Text(right ?? '${(v * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(color: Pal.muted, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _itemBody(BuildContext ctx, GItem it) {
    final s = it.s;
    final now = DateTime.now().millisecondsSinceEpoch;
    final kind = s.kind;
    final u = {'u': it.uid};
    Widget act(String emoji, String label, String a, bool enabled, {String? hint}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: enabled ? const Color(0xFFE6F7EF) : const Color(0xFFF2EEE8),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: enabled
                    ? () {
                        Sound.sfx('tap');
                        g.act(a, u);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Text(emoji, style: const TextStyle(fontSize: 26)),
                    Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: enabled ? Pal.text : Pal.muted)),
                    if (hint != null) Text(hint, style: const TextStyle(fontSize: 10, color: Pal.muted)),
                  ]),
                ),
              ),
            ),
          ),
        );

    final fertOn = it.fertUntil > now;
    final raining = weatherAt(now).id == 'rain' || weatherAt(now).id == 'storm';
    final children = <Widget>[];
    if (it.dead) {
      children.addAll([
        Text(
          it.isPlant ? '🥀 Cây đã héo vì bị bỏ bê quá lâu (khát, bệnh không ai chữa…).' : '🏥 ${s.name} yếu quá nên đã được đưa về trạm thú y.',
          style: const TextStyle(color: Pal.text, fontSize: 14),
        ),
        const SizedBox(height: 14),
        GButton('Dọn chỗ để nuôi trồng lại', emoji: '🧹', onTap: () {
          g.act('remove', u);
          Navigator.pop(ctx);
        }),
      ]);
    } else if (it.ready) {
      final first = !g.unlocked.contains(s.id);
      children.addAll([
        Center(child: DishIcon(s.recipeId, size: 90)),
        const SizedBox(height: 6),
        Center(child: Text('${s.name} đã lớn! Thu hoạch để nhận 💰${s.reward}', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text))),
        if (first)
          Center(child: Text('🎉 Mở khoá món mới: ${recipeById(s.recipeId).name}', style: const TextStyle(color: Pal.mint, fontWeight: FontWeight.w900))),
        const SizedBox(height: 14),
        GButton('Thu hoạch', emoji: '🧺', onTap: () {
          Sound.sfx('goal');
          g.act('harvest', u);
          widget.earn(s.reward);
          Navigator.pop(ctx);
          widget.toast(first ? '🎉 Món mới "${recipeById(s.recipeId).name}" đã có trong thực đơn mọi quán!' : '🧺 Thu hoạch ${s.name}: +💰${s.reward}');
        }),
      ]);
    } else {
      children.add(_bar('🌱 Lớn lên', it.progress, Pal.mint, right: 'Ngày ${it.dayNo}/${s.days}'));
      children.add(_bar('❤️ Sức khoẻ', it.health, it.health > 0.6 ? const Color(0xFF43A047) : (it.health > 0.3 ? Pal.coral2 : Pal.danger)));
      if (it.isPlant) {
        children.add(_bar('💧 Độ ẩm', it.water, Pal.sky));
      } else {
        children.add(_bar('🌽 No bụng', it.food, Pal.gold));
        children.add(_bar(kind == 'fish' ? '🪣 Nước sạch' : '🧹 Sạch sẽ', 1 - it.dirt, Pal.mint2));
      }
      if (fertOn) {
        children.add(Text(it.isPlant ? '🌾 Đang được bón phân: lớn nhanh hơn 30%' : '💊 Đang uống vitamin: lớn nhanh hơn 30%',
            style: const TextStyle(color: Pal.mint, fontWeight: FontWeight.w700, fontSize: 12.5)));
      }
      if (it.prob != null) {
        final gp = gProblemById(it.probType);
        children.addAll([
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFEDE6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Pal.coral)),
            child: Row(children: [
              Text(gp.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(gp.name, style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.danger, fontSize: 15)),
                  Text('${gp.desc}. Chưa xử lý thì không lớn được và yếu dần.', style: const TextStyle(color: Pal.text, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          GButton(gp.fix, emoji: gp.fixEmoji, onTap: () {
            Sound.sfx('coin');
            g.act('fix', {'u': it.uid, 'pk': it.prob});
            widget.toast('${gp.fixEmoji} Đã ${gp.fix.toLowerCase()} cho ${s.name}!');
          }),
        ]);
      }
      children.add(const SizedBox(height: 12));
      if (it.isPlant) {
        children.add(Row(children: [
          act('💧', 'Tưới nước', 'water', !raining && it.water < 0.95, hint: raining ? 'trời đang mưa' : null),
          act('🌾', 'Bón phân', 'fert', !fertOn),
        ]));
      } else {
        children.add(Row(children: [
          act(kind == 'fish' ? '🦐' : '🌽', 'Cho ăn', 'feed', it.food < 0.95),
          act(kind == 'fish' ? '🪣' : '🧹', kind == 'fish' ? 'Thay nước' : 'Dọn chuồng', 'clean', it.dirt > 0.05),
          act('💊', 'Vitamin', 'fert', !fertOn),
        ]));
      }
    }
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: children);
  }
}

// =====================================================================
//  VẼ KHU VƯỜN: trời theo thời tiết, ruộng, chuồng, hồ cá
// =====================================================================
class GardenPainter extends CustomPainter {
  final String weather;
  final double t;
  final Map<String, double> wet; // độ ẩm từng ô ruộng
  final double pondDirt;
  GardenPainter(this.weather, this.t, this.wet, this.pondDirt);

  @override
  void paint(Canvas c, Size size) {
    final w = size.width, h = size.height;
    final dark = weather == 'storm' || weather == 'rain';
    // cỏ
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF7FA65A), Color(0xFF5E8A3E)] : const [Color(0xFFB5DD7A), Color(0xFF86C04F)],
        ).createShader(Offset.zero & size),
    );
    // bầu trời
    final skyH = h * 0.13;
    final skyCols = switch (weather) {
      'hot' => const [Color(0xFFFFB74D), Color(0xFFFFE0A3)],
      'rain' => const [Color(0xFF90A4AE), Color(0xFFCFD8DC)],
      'storm' => const [Color(0xFF455A64), Color(0xFF78909C)],
      _ => const [Color(0xFF64B5F6), Color(0xFFBBDEFB)],
    };
    final sky = Rect.fromLTWH(0, 0, w, skyH);
    c.drawRect(sky, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: skyCols).createShader(sky));
    if (weather == 'sun' || weather == 'hot') {
      final sp = Offset(w * 0.88, skyH * 0.5);
      c.drawCircle(sp, skyH * 0.55, Paint()..color = const Color(0x55FFF59D));
      c.drawCircle(sp, skyH * 0.32, Paint()..color = weather == 'hot' ? const Color(0xFFFF9800) : const Color(0xFFFFEB3B));
    }
    for (var k = 0; k < 4; k++) {
      final x = ((t * 6 + k * w / 3.5) % (w + 80)) - 40;
      final y = skyH * (0.3 + 0.15 * (k % 2));
      final cc = Paint()..color = dark ? const Color(0xFFB0BEC5) : const Color(0xEEFFFFFF);
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 46, height: 16), cc);
      c.drawOval(Rect.fromCenter(center: Offset(x + 12, y - 6), width: 26, height: 16), cc);
    }
    // hàng rào gỗ phía xa
    final fence = Paint()
      ..color = const Color(0xFFA1887F)
      ..strokeWidth = 3;
    c.drawLine(Offset(0, skyH + 6), Offset(w, skyH + 6), fence);
    for (double x = 6; x < w; x += 18) {
      c.drawLine(Offset(x, skyH - 2), Offset(x, skyH + 12), fence);
    }

    // ---- ruộng
    final field = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.02, h * 0.18, w * 0.605, h * 0.64), const Radius.circular(16));
    c.drawRRect(field, Paint()..color = const Color(0x2A3E5B1F));
    for (final s in gSlots.where((s) => s.area == 'field')) {
      final m = wet[s.id];
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.x * w, s.y * h + h * 0.03), width: w * 0.165, height: h * 0.1), const Radius.circular(10));
      final soil = m == null ? const Color(0xFFA27B5C) : Color.lerp(const Color(0xFFB8916B), const Color(0xFF6D4C35), m)!;
      c.drawRRect(r.shift(const Offset(0, 3)), Paint()..color = const Color(0x33000000));
      c.drawRRect(r, Paint()..color = soil);
      for (var k = 1; k < 4; k++) {
        final y = r.top + r.height * k / 4;
        c.drawLine(Offset(r.left + 6, y), Offset(r.right - 6, y), Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = 1.5);
      }
    }

    // ---- chuồng
    final pen = Rect.fromLTRB(w * 0.635, h * 0.17, w * 0.985, h * 0.65);
    c.drawRRect(RRect.fromRectAndRadius(pen, const Radius.circular(14)), Paint()..color = const Color(0xFFD9C3A0));
    final rail = Paint()
      ..color = const Color(0xFF8D6E63)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (final y in [pen.top, pen.bottom]) {
      c.drawLine(Offset(pen.left, y), Offset(pen.right, y), rail);
      c.drawLine(Offset(pen.left, y - 8), Offset(pen.right, y - 8), rail..strokeWidth = 2.5);
      rail.strokeWidth = 3.5;
    }
    c.drawLine(Offset(pen.left, pen.top), Offset(pen.left, pen.bottom), rail);
    c.drawLine(Offset(pen.right, pen.top), Offset(pen.right, pen.bottom), rail);
    for (double y = pen.top; y <= pen.bottom; y += (pen.height / 6)) {
      c.drawCircle(Offset(pen.left, y), 3, Paint()..color = const Color(0xFF6D4C41));
      c.drawCircle(Offset(pen.right, y), 3, Paint()..color = const Color(0xFF6D4C41));
    }
    // máng cỏ + chuồng nhỏ
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pen.left + 8, pen.bottom - 22, pen.width * 0.32, 10), const Radius.circular(4)), Paint()..color = const Color(0xFF8D6E63));
    c.drawRect(Rect.fromLTWH(pen.left + 10, pen.bottom - 26, pen.width * 0.28, 5), Paint()..color = const Color(0xFFCDDC39));
    final barn = Rect.fromLTWH(pen.right - pen.width * 0.36, pen.top + 6, pen.width * 0.3, pen.height * 0.2);
    c.drawRect(barn, Paint()..color = const Color(0xFFC62828));
    c.drawPath(
      Path()
        ..moveTo(barn.left - 4, barn.top)
        ..lineTo(barn.center.dx, barn.top - barn.height * 0.55)
        ..lineTo(barn.right + 4, barn.top)
        ..close(),
      Paint()..color = const Color(0xFF8E2424),
    );
    c.drawRect(Rect.fromCenter(center: Offset(barn.center.dx, barn.bottom - barn.height * 0.3), width: barn.width * 0.4, height: barn.height * 0.6), Paint()..color = const Color(0xFFFFF3E0));

    // ---- lối đi
    final path = Path()
      ..moveTo(w * 0.62, h * 0.66)
      ..quadraticBezierTo(w * 0.55, h * 0.7, w * 0.5, h * 0.7)
      ..lineTo(w * 0.1, h * 0.69);
    c.drawPath(path, Paint()
      ..color = const Color(0xFFE8D5A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round);

    // ---- hồ cá
    final pond = Rect.fromCenter(center: Offset(w * 0.5, h * 0.85), width: w * 0.9, height: h * 0.22);
    final waterTop = Color.lerp(const Color(0xFF4FC3F7), const Color(0xFF8BC34A), pondDirt * 0.8)!;
    final waterBot = Color.lerp(const Color(0xFF0288D1), const Color(0xFF558B2F), pondDirt * 0.8)!;
    c.drawOval(pond.inflate(6), Paint()..color = const Color(0xFFBCAAA4));
    c.drawOval(pond, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [waterTop, waterBot]).createShader(pond));
    for (var k = 0; k < 3; k++) {
      final ph = (t * 0.25 + k / 3) % 1.0;
      final cx = pond.left + pond.width * (0.2 + 0.3 * k);
      c.drawOval(
        Rect.fromCenter(center: Offset(cx, pond.center.dy + pond.height * 0.1), width: 20 + 50 * ph, height: 6 + 14 * ph),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.fromARGB((120 * (1 - ph)).round(), 255, 255, 255),
      );
    }
    // lá sen + lau sậy
    c.drawCircle(Offset(pond.left + pond.width * 0.1, pond.center.dy - 4), 9, Paint()..color = const Color(0xFF66BB6A));
    c.drawCircle(Offset(pond.right - pond.width * 0.1, pond.center.dy + 6), 8, Paint()..color = const Color(0xFF66BB6A));
    for (var k = 0; k < 5; k++) {
      final x = pond.right - 8 - k * 5.0;
      c.drawLine(Offset(x, pond.top + 8), Offset(x - 3, pond.top - 18 - (k % 2) * 6), Paint()
        ..color = const Color(0xFF558B2F)
        ..strokeWidth = 2);
    }

    // ---- mưa / bão
    if (weather == 'rain' || weather == 'storm') {
      final n = weather == 'storm' ? 70 : 45;
      final drop = Paint()
        ..color = const Color(0x88E3F2FD)
        ..strokeWidth = 1.4;
      for (var k = 0; k < n; k++) {
        final x = (k * 53.7) % w;
        final y = ((k * 97.3) + t * (weather == 'storm' ? 420 : 300)) % (h + 20) - 10;
        c.drawLine(Offset(x, y), Offset(x - 3, y + 10), drop);
      }
      if (weather == 'storm' && (t % 5.0) < 0.12) {
        c.drawRect(Offset.zero & size, Paint()..color = const Color(0x55FFFFFF));
      }
    }
    if (weather == 'hot') {
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0x14FF9800));
    }
    // giờ thật: hoàng hôn / đêm
    final phase = realDayPhase();
    if (phase == 2) {
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0x77101040));
      for (var k = 0; k < 14; k++) {
        final x = (k * 71.3) % w, y = (k * 37.7) % (skyH * 0.9);
        c.drawCircle(Offset(x, y), 1.2 + (k % 3) * 0.4, Paint()..color = Color.fromARGB((150 + 100 * sin(t * 2 + k)).clamp(0, 255).round(), 255, 255, 230));
      }
      c.drawCircle(Offset(w * 0.12, skyH * 0.45), skyH * 0.25, Paint()..color = const Color(0xFFFFF8E1)); // trăng
    } else if (phase == 1) {
      c.drawRect(Offset.zero & size, Paint()..color = const Color(0x33FF7043));
    }
  }

  @override
  bool shouldRepaint(covariant GardenPainter old) => true;
}
