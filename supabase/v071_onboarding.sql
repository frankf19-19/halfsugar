-- ============ v0.71 註冊流程減少流失 ============
-- 1. 建立檔案時「身材」「自我介紹」改成選填（上架後再補）：送審條件拿掉這兩項
-- 2. 註冊超過 24 小時還沒完成的人，自動寄一封「只差一步」提醒信（每人只寄一次、7 天內註冊的才寄）
create or replace function public.profiles_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if not coalesce(new.show_online, true) then new.last_active_at := null; end if;

  -- SQL Editor / 後端服務（沒有登入者）與管理員：不限制
  if auth.uid() is null or public.is_admin() then return new; end if;
  if current_setting('halfsugar.deleting', true) = '1' then return new; end if;   -- 刪除帳號流程中
  if new.birth_year is not null and new.birth_year > extract(year from now())::int - 18 then
    raise exception '必須年滿 18 歲才能使用本站';
  end if;

  new.id          := old.id;
  new.is_admin    := old.is_admin;
  new.review_note := old.review_note;
  new.wealth_verified_at := old.wealth_verified_at;
  if new.role = 'baby' and old.role is distinct from 'baby' then new.wealth_verified_at := null; end if;   -- 改成甜心：財力認證標章不再適用
  new.person_verified_at := old.person_verified_at;   -- 真人認證只有管理員能設定   -- 財力認證只有管理員能設定
  new.created_at  := old.created_at;
  new.founder_no  := old.founder_no;     -- 創始會員編號只由系統給
  new.founder_boost_until := old.founder_boost_until;
  new.approved_avatar_path := old.approved_avatar_path; new.approved_bio := old.approved_bio; new.approved_occupation := old.approved_occupation; new.approved_tags := old.approved_tags;
  -- 換頭像：真人認證要重新申請（避免用本人通過後換成別人的照片）
  if old.avatar_path is not null and new.avatar_path is distinct from old.avatar_path then new.person_verified_at := null; end if;
  if new.openers is distinct from old.openers then
    new.openers := array(select left(btrim(x), 200) from unnest(coalesce(new.openers, '{}')) x where btrim(x) <> '');
    if cardinality(new.openers) > 5 then raise exception '開場白最多 5 句'; end if;
  end if;
  if current_setting('halfsugar.avail', true) is distinct from '1' then   -- 今晚有空、旅行模式只能用專用函式設定
    new.free_until := old.free_until; new.travel_city := old.travel_city; new.travel_from := old.travel_from; new.travel_to := old.travel_to;
  end if;
  new.approved_at  := old.approved_at;    -- 只能由審核流程設定（下一個 trigger 處理）
  new.submitted_at := old.submitted_at;
  if new.last_active_at is not null then new.last_active_at := least(new.last_active_at, now()); end if;
  -- 性別與想認識的對象：第一次設定後不可更改
  if old.gender is not null then new.gender := old.gender; end if;
  if old.looking_for is not null then new.looking_for := old.looking_for; end if;
  -- 暱稱：送出審核後就不能改（只有被退件時可以修改）
  if old.nickname is not null and old.status not in ('incomplete','rejected') then new.nickname := old.nickname; end if;
  if new.role = 'baby' then new.budget := null; else new.expect_budget := null; end if;
  if new.gender = 'male' then new.cup := null; end if;
  if new.role in ('daddy','mommy') and new.budget is null and old.status <> 'incomplete' then
    raise exception 'Sugar Daddy／Mommy 請選擇每月相處預算';
  end if;
  if (new.role = 'daddy' and new.gender = 'female') or (new.role = 'mommy' and new.gender = 'male') then
    raise exception 'Sugar Daddy 限男性、Sugar Mommy 限女性';
  end if;
  if new.avatar_path is not null and new.avatar_path not like new.id::text || '/%' then
    raise exception '頭像必須是自己上傳的照片';
  end if;

  if old.status = 'suspended' then new.status := 'suspended'; return new; end if;

  if old.status = 'incomplete' then
    if exists (select 1 from auth.users u join public.banned_phones b on b.phone_hash = private.phone_hash(u.phone)
               where u.id = new.id and u.phone is not null and u.phone <> '') then
      raise exception '這支手機號碼無法在本站註冊。如有疑問請聯絡客服。';
    end if;
    if nullif(btrim(new.nickname),'') is not null and new.gender is not null and new.looking_for is not null and new.role is not null
       and new.birth_year is not null and new.city is not null and new.avatar_path is not null
       and new.age_confirmed and new.agreed_terms_at is not null
       and (new.role = 'baby' or new.budget is not null)
       and exists (select 1 from auth.users u where u.id = new.id and u.phone is not null and u.phone_confirmed_at is not null) then
      new.status := 'pending';
    else
      new.status := 'incomplete';
    end if;
    return new;
  end if;

  if (new.nickname, new.bio, new.avatar_path, new.occupation, new.tags, new.role, new.birth_year, new.gender)
     is distinct from (old.nickname, old.bio, old.avatar_path, old.occupation, old.tags, old.role, old.birth_year, old.gender) then
    new.status := 'pending';
  elsif old.status = 'rejected'
     and ((new.city, new.looking_for, new.height_cm) is distinct from (old.city, old.looking_for, old.height_cm)
          or current_setting('halfsugar.resubmit', true) = '1') then
    new.status := 'pending';
  else
    new.status := old.status;
  end if;
  return new;
end $$;

create or replace function public.profiles_unsuspend_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'suspended' and new.status = 'pending'
     and not (nullif(btrim(new.nickname),'') is not null and new.gender is not null and new.looking_for is not null and new.role is not null
       and new.birth_year is not null and new.city is not null and new.avatar_path is not null
       and new.age_confirmed and new.agreed_terms_at is not null
       and (new.role = 'baby' or new.budget is not null)
       and exists (select 1 from auth.users u where u.id = new.id and u.phone is not null and u.phone_confirmed_at is not null)) then
    new.status := 'incomplete';
  end if;
  return new;
end $$;

create table if not exists private.onboard_reminders (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  sent_at timestamptz not null default now(),
  stage   text
);
revoke all on private.onboard_reminders from public, anon, authenticated;

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
      html := '<p>你已經完成手機驗證了，只差建立檔案就能送審。</p>'
           || '<p>現在只要填暱稱、身分、年齡、所在地和一張頭像，大約 2 分鐘；自我介紹可以上架後再慢慢寫。</p>';
    else
      stage := 'phone';
      subj := '完成手機驗證，就能開始認識微糖的會員';
      html := '<p>你的微糖帳號已經建立好了，下一步是手機驗證。</p>'
           || '<p>手機只用來確認你是真人、一人一個帳號，號碼不會顯示給任何會員。</p>';
    end if;
    html := '<div style="font-family:sans-serif;font-size:15px;line-height:1.8;color:#111;max-width:480px">'
      || html
      || '<p><a href="https://onethirdsugar.com/#/onboarding" style="display:inline-block;background:#111;color:#fff;padding:10px 22px;text-decoration:none">繼續完成註冊</a></p>'
      || '<p style="font-size:12px;color:#777">開站期間所有功能免費。這是唯一一封提醒信，之後不會再寄；如果不是你註冊的，忽略這封信即可。</p></div>';
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

select cron.unschedule('onboard-remind') where exists (select 1 from cron.job where jobname = 'onboard-remind');
select cron.schedule('onboard-remind', '17 * * * *', $$select private.onboard_remind_run()$$);
