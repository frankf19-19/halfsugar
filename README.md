# 微糖 JUST SUGAR — 台灣甜心交友平台

品牌名「微糖 JUST SUGAR」（前名半糖 HALF SUGAR、微糖 SUGAR 30）。改名只需搜尋替換 `微糖` / `JUST SUGAR` 兩個字串，logo 在 brand/ 資料夾。

## 檔案
```
index.html              前端（單一檔案 SPA，含條款/隱私/守則/安全須知）
supabase/schema.sql     資料庫結構、觸發器、RLS、Storage 規則（可重複執行）
README.md               本文件
```

## 功能（v0.1.0）
- 18+ 閘門、註冊時雙重勾選（成年＋同意條款）
- Email 註冊／登入／忘記密碼／改密碼
- 建檔：頭像、暱稱、性別、想認識、出生年、地區、身高、職業、興趣、自介
- **先審後上架**：檔案與每張照片都要管理員核准才公開；會員修改公開欄位會自動退回待審
- 探索：性別／地區／年齡篩選，按「喜歡」，互相喜歡即配對
- 配對後才能私訊（即時推送）、未讀數、解除配對
- 私密相簿：對方索取 → 你同意才看得到，可隨時收回
- 封鎖、檢舉（含「要求金錢」「色情產業招攬」「疑似未成年」）
- 前端敏感字攔截：自介與訊息出現「包養、援交、乾爹、月付…」等字眼無法送出
- 後台：待審會員、待審照片、檢舉處理（可看被檢舉人最近訊息、停權）、會員查詢

## 安裝步驟（約 20 分鐘）

### 1. 建 Supabase 專案
1. https://supabase.com → New project（Region 選 **Northeast Asia (Tokyo)** 離台灣最近）
2. 左側 **SQL Editor** → New query → 把 `supabase/schema.sql` 整段貼上 → Run
3. 左側 **Storage** → 確認已有 `photos` bucket（schema 會自動建立；若沒有，手動建一個 **Private** bucket 叫 `photos`）
4. 左側 **Authentication → Providers → Email**：
   - 開發階段可先關掉「Confirm email」方便測試；正式上線請打開
5. **Authentication → URL Configuration**：Site URL 填你的 GitHub Pages 網址（例如 `https://你的帳號.github.io/yueyu/`），Redirect URLs 也加上同一個網址

### 2. 填入金鑰
**Project Settings → API** 複製兩個值，貼到 `index.html` 最上方：
```js
SUPABASE_URL:  'https://xxxx.supabase.co',
SUPABASE_ANON: 'eyJ...',
```
anon key 是公開金鑰，放在前端是正常做法；真正的保護在 RLS。

### 3. 部署到 GitHub Pages
1. 建一個 repo（例如 `yueyu`），把 `index.html` 放在根目錄
2. Settings → Pages → Source: Deploy from branch → main / root
3. 幾分鐘後網址生效

### 4. 設定你自己為管理員
1. 先到網站用你的 Email 註冊一個帳號
2. 回到 Supabase SQL Editor 執行（把 email 換掉）：
```sql
update public.profiles set is_admin = true, status = 'approved'
 where id = (select id from auth.users where email = 'you@example.com');
```
3. 重新整理網站，導覽列會出現「後台」

### 5. 上線前要改的地方
- `index.html` 搜尋 `support@yueyu.example` → 換成真的客服信箱
- 條款與隱私政策是草稿，**請找律師看過**
- 正式營運建議：Supabase 升 Pro（每月 US$25，才有每日備份與較高流量），並把 Auth 的「Confirm email」打開

## 文案規則（PrimeSugar 路線）
網站對外的定位是「重視隱私的成人交友平台」，所有文案要守這幾條：

| 可以用 | 不能用 |
|---|---|
| 成人交友、成熟交友、高質感交友、私密、真實、人工審核 | 包養、援交、乾爹、甜心（作為身分稱呼）、Sugar Daddy/Baby、金主 |
| 成熟、事業有成、經濟獨立、生活品質 | 有錢、多金、月付、周付、零用金、贊助、生活費、車馬費 |
| 認識、約會、交往、陪伴 | 出場、包夜、全套、約炮、性交易 |

原則：**平台只收會籍費（未來），不經手、不媒介、不暗示任何會員之間的金錢往來。** 這是平台與刑法第 231 條「媒介以營利」拉開距離的核心。

## 已知限制（下一階段）
- 尚無付費會籍（預留 `第七條　付費服務`，金流建議綠界或藍新）
- 刪除帳號需人工處理（需要 Edge Function 才能讓使用者自助刪除）
- 無推播通知、無 App 包裝
- 會員修改公開欄位即下架重審：審核量大時可改成「舊版本繼續顯示、新版本待審」
- 敏感字清單在 `index.html` 的 `BAD_WORDS`，可自行增減；後台審核頁也會標示含敏感字的自介
