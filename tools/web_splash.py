# Chèn màn hình chờ vào web/index.html (hiện trong lúc game đang tải, tự tắt khi game vẽ khung hình đầu)
import re, sys
p = sys.argv[1] if len(sys.argv) > 1 else 'web/index.html'
s = open(p, encoding='utf-8').read()
if 'id="splash"' in s:
    sys.exit(0)
css = """<style>
  html, body { background: #221B3F; margin: 0; }
  #splash { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
    justify-content: center; background: linear-gradient(160deg, #221B3F, #3A2F66); color: #fff;
    font-family: -apple-system, system-ui, sans-serif; z-index: 0; }
  #splash .logo { width: 110px; height: 110px; border-radius: 26px; box-shadow: 0 10px 30px rgba(0,0,0,.35); animation: bob 1.2s ease-in-out infinite; }
  #splash .name { font-size: 26px; font-weight: 800; margin-top: 10px; }
  #splash .sub { font-size: 14px; opacity: .7; margin-top: 6px; }
  #splash .bar { width: 160px; height: 6px; border-radius: 3px; background: rgba(255,255,255,.15); margin-top: 22px; overflow: hidden; }
  #splash .bar i { display: block; width: 40%; height: 100%; border-radius: 3px; background: #FF9A3D; animation: run 1.1s ease-in-out infinite; }
  @keyframes bob { 0%,100% { transform: translateY(0) } 50% { transform: translateY(-10px) } }
  @keyframes run { 0% { transform: translateX(-100%) } 100% { transform: translateX(260%) } }
</style>
"""
div = """<div id="splash"><img class="logo" src="icons/Icon-192.png" alt=""><div class="name">Nhà Hàng Đôi</div>
<div class="sub">Nguyên &amp; Ngọc Anh • đang mở quán…</div><div class="bar"><i></i></div></div>
<script>window.addEventListener('flutter-first-frame', function () { var e = document.getElementById('splash'); if (e) e.remove(); });</script>
"""
s = s.replace('</head>', css + '</head>', 1)
s = re.sub(r'(<body[^>]*>)', lambda m: m.group(1) + '\n' + div, s, count=1)
open(p, 'w', encoding='utf-8').write(s)
print('splash added')
