-- v0.73.0 會員通知信、提醒信、管理員通知信改用和登入信同一套版型（logo、標題、按鈕、頁尾）。
create or replace function private.mail_wrap(title text, body_html text, cta_text text, cta_url text, note_html text default '')
returns text language sql immutable set search_path = public, private as $f$
select '<!DOCTYPE html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' || title || '</title></head>'
 || '<body style="margin:0;padding:0;background:#F4F3F0;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F3F0;padding:40px 12px;"><tr><td align="center">'
 || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border:1px solid #E8E5E0;">'
 || '<tr><td align="center" style="padding:40px 32px 8px;"><img src="https://onethirdsugar.com/brand/mail-logo.png" width="120" height="56" alt="微糖" style="display:block;border:0;"></td></tr>'
 || '<tr><td align="center" style="padding:24px 32px 0;font-family:''Noto Serif TC'',''PingFang TC'',''Microsoft JhengHei'',serif;font-size:22px;letter-spacing:4px;color:#1A1A1A;font-weight:400;">' || title || '</td></tr>'
 || '<tr><td align="center" style="padding:10px 32px 0;"><div style="width:32px;height:1px;background:#B04A62;line-height:1px;font-size:0;">&nbsp;</div></td></tr>'
 || '<tr><td style="padding:24px 28px 0;font-family:''PingFang TC'',''Microsoft JhengHei'',''Noto Sans TC'',sans-serif;font-size:15px;line-height:1.9;color:#3A3A3A;text-align:center;">' || body_html || '</td></tr>'
 || '<tr><td align="center" style="padding:30px 32px 8px;"><a href="' || cta_url || '" style="display:inline-block;background:#1A1A1A;color:#FFFFFF;text-decoration:none;font-family:''PingFang TC'',''Microsoft JhengHei'',sans-serif;font-size:14px;letter-spacing:4px;padding:15px 40px;">' || cta_text || '</a></td></tr>'
 || '<tr><td style="padding:26px 28px 36px;font-family:''PingFang TC'',''Microsoft JhengHei'',sans-serif;font-size:12px;line-height:1.8;color:#8A8580;text-align:center;border-bottom:1px solid #F0EEEA;">' || coalesce(note_html, '') || '</td></tr>'
 || '<tr><td style="padding:22px 20px 30px;font-family:''PingFang TC'',''Microsoft JhengHei'',sans-serif;font-size:11px;line-height:1.9;color:#A8A39D;text-align:center;letter-spacing:1px;">'
 || '微糖 1/3 Sugar · 台灣甜心交友<br>系統自動寄出，請勿直接回覆<br>客服信箱 <a href="mailto:support@onethirdsugar.com" style="color:#8A8580;">support@onethirdsugar.com</a><br>'
 || '<a href="https://onethirdsugar.com" style="color:#8A8580;">onethirdsugar.com</a> · 僅限年滿 18 歲成年人使用</td></tr>'
 || '</table></td></tr></table></body></html>'
$f$;
revoke execute on function private.mail_wrap(text, text, text, text, text) from public, anon, authenticated;

create or replace function private.member_notify_run()
returns int language plpgsql security definer set search_path = public, private, extensions as $$
declare
  cfg private.mail_config%rowtype; k text; t0 timestamptz := now(); n int := 0; r record; parts text[]; html text;
begin
  select * into cfg from private.mail_config where id = 1;
  if not coalesce(cfg.enabled, false) then return 0; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null then return 0; end if;

  insert into private.member_notify (user_id) select id from profiles on conflict (user_id) do nothing;

  for r in
    with ev as (   -- 最近一天內的新訊息與新心動，算出收件人
      select case when mt.user_a = m.sender_id then mt.user_b else mt.user_a end as uid, 'm' as kind, m.created_at
        from messages m join matches mt on mt.id = m.match_id
       where m.created_at > t0 - interval '1 day' and m.read_at is null and m.recalled_at is null and mt.closed_at is null
      union all
      select l.to_id, 'l', l.created_at from likes l
        join profiles s on s.id = l.from_id and s.status = 'approved'
       where l.created_at > t0 - interval '1 day'
         and not exists (select 1 from blocks b where (b.blocker_id = l.to_id and b.blocked_id = l.from_id) or (b.blocker_id = l.from_id and b.blocked_id = l.to_id))
    )
    select p.id, u.email,
           count(*) filter (where ev.kind = 'm' and p.notify_email_msg)  as msgs,
           count(*) filter (where ev.kind = 'l' and p.notify_email_like) as likes
      from ev
      join profiles p on p.id = ev.uid
      join auth.users u on u.id = p.id
      join private.member_notify mn on mn.user_id = p.id
     where ev.created_at > mn.last_at
       and p.status = 'approved'
       and u.email is not null and u.email <> '' and u.email_confirmed_at is not null
       and (mn.last_seen is null or mn.last_seen < t0 - interval '10 minutes')
       and (mn.last_sent is null or mn.last_sent < t0 - interval '1 hour')
       and (mn.day_on is distinct from current_date or mn.day_count < 6)
     group by p.id, u.email
    having count(*) filter (where ev.kind = 'm' and p.notify_email_msg) > 0
        or count(*) filter (where ev.kind = 'l' and p.notify_email_like) > 0
     limit 80
  loop
    parts := array[]::text[];
    if r.msgs  > 0 then parts := parts || (r.msgs  || ' 則新訊息'); end if;
    if r.likes > 0 then parts := parts || (r.likes || ' 個人對你心動'); end if;
    html := private.mail_wrap('你有新動態',
      '你在微糖有 ' || array_to_string(parts, '、') || '。',
      '打開微糖查看', 'https://onethirdsugar.com/#/' || case when r.msgs > 0 then 'matches' else 'likes' end,
      '不想收到這類通知？<br>登入後到「我的 → 設定 → Email 通知」關閉。');
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
      body := jsonb_build_object('from', cfg.from_email, 'to', jsonb_build_array(r.email),
                'subject', '你在微糖有新動態', 'html', html));
    update private.member_notify set last_at = t0, last_sent = t0,
      day_count = case when day_on = current_date then day_count + 1 else 1 end, day_on = current_date
     where user_id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function private.member_notify_run() from public, anon, authenticated;

create or replace function private.onboard_remind_run()
returns int language plpgsql security definer set search_path = public, private, extensions as $$
declare
  cfg private.mail_config%rowtype; k text; n int := 0; r record; html text; subj text; stage text;
begin
  select * into cfg from private.mail_config where id = 1;
  if not coalesce(cfg.enabled, false) then return 0; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null then return 0; end if;

  for r in
    select p.id, u.email, (u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) as phone_ok
      from profiles p join auth.users u on u.id = p.id
     where p.status = 'incomplete' and not coalesce(p.is_admin, false)
       and u.email is not null and u.email <> '' and u.email_confirmed_at is not null
       and p.created_at < now() - interval '24 hours'
       and p.created_at > now() - interval '7 days'
       and not exists (select 1 from private.onboard_reminders o where o.user_id = p.id)
     order by p.created_at
     limit 50
  loop
    if r.phone_ok then
      stage := 'profile';
      subj := '你的微糖檔案只差一步';
      html := '你已經完成手機驗證了，只差建立檔案就能送審。<br>只要填暱稱、身分、年齡、所在地和一張頭像，<br>大約 2 分鐘；自我介紹可以上架後再慢慢寫。';
    else
      stage := 'phone';
      subj := '完成手機驗證，就能開始認識微糖的會員';
      html := '你的微糖帳號已經建立好了，下一步是手機驗證。<br>手機只用來確認你是真人、一人一個帳號，<br>號碼不會顯示給任何會員。';
    end if;
    html := private.mail_wrap(case stage when 'profile' then '只差一步' else '完成手機驗證' end, html,
      '繼續完成註冊', 'https://onethirdsugar.com/#/onboarding',
      '開站期間所有功能免費。<br>這是唯一一封提醒信，之後不會再寄；<br>如果不是你註冊的，忽略這封信即可。');
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
      body := jsonb_build_object('from', cfg.from_email, 'to', jsonb_build_array(r.email), 'subject', subj, 'html', html));
    insert into private.onboard_reminders (user_id, stage) values (r.id, stage);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function private.onboard_remind_run() from public, anon, authenticated;

create or replace function private.admin_mail(subj text, body_html text)
returns void language plpgsql security definer set search_path = public, private, extensions as $$
declare cfg private.mail_config%rowtype; k text; tos jsonb;
begin
  select * into cfg from private.mail_config where id = 1;
  if not coalesce(cfg.enabled, false) then return; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if k is null then return; end if;
  if nullif(btrim(cfg.admin_email), '') is not null then
    tos := jsonb_build_array(btrim(cfg.admin_email));
  else
    select coalesce(jsonb_agg(distinct u.email), '[]'::jsonb) into tos
      from profiles p join auth.users u on u.id = p.id
     where p.is_admin and u.email is not null and u.email <> '';
  end if;
  if jsonb_array_length(tos) = 0 then return; end if;
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
    body := jsonb_build_object('from', cfg.from_email, 'to', tos, 'subject', subj,
      'html', private.mail_wrap('管理員通知', body_html, '打開後台', 'https://onethirdsugar.com/#/admin', '這封信只寄給微糖管理員。')));
end $$;
revoke execute on function private.admin_mail(text, text) from public, anon, authenticated;
