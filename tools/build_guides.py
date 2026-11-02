#!/usr/bin/env python3
"""產生給搜尋引擎的介紹頁（包養、Sugar Daddy、Sugar Mommy、甜心）。
   改內容就改下面的 PAGES，然後執行：python3 tools/build_guides.py
   會寫出 /baoyang/index.html 等頁面，並更新 sitemap.xml。"""
import json, html, pathlib, datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = 'https://onethirdsugar.com'
TODAY = datetime.date.today().isoformat()

PAGES = [
  {
    'slug': 'baoyang',
    'title': '包養網、甜心網怎麼選？認識甜心交友｜微糖 1/3 Sugar',
    'desc': '想找包養網、甜心網？微糖是真人審核的台灣甜心交友平台，Sugar Daddy、Sugar Mommy 與甜心一開始就說清楚期待。不做性交易、不經手金錢，重視隱私與安全。',
    'h1': '包養、甜心交友，有什麼不一樣？',
    'lead': '很多人搜尋「包養網」「甜心網」，其實想找的是同一件事：一段雙方都清楚期待、彼此照顧的成熟關係。在微糖，我們把它叫做「甜心交友（Sugar Dating）」。',
    'sections': [
      ('甜心交友是什麼', [
        '甜心交友是成年人之間，以坦誠為前提的交往方式。一方事業有成、願意在生活中照顧對方；另一方年輕、有自己的節奏與追求。',
        '和一般交友最大的不同，是彼此在認識之初就把期待說清楚：見面頻率、相處方式、每月相處預算。少一點猜測，也少一點失望。',
      ]),
      ('微糖不是什麼', [
        '微糖不是性交易平台。平台不經手會員之間的任何金錢，也禁止以金錢交換性行為的要求。',
        '色情業者、茶莊、外送茶、代聊、留聯絡方式拉客的帳號，到不了這裡；被檢舉查證屬實會直接停權，那支手機也不能再註冊。',
      ]),
      ('為什麼選微糖', [
        '每一張照片、每一段自介都由真人審核後才公開；一支台灣手機只能註冊一個帳號，假帳號與重複帳號很難存在。',
        '照片不公開存放，私密照只給你同意的人看；可以隱身，只讓聊過、心動過的人看到你；站內就能聊天，不必交換 LINE。',
      ]),
    ],
    'faq': [
      ('微糖是包養網嗎？', '微糖是甜心交友平台。很多人用「包養」這個詞，但我們更重視雙方平等、自願、坦誠的關係；平台不經手金錢，也禁止任何性交易。'),
      ('使用微糖要付費嗎？', '開站期間，所有會員都免費使用全部功能。正式收費前會提前公告，不會自動扣款。'),
      ('怎麼確認對方是真人？', '所有檔案都經過真人審核；會員也可以申請「真人認證」，依隨機指定動作拍攝自拍與短影片，通過後檔案會顯示認證標章。'),
    ],
  },
  {
    'slug': 'sugar-daddy',
    'title': 'Sugar Daddy 是什麼？台灣甜心爹地交友｜微糖 1/3 Sugar',
    'desc': 'Sugar Daddy（甜心爹地）是事業有成、願意照顧對方的男性。在微糖，Sugar Daddy 可以填寫每月相處預算、申請財力認證，認識真人審核的甜心。',
    'h1': 'Sugar Daddy 是什麼？',
    'lead': 'Sugar Daddy（甜心爹地）指的是事業有成、生活穩定，願意花時間與心力照顧另一半的男性。對他們來說，好的關係是彼此舒服、坦誠，不必猜來猜去。',
    'sections': [
      ('在微糖當 Sugar Daddy', [
        '建立檔案時，你會填寫「每月相處預算」，例如一起用餐、旅行、禮物與生活上照顧的大約範圍。這會顯示在你的檔案上，讓甜心一開始就清楚你的期待。',
        '你也可以自願申請「財力認證」：上傳一份財力文件（姓名可以遮住），由真人確認後，檔案會顯示認證標章，甜心可以申請查看。',
      ]),
      ('認識甜心的方式', [
        '探索只會出現方向互相吻合的會員；遇到想認識的人，可以直接傳一則訊息，或先按「心動」讓對方知道。',
        '每一位甜心的照片與自介都經過真人審核。你也可以篩選「只看真人認證」，或看看「今晚有空」的會員。',
      ]),
      ('我們重視的事', [
        '甜心交友不是性交易。平台不經手任何金錢，也不允許以金錢交換性行為的要求；違反者會直接停權。',
        '你的手機號碼與 Email 永遠不會顯示給任何會員，想隱身也可以只讓聊過的人看到你。',
      ]),
    ],
    'faq': [
      ('每月相處預算一定要填嗎？', 'Sugar Daddy／Sugar Mommy 建立檔案時需要填寫，也可以選「見面再談」。這只是讓雙方一開始就清楚期待，平台不經手任何款項。'),
      ('財力認證會公開我的文件嗎？', '不會。文件只給你親自同意的甜心查看，你可以隨時收回；未通過的文件會立即刪除。'),
      ('使用微糖要付費嗎？', '開站期間，所有會員都免費使用全部功能。'),
    ],
  },
  {
    'slug': 'sugar-mommy',
    'title': 'Sugar Mommy 是什麼？甜心媽咪交友｜微糖 1/3 Sugar',
    'desc': 'Sugar Mommy（甜心媽咪）是事業有成、願意照顧對方的女性。微糖支援 Sugar Mommy 認識真人審核的甜心，也歡迎同性甜心交友，重視隱私與安全。',
    'h1': 'Sugar Mommy 是什麼？',
    'lead': 'Sugar Mommy（甜心媽咪）是事業有成、經濟獨立，願意照顧另一半的女性。她們清楚自己想要什麼，也欣賞坦誠、懂得相處的人。',
    'sections': [
      ('在微糖當 Sugar Mommy', [
        '和 Sugar Daddy 一樣，你可以填寫每月相處預算、申請財力認證，讓對方一開始就清楚你的期待。',
        '微糖支援男生找女生、女生找男生，也支援同性的甜心交友。你選擇的方向決定探索裡會看到誰、誰看得到你，保護每一位會員的隱私。',
      ]),
      ('隱私是第一件事', [
        '照片存放在私有空間，只有登入、通過審核、方向吻合的會員看得到，看的時候還會疊上對方的代號浮水印。',
        '私密照只給你點頭的人看；也可以隱身，不出現在探索，只讓你心動過、聊過的人看到你。',
      ]),
      ('我們重視的事', [
        '甜心交友不是性交易，平台不經手任何金錢。每一張照片、每一段自介都由真人審核，業者與假帳號很難存在。',
      ]),
    ],
    'faq': [
      ('女生也可以當 Sugar Mommy 嗎？', '可以。建立檔案時選擇「Sugar Mommy」身分即可，並依你的方向認識想認識的對象。'),
      ('會被認識的人看到嗎？', '不會被路人或搜尋引擎看到。只有登入、通過審核、方向吻合的會員才看得到檔案；你也可以選擇隱身。'),
      ('使用微糖要付費嗎？', '開站期間，所有會員都免費使用全部功能。'),
    ],
  },
  {
    'slug': 'sugar-baby',
    'title': '甜心是什麼？成為甜心（Sugar Baby）前要知道的事｜微糖 1/3 Sugar',
    'desc': '甜心（Sugar Baby、甜心寶貝）是希望認識成熟、穩定對象的人。微糖是真人審核的甜心交友平台，私密照自己授權、不必交換聯絡方式，安全認識 Sugar Daddy 與 Sugar Mommy。',
    'h1': '甜心是什麼？',
    'lead': '甜心（Sugar Baby，也有人叫甜心寶貝）是希望認識成熟、穩定對象的人。你有自己的生活與追求，也希望遇到懂得照顧、彼此尊重的另一半。',
    'sections': [
      ('在微糖當甜心', [
        'Sugar Daddy／Sugar Mommy 的檔案上會顯示每月相處預算，有些也通過了財力認證，你可以申請查看。彼此一開始就清楚期待，不必猜。',
        '你可以先看看對方的回覆率、真人認證，也可以只回覆你想聊的人。對方回覆前，每段對話只能先傳一則訊息，不會被大量轟炸。',
      ]),
      ('保護自己的方法', [
        '第一次見面請選公開場所、自己安排交通，告訴信任的朋友你的行程；微糖也有「約會安全分享」，可以把見面資訊傳給朋友。',
        '任何在見面前就談價碼、要求先匯款，或要你傳私密照片的人，請直接封鎖並檢舉。',
      ]),
      ('我們重視的事', [
        '甜心交友不是性交易，平台不經手任何金錢。照片不公開存放，私密照只給你同意的人看，隨時可以收回。',
      ]),
    ],
    'faq': [
      ('當甜心需要付費嗎？', '開站期間，所有會員都免費使用全部功能。'),
      ('我的照片會被外流嗎？', '照片不公開存放，只有登入、通過審核、方向吻合的會員看得到，查看時會疊上對方的代號浮水印，截圖外流也查得到是誰。'),
      ('遇到奇怪的人怎麼辦？', '直接封鎖並檢舉。封鎖之後對方再也找不到你；檢舉時系統會自動保存你們的對話，供管理員查證。'),
    ],
  },
  {
    'slug': 'dating',
    'title': '台灣約會交友網站｜認真約會、安全見面｜微糖 1/3 Sugar',
    'desc': '在找約會網站、交友網站或交友軟體？微糖是真人審核的台灣約會交友平台，一支手機一個帳號、站內聊天不必交換 LINE，適合想認真約會、認識成熟對象的你。',
    'h1': '想找一個能認真約會的交友網站？',
    'lead': '交友軟體很多，但滑了半天，常常遇到假帳號、業者、聊兩句就消失的人。微糖想做的，是一個讓成年人可以安心、坦誠約會的地方。',
    'sections': [
      ('和一般交友軟體有什麼不同', [
        '每一張照片、每一段自介都由真人審核後才公開；一支台灣手機只能註冊一個帳號，假帳號、重複帳號和被停權的人很難回來。',
        '每個人一開始就寫清楚想要的相處方式：長期穩定、短期相處、晚餐約會、旅伴或生活陪伴，見面頻率與期待也一目了然，不用再猜對方在想什麼。',
      ]),
      ('約會從站內開始', [
        '遇到想認識的人，可以直接傳一則訊息，或先按「心動」。對方回覆前，每段對話只能先傳一則，不會被大量群發騷擾。',
        '站內就能聊天、傳照片、發約會邀請卡，不必一開始就交換 LINE 或電話。想今晚就見面，也可以打開「今晚有空」，讓附近的人知道。',
      ]),
      ('見面前的安心', [
        '可以先看對方有沒有通過真人認證、回覆率如何；見面時用「約會安全分享」把時間地點傳給信任的朋友。',
        '任何讓你不舒服的互動，一鍵封鎖並檢舉，系統會自動保存對話供管理員查證。',
      ]),
    ],
    'faq': [
      ('微糖是什麼樣的交友網站？', '微糖是台灣的甜心交友平台，Sugar Daddy、Sugar Mommy 與甜心在真人審核的環境中認識彼此。也歡迎單純想認真約會、認識成熟對象的人。'),
      ('需要下載 App 嗎？', '不用。用手機或電腦的瀏覽器打開 onethirdsugar.com 就能使用，也可以加到手機主畫面，像 App 一樣打開。'),
      ('使用要付費嗎？', '開站期間，所有會員都免費使用全部功能。'),
    ],
  },
  {
    'slug': 'dating-safety',
    'title': '第一次約會、網友見面安全指南｜避開交友詐騙｜微糖 1/3 Sugar',
    'desc': '第一次和網友見面要注意什麼？如何分辨交友詐騙、假帳號與色情業者？微糖整理約會前、見面時與遇到問題時的安全守則，讓你安心約會。',
    'h1': '第一次約會、網友見面，要注意什麼？',
    'lead': '線上認識的人，請用線下的謹慎對待。以下是我們整理的約會安全守則，不管你在哪個平台認識對方都適用。',
    'sections': [
      ('見面之前', [
        '先在站內多聊幾次，再考慮交換其他聯絡方式；可以要求視訊，確認對方和照片是同一個人。',
        '任何在見面前就談錢、要你先匯款、買點數、投資，或要你傳私密照片的人，都是常見的詐騙手法，請直接封鎖並檢舉。',
      ]),
      ('第一次見面', [
        '選擇公開、人多的地方，例如餐廳、咖啡廳；自己安排交通，不要讓對方接送，也不要去對方家裡。',
        '告訴信任的朋友你的行程與對方的資訊；保持清醒，自己看著自己的飲料。',
      ]),
      ('怎麼分辨假帳號與業者', [
        '照片過於完美像網路圖片、一開口就給 LINE ID 或外部連結、急著談價碼或「定點」、說自己急需用錢，這些都是警訊。',
        '在微糖，每一個帳號都要通過手機驗證與真人審核，會員也可以申請真人認證；業者、茶莊、外送茶、代聊會被直接停權。',
      ]),
      ('遇到問題時', [
        '立即封鎖並檢舉；若涉及威脅、勒索或人身安全，請撥打 110 報警，並保留對話紀錄與截圖。',
      ]),
    ],
    'faq': [
      ('網友要求先匯款或買點數怎麼辦？', '這幾乎都是詐騙。不要匯款、不要提供帳戶或驗證碼，直接封鎖並檢舉；若已經被騙，請撥打 165 反詐騙專線。'),
      ('第一次見面約在哪裡比較安全？', '公開、人多、交通方便的地方，例如餐廳或咖啡廳。避免一開始就去酒吧到很晚、對方家裡或偏僻的地方。'),
      ('微糖怎麼保護會員的安全？', '一支手機只能註冊一個帳號、真人審核每一個檔案、可申請真人認證、一鍵封鎖檢舉，以及見面時的「約會安全分享」。'),
    ],
  },
  {
    'slug': 'elite-dating',
    'title': '高端交友、菁英交友平台｜認識事業有成的對象｜微糖 1/3 Sugar',
    'desc': '想認識事業有成、生活穩定的對象？微糖是重視隱私的台灣高端交友平台，Sugar Daddy、Sugar Mommy 可申請財力認證，所有檔案由真人審核。',
    'h1': '想認識事業有成的對象？',
    'lead': '有些人在找「高端交友」「菁英交友」「富豪交友」，想認識的是生活穩定、懂得經營關係的人。微糖讓這樣的相遇更坦誠，也更安全。',
    'sections': [
      ('看得見的誠意', [
        'Sugar Daddy／Sugar Mommy 會在檔案上寫出每月相處預算，也可以自願申請財力認證：上傳財力文件（姓名可以遮住），由真人確認後顯示認證標章。',
        '檔案也會標示真人認證、回覆率與近期上線狀態，讓你在開口之前就有足夠的判斷。',
      ]),
      ('對隱私的講究', [
        '事業有成的人往往最在意隱私。微糖的照片不公開存放、搜尋引擎與路人都看不到；可以隱身，只讓聊過、心動過的人看到你。',
        '手機號碼與 Email 永遠不會顯示給任何會員；財力文件只給你親自同意的人看，隨時可以收回。',
      ]),
      ('我們重視的事', [
        '甜心交友不是性交易，平台不經手任何金錢。每一張照片、每一段自介都由真人審核，業者與假帳號很難存在。',
      ]),
    ],
    'faq': [
      ('財力認證要上傳什麼？', '一份能說明財力的文件，例如存款或資產證明，姓名等個資可以自行遮住。由真人審核，未通過會立即刪除。'),
      ('會被認識的人看到嗎？', '不會被路人或搜尋引擎看到。只有登入、通過審核、方向吻合的會員才看得到檔案，你也可以選擇隱身。'),
      ('使用要付費嗎？', '開站期間，所有會員都免費使用全部功能。'),
    ],
  }
]

CSS = '''
:root{--ink:#1A1A1A;--grey:#5f5b57;--rule:#E3E1DD;--wine:#B04A62;--paper:#F7F6F4}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"PingFang TC","Noto Sans TC","Microsoft JhengHei",sans-serif;color:var(--ink);background:#fff;line-height:1.9;line-break:strict;overflow-wrap:break-word;-webkit-font-smoothing:antialiased}
html{overflow-x:hidden}
a{color:inherit;text-underline-offset:4px}
header{border-bottom:1px solid var(--rule)}
header .in,main,footer .in{max-width:760px;margin:0 auto;padding:0 22px}
header .in{height:64px;display:flex;align-items:center;justify-content:space-between}
.logo{display:inline-flex;align-items:center;gap:10px;font-family:"Noto Serif TC",serif;font-size:21px;letter-spacing:.12em;text-decoration:none}
.logo img{width:26px;height:26px}
.top a.btn{min-height:40px;padding:0 18px;font-size:13px}
h1,h2{font-family:"Noto Serif TC",serif;font-weight:300;letter-spacing:.06em;line-height:1.45;text-wrap:balance;word-break:keep-all}
h1{font-size:32px;margin:56px 0 18px}
h2{font-size:21px;margin:44px 0 12px}
p{margin:0 0 14px;color:#333}
.lead{font-size:17px;color:var(--ink)}
.kicker{font-size:12px;letter-spacing:.2em;color:var(--wine);margin-top:48px}
.faq{margin-top:50px;border-top:1px solid var(--rule)}
.faq details{border-bottom:1px solid var(--rule);padding:16px 0}
.faq summary{cursor:pointer;font-weight:500;list-style:none}
.faq summary::-webkit-details-marker{display:none}
.faq summary::after{content:"＋";float:right;color:var(--grey)}
.faq details[open] summary::after{content:"－"}
.faq details p{margin:10px 0 0}
.cta{margin:56px 0 30px;padding:36px 28px;background:var(--paper);text-align:center}
.cta p{margin-bottom:20px}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:0 30px;border:1px solid var(--ink);text-decoration:none;font-size:14px;letter-spacing:.2em;margin:4px}
.btn.primary{background:#111;border-color:#111;color:#fff}
.more{margin:40px 0 0;font-size:14px;color:var(--grey)}
.more a{margin-right:14px;display:inline-block;padding:6px 0}
footer{border-top:1px solid var(--rule);margin-top:40px;padding:34px 0 44px;font-size:12px;color:var(--grey);text-align:center}
footer a{margin:0 8px;display:inline-block;padding:6px 0}
footer .copy{margin-top:12px}
@media(max-width:600px){h1{font-size:26px;margin-top:40px}.top a.btn{padding:0 14px}}
'''

def page(p):
    e = html.escape
    url = f"{SITE}/{p['slug']}/"
    sections = ''.join(f"<h2>{e(h)}</h2>" + ''.join(f"<p>{e(x)}</p>" for x in ps) for h, ps in p['sections'])
    faq = ''.join(f"<details><summary>{e(q)}</summary><p>{e(a)}</p></details>" for q, a in p['faq'])
    others = ''.join(f'<a href="/{o["slug"]}/">{e(o["h1"].rstrip("？"))}</a>' for o in PAGES if o['slug'] != p['slug'])
    ld = {"@context": "https://schema.org", "@graph": [
        {"@type": "WebPage", "@id": url, "url": url, "name": p['title'], "description": p['desc'], "inLanguage": "zh-TW",
         "isPartOf": {"@id": f"{SITE}/#site"}},
        {"@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in p['faq']]},
        {"@type": "BreadcrumbList", "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "微糖", "item": f"{SITE}/"},
            {"@type": "ListItem", "position": 2, "name": p['h1'].rstrip('？'), "item": url}]}]}
    csp = ("default-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; "
           "img-src 'self' data:; script-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'")
    return f'''<!DOCTYPE html>
<html lang="zh-Hant-TW">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="{csp}">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(p['title'])}</title>
<meta name="description" content="{e(p['desc'])}">
<meta name="robots" content="index,follow">
<link rel="canonical" href="{url}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="微糖 1/3 Sugar">
<meta property="og:title" content="{e(p['title'])}">
<meta property="og:description" content="{e(p['desc'])}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}/brand/og.png">
<meta property="og:locale" content="zh_TW">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/brand/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/brand/apple-touch-icon.png">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+TC:wght@300;400&display=swap">
<link rel="stylesheet" href="/guides.css">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
</head>
<body>
<header><div class="in top"><a class="logo" href="/"><img src="/brand/mark-black.svg" alt="">微糖</a><a class="btn primary" href="/#/auth">免費加入</a></div></header>
<main>
<p class="kicker">認識甜心交友</p>
<h1>{e(p['h1'])}</h1>
<p class="lead">{e(p['lead'])}</p>
{sections}
<section class="faq"><h2>常見問題</h2>{faq}</section>
<section class="cta"><p>真人審核、重視隱私的台灣甜心交友平台。開站期間全部免費。</p>
<a class="btn primary" href="/#/auth">免費加入微糖</a><a class="btn" href="/">看看微糖</a></section>
<p class="more">延伸閱讀：{others}</p>
</main>
<footer><div class="in"><a href="/">微糖首頁</a><a href="/#/safety">安全須知</a><a href="/#/guidelines">社群守則</a><a href="/#/privacy">隱私政策</a><a href="/#/terms">使用條款</a>
<p class="copy">© 2026 微糖 1/3 Sugar・僅限 18 歲以上成年人使用・平台不經手會員之間的任何金錢，禁止任何性交易。</p></div></footer>
</body>
</html>
'''

(ROOT / 'guides.css').write_text(CSS.strip() + '\n', encoding='utf-8')
for p in PAGES:
    d = ROOT / p['slug']; d.mkdir(exist_ok=True)
    (d / 'index.html').write_text(page(p), encoding='utf-8')

urls = [(f'{SITE}/', '1.0', 'weekly')] + [(f"{SITE}/{p['slug']}/", '0.8', 'monthly') for p in PAGES]
(ROOT / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + ''.join(f'  <url><loc>{u}</loc><lastmod>{TODAY}</lastmod><changefreq>{c}</changefreq><priority>{pr}</priority></url>\n' for u, pr, c in urls)
    + '</urlset>\n', encoding='utf-8')
print('寫出', len(PAGES), '頁介紹頁與 sitemap.xml')
