# 微糖漫畫產生器：原創角色「小糖」（女）、「阿哲」（男）、「方糖」（方糖小幫手）
import html, json, sys
NM='/tmp/node_modules'
FONT=f"""
<link rel=stylesheet href="file://{NM}/lxgw-wenkai-tc-webfont/lxgwwenkaitc-bold.css">
<link rel=stylesheet href="file://{NM}/lxgw-wenkai-tc-webfont/lxgwwenkaitc-regular.css">
<style>
@font-face{{font-family:S;font-weight:900;src:url(file://{NM}/@fontsource/noto-serif-tc/files/noto-serif-tc-chinese-traditional-900-normal.woff2)}}
@font-face{{font-family:N;font-weight:700;src:url(file://{NM}/@fontsource/noto-sans-tc/files/noto-sans-tc-chinese-traditional-700-normal.woff2)}}
@font-face{{font-family:N;font-weight:400;src:url(file://{NM}/@fontsource/noto-sans-tc/files/noto-sans-tc-chinese-traditional-400-normal.woff2)}}
</style>"""
INK='#1d1a17'; SKIN='#F7D9C4'; WINE='#A63F58'; PAPER='#F4EFE5'; CREAM='#FCFAF4'
SW=7
def eyes(cx,cy,r,expr):
    o=''
    for dx in (-0.38*r,0.38*r):
        x=cx+dx; y=cy+0.02*r
        if expr in ('happy','laugh'):
            o+=f'<path d="M{x-0.13*r} {y+0.04*r} q{0.13*r} {-0.16*r} {0.26*r} 0" fill="none" stroke="{INK}" stroke-width="{SW-1}" stroke-linecap="round"/>'
        elif expr=='flat':
            o+=f'<path d="M{x-0.12*r} {y} h{0.24*r}" stroke="{INK}" stroke-width="{SW-1}" stroke-linecap="round"/>'
        elif expr=='shock':
            o+=f'<circle cx="{x}" cy="{y}" r="{0.11*r}" fill="#fff" stroke="{INK}" stroke-width="{SW-2}"/><circle cx="{x}" cy="{y}" r="{0.04*r}" fill="{INK}"/>'
        else:
            o+=f'<ellipse cx="{x}" cy="{y}" rx="{0.06*r}" ry="{0.085*r}" fill="{INK}"/>'
    return o
def mouth(cx,cy,r,expr):
    y=cy+0.38*r
    if expr=='laugh': return f'<path d="M{cx-0.2*r} {y-0.04*r} q{0.2*r} {0.32*r} {0.4*r} 0 z" fill="{WINE}" stroke="{INK}" stroke-width="{SW-2}" stroke-linejoin="round"/>'
    if expr=='happy': return f'<path d="M{cx-0.14*r} {y} q{0.14*r} {0.16*r} {0.28*r} 0" fill="none" stroke="{INK}" stroke-width="{SW-1}" stroke-linecap="round"/>'
    if expr=='shock': return f'<ellipse cx="{cx}" cy="{y+0.04*r}" rx="{0.08*r}" ry="{0.11*r}" fill="{INK}"/>'
    if expr in ('flat','nervous'): return f'<path d="M{cx-0.12*r} {y+0.04*r} q{0.06*r} {-0.06*r} {0.12*r} 0 t{0.12*r} 0" fill="none" stroke="{INK}" stroke-width="{SW-2}" stroke-linecap="round"/>'
    return f'<path d="M{cx-0.1*r} {y} q{0.1*r} {0.1*r} {0.2*r} 0" fill="none" stroke="{INK}" stroke-width="{SW-1}" stroke-linecap="round"/>'
def blush(cx,cy,r):
    return ''.join(f'<ellipse cx="{cx+dx}" cy="{cy+0.25*r}" rx="{0.14*r}" ry="{0.08*r}" fill="#EFA3A8" opacity=".75"/>' for dx in (-0.6*r,0.6*r))
def sweat(cx,cy,r):
    x=cx+0.95*r; y=cy-0.35*r
    return f'<path d="M{x} {y} q{0.14*r} {0.24*r} 0 {0.32*r} q{-0.14*r} {-0.08*r} 0 {-0.32*r} z" fill="#9FD3F0" stroke="{INK}" stroke-width="{SW-3}"/>'
def tang(cx,cy,r,expr='normal',extra=''):
    """小糖：短鮑伯頭、酒紅上衣"""
    hair=f'<path d="M{cx-1.08*r} {cy+0.55*r} C{cx-1.25*r} {cy-0.9*r} {cx-0.5*r} {cy-1.2*r} {cx} {cy-1.15*r} C{cx+0.6*r} {cy-1.2*r} {cx+1.25*r} {cy-0.9*r} {cx+1.08*r} {cy+0.55*r} L{cx+0.75*r} {cy+0.5*r} L{cx+0.8*r} {cy-0.2*r} Q{cx+0.1*r} {cy-0.35*r} {cx-0.45*r} {cy-0.72*r} Q{cx-0.75*r} {cy-0.25*r} {cx-0.8*r} {cy+0.5*r} Z" fill="#3A2A26" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
    body=f'<path d="M{cx-0.95*r} {cy+2.3*r} Q{cx-0.95*r} {cy+1.05*r} {cx} {cy+1.0*r} Q{cx+0.95*r} {cy+1.05*r} {cx+0.95*r} {cy+2.3*r} Z" fill="{WINE}" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
    neck=f'<rect x="{cx-0.18*r}" y="{cy+0.75*r}" width="{0.36*r}" height="{0.35*r}" fill="{SKIN}" stroke="{INK}" stroke-width="{SW-2}"/>'
    face=f'<ellipse cx="{cx}" cy="{cy}" rx="{0.92*r}" ry="{0.95*r}" fill="{SKIN}" stroke="{INK}" stroke-width="{SW}"/>'
    bang=f'<path d="M{cx-0.86*r} {cy-0.2*r} Q{cx-0.6*r} {cy-1.05*r} {cx+0.2*r} {cy-0.98*r} Q{cx+0.82*r} {cy-0.9*r} {cx+0.88*r} {cy-0.25*r} Q{cx+0.3*r} {cy-0.5*r} {cx-0.2*r} {cy-0.72*r} Q{cx-0.55*r} {cy-0.3*r} {cx-0.86*r} {cy-0.2*r} Z" fill="#3A2A26" stroke="{INK}" stroke-width="{SW-2}" stroke-linejoin="round"/>'
    s=body+neck+hair+face+bang+eyes(cx,cy,r,expr)+mouth(cx,cy,r,expr)+blush(cx,cy,r)
    if expr=='nervous': s+=sweat(cx,cy,r)
    return f'<g>{s}{extra}</g>'
def zhe(cx,cy,r,expr='normal',extra=''):
    """阿哲：短髮、圓框眼鏡、藏青襯衫"""
    body=f'<path d="M{cx-1.0*r} {cy+2.3*r} Q{cx-1.0*r} {cy+1.05*r} {cx} {cy+1.0*r} Q{cx+1.0*r} {cy+1.05*r} {cx+1.0*r} {cy+2.3*r} Z" fill="#2E3A55" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/><path d="M{cx-0.25*r} {cy+1.02*r} L{cx} {cy+1.35*r} L{cx+0.25*r} {cy+1.02*r}" fill="#fff" stroke="{INK}" stroke-width="{SW-2}" stroke-linejoin="round"/>'
    neck=f'<rect x="{cx-0.2*r}" y="{cy+0.75*r}" width="{0.4*r}" height="{0.33*r}" fill="{SKIN}" stroke="{INK}" stroke-width="{SW-2}"/>'
    face=f'<ellipse cx="{cx}" cy="{cy}" rx="{0.9*r}" ry="{0.98*r}" fill="{SKIN}" stroke="{INK}" stroke-width="{SW}"/>'
    hair=f'<path d="M{cx-0.92*r} {cy-0.1*r} Q{cx-1.0*r} {cy-1.15*r} {cx} {cy-1.12*r} Q{cx+1.0*r} {cy-1.15*r} {cx+0.92*r} {cy-0.15*r} Q{cx+0.5*r} {cy-0.62*r} {cx+0.1*r} {cy-0.55*r} L{cx+0.2*r} {cy-0.8*r} Q{cx-0.3*r} {cy-0.5*r} {cx-0.92*r} {cy-0.1*r} Z" fill="#231C1A" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
    gl=''.join(f'<circle cx="{cx+dx}" cy="{cy+0.02*r}" r="{0.24*r}" fill="none" stroke="{INK}" stroke-width="{SW-2}"/>' for dx in (-0.38*r,0.38*r))+f'<path d="M{cx-0.14*r} {cy} h{0.28*r}" stroke="{INK}" stroke-width="{SW-2}"/>'
    s=body+neck+face+hair+eyes(cx,cy,r,expr)+gl+mouth(cx,cy,r,expr)
    if expr in ('happy','laugh'): s+=blush(cx,cy,r)
    if expr=='nervous': s+=sweat(cx,cy,r)
    return f'<g>{s}{extra}</g>'
def cube(cx,cy,r,expr='happy',extra=''):
    """方糖小幫手：白色方糖，頭頂一顆小愛心"""
    s=f'<rect x="{cx-r}" y="{cy-r}" width="{2*r}" height="{2*r}" rx="{0.28*r}" fill="#fff" stroke="{INK}" stroke-width="{SW}"/>'
    s+=f'<path d="M{cx-r+0.2*r} {cy-r+0.25*r} h{0.5*r}" stroke="#E8E1D4" stroke-width="{SW}" stroke-linecap="round"/>'
    s+=f'<path transform="translate({cx-0.2*r},{cy-1.55*r}) scale({r/60})" d="M20 34 C6 25 0 18 0 11 C0 4 6 0 11 0 C15 0 18 2 20 6 C22 2 25 0 29 0 C34 0 40 4 40 11 C40 18 34 25 20 34Z" fill="{WINE}" stroke="{INK}" stroke-width="5"/>'
    s+=eyes(cx,cy-0.1*r,0.9*r,expr)+mouth(cx,cy-0.15*r,0.9*r,expr)+blush(cx,cy-0.1*r,0.9*r)
    return f'<g>{s}{extra}</g>'
def bubble(x,y,w,h,text,tail=None,size=44,think=False):
    t=html.escape(text).replace('\n','<br>')
    tl=''
    if tail and y<tail[1]<y+h:
        tx,ty=tail; ex=x+w if tx>x+w else x; d=-4 if ex==x+w else 4
        by=min(max(ty-40,y+40),y+h-40)
        tl=f'<path d="M{ex} {by-24} L{tx} {ty} L{ex} {by+24}" fill="#fff" stroke="{INK}" stroke-width="{SW-1}" stroke-linejoin="round"/><path d="M{ex+d} {by-20} L{ex+d} {by+20}" stroke="#fff" stroke-width="{SW+2}"/>'
    elif tail:
        tx,ty=tail
        bx=min(max(tx,x+40),x+w-40)
        by=y+h if ty>y+h else y
        tl=f'<path d="M{bx-26} {by} L{tx} {ty} L{bx+26} {by}" fill="#fff" stroke="{INK}" stroke-width="{SW-1}" stroke-linejoin="round"/><path d="M{bx-22} {by+(-4 if by==y+h else 4)} L{bx+22} {by+(-4 if by==y+h else 4)}" stroke="#fff" stroke-width="{SW+2}"/>'
    return (f'<foreignObject x="{x}" y="{y}" width="{w}" height="{h}"><div xmlns="http://www.w3.org/1999/xhtml" style="box-sizing:border-box;width:{w}px;height:{h}px;background:#fff;border:{SW-1}px solid {INK};border-radius:{h/2.2 if not think else 40}px;display:flex;align-items:center;justify-content:center;text-align:center;font:700 {size}px/1.35 \'LXGW WenKai TC\',N;color:{INK};padding:0 28px">{t}</div></foreignObject>'+tl)
def phone(x,y,w,h,msgs,title="阿哲"):
    """手機畫面：msgs = [(side,'text')] side: 'me' 右邊酒紅 / 'them' 左邊灰"""
    o=f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="48" fill="{INK}"/><rect x="{x+16}" y="{y+16}" width="{w-32}" height="{h-32}" rx="36" fill="#fff"/>'
    o+=f'<rect x="{x+w/2-50}" y="{y+28}" width="100" height="20" rx="10" fill="{INK}"/>'
    o+=f'<foreignObject x="{x+16}" y="{y+60}" width="{w-32}" height="70"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:700 30px/70px N;color:{INK};border-bottom:2px solid #EDE8E0">{html.escape(title)}</div></foreignObject>'
    cy=y+160
    for side,txt in msgs:
        lines=txt.split('\n'); bh=24+len(lines)*44; bw=min(w-120, max(len(l) for l in lines)*36+56)
        bx=x+w-36-bw if side=='me' else x+36
        col=WINE if side=='me' else '#EDE8E0'; fc='#fff' if side=='me' else INK
        o+=f'<foreignObject x="{bx}" y="{cy}" width="{bw}" height="{bh}"><div xmlns="http://www.w3.org/1999/xhtml" style="box-sizing:border-box;width:{bw}px;height:{bh}px;background:{col};color:{fc};border-radius:26px;font:400 34px/44px N;padding:12px 26px">{"<br>".join(html.escape(l) for l in lines)}</div></foreignObject>'
        cy+=bh+18
    return o
def page(inner, ep, idx, total, caption=None, bg=PAPER):
    cap=''
    if caption:
        cap=f'<div style="position:absolute;left:70px;right:70px;bottom:118px;text-align:center;font:400 40px/1.5 \'LXGW WenKai TC\';color:{INK}">{html.escape(caption)}</div>'
    return f'''<!doctype html><meta charset=utf-8>{FONT}<style>*{{margin:0;box-sizing:border-box}}body{{width:1080px;height:1350px;background:{bg};position:relative;overflow:hidden}}
.frame{{position:absolute;left:48px;top:48px;right:48px;bottom:48px;border:{SW}px solid {INK};border-radius:28px;background:{CREAM};overflow:hidden}}
.tag{{position:absolute;left:80px;top:78px;font:700 26px N;letter-spacing:.2em;color:{WINE};z-index:3}}
.pg{{position:absolute;right:80px;top:78px;font:400 26px N;color:#8C7B5E;z-index:3}}
.ft{{position:absolute;right:80px;bottom:72px;font:400 24px N;color:#8C7B5E;letter-spacing:.06em;z-index:3}}</style>
<div class=frame><svg width="984" height="1254" viewBox="48 48 984 1254" style="position:absolute;left:0;top:0">{inner}</svg></div>
<div class=tag>微糖小劇場 EP.{ep}</div><div class=pg>{idx} / {total}</div>{cap}<div class=ft>♡ @onethirdsugar.tw</div>'''

def leo(cx,cy,r,expr='normal',extra=''):
    """Leo：成熟大叔，往後梳、兩鬢灰白、淡鬍渣、駝色大衣"""
    coat=f'<path d="M{cx-1.1*r} {cy+2.3*r} Q{cx-1.05*r} {cy+1.05*r} {cx} {cy+1.0*r} Q{cx+1.05*r} {cy+1.05*r} {cx+1.1*r} {cy+2.3*r} Z" fill="#B88A5A" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
    coat+=f'<path d="M{cx-0.32*r} {cy+1.02*r} L{cx} {cy+2.3*r} L{cx+0.32*r} {cy+1.02*r} Z" fill="#2B2A33" stroke="{INK}" stroke-width="{SW-2}" stroke-linejoin="round"/>'
    coat+=f'<path d="M{cx-0.32*r} {cy+1.02*r} L{cx-0.55*r} {cy+1.6*r} L{cx-0.12*r} {cy+1.55*r}" fill="#A87B4D" stroke="{INK}" stroke-width="{SW-2}" stroke-linejoin="round"/><path d="M{cx+0.32*r} {cy+1.02*r} L{cx+0.55*r} {cy+1.6*r} L{cx+0.12*r} {cy+1.55*r}" fill="#A87B4D" stroke="{INK}" stroke-width="{SW-2}" stroke-linejoin="round"/>'
    neck=f'<rect x="{cx-0.2*r}" y="{cy+0.75*r}" width="{0.4*r}" height="{0.33*r}" fill="#F0CDB4" stroke="{INK}" stroke-width="{SW-2}"/>'
    face=f'<path d="M{cx-0.88*r} {cy-0.2*r} Q{cx-0.9*r} {cy+0.95*r} {cx} {cy+0.98*r} Q{cx+0.9*r} {cy+0.95*r} {cx+0.88*r} {cy-0.2*r} Q{cx+0.85*r} {cy-0.95*r} {cx} {cy-0.95*r} Q{cx-0.85*r} {cy-0.95*r} {cx-0.88*r} {cy-0.2*r}Z" fill="#F0CDB4" stroke="{INK}" stroke-width="{SW}"/>'
    hair=f'<path d="M{cx-0.9*r} {cy-0.05*r} Q{cx-1.0*r} {cy-1.2*r} {cx+0.05*r} {cy-1.15*r} Q{cx+1.0*r} {cy-1.15*r} {cx+0.9*r} {cy-0.05*r} Q{cx+0.82*r} {cy-0.55*r} {cx+0.4*r} {cy-0.62*r} Q{cx-0.2*r} {cy-0.72*r} {cx-0.5*r} {cy-0.5*r} Q{cx-0.8*r} {cy-0.4*r} {cx-0.9*r} {cy-0.05*r}Z" fill="#2A2523" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
    hair+=''.join(f'<path d="M{cx+s*0.86*r} {cy-0.05*r} Q{cx+s*0.88*r} {cy-0.4*r} {cx+s*0.74*r} {cy-0.55*r}" stroke="#BDB8B2" stroke-width="{SW+3}" fill="none" stroke-linecap="round"/>' for s in (-1,1))
    hair+=f'<path d="M{cx-0.3*r} {cy-0.95*r} Q{cx+0.2*r} {cy-0.8*r} {cx+0.6*r} {cy-0.85*r}" stroke="#5a504a" stroke-width="3" fill="none"/>'
    brows=''.join(f'<path d="M{cx+dx-0.13*r} {cy-0.2*r} L{cx+dx+0.13*r} {cy-0.23*r}" stroke="{INK}" stroke-width="{SW-1}" stroke-linecap="round"/>' for dx in (-0.38*r,0.38*r))
    stub=''.join(f'<circle cx="{cx+dx*r}" cy="{cy+dy*r}" r="2.4" fill="#8a7a70"/>' for dx,dy in [(-0.45,0.55),(-0.3,0.68),(-0.12,0.74),(0.12,0.74),(0.3,0.68),(0.45,0.55),(-0.2,0.84),(0.0,0.86),(0.2,0.84)])
    s=coat+neck+face+hair+brows+stub+eyes(cx,cy,r,expr)+mouth(cx,cy,r,expr)
    if expr in ('happy','laugh'): s+=blush(cx,cy,r)
    return f'<g>{s}{extra}</g>'
def narr(x,y,w,text,size=36,dark=False):
    bg='#FFF6D9'
    return f'<foreignObject x="{x}" y="{y}" width="{w+14}" height="400"><div xmlns="http://www.w3.org/1999/xhtml" style="display:inline-block;box-sizing:border-box;max-width:{w}px;background:{bg};border:{SW-2}px solid {INK};box-shadow:7px 7px 0 {INK};padding:16px 26px;font:400 {size}px/1.55 \'LXGW WenKai TC\';color:{INK}">{html.escape(text).replace(chr(10),"<br>")}</div></foreignObject>'
def rain(x0,y0,x1,y1,n=70,seed=3,col='#9FB4D6'):
    import random; R=random.Random(seed); o=''
    for _ in range(n):
        x=R.uniform(x0,x1); y=R.uniform(y0,y1); L=R.uniform(26,50)
        o+=f'<path d="M{x} {y} l-8 {L}" stroke="{col}" stroke-width="4" stroke-linecap="round" opacity=".7"/>'
    return o
def umbrella(cx,top,w,col=WINE):
    h=w*0.42
    s=f'<path d="M{cx} {top+h*0.2} V{top+h+w*0.42} q0 {w*0.1} {-w*0.09} {w*0.09}" fill="none" stroke="{INK}" stroke-width="{SW+1}" stroke-linecap="round"/>'
    s+=f'<path d="M{cx-w/2} {top+h} Q{cx-w/2} {top} {cx} {top} Q{cx+w/2} {top} {cx+w/2} {top+h} q{-w/12} {-h*0.18} {-w/6} 0 q{-w/12} {-h*0.18} {-w/6} 0 q{-w/12} {-h*0.18} {-w/6} 0 q{-w/12} {-h*0.18} {-w/6} 0 q{-w/12} {-h*0.18} {-w/6} 0 q{-w/12} {-h*0.18} {-w/6} 0Z" fill="{col}" stroke="{INK}" stroke-width="{SW}" stroke-linejoin="round"/>'
    s+=f'<path d="M{cx} {top} V{top-26}" stroke="{INK}" stroke-width="{SW}" stroke-linecap="round"/>'
    return s

from chars import tang, zhe, leo
