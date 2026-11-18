import sys,html; sys.path.insert(0,'/tmp/comic')
from comic import FONT, bubble, INK
def narr(x,y,w,text,size=38,align='left'):
    t=html.escape(text).replace('\n','<br>')
    return f'<foreignObject x="{x}" y="{y}" width="{w}" height="400"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;box-sizing:border-box;max-width:{w}px;background:rgba(18,20,32,.78);border-left:6px solid #E8B4BE;padding:18px 28px;font:400 {size}px/1.55 \'LXGW WenKai TC\';color:#FFF8EE;text-align:{align}">{t}</div></foreignObject>'
def big(x,y,w,text,size=64,sub=None):
    s=f'<div style="font:900 {size}px/1.35 S;color:#FFF8EE;text-shadow:0 0 18px rgba(0,0,0,.85),0 3px 6px rgba(0,0,0,.7)">{html.escape(text).replace(chr(10),"<br>")}</div>'
    if sub: s+=f'<div style="font:700 42px/1.6 \'LXGW WenKai TC\';color:#FFE9D2;margin-top:14px;text-shadow:0 0 14px #000,0 2px 4px #000">{html.escape(sub).replace(chr(10),"<br>")}</div>'
    return f'<foreignObject x="{x}" y="{y}" width="{w}" height="600"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center">{s}</div></foreignObject>'
def page(img,inner,idx,T=6,shade_top=False,shade_bot=True):
    g=''
    if shade_top: g+='<rect x="0" y="0" width="1080" height="520" fill="url(#gt)"/>'
    if shade_bot: g+='<rect x="0" y="900" width="1080" height="450" fill="url(#gb)"/>'
    return f'''<!doctype html><meta charset=utf-8>{FONT}<style>*{{margin:0}}body{{width:1080px;height:1350px;overflow:hidden;background:#111}}
.tag{{position:absolute;left:44px;top:40px;font:700 24px N;letter-spacing:.18em;color:#fff;text-shadow:0 1px 6px rgba(0,0,0,.7)}}
.pg{{position:absolute;right:44px;top:40px;font:400 24px N;color:#fff;text-shadow:0 1px 6px rgba(0,0,0,.7)}}
.ft{{position:absolute;right:44px;bottom:30px;font:400 24px N;color:#fff;letter-spacing:.05em;text-shadow:0 1px 6px rgba(0,0,0,.8)}}</style>
<svg width="1080" height="1350" viewBox="0 0 1080 1350" style="position:absolute;left:0;top:0"><defs>
<linearGradient id="gt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0b0d18" stop-opacity=".85"/><stop offset="1" stop-color="#0b0d18" stop-opacity="0"/></linearGradient>
<linearGradient id="gb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0b0d18" stop-opacity="0"/><stop offset="1" stop-color="#0b0d18" stop-opacity=".85"/></linearGradient></defs>
<image href="file:///tmp/comic/ai/{img}" x="0" y="0" width="1080" height="1350" preserveAspectRatio="xMidYMid slice"/>{g}{inner}</svg>
<div class=tag>微糖小劇場｜大她 12 歲的溫柔</div><div class=pg>{idx} / {T}</div><div class=ft>♡ @onethirdsugar.tw</div>'''
S=[]
S.append(page('weitang-ep1-p1.png', big(60,120,960,'她總是說\n「沒關係」',96,'EP.1')+f'<foreignObject x="0" y="1180" width="1080" height="80"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:400 34px \'LXGW WenKai TC\';color:#F3DCC2;text-shadow:0 2px 8px #000">往右滑 →</div></foreignObject>',1,shade_top=True))
S.append(page('weitang-ep1-p2.png', bubble(50,130,520,190,'沒關係～你先走，\n我自己可以！',tail=(500,520),size=44)+narr(60,1110,960,'安安最常說的一句話，就是「沒關係」。\n加班沒關係，沒吃飯也沒關係。'),2))
S.append(page('weitang-ep1-p3.png', narr(60,110,620,'鞋跟斷了。\n末班車剛走。\n手機只剩 3%。')+narr(60,1110,960,'她還是傳了一句給媽媽：\n「我到家了，沒關係，別擔心。」'),3,shade_top=True))
S.append(page('weitang-ep1-p4.png', bubble(560,110,480,190,'這麼晚了，\n還要說沒關係？',tail=(720,330),size=44)+bubble(40,820,330,130,'……沈先生？',tail=(300,690),size=40)+narr(60,1110,960,'是樓上公司那個人。\n每天在電梯裡，只對她點頭、從不說話。'),4))
S.append(page('weitang-ep1-p5.png', bubble(40,70,560,190,'「沒關係」\n是說給別人聽的。',tail=(400,290),size=44)+big(40,1020,1000,'在我這裡，\n可以有關係。',70),5))
S.append(page('weitang-ep1-p6.png', big(60,70,960,'原來被照顧，\n就是不用再逞強。',72)+narr(60,1100,960,'下一集｜他為什麼，會知道她的名字？'),6))
if __name__=="__main__":
  for i,h in enumerate(S,1): open(f'out/ai-ep1-{i}.html','w').write(h)
