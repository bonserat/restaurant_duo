# Gắn tên + biểu tượng riêng của game vào bản web (chạy trong bước build GitHub)
import json, os, re, shutil, sys
web = sys.argv[1] if len(sys.argv) > 1 else 'web'
src = 'branding/web'
for root, _, files in os.walk(src):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), src)
        dst = os.path.join(web, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(root, f), dst)

mp = os.path.join(web, 'manifest.json')
m = json.load(open(mp, encoding='utf-8')) if os.path.exists(mp) else {}
m.update({
    'name': 'Nhà Hàng Đôi',
    'short_name': 'Nhà Hàng Đôi',
    'description': 'Nhà hàng của Nguyên & Ngọc Anh',
    'background_color': '#221B3F',
    'theme_color': '#FF6A47',
    'display': 'standalone',
    'orientation': 'portrait-primary',
    'icons': [
        {'src': 'icons/Icon-192.png', 'sizes': '192x192', 'type': 'image/png'},
        {'src': 'icons/Icon-512.png', 'sizes': '512x512', 'type': 'image/png'},
        {'src': 'icons/Icon-maskable-192.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'maskable'},
        {'src': 'icons/Icon-maskable-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'maskable'},
    ],
})
json.dump(m, open(mp, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)

ip = os.path.join(web, 'index.html')
s = open(ip, encoding='utf-8').read()
s = re.sub(r'<title>.*?</title>', '<title>Nhà Hàng Đôi</title>', s, flags=re.S)
s = re.sub(r'\s*<link rel="apple-touch-icon"[^>]*>', '', s)
s = re.sub(r'\s*<meta name="apple-mobile-web-app-title"[^>]*>', '', s)
s = re.sub(r'\s*<meta content="[^"]*" name="apple-mobile-web-app-title"[^>]*>', '', s)
s = re.sub(r'\s*<meta name="theme-color"[^>]*>', '', s)
s = s.replace('</head>', '''  <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
  <meta name="apple-mobile-web-app-title" content="Nhà Hàng Đôi">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="theme-color" content="#221B3F">
  <script>
    // Giới hạn độ nét ở mức x2: màn Retina x3 phải vẽ gấp ~2,25 lần điểm ảnh mà mắt khó thấy khác
    (function () {
      var r = window.devicePixelRatio || 1;
      if (r > 2) {
        try { Object.defineProperty(window, 'devicePixelRatio', { get: function () { return 2; }, configurable: true }); } catch (e) {}
      }
    })();
  </script>
</head>''', 1)
open(ip, 'w', encoding='utf-8').write(s)
print('branding ok')
