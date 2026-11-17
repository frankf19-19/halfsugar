#!/usr/bin/env python3
"""產生 /quiz/care/ 與 /quiz/animal/ 兩個心理測驗頁（資料 data.js + index.html），共用 /quiz/engine.js。"""
import json, html, os

SITE = 'https://onethirdsugar.com'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

QUIZZES = [
 {
  'slug': 'care',
  'title': '你最需要哪一種被照顧？',
  'h1': '你最需要<br>哪一種被照顧？',
  'seo_title': '心理測驗：你最需要哪一種被照顧？行動、陪伴、肯定還是儀式感｜微糖 1/3 Sugar',
  'desc': '7 題戀愛心理測驗，1 分鐘測出你在感情裡最需要的照顧方式：行動派、陪伴派、肯定派還是儀式派。附上最讓你心動的瞬間，測完存成圖片分享到限動。',
  'og_desc': '7 題、1 分鐘，測出最能打動你的照顧方式。',
  'sub': '7 題、1 分鐘。同樣是對你好，有人要他把事情做好，有人只要他在身邊。測出最能打動你的那一種，測完可以存成圖片分享。',
  'lead': '我最需要的是',
  'cta': '你需要哪一種？1 分鐘測測看',
  'share': '我是「{w}」！你最需要哪一種被照顧？1 分鐘測測看',
  'store': 'yy_care',
  'rows': [['l', '為什麼是你'], ['sign', '最讓你心動的瞬間'], ['tip', '給你的小提醒']],
  'card': [['sign', '最讓我心動的瞬間'], ['tip', '小提醒']],
  'types_intro': [['行動派', '默默把事情處理好'], ['陪伴派', '放下手機，好好在你身邊'], ['肯定派', '說出口的在乎和稱讚'], ['儀式派', '記得你在意的每件小事']],
  'q': [
   ['加班到很晚，你最希望收到？', ['他已經在樓下等你，車上有熱飲', '他打電話來，陪你一路講到家', '一則訊息：「你今天辛苦了，真的很厲害」', '回家發現桌上有你最愛的甜點和一張小卡']],
   ['吵架和好，最有效的是？', ['他直接把讓你不開心的事改掉', '放下手機，好好陪你一整晚', '他認真說出哪裡錯了、為什麼在乎你', '他準備一個小驚喜，說對不起']],
   ['生日那天，你最期待？', ['他把一整天行程都安排好，你只要出門', '不用多特別，一起待一整天就好', '他寫一封長長的信給你', '精心布置的晚餐，還有一個有紀念意義的小東西']],
   ['讓你瞬間冷掉的是？', ['答應的事一直沒做', '約會時一直在滑手機', '從來不稱讚你', '紀念日完全忘記']],
   ['你心情不好的時候，最希望他？', ['直接問：「需要我幫你處理什麼？」', '什麼都不說，就在旁邊陪你', '一直跟你說：「不是你的錯」', '帶你去一個你一直想去的地方']],
   ['最讓你記很久的一件事？', ['他幫你修好壞掉很久的東西', '他陪你在急診等了一整夜', '他在朋友面前說以你為榮', '他記得你們第一次約會的日子']],
   ['理想的週末早上？', ['醒來時早餐已經做好', '賴床聊天，聊到中午', '他說：「早安，今天也好喜歡你」', '他說：「換衣服，帶你去個地方」']],
  ],
  'r': {
   'A': {'w': '行動派', 'p': 'Acts of Care', 'd': '最讓你心動的，是他默默把事情處理好。',
         'l': '對你來說，喜歡不是用說的，是用做的。你平常就很能幹，所以最心動的是有人主動接手，讓你不用什麼都自己扛。',
         'sign': '加班到很晚，下樓發現他已經在等你。', 'tip': '先讓他知道你哪裡累，他才知道從哪裡幫你。'},
   'B': {'w': '陪伴派', 'p': 'Quality Time', 'd': '你要的不多，只要他真的在。',
         'l': '你最在乎的是「在不在」。不用貴、不用多，但他要真的在：放下手機、看著你、聽你把話說完。',
         'sign': '你隨口說想吃宵夜，他二話不說穿上外套陪你出門。', 'tip': '陪伴是雙向的，也記得留時間給自己和朋友。'},
   'C': {'w': '肯定派', 'p': 'Words of Comfort', 'd': '一句真心的話，比什麼都有用。',
         'l': '你常常對自己很嚴格，所以特別需要一個人告訴你：你已經做得很好了。被看見、被肯定，你就有力氣繼續。',
         'sign': '他在朋友面前說：「她真的很厲害。」', 'tip': '好聽的話很多，看他說的和做的有沒有一致。'},
   'D': {'w': '儀式派', 'p': 'Little Rituals', 'd': '你喜歡被放在心上的感覺。',
         'l': '不是要多貴，而是他記得、他用心：一張小卡、一個紀念日、一頓特別安排的晚餐，都讓你覺得自己很重要。',
         'sign': '他記得你半年前隨口提過的那家店，默默訂好了位。', 'tip': '儀式感不用天天有，重要的是他記不記得你在意的事。'},
  },
  'read': [['/want-to-be-cared/', '想被照顧是一種錯嗎'], ['/daddy-type-boyfriend/', '爹系男友是什麼'], ['/care-vs-control/', '照顧和控制的差別']],
 },
 {
  'slug': 'animal',
  'title': '你是貓系、狗系、兔系還是狐系戀人？',
  'h1': '你是貓系、狗系，<br>還是狐系戀人？',
  'seo_title': '心理測驗：你是貓系、狗系、兔系還是狐系戀人？｜微糖 1/3 Sugar',
  'desc': '7 題戀愛心理測驗，1 分鐘測出你是貓系、狗系、兔系還是狐系戀人，看看你談戀愛的樣子，和最適合你的另一半。測完存成圖片分享給姐妹。',
  'og_desc': '7 題、1 分鐘，測出你談戀愛是哪一種動物。',
  'sub': '7 題、1 分鐘。曖昧時的你、吵架後的你、想念一個人的你，測出你是哪一種戀人，還有最適合你的他。',
  'lead': '我談戀愛是',
  'cta': '你是哪一系？1 分鐘測測看',
  'share': '我是「{w}」！你是貓系、狗系、兔系還是狐系戀人？',
  'store': 'yy_animal',
  'rows': [['l', '你談戀愛的樣子'], ['match', '最適合你的他'], ['tip', '給你的小提醒']],
  'card': [['match', '最適合我的他'], ['tip', '小提醒']],
  'types_intro': [['貓系戀人', '獨立、熟了才撒嬌'], ['狗系戀人', '熱情、喜歡就直說'], ['兔系戀人', '溫柔、需要安全感'], ['狐系戀人', '聰明、讓人猜不透']],
  'q': [
   ['剛開始曖昧，你通常？', ['等他先開口，但會偷偷看他的限動', '喜歡就直接說，根本藏不住', '很容易害羞，一則訊息要想很久才回', '若即若離，讓他猜不透']],
   ['另一半一整天沒回訊息，你會？', ['沒差，我也有自己的事要忙', '連打三通電話，擔心他出事', '有點不安，一直重看對話紀錄', '我也晚點回，看誰先忍不住']],
   ['約會他遲到 20 分鐘，你會？', ['先自己去逛逛，不乾等', '站在原地等，看到他還是很開心', '默默難過，但不好意思說', '笑著說沒關係，下次換我遲到']],
   ['你表達喜歡的方式？', ['偶爾撒個嬌，大部分時間很獨立', '每天說喜歡你，黏在旁邊', '準備小東西，做很多貼心的事', '一個眼神、一句話，就讓他心跳加速']],
   ['朋友眼中的你？', ['有點高冷，熟了才知道很可愛', '熱情、超好相處', '溫柔、心思細膩', '很有魅力，很難捉摸']],
   ['你最需要另一半？', ['給你空間，不要管太多', '給你回應，熱情要對等', '給你安全感，常常說在乎你', '跟得上你的節奏，聊天有火花']],
   ['吵架之後，你通常？', ['先冷靜一下，自己想通就好', '最多撐一小時，就先去和好', '需要他先抱抱、哄一下', '不急，先看他怎麼表現']],
  ],
  'r': {
   'A': {'w': '貓系戀人', 'p': 'Cat Lover', 'd': '獨立又難捉摸，熟了才會撒嬌。',
         'l': '你很需要自己的空間，喜歡但不黏人。一旦真正信任一個人，才會露出可愛、愛撒嬌的那一面。',
         'match': '情緒穩定、不會緊迫盯人，懂得給你空間的人。', 'tip': '偶爾主動一點，讓他知道你其實很在乎。'},
   'B': {'w': '狗系戀人', 'p': 'Puppy Lover', 'd': '熱情直接，喜歡就全心全意。',
         'l': '你愛得很真、很熱烈，喜歡就說、想念就找。跟你在一起的人，每天都能感受到被愛。',
         'match': '回應及時、一樣熱情，懂得珍惜你真心的人。', 'tip': '把一部分重心留給自己，愛別人之前也要愛自己。'},
   'C': {'w': '兔系戀人', 'p': 'Bunny Lover', 'd': '溫柔敏感，需要滿滿的安全感。',
         'l': '你心思細膩、很會照顧人，但也容易不安。你需要的是穩定、說到做到的陪伴，讓你不用一直猜。',
         'match': '成熟穩重、會主動報備，讓你不用猜的人。', 'tip': '不安的時候直接說出來，對的人會願意安撫你。'},
   'D': {'w': '狐系戀人', 'p': 'Fox Lover', 'd': '聰明有魅力，讓人忍不住想靠近。',
         'l': '你懂得拿捏距離感，知道自己要什麼，也很會讓人心動。真正吸引你的，是同樣有想法、有生活的人。',
         'match': '有主見、有生活品味，能跟上你節奏的人。', 'tip': '遇到對的人，也可以放下一點防備，讓他看見真實的你。'},
  },
  'read': [['/uncle-type/', '大叔控是什麼'], ['/emotionally-stable-men/', '情緒穩定的男生'], ['/first-date-outfit/', '第一次約會穿什麼']],
 },
]

ALL = [('/quiz/match/', '你適合大叔，還是小狼狗？'), ('/quiz/care/', '你最需要哪一種被照顧？'),
       ('/quiz/animal/', '你是貓系、狗系、兔系還是狐系戀人？'), ('/quiz/', '約會人格測驗：你的約會暗號是哪一句？')]

CSP = "default-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data: blob:; script-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'none'"

def page(z):
    url = f"{SITE}/quiz/{z['slug']}/"
    e = html.escape
    types = ''.join(f'<li><b>{e(a)}</b><i>{e(b)}</i></li>' for a, b in z['types_intro'])
    others = '・'.join(f'<a href="{h}">{e(t)}</a>' for h, t in ALL if h != f"/quiz/{z['slug']}/")
    read = '・'.join(f'<a href="{h}">{e(t)}</a>' for h, t in z['read'])
    ld = json.dumps({"@context": "https://schema.org", "@type": "WebPage", "url": url, "name": z['seo_title'],
                     "inLanguage": "zh-TW", "isPartOf": {"@id": f"{SITE}/#site"}}, ensure_ascii=False)
    return f'''<!DOCTYPE html>
<html lang="zh-Hant-TW">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="{CSP}">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(z['seo_title'])}</title>
<meta name="description" content="{e(z['desc'])}">
<meta name="robots" content="index,follow">
<link rel="canonical" href="{url}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="微糖 1/3 Sugar">
<meta property="og:title" content="心理測驗：{e(z['title'])}">
<meta property="og:description" content="{e(z['og_desc'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{url}og.png">
<meta property="og:locale" content="zh_TW">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/brand/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/brand/apple-touch-icon.png">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+TC:wght@400;900&display=swap">
<link rel="stylesheet" href="/quiz/quiz.css">
<script type="application/ld+json">{ld}</script>
</head>
<body>
<header><a class="logo" href="/"><img src="/brand/mark-black.svg" alt="">微糖</a><a class="join" href="/for-women/">女生安心交友</a></header>
<main>
  <section id="intro" class="card">
    <p class="pg">戀愛心理測驗</p>
    <h1>{z['h1']}</h1>
    <p class="sub">{e(z['sub'])}</p>
    <ol class="types">{types}</ol>
    <button id="start" class="btn">開始測驗</button>
  </section>
  <section id="quiz" class="card" hidden>
    <p class="pg"><span id="qn">第 1 題</span>・<span id="qtot">共 {len(z['q'])} 題</span></p>
    <div class="bar"><i id="prog"></i></div>
    <h2 id="qt"></h2>
    <div id="opts" class="opts"></div>
  </section>
  <section id="result" class="card" hidden>
    <p class="pg">{e(z['lead'])}</p>
    <h2 class="word" id="rw"></h2><p class="py" id="rp"></p>
    <p class="def"><span>你</span><span id="rd"></span></p>
    <dl class="info" id="rinfo"></dl>
    <div class="share"><button id="img" class="btn">存成圖片分享限動</button><a id="line" class="btn ghost" target="_blank" rel="noopener">分享到 LINE</a><a id="threads" class="btn ghost" target="_blank" rel="noopener">分享到 Threads</a></div>
    <p class="tome">想認識懂得照顧你的人？<a href="/for-women/">在微糖認識真人審核的成熟對象</a>，開站期間完全免費。</p>
    <button id="again" class="lnk">再測一次</button>
  </section>
  <section class="more">
    <p>再玩一個：{others}</p>
    <p>延伸閱讀：{read}</p>
  </section>
</main>
<footer>© 2026 微糖 1/3 Sugar・僅限 18 歲以上成年人使用・測驗結果僅供娛樂參考・<a href="/#/privacy">隱私政策</a></footer>
<script src="/quiz/{z['slug']}/data.js"></script>
<script src="/quiz/engine.js"></script>
</body>
</html>
'''

def data(z):
    d = {k: z[k] for k in ('title', 'lead', 'cta', 'share', 'store', 'rows', 'card', 'q', 'r')}
    d['url'] = f"{SITE}/quiz/{z['slug']}/"
    return '// 由 tools/build_quizzes.py 產生，請改那支程式\nwindow.QZ=' + json.dumps(d, ensure_ascii=False) + ';\n'

for z in QUIZZES:
    d = os.path.join(ROOT, 'quiz', z['slug'])
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'index.html'), 'w').write(page(z))
    open(os.path.join(d, 'data.js'), 'w').write(data(z))
    print('寫出', d)
