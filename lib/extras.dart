part of 'main.dart';

// =====================================================================
//  TÍNH NĂNG THÊM: chợ phiên, quà tặng nhau, mùa vụ, thú thân thiết, sự cố vườn,
//  nâng cấp vườn, bộ sưu tập · chợ đêm, pháo hoa, người dân, nhiệm vụ ngày,
//  nhà riêng, xe cộ. Dữ liệu riêng lưu trong [ex].
// =====================================================================

const _upgrades = [
  ('tuoi', '💦', 'Máy tưới tự động', 600, 'Tự tưới cây khát nước mỗi khi bạn ghé vườn'),
  ('bunhin', '🎃', 'Bù nhìn', 250, 'Chim không dám vào ăn trái nữa'),
  ('chuong', '🏠', 'Chuồng rộng', 500, 'Vật nuôi cho quà gấp đôi'),
  ('ao', '🌊', 'Ao rộng', 500, 'Chợ phiên trả giá cao hơn 20%'),
  ('kho', '❄️', 'Kho lạnh', 400, 'Bán nông sản cả ngày thường (giá 70%)'),
];

const _furniture = [
  ('sofa', '🛋️', 'Sofa', 300),
  ('tv', '📺', 'Tivi', 400),
  ('bed', '🛏️', 'Giường đôi', 500),
  ('plant', '🪴', 'Cây cảnh', 120),
  ('art', '🖼️', 'Tranh treo tường', 200),
  ('piano', '🎹', 'Đàn piano', 900),
  ('tank', '🐠', 'Bể cá', 350),
  ('lamp', '💡', 'Đèn ngủ', 150),
  ('dog', '🐶', 'Chó cưng', 600),
  ('catx', '🐱', 'Mèo cưng', 500),
];

const _vehicles = [
  ('bike', '🚲', 'Xe đạp', 400, 5),
  ('moto', '🛵', 'Xe máy', 1200, 10),
  ('car', '🚗', 'Ô tô', 4000, 15),
];

const _npcs = [
  ('👵', 'Bà Tư bán xôi', ['Xôi nóng đây con ơi!', 'Hai đứa dạo này làm ăn khá ha.', 'Nhớ ăn sáng đầy đủ nghe chưa.']),
  ('🛵', 'Chú Ba xe ôm', ['Đi đâu chú chở cho!', 'Cầu Hoà Xuân tối nay lên đèn đẹp lắm.', 'Mưa thì nhớ mang áo mưa nha.']),
  ('👩‍🏫', 'Cô Lan dạy học', ['Học trò cô khen quán hai đứa ngon lắm.', 'Cuối tuần cô dẫn lớp đi ăn nhé.', 'Vườn nhà hai đứa có trái gì mới chưa?']),
];

const _questPool = [
  ('served', '🍽️', 'Phục vụ {n} khách', 20),
  ('earned', '💰', 'Kiếm {n}💰 ở quán', 500),
  ('fashion', '👗', 'Bán hàng ở cửa hàng thời trang', 1),
  ('nm', '🎪', 'Chơi chợ đêm ven sông', 1),
  ('gift', '🎁', 'Tặng quà cho người ấy', 1),
  ('pet', '🐾', 'Vuốt ve vật nuôi {n} lần', 3),
  ('market', '🧺', 'Bán nông sản ở chợ', 1),
  ('npc', '💬', 'Giúp người dân trên phố', 1),
];

extension Extras on _GamePageState {
  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  Map<String, dynamic> _sub(String k) {
    final v = ex[k];
    if (v is Map<String, dynamic>) return v;
    final m = <String, dynamic>{};
    if (v is Map) m.addAll(v.map((a, b) => MapEntry(a.toString(), b)));
    ex[k] = m;
    return m;
  }

  int _num(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;
  bool hasUp(String id) => _sub('up')[id] == true;
  int _hash(String s) {
    var h = 2166136261;
    for (final u in s.codeUnits) {
      h = ((h ^ u) * 16777619) & 0x7fffffff;
    }
    return h;
  }

  void _done(String msg) {
    save();
    setState(() {});
    if (msg.isNotEmpty) snack(msg);
  }

  // ------------------------------------------------------------------ nhiệm vụ hằng ngày
  List<(String, String, String, int)> get todayQuests {
    final h = _hash('q-$_today');
    final idx = <int>[];
    var k = h;
    while (idx.length < 3) {
      final i = k % _questPool.length;
      if (!idx.contains(i)) idx.add(i);
      k = (k ~/ 7) + 13 + idx.length * 31;
    }
    return [for (final i in idx) (_questPool[i].$1, _questPool[i].$2, _questPool[i].$3.replaceAll('{n}', '${_questPool[i].$4}'), _questPool[i].$4)];
  }

  Map<String, dynamic> get _qd {
    final q = _sub('q');
    if (q['date'] != _today) {
      q
        ..clear()
        ..['date'] = _today;
    }
    return q;
  }

  void qAdd(String key, int n) {
    if (n <= 0) return;
    final q = _qd;
    q[key] = _num(q, key) + n;
  }

  bool get questsDone => todayQuests.every((x) => _num(_qd, x.$1) >= x.$4);

  bool _partnerQuestDone() => Garden.instance.events.any((e) => e.a == 'quest' && e.d['own'] == partnerName && e.d['date'] == _today);

  void showQuests() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Nhiệm vụ hôm nay', emoji: '📜', builder: (ctx, setS) {
      final q = _qd;
      final both = questsDone && _partnerQuestDone();
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        const Text('Mỗi ngày 3 nhiệm vụ giống nhau cho cả hai người. Xong hết được 150💰, nếu cả hai cùng xong thì thêm 150💰 nữa.', style: TextStyle(color: Pal.muted, fontSize: 12.5)),
        const SizedBox(height: 10),
        for (final x in todayQuests)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Text(x.$2, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(child: Text(x.$3, style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text))),
                Text(_num(q, x.$1) >= x.$4 ? '✅' : '${min(_num(q, x.$1), x.$4)}/${x.$4}', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.muted)),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Text(_partnerQuestDone() ? '💞 $partnerName đã xong nhiệm vụ hôm nay' : '⏳ $partnerName chưa xong nhiệm vụ', style: const TextStyle(color: Pal.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (q['claim'] != true)
          GButton(questsDone ? 'Nhận thưởng 150💰' : 'Chưa xong nhiệm vụ', emoji: '🎁', onTap: !questsDone
              ? null
              : () {
                  q['claim'] = true;
                  money += 150;
                  Garden.instance.act('quest', {'own': owner, 'date': _today});
                  Sound.sfx('goal');
                  setS(() {});
                  _done('📜 Xong nhiệm vụ hôm nay! +150💰');
                })
        else if (q['both'] != true)
          GButton(both ? 'Cả hai cùng xong: nhận thêm 150💰' : 'Chờ $partnerName xong để nhận thưởng đôi', emoji: '💞', onTap: !both
              ? null
              : () {
                  q['both'] = true;
                  money += 150;
                  Sound.sfx('goal');
                  setS(() {});
                  _done('💞 Hai vợ chồng cùng xong nhiệm vụ! +150💰');
                })
        else
          const Center(child: Text('🎉 Đã nhận hết thưởng hôm nay', style: TextStyle(fontWeight: FontWeight.w900, color: Pal.mint))),
      ]);
    });
  }

  // ------------------------------------------------------------------ mùa vụ
  (String, String, List<String>) get season {
    final m = DateTime.now().month;
    if (isTet()) return ('🧧', 'Tết Nguyên Đán', ['straw', 'orange', 'goldmelon']);
    if (m >= 2 && m <= 4) return ('🌸', 'Mùa xuân', ['straw', 'orange', 'melon']);
    if (m >= 5 && m <= 8) return ('☀️', 'Mùa hè', ['mango', 'melon', 'dragon', 'banana', 'pine']);
    if (m >= 9 && m <= 10) return ('🍂', 'Mùa thu', ['grape', 'apple', 'banana']);
    return ('❄️', 'Mùa đông', ['orange', 'apple', 'straw']);
  }

  // ------------------------------------------------------------------ chợ phiên
  int get soldPortions => _num(ex, 'sold');

  double get marketPrice {
    final w = Crowd.weather;
    var p = 25.0;
    if (w != null && (w.rain || w.storm)) p *= 1.2; // mưa ít hàng, giá lên
    if (w != null && w.temp >= 32) p *= 1.1;
    if (isTet()) p *= 1.5;
    if (hasUp('ao')) p *= 1.2;
    p *= 0.9 + (_hash('mk-$_today') % 30) / 100;
    final wd = DateTime.now().weekday;
    if (wd < 6) p *= 0.7;
    return p;
  }

  bool get marketOpen => DateTime.now().weekday >= 6 || hasUp('kho');

  void showMarket() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Chợ phiên cuối tuần', emoji: '🧺', builder: (ctx, setS) {
      final avail = farmAvail;
      final price = marketPrice;
      final se = season;
      void sell(int n) {
        if (n <= 0) return;
        ex['sold'] = soldPortions + n;
        final m = (n * price).round();
        money += m;
        qAdd('market', 1);
        Sound.sfx('coin');
        setS(() {});
        _done('🧺 Bán $n phần nông sản, thu $m💰');
      }

      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Text(
            marketOpen
                ? 'Thương lái đang ở vườn! Giá hôm nay: ${price.toStringAsFixed(0)}💰 / phần${DateTime.now().weekday < 6 ? ' (kho lạnh, ngày thường)' : ''}.'
                : 'Chợ chỉ họp thứ Bảy và Chủ nhật. Mua ❄️ Kho lạnh để bán cả ngày thường.',
            style: const TextStyle(color: Pal.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('${se.$1} ${se.$2} • đang mùa: ${se.$3.map((id) => speciesById(id).emoji).join(' ')} • trời mưa giá lên 20%, Tết giá lên 50%',
            style: const TextStyle(color: Pal.muted, fontSize: 12)),
        const SizedBox(height: 10),
        Text('📦 Nông sản đang có: $avail phần', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: SoftButton('Bán 6 phần', emoji: '🧺', onTap: marketOpen && avail >= 6 ? () => sell(6) : null)),
          const SizedBox(width: 8),
          Expanded(child: GButton('Bán hết', emoji: '💰', onTap: marketOpen && avail > 0 ? () => sell(avail) : null)),
        ]),
      ]);
    });
  }

  // ------------------------------------------------------------------ quà tặng nhau
  List<GEvent> get unreadPresents {
    final seen = _num(ex, 'pseen');
    return [for (final e in Garden.instance.events) if (e.a == 'present' && e.d['to'] == owner && e.at > seen) e];
  }

  void showGifts() {
    Sound.sfx('tap');
    const items = [
      ('🧺', 'Giỏ trái cây', 0, 60),
      ('💐', 'Bó hoa', 40, 50),
      ('🍫', 'Hộp sô-cô-la', 60, 80),
      ('🥚', 'Rổ trứng gà', 0, 40),
      ('🎂', 'Bánh kem', 100, 130),
      ('🧧', 'Bao lì xì', 100, 120),
    ];
    const msgs = ['Yêu em nhiều ❤️', 'Cố lên nhé! 💪', 'Tối nay ăn gì?', 'Nhớ anh không? 😘', 'Cảm ơn vì đã chăm vườn 🌻'];
    var msg = msgs.first;
    showGameSheet(context, title: 'Quà tặng nhau', emoji: '🎁', builder: (ctx, setS) {
      final inbox = unreadPresents;
      final sentToday = _sub('q')['giftDay'] == _today || ex['giftDay'] == _today;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        if (inbox.isNotEmpty) ...[
          SectionTitle('📬 Quà $partnerName gửi (${inbox.length})'),
          for (final e in inbox)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Text('${e.d['it']}  •  "${e.d['msg']}"', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
              ),
            ),
          GButton('Mở hết quà', emoji: '🎀', onTap: () {
            var gain = 0;
            for (final e in inbox) {
              gain += (e.d['v'] as num?)?.toInt() ?? 50;
            }
            ex['pseen'] = inbox.map((e) => e.at).reduce(max);
            money += gain;
            Sound.sfx('goal');
            setS(() {});
            _done('🎀 Mở quà của $partnerName: +$gain💰');
          }),
          const SizedBox(height: 12),
        ],
        SectionTitle('💌 Gửi quà cho $partnerName', sub: sentToday ? 'Hôm nay đã gửi rồi, mai gửi tiếp nhé' : 'Mỗi ngày gửi được 1 món'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in msgs)
            ChoiceChip(label: Text(m, style: const TextStyle(fontSize: 12)), selected: msg == m, onSelected: (_) => setS(() => msg = m)),
        ]),
        const SizedBox(height: 8),
        for (final it in items)
          if (it.$1 != '🥚' || Garden.instance.state.items.values.any((i) => i.sp == 'chicken' || i.sp == 'duck' || i.sp == 'dongtao'))
            if (it.$1 != '🧺' || farmAvail >= 6)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SoftButton('${it.$1} ${it.$2}${it.$3 > 0 ? ' • ${it.$3}💰' : (it.$1 == '🧺' ? ' • 6 phần nông sản' : ' • từ chuồng gà')}', onTap: sentToday
                    ? null
                    : () {
                        if (it.$3 > 0 && !pay(it.$3)) return;
                        if (it.$1 == '🧺') ex['sold'] = soldPortions + 6;
                        Garden.instance.act('present', {'to': partnerName, 'from': owner, 'it': '${it.$1} ${it.$2}', 'msg': msg, 'v': it.$4});
                        ex['giftDay'] = _today;
                        qAdd('gift', 1);
                        Navigator.pop(ctx);
                        Sound.sfx('goal');
                        _done('${it.$1} Đã gửi ${it.$2} cho $partnerName: "$msg"');
                      }),
              ),
      ]);
    });
  }

  // ------------------------------------------------------------------ vật nuôi thân thiết
  void showPets() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Vật nuôi thân thiết', emoji: '🐾', builder: (ctx, setS) {
      final pets = Garden.instance.state.items.values.where((i) => !i.isPlant && !i.dead).toList();
      final names = _sub('pn'), aff = _sub('aff'), petAt = _sub('petAt'), giftAt = _sub('pgift');
      const products = {
        'chicken': ('🥚', 'trứng'), 'duck': ('🥚', 'trứng vịt'), 'dongtao': ('🥚', 'trứng gà quý'), 'beef': ('🥛', 'sữa'), 'goat': ('🥛', 'sữa dê'),
        'sheep': ('🧶', 'lông cừu'), 'pig': ('💕', 'niềm vui'), 'rabbit': ('🥕', 'cà rốt thừa'),
      };
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        const Text('Đặt tên, vuốt ve mỗi 2 tiếng để con vật quý bạn hơn. Thân từ 3 ❤️ trở lên thì mỗi ngày con vật tặng quà.', style: TextStyle(color: Pal.muted, fontSize: 12.5)),
        const SizedBox(height: 8),
        if (pets.isEmpty) const Text('Chưa nuôi con vật nào. Ra chuồng hoặc ao để thả giống nhé!', style: TextStyle(color: Pal.text)),
        for (final it in pets)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(children: [
                Text(it.s.emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${names[it.uid] ?? it.s.name}', style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
                    Text('${'❤️' * min(5, _num(aff, it.uid) ~/ 2)}${'🤍' * (5 - min(5, _num(aff, it.uid) ~/ 2))}', style: const TextStyle(fontSize: 12)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Đặt tên',
                  icon: const Text('✏️', style: TextStyle(fontSize: 18)),
                  onPressed: () async {
                    final ctl = TextEditingController(text: names[it.uid]?.toString() ?? '');
                    final v = await showDialog<String>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        title: Text('Đặt tên cho ${it.s.name}'),
                        content: TextField(controller: ctl, autofocus: true, maxLength: 16),
                        actions: [TextButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('Lưu'))],
                      ),
                    );
                    if (v != null && v.isNotEmpty) {
                      names[it.uid] = v;
                      setS(() {});
                      _done('');
                    }
                  },
                ),
                SoftButton('Vuốt ve', emoji: '✋', onTap: DateTime.now().millisecondsSinceEpoch - _num(petAt, it.uid) < 2 * 3600000
                    ? null
                    : () {
                        petAt[it.uid] = DateTime.now().millisecondsSinceEpoch;
                        aff[it.uid] = min(10, _num(aff, it.uid) + (hasUp('chuong') ? 2 : 1));
                        qAdd('pet', 1);
                        Sound.sfx('coin', vol: 0.5);
                        setS(() {});
                        _done('💕 ${names[it.uid] ?? it.s.name} thích lắm!');
                      }),
                if (_num(aff, it.uid) >= 6 && giftAt[it.uid] != _today) ...[
                  const SizedBox(width: 4),
                  SoftButton('Quà', emoji: (products[it.sp] ?? ('🫧', 'ngọc trai')).$1, onTap: () {
                    giftAt[it.uid] = _today;
                    final m = 8 * _num(aff, it.uid) * (hasUp('chuong') ? 2 : 1);
                    money += m;
                    setS(() {});
                    _done('${(products[it.sp] ?? ('🫧', 'ngọc trai')).$1} ${names[it.uid] ?? it.s.name} tặng ${(products[it.sp] ?? ('🫧', 'ngọc trai')).$2}, bán được $m💰');
                  }),
                ],
              ]),
            ),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------------ sự cố bất ngờ trong vườn
  (String, String, String, String)? get gardenEvent {
    final now = DateTime.now();
    final win = '${_today}-${now.hour ~/ 3}';
    if (_sub('evd')[win] == true) return null;
    final items = Garden.instance.state.items.values.where((i) => !i.dead).toList();
    if (items.isEmpty) return null;
    final h = _hash('gev-$win') % 6;
    final w = Crowd.weather;
    final hasBird = items.any((i) => i.sp == 'chicken' || i.sp == 'duck' || i.sp == 'dongtao' || i.sp == 'rabbit');
    if (h == 0 && hasBird) return (win, '🦊', 'Cáo đang rình chuồng gà!', 'Đuổi cáo');
    if (h == 1 && items.any((i) => i.isPlant) && !hasUp('bunhin')) return (win, '🐦', 'Đàn chim đang ăn trái!', 'Xua chim');
    if (h == 2 && (w == null || w.rain || w.storm)) return (win, '🌨️', 'Sắp có mưa đá!', 'Che bạt');
    if (h == 3 && items.any((i) => i.s.kind == 'fish')) return (win, '🦦', 'Rái cá lẻn vào ao!', 'Đuổi rái cá');
    return null;
  }

  void handleGardenEvent() {
    final e = gardenEvent;
    if (e == null) return;
    _sub('evd')[e.$1] = true;
    money += 30;
    Sound.sfx('goal');
    _done('${e.$2} ${e.$4} thành công! Vườn an toàn, +30💰');
  }

  /// Máy tưới tự động: tưới cây khát mỗi 3 tiếng khi mở vườn
  void autoWater() {
    if (!hasUp('tuoi')) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _num(ex, 'autoW') < 3 * 3600000) return;
    final list = Garden.instance.state.items.values.where((i) => i.alive && i.isPlant && i.water < 0.7).toList();
    ex['autoW'] = now;
    if (list.isEmpty) return;
    Garden.instance.actMany([for (final i in list) ('water', {'u': i.uid})]);
    snack('💦 Máy tưới đã tưới ${list.length} cây');
  }

  // ------------------------------------------------------------------ nâng cấp vườn
  void showUpgrades() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Nâng cấp vườn', emoji: '🛠️', builder: (ctx, setS) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        for (final u in _upgrades)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Text(u.$2, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.$3, style: const TextStyle(fontWeight: FontWeight.w900, color: Pal.text)),
                    Text(u.$5, style: const TextStyle(color: Pal.muted, fontSize: 11.5)),
                  ]),
                ),
                if (hasUp(u.$1))
                  const Tag('Đã có')
                else
                  PriceButton(u.$4, afford: money >= u.$4, onTap: () {
                    if (!pay(u.$4)) return;
                    _sub('up')[u.$1] = true;
                    Sound.sfx('coin');
                    setS(() {});
                    _done('${u.$2} Đã lắp ${u.$3}');
                  }),
              ]),
            ),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------------ bộ sưu tập
  bool rareUnlocked(String id) {
    final hv = Garden.instance.state.harvests;
    int kinds(String kind) => species.where((s) => s.kind == kind && !rareSpecies.contains(s.id) && (hv[s.id] ?? 0) > 0).length;
    switch (id) {
      case 'goldmelon':
        return kinds('plant') >= 6;
      case 'dongtao':
        return kinds('animal') >= 5;
      case 'koi':
        return kinds('fish') >= 5;
    }
    return true;
  }

  void showAlbum() {
    Sound.sfx('tap');
    final hv = Garden.instance.state.harvests;
    showGameSheet(context, title: 'Bộ sưu tập vườn', emoji: '📖', builder: (ctx, setS) {
      Widget group(String kind, String title, String rare, int need) {
        final list = species.where((s) => s.kind == kind && !rareSpecies.contains(s.id)).toList();
        final got = list.where((s) => (hv[s.id] ?? 0) > 0).length;
        final r = speciesById(rare);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('$title • $got/${list.length}', sub: rareUnlocked(rare) ? '🏅 Đã mở loài hiếm ${r.emoji} ${r.name}' : 'Thu hoạch $need loài khác nhau để mở ${r.emoji} ${r.name}'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in [...list, r])
              Container(
                width: 62,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: (hv[s.id] ?? 0) > 0 ? const Color(0xFFDDF6EF) : const Color(0xFFF2EEE8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: s.id == rare ? Pal.gold : Pal.line, width: s.id == rare ? 2 : 1),
                ),
                child: Column(children: [
                  Opacity(opacity: (hv[s.id] ?? 0) > 0 ? 1 : 0.35, child: Text(s.emoji, style: const TextStyle(fontSize: 24))),
                  Text((hv[s.id] ?? 0) > 0 ? '×${hv[s.id]}' : '?', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Pal.muted)),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
        ]);
      }

      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        group('plant', '🍎 Cây trái', 'goldmelon', 6),
        group('animal', '🐄 Vật nuôi', 'dongtao', 5),
        group('fish', '🐟 Thuỷ sản', 'koi', 5),
      ]);
    });
  }

  /// Dải nút tính năng phía trên khu vườn
  Widget gardenExtrasBar() {
    final se = season;
    final ev = gardenEvent;
    final inbox = unreadPresents.length;
    Widget chip(String label, VoidCallback onTap, {Color? bg}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            color: bg ?? Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Pal.text)),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 6, 12, 2), children: [
        if (ev != null) chip('${ev.$2} ${ev.$3} ${ev.$4}!', handleGardenEvent, bg: const Color(0xFFFFE0E0)),
        chip('${se.$1} ${se.$2}', showMarket, bg: const Color(0xFFFFF3CD)),
        chip(marketOpen ? '🧺 Chợ phiên đang họp' : '🧺 Chợ phiên', showMarket),
        chip(inbox > 0 ? '🎁 Quà ($inbox mới)' : '🎁 Tặng quà', showGifts, bg: inbox > 0 ? const Color(0xFFFFE4F0) : null),
        chip('🐾 Thú thân thiết', showPets),
        chip('🛠️ Nâng cấp', showUpgrades),
        chip('📖 Bộ sưu tập', showAlbum),
        chip('📜 Nhiệm vụ', showQuests),
      ]),
    );
  }

  // ------------------------------------------------------------------ chợ đêm: ném vòng
  bool get isNight {
    final h = DateTime.now().hour;
    return h >= 18 || h < 5;
  }

  void showNightMarket() {
    Sound.sfx('tap');
    final plays = _sub('nm');
    if (!isNight) {
      snack('🎪 Chợ đêm ven sông Cẩm Lệ mở từ 18h tới 5h sáng');
      return;
    }
    var pos = 0.0, dir = 1.0, rings = 3, won = 0;
    String msg = 'Chạm "Ném" khi vòng ở vùng xanh để trúng chai nước!';
    Timer? tm;
    showGameSheet(context, title: 'Chợ đêm • Ném vòng', emoji: '🎪', builder: (ctx, setS) {
      final left = 5 - _num(plays, _today);
      tm ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
        if (!ctx.mounted) {
          tm?.cancel();
          return;
        }
        pos += dir * 0.025;
        if (pos > 1 || pos < 0) dir = -dir;
        setS(() {});
      });
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Text('Còn $left lượt chơi tối nay • vòng còn $rings • trúng $won', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text)),
        const SizedBox(height: 8),
        const Text('🍾 🧸 🍾 🎁 🍾', textAlign: TextAlign.center, style: TextStyle(fontSize: 30)),
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: LayoutBuilder(builder: (_, c) {
            final w = c.maxWidth;
            return Stack(children: [
              Container(decoration: BoxDecoration(color: const Color(0xFFFFE0E0), borderRadius: BorderRadius.circular(13))),
              Positioned(left: w * 0.42, width: w * 0.16, top: 0, bottom: 0, child: Container(color: const Color(0xFF9BE7C4))),
              Positioned(left: (w - 26) * pos.clamp(0.0, 1.0), top: 0, child: const Text('⭕', style: TextStyle(fontSize: 20))),
            ]);
          }),
        ),
        const SizedBox(height: 8),
        Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
        const SizedBox(height: 8),
        GButton(rings > 0 ? 'Ném!' : 'Hết vòng', emoji: '🎯', onTap: rings <= 0 || left <= 0
            ? null
            : () {
                rings--;
                final hit = (pos - 0.5).abs() < 0.09;
                if (hit) {
                  won++;
                  Sound.sfx('coin');
                  msg = '🎉 Trúng rồi!';
                } else {
                  Sound.sfx('wrong');
                  msg = 'Trượt mất rồi 😅';
                }
                if (rings == 0) {
                  plays[_today] = _num(plays, _today) + 1;
                  final prize = [0, 30, 80, 200][won];
                  money += prize;
                  qAdd('nm', 1);
                  msg = won == 0 ? 'Không trúng vòng nào, tối mai thử lại nhé!' : '🎁 Trúng $won vòng, nhận $prize💰!';
                  rings = left - 1 > 0 ? 3 : 0;
                  won = 0;
                  _done('');
                }
                setS(() {});
              }),
      ]);
    }).whenComplete(() => tm?.cancel());
  }

  // ------------------------------------------------------------------ người dân trên phố
  void showNpc(int k) {
    Sound.sfx('tap');
    final n = _npcs[k % _npcs.length];
    final fr = _sub('npcf');
    final done = _sub('npcd')[n.$2] == _today;
    final reqs = [('Mua giúp bà 3 ổ bánh mì', 45), ('Chở giúp chú thùng hàng ra chợ', 60), ('Mang giúp cô sách tới trường', 30)];
    final rq = reqs[k % reqs.length];
    final line = n.$3[(_hash('$_today${n.$2}') % n.$3.length)];
    showGameSheet(context, title: n.$2, emoji: n.$1, builder: (ctx, setS) {
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        AppCard(child: Text('"$line"', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Pal.text))),
        const SizedBox(height: 6),
        Text('Thân thiết: ${'💛' * min(5, _num(fr, n.$2))}${'🤍' * (5 - min(5, _num(fr, n.$2)))}', style: const TextStyle(color: Pal.muted)),
        const SizedBox(height: 10),
        if (done)
          const Text('Hôm nay đã giúp rồi, mai ghé lại nhé!', style: TextStyle(color: Pal.mint, fontWeight: FontWeight.w800))
        else
          GButton('${rq.$1} (bỏ ra ${rq.$2}💰)', emoji: '🤝', onTap: () {
            if (!pay(rq.$2)) return;
            _sub('npcd')[n.$2] = _today;
            fr[n.$2] = _num(fr, n.$2) + 1;
            final reward = rq.$2 * 2 + 10 * _num(fr, n.$2);
            money += reward;
            qAdd('npc', 1);
            Navigator.pop(ctx);
            Sound.sfx('goal');
            _done('${n.$1} ${n.$2} cảm ơn, gửi lại $reward💰');
          }),
      ]);
    });
  }

  // ------------------------------------------------------------------ nhà riêng + xe cộ
  List<String> get homeItems => [for (final f in _furniture) if (_sub('home')[f.$1] == true) f.$1];
  String get vehicle => (ex['veh'] ?? '').toString();
  int get vehicleBonus => _vehicles.where((v) => v.$1 == vehicle).map((v) => v.$5).fold(0, (a, b) => a + b);

  void showHome() {
    Sound.sfx('tap');
    showGameSheet(context, title: 'Nhà của $owner & $partnerName', emoji: '🏡', builder: (ctx, setS) {
      final have = homeItems;
      final rest = _sub('rest')[owner] == _today;
      return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Container(
          height: 130,
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF3E0), Color(0xFFFFF3E0), Color(0xFFD7B48A)], stops: [0, 0.6, 0.6]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Pal.line),
          ),
          child: Center(
            child: have.isEmpty
                ? const Text('Nhà còn trống, mua đồ nội thất bên dưới nhé', style: TextStyle(color: Pal.muted))
                : Wrap(spacing: 10, children: [for (final id in have) Text(_furniture.firstWhere((f) => f.$1 == id).$2, style: const TextStyle(fontSize: 34))]),
          ),
        ),
        const SizedBox(height: 8),
        GButton(rest ? 'Hôm nay đã nghỉ ngơi' : 'Nghỉ ngơi ở nhà (+${20 + 15 * have.length}💰 tiết kiệm)', emoji: '😴', onTap: rest
            ? null
            : () {
                _sub('rest')[owner] = _today;
                money += 20 + 15 * have.length;
                setS(() {});
                _done('😴 Nghỉ ngơi thoải mái, nhà càng đầy đủ tiết kiệm càng nhiều');
              }),
        const SizedBox(height: 10),
        const SectionTitle('🛋️ Nội thất'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in _furniture)
            have.contains(f.$1)
                ? Chip(label: Text('${f.$2} ${f.$3} ✓'))
                : ActionChip(
                    label: Text('${f.$2} ${f.$3} • ${f.$4}💰'),
                    onPressed: () {
                      if (!pay(f.$4)) return;
                      _sub('home')[f.$1] = true;
                      Sound.sfx('coin');
                      setS(() {});
                      _done('${f.$2} Đã mua ${f.$3} cho nhà');
                    }),
        ]),
        const SizedBox(height: 10),
        const SectionTitle('🚦 Xe cộ', sub: 'Có xe đi làm nhanh hơn: thêm giây mỗi ngày ở quán, dọc đường có chuyện vui'),
        for (final v in _vehicles)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Text(v.$2, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(child: Text('${v.$3} • +${v.$5}s mỗi ngày', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.text))),
                if (vehicle == v.$1)
                  const Tag('Đang đi')
                else if (_sub('vehs')[v.$1] == true)
                  SoftButton('Đi xe này', onTap: () {
                    ex['veh'] = v.$1;
                    setS(() {});
                    _done('${v.$2} Đổi sang ${v.$3}');
                  })
                else
                  PriceButton(v.$4, afford: money >= v.$4, onTap: () {
                    if (!pay(v.$4)) return;
                    _sub('vehs')[v.$1] = true;
                    ex['veh'] = v.$1;
                    Sound.sfx('goal');
                    setS(() {});
                    _done('${v.$2} Tậu ${v.$3} mới!');
                  }),
              ]),
            ),
          ),
      ]);
    });
  }

  /// Gọi khi bắt đầu ngày làm: xe giúp tới sớm + chuyện dọc đường
  void commuteBonus() {
    final b = vehicleBonus;
    if (b <= 0) return;
    timeLeft += b;
    final r = Random();
    if (r.nextDouble() < 0.3) {
      const evs = [('Gặp khách quen trên đường, được bo', 30), ('Nhặt được ví, trả lại chủ được hậu tạ', 50), ('Ghé cây xăng được tặng nước', 10)];
      final e = evs[r.nextInt(evs.length)];
      money += e.$2;
      snack('${_vehicles.firstWhere((v) => v.$1 == vehicle).$2} ${e.$1} +${e.$2}💰');
    }
  }
}
