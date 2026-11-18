import sys; sys.path.insert(0,'/tmp/comic')
from comic import *
T=5; EP=2; NIGHT='#24304A'
def stars(pts): return ''.join(f'<path transform="translate({x},{y}) scale({s})" d="M0 -20 L5 -5 L20 0 L5 5 L0 20 L-5 5 L-20 0 L-5 -5Z" fill="{c}"/>' for x,y,s,c in pts)
def city(y,mh=380):
    import random; R=random.Random(7); o=''; x=48
    while x<1032:
        w=R.randint(70,140); h=R.randint(min(140,mh-40),mh)
        o+=f'<rect x="{x}" y="{y-h}" width="{w}" height="{h}" fill="#1A2236"/>'
        for wy in range(int(y-h+20),int(y-20),44):
            for wx in range(x+14,x+w-20,32):
                if R.random()<.35: o+=f'<rect x="{wx}" y="{wy}" width="14" height="20" fill="#F2C46B" opacity=".85"/>'
        x+=w+6
    return o
S=[]
# 1 封面
c=f'''<rect x="48" y="48" width="984" height="1254" fill="{NIGHT}"/>{city(1302,230)}{rain(60,300,1020,980,70)}
{umbrella(540,330,560)}
{tang(430,640,100,'happy')}{leo(660,620,108,'happy')}
<foreignObject x="80" y="150" width="920" height="160"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:900 100px/1.2 S;color:#FFF6E8;letter-spacing:.06em">他記得的小事</div></foreignObject>
<foreignObject x="80" y="1010" width="920" height="200"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:400 40px/1.6 'LXGW WenKai TC';color:#F7E7CF">下雨的加班夜，樓下有人在等。<br><span style="font-size:32px;color:#C9B89A">往右滑 →</span></div></foreignObject>'''
S.append(c)
# 2 加班
c=f'''<rect x="48" y="48" width="984" height="1254" fill="#EFE7DA"/>
<rect x="120" y="150" width="840" height="520" rx="10" fill="{NIGHT}" stroke="{INK}" stroke-width="{SW}"/>
<svg x="120" y="150" width="840" height="520" viewBox="48 400 984 600">{city(1000)}{rain(48,400,1032,1000,60,5)}</svg>
<path d="M540 150 V670 M120 410 H960" stroke="{INK}" stroke-width="{SW}"/>
<circle cx="860" cy="250" r="64" fill="#fff" stroke="{INK}" stroke-width="{SW}"/><path d="M860 250 V205 M860 250 L840 266" stroke="{INK}" stroke-width="{SW}" stroke-linecap="round"/>
{tang(540,830,120,'flat')}
<rect x="120" y="1000" width="840" height="40" rx="6" fill="#8C6A4A" stroke="{INK}" stroke-width="{SW}"/>
<path d="M330 1000 L370 870 H710 L750 1000Z" fill="#cfd6e0" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/><circle cx="540" cy="935" r="14" fill="#fff"/>
<g transform="translate(830,950)"><rect x="-34" y="-50" width="68" height="70" rx="8" fill="#fff" stroke="{INK}" stroke-width="{SW-1}"/><path d="M34 -30 q30 0 30 20 q0 20 -30 20" fill="none" stroke="{INK}" stroke-width="{SW-1}"/></g>
{narr(110,1080,860,'晚上十一點，辦公室只剩她一個人。\n提案改到第七版，晚餐還沒吃。')}'''
S.append(c)
# 3 訊息
c=f'''<rect x="48" y="48" width="984" height="1254" fill="#EFE7DA"/>
{phone(90,150,600,820,[('them','還在公司嗎？'),('me','你怎麼知道\n我在加班 😳'),('them','你昨天說，\n今天要交提案。'),('them','我在樓下，帶傘了。')],title='Leo')}
{tang(850,720,110,'shock')}
{bubble(710,300,300,170,'他…\n記得？',tail=(840,580),size=46)}
{narr(110,1060,860,'她只是隨口提過一次。\n連她自己都忘了說過。')}'''
S.append(c)
# 4 樓下
c=f'''<rect x="48" y="48" width="984" height="1254" fill="{NIGHT}"/>{rain(60,60,1020,1290,110,9)}
<path d="M200 1302 V420" stroke="#11182a" stroke-width="22"/><circle cx="200" cy="410" r="40" fill="#F2C46B"/><path d="M200 430 L90 1120 H310Z" fill="#F2C46B" opacity=".10"/>
<rect x="48" y="1120" width="984" height="182" fill="#1A2236"/>
{umbrella(690,420,460,'#2B2A33')}
{leo(690,700,115,'happy')}
<g transform="translate(560,1040)"><rect x="-55" y="-60" width="110" height="90" rx="10" fill="#F4E3C5" stroke="{INK}" stroke-width="{SW}"/><path d="M-30 -60 q30 -40 60 0" fill="none" stroke="{INK}" stroke-width="{SW-1}"/><path d="M-20 -95 q10 -15 0 -30 M10 -95 q10 -15 0 -30" stroke="#fff" stroke-width="5" fill="none" opacity=".7" stroke-linecap="round"/></g>
{bubble(80,640,420,180,'先吃點熱的。\n提案辛苦了。',tail=(590,700),size=46)}
{narr(110,1150,860,'熱湯還是燙的，他的大衣肩膀卻濕了一半。')}'''
S.append(c)
# 5 結局
c=f'''<rect x="48" y="48" width="984" height="1254" fill="{NIGHT}"/>{city(1302,200)}{rain(60,120,1020,820,70,11)}
{umbrella(540,190,600)}
{tang(440,500,100,'happy')}{leo(650,485,108,'happy')}
<g transform="translate(560,460)">{''.join(f'<path transform="translate({x},{y}) scale(.9)" d="M20 34 C6 25 0 18 0 11 C0 4 6 0 11 0 C15 0 18 2 20 6 C22 2 25 0 29 0 C34 0 40 4 40 11 C40 18 34 25 20 34Z" fill="#EFA3A8"/>' for x,y in [(-40,-150),(20,-190)])}</g>
<foreignObject x="80" y="820" width="920" height="300"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;color:#FFF6E8">
<div style="font:900 62px/1.4 S">最動人的照顧，<br>是被好好記得。</div>
<div style="font:400 34px/1.6 'LXGW WenKai TC';color:#D9C9AC;margin-top:20px">遇見一個，把你隨口說的話放在心上的人。</div></div></foreignObject>'''
S.append(c)
import os; os.makedirs('out',exist_ok=True)
for i,h in enumerate(S,1):
    html_=page(h,EP,i,T)
    if h.startswith(f'<rect x="48" y="48" width="984" height="1254" fill="{NIGHT}"'):
        html_=html_.replace('color:#8C7B5E;letter-spacing','color:#C9B89A;letter-spacing').replace('.pg{position:absolute;right:80px;top:78px;font:400 26px N;color:#8C7B5E','.pg{position:absolute;right:80px;top:78px;font:400 26px N;color:#C9B89A').replace('.tag{position:absolute;left:80px;top:78px;font:700 26px N;letter-spacing:.2em;color:#A63F58','.tag{position:absolute;left:80px;top:78px;font:700 26px N;letter-spacing:.2em;color:#EFA3A8')
    open(f'out/ep2-{i}.html','w').write(html_)
