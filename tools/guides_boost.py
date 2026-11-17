# 2026-11-17 SEO 加強：Search Console 顯示「sugar daddy／糖寶意思／糖爹」有曝光但排名在 15～70 名，
# 而且好幾頁互相搶同一組字。這裡把「意思／中文」的主頁加長、補上別人會搜的字，其他頁改成不同意圖並連回主頁。
# 段落文字可用 [[連結文字|/路徑/]] 插入站內連結（build_guides.py 會轉成 <a>）。

def _sec(p, title, paras, at=None):
    s = list(p['sections'])
    i = len(s) if at is None else at
    s.insert(i, (title, paras))
    p['sections'] = s

def apply(pages):
    by = {p['slug']: p for p in pages}

    p = by['what-is-sugar-daddy']
    p['desc'] = ('Sugar Daddy 中文是什麼意思？台灣常譯作甜心爹地，也有人說糖爹、SD。這個詞從哪裡來、'
                 '和乾爹、爹系男友有什麼不同、台灣的 Sugar Daddy 是什麼樣的人，微糖一次整理。')
    p['lead'] = ('Sugar Daddy 直譯是「糖爹」，台灣比較常說「甜心爹地」，網路上也縮寫成 SD。它指的是生活穩定、'
                 '願意在關係裡照顧另一半的成熟男性。這個詞被誤用得很多，先把意思說清楚。')
    p['related'] = ['tangdie-meaning', 'sugar-baby-meaning', 'sugar-mommy', 'daddy-type-boyfriend', 'avoid-scams']
    p['sections'] = [
        ('Sugar Daddy 中文怎麼說', [
            '常見的中文說法有：甜心爹地、糖爹、SD（Sugar Daddy 的縮寫）。對應的另一方叫 Sugar Baby，中文常說甜心、糖寶，縮寫是 SB。',
            '女性的版本叫 Sugar Mommy（甜心媽咪），可以看[[Sugar Mommy 是什麼意思|/sugar-mommy/]]。']),
        ('這個詞從哪裡來', [
            'Sugar Daddy 是英文俚語，二十世紀初就出現在美國，原本用來形容對年輕伴侶很大方的年長男性。網路交友興起之後，它慢慢變成一種交友身分的名稱。',
            '在台灣，這個詞常常和「乾爹」混在一起講，所以很多人一聽到就有負面印象。其實兩者的意思並不一樣。']),
        ('Sugar Daddy、乾爹、爹系男友有什麼不同', [
            {'head': ['', 'Sugar Daddy', '乾爹', '爹系男友'],
             'rows': [['是什麼', '願意照顧另一半的成熟男性', '網路用語，常帶有金錢交換的暗示', '個性像爸爸一樣會照顧、包容的男友'],
                      ['重點', '一開始就把彼此期待說清楚', '容易和對價關係連在一起', '相處方式與個性'],
                      ['年紀', '通常較年長，但不是必要條件', '通常年紀差很多', '不一定比較大']]},
            '想多了解爹系男友，可以看[[爹系男友是什麼|/daddy-type-boyfriend/]]。']),
        ('台灣的 Sugar Daddy 通常是什麼樣的人', [
            '多半是三十五歲以上、事業和生活都穩定下來的男性。工作忙、社交圈固定，想認識的是相處輕鬆、不用猜、能一起吃飯或旅行的對象。',
            '他們在意的往往不是外表多亮眼，而是聊不聊得來、彼此尊重、話說不說得清楚。']),
        ('常見誤解', [
            '「Sugar Daddy 就是付錢的人」——在微糖，Sugar Daddy 是認真交往的成年人，平台不經手、不媒介任何金錢或對價。',
            '「只有老人才當 Sugar Daddy」——重點是成熟與穩定，不是年紀。']),
        ('小心冒充 Sugar Daddy 的詐騙', [
            '網路上很多詐騙會自稱 Sugar Daddy：一開始就說要給你錢，接著要你先付「手續費」「保證金」，或要你提供帳戶、證件。真心想認識你的人，不會要你先付任何費用。',
            '更多常見手法，可以看[[交友詐騙怎麼防|/avoid-scams/]]。']),
        ('在微糖', [
            'Sugar Daddy 建立檔案時填寫生活方式預算（公開只顯示等級）、可申請財力認證與真人認證；認識的是經真人審核的甜心。']),
    ]
    p['faq'] = list(p['faq']) + [
        ('SD 是什麼意思？', 'SD 是 Sugar Daddy 的縮寫，中文常說甜心爹地或糖爹；SB 是 Sugar Baby，也就是甜心。'),
        ('Sugar Daddy 和 Sugar Mommy 差在哪？', 'Sugar Daddy 是男性，Sugar Mommy 是女性；兩者都是關係裡比較會照顧人的一方。'),
    ]

    p = by['sugar-daddy']
    p['title'] = 'Sugar Daddy 交友：在台灣怎麼認識甜心爹地｜微糖 1/3 Sugar'
    p['h1'] = 'Sugar Daddy 交友怎麼開始？'
    p['desc'] = ('想在台灣當 Sugar Daddy、認識甜心？從建立檔案、生活方式預算、財力認證到第一次見面，'
                 '微糖整理 Sugar Daddy 交友的做法。還不熟這個詞，可以先看 Sugar Daddy 是什麼意思。')
    p['related'] = ['what-is-sugar-daddy', 'sugar-daddy-guide', 'sugar-daddy-app', 'tangdie-meaning']
    _sec(p, '先搞懂這個詞', ['還不確定 Sugar Daddy 指的是什麼，可以先看[[Sugar Daddy 是什麼意思|/what-is-sugar-daddy/]]。'], at=0)

    for slug in ('sugar-daddy-guide', 'sugar-daddy-app', 'terms-glossary'):
        if slug in by:
            _sec(by[slug], '延伸：這個詞的意思', ['想知道 Sugar Daddy 中文是什麼、和乾爹有什麼不同，可以看[[Sugar Daddy 是什麼意思|/what-is-sugar-daddy/]]。'])

    p = by['sugar-baby-meaning']
    p['related'] = ['tangdie-meaning', 'what-is-sugar-daddy', 'sugar-baby', 'sugar-baby-guide', 'avoid-scams']
    _sec(p, '這個詞從哪裡來', [
        'Sugar Baby 和 Sugar Daddy 一樣來自英文俚語。網路交友普及後，它變成指「關係中被照顧的一方」的身分名稱。中文直譯成糖寶，台灣比較常說甜心。'], at=1)
    _sec(p, '台灣的甜心通常是什麼樣的人', [
        '多半是二十多歲到三十出頭、生活忙碌、想認識成熟穩重對象的人。她們在意的是被尊重、被好好對待，以及相處起來舒不舒服。',
        '想知道怎麼開始，可以看[[甜心新手指南|/sugar-baby-guide/]]。'], at=3)
    _sec(p, '小心冒充 Sugar Daddy 的詐騙', [
        '有人會自稱 Sugar Daddy，說要給你錢，再要你先付「手續費」或提供帳戶、證件。真心想認識你的人，不會要你先付任何費用。更多手法看[[交友詐騙怎麼防|/avoid-scams/]]。'])
    p['faq'] = list(p['faq']) + [
        ('糖寶的英文是什麼？', '糖寶的英文是 Sugar Baby，縮寫 SB。'),
        ('糖寶和糖爹是什麼關係？', '糖爹是 Sugar Daddy，糖寶是 Sugar Baby；一個是比較會照顧人的一方，一個是被照顧的一方。詳細可以看糖爹是什麼意思。'),
    ]

    p = by['tangdie-meaning']
    p['related'] = ['what-is-sugar-daddy', 'sugar-baby-meaning', 'sugar-mommy', 'terms-glossary']
    _sec(p, '這些詞常一起出現：小辭典', [
        {'head': ['說法', '英文', '意思'],
         'rows': [['糖爹、甜心爹地', 'Sugar Daddy（SD）', '會照顧另一半的成熟男性'],
                  ['糖媽、甜心媽咪', 'Sugar Mommy（SM）', '會照顧另一半的成熟女性'],
                  ['糖寶、甜心', 'Sugar Baby（SB）', '被照顧的一方，男女都可以'],
                  ['爹系男友', '—', '個性很會照顧、包容另一半的男友']]},
        '想看更完整的說明：[[Sugar Daddy 是什麼意思|/what-is-sugar-daddy/]]、[[糖寶是什麼意思|/sugar-baby-meaning/]]、[[Sugar Mommy 是什麼意思|/sugar-mommy/]]。'], at=3)
    p['faq'] = list(p['faq']) + [
        ('糖媽是什麼意思？', '糖媽是 Sugar Mommy 的直譯，台灣常說甜心媽咪，指事業有成、願意照顧另一半的女性。'),
        ('糖爹網是什麼？', '一般指以 Sugar Daddy 交友為主的網站。選擇時要看有沒有真人審核、手機驗證，以及平台是否經手金錢；經手金錢或要你先付保證金的都要小心。'),
    ]
