#!/usr/bin/env python3
"""每次改完 index.html、發佈前執行：重新計算內嵌程式的雜湊，更新內容安全政策（CSP）。
   python3 tools/build_csp.py"""
import re, hashlib, base64, pathlib, sys
P = pathlib.Path(__file__).resolve().parent.parent / 'index.html'
s = P.read_text(encoding='utf-8')

FRAME_BUSTER = "if(self===top){var f=document.getElementById('fb');f.parentNode.removeChild(f)}else{top.location.replace(self.location.href)}"
SB = 'https://xuecvkwqgvicrttlezzy.supabase.co'

def build(hashes):
    csp = '; '.join([
        "default-src 'self'",
        "script-src 'self' " + ' '.join(f"'sha256-{h}'" for h in hashes) + " https://challenges.cloudflare.com",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com",
        f"img-src 'self' data: blob: https://images.unsplash.com {SB}",
        f"media-src 'self' blob: {SB}",
        f"connect-src 'self' {SB} wss://xuecvkwqgvicrttlezzy.supabase.co https://*.googleusercontent.com https://profile.line-scdn.net https://obs.line-scdn.net",
        "frame-src https://challenges.cloudflare.com",
        "worker-src 'self' blob:",
        "manifest-src 'self'",
        "object-src 'none'",
        "base-uri 'none'",
        "form-action 'self'",
        "upgrade-insecure-requests",
    ])
    return ('<!--security:start-->\n'
            f'<meta http-equiv="Content-Security-Policy" content="{csp}">\n'
            '<meta name="referrer" content="strict-origin-when-cross-origin">\n'
            '<style id="fb">html{display:none!important}</style>\n'
            f'<script>{FRAME_BUSTER}</script>\n'
            '<!--security:end-->')

# 先拿掉舊的區塊，再算其餘內嵌 <script> 的雜湊
s = re.sub(r'<!--security:start-->.*?<!--security:end-->\n?', '', s, flags=re.S)
inline = re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', s, flags=re.S)
hashes = [base64.b64encode(hashlib.sha256(x.encode('utf-8')).digest()).decode() for x in inline + [FRAME_BUSTER]]
s = s.replace('<meta charset="UTF-8">\n', '<meta charset="UTF-8">\n' + build(hashes) + '\n', 1)
P.write_text(s, encoding='utf-8')
print(f'CSP 已更新：{len(inline)} 段內嵌程式 + 防嵌入程式')
