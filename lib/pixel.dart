// Sprite điểm ảnh (pixel art) cho cây và ô tô trên bản đồ và quanh phòng.
// Mỗi sprite là lưới ký tự; vẽ một lần thành Picture rồi dùng lại.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class _Sprite {
  final List<String> rows;
  final Map<String, Color> pal;
  final bool faceRight; // đầu xe quay sang phải
  const _Sprite(this.rows, this.pal, {this.faceRight = true});
}

const _k = Color(0xFF14142E);
const _carBase = {
  'k': _k,
  'b': Color(0xFFF2453D),
  'd': Color(0xFFC0302B),
  'l': Color(0xFFFF7A70),
  'w': Color(0xFF29B6F6),
  'h': Color(0xFFB3E5FC),
  't': Color(0xFF37474F),
  'r': Color(0xFFB0BEC5),
  'y': Color(0xFFFFD54F),
  'R': Color(0xFFE53935),
};

const _sprites = <String, _Sprite>{
  'sedan': _Sprite([
    '....kkkkkkkk......',
    '...kllllllllk.....',
    '..klwwhkwwhwlk....',
    '..kbwhwkwhwwbbk...',
    '.kbbbbbkbbbbbbbbk.',
    'kRbbbbbkbbbbbbbbyk',
    'kddkkkdddddkkkdddk',
    '.kktrtkkkkktrtkkk.',
    '...kkk.....kkk....',
  ], _carBase),
  'pickup': _Sprite([
    '......kkkkkkk.......',
    '.....kwwhkwwhk......',
    '....kwwhwkwhwwk.....',
    'kkkkbbbbbkbbbbbkkkkk',
    'kybbbbbbbkbbbbbbbbRk',
    'kybbbbbbbkbbbbbbbbbk',
    'kdddkkkddddddkkkdddk',
    '.kkktrtkkkkkkktrtkk.',
    '....kkk.......kkk...',
  ], _carBase, faceRight: false),
  'sport': _Sprite([
    '......kkkkk.......',
    '....kkwwhwbk...kk.',
    '..kkbwhwwwbbkkkbk.',
    'kkbbbbbbbbbbbbbbbk',
    'kybblllbbbbbbbbbRk',
    'kdddkkkdddddkkkddk',
    '.kktrtkkkkkkktrtk.',
    '...kkk.......kkk..',
  ], _carBase, faceRight: false),
  'tree': _Sprite([
    '......kkkk......',
    '....kkGGGGkk....',
    '...kGGGgGGgmk...',
    '..kGGgggGgggmk..',
    '.kGgggtgggtggmk.',
    '.kGggggtgtgggmk.',
    'kGggmggtttggmmmk',
    'kggmmgggtgggmmmk',
    'kggggggtttgggmmk',
    '.kmggggtttggmmk.',
    '..kmmgmtttmmmk..',
    '...kkmmtttmkk...',
    '.....kktTtkk....',
    '.......tTt......',
    '.......tTt......',
    '......ttTtt.....',
  ], {
    'k': Color(0xFF1B3A1A),
    'G': Color(0xFF8FD14F),
    'g': Color(0xFF6DB33F),
    'm': Color(0xFF4E8F2E),
    't': Color(0xFF4A2A10),
    'T': Color(0xFF7A4A22),
  }),
  'bush': _Sprite([
    '....GgGG.G....',
    '..GgGGgmgGG...',
    '.gGmgGGgmmgG..',
    'gmgGgmmgGgmgG.',
    'mgGgmgGGmgmgGg',
    '.mmgGmgmgGmmg.',
    '..mm.gtmg.mm..',
    '.....ttt......',
    '......tT......',
    '......tT......',
    '......tT......',
    '.....ttTt.....',
  ], {
    'G': Color(0xFF8CC063),
    'g': Color(0xFF4F9442),
    'm': Color(0xFF2A4D29),
    't': Color(0xFF8A5523),
    'T': Color(0xFFC96A2B),
  }),
};

final Map<String, ui.Picture> _cache = {};

ui.Picture _pic(String id, Map<String, Color> over) {
  final key = '$id|${over.entries.map((e) => '${e.key}${e.value.hashCode}').join(',')}';
  return _cache.putIfAbsent(key, () {
    final sp = _sprites[id]!;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final p = Paint()..isAntiAlias = false;
    for (var y = 0; y < sp.rows.length; y++) {
      final r = sp.rows[y];
      for (var x = 0; x < r.length; x++) {
        final ch = r[x];
        if (ch == '.') continue;
        final col = over[ch] ?? sp.pal[ch];
        if (col == null) continue;
        p.color = col;
        c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.04, 1.04), p);
      }
    }
    return rec.endRecording();
  });
}

/// Vẽ sprite [id] với đáy giữa tại [bottom], cao [height] pixel.
/// [faceRight]: hướng đầu xe mong muốn (chỉ có ý nghĩa với xe).
void drawPixelSprite(Canvas c, String id, Offset bottom, double height, {bool? faceRight, Map<String, Color> recolor = const {}}) {
  final sp = _sprites[id];
  if (sp == null) return;
  final rows = sp.rows.length, cols = sp.rows.first.length;
  final s = height / rows;
  final flip = faceRight != null && faceRight != sp.faceRight;
  c.save();
  c.translate(bottom.dx, bottom.dy - height);
  c.scale(flip ? -s : s, s);
  c.translate(-cols / 2, 0);
  c.drawPicture(_pic(id, recolor));
  c.restore();
}

/// Bảng màu thân xe từ một màu chính
Map<String, Color> carColors(Color body) => {
      'b': body,
      'd': Color.lerp(body, Colors.black, 0.25)!,
      'l': Color.lerp(body, Colors.white, 0.3)!,
    };

/// Cây pixel: kind 0 thường, 1 có trái cam, 2 hoa hồng; [alt] chọn dáng cây
void drawPixelTree(Canvas c, Offset bottom, double height, {int kind = 0, bool alt = false}) {
  final id = alt ? 'bush' : 'tree';
  Map<String, Color> rc = const {};
  if (kind == 2) {
    rc = const {'G': Color(0xFFFFC1D9), 'g': Color(0xFFF48FB1), 'm': Color(0xFFD25C8C)};
  } else if (kind == 1) {
    rc = const {'G': Color(0xFFFFA726)};
  }
  c.drawOval(Rect.fromCenter(center: bottom, width: height * 0.8, height: height * 0.22), Paint()..color = const Color(0x33000000));
  drawPixelSprite(c, id, bottom, height, recolor: rc);
}
