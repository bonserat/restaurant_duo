# Chụp màn hình game (bản web) ở chế độ thử nghiệm, dùng trong workflow "Screenshots"
import sys, time
from playwright.sync_api import sync_playwright

venues = sys.argv[1].split(',')
with sync_playwright() as p:
    b = p.chromium.launch(args=['--use-gl=swiftshader', '--enable-unsafe-swiftshader'])
    for v in venues:
        pg = b.new_page(viewport={'width': 390, 'height': 844}, device_scale_factor=2)
        logs = []
        pg.on('console', lambda m: logs.append(m.text))
        pg.goto(f'http://localhost:8000/?demo=1&v={v}&t=6', wait_until='load')
        time.sleep(28)
        pg.screenshot(path=f'shots/{v}.png')
        open(f'shots/{v}.log', 'w').write('\n'.join(logs[-80:]))
        pg.close()
    b.close()
