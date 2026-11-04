#!/usr/bin/env python3
"""微糖社群圖卡產生器：和 Claude Design 畫布「微糖社群圖文」同一套樣式。"""
import html
import json, html, datetime
E = html.escape
FONT = ''
W, H = 1080, 1350
TH = {
 'light': dict(bg='#F6F2EC', ink='#1A1717', sub='#5B5550', rule='#DCD5CC', accent='#A63F58', mark_stroke='#1A1717'),
 'dark':  dict(bg='#151213', ink='#F4EEE6', sub='#B9AFA6', rule='#3A3335', accent='#D98A9D', mark_stroke='#F4EEE6'),
 'wine':  dict(bg='#7E2D42', ink='#FBF4EE', sub='#F0D9DF', rule='#9A4A5E', accent='#FBF4EE', mark_stroke='#FBF4EE'),
}
ICON = {
 'heart': '<path d="M32 54 C14 42 8 32 8 23 C8 15 14 10 21 10 C26 10 30 13 32 17 C34 13 38 10 43 10 C50 10 56 15 56 23 C56 32 50 42 32 54Z"/>',
 'cup': '<path d="M12 26h32v14a12 12 0 0 1-12 12h-8a12 12 0 0 1-12-12z"/><path d="M44 30h4a6 6 0 0 1 0 12h-4"/><path d="M22 10c-2 3 2 5 0 9M30 8c-2 3 2 5 0 9M38 10c-2 3 2 5 0 9"/><path d="M8 58h44"/>',
 'shield': '<path d="M32 6l20 8v16c0 14-9 23-20 28C21 53 12 44 12 30V14z"/><path d="M24 31l6 6 11-12"/>',
 'pin': '<path d="M32 58s18-17 18-31a18 18 0 0 0-36 0c0 14 18 31 18 31z"/><circle cx="32" cy="27" r="7"/>',
 'glass': '<path d="M20 8h24l-2 16a10 10 0 0 1-20 0z"/><path d="M32 34v20M22 56h20"/><path d="M21.5 18h21"/>',
 'chat': '<path d="M10 14h44v28H30l-12 10V42h-8z"/><path d="M20 26h24M20 33h14"/>',
 'eye': '<path d="M4 32s10-18 28-18 28 18 28 18-10 18-28 18S4 32 4 32z"/><circle cx="32" cy="32" r="8"/>',
}
def icon(name, size, color, sw=1.6):
    return f'<svg width="{size}" height="{size}" viewBox="0 0 64 64" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{ICON[name]}</svg>'
def mark(t, size=40):
    return f'<svg width="{size}" height="{size}" viewBox="0 0 64 64" aria-hidden="true"><path d="M32 54 C14 42 8 32 8 23 C8 15 14 10 21 10 C26 10 30 13 32 17 Z" fill="#B04A62"/><path d="M32 54 C14 42 8 32 8 23 C8 15 14 10 21 10 C26 10 30 13 32 17 C34 13 38 10 43 10 C50 10 56 15 56 23 C56 32 50 42 32 54Z" fill="none" stroke="{t["mark_stroke"]}" stroke-width="2.2" stroke-linejoin="round"/></svg>'
def br(s): return E(s).replace('\n','<br>')
def footer(t, page=None):
    pg = f'<span style="font-family: \'Noto Sans TC\', sans-serif; font-size: 24px; letter-spacing: 0.2em; color: {t["sub"]}">{page}</span>' if page else '<span></span>'
    return (f'<div style="display: flex; align-items: center; justify-content: space-between; border-top: 1px solid {t["rule"]}; padding-top: 36px">'
            f'<div style="display: flex; align-items: center; gap: 16px">{mark(t)}<span style="font-family: \'Noto Serif TC\', serif; font-size: 30px; letter-spacing: 0.18em; color: {t["ink"]}">微糖</span>'
            f'<span style="font-family: \'Noto Sans TC\', sans-serif; font-size: 22px; letter-spacing: 0.16em; color: {t["sub"]}">1/3 SUGAR</span></div>{pg}</div>')
def doc(title, theme, inner):
    t = TH[theme]
    return f'''<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><title>{E(title)}</title>
<style>{FONTCSS}body{{margin:0}}</style></head><body>
<div style="width: {W}px; height: {H}px; box-sizing: border-box; padding: 96px 96px 80px; display: flex; flex-direction: column; justify-content: space-between; background: {t['bg']}; color: {t['ink']}; font-family: 'Noto Sans TC', 'Noto Sans CJK TC', 'Noto Sans CJK HK', sans-serif; overflow: hidden">
{inner}
</div></body></html>'''
def kicker(t, s): return f'<p style="margin: 0; font-size: 26px; letter-spacing: 0.32em; color: {t["accent"]}">{E(s)}</p>'
def cover(theme, kick, title, sub, ic, page):
    t=TH[theme]
    return doc(title.replace('\n',''), theme, f'''<div style="display: flex; justify-content: space-between; align-items: flex-start">{kicker(t,kick)}{icon(ic,150,t['accent'],1.4)}</div>
<div style="display: flex; flex-direction: column; gap: 44px">
<h1 style="margin: 0; font-family: 'Noto Serif TC', serif; font-weight: 300; font-size: 104px; line-height: 1.32; letter-spacing: 0.04em">{br(title)}</h1>
<div style="width: 72px; height: 2px; background: {t['accent']}"></div>
<p style="margin: 0; font-size: 36px; line-height: 1.7; color: {t['sub']}">{br(sub)}</p>
</div>
{footer(t,page)}''')
def point(theme, num, title, body, page, kick=None):
    t=TH[theme]
    return doc(title, theme, f'''{kicker(t,kick) if kick else '<span></span>'}
<div style="display: flex; flex-direction: column; gap: 40px">
<p style="margin: 0; font-family: 'Noto Serif TC', serif; font-weight: 300; font-size: 200px; line-height: 1; color: {t['accent']}">{E(num)}</p>
<h2 style="margin: 0; font-family: 'Noto Serif TC', serif; font-weight: 500; font-size: 76px; line-height: 1.35; letter-spacing: 0.03em">{br(title)}</h2>
<p style="margin: 0; font-size: 38px; line-height: 1.75; color: {t['sub']}">{br(body)}</p>
</div>
{footer(t,page)}''')
def listslide(theme, kick, title, items, page, url=None):
    t=TH[theme]
    rows=''.join(f'<div style="display: flex; gap: 32px; align-items: baseline; border-bottom: 1px solid {t["rule"]}; padding: 30px 0"><span style="font-family: \'Noto Serif TC\', serif; font-size: 40px; color: {t["accent"]}; min-width: 56px">{E(a)}</span><div style="display: flex; flex-direction: column; gap: 8px"><span style="font-family: \'Noto Serif TC\', serif; font-weight: 500; font-size: 46px">{E(b)}</span>{f"<span style=\"font-size: 32px; line-height: 1.6; color: {t[chr(115)+chr(117)+chr(98)]}\">{E(c)}</span>" if c else ""}</div></div>' for a,b,c in items)
    u = f'<p style="margin: 0; font-size: 32px; letter-spacing: 0.06em; color: {t["accent"]}">{E(url)}</p>' if url else ''
    return doc(title, theme, f'''{kicker(t,kick)}
<div style="display: flex; flex-direction: column; gap: 28px">
<h2 style="margin: 0 0 12px; font-family: 'Noto Serif TC', serif; font-weight: 300; font-size: 84px; line-height: 1.3">{br(title)}</h2>
<div style="display: flex; flex-direction: column">{rows}</div>
{u}
</div>
{footer(t,page)}''')
def quote(theme, kick, text, sub, ic):
    t=TH[theme]
    return doc(text.replace('\n',''), theme, f'''<div style="display: flex; justify-content: space-between; align-items: flex-start">{kicker(t,kick)}{icon(ic,120,t['accent'],1.4)}</div>
<div style="display: flex; flex-direction: column; gap: 48px">
<p style="margin: 0; font-family: 'Noto Serif TC', serif; font-size: 120px; line-height: 0.6; color: {t['accent']}">「</p>
<h1 style="margin: 0; font-family: 'Noto Serif TC', serif; font-weight: 300; font-size: 96px; line-height: 1.4; letter-spacing: 0.04em">{br(text)}</h1>
<p style="margin: 0; font-size: 36px; line-height: 1.75; color: {t['sub']}">{br(sub)}</p>
</div>
{footer(t)}''')
def poll(theme, kick, q, opts):
    t=TH[theme]
    rows=''.join(f'<div style="display: flex; align-items: center; gap: 28px; border: 1.5px solid {t["rule"]}; padding: 30px 36px"><span style="font-family: \'Noto Serif TC\', serif; font-size: 44px; color: {t["accent"]}">{a}</span><span style="font-size: 38px">{E(b)}</span></div>' for a,b in opts)
    return doc(q.replace('\n',''), theme, f'''{kicker(t,kick)}
<div style="display: flex; flex-direction: column; gap: 56px">
<h1 style="margin: 0; font-family: 'Noto Serif TC', serif; font-weight: 300; font-size: 96px; line-height: 1.38">{br(q)}</h1>
<div style="display: flex; flex-direction: column; gap: 20px">{rows}</div>
<p style="margin: 0; font-size: 32px; color: {t['sub']}">留言告訴我們，明天公布結果。</p>
</div>
{footer(t)}''')


FONTCSS = ''
def build_fontcss(fdir):
    import glob, os
    css = []
    for fam, pat in (('Noto Serif TC', 'noto-serif-tc'), ('Noto Sans TC', 'noto-sans-tc')):
        for w in (300, 400, 500):
            for f in sorted(glob.glob(f'{fdir}/@fontsource/{pat}/files/{pat}-*-{w}-normal.woff2')):
                css.append(f"@font-face{{font-family:'{fam}';font-weight:{w};src:url('file://{f}') format('woff2')}}")
    return ''.join(css)

KIND = {'cover': lambda s: cover(s['theme'], s['kicker'], s['title'], s['sub'], s.get('icon','heart'), s.get('page')),
        'point': lambda s: point(s['theme'], s['num'], s['title'], s['body'], s.get('page'), s.get('kicker')),
        'list':  lambda s: listslide(s['theme'], s['kicker'], s['title'], [tuple(x) for x in s['items']], s.get('page'), s.get('url')),
        'quote': lambda s: quote(s['theme'], s['kicker'], s['title'], s['sub'], s.get('icon','heart')),
        'poll':  lambda s: poll(s['theme'], s['kicker'], s['title'], [tuple(x) for x in s['options']])}

if __name__ == '__main__':
    """用法：python3 render.py spec.json 輸出資料夾 [node_modules 路徑]
    spec.json = 投影片清單，每張：{"kind":"cover|point|list|quote|poll","theme":"light|dark|wine", ...}
      cover: kicker,title,sub,icon,page   point: num,title,body,kicker,page
      list: kicker,title,items[[標號,標題,說明]],page,url   quote: kicker,title,sub,icon   poll: kicker,title,options[[A,文字]]
      icon 可用：heart cup shield pin glass chat eye；標題用 \n 換行。輸出 1080x1350 PNG。"""
    import sys, json, os, asyncio
    spec, out = sys.argv[1], sys.argv[2]
    fdir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.getcwd(), 'node_modules')
    FONTCSS = build_fontcss(fdir)
    globals()['FONTCSS'] = FONTCSS
    slides = json.load(open(spec, encoding='utf-8'))
    os.makedirs(out, exist_ok=True)
    from playwright.async_api import async_playwright
    async def run():
        async with async_playwright() as p:
            b = await p.chromium.launch(); pg = await b.new_page(viewport={'width': W, 'height': H})
            for k, s in enumerate(slides, 1):
                f = os.path.join(out, f'slide-{k:02d}.html'); open(f, 'w', encoding='utf-8').write(KIND[s['kind']](s))
                await pg.goto('file://' + os.path.abspath(f)); await pg.evaluate('document.fonts.ready'); await pg.wait_for_timeout(300)
                await pg.evaluate('''() => { for (const h of document.querySelectorAll('h1,h2')) { h.style.whiteSpace = 'nowrap'; let fs = parseFloat(getComputedStyle(h).fontSize); while (h.scrollWidth > h.clientWidth + 1 && fs > 40) { fs -= 2; h.style.fontSize = fs + 'px'; } } }''')   # 標題太長就縮小字級，不讓一行斷開
                await pg.screenshot(path=os.path.join(out, f'slide-{k:02d}.png')); print(os.path.join(out, f'slide-{k:02d}.png'))
            await b.close()
    asyncio.run(run())
