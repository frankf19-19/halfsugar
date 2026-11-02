// 微糖：手機驗證簡訊（Twilio Verify）
// 網站只能透過這支後端寄驗證碼；次數限制在資料庫 sms_reserve() 裡檢查：
//   每個帳號最多 3 封、每支手機最多 3 封、全站每小時最多 30 封。
// 需要的密鑰（Edge Functions → Secrets）：TWILIO_ACCOUNT_SID、TWILIO_AUTH_TOKEN、TWILIO_VERIFY_SID
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGINS = ["https://onethirdsugar.com", "https://www.onethirdsugar.com", "https://frankf19-19.github.io"];
const cors = (req: Request) => {
  const o = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": ORIGINS.includes(o) ? o : ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
};

const env = (k: string) => Deno.env.get(k) ?? "";
const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

async function twilio(path: string, body: Record<string, string>) {
  const r = await fetch(`https://verify.twilio.com/v2/Services/${env("TWILIO_VERIFY_SID")}/${path}`, {
    method: "POST",
    headers: {
      Authorization: "Basic " + btoa(env("TWILIO_ACCOUNT_SID") + ":" + env("TWILIO_AUTH_TOKEN")),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(body),
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, j };
}

Deno.serve(async (req) => {
  const h = cors(req);
  const reply = (o: unknown, status = 200) =>
    new Response(JSON.stringify(o), { status, headers: { ...h, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply({ error: "method" }, 405);

  // 誰在呼叫
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: ud, error: ue } = await admin.auth.getUser(jwt);
  const user = ud?.user;
  if (ue || !user) return reply({ error: "auth" }, 401);

  let b: { action?: string; phone?: string; code?: string } = {};
  try { b = await req.json(); } catch { /* ignore */ }
  const phone = String(b.phone || "").replace(/[\s-]/g, "");
  if (!/^\+8869\d{8}$/.test(phone)) return reply({ error: "bad_phone" }, 400);

  if (b.action === "send") {
    const { data: rs, error: re } = await admin.rpc("sms_reserve", { uid: user.id, ph: phone });
    if (re) return reply({ error: "server", detail: re.message }, 500);
    if (rs?.r !== "ok") return reply({ error: rs?.r || "server" }, rs?.r === "already" ? 200 : 429);
    let t = await twilio("Verifications", { To: phone, Channel: "sms", Locale: "zh-HK" });
    if (!t.ok && t.j?.code === 60220) t = await twilio("Verifications", { To: phone, Channel: "sms" }); // 不支援語系時退回預設
    if (!t.ok) {
      await admin.rpc("sms_refund", { rid: rs.id });
      const c = t.j?.code;
      return reply({ error: c === 60203 ? "twilio_rate" : c === 60200 || c === 60205 || c === 21211 ? "bad_phone" : "send_failed", code: c }, 502);
    }
    return reply({ ok: true, left: rs.left });
  }

  if (b.action === "check") {
    const code = String(b.code || "").replace(/\D/g, "");
    if (code.length < 4 || code.length > 10) return reply({ error: "bad_code" }, 400);
    const t = await twilio("VerificationCheck", { To: phone, Code: code });
    if (t.status === 404) return reply({ error: "expired" }, 400);       // 驗證碼過期或已用完嘗試次數
    if (!t.ok) return reply({ error: t.j?.code === 60202 ? "too_many_checks" : "check_failed", code: t.j?.code }, 400);
    if (t.j?.status !== "approved") return reply({ error: "wrong_code" }, 400);
    const { data: free } = await admin.rpc("sms_phone_free", { uid: user.id, ph: phone });
    if (free !== "ok") return reply({ error: free || "server" }, 409);
    const { error: ue2 } = await admin.auth.admin.updateUserById(user.id, { phone: phone.slice(1), phone_confirm: true });
    if (ue2) return reply({ error: /already|exists|unique/i.test(ue2.message) ? "phone_exists" : "server", detail: ue2.message }, 409);
    return reply({ ok: true });
  }

  return reply({ error: "action" }, 400);
});
