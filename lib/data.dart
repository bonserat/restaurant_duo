class Ing {
  final String id, emoji, name;
  final int cut; // số nhát cần thái trên thớt (0 = cho thẳng vào nồi)
  const Ing(this.id, this.emoji, this.name, [this.cut = 0]);
}

class Recipe {
  final String id, name, emoji;
  final List<String> ings; // nguyên liệu cần chọn
  final int cook; // giây nấu cơ bản
  final int price; // giá bán
  final int unlock; // chi phí mở khoá (0 = có sẵn)
  const Recipe(this.id, this.name, this.emoji, this.ings, this.cook, this.price, this.unlock);

  /// Lượng gia vị chuẩn của món (1–3 lần nêm)
  double get salt => 1.0 + id.codeUnits.fold<int>(0, (a, b) => a + b) % 3;
}

class Venue {
  final String id, name, emoji;
  final int cost, maxTables;
  final double spawnMul; // nhỏ = khách đến dồn dập hơn
  final List<Ing> shelf;
  final List<Recipe> recipes;
  const Venue(this.id, this.name, this.emoji, this.cost, this.maxTables, this.spawnMul, this.shelf, this.recipes);
}

class Upg {
  final String id, name, emoji, desc;
  final int max, baseCost;
  const Upg(this.id, this.name, this.emoji, this.desc, this.max, this.baseCost);
  int cost(int level) => baseCost * (level + 1);
}

const upgrades = [
  Upg('stove', 'Nâng cấp bếp / lò / máy pha', '🔥', 'Nấu nhanh hơn 15% mỗi cấp', 4, 150),
  Upg('stations', 'Thêm vị trí nấu', '🍳', 'Nấu thêm 1 món cùng lúc', 2, 200),
  Upg('tables', 'Bàn ghế mới', '🪑', 'Thêm 1 bàn cho khách (tối đa 10 bàn)', 6, 100),
  Upg('decor', 'Trang trí quán', '🖼️', 'Khách kiên nhẫn hơn, tip nhiều hơn', 4, 120),
  Upg('clean', 'Dụng cụ dọn dẹp', '🧹', 'Bàn bẩn tự được dọn sau vài giây', 3, 180),
];

const venues = [
  Venue('cafe', 'Quán cà phê', '☕', 0, 10, 1.0, [
    Ing('bean', '🫘', 'Cà phê'),
    Ing('milk', '🥛', 'Sữa'),
    Ing('ice', '🧊', 'Đá'),
    Ing('tea', '🍵', 'Trà'),
    Ing('straw', '🍓', 'Dâu', 2),
    Ing('honey', '🍯', 'Mật ong'),
  ], [
    Recipe('cf_den', 'Cà phê đen', '☕', ['bean'], 3, 20, 0),
    Recipe('cf_sua', 'Cà phê sữa', '🥛', ['bean', 'milk'], 4, 30, 0),
    Recipe('cf_da', 'Cà phê sữa đá', '🧋', ['bean', 'milk', 'ice'], 5, 40, 100),
    Recipe('tra_dau', 'Trà dâu', '🍹', ['tea', 'straw', 'ice'], 5, 45, 200),
    Recipe('sinh_to', 'Sinh tố dâu', '🥤', ['straw', 'milk', 'ice', 'honey'], 7, 65, 350),
  ]),
  Venue('bakery', 'Tiệm bánh', '🥐', 300, 10, 1.0, [
    Ing('flour', '🌾', 'Bột'),
    Ing('egg', '🥚', 'Trứng'),
    Ing('butter', '🧈', 'Bơ'),
    Ing('choco', '🍫', 'Socola', 1),
    Ing('straw', '🍓', 'Dâu', 2),
    Ing('cheese', '🧀', 'Phô mai', 1),
  ], [
    Recipe('banh_mi', 'Bánh mì bơ', '🥖', ['flour', 'butter'], 4, 25, 0),
    Recipe('cookie', 'Cookie socola', '🍪', ['flour', 'butter', 'choco'], 5, 35, 0),
    Recipe('cupcake', 'Cupcake dâu', '🧁', ['flour', 'egg', 'straw'], 6, 50, 150),
    Recipe('cheesecake', 'Cheesecake', '🍰', ['flour', 'egg', 'cheese', 'butter'], 8, 80, 300),
  ]),
  Venue('chinese', 'Nhà hàng Trung', '🥟', 600, 10, 0.95, [
    Ing('rice', '🍚', 'Cơm'),
    Ing('egg', '🥚', 'Trứng'),
    Ing('dough', '🫓', 'Bột bọc', 1),
    Ing('meat', '🥩', 'Thịt', 3),
    Ing('veg', '🥬', 'Rau', 2),
    Ing('noodle', '🍜', 'Mì'),
    Ing('sauce', '🥫', 'Sốt'),
  ], [
    Recipe('com_chien', 'Cơm chiên', '🍚', ['rice', 'egg', 'veg'], 5, 40, 0),
    Recipe('mi_xao', 'Mì xào', '🍜', ['noodle', 'meat', 'veg'], 6, 55, 0),
    Recipe('ha_cao', 'Há cảo', '🥟', ['dough', 'meat', 'veg'], 6, 60, 200),
    Recipe('suon', 'Sườn chua ngọt', '🍖', ['meat', 'sauce', 'rice'], 8, 85, 350),
  ]),
  Venue('mexican', 'Nhà hàng Mexico', '🌮', 900, 10, 0.9, [
    Ing('tortilla', '🫓', 'Vỏ bánh'),
    Ing('meat', '🥩', 'Thịt', 3),
    Ing('cheese', '🧀', 'Phô mai', 1),
    Ing('tomato', '🍅', 'Cà chua', 2),
    Ing('avocado', '🥑', 'Bơ', 2),
    Ing('chili', '🌶️', 'Ớt', 1),
    Ing('bean', '🫘', 'Đậu'),
  ], [
    Recipe('taco', 'Taco', '🌮', ['tortilla', 'meat', 'tomato'], 5, 45, 0),
    Recipe('burrito', 'Burrito', '🌯', ['tortilla', 'meat', 'bean', 'cheese'], 7, 70, 0),
    Recipe('nachos', 'Nachos', '🧀', ['tortilla', 'cheese', 'chili'], 5, 50, 200),
    Recipe('guac', 'Guacamole', '🥑', ['avocado', 'tomato', 'chili'], 5, 55, 250),
    Recipe('quesa', 'Quesadilla', '🫔', ['tortilla', 'cheese', 'meat', 'chili'], 8, 90, 400),
  ]),
  Venue('truck', 'Xe bán đồ ăn lưu động', '🚚', 1200, 6, 0.6, [
    Ing('bun', '🍞', 'Bánh mì'),
    Ing('meat', '🥩', 'Thịt', 3),
    Ing('veg', '🥬', 'Rau', 2),
    Ing('cheese', '🧀', 'Phô mai', 1),
    Ing('potato', '🥔', 'Khoai', 3),
    Ing('sauce', '🥫', 'Sốt'),
  ], [
    Recipe('fries', 'Khoai chiên', '🍟', ['potato', 'sauce'], 4, 30, 0),
    Recipe('hotdog', 'Hotdog', '🌭', ['bun', 'meat', 'sauce'], 5, 45, 0),
    Recipe('burger', 'Burger', '🍔', ['bun', 'meat', 'veg', 'cheese'], 6, 60, 100),
    Recipe('combo', 'Combo burger + khoai', '🍱', ['bun', 'meat', 'cheese', 'potato'], 8, 100, 300),
  ]),
  // ---------- Nhà hàng riêng: mỗi người chọn 1 trong 3 kiểu ----------
  Venue('poseidon', 'Poseidon – Buffet cua & hải sản', '🦀', 1000, 10, 0.95, [
    Ing('crab', '🦀', 'Cua', 2),
    Ing('shrimp', '🦐', 'Tôm', 1),
    Ing('squid', '🦑', 'Mực', 2),
    Ing('oyster', '🦪', 'Hàu', 1),
    Ing('garlic', '🧄', 'Tỏi', 1),
    Ing('butter', '🧈', 'Bơ'),
    Ing('chili', '🌶️', 'Ớt', 1),
    Ing('onion', '🧅', 'Hành', 1),
    Ing('lemon', '🍋', 'Chanh', 1),
  ], [
    Recipe('ps_cua', 'Cua sốt ớt', '🦀', ['crab', 'chili', 'garlic'], 7, 110, 0),
    Recipe('ps_tom', 'Tôm nướng bơ tỏi', '🦐', ['shrimp', 'butter', 'garlic'], 6, 90, 0),
    Recipe('ps_hau', 'Hàu nướng mỡ hành', '🦪', ['oyster', 'onion', 'butter'], 6, 95, 300),
    Recipe('ps_lau', 'Lẩu hải sản', '🍲', ['crab', 'shrimp', 'squid', 'lemon'], 9, 180, 600),
  ]),
  Venue('goyuhan', 'Goyuhan – Buffet nướng Hàn Quốc', '🥓', 1000, 10, 0.95, [
    Ing('porkb', '🥓', 'Ba chỉ heo', 2),
    Ing('beef', '🥩', 'Bò', 3),
    Ing('lettuce', '🥬', 'Xà lách', 1),
    Ing('garlic', '🧄', 'Tỏi', 1),
    Ing('ksauce', '🫙', 'Sốt Hàn'),
    Ing('kimchi', '🌶️', 'Kim chi'),
    Ing('rice', '🍚', 'Cơm'),
    Ing('egg', '🥚', 'Trứng'),
    Ing('mushroom', '🍄', 'Nấm', 1),
  ], [
    Recipe('gy_bachi', 'Ba chỉ nướng cuốn rau', '🥓', ['porkb', 'lettuce', 'garlic'], 7, 100, 0),
    Recipe('gy_galbi', 'Bò nướng Galbi', '🥩', ['beef', 'ksauce', 'garlic'], 8, 130, 0),
    Recipe('gy_bibim', 'Cơm trộn Bibimbap', '🍚', ['rice', 'egg', 'mushroom', 'kimchi'], 7, 110, 300),
    Recipe('gy_kimchi', 'Canh kim chi hầm', '🍲', ['kimchi', 'porkb', 'mushroom'], 8, 120, 550),
  ]),
  Venue('binhdan', 'Quán nhậu Bình Dân – Chim đồng, heo tộc', '🐦', 1000, 10, 0.95, [
    Ing('bird', '🐦', 'Chim đồng', 3),
    Ing('pig', '🐖', 'Heo tộc', 3),
    Ing('lime', '🍃', 'Lá chanh', 1),
    Ing('lemongrass', '🌿', 'Sả', 2),
    Ing('chili', '🌶️', 'Ớt', 1),
    Ing('honey', '🍯', 'Mật ong'),
    Ing('ginger', '🫚', 'Gừng', 1),
    Ing('sticky', '🍙', 'Xôi'),
  ], [
    Recipe('bd_chimchien', 'Chim đồng chiên giòn', '🐦', ['bird', 'ginger', 'chili'], 7, 100, 0),
    Recipe('bd_chimmat', 'Chim đồng nướng mật ong', '🍯', ['bird', 'honey', 'lemongrass'], 8, 120, 0),
    Recipe('bd_heola', 'Heo tộc nướng lá chanh', '🐖', ['pig', 'lime', 'chili'], 8, 140, 300),
    Recipe('bd_heoxa', 'Heo tộc xào sả ớt & xôi', '🍙', ['pig', 'lemongrass', 'chili', 'sticky'], 9, 170, 550),
  ]),
];

Venue venueById(String id) => venues.firstWhere((v) => v.id == id);

/// 3 kiểu nhà hàng riêng (mỗi chủ quán chỉ chọn được 1)
const sigVenueIds = ['poseidon', 'goyuhan', 'binhdan'];
bool isSigVenue(String id) => sigVenueIds.contains(id);

/// Mô tả ngắn của từng kiểu
const sigBlurb = {
  'poseidon': 'Buffet cua, tôm, mực, hàu tươi sống. Đông khách cuối tuần và ngày lễ.',
  'goyuhan': 'Buffet thịt nướng Hàn Quốc: ba chỉ, bò Galbi, kim chi. Hút khách khi trời mát, mưa.',
  'binhdan': 'Đặc sản chim đồng, heo tộc nướng than. Quán nhậu đông vui khi trời mưa.',
};

Recipe recipeById(String id) => [...venues.expand((v) => v.recipes), ...gardenRecipes].firstWhere((r) => r.id == id);

// =====================================================================
//  KHU VƯỜN CHUNG – cây trái, gia súc, cá. Thu hoạch lần đầu sẽ mở món mới
//  (món từ vườn bán được ở mọi quán).
// =====================================================================
class Species {
  final String id, name, emoji, kind; // kind: plant | animal | fish
  final String baby; // hình lúc còn nhỏ
  final int cost, days, reward; // giá giống, số ngày chăm tốt để lớn, tiền thưởng khi thu hoạch
  const Species(this.id, this.name, this.emoji, this.kind, this.baby, this.cost, this.days, this.reward);
  String get recipeId => 'r_$id';
  double get hours => days * 24.0;
}

const species = [
  Species('melon', 'Dưa hấu', '🍉', 'plant', '🌱', 40, 1, 60),
  Species('mango', 'Xoài cát', '🥭', 'plant', '🌱', 70, 2, 110),
  Species('dragon', 'Thanh long', '🐉', 'plant', '🌵', 80, 2, 120),
  Species('pine', 'Dứa mật', '🍍', 'plant', '🌱', 90, 3, 150),
  Species('duck', 'Vịt bầu', '🦆', 'animal', '🐣', 100, 2, 170),
  Species('beef', 'Bò Wagyu', '🐄', 'animal', '🐮', 220, 4, 320),
  Species('salmon', 'Cá hồi', '🐟', 'fish', '🐠', 120, 2, 190),
  Species('lobster', 'Tôm hùm', '🦞', 'fish', '🦐', 200, 3, 300),
];

Species speciesById(String id) => species.firstWhere((s) => s.id == id, orElse: () => species.first);

/// Nguyên liệu của món từ vườn (các nguyên liệu phụ dùng chung id với kệ các quán)
const gardenIngs = [
  Ing('p_melon', '🍉', 'Dưa hấu', 2),
  Ing('p_mango', '🥭', 'Xoài', 2),
  Ing('p_dragon', '🐉', 'Thanh long', 2),
  Ing('p_pine', '🍍', 'Dứa', 2),
  Ing('p_duck', '🦆', 'Thịt vịt', 3),
  Ing('p_beef', '🥩', 'Bò Wagyu', 3),
  Ing('p_salmon', '🐟', 'Cá hồi', 2),
  Ing('p_lobster', '🦞', 'Tôm hùm', 2),
  Ing('ice', '🧊', 'Đá'),
  Ing('yog', '🥛', 'Sữa chua'),
  Ing('rice', '🍚', 'Cơm'),
  Ing('honey', '🍯', 'Mật ong'),
  Ing('garlic', '🧄', 'Tỏi', 1),
  Ing('butter', '🧈', 'Bơ'),
  Ing('cheese', '🧀', 'Phô mai', 1),
];

const gardenRecipes = [
  Recipe('r_melon', 'Nước ép dưa hấu', '🍉', ['p_melon', 'ice'], 4, 70, 0),
  Recipe('r_mango', 'Sinh tố xoài', '🥭', ['p_mango', 'yog', 'ice'], 6, 95, 0),
  Recipe('r_dragon', 'Thanh long sữa chua', '🐉', ['p_dragon', 'yog'], 5, 90, 0),
  Recipe('r_pine', 'Cơm chiên dứa', '🍍', ['p_pine', 'rice'], 7, 120, 0),
  Recipe('r_duck', 'Vịt quay', '🦆', ['p_duck', 'honey', 'garlic'], 9, 160, 0),
  Recipe('r_beef', 'Bò bít tết Wagyu', '🥩', ['p_beef', 'butter', 'garlic'], 9, 220, 0),
  Recipe('r_salmon', 'Cá hồi nướng', '🐟', ['p_salmon', 'butter'], 7, 150, 0),
  Recipe('r_lobster', 'Tôm hùm phô mai', '🦞', ['p_lobster', 'cheese', 'butter'], 9, 240, 0),
];

/// Sự cố trong vườn: mỗi loại cần một cách xử lý riêng
class GProblem {
  final String id, emoji, name, desc, fix, fixEmoji;
  const GProblem(this.id, this.emoji, this.name, this.desc, this.fix, this.fixEmoji);
}

const gProblems = [
  GProblem('pest', '🐛', 'Sâu bệnh', 'Sâu đang ăn lá, cây ngừng lớn', 'Phun thuốc', '🧴'),
  GProblem('weed', '🌾', 'Cỏ dại', 'Cỏ mọc tranh hết chất dinh dưỡng', 'Nhổ cỏ', '🧤'),
  GProblem('flood', '💦', 'Úng nước', 'Mưa nhiều làm rễ bị úng', 'Khơi rãnh thoát nước', '⛏️'),
  GProblem('burn', '🥵', 'Cháy lá', 'Nắng gắt làm cháy lá', 'Che lưới', '⛱️'),
  GProblem('sick', '🤒', 'Bị bệnh', 'Con vật mệt mỏi, bỏ ăn', 'Tiêm thuốc thú y', '💉'),
  GProblem('flies', '🪰', 'Ruồi muỗi', 'Ruồi muỗi bu đầy chuồng', 'Phun xịt diệt muỗi', '🧯'),
  GProblem('cold', '🥶', 'Nhiễm lạnh', 'Mưa bão làm con vật bị lạnh', 'Sưởi ấm', '🔥'),
  GProblem('algae', '🟢', 'Tảo xanh', 'Tảo phủ kín mặt hồ', 'Vớt tảo', '🥅'),
  GProblem('oxygen', '🫧', 'Thiếu oxy', 'Trời nóng, nước thiếu oxy', 'Bật máy sục khí', '⚙️'),
];

GProblem gProblemById(String id) => gProblems.firstWhere((p) => p.id == id, orElse: () => gProblems.first);

/// Thời tiết mỗi ngày (giống nhau trên cả 2 máy)
class GWeather {
  final String id, emoji, name, effect;
  const GWeather(this.id, this.emoji, this.name, this.effect);
}

const gWeathers = [
  GWeather('sun', '☀️', 'Nắng đẹp', 'Cây uống nước vừa phải, mọi thứ lớn đều'),
  GWeather('hot', '🥵', 'Nắng gắt', 'Cây khát nhanh, dễ cháy lá; hồ cá dễ thiếu oxy'),
  GWeather('rain', '🌧️', 'Mưa', 'Trời tưới hộ cây, nhưng ruộng dễ bị úng'),
  GWeather('storm', '⛈️', 'Mưa bão', 'Cây chậm lớn, gia súc dễ nhiễm lạnh, ruộng dễ úng'),
];

// =====================================================================
//  GIA VỊ – tên theo loại quán
// =====================================================================
String seasonName(String venueId) => (venueId == 'cafe' || venueId == 'bakery') ? 'Đường' : 'Muối';
String seasonEmoji(String venueId) => (venueId == 'cafe' || venueId == 'bakery') ? '🍬' : '🧂';

/// Món ngọt (đồ uống, bánh, tráng miệng) nêm bằng đường; còn lại nêm muối
const _sweetRecipes = {
  'cf_den', 'cf_sua', 'cf_da', 'tra_dau', 'sinh_to', //
  'banh_mi', 'cookie', 'cupcake', 'cheesecake', //
  'r_melon', 'r_mango', 'r_dragon',
};
bool isSweet(String recipeId) => _sweetRecipes.contains(recipeId);

/// Gia vị theo món đang nấu (chưa có món thì theo loại quán)
String seasonNameFor(String? recipeId, String venueId) => recipeId == null ? seasonName(venueId) : (isSweet(recipeId) ? 'Đường' : 'Muối');
String seasonEmojiFor(String? recipeId, String venueId) => recipeId == null ? seasonEmoji(venueId) : (isSweet(recipeId) ? '🍬' : '🧂');

// =====================================================================
//  GIỜ THẬT: ngày / hoàng hôn / đêm
// =====================================================================
/// 0 = ban ngày (6h–17h), 1 = bình minh/hoàng hôn (5h–6h, 17h–18h30), 2 = ban đêm
int realDayPhase([DateTime? now]) {
  final d = now ?? DateTime.now();
  final x = d.hour + d.minute / 60;
  if (x >= 6 && x < 17) return 0;
  if ((x >= 17 && x < 18.5) || (x >= 5 && x < 6)) return 1;
  return 2;
}

String realDayLabel([DateTime? now]) {
  final d = now ?? DateTime.now();
  final h = d.hour;
  final part = h < 5 ? 'Đêm khuya' : (h < 11 ? 'Buổi sáng' : (h < 13 ? 'Buổi trưa' : (h < 17 ? 'Buổi chiều' : (h < 19 ? 'Chiều tối' : (h < 22 ? 'Buổi tối' : 'Đêm khuya')))));
  final hh = d.hour.toString().padLeft(2, '0'), mm = d.minute.toString().padLeft(2, '0');
  return '$hh:$mm • $part';
}

String realDayEmoji([DateTime? now]) {
  final p = realDayPhase(now);
  return p == 0 ? '☀️' : (p == 1 ? '🌇' : '🌙');
}

// =====================================================================
//  KHÁCH ĐẶC BIỆT (NPC) – mỗi người có tính cách, sở thích và câu chuyện
// =====================================================================
class NpcType {
  final String id, emoji, title, name;
  final double patMul, payMul, saltPref, chance;
  final List<String> lines; // câu nói theo số lần ghé quán
  const NpcType(this.id, this.emoji, this.title, this.name, this.patMul, this.payMul, this.saltPref, this.chance, this.lines);
}

const npcTypes = [
  NpcType('vip', '👑', 'Khách VIP', 'Ông Bảy', 0.8, 2.0, 0, 0.08, [
    'Phục vụ cho xứng đáng, tôi trả gấp đôi!',
    'Lần trước ngon đấy. Hôm nay tôi dẫn đối tác tới.',
    'Tôi sẽ ghi quán này vào cẩm nang 5 sao!',
  ]),
  NpcType('critic', '🧐', 'Nhà phê bình', 'Cô Lan', 0.9, 1.2, 0, 0.06, [
    'Tôi viết blog ẩm thực. Gia vị phải thật chuẩn nhé.',
    'Bài trước về quán được 10 nghìn lượt xem đó!',
    'Hôm nay tôi chấm điểm cho chuyên mục "Quán quen".',
  ]),
  NpcType('hunter', '🏹', 'Thợ săn', 'Chú Tư', 1.0, 1.3, 1.0, 0.07, [
    'Đi rừng cả tuần, cho chú món gì đậm đà!',
    'Hôm nay chú gặp con nai to lắm, mà để nó đi rồi.',
    'Ăn ở đây xong chú mới có sức vào rừng.',
  ]),
  NpcType('student', '🎒', 'Học sinh', 'Bé Na', 1.35, 0.7, -0.6, 0.10, [
    'Con để dành tiền ăn sáng để tới đây đó!',
    'Con được điểm 10, mẹ cho đi ăn mừng!',
    'Lớn lên con muốn làm đầu bếp giống anh chị!',
  ]),
  NpcType('stranger', '🕵️', 'Người lạ bí ẩn', 'Người lạ', 1.1, 1.0, 0, 0.03, [
    '…',
    'Mùi vị này… gợi nhớ quán xưa của ta.',
    'Ta từng là bếp trưởng. Giữ lấy món quà này nhé.',
  ]),
];

NpcType? npcById(String id) {
  for (final n in npcTypes) {
    if (n.id == id) return n;
  }
  return null;
}

// =====================================================================
//  THÚ CƯNG
// =====================================================================
class PetType {
  final String id, emoji, name, perk;
  final int cost;
  const PetType(this.id, this.emoji, this.name, this.perk, this.cost);
}

const petTypes = [
  PetType('cat', '🐈', 'Mèo Mướp', 'Nằm cạnh khách đang sốt ruột: khách chờ được lâu hơn', 0),
  PetType('dog', '🐕', 'Chó Vàng', 'Đuổi chuột giúp, đôi khi mang may mắn: khách tip gấp rưỡi', 250),
  PetType('hamster', '🐹', 'Hamster Bông', 'Bùa may mắn: mỗi khách trả thêm 5%', 150),
  PetType('parrot', '🦜', 'Vẹt Xanh', 'Chào khách ở cửa: khách mới kiên nhẫn thêm 10 giây', 200),
];

PetType petById(String id) => petTypes.firstWhere((p) => p.id == id, orElse: () => petTypes.first);

// =====================================================================
//  ĐỒ TRANG TRÍ (kéo thả tự do)
// =====================================================================
class DecoType {
  final String id, emoji, name;
  final int cost;
  final bool wall; // treo tường (chỉ kéo ngang)
  final double size; // kích thước so với bàn
  const DecoType(this.id, this.emoji, this.name, this.cost, this.wall, this.size);
}

const decoTypes = [
  DecoType('plant', '🪴', 'Chậu cây', 40, false, 1.1),
  DecoType('flower', '💐', 'Bình hoa', 50, false, 0.9),
  DecoType('tree', '🌳', 'Cây lớn', 120, false, 1.7),
  DecoType('bar', '🍸', 'Quầy bar', 300, false, 1.0),
  DecoType('piano', '🎹', 'Đàn piano', 400, false, 1.5),
  DecoType('fish', '🐠', 'Bể cá', 250, false, 1.2),
  DecoType('books', '📚', 'Kệ sách', 120, false, 1.2),
  DecoType('sofa', '🛋️', 'Ghế sofa chờ', 200, false, 1.5),
  DecoType('statue', '🗿', 'Tượng đá', 180, false, 1.3),
  DecoType('frame', '🖼️', 'Tranh treo tường', 80, true, 1.0),
  DecoType('clock', '🕰️', 'Đồng hồ', 90, true, 1.0),
  DecoType('lantern', '🏮', 'Đèn lồng', 60, true, 1.0),
  DecoType('light', '💡', 'Đèn treo', 70, true, 1.0),
];

DecoType decoById(String id) => decoTypes.firstWhere((d) => d.id == id, orElse: () => decoTypes.first);

/// Kiểu ánh sáng của quán
const lightModes = [
  ['day', '☀️ Ban ngày'],
  ['warm', '🕯️ Ấm áp'],
  ['romantic', '🌙 Lãng mạn'],
  ['disco', '🪩 Sôi động'],
];

// =====================================================================
//  SỰ CỐ BẤT NGỜ và dụng cụ xử lý
// =====================================================================
class IncidentType {
  final String id, emoji, name, tool, toolEmoji, toolName, hint;
  final int hp; // số lần dùng dụng cụ
  final bool kitchen; // xảy ra ở bếp (đầu bếp xử lý) hay sảnh (phục vụ xử lý)
  const IncidentType(this.id, this.emoji, this.name, this.tool, this.toolEmoji, this.toolName, this.hint, this.hp, this.kitchen);
}

const incidentTypes = [
  IncidentType('fire', '🔥', 'Cháy bếp', 'ext', '🧯', 'Bình chữa cháy', 'Chọn 🧯 rồi chạm vào bếp đang cháy', 4, true),
  IncidentType('power', '⚡', 'Mất điện', 'fuse', '🔌', 'Cầu dao', 'Chọn 🔌 rồi chạm hộp cầu dao góc trên bếp', 1, true),
  IncidentType('rat', '🐀', 'Chuột chạy qua', 'broom', '🧹', 'Chổi', 'Chọn 🧹 rồi chạm trúng con chuột', 2, false),
  IncidentType('leak', '💧', 'Rò rỉ nước', 'wrench', '🔧', 'Cờ lê', 'Chọn 🔧 rồi chạm vào vũng nước', 3, false),
  IncidentType('brawl', '💢', 'Khách gây gổ', 'tea', '🍵', 'Trà xoa dịu', 'Chọn 🍵 rồi chạm vào bàn khách đang nổi nóng', 3, false),
];

IncidentType incidentType(String id) => incidentTypes.firstWhere((t) => t.id == id, orElse: () => incidentTypes.first);
