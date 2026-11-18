import sys; sys.path.insert(0,'/tmp/comic')
from comic import *
T=5; EP=1
def deco_stars(pts):
    return ''.join(f'<path transform="translate({x},{y}) scale({s})" d="M0 -20 L5 -5 L20 0 L5 5 L0 20 L-5 5 L-20 0 L-5 -5Z" fill="{c}"/>' for x,y,s,c in pts)
slides=[]
# 1 封面
cover=f'''
<rect x="48" y="48" width="984" height="1254" fill="{CREAM}"/>
<circle cx="540" cy="600" r="330" fill="#F1E2DF"/>
{deco_stars([(200,330,1.2,WINE),(880,420,1,"#E8B44C"),(860,860,1.4,WINE),(220,900,.9,"#E8B44C")])}
{tang(400,560,120,'happy')}
{zhe(690,560,120,'nervous')}
{cube(545,880,70,'happy')}
<foreignObject x="80" y="170" width="920" height="200"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:900 112px/1.1 S;color:{INK};letter-spacing:.04em">改天約</div></foreignObject>
<foreignObject x="80" y="1020" width="920" height="200"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:700 46px/1.5 'LXGW WenKai TC';color:{INK}">約會暗號翻譯中…<br><span style="font-size:36px;color:#8C7B5E">往右滑 →</span></div></foreignObject>
'''
slides.append(page(cover,EP,1,T))
# 2 他回「改天約」
s2=f'''
{phone(100,190,540,640,[('me','這週六要不要\n一起吃飯？'),('them','最近有點忙'),('them','改天約！')])}
{tang(830,720,120,'flat')}
{bubble(660,330,340,170,'改天…\n是哪天？',tail=(820,560),size=44)}
'''
slides.append(page(s2,EP,2,T,caption='小糖約了阿哲吃飯，收到一句很熟悉的回覆。'))
# 3 方糖翻譯
dictcard=f'''<foreignObject x="150" y="200" width="800" height="490"><div xmlns="http://www.w3.org/1999/xhtml" style="box-sizing:border-box;width:780px;height:470px;background:#fff;border:{SW}px solid {INK};border-radius:24px;padding:46px 56px;box-shadow:12px 12px 0 {WINE}">
<div style="font:900 84px/1 S;color:{INK}">改天約</div>
<div style="font:400 30px/1 N;color:#8C7B5E;margin:18px 0 26px">gǎi tiān yuē ｜ 社交用語</div>
<div style="font:700 50px/1.4 'LXGW WenKai TC';color:{WINE}">＝ 大概不會約。</div>
<div style="font:400 32px/1.6 'LXGW WenKai TC';color:{INK};margin-top:18px">例：「好啊改天約！」<br>（說完雙方都鬆了一口氣）</div></div></foreignObject>'''
s3=f'''{dictcard}
{cube(320,1120,90,'happy')}
{bubble(260,760,620,180,'沒有日期的約，\n通常就只是客套喔～',tail=(360,975),size=44)}
'''
slides.append(page(s3,EP,3,T))
# 4 反轉
s4=f'''
{phone(100,190,540,700,[('me','好啊！'),('me','那下週三晚上 7 點？\n我來訂位 🍝'),('them','……'),('them','好')])}
{zhe(830,740,120,'nervous')}
{bubble(660,330,340,170,'她…真的\n約了日期！',tail=(820,570),size=44)}
'''
slides.append(page(s4,EP,4,T,caption='但小糖不打算翻譯，她直接給了一個日期。'))
# 5 結局
s5=f'''
<rect x="48" y="760" width="984" height="542" fill="#EADDC8"/>
<rect x="250" y="720" width="580" height="40" rx="8" fill="#C9A77C" stroke="{INK}" stroke-width="{SW}"/>
{tang(380,480,115,'laugh')}
{zhe(700,480,115,'laugh')}
<g transform="translate(540,690)"><ellipse cx="0" cy="0" rx="90" ry="22" fill="#fff" stroke="{INK}" stroke-width="{SW-1}"/><path d="M-50 -6 q25 -40 50 -10 q25 -30 50 10" fill="#E8B44C" stroke="{INK}" stroke-width="{SW-2}"/></g>
{deco_stars([(240,250,1,WINE),(840,240,1.2,"#E8B44C")])}
<foreignObject x="100" y="860" width="880" height="300"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;color:{INK}">
<div style="font:900 64px/1.35 S">想見的人，<br>給一個確切的時間。</div>
<div style="font:400 34px/1.6 'LXGW WenKai TC';color:#6E5F4A;margin-top:22px">下週三晚上 7 點，他準時到了。</div></div></foreignObject>
'''
slides.append(page(s5,EP,5,T,bg=PAPER))
import os; os.makedirs('out',exist_ok=True)
for i,h in enumerate(slides,1): open(f'out/ep1-{i}.html','w').write(h)
print(len(slides))
