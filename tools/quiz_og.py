from PIL import Image, ImageDraw, ImageFont
import sys
F='/usr/share/fonts/opentype/noto/'
def font(n,s):
    # TC face index in TTC: try names
    for i in range(10):
        try:
            f=ImageFont.truetype(F+n,s,index=i)
            if 'TC' in f.getname()[0]: return f
        except Exception: break
    return ImageFont.truetype(F+n,s)
def make(out,title,types,slug):
    W,H=1200,630; im=Image.new('RGB',(W,H),'#F4EFE5'); d=ImageDraw.Draw(im)
    d.rectangle([40,40,W-40,H-40],fill='#FCFAF4',outline='#D9CFB8',width=6)
    d.text((105,188),'1 分鐘心理測驗・7 題',font=font('NotoSerifCJK-Regular.ttc',28),fill='#6B5D45')
    size=80
    while True:
        ft=font('NotoSerifCJK-Black.ttc',size)
        if d.textlength(title,font=ft)<=990 or size<50: break
        size-=4
    d.text((105,240),title,font=ft,fill='#1d1a17')
    x=105; fb=font('NotoSerifCJK-Black.ttc',32); fl=font('NotoSerifCJK-Black.ttc',32)
    for k,t in zip('ABCD',types):
        w=d.textlength(k,font=fl)+12+d.textlength(t,font=fb)+52
        d.rectangle([x,384,x+w,462],outline='#D9CFB8',width=3,fill='#FFFFFF')
        d.text((x+26,402),k,font=fl,fill='#A63F58'); d.text((x+26+d.textlength(k,font=fl)+12,402),t,font=fb,fill='#1d1a17')
        x+=w+18
    assert x<=W-60, x
    fs=font('NotoSansCJK-Regular.ttc',24); s='微糖 1/3 Sugar・onethirdsugar.com/quiz/'+slug
    d.text((W-90-d.textlength(s,font=fs),528),s,font=fs,fill='#6B5D45')
    im.save(out,optimize=True)
make('quiz/care/og.png','你最需要哪一種被照顧？',['行動派','陪伴派','肯定派','儀式派'],'care')
make('quiz/animal/og.png','你是貓系、狗系還是狐系戀人？',['貓系','狗系','兔系','狐系'],'animal')
