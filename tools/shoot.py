# Chụp màn hình game (bản web) ở chế độ thử nghiệm, dùng trong workflow "Screenshots".
# Tham số: danh sách trang, cách nhau bằng ';'. Mỗi trang là chuỗi query, ví dụ "demo=1&v=goyuhan&t=6".
import sys, time, re
from playwright.sync_api import sync_playwright

pages = [x for x in sys.argv[1].split(';') if x.strip()]
with sync_playwright() as p:
    b = p.chromium.launch(args=['--use-gl=swiftshader', '--enable-unsafe-swiftshader'])
    for q in pages:
        name = re.sub(r'[^a-z0-9]+', '_', q.lower()).strip('_')
        pg = b.new_page(viewport={'width': 390, 'height': 844}, device_scale_factor=2)
        logs = []
        pg.on('console', lambda m: logs.append(m.text))
        pg.goto(f'http://localhost:8000/?{q}', wait_until='load')
        time.sleep(28)
        pg.screenshot(path=f'shots/{name}.png')
        open(f'shots/{name}.log', 'w').write('\n'.join(logs[-80:]))
        pg.close()
    b.close()
