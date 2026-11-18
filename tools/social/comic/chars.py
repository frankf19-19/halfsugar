# 精緻版角色（覆蓋 comic.py 的 tang / zhe / leo）
LN='#3a2620'; SK='#F9DDCB'; SKS='#EFC2AC'; GID=[0]
def _id(p): GID[0]+=1; return f'{p}{GID[0]}'
def _defs(hair_top,hair_bot,iris_in,iris_out):
    h=_id('h'); i=_id('i'); b=_id('b')
    d=(f'<defs><linearGradient id="{h}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{hair_top}"/><stop offset="1" stop-color="{hair_bot}"/></linearGradient>'
       f'<radialGradient id="{i}" cx=".5" cy=".65" r=".6"><stop offset="0" stop-color="{iris_in}"/><stop offset="1" stop-color="{iris_out}"/></radialGradient>'
       f'<filter id="{b}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter></defs>')
    return d,h,i,b
def _eye(x,y,expr,iris,fem,side):
    ry=17 if fem else 13; rr=15 if fem else 12; lw=6 if fem else 5
    o=''
    if expr in ('happy','laugh','shy_closed'):
        o+=f'<path d="M{x-22} {y+4} Q{x} {y-14} {x+22} {y+4}" fill="none" stroke="{LN}" stroke-width="{lw}" stroke-linecap="round"/>'
        if fem: o+=f'<path d="M{x+side*20} {y+1} l{side*10} -5" stroke="{LN}" stroke-width="4" stroke-linecap="round"/>'
        return o
    if expr=='shock': ry+=3; rr=9
    o+=f'<ellipse cx="{x}" cy="{y}" rx="24" ry="{ry}" fill="#fff"/>'
    dx=-4*side if expr=='nervous' else 0
    o+=f'<circle cx="{x+dx}" cy="{y+1}" r="{rr}" fill="url(#{iris})"/><circle cx="{x+dx}" cy="{y+2}" r="{rr*0.42}" fill="#1a0d0b"/>'
    o+=f'<circle cx="{x+dx-rr*0.38}" cy="{y-rr*0.35}" r="{rr*0.33}" fill="#fff"/><circle cx="{x+dx+rr*0.4}" cy="{y+rr*0.4}" r="{rr*0.15}" fill="#fff"/>'
    if expr=='flat':
        cid=_id('c'); o=f'<clipPath id="{cid}"><rect x="{x-30}" y="{y-2}" width="60" height="40"/></clipPath><g clip-path="url(#{cid})">'+o+'</g>'
        o+=f'<path d="M{x-26} {y} Q{x} {y-3} {x+26} {y-2}" fill="none" stroke="{LN}" stroke-width="{lw}" stroke-linecap="round"/>'
    else:
        o+=f'<path d="M{x-26} {y+1} Q{x-4} {y-ry-6} {x+26} {y-4}" fill="none" stroke="{LN}" stroke-width="{lw}" stroke-linecap="round"/>'
        if fem: o+=f'<path d="M{x+side*24} {y-3} l{side*11} -7 M{x+side*20} {y-8} l{side*8} -9" stroke="{LN}" stroke-width="3.5" stroke-linecap="round"/>'
    o+=f'<path d="M{x-17} {y+ry-3} Q{x} {y+ry+3} {x+17} {y+ry-5}" fill="none" stroke="#9a6a5e" stroke-width="2.5" opacity=".6" stroke-linecap="round"/>'
    return o
def _mouth(expr,fem,y=270):
    c='#B85566' if fem else '#9a5a50'
    if expr=='laugh': return f'<path d="M182 {y-8} Q200 {y+24} 218 {y-8}Z" fill="#8E3344" stroke="{LN}" stroke-width="3" stroke-linejoin="round"/><path d="M190 {y+5} Q200 {y+12} 210 {y+5}" fill="#E9828F"/>'
    if expr in ('happy',): return f'<path d="M185 {y-6} Q200 {y+10} 215 {y-6}" fill="none" stroke="{c}" stroke-width="4" stroke-linecap="round"/>'
    if expr=='shock': return f'<ellipse cx="200" cy="{y+2}" rx="8" ry="11" fill="#6b2a33"/>'
    if expr=='flat': return f'<path d="M190 {y} L210 {y-1}" stroke="{c}" stroke-width="4" stroke-linecap="round"/>'
    if expr=='nervous': return f'<path d="M186 {y} q4 -5 8 0 t8 0 t8 0" fill="none" stroke="{c}" stroke-width="3.5" stroke-linecap="round"/>'
    if fem: return f'<path d="M189 {y-2} Q200 {y+7} 211 {y-2} Q200 {y+1} 189 {y-2}Z" fill="#D9707E" stroke="{c}" stroke-width="2.5" stroke-linejoin="round"/>'
    return f'<path d="M188 {y} Q200 {y+5} 212 {y}" fill="none" stroke="{c}" stroke-width="3.5" stroke-linecap="round"/>'
def _blush(b,op=.5):
    return f'<g filter="url(#{b})"><ellipse cx="152" cy="242" rx="20" ry="9" fill="#F28C98" opacity="{op}"/><ellipse cx="248" cy="242" rx="20" ry="9" fill="#F28C98" opacity="{op}"/></g>'
def _sweat(): return f'<path d="M288 150 q12 22 0 30 q-12 -8 0 -30z" fill="#A9D8F2" stroke="{LN}" stroke-width="3"/>'
def _wrap(cx,cy,r,inner,extra=''):
    s=r/95
    return f'<g transform="translate({cx-200*s:.1f},{cy-200*s:.1f}) scale({s:.4f})">{inner}</g>{extra}'
def tang(cx,cy,r,expr='normal',extra=''):
    d,h,i,b=_defs('#5a3a31','#2e1e1a','#a0654f','#3b211b')
    o=d
    o+=f'<path d="M106 200 C90 92 140 58 200 58 C260 58 310 92 294 200 C290 250 296 290 306 320 C286 334 262 330 250 314 L150 314 C138 330 114 334 94 320 C104 290 110 250 106 200Z" fill="url(#{h})" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
    o+=f'<path d="M180 280 L180 346 Q200 356 220 346 L220 280Z" fill="{SK}" stroke="{LN}" stroke-width="4"/><path d="M180 290 Q200 316 220 290 L220 280 L180 280Z" fill="{SKS}"/>'
    o+=f'<path d="M52 440 C56 382 100 354 162 342 Q200 364 238 342 C300 354 344 382 348 440Z" fill="#A63F58" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
    o+=f'<path d="M162 342 Q200 386 238 342 Q200 352 162 342Z" fill="{SK}" stroke="{LN}" stroke-width="3.5" stroke-linejoin="round"/>'
    o+=f'<path d="M168 347 Q200 380 232 347" fill="none" stroke="#D9A94E" stroke-width="2.5"/><path transform="translate(193,372) scale(.36)" d="M20 34 C6 25 0 18 0 11 C0 4 6 0 11 0 C15 0 18 2 20 6 C22 2 25 0 29 0 C34 0 40 4 40 11 C40 18 34 25 20 34Z" fill="#E7B95A"/>'
    o+=f'<path d="M100 410 Q110 380 128 370 M300 410 Q290 380 272 370" stroke="#8b2f45" stroke-width="4" fill="none" opacity=".6"/>'
    o+=f'<path d="M122 182 C122 112 160 92 200 92 C240 92 278 112 278 182 C278 240 252 290 200 304 C148 290 122 240 122 182Z" fill="{SK}" stroke="{LN}" stroke-width="4.5"/>'
    o+=f'<path transform="translate(0,9)" d="M116 206 C104 118 150 70 210 72 C268 74 302 120 288 206 C284 188 276 174 266 162 C258 174 246 180 232 184 C238 170 236 158 230 148 C212 168 182 180 150 184 C136 188 124 196 116 206Z" fill="{SKS}" opacity=".9"/>'
    o+=f'<path d="M116 206 C104 118 150 70 210 72 C268 74 302 120 288 206 C284 188 276 174 266 162 C258 174 246 180 232 184 C238 170 236 158 230 148 C212 168 182 180 150 184 C136 188 124 196 116 206Z" fill="url(#{h})" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
    o+=f'<path d="M226 150 Q236 166 232 182 M200 166 Q206 160 212 150" fill="none" stroke="{LN}" stroke-width="2.5" opacity=".45"/>'
    o+=f'<path d="M116 200 C112 240 116 282 128 312 M286 200 C290 240 286 282 272 312" stroke="{LN}" stroke-width="3" fill="none" opacity=".5"/>'
    o+=f'<path d="M150 100 Q190 84 236 94" fill="none" stroke="#fff" stroke-width="7" opacity=".35" stroke-linecap="round"/><path d="M160 118 Q170 112 182 110" fill="none" stroke="#fff" stroke-width="5" opacity=".3" stroke-linecap="round"/>'
    br='M148 182 Q164 176 182 181' if expr!='nervous' else 'M148 178 Q164 181 182 184'
    br2='M218 181 Q236 176 252 182' if expr!='nervous' else 'M218 184 Q236 181 252 178'
    o+=f'<path d="{br} M{br2[1:]}" fill="none" stroke="#5a3a32" stroke-width="3.5" stroke-linecap="round"/>'
    o+=_eye(163,206,expr,i,True,-1)+_eye(237,206,expr,i,True,1)
    o+=f'<path d="M201 232 Q197 246 203 250" fill="none" stroke="#D9A08A" stroke-width="3" stroke-linecap="round"/>'
    o+=_mouth(expr,True)+_blush(b,.6 if expr in('happy','laugh','shy') else .45)
    if expr=='nervous': o+=_sweat()
    return _wrap(cx,cy,r,o,extra)
def _male(hair,glasses=False,coat='leo',expr='normal',gray=False):
    d,h,i,b=_defs(*hair,'#7a5444','#2a1a15')
    o=d
    o+=''.join(f'<ellipse cx="{x}" cy="208" rx="11" ry="19" fill="{SK}" stroke="{LN}" stroke-width="4"/>' for x in (124,276))
    o+=f'<path d="M176 280 L174 352 Q200 362 226 352 L224 280Z" fill="{SK}" stroke="{LN}" stroke-width="4"/><path d="M176 288 Q200 318 224 288 L224 280 L176 280Z" fill="{SKS}"/>'
    if coat=='leo':
        o+=f'<path d="M36 440 C42 378 98 350 166 344 Q200 362 234 344 C302 350 358 378 364 440Z" fill="#B88A5A" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
        o+=f'<path d="M166 344 Q200 362 234 344 L224 440 L176 440Z" fill="#2B2A33" stroke="{LN}" stroke-width="4" stroke-linejoin="round"/>'
        o+=f'<path d="M166 330 Q200 348 234 330 L238 360 Q200 378 162 360Z" fill="#2B2A33" stroke="{LN}" stroke-width="4" stroke-linejoin="round"/>'
        o+=f'<path d="M166 346 L144 396 L176 440 L172 368Z M234 346 L256 396 L224 440 L228 368Z" fill="#A87B4D" stroke="{LN}" stroke-width="4" stroke-linejoin="round"/>'
    else:
        o+=f'<path d="M40 440 C46 380 98 352 164 344 Q200 360 236 344 C302 352 354 380 360 440Z" fill="#33415F" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
        o+=f'<path d="M164 340 L200 380 L180 392 L156 352Z M236 340 L200 380 L220 392 L244 352Z" fill="#fff" stroke="{LN}" stroke-width="4" stroke-linejoin="round"/><path d="M200 380 V440" stroke="{LN}" stroke-width="3"/><circle cx="200" cy="410" r="4" fill="{LN}"/>'
    o+=f'<path d="M124 172 C124 112 160 96 200 96 C240 96 276 112 276 172 C276 228 264 268 238 294 C222 308 178 308 162 294 C136 268 124 228 124 172Z" fill="{SK}" stroke="{LN}" stroke-width="4.5"/>'
    if coat=='leo':
        o+=f'<path d="M140 250 Q150 290 178 300 Q200 306 222 300 Q250 290 260 250 Q250 286 200 292 Q150 286 140 250Z" fill="#7a6a62" opacity=".22"/>'
        o+=f'<path d="M126 176 C112 104 150 64 210 64 C268 66 296 104 280 178 C276 150 262 132 244 124 C222 114 190 114 166 122 C146 128 132 146 126 176Z" fill="url(#{h})" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
        o+=f'<path d="M132 132 C158 84 238 76 276 112 C244 98 200 98 166 118 C150 126 140 132 132 132Z" fill="#4a403b" stroke="{LN}" stroke-width="3" stroke-linejoin="round"/>'
        o+=f'<path d="M126 176 C122 160 124 146 130 136 L138 168Z M280 178 C284 160 282 146 276 136 L268 168Z" fill="#BDB6AF" stroke="{LN}" stroke-width="3" stroke-linejoin="round"/>'
        o+=f'<path d="M160 92 Q200 76 246 88" fill="none" stroke="#fff" stroke-width="6" opacity=".25" stroke-linecap="round"/>'
    else:
        o+=f'<path d="M120 186 C106 104 150 62 206 64 C264 66 302 106 284 186 C276 162 266 150 254 144 L248 164 L234 138 L220 160 L208 132 L192 158 L178 134 L166 160 L152 142 C136 152 126 168 120 186Z" fill="url(#{h})" stroke="{LN}" stroke-width="4.5" stroke-linejoin="round"/>'
        o+=f'<path d="M156 88 Q196 72 240 84" fill="none" stroke="#fff" stroke-width="6" opacity=".3" stroke-linecap="round"/>'
    if expr=='nervous': o+=f'<path d="M146 170 L184 174 M216 174 L254 170" stroke="#2a1c18" stroke-width="6" stroke-linecap="round"/>'
    else: o+=f'<path d="M146 174 L184 168 M216 168 L254 174" stroke="#2a1c18" stroke-width="6.5" stroke-linecap="round"/>'
    o+=_eye(164,206,expr,i,False,-1)+_eye(236,206,expr,i,False,1)
    if glasses: o+=''.join(f'<circle cx="{x}" cy="206" r="28" fill="#fff" fill-opacity=".08" stroke="#2a1c18" stroke-width="4"/>' for x in (164,236))+'<path d="M192 204 Q200 198 208 204 M136 200 L124 196 M264 200 L276 196" stroke="#2a1c18" stroke-width="4" fill="none"/>'
    o+=f'<path d="M201 222 L196 250 Q200 255 207 252" fill="none" stroke="#C98F78" stroke-width="3" stroke-linecap="round"/>'
    o+=_mouth(expr,False,274)
    if expr in ('happy','laugh','shy'): o+=_blush(b,.4)
    if expr=='nervous': o+=_sweat()
    return o
def leo(cx,cy,r,expr='normal',extra=''): return _wrap(cx,cy,r,_male(('#3a322e','#1f1a18'),False,'leo',expr),extra)
def zhe(cx,cy,r,expr='normal',extra=''): return _wrap(cx,cy,r,_male(('#2c2422','#141010'),True,'zhe',expr),extra)
