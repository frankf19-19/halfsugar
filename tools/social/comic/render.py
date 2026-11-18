import sys,glob,os
from playwright.sync_api import sync_playwright
files=sorted(glob.glob(sys.argv[1]))
with sync_playwright() as p:
    b=p.chromium.launch(); pg=b.new_page(viewport={'width':1080,'height':1350})
    for f in files:
        pg.goto('file://'+os.path.abspath(f)); pg.wait_for_timeout(900)
        pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(300)
        pg.screenshot(path=f.replace('.html','.png')); print(f)
    b.close()
