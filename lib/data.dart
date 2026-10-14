class Ing {
  final String id, emoji, name;
  const Ing(this.id, this.emoji, this.name);
}

class Recipe {
  final String id, name, emoji;
  final List<String> ings; // nguyên liệu cần chọn
  final int cook; // giây nấu cơ bản
  final int price; // giá bán
  final int unlock; // chi phí mở khoá (0 = có sẵn)
  const Recipe(this.id, this.name, this.emoji, this.ings, this.cook, this.price, this.unlock);
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
  Upg('tables', 'Bàn ghế mới', '🪑', 'Thêm 1 bàn cho khách (tối đa 12 bàn)', 8, 100),
  Upg('decor', 'Trang trí quán', '🖼️', 'Khách kiên nhẫn hơn, tip nhiều hơn', 4, 120),
  Upg('clean', 'Dụng cụ dọn dẹp', '🧹', 'Bàn bẩn tự được dọn sau vài giây', 3, 180),
];

const venues = [
  Venue('cafe', 'Quán cà phê', '☕', 0, 12, 1.0, [
    Ing('bean', '🫘', 'Cà phê'),
    Ing('milk', '🥛', 'Sữa'),
    Ing('ice', '🧊', 'Đá'),
    Ing('tea', '🍵', 'Trà'),
    Ing('straw', '🍓', 'Dâu'),
    Ing('honey', '🍯', 'Mật ong'),
  ], [
    Recipe('cf_den', 'Cà phê đen', '☕', ['bean'], 3, 20, 0),
    Recipe('cf_sua', 'Cà phê sữa', '🥛', ['bean', 'milk'], 4, 30, 0),
    Recipe('cf_da', 'Cà phê sữa đá', '🧋', ['bean', 'milk', 'ice'], 5, 40, 100),
    Recipe('tra_dau', 'Trà dâu', '🍹', ['tea', 'straw', 'ice'], 5, 45, 200),
    Recipe('sinh_to', 'Sinh tố dâu', '🥤', ['straw', 'milk', 'ice', 'honey'], 7, 65, 350),
  ]),
  Venue('bakery', 'Tiệm bánh', '🥐', 300, 12, 1.0, [
    Ing('flour', '🌾', 'Bột'),
    Ing('egg', '🥚', 'Trứng'),
    Ing('butter', '🧈', 'Bơ'),
    Ing('choco', '🍫', 'Socola'),
    Ing('straw', '🍓', 'Dâu'),
    Ing('cheese', '🧀', 'Phô mai'),
  ], [
    Recipe('banh_mi', 'Bánh mì bơ', '🥖', ['flour', 'butter'], 4, 25, 0),
    Recipe('cookie', 'Cookie socola', '🍪', ['flour', 'butter', 'choco'], 5, 35, 0),
    Recipe('cupcake', 'Cupcake dâu', '🧁', ['flour', 'egg', 'straw'], 6, 50, 150),
    Recipe('cheesecake', 'Cheesecake', '🍰', ['flour', 'egg', 'cheese', 'butter'], 8, 80, 300),
  ]),
  Venue('chinese', 'Nhà hàng Trung', '🥟', 600, 12, 0.95, [
    Ing('rice', '🍚', 'Cơm'),
    Ing('egg', '🥚', 'Trứng'),
    Ing('dough', '🫓', 'Bột bọc'),
    Ing('meat', '🥩', 'Thịt'),
    Ing('veg', '🥬', 'Rau'),
    Ing('noodle', '🍜', 'Mì'),
    Ing('sauce', '🥫', 'Sốt'),
  ], [
    Recipe('com_chien', 'Cơm chiên', '🍚', ['rice', 'egg', 'veg'], 5, 40, 0),
    Recipe('mi_xao', 'Mì xào', '🍜', ['noodle', 'meat', 'veg'], 6, 55, 0),
    Recipe('ha_cao', 'Há cảo', '🥟', ['dough', 'meat', 'veg'], 6, 60, 200),
    Recipe('suon', 'Sườn chua ngọt', '🍖', ['meat', 'sauce', 'rice'], 8, 85, 350),
  ]),
  Venue('mexican', 'Nhà hàng Mexico', '🌮', 900, 12, 0.9, [
    Ing('tortilla', '🫓', 'Vỏ bánh'),
    Ing('meat', '🥩', 'Thịt'),
    Ing('cheese', '🧀', 'Phô mai'),
    Ing('tomato', '🍅', 'Cà chua'),
    Ing('avocado', '🥑', 'Bơ'),
    Ing('chili', '🌶️', 'Ớt'),
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
    Ing('meat', '🥩', 'Thịt'),
    Ing('veg', '🥬', 'Rau'),
    Ing('cheese', '🧀', 'Phô mai'),
    Ing('potato', '🥔', 'Khoai'),
    Ing('sauce', '🥫', 'Sốt'),
  ], [
    Recipe('fries', 'Khoai chiên', '🍟', ['potato', 'sauce'], 4, 30, 0),
    Recipe('hotdog', 'Hotdog', '🌭', ['bun', 'meat', 'sauce'], 5, 45, 0),
    Recipe('burger', 'Burger', '🍔', ['bun', 'meat', 'veg', 'cheese'], 6, 60, 100),
    Recipe('combo', 'Combo burger + khoai', '🍱', ['bun', 'meat', 'cheese', 'potato'], 8, 100, 300),
  ]),
];

Venue venueById(String id) => venues.firstWhere((v) => v.id == id);

Recipe recipeById(String id) => venues.expand((v) => v.recipes).firstWhere((r) => r.id == id);
