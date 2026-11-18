import sys; sys.path.insert(0,'/tmp/comic')
from aiep1 import page, narr, big, bubble
S=[]
S.append(page('weitang-ep2-p1.png', big(40,110,1000,'他為什麼\n知道我的名字？',88,'EP.2')+f'<foreignObject x="0" y="1180" width="1080" height="80"><div xmlns="http://www.w3.org/1999/xhtml" style="text-align:center;font:400 34px \'LXGW WenKai TC\';color:#F3DCC2;text-shadow:0 2px 8px #000">往右滑 →</div></foreignObject>',1,shade_top=True))
S.append(page('weitang-ep2-p2.png', narr(50,110,560,'昨晚，他送她到樓下。')+bubble(560,180,480,180,'安安，\n到家記得傳訊息。',tail=(820,370),size=42)+narr(60,1110,960,'她愣在門口——\n她從來沒跟他說過自己的名字。'),2,shade_top=True))
S.append(page('weitang-ep2-p3.png', bubble(590,300,450,180,'第一句先說謝謝……\n第二句……要問嗎？',tail=(640,560),size=36)+narr(60,1110,960,'隔天一早，她把外套洗好、燙好，\n在電梯口等了二十分鐘。'),3))
S.append(page('weitang-ep2-p4.png', bubble(520,110,530,250,'沈先生，謝謝你的外套……\n還有，你怎麼知道\n我的名字？',tail=(790,470),size=38)+narr(60,1130,960,'電梯門一打開，他就在裡面。'),4))
S.append(page('weitang-ep2-p5.png', bubble(40,1010,700,230,'識別證，你每天都掛著。\n而且你每天早上，\n都會跟警衛伯伯說早安。',tail=(380,830),size=38),5,shade_bot=False))
S.append(page('weitang-ep2-p6.png', big(40,80,1000,'「今天中午，\n不准再說沒關係。」',66,'一起吃飯？')+narr(60,1110,960,'下一集｜第一次一起吃午餐，\n她發現了他的另一面。'),6,shade_top=True))
for i,h in enumerate(S,1): open(f'out/ai-ep2-{i}.html','w').write(h)
