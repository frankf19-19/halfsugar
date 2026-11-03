// 中文斷行：把不能拆開的詞包成 <span class="w">（white-space:nowrap），詞與詞之間照一般規則換行，
// 避免「開／放」「對／方」這種把一個詞拆兩行的情況；段落最後幾個字黏在一起，避免一行只剩一兩個字。
// 這個檔案同時給：1) 網站執行時（index.html 內嵌同一段 WB 函式）2) 產生介紹頁時（node tools/wbr.js 檔案...）
const WB = (() => {
  const SEG = (typeof Intl !== 'undefined' && Intl.Segmenter) ? new Intl.Segmenter('zh-Hant', { granularity: 'word' }) : null;
  const HAN = /[㐀-鿿豈-﫿]/;
  const CLOSE = /[，。、；：？！）」』》〉】…—·～,.;:?!)\]%]/;   // 這些字前面不能換行
  const OPEN = /[（「『《〈【(\[]/;                              // 這些字後面不能換行
  const SPACE = /[\s ⁠]/;
  const TAIL = 5;  // 段落最後 5 個字不放換行點
  // 回傳在 text 裡可以換行的位置（index 陣列）；after = 這段文字後面同一段落還有幾個字
  function points(text, after) {
    if (!SEG || !HAN.test(text)) return [];
    const out = []; let pos = 0; const keep = new Set();
    for (const m of text.matchAll(/近照|私密照|大頭照|生活照|自拍照|私密相簿|心動|甜心|微糖|包養|浮水印|真人認證|財力認證|真人審核|不經手|另一方|對方|咖啡廳|驗證碼|聯絡方式|自我介紹|會員|帳號|手機號碼|網路圖片|見面|每月預算|相處預算/g)) for (let i = m.index + 1; i < m.index + m[0].length; i++) keep.add(i);
    for (const s of SEG.segment(text)) {
      if (pos > 0 && !keep.has(pos)) {
        const P = text[pos - 1], N = text[pos];
        const left = text.length - pos + after;
        if (left >= TAIL && !SPACE.test(P) && !SPACE.test(N) && !CLOSE.test(N) && !OPEN.test(P)
            && (HAN.test(P) || HAN.test(N) || CLOSE.test(P))
            && !(/[0-9A-Za-z]/.test(P) && /[0-9A-Za-z]/.test(N))) out.push(pos);
      }
      pos += s.segment.length;
    }
    return out;
  }
  // 不該拆開的英文詞與「數字＋單位」改用不換行空白
  const glue = t => t.replace(/\b(Sugar|1\/3) (Daddy|Mommy|Baby|Dating|Sugar)\b/g, '$1\u00a0$2').replace(/(\d) (?=[\u3400-\u9fff])/g, '$1\u00a0');
  return { points, SEG, glue };
})();

if (typeof module !== 'undefined' && require.main === module) {
  // 處理產生好的靜態 HTML：只動 <body> 內、<script>/<style> 以外的文字
  const fs = require('fs');
  const BLOCK_END = /^<\/(p|li|h[1-6]|dd|dt|div|a|summary|blockquote|td|th|figcaption|footer|header|section|main|nav|ul|ol|dl|details|button|label)\b/i;
  const BLOCK_START = /^<(p|li|h[1-6]|dd|dt|div|summary|blockquote|td|th|figcaption|footer|header|section|main|nav|ul|ol|dl|details|br)\b/i;
  for (const f of process.argv.slice(2)) {
    let h = fs.readFileSync(f, 'utf8').replace(/<wbr>/g, '').replace(/<span class="w">([^<]*)<\/span>/g, '$1');
    const bi = h.indexOf('<body'); if (bi < 0) continue;
    const head = h.slice(0, bi); const body = h.slice(bi);
    const toks = body.split(/(<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<[^>]+>)/);
    // 每個文字片段後面、到段落結束前還有幾個字
    const txtLen = t => t.replace(/&[a-z#0-9]+;/gi, 'x').length;
    let res = '';
    for (let i = 0; i < toks.length; i++) {
      const t = toks[i];
      if (i % 2 === 1 || !t) { res += t; continue; }
      let after = 0;
      for (let j = i + 1; j < toks.length; j++) {
        if (j % 2 === 1) { if (BLOCK_END.test(toks[j]) || BLOCK_START.test(toks[j]) || /^<(script|style)/i.test(toks[j])) break; continue; }
        after += txtLen(toks[j]);
      }
      // 以 HTML 實體切開，實體當成不可分割
      const parts = WB.glue(t).split(/(&[a-z#0-9]+;)/gi); let out = '';
      for (let k = 0; k < parts.length; k++) {
        let pt = parts[k]; if (k % 2 === 1) { out += pt; continue; }
        let rest = 0; for (let m = k + 1; m < parts.length; m++) rest += m % 2 ? 1 : parts[m].length;
        { const a = [...pt]; for (let q = 1; q < a.length; q++) if (a[q] === ' ' && a.length - q + rest + after < 6) a[q] = '\u00a0'; pt = a.join(''); }
        const pts = WB.points(pt, rest + after); const cuts = [0, ...pts, pt.length];
        for (let c = 0; c < cuts.length - 1; c++) {
          for (const seg of pt.slice(cuts[c], cuts[c + 1]).split(/( +)/)) { if (!seg) continue;
            const sa = [...seg]; let head = '', body = seg;
            if (sa.length > 14 && c === cuts.length - 2) { head = sa.slice(0, -6).join(''); body = sa.slice(-6).join(''); }
            out += head + (([...body].length > 1 && /[\u3400-\u9fff]/.test(body) && [...body].length <= 14) ? '<span class="w">' + body + '</span>' : body); }
        }
      }
      res += out;
    }
    fs.writeFileSync(f, head + res);
  }
}
if (typeof module !== 'undefined') module.exports = WB;
