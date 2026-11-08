// Cửa hàng thời trang nam nữ: khách nói muốn thử bộ nào, người chơi chọn áo,
// quần/váy, phụ kiện để thay cho khách trong phòng thử. Khách ưng thì trả tiền và đi ra.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'scene.dart';
import 'sound.dart';
import 'ui.dart';

class Garment {
  final String id, name, emoji, slot; // slot: top | bottom | acc
  final Color color;
  final int price;
  final int sex; // 0 cả hai, 1 nam, 2 nữ
  const Garment(this.id, this.name, this.emoji, this.slot, this.color, this.price, [this.sex = 0]);
}

const garments = [
  Garment('ao_do', 'Áo thun đỏ', '👕', 'top', Color(0xFFE53935), 120),
  Garment('ao_trang', 'Sơ mi trắng', '👔', 'top', Color(0xFFF5F5F5), 150),
  Garment('ao_xanh', 'Áo khoác xanh', '🧥', 'top', Color(0xFF1E88E5), 220),
  Garment('ao_vang', 'Áo len vàng', '🧶', 'top', Color(0xFFFDD835), 180),
  Garment('ao_hong', 'Áo hồng', '👚', 'top', Color(0xFFF06292), 140),
  Garment('ao_den', 'Áo đen', '👕', 'top', Color(0xFF212121), 130),
  Garment('ao_la', 'Áo xanh lá', '👕', 'top', Color(0xFF43A047), 120),
  Garment('q_jean', 'Quần jean', '👖', 'bottom', Color(0xFF3949AB), 200, 1),
  Garment('q_kaki', 'Quần kaki', '👖', 'bottom', Color(0xFFC8A97E), 170, 1),
  Garment('q_den', 'Quần tây đen', '👖', 'bottom', Color(0xFF212121), 190, 1),
  Garment('q_xam', 'Quần short xám', '🩳', 'bottom', Color(0xFF8D8D8D), 120, 1),
  Garment('v_hong', 'Váy hồng', '👗', 'bottom', Color(0xFFF48FB1), 220, 2),
  Garment('v_xanh', 'Váy xanh', '👗', 'bottom', Color(0xFF90CAF9), 210, 2),
  Garment('v_den', 'Chân váy đen', '👗', 'bottom', Color(0xFF263238), 180, 2),
  Garment('v_vang', 'Váy vàng', '👗', 'bottom', Color(0xFFFFE082), 200, 2),
  Garment('v_tim', 'Váy tím', '👗', 'bottom', Color(0xFFCE93D8), 230, 2),
  Garment('kinh', 'Kính râm', '🕶️', 'acc', Color(0xFF212121), 90),
  Garment('mu', 'Mũ lưỡi trai', '🧢', 'acc', Color(0xFF1565C0), 80, 1),
  Garment('khan', 'Khăn choàng', '🧣', 'acc', Color(0xFFD32F2F), 100),
  Garment('tui', 'Túi xách', '👜', 'acc', Color(0xFF8D6E63), 160, 2),
  Garment('non', 'Mũ rộng vành', '👒', 'acc', Color(0xFFFFE0B2), 110, 2),
];

Garment garmentById(String id) => garments.firstWhere((g) => g.id == id);

class _Shopper {
  final Look look;
  final String top, bottom;
  final String? acc;
  final double maxPat;
  double pat;
  _Shopper(this.look, this.top, this.bottom, this.acc, this.maxPat) : pat = maxPat;
  bool get female => look.female;
  int get price => garmentById(top).price + garmentById(bottom).price + (acc == null ? 0 : garmentById(acc!).price);
}

class FashionShop extends StatefulWidget {
  final String staffName; // người bán: Nguyên / Ngọc Anh
  final Look staffLook;
  final int level; // ngày/cấp độ: khách khó tính hơn
  final void Function(int earned, int served, int lost) onDone;
  const FashionShop({super.key, required this.staffName, required this.staffLook, required this.level, required this.onDone});
  @override
  State<FashionShop> createState() => _FashionShopState();
}

class _FashionShopState extends State<FashionShop> {
  final rnd = Random();
  Timer? _timer;
  double timeLeft = 90, t = 0;
  int earned = 0, served = 0, lost = 0;
  final List<_Shopper> queue = [];
  _Shopper? cur;
  String? top, bottom, acc; // đồ đang mặc thử
  String tab = 'top';
  String? say; // khách nói
  double sayT = 0;
  double leaveT = -1; // khách đang đi ra (ưng ý)
  bool happyLeave = true;
  int tries = 0;
  bool ended = false;
  double spawnT = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick(0.05));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  _Shopper _newShopper() {
    final look = Look.seed(rnd.nextInt(1 << 30));
    final sex = look.female ? 2 : 1;
    List<Garment> of(String slot) => garments.where((g) => g.slot == slot && (g.sex == 0 || g.sex == sex)).toList();
    final tp = of('top'), bt = of('bottom'), ac = of('acc');
    final wantAcc = rnd.nextDouble() < min(0.75, 0.25 + widget.level * 0.05);
    return _Shopper(look, tp[rnd.nextInt(tp.length)].id, bt[rnd.nextInt(bt.length)].id, wantAcc ? ac[rnd.nextInt(ac.length)].id : null,
        max(16.0, 34 - widget.level * 1.2));
  }

  void _tick(double dt) {
    if (!mounted || ended) return;
    t += dt;
    timeLeft -= dt;
    if (sayT > 0) sayT -= dt;
    spawnT -= dt;
    if (spawnT <= 0 && timeLeft > 8 && queue.length < 3) {
      queue.add(_newShopper());
      spawnT = 7 + rnd.nextDouble() * 6 - min(3.0, widget.level * 0.3);
    }
    // khách đang chờ ngoài hàng cũng mất kiên nhẫn chậm hơn
    for (final q in queue) {
      q.pat -= dt * 0.35;
    }
    final gone = queue.where((q) => q.pat <= 0).length;
    if (gone > 0) {
      lost += gone;
      queue.removeWhere((q) => q.pat <= 0);
      _speak('😤 Có khách bỏ về vì chờ lâu!');
    }
    if (leaveT >= 0) {
      leaveT += dt;
      if (leaveT > 1.4) {
        leaveT = -1;
        cur = null;
      }
    } else if (cur == null && queue.isNotEmpty) {
      cur = queue.removeAt(0);
      top = null;
      bottom = null;
      acc = null;
      tries = 0;
      tab = 'top';
      Sound.sfx('door', vol: 0.5);
    } else if (cur != null) {
      cur!.pat -= dt;
      if (cur!.pat <= 0) {
        lost++;
        happyLeave = false;
        leaveT = 0;
        _speak('😠 Lâu quá, thôi tôi đi!');
        Sound.sfx('angry');
      }
    }
    if (timeLeft <= 0 && (cur == null || leaveT >= 0) && !ended) {
      ended = true;
      _timer?.cancel();
      _finish();
    }
    setState(() {});
  }

  void _speak(String s) {
    say = s;
    sayT = 2.2;
  }

  void _wear(Garment g) {
    final c = cur;
    if (c == null || leaveT >= 0) return;
    if (g.sex != 0 && g.sex != (c.female ? 2 : 1)) {
      _speak(c.female ? 'Đồ này của nam mà 😅' : 'Đồ này của nữ mà 😅');
      Sound.sfx('wrong');
      return;
    }
    Sound.sfx('tap');
    setState(() {
      if (g.slot == 'top') top = top == g.id ? null : g.id;
      if (g.slot == 'bottom') bottom = bottom == g.id ? null : g.id;
      if (g.slot == 'acc') acc = acc == g.id ? null : g.id;
    });
  }

  void _mirror() {
    final c = cur;
    if (c == null || leaveT >= 0) return;
    tries++;
    final okTop = top == c.top, okBot = bottom == c.bottom, okAcc = acc == c.acc;
    if (okTop && okBot && okAcc) {
      final f = (c.pat / c.maxPat).clamp(0.0, 1.0);
      final pay = (c.price * (0.85 + 0.35 * f) * (tries == 1 ? 1.1 : 1.0)).round();
      earned += pay;
      served++;
      happyLeave = true;
      leaveT = 0;
      _speak(tries == 1 ? '😍 Đúng ý luôn! Gửi $pay💰' : '😊 Ưng rồi! Gửi $pay💰');
      Sound.sfx('coin');
    } else {
      final miss = <String>[
        if (!okTop) 'áo',
        if (!okBot) c.female ? 'váy' : 'quần',
        if (!okAcc) c.acc == null ? 'bỏ phụ kiện' : 'phụ kiện',
      ];
      c.pat -= 3;
      _speak('🤔 Chưa đúng ${miss.join(', ')}…');
      Sound.sfx('wrong');
    }
  }

  void _finish() {
    widget.onDone(earned, served, lost);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🛍️ Hết giờ bán hàng'),
        content: Text('Bán được cho $served khách, $lost khách bỏ về.\nThu về 💰 $earned'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Về bản đồ'),
          ),
        ],
      ),
    );
  }

  Look _dressed(_Shopper c) {
    final lk = c.look;
    return Look(lk.skin, lk.hair, top == null ? const Color(0xFFEEEEEE) : garmentById(top!).color, bottom == null ? const Color(0xFFBDBDBD) : garmentById(bottom!).color,
        lk.hairStyle,
        female: lk.female, bow: lk.bow);
  }

  Widget _want(String id) {
    final g = garmentById(id);
    final on = id == top || id == bottom || id == acc;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFDDF6EF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? Pal.mint : Pal.line, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: g.color, shape: BoxShape.circle, border: Border.all(color: Colors.black26))),
        const SizedBox(width: 3),
        Text('${g.emoji} ${g.name}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Pal.text)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = cur;
    final items = garments.where((g) => g.slot == tab && (c == null || g.sex == 0 || g.sex == (c.female ? 2 : 1))).toList();
    return Scaffold(
      backgroundColor: Pal.bg,
      body: SafeArea(
        child: Column(children: [
          // thanh trên
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Pal.ink, Pal.ink2])),
            child: Row(children: [
              const Text('👗 Thời trang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(width: 8),
              StatPill('⏱', '${max(0, timeLeft).ceil()}s', color: timeLeft < 15 ? Pal.danger : null),
              const SizedBox(width: 4),
              StatPill('💰', '$earned'),
              const SizedBox(width: 4),
              StatPill('🛍️', '$served'),
              const Spacer(),
              IconButton(
                onPressed: () {
                  if (!ended) {
                    ended = true;
                    _timer?.cancel();
                    _finish();
                  }
                },
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
          ),
          // yêu cầu của khách
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            color: const Color(0xFFFFF7E8),
            child: c == null
                ? Text(queue.isEmpty ? '🕐 Đang chờ khách vào cửa hàng…' : '🚪 Khách đang vào…', style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w700))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.female ? '💁‍♀️ Chị ấy muốn thử:' : '💁‍♂️ Anh ấy muốn thử:', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [_want(c.top), _want(c.bottom), if (c.acc != null) _want(c.acc!)]),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (c.pat / c.maxPat).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: const Color(0xFFF0EAE0),
                        color: c.pat / c.maxPat < 0.35 ? Pal.danger : Pal.mint,
                      ),
                    ),
                  ]),
          ),
          // phòng thử
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _ShopPainter(this))),
              if (say != null && sayT > 0)
                Align(
                  alignment: const Alignment(0, -0.85),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)]),
                    child: Text(say!, style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
                  ),
                ),
              if (queue.isNotEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(230), borderRadius: BorderRadius.circular(12)),
                    child: Text('🚶 ${queue.length} khách đang chờ', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Pal.text)),
                  ),
                ),
            ]),
          ),
          // giá treo đồ
          Container(
            color: Pal.surface,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(children: [
              for (final (id, label) in const [('top', '👕 Áo'), ('bottom', '👖 Quần / Váy'), ('acc', '🕶️ Phụ kiện')])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => tab = id),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(color: tab == id ? Pal.coral : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Pal.line)),
                      child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: tab == id ? Colors.white : Pal.text)),
                    ),
                  ),
                ),
            ]),
          ),
          Container(
            height: 84,
            color: Pal.surface,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), children: [
              for (final g in items)
                GestureDetector(
                  onTap: () => _wear(g),
                  child: Container(
                    width: 74,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: (g.id == top || g.id == bottom || g.id == acc) ? const Color(0xFFDDF6EF) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: (g.id == top || g.id == bottom || g.id == acc) ? Pal.mint : Pal.line, width: 2),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Stack(alignment: Alignment.bottomRight, children: [
                        Text(g.emoji, style: const TextStyle(fontSize: 28)),
                        Container(width: 12, height: 12, decoration: BoxDecoration(color: g.color, shape: BoxShape.circle, border: Border.all(color: Colors.black26))),
                      ]),
                      Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Pal.text)),
                      Text('${g.price}💰', style: const TextStyle(fontSize: 9.5, color: Pal.muted, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, 6 + MediaQuery.of(context).padding.bottom * 0),
            child: Row(children: [
              Expanded(
                child: SoftButton('Cởi ra', emoji: '↩️', onTap: () => setState(() {
                  top = null;
                  bottom = null;
                  acc = null;
                })),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: GButton('Soi gương', emoji: '🪞', onTap: c == null ? null : _mirror)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ShopPainter extends CustomPainter {
  final _FashionShopState st;
  _ShopPainter(this.st);

  void _emoji(Canvas c, String e, Offset p, double size) {
    final tp = TextPainter(text: TextSpan(text: e, style: TextStyle(fontSize: size)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, p - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas c, Size sz) {
    final w = sz.width, h = sz.height;
    final t = st.t;
    // tường hồng nhạt + sàn gỗ
    c.drawRect(Rect.fromLTWH(0, 0, w, h * 0.7), Paint()..color = const Color(0xFFFCE4EC));
    for (var x = 0.0; x < w; x += 26) {
      c.drawRect(Rect.fromLTWH(x, 0, 13, h * 0.7), Paint()..color = const Color(0x10E91E63));
    }
    c.drawRect(Rect.fromLTWH(0, h * 0.7, w, h * 0.3), Paint()..color = const Color(0xFFD7B48A));
    for (var x = 0.0; x < w; x += 40) {
      c.drawLine(Offset(x, h * 0.7), Offset(x - 30, h), Paint()
        ..color = const Color(0x22000000)
        ..strokeWidth = 1);
    }
    // giá treo đồ bên trái
    final rackY = h * 0.18;
    c.drawLine(Offset(w * 0.04, rackY), Offset(w * 0.3, rackY), Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 3);
    var k = 0;
    for (final g in garments.where((g) => g.slot != 'acc').take(8)) {
      final x = w * 0.06 + k * w * 0.032;
      c.drawLine(Offset(x, rackY), Offset(x, rackY + 6), Paint()..color = const Color(0xFF616161));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 6, rackY + 6, 12, h * 0.2), const Radius.circular(3)), Paint()..color = g.color);
      k++;
    }
    // gương lớn bên phải
    final mirror = Rect.fromLTWH(w * 0.7, h * 0.08, w * 0.24, h * 0.6);
    c.drawRRect(RRect.fromRectAndRadius(mirror.inflate(5), const Radius.circular(60)), Paint()..color = const Color(0xFFD4AF37));
    c.drawRRect(RRect.fromRectAndRadius(mirror, const Radius.circular(56)),
        Paint()..shader = const LinearGradient(colors: [Color(0xFFE3F2FD), Color(0xFFFFFFFF), Color(0xFFBBDEFB)]).createShader(mirror));
    // rèm phòng thử
    final cur = Rect.fromLTWH(w * 0.36, h * 0.06, w * 0.3, h * 0.66);
    c.drawRect(Rect.fromLTWH(cur.left - 6, cur.top - 6, cur.width + 12, 6), Paint()..color = const Color(0xFF8D6E63));
    for (final side in [0.0, 1.0]) {
      final x = side == 0 ? cur.left : cur.right - cur.width * 0.18;
      c.drawRect(Rect.fromLTWH(x, cur.top, cur.width * 0.18, cur.height), Paint()..color = const Color(0xFFAD1457));
      for (var j = 1; j < 4; j++) {
        c.drawLine(Offset(x + cur.width * 0.045 * j, cur.top), Offset(x + cur.width * 0.045 * j, cur.bottom), Paint()
          ..color = const Color(0x33000000)
          ..strokeWidth = 1);
      }
    }
    // người bán đứng cạnh
    drawPerson(c, Offset(w * 0.2, h * 0.94), h * 0.42, st.widget.staffLook, name: st.widget.staffName, phase: t * 6, armUp: sin(t * 2) > 0.7);
    // khách trong phòng thử
    final s = st.cur;
    if (s != null) {
      var px = w * 0.51;
      if (st.leaveT >= 0) px -= st.leaveT * w * 0.35 * (st.happyLeave ? 1 : 1.2);
      final p = Offset(px, h * 0.94);
      final size = h * 0.62;
      final u = size / 10;
      final lk = st._dressed(s);
      final mood = st.leaveT >= 0 ? (st.happyLeave ? 0 : 2) : ((s.pat / s.maxPat) < 0.35 ? 2 : ((s.pat / s.maxPat) < 0.6 ? 1 : 0));
      drawPerson(c, p, size, lk, walking: st.leaveT >= 0, phase: t * 8, facingLeft: st.leaveT >= 0, mood: mood, armUp: st.leaveT >= 0 && st.happyLeave && sin(t * 9) > 0, bob: sin(t * 2) * 1.5);
      // phụ kiện
      final a = st.acc;
      if (a != null) {
        switch (a) {
          case 'kinh':
            _emoji(c, '🕶️', p + Offset(0, -8.5 * u), u * 2.2);
            break;
          case 'mu':
            _emoji(c, '🧢', p + Offset(0, -10.4 * u), u * 3.0);
            break;
          case 'non':
            _emoji(c, '👒', p + Offset(0, -10.4 * u), u * 3.4);
            break;
          case 'khan':
            _emoji(c, '🧣', p + Offset(0, -6.6 * u), u * 2.6);
            break;
          case 'tui':
            _emoji(c, '👜', p + Offset(2.8 * u, -4.2 * u), u * 2.4);
            break;
        }
      }
      // ảnh trong gương
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(mirror, const Radius.circular(56)));
      drawPerson(c, Offset(mirror.center.dx, mirror.bottom - 4), mirror.height * 0.85, lk, facingLeft: true, mood: mood);
      c.restore();
      if (st.leaveT >= 0 && st.happyLeave) {
        for (var j = 0; j < 3; j++) {
          _emoji(c, j.isEven ? '💖' : '✨', p + Offset((j - 1) * u * 3, -11 * u - st.leaveT * 30 - j * 6), u * 2);
        }
      }
    } else {
      _emoji(c, '🪝', Offset(w * 0.51, h * 0.4), 30);
    }
  }

  @override
  bool shouldRepaint(covariant _ShopPainter oldDelegate) => true;
}
