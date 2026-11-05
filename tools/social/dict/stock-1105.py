import html
F='/tmp/node_modules/@fontsource'
fonts=f"""
@font-face{{font-family:S;font-weight:900;src:url(file://{F}/noto-serif-tc/files/noto-serif-tc-chinese-traditional-900-normal.woff2)}}
@font-face{{font-family:S;font-weight:400;src:url(file://{F}/noto-serif-tc/files/noto-serif-tc-chinese-traditional-400-normal.woff2)}}
@font-face{{font-family:N;font-weight:400;src:url(file://{F}/noto-sans-tc/files/noto-sans-tc-chinese-traditional-400-normal.woff2)}}
@font-face{{font-family:N;font-weight:700;src:url(file://{F}/noto-sans-tc/files/noto-sans-tc-chinese-traditional-700-normal.woff2)}}
@font-face{{font-family:N;font-weight:400;src:url(file://{F}/noto-sans-tc/files/noto-sans-tc-latin-400-normal.woff2);unicode-range:U+0000-024F,U+1E00-1EFF}}
@font-face{{font-family:S;font-weight:400;src:url(file://{F}/noto-serif-tc/files/noto-serif-tc-latin-400-normal.woff2);unicode-range:U+0000-024F}}
"""
E=[('長期持有','cháng qí chí yǒu','我不想看了。'),
   ('逢低布局','féng dī bù jú','我還在套牢。'),
   ('我們聊點別的','wǒ men liáo diǎn bié de','今天不要提台積電。'),
   ('今天早點睡','jīn tiān zǎo diǎn shuì','明天九點還要開盤。'),
   ('我還好','wǒ hái hǎo','綠到發光，但晚餐照吃。')]
rows=''.join(f'<div class=e><div class=h><b>{a}</b><i>{p}</i></div><div class=d><span>釋</span>{html.escape(d)}</div></div>' for a,p,d in E)
doc=f"""<!doctype html><meta charset=utf-8><style>{fonts}
*{{box-sizing:border-box;margin:0}}body{{width:1080px;height:1350px;background:#F4EFE5;font-family:N;color:#1d1a17;position:relative}}
h1{{position:absolute;left:66px;top:62px;font:700 50px/1.45 N;letter-spacing:.02em}}
.card{{position:absolute;left:64px;right:64px;top:240px;bottom:84px;background:#FCFAF4;border:2px solid #D9CFB8;padding:34px 52px}}
.pg{{font:400 26px S;letter-spacing:.3em;color:#8C7B5E;padding-bottom:22px;border-bottom:2px solid #D9CFB8}}
.e{{padding:20px 0 18px;border-bottom:2px dashed #DDD3C0}} .e:last-child{{border-bottom:0}}
.h b{{font:900 54px S;letter-spacing:.02em}} .h i{{font-style:normal;font:400 28px N;color:#8C7B5E;margin-left:22px}}
.d{{font:400 34px S;margin-top:10px;display:flex;align-items:center;gap:16px}}
.d span{{font:400 24px S;color:#A63F58;border:2px solid #A63F58;padding:2px 6px;line-height:1.2}}
.ft{{position:absolute;right:46px;bottom:30px;font:400 24px N;color:#8C7B5E;letter-spacing:.06em}}
</style><h1>股民約會暗號<br>重編國語辭典（收盤特刊）</h1>
<div class=card><div class=pg>台 股 −1,374 點 ・ 收 盤 後 限 定</div>{rows}</div>
<div class=ft>♡ @onethirdsugar.tw</div>"""
open('d.html','w').write(doc)
