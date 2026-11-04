#!/usr/bin/env python3
"""微糖社群圖卡產生器 v2「白紙黑字・幽默版」
用法：python3 render.py spec.json 輸出資料夾 [node_modules 路徑]
spec.json = 圖卡清單，每張一個物件，kind 決定模板：

  receipt  收據（約會提案）：{"kind":"receipt","title":"微糖提案所","no":"NO.0001 ・ 11/08 (六) 19:30","sub":"第一次見面",
            "items":[["飯店大廳酒吧 ×1","安靜、離捷運近"],...],"totals":[["小計","聊不來也不尷尬"],["服務費","自己安排交通"]],
            "total":["合計","一個好印象"],"notes":["＊本收據不可兌換任何承諾。","＊離開前，跟朋友報個平安。"],
            "stamp":"期待已說清楚","big":"第一次見面，約一杯，不約晚餐。"}
  retro    復古招牌（本土幽默）：{"kind":"retro","shop":"微糖老派約會所","since":"自 2026 年起","h1":"老派約會\\n限時供應",
            "items":[["準時到","基本"],...],"tag":"不談錢・不過夜","foot_b":"本店不接受預付、訂金、車馬費。","foot":"見面前談錢者，恕不招待。被騙請撥 165。"}
  weather  天氣 App（兩性觀點）：{"kind":"weather","time":"21:40","loc":"台北・約會後","pct":"70","cond":"先傳訊息降雨機率","hl":"最高：想傳　最低：怕太快",
            "hours":[["21:00","moon","到家"],...]（icon: moon cloud rain sun）,"days":[["第二次見面","sun","晚餐","85%"],...],
            "feel":"體感：有點想傳","vis":"能見度：把期待說清楚就好了"}
  lock     鎖定畫面通知（小劇情）：{"kind":"lock","carrier":"台灣大哥大","date":"11月8日 星期六","clock":"23:12",
            "notifs":[["行事曆","#E8503A","📅","19:30 一杯・飯店大廳酒吧","已結束","3 小時前"],...],"bottom":"向上滑動以回覆（或先睡一覺）"}
  neon     霓虹燈（酒吧門口）：{"kind":"neon","big":"一杯","line":"OPEN 19:30 – 20:30","small":"不約晚餐・不談錢・不過夜","cap":"第一次見面的營業時間"}

標題用 \\n 換行。輸出 1080×1350 PNG（IG 4:5；Threads 也可直接用）。
"""
import html, json, os, sys, glob
E = html.escape

MARK = '<svg width="30" height="30" viewBox="0 0 64 64"><path d="M32 54 C14 42 8 32 8 23 C8 15 14 10 21 10 C26 10 30 13 32 17 Z" fill="#B04A62"/><path d="M32 54 C14 42 8 32 8 23 C8 15 14 10 21 10 C26 10 30 13 32 17 C34 13 38 10 43 10 C50 10 56 15 56 23 C56 32 50 42 32 54Z" fill="none" stroke="currentColor" stroke-width="3"/></svg>'
FONTCSS = ''

def base():
    return (f"<style>{FONTCSS}*{{box-sizing:border-box}}body{{margin:0;width:1080px;height:1350px;font-family:'Noto Sans TC',sans-serif;overflow:hidden;position:relative}}"
            ".mono{font-family:'DejaVu Sans Mono','Noto Sans TC',monospace}</style>")

def brand(col='#F7F2EA', pos='top:56px;left:64px'):
    return f'<div style="position:absolute;{pos};color:{col};display:flex;gap:12px;align-items:center;font-size:24px;letter-spacing:.22em">{MARK}微糖 <span style="font-size:18px;opacity:.6">1/3 SUGAR</span></div>'

def br(s): return E(s).replace('\n', '<br>')

def doc(inner, style):
    return f'<!doctype html><html><head><meta charset=utf-8>{base()}<style>{style}</style></head><body>{inner}</body></html>'

# ---------- receipt ----------
def _zig(top):
    pts = []
    for i in range(0, 101, 3):
        y = '0' if (i // 3) % 2 == 0 else '12px'
        pts.append(f'{i}% {y}' if top else f'{100 - i}% calc(100% - {"0px" if (i // 3) % 2 == 0 else "12px"})')
    return ','.join(pts)
CLIP = f'polygon({_zig(True)},{_zig(False)})'
BARS = [3,6,2,4,2,8,3,2,6,2,4,3,7,2,2,5,3,6,2,4,8,2,3,5,2,6,3,2,4,7,2,3,6,2,5,3,2,8,4,2]

def receipt(s):
    rows = ''.join(f'<div class=row><span>{E(a)}</span><span>{E(b)}</span></div>' for a, b in s.get('items', []))
    tots = ''.join(f'<div class=row><span>{E(a)}</span><span>{E(b)}</span></div>' for a, b in s.get('totals', []))
    notes = '<br>'.join(E(n) for n in s.get('notes', []))
    bars = ''.join(f'<i style="width:{w}px"></i>' for w in BARS)
    tot = s.get('total', ['合計', ''])
    style = f'''
body{{background:#3A2E2A;background-image:radial-gradient(ellipse at 30% 20%,#55433c 0%,#3A2E2A 55%,#2a211e 100%)}}
.table{{position:absolute;inset:0;background:repeating-linear-gradient(90deg,rgba(255,255,255,.015) 0 6px,transparent 6px 14px)}}
.paper{{position:absolute;left:235px;top:120px;width:610px;background:linear-gradient(180deg,#FCFBF7 0%,#F3F0E8 100%);color:#2a2622;padding:60px 44px 46px;transform:rotate(-3deg);box-shadow:0 30px 60px rgba(0,0,0,.5);clip-path:{CLIP}}}
.paper:before{{content:'';position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(0,0,0,.025) 0 2px,transparent 2px 5px);pointer-events:none}}
.c{{text-align:center}} .t{{font-size:36px;letter-spacing:.34em;font-weight:500}} .s{{font-size:20px;letter-spacing:.22em;color:#6a645c;margin-top:10px}}
.hr{{border-top:2px dashed #9b958c;margin:20px 0}}
.row{{display:flex;justify-content:space-between;font-size:28px;line-height:1.3;padding:7px 0}} .row span:last-child{{color:#4d4844;text-align:right}}
.tot{{display:flex;justify-content:space-between;font-size:38px;font-weight:700;padding-top:10px}}
.note{{font-size:21px;color:#6a645c;line-height:1.7;margin-top:22px}}
.bar{{display:flex;gap:3px;justify-content:center;margin-top:28px}} .bar i{{display:block;height:64px;background:#222}}
.stamp{{position:absolute;right:40px;bottom:150px;transform:rotate(-12deg);border:5px solid #A63F58;color:#A63F58;border-radius:10px;padding:8px 18px;font-size:34px;font-weight:700;letter-spacing:.2em;opacity:.78;mix-blend-mode:multiply}}
.ring{{position:absolute;left:600px;top:95px;width:250px;height:250px;border-radius:50%;border:14px solid rgba(150,95,45,.28);box-shadow:inset 0 0 0 5px rgba(150,95,45,.10);mix-blend-mode:multiply;z-index:3}}
.big{{position:absolute;left:0;right:0;bottom:46px;text-align:center;color:#F7F2EA;font-family:'Noto Serif TC',serif;font-weight:300;font-size:50px;letter-spacing:.06em}}'''
    inner = f'''<div class=table></div>{brand()}
<div class=paper><div>
<div class=c><div class=t>{E(s.get('title','微糖提案所'))}</div><div class="s mono">{E(s.get('no',''))}</div><div class=s>{E(s.get('sub',''))}</div></div>
<div class=hr></div>{rows}<div class=hr></div>{tots}
<div class=tot><span>{E(tot[0])}</span><span>{E(tot[1])}</span></div>
<div class=hr></div><div class=note>{notes}</div>
<div class=bar>{bars}</div><div class="c s mono" style="margin-top:10px">ONETHIRDSUGAR.COM</div>
</div>{f'<div class=stamp>{E(s["stamp"])}</div>' if s.get('stamp') else ''}</div>
<div class=ring></div><div class=big>{br(s.get('big',''))}</div>'''
    return doc(inner, style)

# ---------- retro sign ----------
def retro(s):
    items = ''.join(f'<div class=item><span>{E(a)}</span><span>{E(b)}</span></div>' for a, b in s.get('items', []))
    style = '''
body{background:#E8DCC3;padding:60px}
.board{height:100%;background:#C8102E;border:16px solid #F3E7C9;outline:10px solid #C8102E;padding:50px 54px;color:#F3E7C9;display:flex;flex-direction:column;position:relative}
.top{display:flex;justify-content:space-between;align-items:center;font-size:26px;letter-spacing:.4em;border-bottom:4px solid #F3E7C9;padding-bottom:22px}
h1{position:absolute;left:60px;top:150px;margin:0;font-size:124px;font-weight:900;line-height:1.15;letter-spacing:.08em;writing-mode:vertical-rl;height:720px}
.right{position:absolute;left:400px;top:170px;width:470px}
.item{display:flex;justify-content:space-between;font-size:34px;font-weight:700;padding:16px 0;border-bottom:3px dotted rgba(243,231,201,.6)} .item span:last-child{font-weight:400}
.foot{margin-top:auto;font-size:28px;line-height:1.6;letter-spacing:.06em} .foot b{font-size:40px;display:block;font-weight:900;margin-bottom:10px}
.tag{position:absolute;right:54px;top:740px;background:#F3E7C9;color:#C8102E;font-size:30px;font-weight:900;padding:14px 18px;writing-mode:vertical-rl;letter-spacing:.2em}
.b{position:absolute;right:54px;bottom:50px;display:flex;align-items:center;gap:10px;font-size:22px;letter-spacing:.2em}'''
    inner = f'''<div class=board>
<div class=top><span>{E(s.get('shop','微糖老派約會所'))}</span><span>{E(s.get('since','自 2026 年起'))}</span></div>
<h1>{br(s.get('h1',''))}</h1><div class=right>{items}</div>
{f'<div class=tag>{E(s["tag"])}</div>' if s.get('tag') else ''}
<div class=foot><b>{E(s.get('foot_b',''))}</b>{E(s.get('foot',''))}</div>
<div class=b>{MARK}微糖 1/3 SUGAR</div></div>'''
    return doc(inner, style)

# ---------- weather app ----------
ICON = {'cloud': '<path d="M20 44h26a10 10 0 0 0 1-20 14 14 0 0 0-27 4 8 8 0 0 0 0 16z" fill="none" stroke="#F4F1EA" stroke-width="3" stroke-linejoin="round"/>',
        'rain': '<path d="M20 38h26a10 10 0 0 0 1-20 14 14 0 0 0-27 4 8 8 0 0 0 0 16z" fill="none" stroke="#F4F1EA" stroke-width="3" stroke-linejoin="round"/><path d="M24 46l-3 8M34 46l-3 8M44 46l-3 8" stroke="#9EC5FF" stroke-width="3" stroke-linecap="round"/>',
        'sun': '<circle cx="32" cy="32" r="11" fill="none" stroke="#FFD66B" stroke-width="3"/><g stroke="#FFD66B" stroke-width="3" stroke-linecap="round"><path d="M32 8v8M32 48v8M8 32h8M48 32h8M15 15l6 6M43 43l6 6M49 15l-6 6M21 43l-6 6"/></g>',
        'moon': '<path d="M40 10a20 20 0 1 0 14 30 16 16 0 0 1-14-30z" fill="none" stroke="#F4F1EA" stroke-width="3"/>'}
def ic(n, sz=44): return f'<svg width="{sz}" height="{sz}" viewBox="0 0 64 64">{ICON.get(n, ICON["cloud"])}</svg>'

def weather(s):
    hours = ''.join(f'<div class=h><div class=m>{E(t)}</div>{ic(i)}<div class=l>{E(l)}</div></div>' for t, i, l in s.get('hours', []))
    days = ''.join(f'<div class=d><span>{E(a)}</span>{ic(b,40)}<span style="opacity:.85">{E(c)}</span><span class=p>{E(d)}</span></div>' for a, b, c, d in s.get('days', []))
    style = '''
body{background:linear-gradient(180deg,#0B1526 0%,#1D3458 55%,#5A4A6E 100%);color:#F4F1EA;padding:0 72px}
.sb{display:flex;justify-content:space-between;font-size:24px;padding:40px 10px 0;opacity:.9} .sb .mono{font-weight:700}
.loc{text-align:center;margin-top:40px} .loc h1{margin:0;font-size:44px;font-weight:500;letter-spacing:.08em} .loc p{margin:8px 0 0;font-size:24px;opacity:.75;letter-spacing:.2em}
.pct{text-align:center;font-size:210px;font-weight:200;line-height:1;letter-spacing:-.05em;font-family:'DejaVu Sans Mono';margin-top:6px}
.cond{text-align:center;font-size:34px;margin-top:-10px} .hl{text-align:center;font-size:26px;opacity:.8;margin-top:12px}
.card{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.14);border-radius:28px;padding:22px 30px;margin-top:30px}
.ct{font-size:20px;letter-spacing:.25em;opacity:.7;padding-bottom:16px;border-bottom:1px solid rgba(255,255,255,.18)}
.hours{display:flex;justify-content:space-between;padding-top:22px} .h{text-align:center;width:120px} .h .m{font-family:'DejaVu Sans Mono';font-size:22px;opacity:.8} .h .l{font-size:21px;margin-top:8px;line-height:1.3} .h svg{margin:10px 0 0}
.d{display:grid;grid-template-columns:230px 60px 1fr 90px;align-items:center;padding:18px 0;border-bottom:1px solid rgba(255,255,255,.14);font-size:28px} .d:last-child{border:0} .d .p{text-align:right;font-family:'DejaVu Sans Mono'}
.fv{display:flex;justify-content:space-between;margin-top:26px;padding:0 10px;font-size:25px;opacity:.9}
.brand{position:absolute;bottom:40px;left:0;right:0;display:flex;justify-content:center;align-items:center;gap:12px;font-size:20px;letter-spacing:.24em;opacity:.8}'''
    inner = f'''<div class=sb><span class=mono>{E(s.get('time','21:40'))}</span><span>●●● ▲ ▮</span></div>
<div class=loc><h1>{E(s.get('loc',''))}</h1><p>我的位置</p></div>
<div class=pct>{E(s.get('pct','70'))}<span style="font-size:100px;vertical-align:top;line-height:2.1">%</span></div>
<div class=cond>{E(s.get('cond',''))}</div><div class=hl>{E(s.get('hl',''))}</div>
<div class=card><div class=ct>逐時預報</div><div class=hours>{hours}</div></div>
<div class=card style="margin-top:20px"><div class=ct>之後幾次</div>{days}</div>
<div class=fv><span>{E(s.get('feel',''))}</span><span>{E(s.get('vis',''))}</span></div>
<div class=brand>{MARK}微糖 1/3 SUGAR</div>'''
    return doc(inner, style)

# ---------- lock screen ----------
def lock(s):
    ns = ''.join(f'<div class=n><div class=ic style="background:{E(c)}">{E(i)}</div><div class=t><div class=h><span>{E(a)}</span><span>{E(tm)}</span></div><b>{E(ti)}</b><p>{E(bo)}</p></div></div>'
                 for a, c, i, ti, bo, tm in s.get('notifs', []))
    style = '''
body{background:radial-gradient(ellipse at 50% 15%,#3b2a4a 0%,#14101c 55%,#0a0810 100%);color:#fff}
.sb{display:flex;justify-content:space-between;padding:36px 60px 0;font-size:22px;opacity:.9}
.date{text-align:center;margin-top:110px;font-size:30px;letter-spacing:.1em;opacity:.9} .clock{text-align:center;font-size:200px;font-weight:200;line-height:1;letter-spacing:-.03em;margin-top:6px}
.stack{position:absolute;left:48px;right:48px;top:600px;display:flex;flex-direction:column;gap:16px}
.n{display:flex;gap:18px;background:rgba(255,255,255,.14);border-radius:30px;padding:22px 26px}
.ic{width:76px;height:76px;border-radius:20px;flex:none;display:flex;align-items:center;justify-content:center;font-size:36px}
.t{flex:1} .h{display:flex;justify-content:space-between;font-size:20px;opacity:.7;margin-bottom:4px} .t b{font-size:27px;font-weight:600;display:block} .t p{margin:4px 0 0;font-size:25px;line-height:1.4;opacity:.95}
.bottom{position:absolute;bottom:40px;left:0;right:0;text-align:center;font-size:22px;opacity:.6}'''
    inner = f'''<div class=sb><span>{E(s.get('carrier','台灣大哥大'))}</span><span>●●●●  81%</span></div>
<div class=date>{E(s.get('date',''))}</div><div class=clock>{E(s.get('clock',''))}</div>
<div class=stack>{ns}</div><div class=bottom>{E(s.get('bottom',''))}</div>'''
    return doc(inner, style)

# ---------- neon ----------
def neon(s):
    style = '''
body{background:#07070B;background-image:repeating-linear-gradient(0deg,rgba(255,255,255,.025) 0 2px,transparent 2px 60px),repeating-linear-gradient(90deg,rgba(255,255,255,.025) 0 2px,transparent 2px 60px);display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff}
.n{font-family:'LXGW WenKai TC','Noto Sans TC';font-weight:700;text-align:center;line-height:1.1}
.pink{color:#FF7BB0;text-shadow:0 0 8px #FF7BB0,0 0 24px #ff3d8a,0 0 60px #ff3d8a,0 0 120px #ff1f7a}
.blue{color:#9FE8FF;text-shadow:0 0 8px #9FE8FF,0 0 24px #2bd1ff,0 0 60px #2bd1ff}
.b1{font-size:230px} .b2{font-size:76px;margin-top:10px;letter-spacing:.2em} .b3{font-size:40px;margin-top:70px;letter-spacing:.3em;opacity:.95}
.tube{width:520px;height:6px;border-radius:3px;background:#9FE8FF;box-shadow:0 0 10px #9FE8FF,0 0 30px #2bd1ff;margin:30px auto 0}
.cap{position:absolute;bottom:70px;left:0;right:0;text-align:center;color:#8a8a99;font-size:24px;letter-spacing:.2em}'''
    inner = f'''<div class="n pink b1">{br(s.get('big',''))}</div><div class=tube></div>
<div class="n blue b2">{E(s.get('line',''))}</div><div class="n pink b3">{E(s.get('small',''))}</div>
<div class=cap>{E(s.get('cap',''))}</div>{brand('#8a8a99')}'''
    return doc(inner, style)

KIND = {'receipt': receipt, 'retro': retro, 'weather': weather, 'lock': lock, 'neon': neon}

def build_fontcss(fdir):
    css = []
    for fam, pat in (('Noto Serif TC', 'noto-serif-tc'), ('Noto Sans TC', 'noto-sans-tc')):
        for w in (200, 300, 400, 500, 700, 900):
            for f in sorted(glob.glob(f'{fdir}/@fontsource/{pat}/files/{pat}-*-{w}-normal.woff2')):
                css.append(f"@font-face{{font-family:'{fam}';font-weight:{w};src:url('file://{f}') format('woff2')}}")
    wk = f'{fdir}/lxgw-wenkai-tc-webfont'
    if os.path.isdir(wk):
        for c in ('lxgwwenkaitc-regular.css', 'lxgwwenkaitc-bold.css'):
            p = os.path.join(wk, c)
            if os.path.exists(p):
                css.append(open(p, encoding='utf-8').read().replace("url('./files/", f"url('file://{wk}/files/").replace('url("./files/', f'url("file://{wk}/files/'))
    return ''.join(css)

if __name__ == '__main__':
    spec, out = sys.argv[1], sys.argv[2]
    fdir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.getcwd(), 'node_modules')
    FONTCSS = build_fontcss(fdir)
    slides = json.load(open(spec, encoding='utf-8'))
    os.makedirs(out, exist_ok=True)
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1080, 'height': 1350})
        for k, s in enumerate(slides, 1):
            f = os.path.join(out, f'slide-{k:02d}.html'); open(f, 'w', encoding='utf-8').write(KIND[s['kind']](s))
            pg.goto('file://' + os.path.abspath(f)); pg.evaluate('document.fonts.ready'); pg.wait_for_timeout(500)
            pg.screenshot(path=os.path.join(out, f'slide-{k:02d}.png')); print(os.path.join(out, f'slide-{k:02d}.png'))
        b.close()
