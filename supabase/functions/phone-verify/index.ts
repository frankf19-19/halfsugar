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

// f***k@gmail.com：只露出頭尾，讓本人認得、別人猜不到
function maskEmail(e: string) {
  const [u, d] = String(e || "").split("@");
  if (!d) return "";
  const m = u.length <= 2 ? u[0] + "*" : u[0] + "*".repeat(Math.min(6, u.length - 2)) + u[u.length - 1];
  return m + "@" + d;
}

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
async function twilioSafe(path: string, body: Record<string, string>) {
  try { return await twilio(path, body); } catch (_) { return { ok: false, status: 0, j: { code: "network" } as Record<string, unknown> }; }
}
// 客戶端 IP：優先用 Cloudflare 提供、無法偽造的 cf-connecting-ip；否則取 x-forwarded-for 最後一段（由閘道附加）
function clientIp(req: Request) {
  const cf = (req.headers.get("cf-connecting-ip") || "").trim();
  if (cf) return cf;
  const xff = (req.headers.get("x-forwarded-for") || "").split(",").map((x) => x.trim()).filter(Boolean);
  return xff.length ? xff[xff.length - 1] : "";
}

Deno.serve(async (req) => {
  try { return await handle(req); }
  catch (e) {
    console.error("phone-verify", e);
    return new Response(JSON.stringify({ error: "server" }), { status: 500, headers: { ...cors(req), "Content-Type": "application/json" } });
  }
});

// 真人驗證（Cloudflare Turnstile）：設定了 TURNSTILE_SECRET 才啟用
async function captchaOk(token: string, ip: string) {
  if (!env("TURNSTILE_SECRET")) return true;
  const tv = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: new URLSearchParams({ secret: env("TURNSTILE_SECRET"), response: token, ...(ip ? { remoteip: ip } : {}) }),
  }).then((r) => r.json()).catch(() => ({ success: false }));
  return !!tv?.success;
}

async function handle(req: Request): Promise<Response> {
  const h = cors(req);
  const reply = (o: unknown, status = 200) =>
    new Response(JSON.stringify(o), { status, headers: { ...h, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  if (req.method !== "POST") return reply({ error: "method" }, 405);

  let b: { action?: string; phone?: string; code?: string; mode?: string; captcha?: string } = {};
  try { b = await req.json(); } catch { /* ignore */ }

  // 用手機找回帳號（不用登入）：沒註冊的號碼不寄簡訊，回應也一樣，不能拿來試探別人有沒有註冊
  if (b.action === "find_send" || b.action === "find_check") {
    const fphone = String(b.phone || "").replace(/[\s-]/g, "");
    if (!/^\+8869\d{8}$/.test(fphone)) return reply({ error: "bad_phone" }, 400);
    const ip = clientIp(req);
    if (b.action === "find_send") {
      if (!(await captchaOk(String(b.captcha || ""), ip))) return reply({ error: "captcha" }, 400);
      const { data: rs, error: re } = await admin.rpc("sms_find_reserve", { ph: fphone, ip: ip || null });
      if (re) return reply({ error: "server" }, 500);
      if (rs?.r === "none") return reply({ ok: true });
      if (rs?.r !== "ok") return reply({ error: rs?.r || "server" }, 429);
      let t = await twilioSafe("Verifications", { To: fphone, Channel: "sms", Locale: "zh-HK" });
      if (!t.ok && t.status === 400 && ![60200, 60203, 60205, 60410, 21211, 21408, 21610, 21614].includes(Number(t.j?.code))) {
        t = await twilioSafe("Verifications", { To: fphone, Channel: "sms" });
      }
      if (!t.ok) { console.error("phone-verify find_send failed", JSON.stringify({ status: t.status, code: t.j?.code, message: t.j?.message })); await admin.rpc("sms_refund", { rid: rs.id }); return reply({ error: t.j?.code === 60203 ? "twilio_rate" : "send_failed", code: t.j?.code }, 502); }
      return reply({ ok: true });
    }
    const code = String(b.code || "").replace(/\D/g, "");
    if (code.length < 4 || code.length > 10) return reply({ error: "bad_code" }, 400);
    const t = await twilioSafe("VerificationCheck", { To: fphone, Code: code });
    if (t.status === 404) return reply({ error: "expired" }, 400);
    if (!t.ok) return reply({ error: t.j?.code === 60202 ? "too_many_checks" : "check_failed" }, 400);
    if (t.j?.status !== "approved") return reply({ error: "wrong_code" }, 400);
    const { data: em } = await admin.rpc("sms_find_take", { ph: fphone });
    if (!em) return reply({ error: "expired" }, 400);
    const anon = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false } });
    const { error: me } = await anon.auth.resetPasswordForEmail(em, { redirectTo: "https://onethirdsugar.com/" });
    return reply({ ok: true, email: maskEmail(em), mailed: !me });
  }

  // 誰在呼叫
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: ud, error: ue } = await admin.auth.getUser(jwt);
  const user = ud?.user;
  if (ue || !user) return reply({ error: "auth" }, 401);

  // 管理員檢查 Twilio 設定（不寄簡訊）
  if (b.action === "diag") {
    const { data: pr } = await admin.from("profiles").select("is_admin").eq("id", user.id).maybeSingle();
    if (!pr?.is_admin) return reply({ error: "auth" }, 403);
    const sid = env("TWILIO_ACCOUNT_SID"), auth = "Basic " + btoa(sid + ":" + env("TWILIO_AUTH_TOKEN"));
    const get = async (u: string) => { try { const r = await fetch(u, { headers: { Authorization: auth } }); return { status: r.status, j: await r.json().catch(() => ({})) }; } catch (e) { return { status: 0, j: { err: String(e) } }; } };
    const acc = await get(`https://api.twilio.com/2010-04-01/Accounts/${sid}.json`);
    const bal = await get(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Balance.json`);
    const svc = await get(`https://verify.twilio.com/v2/Services/${env("TWILIO_VERIFY_SID")}`);
    const geo = await get(`https://voice.twilio.com/v1/DialingPermissions/Countries/TW`);
    const al = await get(`https://monitor.twilio.com/v1/Alerts?PageSize=10`);
    const alerts = (al.j?.alerts || []).map((a: Record<string, unknown>) => ({ at: a.date_created, code: a.error_code, level: a.log_level, text: String(a.alert_text || "").replace(/\+?\d{8,}/g, "＊").slice(0, 300) }));
    return reply({
      secrets: { sid: !!sid, token: !!env("TWILIO_AUTH_TOKEN"), verify: !!env("TWILIO_VERIFY_SID") },
      account: { status: acc.status, type: acc.j?.type, state: acc.j?.status, code: acc.j?.code, message: acc.j?.message },
      balance: { status: bal.status, balance: bal.j?.balance, currency: bal.j?.currency },
      verify: { status: svc.status, name: svc.j?.friendly_name, code: svc.j?.code, message: svc.j?.message },
      tw_voice: { status: geo.status, low_risk: geo.j?.low_risk_numbers_enabled },
      alerts_status: al.status, alerts,
    });
  }

  // 恢復原本帳號（手機已驗證、且屬於另一個帳號時才會走到這裡）
  if (b.action === "recover") {
    const { data: rt, error: re } = await admin.rpc("sms_recover_peek", { uid: user.id });   // 先確認，不用掉
    if (re) return reply({ error: "server", detail: re.message }, 500);
    if (rt?.r !== "ok") return reply({ error: "recover_expired" }, 400);
    if (b.mode === "reset" && rt.email) {
      const anon = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), { auth: { persistSession: false } });
      const { error: me } = await anon.auth.resetPasswordForEmail(rt.email, { redirectTo: "https://onethirdsugar.com/" });
      if (me) return reply({ error: /rate|seconds/i.test(me.message) ? "mail_rate" : "mail_failed" }, 502);
    }
    await admin.rpc("sms_recover_take", { uid: user.id });   // 信寄出（或選擇直接登入）後才用掉
    let deleted = false;
    if (rt.empty) {   // 剛開、還沒建檔的空帳號才刪（管理員、有照片的帳號一律不刪）
      const { error: de } = await admin.auth.admin.deleteUser(user.id);
      deleted = !de;
      if (de) console.error("phone-verify recover delete", de.message);
    }
    return reply({ ok: true, email: maskEmail(rt.email), deleted });
  }

  const phone = String(b.phone || "").replace(/[\s-]/g, "");
  if (!/^\+8869\d{8}$/.test(phone)) return reply({ error: "bad_phone" }, 400);

  if (b.action === "send") {
    const ip = clientIp(req);
    if (!(await captchaOk(String(b.captcha || ""), ip))) return reply({ error: "captcha" }, 400);
    const { data: rs, error: re } = await admin.rpc("sms_reserve", { uid: user.id, ph: phone, ip: ip || null });
    if (re) return reply({ error: "server", detail: re.message }, 500);
    if (rs?.r !== "ok") return reply({ error: rs?.r || "server" }, rs?.r === "already" ? 200 : 429);
    let t = await twilioSafe("Verifications", { To: phone, Channel: "sms", Locale: "zh-HK" });
    // 語系不被接受時（400 且不是已知的號碼／頻率錯誤），改用預設語系再寄一次
    if (!t.ok && t.status === 400 && ![60200, 60203, 60205, 60410, 21211, 21408, 21610, 21614].includes(Number(t.j?.code))) {
      t = await twilioSafe("Verifications", { To: phone, Channel: "sms" });
    }
    if (!t.ok) {
      await admin.rpc("sms_refund", { rid: rs.id });
      const c = t.j?.code;
      console.error("phone-verify send failed", JSON.stringify({ status: t.status, code: c, message: t.j?.message, more: t.j?.more_info }));
      return reply({ error: c === 60203 ? "twilio_rate" : c === 60410 ? "blocked_by_twilio" : c === 60200 || c === 60205 || c === 21211 || c === 21614 ? "bad_phone" : "send_failed", code: c }, 502);
    }
    return reply({ ok: true, left: rs.left });
  }

  if (b.action === "check") {
    const code = String(b.code || "").replace(/\D/g, "");
    if (code.length < 4 || code.length > 10) return reply({ error: "bad_code" }, 400);
    const { data: ck } = await admin.rpc("sms_check_ok", { uid: user.id, ph: phone });
    if (ck === "already") return reply({ error: "already" }, 200);
    if (ck !== "ok") return reply({ error: "expired" }, 400);
    const t = await twilioSafe("VerificationCheck", { To: phone, Code: code });
    if (t.status === 404) return reply({ error: "expired" }, 400);       // 驗證碼過期或已用完嘗試次數
    if (!t.ok) return reply({ error: t.j?.code === 60202 ? "too_many_checks" : t.status === 0 ? "send_failed" : "check_failed", code: t.j?.code }, 400);
    if (t.j?.status !== "approved") return reply({ error: "wrong_code" }, 400);
    const { data: em, error: re2 } = await admin.rpc("sms_recover_start", { uid: user.id, ph: phone });
    if (re2) return reply({ error: "server", detail: re2.message }, 500);
    if (em !== null && em !== undefined) return reply({ recover: true, email: maskEmail(em) });
    const { data: free } = await admin.rpc("sms_phone_free", { uid: user.id, ph: phone });
    if (free !== "ok") return reply({ error: free || "server" }, 409);
    const { error: ue2 } = await admin.auth.admin.updateUserById(user.id, { phone: phone.slice(1), phone_confirm: true });
    if (ue2) return reply({ error: /already|exists|unique/i.test(ue2.message) ? "phone_exists" : "server", detail: ue2.message }, 409);
    return reply({ ok: true });
  }

  return reply({ error: "action" }, 400);
}

