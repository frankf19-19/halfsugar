-- =====================================================================
-- 微糖 1/3 SUGAR — Supabase 資料庫結構  (schema v0.46.0)
-- 在 Supabase Dashboard → SQL Editor 整段貼上執行（可重複執行）
-- =====================================================================

create extension if not exists pgcrypto;

-- 內部用函式放在 private schema（不對外開放 API 呼叫，只給權限規則使用）
create schema if not exists private;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------
-- 0. 共用函式
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select is_admin from public.profiles where id = auth.uid()), false);
end $$;

-- 目前登入者自己的狀態（給 RLS 用，避免 profiles 規則自我遞迴）
create or replace function public.my_status()
returns text
language plpgsql stable security definer set search_path = public as $$
begin
  return (select status from public.profiles where id = auth.uid());
end $$;

-- ---------------------------------------------------------------------
-- 1. profiles  會員檔案（與 auth.users 一對一）
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  nickname        text,
  gender          text check (gender in ('male','female')),
  looking_for     text check (looking_for in ('male','female')),   -- 設定後不可更改
  role            text check (role in ('daddy','mommy','baby')),   -- Sugar Daddy / Sugar Mommy / 甜心
  birth_year      int  check (birth_year between 1900 and 2100),
  city            text,
  height_cm       int  check (height_cm between 100 and 250),
  occupation      text,
  bio             text,
  tags            text[] default '{}',
  avatar_path     text,
  status          text not null default 'incomplete'
                  check (status in ('incomplete','pending','approved','rejected','suspended')),
  review_note     text,
  is_admin        boolean not null default false,
  agreed_terms_at timestamptz,
  age_confirmed   boolean not null default false,
  hidden          boolean not null default false,   -- 不出現在探索
  show_online     boolean not null default true,    -- 顯示上線狀態
  last_active_at  timestamptz default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table public.profiles add column if not exists role text check (role in ('daddy','mommy','baby'));
alter table public.profiles add column if not exists hidden boolean not null default false;
alter table public.profiles add column if not exists show_online boolean not null default true;
alter table public.profiles add column if not exists submitted_at timestamptz;
alter table public.profiles add column if not exists approved_at timestamptz;
alter table public.profiles add column if not exists wealth_verified_at timestamptz;
alter table public.profiles add column if not exists person_verified_at timestamptz;   -- 真人認證通過時間   -- 財力認證通過時間
-- 身材、罩杯（選填、只限女性）、相處方式、見面頻率、甜心期望預算
-- 創始會員：前 100 位第一次通過審核的會員（不對外顯示，正式收費後給優惠用）
alter table public.profiles add column if not exists founder_no int unique;
alter table public.profiles add column if not exists founder_boost_until timestamptz;
alter table public.profiles add column if not exists free_until timestamptz;        -- 今晚有空：到期時間（隔天早上 6 點）
alter table public.profiles add column if not exists travel_city text;              -- 旅行模式：要去的城市
alter table public.profiles add column if not exists travel_from date;
alter table public.profiles add column if not exists travel_to date;
alter table public.profiles add column if not exists openers text[] not null default '{}';
alter table public.profiles add column if not exists approved_avatar_path text;
alter table public.profiles add column if not exists approved_bio text;          -- 最近一次通過審核的自介、職業、興趣：重新送審期間給配對對象看
alter table public.profiles add column if not exists approved_occupation text;
alter table public.profiles add column if not exists approved_tags text[];   -- 最近一次通過審核的頭像：重新送審期間，配對對象看到的是這張   -- 我的開場白（只有本人看得到）   -- 甜心創始會員：探索優先曝光到期日
alter table public.profiles add column if not exists body_type text check (body_type in ('slim','fit','average','athletic','curvy','chubby'));
alter table public.profiles add column if not exists cup text check (cup in ('A','B','C','D','E','F+'));
alter table public.profiles add column if not exists relation_types text[] not null default '{}'
  check (relation_types <@ array['long','short','dinner','travel','companion']);
alter table public.profiles add column if not exists meet_freq text check (meet_freq in ('weekly','twomonth','monthly','flexible'));
alter table public.profiles add column if not exists expect_budget text
  check (expect_budget in ('negotiable','lt30k','30to50k','50to80k','80to120k','gt120k'));
-- 每月相處預算（Sugar Daddy／Mommy 必填；甜心不填）
alter table public.profiles add column if not exists budget text
  check (budget in ('negotiable','lt30k','30to50k','50to80k','80to120k','gt120k'));
create index if not exists profiles_browse_idx on public.profiles(status, gender, city, last_active_at desc);
alter table public.profiles drop constraint if exists profiles_looking_for_check;
alter table public.profiles drop constraint if exists profiles_city_check;
alter table public.profiles add constraint profiles_city_check check (city is null or city in
  ('台北市','新北市','桃園市','新竹','台中市','彰化','雲林','嘉義','台南市','高雄市','屏東','基隆','宜蘭','花蓮','台東','南投','苗栗','澎湖','金門','海外'));
alter table public.profiles add constraint profiles_looking_for_check check (looking_for in ('male','female'));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- 一般會員不得自行改審核狀態、管理員身分；修改公開資料會退回待審
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
       and new.body_type is not null and nullif(btrim(new.bio),'') is not null
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
create or replace function public.profiles_submitted_at()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' and old.status is distinct from 'pending' then new.submitted_at := now(); end if;
  -- 被退件：視同重新審核，通過前不能瀏覽其他會員（避免什麼都不改、重送一次就恢復）
  if new.status = 'rejected' and old.status is distinct from 'rejected' then new.approved_at := null; end if;
  -- 解除停權後要重新審核：清掉舊的通過時間，審核前不能瀏覽其他會員
  if old.status = 'suspended' and new.status <> 'suspended' and new.status <> 'approved' then new.approved_at := null; end if;
  if new.status = 'approved' then new.approved_avatar_path := new.avatar_path; new.approved_bio := new.bio; new.approved_occupation := new.occupation; new.approved_tags := new.tags; end if;
  if new.status = 'approved' and new.approved_at is null then
    new.approved_at := now();
    -- 前 100 位第一次通過審核的會員，記錄為創始會員（管理員不算）
    if new.founder_no is null and not coalesce(new.is_admin, false) then
      perform pg_advisory_xact_lock(hashtext('founder_no'));
      if (select count(*) from public.profiles where founder_no is not null) < 100 then
        new.founder_no := coalesce((select max(founder_no) from public.profiles), 0) + 1;
        -- 甜心創始會員：通過審核起 60 天探索優先曝光；Sugar Daddy／Mommy 的優惠（正式收費後 3 個月微糖會員）收費時依 founder_no 發放
        if new.role = 'baby' then new.founder_boost_until := now() + interval '60 days'; end if;
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_zz_submitted_trg on public.profiles;
create trigger profiles_zz_submitted_trg before update on public.profiles
  for each row execute function public.profiles_submitted_at();

drop trigger if exists profiles_guard_trg on public.profiles;
create trigger profiles_guard_trg before update on public.profiles
  for each row execute function public.profiles_guard();

-- ---------------------------------------------------------------------
-- 2. photos  相簿（公開照 / 私密照）
-- ---------------------------------------------------------------------
create table if not exists public.photos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  path        text not null unique,
  is_private  boolean not null default false,
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_note text,
  created_at  timestamptz not null default now()
);
create index if not exists photos_user_idx on public.photos(user_id, status);

-- 新照片一律待審；照片檔案路徑上傳後不能改（避免偷換已通過的照片）
create or replace function public.photos_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    new.user_id := auth.uid(); new.status := 'pending'; new.review_note := null; new.created_at := now();
    perform pg_advisory_xact_lock(hashtext('photos:' || auth.uid()::text));   -- 同時上傳多張時也不會超過上限
    if (select count(*) from public.photos where user_id = auth.uid()) >= 20 then raise exception '相簿最多 20 張'; end if;
  else
    new.user_id := old.user_id; new.path := old.path; new.status := old.status;
    new.review_note := old.review_note; new.created_at := old.created_at;
    -- 私密照改成公開照：重新審核
    if old.is_private and not new.is_private then new.status := 'pending'; end if;
  end if;
  return new;
end $$;
drop trigger if exists photos_guard_trg on public.photos;
create trigger photos_guard_trg before insert or update on public.photos
  for each row execute function public.photos_guard();

create table if not exists public.photo_grants (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, viewer_id)
);

create table if not exists public.photo_requests (
  requester_id uuid not null references public.profiles(id) on delete cascade,
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','granted','denied')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, owner_id)
);

-- ---------------------------------------------------------------------
-- 3. blocks / likes / matches / messages
-- ---------------------------------------------------------------------
create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- 我和某人之間是否有封鎖（只能查自己，不能查別人之間）
create or replace function private.is_blocked_with(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks
                 where (blocker_id = auth.uid() and blocked_id = other) or (blocker_id = other and blocked_id = auth.uid()));
$$;

-- 封鎖後：關閉配對、清掉雙方的喜歡、私密照授權與索取
create or replace function public.handle_block()
returns trigger language plpgsql security definer set search_path = public as $$
declare a uuid := least(new.blocker_id, new.blocked_id); b uuid := greatest(new.blocker_id, new.blocked_id);
begin
  update public.matches set closed_at = coalesce(closed_at, now()), closed_by = null where user_a = a and user_b = b;   -- 對方先結束對話再封鎖時，也要讓雙方都看不到
  delete from public.likes where (from_id = a and to_id = b) or (from_id = b and to_id = a);
  delete from public.photo_grants where (owner_id = a and viewer_id = b) or (owner_id = b and viewer_id = a);
  delete from public.photo_requests where (requester_id = a and owner_id = b) or (requester_id = b and owner_id = a);
  delete from public.wealth_requests where (requester_id = a and owner_id = b) or (requester_id = b and owner_id = a);
  return new;
end $$;
drop trigger if exists blocks_after_trg on public.blocks;
create trigger blocks_after_trg after insert on public.blocks
  for each row execute function public.handle_block();

create table if not exists public.likes (
  from_id    uuid not null references public.profiles(id) on delete cascade,
  to_id      uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_id, to_id),
  check (from_id <> to_id)
);
create index if not exists likes_to_idx on public.likes(to_id);

create table if not exists public.matches (
  id              uuid primary key default gen_random_uuid(),
  user_a          uuid not null references public.profiles(id) on delete cascade,
  user_b          uuid not null references public.profiles(id) on delete cascade,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz,
  last_message    text,
  closed_at       timestamptz,          -- 解除配對（保留對話供檢舉調查）
  unique (user_a, user_b),
  check (user_a < user_b)
);
alter table public.matches add column if not exists closed_at timestamptz;
alter table public.matches add column if not exists reopened_at timestamptz;
alter table public.matches add column if not exists closed_by uuid;            -- 誰結束了對話（另一方仍可唯讀查看、檢舉）
alter table public.matches add column if not exists replied_at timestamptz;     -- 對方（非發起人）第一次回覆的時間
alter table public.profiles add column if not exists accept_from text not null default 'all' check (accept_from in ('all','liked'));
alter table public.matches add column if not exists initiator uuid references public.profiles(id) on delete set null;  -- 主動開啟對話的人
create index if not exists matches_initiator_idx on public.matches(initiator, created_at);  -- 重新配對：只看得到這之後的訊息

-- 「心動」不再自動開啟對話（v1.12 起：會員可直接傳訊息）
drop trigger if exists likes_match_trg on public.likes;
create or replace function public.handle_like()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if false then
    insert into public.matches as m (user_a, user_b)
    values (least(new.from_id, new.to_id), greatest(new.from_id, new.to_id))
    on conflict (user_a, user_b) do update
      set closed_at = null,
          reopened_at = case when m.closed_at is not null then now() else m.reopened_at end,
          last_message = case when m.closed_at is not null then null else m.last_message end,
          last_message_at = case when m.closed_at is not null then null else m.last_message_at end;
  end if;
  return new;
end $$;


-- 結束對話：按下的人看不到這段對話；另一方保留唯讀，並且不能再主動開啟
create or replace function public.unmatch(mid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.matches;
begin
  select * into m from public.matches where id = mid and (user_a = auth.uid() or user_b = auth.uid());
  if not found then raise exception '找不到這個對話'; end if;
  update public.matches set closed_at = now(), closed_by = auth.uid() where id = mid and closed_at is null;
end $$;

create table if not exists public.messages (
  id         bigint generated always as identity primary key,
  match_id   uuid not null references public.matches(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists messages_match_idx on public.messages(match_id, created_at);
-- v0.27：聊天可以傳照片、可以收回訊息
alter table public.messages add column if not exists image_path text;
alter table public.messages add column if not exists recalled_at timestamptz;
alter table public.messages add column if not exists invite_id uuid;   -- v0.30 約會邀請卡
alter table public.messages drop constraint if exists messages_body_check;
create table if not exists public.message_recalls (
  message_id  bigint primary key,
  match_id    uuid not null references public.matches(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  body        text,
  image_path  text,
  sent_at     timestamptz,
  recalled_at timestamptz not null default now()
);
alter table public.message_recalls enable row level security;
revoke all on public.message_recalls from anon, authenticated;
alter table public.messages add constraint messages_body_check
  check (char_length(body) <= 2000 and (char_length(body) >= 1 or image_path is not null or recalled_at is not null));

create or replace function public.handle_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.matches set last_message_at = new.created_at, last_message = case when new.image_path is not null and new.body = '' then '[照片]' else left(new.body, 80) end,
         replied_at = case when replied_at is null and initiator is not null and new.sender_id <> initiator then new.created_at else replied_at end
   where id = new.match_id;
  return new;
end $$;
drop trigger if exists messages_after_trg on public.messages;
create trigger messages_after_trg after insert on public.messages
  for each row execute function public.handle_message();

-- 收回最後一則訊息時，訊息列表的預覽也跟著改
create or replace function public.handle_message_recall()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.recalled_at is not null and old.recalled_at is null then
    update public.matches set last_message = '訊息已收回' where id = new.match_id and last_message_at = new.created_at;
  end if;
  return new;
end $$;
drop trigger if exists messages_recall_trg on public.messages;
create trigger messages_recall_trg after update of recalled_at on public.messages
  for each row execute function public.handle_message_recall();

-- 訊息：時間由伺服器決定；之後只能標記已讀，內容與寄件人不得修改
create or replace function public.messages_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    if public.my_status() is distinct from 'approved' and public.my_status() is distinct from 'pending' then
      raise exception '你的帳號目前無法傳送訊息';   -- 退件、停權的帳號不能再傳（包含從已開啟的對話、邀請卡）
    end if;
    new.created_at := clock_timestamp(); new.read_at := null;
    perform 1 from public.matches where id = new.match_id for update;   -- 同一段對話的送出排隊，避免連點繞過規則
    if not private.can_send(new.match_id) then raise exception '對方回覆後才能繼續傳訊息'; end if;
    if not private.partner_active(new.match_id) then raise exception '對方目前無法接收訊息'; end if;
    new.recalled_at := null;
    if new.invite_id is not null and current_setting('halfsugar.invite', true) is distinct from '1' then
      raise exception '約會邀請只能用邀請卡送出';
    end if;
    if new.image_path is not null and new.image_path !~ ('^' || auth.uid()::text || '/' || new.match_id::text || '-[0-9]+\.jpg$') then
      raise exception '照片路徑不正確';
    end if;
  else
    new.sender_id := old.sender_id; new.match_id := old.match_id; new.created_at := old.created_at; new.invite_id := old.invite_id;
    if old.sender_id = auth.uid() then
      new.read_at := old.read_at;
      if new.recalled_at is not null and old.recalled_at is null then   -- 寄件人收回：會員看不到，原內容另存一份給管理員
        if exists (select 1 from public.matches m where m.id = old.match_id and m.initiator = auth.uid() and m.replied_at is null) then
          raise exception '對方回覆前不能收回第一則訊息';
        end if;
        if old.invite_id is not null then raise exception '約會邀請不能收回，請改用「取消邀請」'; end if;
        insert into public.message_recalls (message_id, match_id, sender_id, body, image_path, sent_at)
        values (old.id, old.match_id, old.sender_id, old.body, old.image_path, old.created_at) on conflict do nothing;
        new.recalled_at := now(); new.body := ''; new.image_path := null;
      else
        new.recalled_at := old.recalled_at; new.body := old.body; new.image_path := old.image_path;
      end if;
    else
      new.body := old.body; new.image_path := old.image_path; new.recalled_at := old.recalled_at;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists messages_guard_trg on public.messages;
create trigger messages_guard_trg before insert or update on public.messages
  for each row execute function public.messages_guard();

-- 可以瀏覽其他會員：已上架，或曾經上架、目前因修改資料重新審核中（新註冊的人要等第一次審核通過）
create or replace function private.can_browse()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid()
                 and (status = 'approved' or (status = 'pending' and approved_at is not null)));
$$;

-- 我和某人之間是否有未解除的配對
create or replace function private.has_open_match(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.matches m where m.closed_at is null
                 and m.user_a = least(auth.uid(), other) and m.user_b = greatest(auth.uid(), other));
$$;

-- 對方是否還能收訊息（已上架或重新審核中）
create or replace function private.partner_active(mid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.matches m join public.profiles p
                   on p.id = case when m.user_a = auth.uid() then m.user_b else m.user_a end
                  where m.id = mid and p.status in ('approved','pending'));
$$;

-- 主動開啟的一方，在對方回覆前只能先傳一則
create or replace function private.can_send(mid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select m.initiator is distinct from auth.uid()
        or m.replied_at is not null
        or not exists (select 1 from public.messages x where x.match_id = m.id and x.sender_id = auth.uid()
                     and (m.reopened_at is null or x.created_at >= m.reopened_at))
      from public.matches m where m.id = mid), false);
$$;

-- 雙方方向是否吻合（我想認識的性別 = 對方性別，且對方想認識的性別 = 我的性別）
create or replace function private.is_compatible(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles a, public.profiles b
                 where a.id = auth.uid() and b.id = other
                   and a.looking_for = b.gender and b.looking_for = a.gender);
$$;

-- 私密照數量（看不到私密照的人也能知道對方有幾張，才能索取）
create or replace function public.private_photo_count(uid uuid)
returns int language sql stable security definer set search_path = public as $$
  select case when private.is_blocked_with(uid) or not private.can_browse()
              or not private.is_compatible(uid)
              or not exists (select 1 from public.profiles where id = uid and status = 'approved') then 0
         else (select count(*)::int from public.photos where user_id = uid and is_private and status = 'approved') end;
$$;

revoke execute on function public.private_photo_count(uuid) from anon, public;
grant execute on function public.private_photo_count(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. reports  檢舉
-- ---------------------------------------------------------------------
-- 財力文件查看申請（詳細規則見後面「財力認證」段落；先建表，名單函式會用到）
create table if not exists public.wealth_requests (
  requester_id uuid not null references public.profiles(id) on delete cascade,
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','granted','denied')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, owner_id)
);

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  reason      text not null check (reason in ('fake','harass','money','adult_industry','minor','other')),
  detail      text,
  status      text not null default 'open' check (status in ('open','resolved','dismissed')),
  created_at  timestamptz not null default now()
);
-- 檢舉人刪除帳號時保留檢舉紀錄（檢舉人欄位清空），避免證據消失
alter table public.reports alter column reporter_id drop not null;
alter table public.reports drop constraint if exists reports_reporter_id_fkey;
alter table public.reports add constraint reports_reporter_id_fkey
  foreign key (reporter_id) references public.profiles(id) on delete set null;
-- v0.29：被檢舉的人刪帳號，檢舉與證據也要留著（被檢舉人欄位清空，另存當時的暱稱）
alter table public.reports alter column reported_id drop not null;
alter table public.reports drop constraint if exists reports_reported_id_fkey;
alter table public.reports add constraint reports_reported_id_fkey
  foreign key (reported_id) references public.profiles(id) on delete set null;
alter table public.reports add column if not exists reported_nickname text;

-- 停權手機黑名單：只存手機號碼的加密指紋（看不出原號碼），任何會員都讀不到
create table if not exists public.banned_phones (
  phone_hash text primary key,
  created_at timestamptz not null default now()
);
alter table public.banned_phones enable row level security;
revoke all on public.banned_phones from anon, authenticated;

create or replace function private.phone_hash(ph text)
returns text language sql immutable set search_path = public, extensions as $$
  select encode(digest('halfsugar:' || regexp_replace(coalesce(ph,''), '\D', '', 'g'), 'sha256'), 'hex');
$$;

-- 停權時把手機列入黑名單；解除停權時移除
create or replace function public.profiles_ban_phone()
returns trigger language plpgsql security definer set search_path = public as $$
declare ph text;
begin
  if new.status = 'suspended' and old.status is distinct from 'suspended' then
    update public.matches set closed_at = now() where (user_a = new.id or user_b = new.id) and closed_at is null;
  end if;
  select phone into ph from auth.users where id = new.id;
  if ph is null or ph = '' then return new; end if;
  if new.status = 'suspended' and old.status is distinct from 'suspended' then
    insert into public.banned_phones (phone_hash) values (private.phone_hash(ph)) on conflict do nothing;
  elsif old.status = 'suspended' and new.status <> 'suspended' then
    delete from public.banned_phones where phone_hash = private.phone_hash(ph);
  end if;
  return new;
end $$;
drop trigger if exists profiles_ban_phone_trg on public.profiles;
create trigger profiles_ban_phone_trg after update of status on public.profiles
  for each row execute function public.profiles_ban_phone();

-- ---------------------------------------------------------------------
-- 5. RLS  權限規則
-- ---------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.photos         enable row level security;
alter table public.photo_grants   enable row level security;
alter table public.photo_requests enable row level security;
alter table public.blocks         enable row level security;
alter table public.likes          enable row level security;
alter table public.matches        enable row level security;
alter table public.messages       enable row level security;
alter table public.reports        enable row level security;

-- profiles：自己、管理員；或（我是待審/已上架會員，且對方已上架、沒封鎖、沒隱身或與我有關）
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select to authenticated
  using (
    id = auth.uid() or public.is_admin()
    or (private.can_browse()
        and private.is_compatible(id)          -- 只看得到方向互相吻合的會員（保護同志會員隱私）
        and not private.is_blocked_with(id)
        and ((status = 'approved'
              and (not hidden
                   or exists (select 1 from public.likes l where l.from_id = profiles.id and l.to_id = auth.uid())
                   or private.has_open_match(profiles.id)))
             or (status = 'pending' and private.has_open_match(profiles.id))))   -- 已配對的人重新審核中仍看得到
  );
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- photos
drop policy if exists "photos_select" on public.photos;
create policy "photos_select" on public.photos for select to authenticated
  using (
    user_id = auth.uid() or public.is_admin()
    or (status = 'approved' and private.can_browse()
        and exists (select 1 from public.profiles p where p.id = photos.user_id)   -- 套用 profiles_select（上架、隱身、封鎖）
        and (not is_private or exists (select 1 from public.photo_grants g
                                       where g.owner_id = user_id and g.viewer_id = auth.uid())))
  );
drop policy if exists "photos_insert_own" on public.photos;
create policy "photos_insert_own" on public.photos for insert to authenticated
  with check (user_id = auth.uid() and path ~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$')
              and public.my_status() in ('pending','approved','rejected'));
drop policy if exists "photos_update" on public.photos;
create policy "photos_update" on public.photos for update to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());
drop policy if exists "photos_delete_own" on public.photos;
create policy "photos_delete_own" on public.photos for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- photo_grants / photo_requests
drop policy if exists "grants_rw" on public.photo_grants;
create policy "grants_rw" on public.photo_grants for all to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid())
  with check (owner_id = auth.uid() and exists (select 1 from public.photo_requests r where r.owner_id = auth.uid() and r.requester_id = viewer_id));   -- 只能授權給向你索取過的人
drop policy if exists "requests_select" on public.photo_requests;
create policy "requests_select" on public.photo_requests for select to authenticated
  using (requester_id = auth.uid() or owner_id = auth.uid());
drop policy if exists "requests_insert" on public.photo_requests;
create policy "requests_insert" on public.photo_requests for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending'
              and public.my_status() = 'approved' and private.is_compatible(owner_id)
              and exists (select 1 from public.profiles p where p.id = owner_id and p.status = 'approved')
              and not private.is_blocked_with(owner_id));
drop policy if exists "requests_update_owner" on public.photo_requests;
create policy "requests_update_owner" on public.photo_requests for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "requests_delete" on public.photo_requests;
create policy "requests_delete" on public.photo_requests for delete to authenticated
  using (owner_id = auth.uid() or (requester_id = auth.uid() and status = 'pending'));

-- blocks
drop policy if exists "blocks_rw" on public.blocks;
drop policy if exists "blocks_select" on public.blocks;
drop policy if exists "blocks_insert" on public.blocks;
drop policy if exists "blocks_delete" on public.blocks;
create policy "blocks_select" on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy "blocks_insert" on public.blocks for insert to authenticated with check (blocker_id = auth.uid());
create policy "blocks_delete" on public.blocks for delete to authenticated using (blocker_id = auth.uid());

-- likes
drop policy if exists "likes_select" on public.likes;
create policy "likes_select" on public.likes for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
drop policy if exists "likes_insert" on public.likes;
create policy "likes_insert" on public.likes for insert to authenticated
  with check (
    from_id = auth.uid()
    and public.my_status() = 'approved'
    and exists (select 1 from public.profiles p where p.id = to_id and p.status = 'approved')
    and not private.is_blocked_with(to_id)
    and private.is_compatible(to_id)
  );
drop policy if exists "likes_delete" on public.likes;
create policy "likes_delete" on public.likes for delete to authenticated
  using (from_id = auth.uid());

-- matches：會員只看得到未解除的配對；解除請呼叫 unmatch()
drop policy if exists "matches_select" on public.matches;
create policy "matches_select" on public.matches for select to authenticated
  using (((user_a = auth.uid() or user_b = auth.uid())
          and (closed_at is null or (closed_by is not null and closed_by <> auth.uid())))   -- 被對方結束的對話：唯讀保留
         or public.is_admin());
drop policy if exists "matches_delete" on public.matches;

-- messages
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select to authenticated
  using (exists (select 1 from public.matches m where m.id = match_id
                 and (m.closed_at is null or (m.closed_by is not null and m.closed_by <> auth.uid()))
                 and (m.user_a = auth.uid() or m.user_b = auth.uid())
                 and (m.reopened_at is null or messages.created_at >= m.reopened_at)) or public.is_admin());
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.my_status() in ('approved','pending')   -- 重新審核中仍可和已配對的人聊天（未曾上架者不會有配對）
    and exists (select 1 from public.matches m where m.id = match_id and m.closed_at is null
                and (m.user_a = auth.uid() or m.user_b = auth.uid())
                and not private.is_blocked_with(case when m.user_a = auth.uid() then m.user_b else m.user_a end))
    and private.can_send(match_id)
  );
drop policy if exists "messages_update_recall" on public.messages;
create policy "messages_update_recall" on public.messages for update to authenticated
  using (sender_id = auth.uid()) with check (sender_id = auth.uid());
drop policy if exists "messages_update_read" on public.messages;
create policy "messages_update_read" on public.messages for update to authenticated
  using (sender_id <> auth.uid() and exists (select 1 from public.matches m where m.id = match_id
                 and (m.user_a = auth.uid() or m.user_b = auth.uid())));

-- reports
create or replace function private.my_reports_today()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.reports where reporter_id = auth.uid() and created_at > now() - interval '1 day';
$$;
drop policy if exists "reports_insert" on public.reports;
create policy "reports_insert" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open' and reported_id <> auth.uid()
              and public.my_status() in ('pending','approved','rejected')
              and char_length(coalesce(detail,'')) <= 1000
              and private.my_reports_today() < 5);
drop policy if exists "reports_select" on public.reports;
create policy "reports_select" on public.reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());
drop policy if exists "reports_update_admin" on public.reports;
create policy "reports_update_admin" on public.reports for update to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- 6. Storage  photos bucket（私有，前端用限時簽章連結讀取）
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

create or replace function private.my_verify_file_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'verify' and name like auth.uid()::text || '/%';
$$;

-- 財力文件：私有空間。管理員審核；通過的文件只給本人與本人允許的會員看，退件的刪除
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verify', 'verify', false, 8388608, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 8388608, allowed_mime_types = array['image/jpeg'];
drop policy if exists "verify_storage_insert" on storage.objects;
create policy "verify_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'verify' and name ~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$')
              and exists (select 1 from public.profiles where id = auth.uid() and role in ('daddy','mommy') and status in ('pending','approved'))
              and private.my_verify_file_count() < 4
              and not exists (select 1 from public.wealth_verifications w where w.path = name));   -- 已送審的檔名不能刪掉再換檔
drop policy if exists "verify_storage_delete" on storage.objects;
create policy "verify_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'verify' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));

-- 檔名是否已登記為照片或頭像（登記後檔案不能刪除再用同檔名重傳）
create or replace function private.photo_path_in_use(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.photos where path = p)
      or exists (select 1 from public.profiles where avatar_path = p or approved_avatar_path = p);
$$;

create or replace function private.my_file_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'photos' and name like auth.uid()::text || '/%' and name !~ 't\.jpg$';   -- 縮圖不算
$$;

create or replace function private.my_thumb_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'photos' and name like auth.uid()::text || '/%' and name ~ 't\.jpg$';
$$;
grant execute on function private.my_thumb_count() to authenticated;

-- 縮圖用：檢查自己是否已上傳這張原圖（security definer，避免在 storage 規則裡查 storage 造成循環）
create or replace function private.my_photo_file_exists(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from storage.objects where bucket_id = 'photos' and name = p_name and name like auth.uid()::text || '/%');
$$;
grant execute on function private.my_photo_file_exists(text) to authenticated;

drop policy if exists "photos_storage_insert" on storage.objects;
create policy "photos_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos'
              and exists (select 1 from public.profiles where id = auth.uid() and status <> 'suspended')
              and (
                (name ~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$')
                 and private.my_file_count() < 30            -- 每人最多 30 個檔案（相簿 20 + 頭像與更換的餘裕）
                 and not private.photo_path_in_use(name))    -- 不可用同檔名覆蓋已登記的照片
                -- 縮圖（檔名加 t）：必須對應一張自己已上傳的原圖，不算在數量裡
                -- 只能在原圖登記之前上傳（之後就跟著原圖一起審核、一起鎖住），縮圖另有數量上限
                or (name ~ ('^' || auth.uid()::text || '/[0-9]+t\.jpg$')
                    and private.my_photo_file_exists(regexp_replace(name, 't\.jpg$', '.jpg'))
                    and not private.photo_path_in_use(regexp_replace(name, 't\.jpg$', '.jpg'))
                    and private.my_thumb_count() < 30)
              ));

drop policy if exists "photos_storage_delete" on storage.objects;
create policy "photos_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (public.is_admin()
         or ((storage.foldername(name))[1] = auth.uid()::text and not private.photo_path_in_use(name)
             and not private.photo_path_in_use(regexp_replace(name, 't\.jpg$', '.jpg')))));   -- 照片登記後（送審、已通過），它的縮圖也鎖住，不能刪掉換別張

drop policy if exists "photos_storage_select" on storage.objects;
create or replace function private.can_see_photo(p_name text)
returns boolean language sql stable set search_path = public as $$
  select ((storage.foldername(p_name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (select 1 from public.profiles p
                 where ((p.avatar_path = p_name and p.status = 'approved')
                        or (p.approved_avatar_path = p_name and p.status = 'pending' and private.has_open_match(p.id)))   -- 重新送審中：只給看上一次通過的頭像
                   and (storage.foldername(p_name))[1] = p.id::text
                   and private.can_browse() and private.is_compatible(p.id)
                   and not private.is_blocked_with(p.id))
      or exists (select 1 from public.photos ph
                 where ph.path = p_name and ph.status = 'approved'
                   and (storage.foldername(p_name))[1] = ph.user_id::text
                   and exists (select 1 from public.profiles op where op.id = ph.user_id and (op.status = 'approved' or (op.status = 'pending' and private.has_open_match(op.id))))
                   and private.can_browse() and private.is_compatible(ph.user_id)
                   and not private.is_blocked_with(ph.user_id)
                   and (not ph.is_private or exists (select 1 from public.photo_grants g
                                                     where g.owner_id = ph.user_id and g.viewer_id = auth.uid())))
  );
$$;
grant execute on function private.can_see_photo(text) to authenticated;
create policy "photos_storage_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'photos' and (
      private.can_see_photo(name)
      -- 縮圖：看得到原圖的人就看得到縮圖
      or (name ~ 't\.jpg$' and private.can_see_photo(regexp_replace(name, 't\.jpg$', '.jpg')))
    )
  );

-- 索取私密照（被婉拒後 3 天才能再問）
create or replace function public.request_private_photos(owner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.photo_requests;
begin
  if public.my_status() is distinct from 'approved' then raise exception '資料審核通過後才能索取'; end if;
  if owner = auth.uid() or private.is_blocked_with(owner) or not private.is_compatible(owner)
     or not exists (select 1 from public.profiles where id = owner and status = 'approved') then
    raise exception '無法向這位會員索取';
  end if;
  select * into r from public.photo_requests where requester_id = auth.uid() and owner_id = owner;
  if found then
    if r.status = 'pending' then raise exception '已送出索取，等待對方同意'; end if;
    if r.status = 'granted' and exists (select 1 from public.photo_grants where owner_id = owner and viewer_id = auth.uid()) then return; end if;
    if r.status = 'denied' and r.created_at > now() - interval '3 days' then raise exception '對方剛婉拒，3 天後才能再問一次'; end if;
    update public.photo_requests set status = 'pending', created_at = now() where requester_id = auth.uid() and owner_id = owner;
  else
    insert into public.photo_requests (requester_id, owner_id) values (auth.uid(), owner);
  end if;
end $$;

-- 名單顯示用：只回傳和我有關（封鎖、授權、索取）的人的暱稱
create or replace function public.related_names(ids uuid[])
returns table (id uuid, nickname text) language sql stable security definer set search_path = public as $$
  select p.id, p.nickname from public.profiles p
   where p.id = any(ids)
     and (exists (select 1 from public.blocks where blocker_id = auth.uid() and blocked_id = p.id)
       or exists (select 1 from public.photo_grants where owner_id = auth.uid() and viewer_id = p.id)
       or exists (select 1 from public.photo_requests where owner_id = auth.uid() and requester_id = p.id)
       or exists (select 1 from public.wealth_requests where owner_id = auth.uid() and requester_id = p.id)
       or exists (select 1 from public.matches m where m.user_a = least(auth.uid(), p.id) and m.user_b = greatest(auth.uid(), p.id)
                    and (m.closed_at is null or (m.closed_by is not null and m.closed_by <> auth.uid()))));
$$;

-- 欄位權限：其他會員只讀得到公開欄位；是否為管理員、退件原因、上線設定、同意紀錄等只有本人與管理員看得到
revoke select on public.profiles from anon, authenticated;
grant select (id, nickname, gender, looking_for, role, budget, wealth_verified_at, person_verified_at, body_type, cup, relation_types, meet_freq, expect_budget, birth_year, city, height_cm, occupation, bio, tags,
              avatar_path, status, hidden, last_active_at, created_at, founder_boost_until, free_until, travel_city, travel_from, travel_to, approved_avatar_path, approved_bio, approved_occupation, approved_tags) on public.profiles to authenticated;

-- 讀自己的完整資料
create or replace function public.get_me()
returns setof public.profiles language sql stable security definer set search_path = public as $$
  select * from public.profiles where id = auth.uid();
$$;

-- 管理員讀會員完整資料
create or replace function public.admin_profiles(p_status text default null, p_q text default null, p_limit int default 100)
returns setof public.profiles language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query
    select * from public.profiles p
     where (p_status is null or p.status = p_status)
       and (p_q is null or p_q = '' or p.nickname ilike '%' || replace(replace(p_q, '%', '\%'), '_', '\_') || '%')
     order by case when p_status = 'pending' then coalesce(p.submitted_at, p.updated_at) end asc nulls last, p.created_at desc
     limit least(coalesce(p_limit, 100), 500);
end $$;

-- 主動開啟新對話的紀錄（額度計算用；刪帳號時一併刪除）
create table if not exists public.conversation_starts (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists conversation_starts_idx on public.conversation_starts(user_id, created_at);
alter table public.conversation_starts enable row level security;
revoke all on public.conversation_starts from anon, authenticated;

-- 主動開新對話的額度：前 10 個隨時可用；用完後每天（台灣時間）只能再開 1 個
-- 網站設定（目前只有「免費開站期」開關）
create table if not exists public.app_config (key text primary key, value text not null);
alter table public.app_config enable row level security;
drop policy if exists "app_config_read" on public.app_config;
create policy "app_config_read" on public.app_config for select to anon, authenticated using (true);
insert into public.app_config (key, value) values ('free_launch', 'on') on conflict (key) do nothing;
grant select on public.app_config to anon, authenticated;
create or replace function private.free_launch()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select value = 'on' from public.app_config where key = 'free_launch'), false);
$$;

-- 主動開啟新對話的額度：
--   免費開站期（所有人都是微糖會員）：不限次數，只留每天 30 個的防濫發上限，回傳 999 代表不限
--   正式收費後：前 10 個，之後每天 1 個
create or replace function public.my_start_quota()
returns int language plpgsql stable security definer set search_path = public as $$
declare total int; today_n int; today timestamptz;
begin
  if auth.uid() is null then return 0; end if;
  today := (date_trunc('day', now() at time zone 'Asia/Taipei')) at time zone 'Asia/Taipei';
  select count(*), count(*) filter (where created_at >= today) into total, today_n
    from public.conversation_starts where user_id = auth.uid();
  if private.free_launch() then return case when today_n < 30 then 999 else 0 end; end if;
  if total < 10 then return 10 - total; end if;
  return greatest(0, 1 - today_n);
end $$;
revoke execute on function public.my_start_quota() from anon, public;
grant execute on function public.my_start_quota() to authenticated;

-- 傳第一則訊息（直接開啟對話）
create or replace function public.send_first_message(other uuid, body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m public.matches; mid uuid; existed boolean;
begin
  if me is null then raise exception '請先登入'; end if;
  if other = me then raise exception '不能傳訊息給自己'; end if;
  if body is null or char_length(trim(body)) = 0 or char_length(body) > 2000 then raise exception '訊息長度不正確'; end if;
  -- 同一位會員的開啟動作排隊處理，避免同時大量送出繞過額度
  perform pg_advisory_xact_lock(hashtext('start:' || me::text));
  perform pg_advisory_xact_lock(hashtext('pair:' || least(me, other)::text || greatest(me, other)::text));
  select * into m from public.matches where user_a = least(me, other) and user_b = greatest(me, other) for update;
  existed := found;
  if existed and m.closed_at is null then
    -- 已有對話：照一般規則傳（由訊息規則檢查）
    insert into public.messages (match_id, sender_id, body) values (m.id, me, body);
    return m.id;
  end if;
  if public.my_status() is distinct from 'approved' then raise exception '檔案審核通過後才能主動傳訊息'; end if;
  if private.is_blocked_with(other) or not private.is_compatible(other)
     or not exists (select 1 from public.profiles p where p.id = other and p.status = 'approved'
                    and (not p.hidden or exists (select 1 from public.likes l where l.from_id = other and l.to_id = me))) then
    raise exception '無法傳訊息給這位會員';
  end if;
  if exists (select 1 from public.profiles p where p.id = other and p.accept_from = 'liked')
     and not exists (select 1 from public.likes l where l.from_id = other and l.to_id = me) then
    raise exception '對方目前只接受自己心動過的人傳訊息';
  end if;
  if existed then
    if m.closed_by = other then raise exception '對方已結束和你的對話，無法再主動傳訊息'; end if;
    if m.closed_by = me and m.initiator = me and m.replied_at is null and m.closed_at > now() - interval '30 days' then
      raise exception '對方還沒回覆過你，30 天內不能重新開啟這段對話';
    end if;
  end if;
  if public.my_start_quota() <= 0 then
    raise exception '%', case when private.free_launch() then '今天主動開啟的新對話已達上限，明天再來吧' else '前 10 個新對話已經用完，之後每天可以再開啟 1 個，明天再來吧' end;
  end if;
  insert into public.conversation_starts (user_id) values (me);
  if existed then
    update public.matches set closed_at = null, closed_by = null, reopened_at = clock_timestamp(), initiator = me,
           replied_at = null, last_message = null, last_message_at = null
     where id = m.id returning id into mid;
  else
    insert into public.matches (user_a, user_b, initiator) values (least(me, other), greatest(me, other), me) returning id into mid;
  end if;
  insert into public.messages (match_id, sender_id, body) values (mid, me, body);
  return mid;
end $$;
revoke execute on function public.send_first_message(uuid, text) from anon, public;
grant execute on function public.send_first_message(uuid, text) to authenticated;

-- 會員自行刪除帳號：刪除 auth.users（連同手機、信箱），其餘資料經由外鍵一併刪除
-- 前端會先刪掉照片登記與 storage 檔案，再呼叫這個函式
-- 第一步：下架、解除照片登記（之後前端才能刪檔）
create or replace function public.begin_account_deletion()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '請先登入'; end if;
  if public.my_status() = 'suspended' then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  perform set_config('halfsugar.deleting', '1', true);
  update public.profiles set hidden = true, avatar_path = null where id = uid;
  delete from public.photos where user_id = uid;
  delete from public.wealth_verifications where user_id = uid;
  delete from public.person_verifications where user_id = uid;
  if to_regclass('public.voice_intros') is not null then execute 'delete from public.voice_intros where user_id = $1' using uid; end if;
  perform set_config('halfsugar.deleting', '0', true);
end $$;
revoke execute on function public.begin_account_deletion() from anon, public;
grant execute on function public.begin_account_deletion() to authenticated;

-- 第二步：確認檔案都刪了，再刪除帳號（含手機、信箱），其餘資料經由外鍵一併刪除
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '請先登入'; end if;
  if public.my_status() = 'suspended' then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  if exists (select 1 from storage.objects where bucket_id in ('photos','verify','person','chat','voice') and name like uid::text || '/%') then
    raise exception '照片檔案還沒刪完，請再按一次刪除';
  end if;
  delete from public.photos where user_id = uid;
  delete from auth.users where id = uid;
end $$;
revoke execute on function public.delete_my_account() from anon, public;
grant execute on function public.delete_my_account() to authenticated;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;
drop function if exists public.is_blocked_with(uuid);
drop function if exists public.is_compatible(uuid);
drop function if exists public.photo_path_in_use(text);

-- 檢舉證據：送出檢舉時，自動備份雙方之間的對話（只有管理員看得到），之後解除配對或刪帳號也不會消失
create table if not exists public.report_evidence (
  id         bigint generated always as identity primary key,
  report_id  uuid not null references public.reports(id) on delete cascade,
  sender_id  uuid,
  body       text not null,
  created_at timestamptz not null
);
create index if not exists report_evidence_idx on public.report_evidence(report_id, created_at);
alter table public.report_evidence enable row level security;
drop policy if exists "evidence_admin" on public.report_evidence;
create policy "evidence_admin" on public.report_evidence for select to authenticated using (public.is_admin());
alter table public.report_evidence add column if not exists image_path text;
alter table public.report_evidence add column if not exists recalled boolean not null default false;

create or replace function public.handle_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.reports set reported_nickname = (select nickname from public.profiles where id = new.reported_id) where id = new.id;
  -- 備份對話（含照片路徑與已收回訊息的原內容）
  insert into public.report_evidence (report_id, sender_id, body, image_path, recalled, created_at)
  select new.id, x.sender_id, x.body, x.image_path, x.recalled, x.created_at from (
    select ms.sender_id, coalesce(r.body, ms.body, '') as body, coalesce(r.image_path, ms.image_path) as image_path,
           ms.recalled_at is not null as recalled, ms.created_at
      from public.messages ms
      join public.matches m on m.id = ms.match_id
      left join public.message_recalls r on r.message_id = ms.id
     where m.user_a = least(new.reporter_id, new.reported_id) and m.user_b = greatest(new.reporter_id, new.reported_id)
     order by ms.created_at desc limit 500) x;
  return new;
end $$;
drop trigger if exists reports_evidence_trg on public.reports;
create trigger reports_evidence_trg after insert on public.reports
  for each row execute function public.handle_report();

-- 被退件後重新送審（內容不一定有改）
create or replace function public.resubmit_profile()
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.my_status() <> 'rejected' then return; end if;
  perform set_config('halfsugar.resubmit', '1', true);
  update public.profiles set updated_at = now() where id = auth.uid();
  perform set_config('halfsugar.resubmit', '0', true);
end $$;
revoke execute on function public.resubmit_profile() from anon, public;
grant execute on function public.resubmit_profile() to authenticated;

-- ---------------------------------------------------------------------
-- 財力認證：Sugar Daddy／Mommy 上傳一份財力文件（姓名等個資可遮住），管理員看過後給「財力認證」標章；通過的文件只給本人允許的會員看
-- ---------------------------------------------------------------------
create table if not exists public.wealth_verifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('deposit','income','tax','property','car','business','other')),
  path        text,                -- 審核後清空（檔案已刪除）
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_note text,
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists wealth_verifications_idx on public.wealth_verifications(status, created_at);
alter table public.wealth_verifications enable row level security;

create or replace function public.wealth_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  new.user_id := auth.uid(); new.status := 'pending'; new.review_note := null; new.reviewed_at := null; new.created_at := now();
  if new.path is null or new.path !~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$') then raise exception '請上傳文件照片'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and role in ('daddy','mommy') and status in ('pending','approved')) then
    raise exception '財力認證只開放給 Sugar Daddy／Mommy';
  end if;
  if exists (select 1 from public.wealth_verifications where user_id = auth.uid() and status = 'pending') then
    raise exception '你已經有一份文件在審核中';
  end if;
  if (select count(*) from public.wealth_verifications where user_id = auth.uid() and created_at > now() - interval '1 day') >= 3 then
    raise exception '今天送出太多次了，明天再試';
  end if;
  return new;
end $$;
drop trigger if exists wealth_guard_trg on public.wealth_verifications;
create trigger wealth_guard_trg before insert on public.wealth_verifications
  for each row execute function public.wealth_guard();

drop policy if exists "wealth_select" on public.wealth_verifications;
create policy "wealth_select" on public.wealth_verifications for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "wealth_insert" on public.wealth_verifications;
create policy "wealth_insert" on public.wealth_verifications for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
drop policy if exists "wealth_delete" on public.wealth_verifications;
create policy "wealth_delete" on public.wealth_verifications for delete to authenticated
  using ((user_id = auth.uid() and status = 'pending') or public.is_admin());

-- 甜心申請查看財力文件；Daddy／Mommy 按允許後才看得到
create table if not exists public.wealth_requests (
  requester_id uuid not null references public.profiles(id) on delete cascade,
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','granted','denied')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, owner_id)
);
alter table public.wealth_requests enable row level security;
drop policy if exists "wreq_select" on public.wealth_requests;
create policy "wreq_select" on public.wealth_requests for select to authenticated
  using (requester_id = auth.uid() or owner_id = auth.uid() or public.is_admin());
drop policy if exists "wreq_update_owner" on public.wealth_requests;
create policy "wreq_update_owner" on public.wealth_requests for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid() and status in ('granted','denied'));
drop policy if exists "wreq_delete" on public.wealth_requests;
create policy "wreq_delete" on public.wealth_requests for delete to authenticated
  using (owner_id = auth.uid() or (requester_id = auth.uid() and status = 'pending'));

-- 某人目前可分享的財力文件路徑（已通過且未刪除的最新一份）
create or replace function private.wealth_doc_path(owner uuid)
returns text language sql stable security definer set search_path = public as $$
  select w.path from public.wealth_verifications w join public.profiles p on p.id = w.user_id
   where w.user_id = owner and w.status = 'approved' and w.path is not null
     and p.wealth_verified_at is not null and p.role in ('daddy','mommy')   -- 認證被取消或改成甜心：不再分享
   order by w.reviewed_at desc nulls last limit 1;
$$;

-- 我能不能看這個檔案（storage 規則用）
create or replace function private.can_view_wealth_doc(fname text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.wealth_verifications w
                   join public.wealth_requests r on r.owner_id = w.user_id and r.requester_id = auth.uid() and r.status = 'granted'
                  where w.path = fname and w.status = 'approved'
                    and not private.is_blocked_with(w.user_id) and private.can_browse()
                    and exists (select 1 from public.profiles p where p.id = w.user_id and p.status = 'approved' and p.wealth_verified_at is not null and p.role in ('daddy','mommy')));
$$;

-- 查看狀態：回傳 none（沒有可看的文件）、can_request、pending、denied、granted（附路徑）
create or replace function public.wealth_doc_status(owner uuid)
returns table (state text, path text) language plpgsql stable security definer set search_path = public as $$
declare r public.wealth_requests; doc text;
begin
  if owner <> auth.uid() and (not private.can_browse() or not private.is_compatible(owner)) then return query select 'none'::text, null::text; return; end if;
  doc := private.wealth_doc_path(owner);
  if doc is null or private.is_blocked_with(owner) then return query select 'none'::text, null::text; return; end if;
  if owner = auth.uid() then return query select 'own'::text, doc; return; end if;
  select * into r from public.wealth_requests where requester_id = auth.uid() and owner_id = owner;
  if not found then return query select 'can_request'::text, null::text;
  elsif r.status = 'granted' then return query select 'granted'::text, doc;
  else return query select r.status, null::text; end if;
end $$;
revoke execute on function public.wealth_doc_status(uuid) from anon, public;
grant execute on function public.wealth_doc_status(uuid) to authenticated;

create or replace function public.request_wealth_view(owner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.wealth_requests;
begin
  if public.my_status() is distinct from 'approved' then raise exception '檔案審核通過後才能申請查看'; end if;
  if owner = auth.uid() or private.is_blocked_with(owner) or not private.is_compatible(owner)
     or not exists (select 1 from public.profiles where id = owner and status = 'approved')
     or private.wealth_doc_path(owner) is null then
    raise exception '這位會員目前沒有可查看的財力證明';
  end if;
  select * into r from public.wealth_requests where requester_id = auth.uid() and owner_id = owner;
  if found then
    if r.status = 'pending' then raise exception '已送出申請，等待對方同意'; end if;
    if r.status = 'granted' then return; end if;
    if r.created_at > now() - interval '3 days' then raise exception '對方剛婉拒，3 天後才能再申請'; end if;
    update public.wealth_requests set status = 'pending', created_at = now() where requester_id = auth.uid() and owner_id = owner;
  else
    insert into public.wealth_requests (requester_id, owner_id) values (auth.uid(), owner);
  end if;
end $$;
revoke execute on function public.request_wealth_view(uuid) from anon, public;
grant execute on function public.request_wealth_view(uuid) to authenticated;

-- 本人刪除已保存的財力文件（標章保留；前端會先刪檔案）
create or replace function public.delete_my_wealth_doc()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.wealth_verifications set path = null where user_id = auth.uid();
  delete from public.wealth_requests where owner_id = auth.uid();
end $$;
revoke execute on function public.delete_my_wealth_doc() from anon, public;
grant execute on function public.delete_my_wealth_doc() to authenticated;

-- 管理員審核財力文件（退件時前端會先刪掉檔案）
create or replace function public.admin_review_wealth(vid uuid, approve boolean, note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.wealth_verifications;
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  select * into v from public.wealth_verifications where id = vid for update;
  if not found then raise exception '找不到這筆申請'; end if;
  update public.wealth_verifications
     set status = case when approve then 'approved' else 'rejected' end,
         review_note = case when approve then null else coalesce(nullif(note,''), '文件看不出財力，請換一份更清楚的文件') end,
         reviewed_at = now(), path = case when approve then path else null end   -- 通過的文件保留（只給本人允許的人看），退件的刪除
   where id = vid;
  if approve then update public.profiles set wealth_verified_at = now() where id = v.user_id; end if;
end $$;
revoke execute on function public.admin_review_wealth(uuid, boolean, text) from anon, public;
grant execute on function public.admin_review_wealth(uuid, boolean, text) to authenticated;

-- 管理員取消某人的財力認證
create or replace function public.admin_revoke_wealth(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  update public.profiles set wealth_verified_at = null where id = target;
  update public.wealth_verifications set path = null where user_id = target and status = 'approved';   -- 文件不再分享
  delete from public.wealth_requests where owner_id = target;
end $$;
revoke execute on function public.admin_revoke_wealth(uuid) from anon, public;
grant execute on function public.admin_revoke_wealth(uuid) to authenticated;

-- 管理員：會員的對話行為統計（找出大量群發的人）
create or replace function public.admin_member_stats(ids uuid[])
returns table (id uuid, starts_7d int, unreplied_pct int, closed_by_others int, blocked_by int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query
  select u.id,
    (select count(*)::int from public.conversation_starts c where c.user_id = u.id and c.created_at > now() - interval '7 days'),
    (select case when count(*) = 0 then 0 else (100 * count(*) filter (where m.replied_at is null) / count(*))::int end
       from public.matches m where m.initiator = u.id),
    (select count(*)::int from public.matches m where (m.user_a = u.id or m.user_b = u.id) and m.closed_by is not null and m.closed_by <> u.id),
    (select count(*)::int from public.blocks b where b.blocked_id = u.id)
  from unnest(ids) as u(id);
end $$;
revoke execute on function public.admin_member_stats(uuid[]) from anon, public;
grant execute on function public.admin_member_stats(uuid[]) to authenticated;

-- 管理員刪除帳號（用於已停權帳號）：手機若在黑名單中仍保留指紋，之後不能再註冊
create or replace function public.admin_delete_account(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  if target = auth.uid() then raise exception '不能刪除自己的管理員帳號'; end if;
  if exists (select 1 from storage.objects where bucket_id in ('photos','verify','person','chat','voice') and name like target::text || '/%') then
    raise exception '這位會員的照片或認證檔案還沒刪完';
  end if;
  update public.reports set status = 'resolved' where reported_id = target and status = 'open';
  delete from public.photos where user_id = target;
  delete from auth.users where id = target;
end $$;
revoke execute on function public.admin_delete_account(uuid) from anon, public;
grant execute on function public.admin_delete_account(uuid) to authenticated;

-- 舊函式（可查詢任意兩人之間的封鎖）移除
drop function if exists public.is_blocked_between(uuid, uuid);

-- ---------------------------------------------------------------------
-- 6c. 客服留言（還沒有客服信箱前，會員在站內留言，管理員在後台看）
-- ---------------------------------------------------------------------
create table if not exists public.support_tickets (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references auth.users(id) on delete set null,
  email      text,
  body       text not null check (char_length(body) between 5 and 1000),
  status     text not null default 'open' check (status in ('open','done')),
  created_at timestamptz not null default now()
);
alter table public.support_tickets enable row level security;

create or replace function private.my_ticket_count_today()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.support_tickets where user_id = auth.uid() and created_at > now() - interval '1 day';
$$;
grant execute on function private.my_ticket_count_today() to authenticated;

create or replace function public.support_tickets_fill()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  new.email := (select email from auth.users where id = auth.uid());
  new.status := 'open';
  new.created_at := now();
  return new;
end $$;
drop trigger if exists support_tickets_fill_trg on public.support_tickets;
create trigger support_tickets_fill_trg before insert on public.support_tickets
  for each row execute function public.support_tickets_fill();

drop policy if exists "support_insert" on public.support_tickets;
create policy "support_insert" on public.support_tickets for insert to authenticated
  with check (user_id = auth.uid() and private.my_ticket_count_today() < 5);
drop policy if exists "support_select" on public.support_tickets;
create policy "support_select" on public.support_tickets for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "support_update" on public.support_tickets;
create policy "support_update" on public.support_tickets for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- 7. Realtime
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 8. 管理員：註冊完成後，把你的帳號設成管理員（把 email 換掉）
-- ---------------------------------------------------------------------
-- update public.profiles set is_admin = true, status = 'approved'
--  where id = (select id from auth.users where email = 'you@example.com');


-- ---------------------------------------------------------------------
-- 真人認證：系統隨機指定動作，會員交一張自拍＋一段 10 秒內短影片，管理員比對頭像後給「真人認證」標章；檔案審核後立即刪除
-- ---------------------------------------------------------------------
create table if not exists public.person_verifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  photo_task  text not null,
  video_task  text not null,
  code        text not null,
  photo_path  text,
  video_path  text,
  status      text not null default 'awaiting' check (status in ('awaiting','pending','approved','rejected')),
  review_note text,
  created_at  timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz
);
create index if not exists person_verifications_idx on public.person_verifications(status, submitted_at);
alter table public.person_verifications enable row level security;
drop policy if exists "pv_select" on public.person_verifications;
create policy "pv_select" on public.person_verifications for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- 取得指定動作（由伺服器隨機產生，會員無法自己選）
create or replace function public.start_person_verification()
returns public.person_verifications language plpgsql security definer set search_path = public as $$
declare r public.person_verifications;
  photos text[] := array['右手比 3，摸左耳','左手比讚，放在下巴旁','右手比 OK，放在右臉旁','雙手在胸前比愛心','左手比 YA，放在額頭旁','右手摸頭頂，閉上左眼'];
  videos text[] := array['先看鏡頭，慢慢把頭轉向左邊再轉回來','對鏡頭眨兩次眼，再揮揮手','先比 1，再比 5，最後比讚','把手機拿近再拿遠，最後微笑','先抬頭看上面，再低頭看下面，最後看鏡頭'];
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.my_status() not in ('pending','approved') then raise exception '建立檔案後才能申請真人認證'; end if;
  if exists (select 1 from public.person_verifications where user_id = auth.uid() and status = 'pending') then
    raise exception '你已經有一份在審核中';
  end if;
  if (select count(*) from public.person_verifications where user_id = auth.uid() and created_at > now() - interval '1 day') >= 5 then
    raise exception '今天申請太多次了，明天再試';
  end if;
  delete from public.person_verifications where user_id = auth.uid() and status = 'awaiting';
  insert into public.person_verifications (user_id, photo_task, video_task, code)
  values (auth.uid(), photos[1 + floor(random()*array_length(photos,1))::int], videos[1 + floor(random()*array_length(videos,1))::int],
          lpad((floor(random()*9000)+1000)::int::text, 4, '0'))
  returning * into r;
  return r;
end $$;
revoke execute on function public.start_person_verification() from anon, public;
grant execute on function public.start_person_verification() to authenticated;

-- 交件（檔案已上傳到 person 空間）
create or replace function public.submit_person_verification(vid uuid, photo text, video text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if photo !~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$') or video !~ ('^' || auth.uid()::text || '/[0-9]+\.(mp4|mov|webm)$') then
    raise exception '檔案格式不正確';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'person' and name = photo)
     or not exists (select 1 from storage.objects where bucket_id = 'person' and name = video) then
    raise exception '檔案還沒上傳完成';
  end if;
  update public.person_verifications set photo_path = photo, video_path = video, status = 'pending', submitted_at = now()
   where id = vid and user_id = auth.uid() and status = 'awaiting' and created_at > now() - interval '2 hours';
  if not found then raise exception '這次的指定動作已過期，請重新開始'; end if;
end $$;
revoke execute on function public.submit_person_verification(uuid, text, text) from anon, public;
grant execute on function public.submit_person_verification(uuid, text, text) to authenticated;

-- 管理員審核（前端會先刪掉檔案）
create or replace function public.admin_review_person(vid uuid, approve boolean, note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.person_verifications;
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  select * into v from public.person_verifications where id = vid for update;
  if not found then raise exception '找不到這筆申請'; end if;
  update public.person_verifications
     set status = case when approve then 'approved' else 'rejected' end,
         review_note = case when approve then null else coalesce(nullif(note,''), '動作或長相和頭像對不起來，請重新拍攝') end,
         reviewed_at = now(), photo_path = null, video_path = null
   where id = vid;
  if approve then update public.profiles set person_verified_at = now() where id = v.user_id; end if;
end $$;
revoke execute on function public.admin_review_person(uuid, boolean, text) from anon, public;
grant execute on function public.admin_review_person(uuid, boolean, text) to authenticated;

create or replace function public.admin_revoke_person(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  update public.profiles set person_verified_at = null where id = target;
end $$;
revoke execute on function public.admin_revoke_person(uuid) from anon, public;
grant execute on function public.admin_revoke_person(uuid) to authenticated;

-- 真人認證檔案空間：私有，只有本人與管理員看得到，審核後刪除
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('person', 'person', false, 26214400, array['image/jpeg','video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set public = false, file_size_limit = 26214400,
  allowed_mime_types = array['image/jpeg','video/mp4','video/quicktime','video/webm'];
create or replace function private.my_person_file_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'person' and name like auth.uid()::text || '/%';
$$;
drop policy if exists "person_storage_insert" on storage.objects;
create policy "person_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'person' and name ~ ('^' || auth.uid()::text || '/[0-9]+\.(jpg|mp4|mov|webm)$')
              and public.my_status() in ('pending','approved') and private.my_person_file_count() < 6);
drop policy if exists "person_storage_select" on storage.objects;
create policy "person_storage_select" on storage.objects for select to authenticated
  using (bucket_id = 'person' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));
drop policy if exists "person_storage_delete" on storage.objects;
create policy "person_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'person' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));

-- ---------------------------------------------------------------------
-- 財力文件讀取規則（放最後：用到上面才定義的函式）
-- ---------------------------------------------------------------------
drop policy if exists "verify_storage_select" on storage.objects;
create policy "verify_storage_select" on storage.objects for select to authenticated
  using (bucket_id = 'verify' and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text
                                   or private.can_view_wealth_doc(name)));   -- 本人允許的甜心
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- v0.26.0：收回匿名訪客對公開函式的執行權（函式內本來就有檢查，這是多一層保險）
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('is_admin','my_status','unmatch','request_private_photos','related_names','get_me','admin_profiles')
  loop execute format('revoke execute on function %s from anon, public', f.sig); execute format('grant execute on function %s to authenticated', f.sig); end loop;
end $$;

-- ---------------------------------------------------------------------
-- v0.27 聊天照片：私有空間，路徑 <寄件人>/<對話id>-<時間>.jpg
--   上傳：自己的資料夾、自己是這段對話的成員、對話還開著
--   讀取：自己上傳的，或對話中還沒被收回的照片（對話成員才看得到）
--   刪除：只有寄件人（收回時）和管理員
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat', 'chat', false, 5242880, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg'];

create or replace function private.chat_can_upload(fname text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare mid uuid; uid uuid := auth.uid();
begin
  if uid is null or fname !~ ('^' || uid::text || '/[0-9a-f-]{36}-[0-9]+\.jpg$') then return false; end if;
  mid := substring(fname from '^[^/]+/([0-9a-f-]{36})-')::uuid;
  return exists (select 1 from public.matches m where m.id = mid and m.closed_at is null and (m.user_a = uid or m.user_b = uid)
                   and not private.is_blocked_with(case when m.user_a = uid then m.user_b else m.user_a end))
     and public.my_status() in ('approved','pending')
     and (select count(*) from storage.objects o where o.bucket_id = 'chat' and o.name like uid::text || '/%' and o.created_at > now() - interval '1 day') < 60;
exception when others then return false;
end $$;

create or replace function private.is_evidence_photo(fname text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.report_evidence where image_path = fname);
$$;
grant execute on function private.is_evidence_photo(text) to authenticated;

create or replace function private.chat_can_read(fname text)
returns boolean language sql stable security definer set search_path = public as $$
  select fname like auth.uid()::text || '/%'
      or exists (select 1 from public.messages ms join public.matches m on m.id = ms.match_id
                  where ms.image_path = fname and ms.recalled_at is null
                    and (m.user_a = auth.uid() or m.user_b = auth.uid())
                    and (m.closed_at is null or (m.closed_by is not null and m.closed_by <> auth.uid()))
                    and (m.reopened_at is null or ms.created_at >= m.reopened_at))
      or public.is_admin();
$$;

drop policy if exists "chat_storage_insert" on storage.objects;
create policy "chat_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat' and private.chat_can_upload(name));
drop policy if exists "chat_storage_select" on storage.objects;
create policy "chat_storage_select" on storage.objects for select to authenticated
  using (bucket_id = 'chat' and private.chat_can_read(name));
drop policy if exists "chat_storage_delete" on storage.objects;
create policy "chat_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'chat' and (public.is_admin()
         or ((storage.foldername(name))[1] = auth.uid()::text and not private.is_evidence_photo(name))));   -- 檢舉證據的照片：會員（含刪帳號時）刪不掉，只有管理員能處理

-- ---------------------------------------------------------------------
-- v0.28 管理員：查看所有對話（含已收回的原內容）與會員聯絡資料
-- ---------------------------------------------------------------------
create or replace function public.admin_conversations(p_q text default null, p_limit int default 200)
returns table (id uuid, user_a uuid, user_b uuid, name_a text, name_b text, created_at timestamptz,
               last_message_at timestamptz, last_message text, closed_at timestamptz, msg_count bigint, img_count bigint, recall_count bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query
    select m.id, m.user_a, m.user_b, pa.nickname, pb.nickname, m.created_at, m.last_message_at, m.last_message, m.closed_at,
           (select count(*) from public.messages x where x.match_id = m.id),
           (select count(*) from public.messages x where x.match_id = m.id and x.image_path is not null)
             + (select count(*) from public.message_recalls r where r.match_id = m.id and r.image_path is not null),
           (select count(*) from public.message_recalls r where r.match_id = m.id)
      from public.matches m
      left join public.profiles pa on pa.id = m.user_a
      left join public.profiles pb on pb.id = m.user_b
     where p_q is null or p_q = ''
        or pa.nickname ilike '%' || replace(replace(p_q, '%', '\%'), '_', '\_') || '%'
        or pb.nickname ilike '%' || replace(replace(p_q, '%', '\%'), '_', '\_') || '%'
     order by m.last_message_at desc nulls last, m.created_at desc
     limit least(coalesce(p_limit, 200), 1000);
end $$;
revoke execute on function public.admin_conversations(text, int) from anon, public;
grant execute on function public.admin_conversations(text, int) to authenticated;

create or replace function public.admin_messages(mid uuid)
returns table (id bigint, sender_id uuid, body text, image_path text, created_at timestamptz, read_at timestamptz, recalled_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query
    select ms.id, ms.sender_id,
           coalesce(r.body, ms.body), coalesce(r.image_path, ms.image_path),
           ms.created_at, ms.read_at, ms.recalled_at
      from public.messages ms left join public.message_recalls r on r.message_id = ms.id
     where ms.match_id = mid
     order by ms.created_at;
end $$;
revoke execute on function public.admin_messages(uuid) from anon, public;
grant execute on function public.admin_messages(uuid) to authenticated;

create or replace function public.admin_contacts(ids uuid[])
returns table (id uuid, email text, phone text, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select u.id, u.email::text, u.phone::text, u.last_sign_in_at from auth.users u where u.id = any(ids);
end $$;
revoke execute on function public.admin_contacts(uuid[]) from anon, public;
grant execute on function public.admin_contacts(uuid[]) to authenticated;

-- =====================================================================
-- v0.30  約會邀請卡、見面安全報備、見面後私下評價、回覆率、語音自我介紹
-- =====================================================================

-- 約會邀請 -------------------------------------------------------------
create table if not exists public.date_invites (
  id           uuid primary key default gen_random_uuid(),
  match_id     uuid not null references public.matches(id) on delete cascade,
  from_id      uuid not null references public.profiles(id) on delete cascade,
  to_id        uuid not null references public.profiles(id) on delete cascade,
  date_at      timestamptz not null,
  kind         text not null check (kind in ('coffee','dinner','drink','tea','activity','other')),
  area         text check (char_length(area) <= 40),
  status       text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz
);
create index if not exists date_invites_match_idx on public.date_invites(match_id, created_at);
alter table public.date_invites enable row level security;
drop policy if exists "date_invites_select" on public.date_invites;
create policy "date_invites_select" on public.date_invites for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid() or public.is_admin());

create or replace function private.invite_msg(mid uuid, iid uuid, txt text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not private.partner_active(mid) then return; end if;   -- 對方已停權或退件：狀態照常更新，只是不發訊息
  perform set_config('halfsugar.invite', '1', true);
  insert into public.messages (match_id, sender_id, body, invite_id) values (mid, auth.uid(), txt, iid);
  perform set_config('halfsugar.invite', '0', true);
end $$;

create or replace function public.create_date_invite(mid uuid, p_date timestamptz, p_kind text, p_area text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m public.matches; other uuid; iid uuid;
begin
  if uid is null then raise exception '請先登入'; end if;
  if public.my_status() not in ('approved','pending') then raise exception '目前無法送出邀請'; end if;
  select * into m from public.matches where id = mid and (user_a = uid or user_b = uid) for update;
  if not found or m.closed_at is not null then raise exception '這段對話已經結束'; end if;
  if m.replied_at is null and m.initiator = uid then raise exception '對方回覆之後才能送出約會邀請'; end if;
  other := case when m.user_a = uid then m.user_b else m.user_a end;
  if private.is_blocked_with(other) or not private.partner_active(mid) then raise exception '對方目前無法接收邀請'; end if;
  if p_date < now() + interval '30 minutes' or p_date > now() + interval '60 days' then raise exception '請選擇 30 分鐘後到 60 天內的時間'; end if;
  if exists (select 1 from public.date_invites where match_id = mid and from_id = uid and status = 'pending') then
    raise exception '你已經送出一張邀請了，等對方回覆，或先取消再重送';
  end if;
  insert into public.date_invites (match_id, from_id, to_id, date_at, kind, area)
  values (mid, uid, other, p_date, p_kind, nullif(btrim(coalesce(p_area,'')), '')) returning id into iid;
  perform private.invite_msg(mid, iid, '送出了約會邀請');
  return iid;
end $$;
revoke execute on function public.create_date_invite(uuid, timestamptz, text, text) from anon, public;
grant execute on function public.create_date_invite(uuid, timestamptz, text, text) to authenticated;

create or replace function public.respond_date_invite(iid uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v public.date_invites;
begin
  select * into v from public.date_invites where id = iid and to_id = auth.uid() for update;
  if not found or v.status <> 'pending' then raise exception '這張邀請已經處理過了'; end if;
  if v.date_at <= now() then raise exception '這張邀請的時間已經過了'; end if;
  if exists (select 1 from public.matches where id = v.match_id and closed_at is not null) then raise exception '這段對話已經結束'; end if;
  update public.date_invites set status = case when accept then 'accepted' else 'declined' end, responded_at = now() where id = iid;
  perform private.invite_msg(v.match_id, iid, case when accept then '接受了約會邀請' else '婉拒了約會邀請' end);
end $$;
revoke execute on function public.respond_date_invite(uuid, boolean) from anon, public;
grant execute on function public.respond_date_invite(uuid, boolean) to authenticated;

create or replace function public.cancel_date_invite(iid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v public.date_invites;
begin
  select * into v from public.date_invites where id = iid and (from_id = auth.uid() or to_id = auth.uid()) for update;
  if not found or v.status not in ('pending','accepted') then raise exception '這張邀請已經不能取消'; end if;
  if v.status = 'pending' and v.from_id <> auth.uid() then raise exception '請改用「婉拒」'; end if;
  if v.status = 'accepted' and v.date_at <= now() then raise exception '約會時間已經到了，不能再取消'; end if;
  update public.date_invites set status = 'cancelled', responded_at = now() where id = iid;
  if not exists (select 1 from public.matches where id = v.match_id and closed_at is not null) then
    perform private.invite_msg(v.match_id, iid, '取消了約會');
  end if;
end $$;
revoke execute on function public.cancel_date_invite(uuid) from anon, public;
grant execute on function public.cancel_date_invite(uuid) to authenticated;

-- 見面安全報備：產生一個連結給朋友看；結束時按「我平安」 ----------------
create table if not exists public.safety_checks (
  id            uuid primary key default gen_random_uuid(),
  invite_id     uuid not null references public.date_invites(id) on delete cascade,
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  token         text not null unique default (replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','')),
  ends_at       timestamptz not null,
  checked_in_at timestamptz,
  created_at    timestamptz not null default now(),
  unique (invite_id, owner_id)
);
alter table public.safety_checks enable row level security;
drop policy if exists "safety_select" on public.safety_checks;
create policy "safety_select" on public.safety_checks for select to authenticated using (owner_id = auth.uid() or public.is_admin());

create or replace function public.create_safety_check(iid uuid, p_hours int default 3)
returns text language plpgsql security definer set search_path = public as $$
declare v public.date_invites; t text;
begin
  select * into v from public.date_invites where id = iid and (from_id = auth.uid() or to_id = auth.uid());
  if not found or v.status <> 'accepted' then raise exception '約會被接受後才能建立報備'; end if;
  insert into public.safety_checks (invite_id, owner_id, ends_at)
  values (iid, auth.uid(), v.date_at + make_interval(hours => greatest(1, least(coalesce(p_hours,3), 12))))
  on conflict (invite_id, owner_id) do update set ends_at = excluded.ends_at, checked_in_at = null
  returning token into t;
  return t;
end $$;
revoke execute on function public.create_safety_check(uuid, int) from anon, public;
grant execute on function public.create_safety_check(uuid, int) to authenticated;

create or replace function public.safety_checkin(iid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.safety_checks set checked_in_at = now() where invite_id = iid and owner_id = auth.uid();
  if not found then raise exception '找不到這次的報備'; end if;
end $$;
revoke execute on function public.safety_checkin(uuid) from anon, public;
grant execute on function public.safety_checkin(uuid) to authenticated;

-- 朋友打開報備連結看到的內容（不用登入；只有拿到連結的人看得到）
create or replace function public.safety_view(p_token text)
returns table (owner_name text, partner_name text, date_at timestamptz, kind text, area text, ends_at timestamptz, checked_in_at timestamptz, invite_status text)
language sql stable security definer set search_path = public as $$
  select po.nickname, pp.nickname, v.date_at, v.kind, v.area, sc.ends_at, sc.checked_in_at, v.status
    from public.safety_checks sc
    join public.date_invites v on v.id = sc.invite_id
    left join public.profiles po on po.id = sc.owner_id
    left join public.profiles pp on pp.id = case when v.from_id = sc.owner_id then v.to_id else v.from_id end
   where length(p_token) = 64 and sc.token = p_token
     and sc.ends_at > now() - interval '3 days';   -- 約會結束 3 天後連結失效
$$;
revoke execute on function public.safety_view(text) from public;
grant execute on function public.safety_view(text) to anon, authenticated;

-- 見面後私下評價（只有管理員看得到） -----------------------------------
create table if not exists public.meet_reviews (
  id          uuid primary key default gen_random_uuid(),
  invite_id   uuid not null references public.date_invites(id) on delete cascade,
  reviewer_id uuid references public.profiles(id) on delete set null,
  reviewee_id uuid not null references public.profiles(id) on delete cascade,
  rating      smallint not null check (rating between 1 and 3),   -- 3 很愉快 2 普通 1 不舒服
  tags        text[] not null default '{}',
  note        text check (char_length(note) <= 500),
  created_at  timestamptz not null default now(),
  unique (invite_id, reviewer_id)
);
alter table public.meet_reviews enable row level security;
drop policy if exists "meet_reviews_admin" on public.meet_reviews;
create policy "meet_reviews_admin" on public.meet_reviews for select to authenticated using (public.is_admin());

-- v0.37：帳號刪除後評價保留（記下當時暱稱、見面日期、手機指紋），刪帳號重來也洗不掉負評
alter table public.meet_reviews add column if not exists date_at timestamptz;
alter table public.meet_reviews add column if not exists reviewee_name text;
alter table public.meet_reviews add column if not exists reviewee_phone_hash text;
alter table public.meet_reviews alter column invite_id drop not null;
alter table public.meet_reviews alter column reviewee_id drop not null;
alter table public.meet_reviews drop constraint if exists meet_reviews_invite_id_fkey;
alter table public.meet_reviews add constraint meet_reviews_invite_id_fkey foreign key (invite_id) references public.date_invites(id) on delete set null;
alter table public.meet_reviews drop constraint if exists meet_reviews_reviewee_id_fkey;
alter table public.meet_reviews add constraint meet_reviews_reviewee_id_fkey foreign key (reviewee_id) references public.profiles(id) on delete set null;
create index if not exists meet_reviews_phone_idx on public.meet_reviews(reviewee_phone_hash) where reviewee_phone_hash is not null;
update public.meet_reviews r set date_at = v.date_at from public.date_invites v where v.id = r.invite_id and r.date_at is null;
update public.meet_reviews r set reviewee_name = p.nickname from public.profiles p where p.id = r.reviewee_id and r.reviewee_name is null;
update public.meet_reviews r set reviewee_phone_hash = private.phone_hash(u.phone) from auth.users u
 where u.id = r.reviewee_id and r.reviewee_phone_hash is null and nullif(u.phone,'') is not null;

create or replace function public.pending_reviews(mid uuid)
returns table (id uuid, date_at timestamptz) language sql stable security definer set search_path = public as $$
  select v.id, v.date_at from public.date_invites v
   where v.match_id = mid and v.status = 'accepted' and (v.from_id = auth.uid() or v.to_id = auth.uid())
     and v.date_at < now() - interval '3 hours' and v.date_at > now() - interval '30 days'
     and not exists (select 1 from public.meet_reviews r where r.invite_id = v.id and r.reviewer_id = auth.uid())
   order by v.date_at desc limit 1;
$$;
revoke execute on function public.pending_reviews(uuid) from anon, public;
grant execute on function public.pending_reviews(uuid) to authenticated;

create or replace function public.submit_meet_review(iid uuid, p_rating int, p_tags text[] default '{}', p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.date_invites;
begin
  select * into v from public.date_invites where id = iid and (from_id = auth.uid() or to_id = auth.uid());
  if not found or v.status <> 'accepted' or v.date_at > now() then raise exception '見面之後才能評價'; end if;
  if v.date_at < now() - interval '30 days' then raise exception '已超過可以評價的時間'; end if;
  if p_rating is null or p_rating not between 1 and 3 then raise exception '請選擇評價'; end if;
  insert into public.meet_reviews (invite_id, reviewer_id, reviewee_id, rating, tags, note, date_at, reviewee_name, reviewee_phone_hash)
  select iid, auth.uid(), x.rid, p_rating, coalesce((select array_agg(left(t, 20)) from unnest(p_tags[1:8]) t), '{}'), nullif(btrim(coalesce(p_note,'')), ''),
         v.date_at, (select nickname from public.profiles where id = x.rid),
         (select private.phone_hash(u.phone) from auth.users u where u.id = x.rid and nullif(u.phone,'') is not null)
    from (select case when v.from_id = auth.uid() then v.to_id else v.from_id end as rid) x;
exception when unique_violation then raise exception '你已經評價過這次見面了';
end $$;
revoke execute on function public.submit_meet_review(uuid, int, text[], text) from anon, public;
grant execute on function public.submit_meet_review(uuid, int, text[], text) to authenticated;

create or replace function public.admin_review_stats(ids uuid[])
returns table (id uuid, n bigint, good bigint, bad bigint, tags text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select r.reviewee_id, count(*), count(*) filter (where r.rating = 3), count(*) filter (where r.rating = 1),
                      array(select distinct t from public.meet_reviews r2, unnest(r2.tags) t where r2.reviewee_id = r.reviewee_id)
                 from public.meet_reviews r where r.reviewee_id = any(ids) group by r.reviewee_id;
end $$;
revoke execute on function public.admin_review_stats(uuid[]) from anon, public;
grant execute on function public.admin_review_stats(uuid[]) to authenticated;

create or replace function public.admin_reviews(target uuid)
returns table (created_at timestamptz, reviewer text, rating smallint, tags text[], note text, date_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select r.created_at, coalesce(p.nickname, '（已刪除）'), r.rating, r.tags, r.note, coalesce(v.date_at, r.date_at)
                 from public.meet_reviews r left join public.profiles p on p.id = r.reviewer_id
                 left join public.date_invites v on v.id = r.invite_id
                where r.reviewee_id = target order by r.created_at desc;
end $$;
revoke execute on function public.admin_reviews(uuid) from anon, public;
grant execute on function public.admin_reviews(uuid) to authenticated;

-- 回覆率：別人主動開啟的對話中，有回覆的比例與回覆時間的中位數（近 90 天） ------
create or replace function public.reply_stats(ids uuid[])
returns table (id uuid, n bigint, replied bigint, median_min int)
language sql stable security definer set search_path = public as $$
  select p.id, count(m.id), count(m.replied_at),
         (percentile_cont(0.5) within group (order by extract(epoch from (m.replied_at - coalesce(m.reopened_at, m.created_at))) / 60)
            filter (where m.replied_at is not null))::int
    from public.profiles p
    left join public.matches m on (m.user_a = p.id or m.user_b = p.id) and m.initiator is not null and m.initiator <> p.id
                              and coalesce(m.reopened_at, m.created_at) > now() - interval '90 days'
   where p.id = any(ids) and (p.id = auth.uid() or public.is_admin() or (private.can_browse() and private.is_compatible(p.id)))
   group by p.id;
$$;
revoke execute on function public.reply_stats(uuid[]) from anon, public;
grant execute on function public.reply_stats(uuid[]) to authenticated;

-- 語音自我介紹（15 秒內，管理員審核後才公開） ----------------------------
create table if not exists public.voice_intros (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  path        text not null,
  duration    int check (duration between 1 and 20),
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz
);
alter table public.voice_intros enable row level security;
create or replace function public.voice_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;   -- 系統／後台直接操作
  if public.is_admin() and (tg_op = 'UPDATE' and new.path = old.path) then
    if new.status <> old.status then new.reviewed_at := now(); end if; return new;
  end if;
  if auth.uid() is not null and new.user_id <> auth.uid() then raise exception '只能上傳自己的語音'; end if;
  if new.path !~ ('^' || new.user_id::text || '/[0-9]+\.(webm|m4a|mp4|ogg|aac|mp3)$') then raise exception '語音路徑不正確'; end if;
  if tg_op = 'INSERT' or new.path <> old.path then new.status := 'pending'; new.reviewed_at := null; new.created_at := now();
  else new.status := old.status; new.reviewed_at := old.reviewed_at; end if;
  return new;
end $$;
drop trigger if exists voice_guard_trg on public.voice_intros;
create trigger voice_guard_trg before insert or update on public.voice_intros for each row execute function public.voice_guard();
drop policy if exists "voice_select" on public.voice_intros;
create policy "voice_select" on public.voice_intros for select to authenticated
  using (user_id = auth.uid() or public.is_admin()
         or (status = 'approved' and private.can_browse() and private.is_compatible(user_id) and not private.is_blocked_with(user_id)
             and exists (select 1 from public.profiles p where p.id = user_id and p.status = 'approved')));
drop policy if exists "voice_insert" on public.voice_intros;
create policy "voice_insert" on public.voice_intros for insert to authenticated
  with check (user_id = auth.uid() and public.my_status() in ('approved','pending','rejected'));
drop policy if exists "voice_update" on public.voice_intros;
create policy "voice_update" on public.voice_intros for update to authenticated
  using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());
drop policy if exists "voice_delete" on public.voice_intros;
create policy "voice_delete" on public.voice_intros for delete to authenticated using (user_id = auth.uid() or public.is_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voice', 'voice', false, 2097152, array['audio/webm','audio/mp4','audio/x-m4a','audio/aac','audio/mpeg','audio/ogg'])
on conflict (id) do update set public = false, file_size_limit = 2097152,
  allowed_mime_types = array['audio/webm','audio/mp4','audio/x-m4a','audio/aac','audio/mpeg','audio/ogg'];
create or replace function private.my_voice_file_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'voice' and name like auth.uid()::text || '/%';
$$;
create or replace function private.voice_path_in_use(fname text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.voice_intros where path = fname);
$$;
drop policy if exists "voice_storage_insert" on storage.objects;
create policy "voice_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'voice' and name ~ ('^' || auth.uid()::text || '/[0-9]+\.(webm|m4a|mp4|ogg|aac|mp3)$')
              and private.my_voice_file_count() < 3 and not private.voice_path_in_use(name));
drop policy if exists "voice_storage_select" on storage.objects;
create policy "voice_storage_select" on storage.objects for select to authenticated
  using (bucket_id = 'voice' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()
         or exists (select 1 from public.voice_intros v where v.path = name and v.status = 'approved'
                      and private.can_browse() and private.is_compatible(v.user_id) and not private.is_blocked_with(v.user_id)
                      and exists (select 1 from public.profiles op where op.id = v.user_id and (op.status = 'approved' or (op.status = 'pending' and private.has_open_match(op.id)))))));
drop policy if exists "voice_storage_delete" on storage.objects;
create policy "voice_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'voice' and (public.is_admin() or ((storage.foldername(name))[1] = auth.uid()::text and not private.voice_path_in_use(name))));

-- v0.31：不經過對話也能評價與報平安（例如已封鎖或結束對話）
create or replace function public.my_open_items()
returns table (kind text, invite_id uuid, date_at timestamptz, partner text, ends_at timestamptz)
language sql stable security definer set search_path = public as $$
  select 'review', v.id, v.date_at, p.nickname, null::timestamptz
    from public.date_invites v left join public.profiles p on p.id = case when v.from_id = auth.uid() then v.to_id else v.from_id end
   where (v.from_id = auth.uid() or v.to_id = auth.uid()) and v.status = 'accepted'
     and v.date_at < now() - interval '3 hours' and v.date_at > now() - interval '30 days'
     and not exists (select 1 from public.meet_reviews r where r.invite_id = v.id and r.reviewer_id = auth.uid())
  union all
  select 'checkin', v.id, v.date_at, p.nickname, sc.ends_at
    from public.safety_checks sc join public.date_invites v on v.id = sc.invite_id
    left join public.profiles p on p.id = case when v.from_id = auth.uid() then v.to_id else v.from_id end
   where sc.owner_id = auth.uid() and sc.checked_in_at is null and v.status = 'accepted' and sc.ends_at > now() - interval '2 days'
  order by 3 desc limit 10;
$$;
revoke execute on function public.my_open_items() from anon, public;
grant execute on function public.my_open_items() to authenticated;


-- =====================================================================
-- v0.32  今晚有空、旅行模式
-- =====================================================================
create index if not exists profiles_travel_idx on public.profiles(travel_city, travel_to) where travel_city is not null;

create or replace function public.set_free_tonight(p_on boolean)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare loc timestamp := now() at time zone 'Asia/Taipei'; v timestamptz;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and status = 'approved') then raise exception '檔案通過審核後才能使用'; end if;
  if p_on then
    -- 到隔天早上 6 點（台灣時間）自動消失；凌晨 6 點前開啟則到當天 6 點
    v := (case when extract(hour from loc) < 6 then date_trunc('day', loc) + interval '6 hours'
               else date_trunc('day', loc) + interval '30 hours' end) at time zone 'Asia/Taipei';
  end if;
  perform set_config('halfsugar.avail', '1', true);
  update public.profiles set free_until = v where id = auth.uid();
  perform set_config('halfsugar.avail', '', true);
  return v;
end $$;

create or replace function public.set_travel(p_city text, p_from date, p_to date)
returns void language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Taipei')::date; home text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select city into home from public.profiles where id = auth.uid() and status = 'approved';
  if not found then raise exception '檔案通過審核後才能使用'; end if;
  if p_city is not null then
    if p_city not in ('台北市','新北市','桃園市','新竹','台中市','彰化','雲林','嘉義','台南市','高雄市','屏東','基隆','宜蘭','花蓮','台東','南投','苗栗','澎湖','金門') then raise exception '請選擇要去的城市'; end if;
    if p_city = home then raise exception '要去的城市和你的所在地相同'; end if;
    if p_from is null or p_to is null then raise exception '請選擇日期'; end if;
    -- 已經出發的行程：出發日維持原本的，可以改回程日
    if p_from < today and not exists (select 1 from public.profiles where id = auth.uid() and travel_city = p_city and travel_from = p_from and travel_to >= today) then
      raise exception '出發日已經過了'; end if;
    if p_from > today + 60 then raise exception '只能設定 60 天內的行程'; end if;
    if p_to < p_from then raise exception '回程日要在出發日之後'; end if;
    if p_to > p_from + 13 then raise exception '一次最多 14 天'; end if;
  end if;
  perform set_config('halfsugar.avail', '1', true);
  update public.profiles set travel_city = p_city, travel_from = case when p_city is null then null else p_from end,
         travel_to = case when p_city is null then null else p_to end where id = auth.uid();
  perform set_config('halfsugar.avail', '', true);
end $$;

revoke all on function public.set_free_tonight(boolean) from public, anon;
revoke all on function public.set_travel(text, date, date) from public, anon;
grant execute on function public.set_free_tonight(boolean) to authenticated;
grant execute on function public.set_travel(text, date, date) to authenticated;

-- v0.36：內部函式不開放直接執行
revoke all on function private.invite_msg(uuid, uuid, text) from public, anon, authenticated;

-- v0.37：同一支手機以前刪掉的帳號收到的評價（管理員用）
create or replace function public.admin_prior_review_counts(ids uuid[])
returns table (id uuid, n bigint, bad bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select u.id, count(r.*), count(r.*) filter (where r.rating = 1)
                 from auth.users u join public.meet_reviews r on r.reviewee_phone_hash = private.phone_hash(u.phone) and r.reviewee_id is distinct from u.id
                where u.id = any(ids) and nullif(u.phone,'') is not null group by u.id;
end $$;
revoke execute on function public.admin_prior_review_counts(uuid[]) from anon, public;
grant execute on function public.admin_prior_review_counts(uuid[]) to authenticated;

create or replace function public.admin_prior_reviews(target uuid)
returns table (created_at timestamptz, old_name text, reviewer text, rating smallint, tags text[], note text, date_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select r.created_at, coalesce(r.reviewee_name, '（未知）'), coalesce(p.nickname, '（已刪除）'), r.rating, r.tags, r.note, r.date_at
                 from auth.users u join public.meet_reviews r on r.reviewee_phone_hash = private.phone_hash(u.phone) and r.reviewee_id is distinct from u.id
                 left join public.profiles p on p.id = r.reviewer_id
                where u.id = target and nullif(u.phone,'') is not null order by r.created_at desc;
end $$;
revoke execute on function public.admin_prior_reviews(uuid) from anon, public;
grant execute on function public.admin_prior_reviews(uuid) to authenticated;

-- v0.38：索取紀錄的對象不能被改掉；婉拒時重新計算 3 天冷卻期；回填通過審核的頭像
create or replace function private.request_row_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.requester_id := old.requester_id; new.owner_id := old.owner_id;
  if new.status = 'denied' and old.status is distinct from 'denied' then new.created_at := now(); end if;
  return new;
end $$;
drop trigger if exists photo_requests_row_guard on public.photo_requests;
create trigger photo_requests_row_guard before update on public.photo_requests for each row execute function private.request_row_guard();
drop trigger if exists wealth_requests_row_guard on public.wealth_requests;
create trigger wealth_requests_row_guard before update on public.wealth_requests for each row execute function private.request_row_guard();
update public.profiles set approved_avatar_path = avatar_path where status = 'approved' and approved_avatar_path is distinct from avatar_path;

-- v0.39：回填通過審核的自介、職業、興趣
update public.profiles set approved_bio = bio, approved_occupation = occupation, approved_tags = tags
 where status = 'approved' and (approved_bio is distinct from bio or approved_occupation is distinct from occupation or approved_tags is distinct from tags);

-- v0.40：手機驗證簡訊改由後端（Edge Function phone-verify）寄送並限制次數
--   每個帳號最多 3 封、每支手機最多 3 封、全站每小時最多 30 封。
--   Supabase 內建的 Phone 登入維持關閉，任何人都無法繞過次數限制直接寄簡訊。
create table if not exists public.sms_sends (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  phone_hash text not null,
  created_at timestamptz not null default now()
);
create index if not exists sms_sends_user_idx on public.sms_sends(user_id);
create index if not exists sms_sends_phone_idx on public.sms_sends(phone_hash);
create index if not exists sms_sends_time_idx on public.sms_sends(created_at);
alter table public.sms_sends enable row level security;
revoke all on public.sms_sends from anon, authenticated;

-- 只給後端（service_role）呼叫：檢查並預留一次寄送額度。回傳 'ok' 或原因代碼。
create or replace function public.sms_reserve(uid uuid, ph text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare h text := private.phone_hash(ph); nu int; np int; ng int; rid bigint;
begin
  if uid is null or coalesce(ph,'') !~ '^\+?8869\d{8}$' then return jsonb_build_object('r','bad_phone'); end if;
  perform pg_advisory_xact_lock(hashtext('sms_reserve'));
  if exists (select 1 from auth.users u where u.id = uid and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) then
    return jsonb_build_object('r','already');
  end if;
  if exists (select 1 from public.banned_phones b where b.phone_hash = h) then return jsonb_build_object('r','banned'); end if;
  -- 手機已綁定別的帳號時照樣寄（v0.41：驗證後改問「要不要恢復原本帳號」），一樣計入次數
  select count(*) into nu from public.sms_sends where user_id = uid;
  if nu >= 3 then return jsonb_build_object('r','user_limit'); end if;
  select count(*) into np from public.sms_sends where phone_hash = h;
  if np >= 3 then return jsonb_build_object('r','phone_limit'); end if;
  select count(*) into ng from public.sms_sends where created_at > now() - interval '1 hour';
  if ng >= 30 then return jsonb_build_object('r','global_limit'); end if;
  insert into public.sms_sends (user_id, phone_hash) values (uid, h) returning id into rid;
  return jsonb_build_object('r','ok','id',rid,'left',2-nu);
end $$;
revoke execute on function public.sms_reserve(uuid, text) from anon, authenticated, public;
grant execute on function public.sms_reserve(uuid, text) to service_role;

-- Twilio 寄送失敗時退回額度
create or replace function public.sms_refund(rid bigint)
returns void language sql security definer set search_path = public as $$
  delete from public.sms_sends where id = rid;
$$;
revoke execute on function public.sms_refund(bigint) from anon, authenticated, public;
grant execute on function public.sms_refund(bigint) to service_role;

-- 驗證成功後，確認這支手機仍未被別人綁定、也不在黑名單
create or replace function public.sms_phone_free(uid uuid, ph text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.banned_phones b where b.phone_hash = private.phone_hash(ph)) then 'banned'
    when exists (select 1 from auth.users u where u.id <> uid and nullif(u.phone,'') is not null and private.phone_hash(u.phone) = private.phone_hash(ph)) then 'phone_exists'
    else 'ok' end;
$$;
revoke execute on function public.sms_phone_free(uuid, text) from anon, authenticated, public;
grant execute on function public.sms_phone_free(uuid, text) to service_role;

-- 自己還剩幾次
create or replace function public.my_sms_left()
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, 3 - (select count(*)::int from public.sms_sends where user_id = auth.uid()));
$$;
revoke execute on function public.my_sms_left() from anon, public;
grant execute on function public.my_sms_left() to authenticated;

-- 管理員：查看與重設簡訊次數
create or replace function public.admin_sms_counts(ids uuid[])
returns table (id uuid, n int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select s.user_id, count(*)::int from public.sms_sends s where s.user_id = any(ids) group by s.user_id;
end $$;
revoke execute on function public.admin_sms_counts(uuid[]) from anon, public;
grant execute on function public.admin_sms_counts(uuid[]) to authenticated;

create or replace function public.admin_reset_sms(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare hs text[];
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  select array_agg(distinct phone_hash) into hs from public.sms_sends where user_id = target;
  delete from public.sms_sends where user_id = target or phone_hash = any(coalesce(hs, '{}'));
end $$;
revoke execute on function public.admin_reset_sms(uuid) from anon, public;
grant execute on function public.admin_reset_sms(uuid) to authenticated;

-- v0.41：同一支手機再註冊 → 驗證手機後詢問是否恢復原本帳號（一支手機仍只能綁一個帳號）
create table if not exists public.phone_recover (
  uid uuid primary key references auth.users(id) on delete cascade,
  target uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null
);
alter table public.phone_recover enable row level security;
revoke all on public.phone_recover from anon, authenticated;

-- 驗證成功後：這支手機屬於別的帳號嗎？是的話記下來（15 分鐘內可以恢復），回傳原帳號 Email
create or replace function public.sms_recover_start(uid uuid, ph text)
returns text language plpgsql security definer set search_path = public as $$
declare t uuid; em text;
begin
  select u.id, u.email into t, em from auth.users u
   where u.id <> sms_recover_start.uid and nullif(u.phone,'') is not null and private.phone_hash(u.phone) = private.phone_hash(ph) limit 1;
  if t is null then return null; end if;
  insert into public.phone_recover (uid, target, expires_at) values (sms_recover_start.uid, t, now() + interval '15 minutes')
    on conflict on constraint phone_recover_pkey do update set target = excluded.target, expires_at = excluded.expires_at;
  return coalesce(em, '');
end $$;
revoke execute on function public.sms_recover_start(uuid, text) from anon, authenticated, public;
grant execute on function public.sms_recover_start(uuid, text) to service_role;

-- 使用者選擇恢復：取出原帳號 Email（只能用一次），並回傳目前這個新帳號是不是還沒建檔的空帳號
create or replace function public.sms_recover_take(uid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t uuid; em text; st text;
begin
  delete from public.phone_recover where phone_recover.uid = sms_recover_take.uid and expires_at > now() returning target into t;
  if t is null then return jsonb_build_object('r','expired'); end if;
  select email into em from auth.users where id = t;
  select status into st from public.profiles where id = sms_recover_take.uid;
  return jsonb_build_object('r','ok','email',coalesce(em,''),'empty', coalesce(st,'incomplete') = 'incomplete');
end $$;
revoke execute on function public.sms_recover_take(uuid) from anon, authenticated, public;
grant execute on function public.sms_recover_take(uuid) to service_role;

-- v0.42：簡訊防護加強
--   同一個 IP 每小時／每天上限、全站每小時／每天上限（後台可調）、緊急暫停、拋棄式信箱不能註冊
alter table public.sms_sends add column if not exists ip_hash text;
create index if not exists sms_sends_ip_idx on public.sms_sends(ip_hash) where ip_hash is not null;
insert into public.app_config (key, value) values
  ('sms_paused','off'), ('sms_ip_hour','5'), ('sms_ip_day','10'), ('sms_hour','100'), ('sms_day','300'), ('turnstile_sitekey','')
  on conflict (key) do nothing;

create or replace function private.cfg_int(k text, d int)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select case when value ~ '^\d{1,6}$' then value::int end from public.app_config where key = k), d);
$$;

drop function if exists public.sms_reserve(uuid, text);
create or replace function public.sms_reserve(uid uuid, ph text, ip text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare h text := private.phone_hash(ph); ih text; nu int; np int; n int; rid bigint;
begin
  if uid is null or coalesce(ph,'') !~ '^\+?8869\d{8}$' then return jsonb_build_object('r','bad_phone'); end if;
  if coalesce((select value from public.app_config where key = 'sms_paused'), 'off') = 'on' then return jsonb_build_object('r','paused'); end if;
  perform pg_advisory_xact_lock(hashtext('sms_reserve'));
  if exists (select 1 from auth.users u where u.id = uid and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) then
    return jsonb_build_object('r','already');
  end if;
  if exists (select 1 from public.banned_phones b where b.phone_hash = h) then return jsonb_build_object('r','banned'); end if;
  -- 手機已綁定別的帳號時照樣寄（驗證後改問「要不要恢復原本帳號」），一樣計入次數
  select count(*) into nu from public.sms_sends where user_id = uid;
  if nu >= 3 then return jsonb_build_object('r','user_limit'); end if;
  select count(*) into np from public.sms_sends where phone_hash = h;
  if np >= 3 then return jsonb_build_object('r','phone_limit'); end if;
  if nullif(ip,'') is not null then
    ih := encode(digest('halfsugar-ip:' || ip, 'sha256'), 'hex');
    select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 hour';
    if n >= private.cfg_int('sms_ip_hour', 5) then return jsonb_build_object('r','ip_limit'); end if;
    select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 day';
    if n >= private.cfg_int('sms_ip_day', 10) then return jsonb_build_object('r','ip_limit'); end if;
  end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_hour', 100) then return jsonb_build_object('r','global_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_day', 300) then return jsonb_build_object('r','global_limit'); end if;
  insert into public.sms_sends (user_id, phone_hash, ip_hash) values (uid, h, ih) returning id into rid;
  return jsonb_build_object('r','ok','id',rid,'left',2-nu);
end $$;
revoke execute on function public.sms_reserve(uuid, text, text) from anon, authenticated, public;
grant execute on function public.sms_reserve(uuid, text, text) to service_role;

-- 管理員：簡訊監控與設定
create or replace function public.admin_sms_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return jsonb_build_object(
    'hour', (select count(*) from public.sms_sends where created_at > now() - interval '1 hour'),
    'day',  (select count(*) from public.sms_sends where created_at > now() - interval '1 day'),
    'week', (select count(*) from public.sms_sends where created_at > now() - interval '7 days'),
    'paused', coalesce((select value from public.app_config where key = 'sms_paused'), 'off') = 'on',
    'ip_hour', private.cfg_int('sms_ip_hour', 5), 'ip_day', private.cfg_int('sms_ip_day', 10),
    'max_hour', private.cfg_int('sms_hour', 100), 'max_day', private.cfg_int('sms_day', 300));
end $$;
revoke execute on function public.admin_sms_stats() from anon, public;
grant execute on function public.admin_sms_stats() to authenticated;

create or replace function public.admin_set_sms_config(k text, v text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  if k = 'sms_paused' then
    if v not in ('on','off') then raise exception '設定值不正確'; end if;
  elsif k in ('sms_ip_hour','sms_ip_day','sms_hour','sms_day') then
    if coalesce(v,'') !~ '^\d{1,5}$' or v::int < 1 then raise exception '請輸入 1 以上的整數'; end if;
  else raise exception '不能修改這個設定';
  end if;
  insert into public.app_config (key, value) values (k, v) on conflict (key) do update set value = excluded.value;
end $$;
revoke execute on function public.admin_set_sms_config(text, text) from anon, public;
grant execute on function public.admin_set_sms_config(text, text) to authenticated;

-- 拋棄式（臨時）信箱不能註冊
create table if not exists public.blocked_email_domains (domain text primary key);
alter table public.blocked_email_domains enable row level security;
revoke all on public.blocked_email_domains from anon, authenticated;
insert into public.blocked_email_domains (domain) values
  ('mailinator.com'),('guerrillamail.com'),('guerrillamail.net'),('guerrillamail.org'),('guerrillamailblock.com'),('sharklasers.com'),('grr.la'),
  ('10minutemail.com'),('10minutemail.net'),('10minemail.com'),('temp-mail.org'),('temp-mail.io'),('tempmail.com'),('tempmail.net'),('tempmail.dev'),
  ('tempmailo.com'),('tempr.email'),('tempail.com'),('throwawaymail.com'),('yopmail.com'),('yopmail.net'),('yopmail.fr'),('getnada.com'),('nada.email'),
  ('dispostable.com'),('maildrop.cc'),('mailnesia.com'),('mintemail.com'),('mohmal.com'),('emailondeck.com'),('fakeinbox.com'),('trashmail.com'),
  ('trashmail.de'),('trashmail.net'),('mytemp.email'),('tempinbox.com'),('spamgourmet.com'),('mailcatch.com'),('moakt.com'),('emailfake.com'),
  ('fakemail.net'),('burnermail.io'),('inboxkitten.com'),('mail.tm'),('mail.gw'),('linshiyouxiang.net'),('1secmail.com'),('1secmail.org'),
  ('1secmail.net'),('byom.de'),('discard.email'),('dropmail.me'),('etranquil.com'),('harakirimail.com'),('jetable.org'),('mailpoof.com'),
  ('mailsac.com'),('mailtemp.info'),('minuteinbox.com'),('owlymail.com'),('spambox.us'),('tmpmail.org'),('tmpmail.net'),('tmail.ws'),
  ('vomoto.com'),('wegwerfmail.de'),('xojxe.com'),('zetmail.com'),('emltmp.com'),('tmpeml.com'),('tmpbox.net'),('crazymailing.com'),
  ('cuvox.de'),('dayrep.com'),('einrot.com'),('fleckens.hu'),('gustr.com'),('jourrapide.com'),('rhyta.com'),('superrito.com'),('teleworm.us'),
  ('armyspy.com'),('anonbox.net'),('mailforspam.com'),('spam4.me'),('tempemail.net'),('instantemailaddress.com'),('temporarymail.com')
  on conflict do nothing;

create or replace function private.block_disposable_email()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email is not null and exists (select 1 from public.blocked_email_domains d where d.domain = lower(split_part(new.email, '@', 2))) then
    raise exception 'disposable_email: 這個 Email 無法註冊，請改用常用的信箱';
  end if;
  return new;
end $$;
drop trigger if exists block_disposable_email on auth.users;
create trigger block_disposable_email before insert on auth.users for each row execute function private.block_disposable_email();

-- v0.43：簡訊防護修正（獨立審查後）
--   1. 驗證碼核對：已綁手機的帳號不能換號；只接受自己 15 分鐘內寄過的號碼
--   2. 管理員重設改成「作廢」而不是刪除：全站／IP 用量照算，只有帳號／手機次數歸零；可依手機號碼重設
--   3. 恢復原帳號時，只有真的空帳號（非管理員、沒照片、沒頭像、未建檔）才會被刪
--   4. 拋棄式信箱：子網域也擋，改 Email 也擋
alter table public.sms_sends add column if not exists voided_at timestamptz;

create or replace function public.sms_reserve(uid uuid, ph text, ip text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare h text := private.phone_hash(ph); ih text; nu int; np int; n int; rid bigint;
begin
  if uid is null or coalesce(ph,'') !~ '^\+?8869\d{8}$' then return jsonb_build_object('r','bad_phone'); end if;
  if coalesce((select value from public.app_config where key = 'sms_paused'), 'off') = 'on' then return jsonb_build_object('r','paused'); end if;
  perform pg_advisory_xact_lock(hashtext('sms_reserve'));
  if exists (select 1 from auth.users u where u.id = uid and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) then
    return jsonb_build_object('r','already');
  end if;
  if exists (select 1 from public.banned_phones b where b.phone_hash = h) then return jsonb_build_object('r','banned'); end if;
  select count(*) into nu from public.sms_sends where user_id = uid and voided_at is null;
  if nu >= 3 then return jsonb_build_object('r','user_limit'); end if;
  select count(*) into np from public.sms_sends where phone_hash = h and voided_at is null;
  if np >= 3 then return jsonb_build_object('r','phone_limit'); end if;
  ih := encode(digest('halfsugar-ip:' || coalesce(nullif(ip,''), 'unknown'), 'sha256'), 'hex');
  select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_ip_hour', 5) * (case when nullif(ip,'') is null then 4 else 1 end) then return jsonb_build_object('r','ip_limit'); end if;
  select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_ip_day', 10) * (case when nullif(ip,'') is null then 4 else 1 end) then return jsonb_build_object('r','ip_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_hour', 100) then return jsonb_build_object('r','global_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_day', 300) then return jsonb_build_object('r','global_limit'); end if;
  insert into public.sms_sends (user_id, phone_hash, ip_hash) values (uid, h, ih) returning id into rid;
  return jsonb_build_object('r','ok','id',rid,'left',2-nu);
end $$;
revoke execute on function public.sms_reserve(uuid, text, text) from anon, authenticated, public;
grant execute on function public.sms_reserve(uuid, text, text) to service_role;

-- 核對驗證碼之前：這個帳號還沒綁手機、而且 15 分鐘內真的寄過這支號碼
create or replace function public.sms_check_ok(uid uuid, ph text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from auth.users u where u.id = uid and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) then 'already'
    when not exists (select 1 from public.sms_sends s where s.user_id = uid and s.phone_hash = private.phone_hash(ph) and s.created_at > now() - interval '15 minutes') then 'no_send'
    else 'ok' end;
$$;
revoke execute on function public.sms_check_ok(uuid, text) from anon, authenticated, public;
grant execute on function public.sms_check_ok(uuid, text) to service_role;

create or replace function public.my_sms_left()
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, 3 - (select count(*)::int from public.sms_sends where user_id = auth.uid() and voided_at is null));
$$;

create or replace function public.admin_sms_counts(ids uuid[])
returns table (id uuid, n int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select s.user_id, count(*)::int from public.sms_sends s where s.user_id = any(ids) and s.voided_at is null group by s.user_id;
end $$;

create or replace function public.admin_reset_sms(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare hs text[];
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  select array_agg(distinct phone_hash) into hs from public.sms_sends where user_id = target and voided_at is null;
  update public.sms_sends set voided_at = now() where voided_at is null and (user_id = target or phone_hash = any(coalesce(hs, '{}')));
end $$;

-- 依手機號碼重設（例如號碼被別人惡意用掉次數）
create or replace function public.admin_reset_sms_phone(ph text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  if coalesce(regexp_replace(ph, '\D', '', 'g'), '') !~ '^(886|0)9\d{8}$' then raise exception '請輸入 09 開頭的 10 碼手機號碼'; end if;
  update public.sms_sends set voided_at = now()
   where voided_at is null and phone_hash = private.phone_hash('886' || right(regexp_replace(ph, '\D', '', 'g'), 9));
  get diagnostics n = row_count; return n;
end $$;
revoke execute on function public.admin_reset_sms_phone(text) from anon, public;
grant execute on function public.admin_reset_sms_phone(text) to authenticated;

-- 恢復原帳號：只有真正的空帳號才可以刪
create or replace function public.sms_recover_take(uid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t uuid; em text; empty boolean;
begin
  delete from public.phone_recover where phone_recover.uid = sms_recover_take.uid and expires_at > now() returning target into t;
  if t is null then return jsonb_build_object('r','expired'); end if;
  select email into em from auth.users where id = t;
  select coalesce(p.status, 'incomplete') = 'incomplete' and not coalesce(p.is_admin, false) and p.avatar_path is null
         and not exists (select 1 from public.photos ph where ph.user_id = sms_recover_take.uid)
         and not exists (select 1 from auth.users u where u.id = sms_recover_take.uid and nullif(u.phone,'') is not null)
    into empty from public.profiles p where p.id = sms_recover_take.uid;
  return jsonb_build_object('r','ok','email',coalesce(em,''),'empty', coalesce(empty, false));
end $$;
revoke execute on function public.sms_recover_take(uuid) from anon, authenticated, public;
grant execute on function public.sms_recover_take(uuid) to service_role;

-- 拋棄式信箱：子網域也擋；註冊與改 Email 都檢查
create or replace function private.block_disposable_email()
returns trigger language plpgsql security definer set search_path = public as $$
declare d text;
begin
  if new.email is null then return new; end if;
  if tg_op = 'UPDATE' and new.email is not distinct from old.email then return new; end if;
  d := lower(split_part(new.email, '@', 2));
  if exists (select 1 from public.blocked_email_domains b where d = b.domain or d like '%.' || b.domain) then
    raise exception 'disposable_email: 這個 Email 無法註冊，請改用常用的信箱';
  end if;
  return new;
end $$;
drop trigger if exists block_disposable_email on auth.users;
create trigger block_disposable_email before insert or update of email on auth.users for each row execute function private.block_disposable_email();

-- =====================================================================
-- v0.44：整體安全性加強（獨立審查後）
-- =====================================================================

-- 1. 權限縱深防禦：未登入的人（anon）不能直接碰任何資料表；登入者也拿掉用不到的權限
do $g$
declare t record;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r','p','v','m') loop
    execute format('revoke all on public.%I from anon', t.relname);
    execute format('revoke truncate, references, trigger on public.%I from authenticated', t.relname);
  end loop;
end $g$;
grant select on public.app_config to anon, authenticated;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke truncate, references, trigger on tables from authenticated;
alter default privileges in schema public revoke execute on functions from anon, public;

-- 觸發器函式：只給資料庫自己用，任何人都不需要、也不能直接呼叫
do $f$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public','private') and p.prorettype = 'trigger'::regtype loop
    execute format('revoke execute on function %s from anon, authenticated, public', f.sig);
  end loop;
end $f$;

-- 網站設定：只公開前端需要的兩項（簡訊上限、暫停狀態不給外人看）
drop policy if exists "app_config_read" on public.app_config;
drop policy if exists "app_config_read_anon" on public.app_config;
drop policy if exists "app_config_read_auth" on public.app_config;
create policy "app_config_read_anon" on public.app_config for select to anon
  using (key in ('free_launch', 'turnstile_sitekey'));
create policy "app_config_read_auth" on public.app_config for select to authenticated
  using (key in ('free_launch', 'turnstile_sitekey') or public.is_admin());

-- 2. 「我看得到這位會員嗎」：和 profiles 的讀取規則一致（隱身、封鎖、方向、狀態）
create or replace function private.profile_visible(x uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select x = auth.uid() or public.is_admin()
      or (private.can_browse() and private.is_compatible(x) and not private.is_blocked_with(x)
          and exists (select 1 from public.profiles p where p.id = x
                        and ((p.status = 'approved'
                              and (not p.hidden
                                   or exists (select 1 from public.likes l where l.from_id = x and l.to_id = auth.uid())
                                   or private.has_open_match(x)))
                             or (p.status = 'pending' and private.has_open_match(x)))));
$$;
-- 「這個人和我有關係嗎」：互相心動、對話（含已結束）、索取私密照或財力文件
create or replace function private.related_to(x uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.likes where (from_id = auth.uid() and to_id = x) or (from_id = x and to_id = auth.uid()))
      or exists (select 1 from public.matches where user_a = least(auth.uid(), x) and user_b = greatest(auth.uid(), x))
      or exists (select 1 from public.photo_requests where (requester_id = auth.uid() and owner_id = x) or (requester_id = x and owner_id = auth.uid()))
      or exists (select 1 from public.wealth_requests where (requester_id = auth.uid() and owner_id = x) or (requester_id = x and owner_id = auth.uid()));
$$;
revoke all on function private.profile_visible(uuid) from public, anon;
revoke all on function private.related_to(uuid) from public, anon;
grant execute on function private.profile_visible(uuid) to authenticated;
grant execute on function private.related_to(uuid) to authenticated;

-- 封鎖、檢舉：只能針對看得到或有關係的人（不能拿任意 ID 探測對方是否存在、叫什麼）
drop policy if exists "blocks_insert" on public.blocks;
create policy "blocks_insert" on public.blocks for insert to authenticated
  with check (blocker_id = auth.uid() and blocked_id <> auth.uid()
              and (private.profile_visible(blocked_id) or private.related_to(blocked_id)));
drop policy if exists "reports_insert" on public.reports;
create policy "reports_insert" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open' and reported_id <> auth.uid()
              and public.my_status() in ('pending','approved','rejected')
              and char_length(coalesce(detail,'')) <= 1000
              and private.my_reports_today() < 5
              and (private.profile_visible(reported_id) or private.related_to(reported_id)));

-- 心動：每天最多 100 個，而且對方要看得到（隱身會員不會被陌生人探測到）
create or replace function private.my_likes_today()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.likes where from_id = auth.uid() and created_at > now() - interval '1 day';
$$;
revoke all on function private.my_likes_today() from public, anon;
grant execute on function private.my_likes_today() to authenticated;
drop policy if exists "likes_insert" on public.likes;
create policy "likes_insert" on public.likes for insert to authenticated
  with check (
    from_id = auth.uid()
    and public.my_status() = 'approved'
    and exists (select 1 from public.profiles p where p.id = to_id and p.status = 'approved')
    and private.profile_visible(to_id)
    and private.my_likes_today() < 100
  );

-- 私密照索取：對方要看得到
drop policy if exists "requests_insert" on public.photo_requests;
create policy "requests_insert" on public.photo_requests for insert to authenticated
  with check (requester_id = auth.uid() and status = 'pending'
              and public.my_status() = 'approved'
              and exists (select 1 from public.profiles p where p.id = owner_id and p.status = 'approved')
              and private.profile_visible(owner_id));

create or replace function public.request_private_photos(owner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.photo_requests;
begin
  if public.my_status() is distinct from 'approved' then raise exception '資料審核通過後才能索取'; end if;
  if owner = auth.uid() or not private.profile_visible(owner)
     or not exists (select 1 from public.profiles where id = owner and status = 'approved') then
    raise exception '無法向這位會員索取';
  end if;
  select * into r from public.photo_requests where requester_id = auth.uid() and owner_id = owner;
  if found then
    if r.status = 'pending' then raise exception '已送出索取，等待對方同意'; end if;
    if r.status = 'granted' and exists (select 1 from public.photo_grants where owner_id = owner and viewer_id = auth.uid()) then return; end if;
    if r.status = 'denied' and r.created_at > now() - interval '3 days' then raise exception '對方剛婉拒，3 天後才能再問一次'; end if;
    update public.photo_requests set status = 'pending', created_at = now() where requester_id = auth.uid() and owner_id = owner;
  else
    insert into public.photo_requests (requester_id, owner_id) values (auth.uid(), owner);
  end if;
end $$;

create or replace function public.private_photo_count(uid uuid)
returns int language sql stable security definer set search_path = public as $$
  select case when not private.profile_visible(uid)
              or not exists (select 1 from public.profiles where id = uid and status = 'approved') then 0
         else (select count(*)::int from public.photos where user_id = uid and is_private and status = 'approved') end;
$$;

create or replace function public.request_wealth_view(owner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.wealth_requests;
begin
  if public.my_status() is distinct from 'approved' then raise exception '檔案審核通過後才能申請查看'; end if;
  if owner = auth.uid() or not private.profile_visible(owner)
     or not exists (select 1 from public.profiles where id = owner and status = 'approved')
     or private.wealth_doc_path(owner) is null then
    raise exception '這位會員目前沒有可查看的財力證明';
  end if;
  select * into r from public.wealth_requests where requester_id = auth.uid() and owner_id = owner;
  if found then
    if r.status = 'pending' then raise exception '已送出申請，等待對方同意'; end if;
    if r.status = 'granted' then return; end if;
    if r.created_at > now() - interval '3 days' then raise exception '對方剛婉拒，3 天後才能再申請'; end if;
    update public.wealth_requests set status = 'pending', created_at = now() where requester_id = auth.uid() and owner_id = owner;
  else
    insert into public.wealth_requests (requester_id, owner_id) values (auth.uid(), owner);
  end if;
end $$;

create or replace function public.wealth_doc_status(owner uuid)
returns table (state text, path text) language plpgsql stable security definer set search_path = public as $$
declare r public.wealth_requests; doc text;
begin
  if owner <> auth.uid() and not private.profile_visible(owner) then return query select 'none'::text, null::text; return; end if;
  doc := private.wealth_doc_path(owner);
  if doc is null or private.is_blocked_with(owner) then return query select 'none'::text, null::text; return; end if;
  if owner = auth.uid() then return query select 'own'::text, doc; return; end if;
  select * into r from public.wealth_requests where requester_id = auth.uid() and owner_id = owner;
  if not found then return query select 'can_request'::text, null::text;
  elsif r.status = 'granted' then return query select 'granted'::text, doc;
  else return query select r.status, null::text; end if;
end $$;

-- 回覆率：只回傳看得到的人（封鎖、隱身、停權、未建檔一律不回傳）
create or replace function public.reply_stats(ids uuid[])
returns table (id uuid, n bigint, replied bigint, median_min int)
language sql stable security definer set search_path = public as $$
  select p.id, count(m.id), count(m.replied_at),
         (percentile_cont(0.5) within group (order by extract(epoch from (m.replied_at - coalesce(m.reopened_at, m.created_at))) / 60)
            filter (where m.replied_at is not null))::int
    from public.profiles p
    left join public.matches m on (m.user_a = p.id or m.user_b = p.id) and m.initiator is not null and m.initiator <> p.id
                              and coalesce(m.reopened_at, m.created_at) > now() - interval '90 days'
   where p.id = any(ids) and private.profile_visible(p.id)
   group by p.id;
$$;

-- 語音介紹：和檔案一樣的可見規則
drop policy if exists "voice_select" on public.voice_intros;
create policy "voice_select" on public.voice_intros for select to authenticated
  using (user_id = auth.uid() or public.is_admin()
         or (status = 'approved' and private.profile_visible(user_id)
             and exists (select 1 from public.profiles p where p.id = user_id and p.status = 'approved')));

-- 3. 已讀：只能從「未讀」改成「現在已讀」，不能偽造時間或改回未讀；對話結束後不能再改
create or replace function public.messages_read_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if new.sender_id <> auth.uid() then
    -- 收件人：只能標記已讀
    if new.body is distinct from old.body or new.image_path is distinct from old.image_path or new.recalled_at is distinct from old.recalled_at
       or new.sender_id is distinct from old.sender_id or new.match_id is distinct from old.match_id or new.created_at is distinct from old.created_at or new.invite_id is distinct from old.invite_id then
      raise exception '不能修改別人的訊息';
    end if;
    new.read_at := case when old.read_at is null and new.read_at is not null then now() else old.read_at end;
  else
    new.read_at := old.read_at;   -- 寄件人不能改已讀狀態
  end if;
  return new;
end $$;
drop trigger if exists messages_read_guard_trg on public.messages;
create trigger messages_read_guard_trg before update on public.messages for each row execute function public.messages_read_guard();
revoke execute on function public.messages_read_guard() from anon, authenticated, public;
drop policy if exists "messages_update_read" on public.messages;
create policy "messages_update_read" on public.messages for update to authenticated
  using (sender_id <> auth.uid() and exists (select 1 from public.matches m where m.id = match_id
                 and (m.user_a = auth.uid() or m.user_b = auth.uid()) and m.closed_at is null))
  with check (sender_id <> auth.uid());

-- 4. 停權的人不能再做任何設定變更
drop policy if exists "grants_rw" on public.photo_grants;
drop policy if exists "grants_select" on public.photo_grants;
create policy "grants_select" on public.photo_grants for select to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid());
drop policy if exists "grants_insert" on public.photo_grants;
create policy "grants_insert" on public.photo_grants for insert to authenticated
  with check (owner_id = auth.uid() and public.my_status() in ('approved','pending')
              and exists (select 1 from public.photo_requests r where r.owner_id = auth.uid() and r.requester_id = viewer_id)
              and not private.is_blocked_with(viewer_id));
drop policy if exists "grants_delete" on public.photo_grants;
create policy "grants_delete" on public.photo_grants for delete to authenticated
  using (owner_id = auth.uid() or viewer_id = auth.uid());
drop policy if exists "requests_update_owner" on public.photo_requests;
create policy "requests_update_owner" on public.photo_requests for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid() and public.my_status() in ('approved','pending'));
drop policy if exists "wreq_update_owner" on public.wealth_requests;
create policy "wreq_update_owner" on public.wealth_requests for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid() and public.my_status() in ('approved','pending'));
drop policy if exists "photos_update" on public.photos;
create policy "photos_update" on public.photos for update to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (public.is_admin() or (user_id = auth.uid() and public.my_status() <> 'suspended'));
drop policy if exists "voice_update" on public.voice_intros;
create policy "voice_update" on public.voice_intros for update to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (public.is_admin() or (user_id = auth.uid() and public.my_status() <> 'suspended'));

-- 5. 文字長度上限（直接打 API 也不能存超長內容；舊資料不受影響）
alter table public.profiles drop constraint if exists profiles_text_len;
alter table public.profiles add constraint profiles_text_len check (
  char_length(coalesce(nickname,'')) <= 20 and char_length(coalesce(occupation,'')) <= 30 and char_length(coalesce(bio,'')) <= 600
  and coalesce(cardinality(tags),0) <= 8 and char_length(coalesce(array_to_string(tags,''),'')) <= 120
  and char_length(coalesce(travel_city,'')) <= 20 and char_length(coalesce(review_note,'')) <= 500) not valid;

-- 6. 不允許的字眼：伺服器端也檢查（以前只有網頁擋，直接打 API 可以繞過）
create or replace function private.bad_words(t text, chat boolean default false)
returns text language sql immutable set search_path = public as $$
  select string_agg(w, '、') from unnest(array['援交','援助交際','約炮','外送茶','茶莊','魚訊','出場','買春','賣春','性交易','嫖','陪睡','包夜','全套','半套','定點','價碼','一次多少','一晚多少','代聊','line id','加賴']) w
   where position(lower(w) in lower(coalesce(t,''))) > 0
     and not (chat and w = any(array['出場','定點','全套','價碼','一次多少','line id','加賴']));
$$;
revoke all on function private.bad_words(text, boolean) from public, anon;

create or replace function public.messages_words_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare b text;
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  b := private.bad_words(new.body, true);
  if b is not null then raise exception '訊息含不允許的字眼：%', b; end if;
  return new;
end $$;
drop trigger if exists messages_words_guard_trg on public.messages;
create trigger messages_words_guard_trg before insert on public.messages for each row execute function public.messages_words_guard();
revoke execute on function public.messages_words_guard() from anon, authenticated, public;

create or replace function public.profiles_words_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare b text;
begin
  if auth.uid() is null or public.is_admin() or current_setting('halfsugar.deleting', true) = '1' then return new; end if;
  if (new.nickname, new.bio, new.occupation, new.tags) is distinct from (old.nickname, old.bio, old.occupation, old.tags) then
    b := private.bad_words(concat_ws(' ', new.nickname, new.bio, new.occupation, array_to_string(new.tags, ' ')), false);
    if b is not null then raise exception '內容含不允許的字眼：%', b; end if;
  end if;
  if new.openers is distinct from old.openers then
    b := private.bad_words(array_to_string(new.openers, ' '), true);
    if b is not null then raise exception '開場白含不允許的字眼：%', b; end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_words_guard_trg on public.profiles;
create trigger profiles_words_guard_trg before update on public.profiles for each row execute function public.profiles_words_guard();
revoke execute on function public.profiles_words_guard() from anon, authenticated, public;

-- 7. 聊天照片：送出後就不能刪掉或換成別張（證據不會消失）；刪帳號時才能清掉
create table if not exists private.account_deleting (uid uuid primary key, at timestamptz not null default now());
alter table private.account_deleting enable row level security;
revoke all on private.account_deleting from anon, authenticated, public;
create or replace function private.am_deleting()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from private.account_deleting where uid = auth.uid() and at > now() - interval '1 hour');
$$;
create or replace function private.chat_file_used(fname text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.messages where image_path = fname)
      or exists (select 1 from public.message_recalls where image_path = fname);
$$;
revoke all on function private.am_deleting() from public, anon;
revoke all on function private.chat_file_used(text) from public, anon;
grant execute on function private.am_deleting() to authenticated;
grant execute on function private.chat_file_used(text) to authenticated;

create or replace function private.chat_can_upload(fname text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare mid uuid; uid uuid := auth.uid();
begin
  if uid is null or fname !~ ('^' || uid::text || '/[0-9a-f-]{36}-[0-9]+\.jpg$') then return false; end if;
  if private.chat_file_used(fname) then return false; end if;   -- 同一個檔名不能重複使用
  mid := substring(fname from '^[^/]+/([0-9a-f-]{36})-')::uuid;
  return exists (select 1 from public.matches m where m.id = mid and m.closed_at is null and (m.user_a = uid or m.user_b = uid)
                   and not private.is_blocked_with(case when m.user_a = uid then m.user_b else m.user_a end))
     and public.my_status() in ('approved','pending')
     and (select count(*) from storage.objects o where o.bucket_id = 'chat' and o.name like uid::text || '/%' and o.created_at > now() - interval '1 day') < 60;
exception when others then return false;
end $$;

drop policy if exists "chat_storage_delete" on storage.objects;
create policy "chat_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'chat' and (public.is_admin()
         or ((storage.foldername(name))[1] = auth.uid()::text and not private.is_evidence_photo(name)
             and (not private.chat_file_used(name) or private.am_deleting()))));

create or replace function public.begin_account_deletion()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '請先登入'; end if;
  if public.my_status() = 'suspended' then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  insert into private.account_deleting (uid) values (auth.uid()) on conflict on constraint account_deleting_pkey do update set at = now();
  perform set_config('halfsugar.deleting', '1', true);
  update public.profiles set hidden = true, avatar_path = null where id = uid;
  delete from public.photos where user_id = uid;
  delete from public.wealth_verifications where user_id = uid;
  delete from public.person_verifications where user_id = uid;
  if to_regclass('public.voice_intros') is not null then execute 'delete from public.voice_intros where user_id = $1' using uid; end if;
  perform set_config('halfsugar.deleting', '0', true);
end $$;

-- 刪帳號：檢舉證據的照片會留給管理員，不擋刪除
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '請先登入'; end if;
  if public.my_status() = 'suspended' then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  if exists (select 1 from storage.objects where bucket_id in ('photos','verify','person','chat','voice') and name like uid::text || '/%'
               and not (bucket_id = 'chat' and private.is_evidence_photo(name))) then
    raise exception '照片檔案還沒刪完，請再按一次刪除';
  end if;
  delete from public.photos where user_id = uid;
  delete from private.account_deleting d where d.uid = auth.uid();
  delete from auth.users where id = uid;
end $$;

-- v0.45：恢復原帳號時，先確認（不消耗），重設密碼信寄出成功後才用掉，寄失敗可以再按一次
create or replace function public.sms_recover_peek(uid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t uuid; em text; empty boolean;
begin
  select target into t from public.phone_recover where phone_recover.uid = sms_recover_peek.uid and expires_at > now();
  if t is null then return jsonb_build_object('r','expired'); end if;
  select email into em from auth.users where id = t;
  select coalesce(p.status, 'incomplete') = 'incomplete' and not coalesce(p.is_admin, false) and p.avatar_path is null
         and not exists (select 1 from public.photos ph where ph.user_id = sms_recover_peek.uid)
         and not exists (select 1 from auth.users u where u.id = sms_recover_peek.uid and nullif(u.phone,'') is not null)
    into empty from public.profiles p where p.id = sms_recover_peek.uid;
  return jsonb_build_object('r','ok','email',coalesce(em,''),'empty', coalesce(empty, false));
end $$;
revoke execute on function public.sms_recover_peek(uuid) from anon, authenticated, public;
grant execute on function public.sms_recover_peek(uuid) to service_role;

-- v0.46：用手機找回帳號（忘記當初用哪個 Email 註冊）
--   每支手機每 30 天最多 2 次，不佔註冊驗證的 3 次額度；IP、全站上限與暫停照常適用
--   沒註冊過的號碼不寄簡訊，畫面回應也一樣（不能拿來試探別人有沒有註冊）
alter table public.sms_sends add column if not exists kind text not null default 'verify';
alter table public.sms_sends add column if not exists used_at timestamptz;
create index if not exists sms_sends_kind_phone_idx on public.sms_sends(kind, phone_hash, created_at);

create or replace function public.sms_reserve(uid uuid, ph text, ip text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare h text := private.phone_hash(ph); ih text; nu int; np int; n int; rid bigint;
begin
  if uid is null or coalesce(ph,'') !~ '^\+?8869\d{8}$' then return jsonb_build_object('r','bad_phone'); end if;
  if coalesce((select value from public.app_config where key = 'sms_paused'), 'off') = 'on' then return jsonb_build_object('r','paused'); end if;
  perform pg_advisory_xact_lock(hashtext('sms_reserve'));
  if exists (select 1 from auth.users u where u.id = uid and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) then
    return jsonb_build_object('r','already');
  end if;
  if exists (select 1 from public.banned_phones b where b.phone_hash = h) then return jsonb_build_object('r','banned'); end if;
  select count(*) into nu from public.sms_sends where user_id = uid and voided_at is null and kind = 'verify';
  if nu >= 3 then return jsonb_build_object('r','user_limit'); end if;
  select count(*) into np from public.sms_sends where phone_hash = h and voided_at is null and kind = 'verify';
  if np >= 3 then return jsonb_build_object('r','phone_limit'); end if;
  ih := encode(digest('halfsugar-ip:' || coalesce(nullif(ip,''), 'unknown'), 'sha256'), 'hex');
  select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_ip_hour', 5) * (case when nullif(ip,'') is null then 4 else 1 end) then return jsonb_build_object('r','ip_limit'); end if;
  select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_ip_day', 10) * (case when nullif(ip,'') is null then 4 else 1 end) then return jsonb_build_object('r','ip_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_hour', 100) then return jsonb_build_object('r','global_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_day', 300) then return jsonb_build_object('r','global_limit'); end if;
  insert into public.sms_sends (user_id, phone_hash, ip_hash, kind) values (uid, h, ih, 'verify') returning id into rid;
  return jsonb_build_object('r','ok','id',rid,'left',2-nu);
end $$;
revoke execute on function public.sms_reserve(uuid, text, text) from anon, authenticated, public;
grant execute on function public.sms_reserve(uuid, text, text) to service_role;

-- 找回帳號：預留一次寄送。'none' = 沒有帳號或已達本號碼上限（兩者對外回應一樣）
create or replace function public.sms_find_reserve(ph text, ip text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare h text := private.phone_hash(ph); ih text; owner uuid; n int; rid bigint;
begin
  if coalesce(ph,'') !~ '^\+?8869\d{8}$' then return jsonb_build_object('r','bad_phone'); end if;
  if coalesce((select value from public.app_config where key = 'sms_paused'), 'off') = 'on' then return jsonb_build_object('r','paused'); end if;
  perform pg_advisory_xact_lock(hashtext('sms_reserve'));
  ih := encode(digest('halfsugar-ip:' || coalesce(nullif(ip,''), 'unknown'), 'sha256'), 'hex');
  select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_ip_hour', 5) * (case when nullif(ip,'') is null then 4 else 1 end) then return jsonb_build_object('r','ip_limit'); end if;
  select count(*) into n from public.sms_sends where ip_hash = ih and created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_ip_day', 10) * (case when nullif(ip,'') is null then 4 else 1 end) then return jsonb_build_object('r','ip_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 hour';
  if n >= private.cfg_int('sms_hour', 100) then return jsonb_build_object('r','global_limit'); end if;
  select count(*) into n from public.sms_sends where created_at > now() - interval '1 day';
  if n >= private.cfg_int('sms_day', 300) then return jsonb_build_object('r','global_limit'); end if;
  select u.id into owner from auth.users u
   where u.phone_confirmed_at is not null and nullif(u.phone,'') is not null and private.phone_hash(u.phone) = h limit 1;
  if owner is null then return jsonb_build_object('r','none'); end if;
  select count(*) into n from public.sms_sends where phone_hash = h and kind = 'find' and voided_at is null and created_at > now() - interval '30 days';
  if n >= 2 then return jsonb_build_object('r','none'); end if;
  insert into public.sms_sends (user_id, phone_hash, ip_hash, kind) values (owner, h, ih, 'find') returning id into rid;
  return jsonb_build_object('r','ok','id',rid);
end $$;
revoke execute on function public.sms_find_reserve(text, text) from anon, authenticated, public;
grant execute on function public.sms_find_reserve(text, text) to service_role;

-- 驗證碼正確後：確認 15 分鐘內有寄過找回簡訊（只能用一次），回傳這支手機帳號的 Email
create or replace function public.sms_find_take(ph text)
returns text language plpgsql security definer set search_path = public as $$
declare h text := private.phone_hash(ph); rid bigint; em text;
begin
  select id into rid from public.sms_sends
   where phone_hash = h and kind = 'find' and used_at is null and created_at > now() - interval '15 minutes'
   order by created_at desc limit 1 for update;
  if rid is null then return null; end if;
  update public.sms_sends set used_at = now() where id = rid;
  select u.email into em from auth.users u
   where u.phone_confirmed_at is not null and nullif(u.phone,'') is not null and private.phone_hash(u.phone) = h limit 1;
  return em;
end $$;
revoke execute on function public.sms_find_take(text) from anon, authenticated, public;
grant execute on function public.sms_find_take(text) to service_role;

create or replace function public.sms_check_ok(uid uuid, ph text)
returns text language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from auth.users u where u.id = uid and u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) then 'already'
    when not exists (select 1 from public.sms_sends s where s.user_id = uid and s.kind = 'verify' and s.phone_hash = private.phone_hash(ph) and s.created_at > now() - interval '15 minutes') then 'no_send'
    else 'ok' end;
$$;

create or replace function public.my_sms_left()
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, 3 - (select count(*)::int from public.sms_sends where user_id = auth.uid() and voided_at is null and kind = 'verify'));
$$;

create or replace function public.admin_sms_counts(ids uuid[])
returns table (id uuid, n int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return query select s.user_id, count(*)::int from public.sms_sends s where s.user_id = any(ids) and s.voided_at is null and s.kind = 'verify' group by s.user_id;
end $$;

-- =====================================================================
-- v0.47：模糊照
--   會員可以把相簿照片設成「模糊」：其他會員只拿得到模糊版（檔名加 b），
--   被授權看私密照的人才拿得到清楚的原圖。改成模糊時重新審核（審核員會同時看到兩張）。
-- =====================================================================
alter table public.photos add column if not exists blurred boolean not null default false;

create or replace function private.photo_blur_name(p text)
returns text language sql immutable as $$ select regexp_replace(p, '\.jpg$', 'b.jpg') $$;

create or replace function public.photos_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    new.user_id := auth.uid(); new.status := 'pending'; new.review_note := null; new.created_at := now();
    perform pg_advisory_xact_lock(hashtext('photos:' || auth.uid()::text));   -- 同時上傳多張時也不會超過上限
    if (select count(*) from public.photos where user_id = auth.uid()) >= 20 then raise exception '相簿最多 20 張'; end if;
    if new.blurred and not exists (select 1 from storage.objects where bucket_id = 'photos' and name = private.photo_blur_name(new.path)) then
      raise exception '模糊版照片還沒上傳完成，請再試一次';
    end if;
  else
    new.user_id := old.user_id; new.path := old.path; new.status := old.status;
    new.review_note := old.review_note; new.created_at := old.created_at;
    -- 私密照改成公開照：重新審核
    if old.is_private and not new.is_private then new.status := 'pending'; end if;
    -- 改成模糊照：模糊版要先上傳好，並重新審核
    if new.blurred and not old.blurred then
      if not exists (select 1 from storage.objects where bucket_id = 'photos' and name = private.photo_blur_name(old.path)) then
        raise exception '模糊版照片還沒上傳完成，請再試一次';
      end if;
      new.status := 'pending';
    end if;
  end if;
  return new;
end $$;

-- 數量上限：縮圖（t）與模糊版（b）都不算在 30 個檔案裡，另有各自的上限
create or replace function private.my_file_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'photos' and name like auth.uid()::text || '/%' and name !~ '[tb]\.jpg$';
$$;
create or replace function private.my_blur_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'photos' and name like auth.uid()::text || '/%' and name ~ 'b\.jpg$';
$$;
grant execute on function private.my_blur_count() to authenticated;
create or replace function private.photo_is_blurred(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.photos where path = p and blurred);
$$;
grant execute on function private.photo_is_blurred(text) to authenticated;

drop policy if exists "photos_storage_insert" on storage.objects;
create policy "photos_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos'
              and exists (select 1 from public.profiles where id = auth.uid() and status <> 'suspended')
              and (
                (name ~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$')
                 and private.my_file_count() < 30
                 and not private.photo_path_in_use(name))
                or (name ~ ('^' || auth.uid()::text || '/[0-9]+t\.jpg$')
                    and private.my_photo_file_exists(regexp_replace(name, 't\.jpg$', '.jpg'))
                    and not private.photo_path_in_use(regexp_replace(name, 't\.jpg$', '.jpg'))
                    and private.my_thumb_count() < 30)
                -- 模糊版（檔名加 b）：要對應自己已上傳的原圖；照片設成模糊之後就鎖住，不能換
                or (name ~ ('^' || auth.uid()::text || '/[0-9]+b\.jpg$')
                    and private.my_photo_file_exists(regexp_replace(name, 'b\.jpg$', '.jpg'))
                    and not private.photo_is_blurred(regexp_replace(name, 'b\.jpg$', '.jpg'))
                    and private.my_blur_count() < 30)
              ));

drop policy if exists "photos_storage_delete" on storage.objects;
create policy "photos_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (public.is_admin()
         or ((storage.foldername(name))[1] = auth.uid()::text and not private.photo_path_in_use(name)
             and not private.photo_path_in_use(regexp_replace(name, 't\.jpg$', '.jpg'))
             and not private.photo_is_blurred(regexp_replace(name, 'b\.jpg$', '.jpg')))));   -- 模糊照使用中的模糊版不能刪

-- 原圖：模糊照要被授權（photo_grants）才看得到
create or replace function private.can_see_photo(p_name text)
returns boolean language sql stable set search_path = public as $$
  select ((storage.foldername(p_name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (select 1 from public.profiles p
                 where ((p.avatar_path = p_name and p.status = 'approved')
                        or (p.approved_avatar_path = p_name and p.status = 'pending' and private.has_open_match(p.id)))
                   and (storage.foldername(p_name))[1] = p.id::text
                   and private.can_browse() and private.is_compatible(p.id)
                   and not private.is_blocked_with(p.id))
      or exists (select 1 from public.photos ph
                 where ph.path = p_name and ph.status = 'approved'
                   and (storage.foldername(p_name))[1] = ph.user_id::text
                   and exists (select 1 from public.profiles op where op.id = ph.user_id and (op.status = 'approved' or (op.status = 'pending' and private.has_open_match(op.id))))
                   and private.can_browse() and private.is_compatible(ph.user_id)
                   and not private.is_blocked_with(ph.user_id)
                   and ((not ph.is_private and not ph.blurred) or exists (select 1 from public.photo_grants g
                                                     where g.owner_id = ph.user_id and g.viewer_id = auth.uid())))
  );
$$;
-- 模糊版：看得到這張照片（列）的人都看得到模糊版
create or replace function private.can_see_blur(p_name text)
returns boolean language sql stable set search_path = public as $$
  select (storage.foldername(p_name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (select 1 from public.photos ph
                 where ph.path = regexp_replace(p_name, 'b\.jpg$', '.jpg') and ph.blurred and ph.status = 'approved'
                   and (storage.foldername(p_name))[1] = ph.user_id::text
                   and exists (select 1 from public.profiles op where op.id = ph.user_id and (op.status = 'approved' or (op.status = 'pending' and private.has_open_match(op.id))))
                   and private.can_browse() and private.is_compatible(ph.user_id)
                   and not private.is_blocked_with(ph.user_id)
                   and (not ph.is_private or exists (select 1 from public.photo_grants g where g.owner_id = ph.user_id and g.viewer_id = auth.uid())));
$$;
grant execute on function private.can_see_photo(text) to authenticated;
grant execute on function private.can_see_blur(text) to authenticated;
drop policy if exists "photos_storage_select" on storage.objects;
create policy "photos_storage_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'photos' and (
      (name !~ 'b\.jpg$' and private.can_see_photo(name))
      or (name ~ 't\.jpg$' and private.can_see_photo(regexp_replace(name, 't\.jpg$', '.jpg')))
      or (name ~ 'b\.jpg$' and private.can_see_blur(name))
    )
  );

-- ============ v0.48 星座、喝酒、抽菸、語言（皆選填，不需重新審核） ============
alter table public.profiles add column if not exists zodiac text
  check (zodiac in ('aries','taurus','gemini','cancer','leo','virgo','libra','scorpio','sagittarius','capricorn','aquarius','pisces'));
alter table public.profiles add column if not exists drink text check (drink in ('never','social','often'));
alter table public.profiles add column if not exists smoke text check (smoke in ('never','social','often'));
alter table public.profiles add column if not exists languages text[] not null default '{}'
  check (languages <@ array['zh','tw','hakka','cantonese','en','ja','ko','fr','de','es','th','vi']);
grant select (zodiac, drink, smoke, languages) on public.profiles to authenticated;

-- ============ v0.50 管理員待審數量（網站上顯示） ============

create or replace function public.admin_pending_counts()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return jsonb_build_object(
    'profiles', (select count(*) from profiles where status = 'pending'),
    'photos',   (select count(*) from photos where status = 'pending'),
    'person',   (select count(*) from person_verifications where status = 'pending'),
    'wealth',   (select count(*) from wealth_verifications where status = 'pending'),
    'reports',  (select count(*) from reports where status = 'open'),
    'support',  (select count(*) from support_tickets where status = 'open'));
end $$;
revoke execute on function public.admin_pending_counts() from public, anon;
grant execute on function public.admin_pending_counts() to authenticated;

-- ============ v0.51 會員 Email 通知（新訊息、新心動），會員可自行開關 ============
-- 每 10 分鐘檢查一次。只寄給「不在線上」的人；同一人最多每小時一封，信裡不放訊息內容。
-- 寄信用 Resend（與驗證信同一個網域 noreply@onethirdsugar.com）；金鑰放在 Supabase Vault，名稱 resend_api_key。
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
alter table public.profiles add column if not exists notify_email_msg  boolean not null default true;
alter table public.profiles add column if not exists notify_email_like boolean not null default true;

create table if not exists private.mail_config (
  id         int primary key default 1 check (id = 1),
  from_email text not null default '微糖 1/3 Sugar <noreply@onethirdsugar.com>',
  enabled    boolean not null default true
);
insert into private.mail_config (id) values (1) on conflict (id) do nothing;
revoke all on private.mail_config from public, anon, authenticated;

create table if not exists private.member_notify (
  user_id   uuid primary key references public.profiles(id) on delete cascade,
  last_at   timestamptz not null default now(),   -- 之後出現的訊息／心動才算新的
  last_sent timestamptz
);
revoke all on private.member_notify from public, anon, authenticated;
-- 上線時先把所有人的起點設成現在，避免一開就寄出舊通知
insert into private.member_notify (user_id) select id from public.profiles on conflict (user_id) do nothing;

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
    select p.id, u.email, x.msgs, x.likes from profiles p
      join auth.users u on u.id = p.id
      join private.member_notify mn on mn.user_id = p.id
      cross join lateral (select
        case when p.notify_email_msg then (select count(*) from messages m join matches mt on mt.id = m.match_id
              where (mt.user_a = p.id or mt.user_b = p.id) and m.sender_id <> p.id
                and m.read_at is null and m.recalled_at is null and m.created_at > mn.last_at) else 0 end as msgs,
        case when p.notify_email_like then (select count(*) from likes l
              where l.to_id = p.id and l.created_at > mn.last_at
                and not exists (select 1 from blocks b where (b.blocker_id = p.id and b.blocked_id = l.from_id) or (b.blocker_id = l.from_id and b.blocked_id = p.id))) else 0 end as likes) x
    where p.status = 'approved' and (p.notify_email_msg or p.notify_email_like)
      and u.email is not null and u.email <> ''
      and (p.last_active_at is null or p.last_active_at < t0 - interval '10 minutes')
      and (mn.last_sent is null or mn.last_sent < t0 - interval '1 hour')
      and (x.msgs > 0 or x.likes > 0)
    limit 80
  loop
    parts := array[]::text[];
    if r.msgs  > 0 then parts := parts || (r.msgs  || ' 則新訊息'); end if;
    if r.likes > 0 then parts := parts || (r.likes || ' 個人對你心動'); end if;
    html := '<div style="font-family:sans-serif;font-size:15px;line-height:1.8;color:#111;max-width:480px">'
      || '<p>你在微糖有 ' || array_to_string(parts, '、') || '。</p>'
      || '<p><a href="https://onethirdsugar.com/#/' || case when r.msgs > 0 then 'matches' else 'likes' end
      || '" style="display:inline-block;background:#111;color:#fff;padding:10px 22px;text-decoration:none">打開微糖查看</a></p>'
      || '<p style="font-size:12px;color:#777">不想收到這類通知？登入後到「我的 → 設定 → Email 通知」關閉。</p></div>';
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'),
      body := jsonb_build_object('from', cfg.from_email, 'to', jsonb_build_array(r.email),
                'subject', '你在微糖有新動態', 'html', html));
    update private.member_notify set last_at = t0, last_sent = t0 where user_id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function private.member_notify_run() from public, anon, authenticated;

select cron.unschedule('member-notify') where exists (select 1 from cron.job where jobname = 'member-notify');
select cron.schedule('member-notify', '*/10 * * * *', $$select private.member_notify_run()$$);

-- ============ v0.52 會員 Email 通知修正 ============
-- 1. 另記「最後在網站上的時間」（不受隱藏上線狀態影響），在線上的人不寄；在網站上看過的動態也不再補寄。
-- 2. 只寄給 Email 已驗證的會員；對話已結束、已封鎖、對方帳號不是正常狀態的都不算。
-- 3. 改成從「最近的新訊息／新心動」反查收件人，會員變多也不會變慢；每人每天最多 6 封。
alter table private.member_notify add column if not exists last_seen timestamptz;
alter table private.member_notify add column if not exists day_count int not null default 0;
alter table private.member_notify add column if not exists day_on date;
create index if not exists messages_created_idx on public.messages(created_at);
create index if not exists likes_created_idx on public.likes(created_at);
create index if not exists matches_user_b_idx on public.matches(user_b);

create or replace function public.touch_seen()
returns void language sql security definer set search_path = public, private as $$
  insert into private.member_notify as mn (user_id, last_at, last_seen) select auth.uid(), now(), now() where auth.uid() is not null
  on conflict (user_id) do update set last_seen = now(), last_at = greatest(mn.last_at, now());
$$;
revoke execute on function public.touch_seen() from public, anon;
grant execute on function public.touch_seen() to authenticated;

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
    html := '<div style="font-family:sans-serif;font-size:15px;line-height:1.8;color:#111;max-width:480px">'
      || '<p>你在微糖有 ' || array_to_string(parts, '、') || '。</p>'
      || '<p><a href="https://onethirdsugar.com/#/' || case when r.msgs > 0 then 'matches' else 'likes' end
      || '" style="display:inline-block;background:#111;color:#fff;padding:10px 22px;text-decoration:none">打開微糖查看</a></p>'
      || '<p style="font-size:12px;color:#777">不想收到這類通知？登入後到「我的 → 設定 → Email 通知」關閉。</p></div>';
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

-- ============ v0.53 誰看過我 ============
alter table public.profiles add column if not exists view_trace boolean not null default true;   -- 瀏覽時留下足跡

create table if not exists public.profile_views (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_id uuid not null references public.profiles(id) on delete cascade,
  last_at   timestamptz not null default now(),
  times     int not null default 1,
  primary key (viewer_id, viewed_id),
  check (viewer_id <> viewed_id)
);
create index if not exists profile_views_viewed_idx on public.profile_views(viewed_id, last_at desc);
alter table public.profile_views enable row level security;
revoke all on public.profile_views from anon, authenticated;
grant select on public.profile_views to authenticated;
drop policy if exists "views_own" on public.profile_views;
create policy "views_own" on public.profile_views for select to authenticated using (viewed_id = auth.uid());

-- 開啟別人的檔案時記錄；管理員、關閉足跡的人、未通過審核的人、有封鎖關係的都不記錄
create or replace function public.record_view(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null or p_id is null or v = p_id then return; end if;
  if not exists (select 1 from profiles where id = v and status = 'approved' and not is_admin and view_trace) then return; end if;
  if not exists (select 1 from profiles where id = p_id and status = 'approved') then return; end if;
  if exists (select 1 from blocks b where (b.blocker_id = v and b.blocked_id = p_id) or (b.blocker_id = p_id and b.blocked_id = v)) then return; end if;
  insert into profile_views as pv (viewer_id, viewed_id) values (v, p_id)
  on conflict (viewer_id, viewed_id) do update
    set times = pv.times + case when pv.last_at < now() - interval '30 minutes' then 1 else 0 end, last_at = now();
end $$;
revoke execute on function public.record_view(uuid) from public, anon;
grant execute on function public.record_view(uuid) to authenticated;
-- 封鎖時，雙方的瀏覽紀錄一併刪除
create or replace function private.blocks_clear_views()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from public.profile_views where (viewer_id = new.blocker_id and viewed_id = new.blocked_id) or (viewer_id = new.blocked_id and viewed_id = new.blocker_id);
  return new;
end $$;
drop trigger if exists blocks_clear_views on public.blocks;
create trigger blocks_clear_views after insert on public.blocks for each row execute function private.blocks_clear_views();

-- ============ v0.54 誰看過我：會員一律留下紀錄（只有管理員不留） ============
create or replace function public.record_view(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null or p_id is null or v = p_id then return; end if;
  if not exists (select 1 from profiles where id = v and status = 'approved' and not is_admin) then return; end if;
  if not exists (select 1 from profiles where id = p_id and status = 'approved') then return; end if;
  if exists (select 1 from blocks b where (b.blocker_id = v and b.blocked_id = p_id) or (b.blocker_id = p_id and b.blocked_id = v)) then return; end if;
  insert into profile_views as pv (viewer_id, viewed_id) values (v, p_id)
  on conflict (viewer_id, viewed_id) do update
    set times = pv.times + case when pv.last_at < now() - interval '30 minutes' then 1 else 0 end, last_at = now();
end $$;
update public.profiles set view_trace = true where not view_trace;
-- 管理員過去若有瀏覽紀錄，一併刪除
delete from public.profile_views v using public.profiles p where p.id = v.viewer_id and p.is_admin;

-- ============ v0.55 誰看過我：還沒通過審核的會員也留下紀錄 ============
create or replace function public.record_view(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null or p_id is null or v = p_id then return; end if;
  if not exists (select 1 from profiles where id = v and status <> 'suspended' and not is_admin) then return; end if;   -- 只有管理員、停權者不留
  if not exists (select 1 from profiles where id = p_id and status = 'approved') then return; end if;
  if exists (select 1 from blocks b where (b.blocker_id = v and b.blocked_id = p_id) or (b.blocker_id = p_id and b.blocked_id = v)) then return; end if;
  insert into profile_views as pv (viewer_id, viewed_id) values (v, p_id)
  on conflict (viewer_id, viewed_id) do update
    set times = pv.times + case when pv.last_at < now() - interval '30 minutes' then 1 else 0 end, last_at = now();
end $$;

-- 我的訪客清單：審核中的訪客只告訴你「有一位審核中的新會員」，不給名字和照片（還沒審過）
create or replace function public.my_viewers()
returns table (viewer_id uuid, last_at timestamptz, times int, approved boolean)
language sql stable security definer set search_path = public as $$
  select v.viewer_id, v.last_at, v.times, p.status = 'approved'
    from profile_views v join profiles p on p.id = v.viewer_id
   where v.viewed_id = auth.uid() and p.status <> 'suspended' and not p.is_admin
   order by v.last_at desc limit 100;
$$;
revoke execute on function public.my_viewers() from public, anon;
grant execute on function public.my_viewers() to authenticated;

-- ============ v0.56 誰看過我：修正 ============
-- 1. 只有「真的看得到對方」的會員才會留下紀錄（同樣套用探索的可見規則），避免直接呼叫 API 灌紀錄
-- 2. 30 分鐘內重複打開同一人只算一次，也不會讓紅點重新亮起
-- 3. 紀錄只能透過 RPC 讀取（不能直接查表，避免審核中訪客被對出身分）；紅點數字與清單用同一套規則
create or replace function public.record_view(p_id uuid)
returns void language plpgsql security definer set search_path = public, private as $$
declare v uuid := auth.uid();
begin
  if v is null or p_id is null or v = p_id then return; end if;
  if not private.can_browse() then return; end if;
  if exists (select 1 from profiles where id = v and is_admin) then return; end if;   -- 管理員不留紀錄
  if not exists (select 1 from profiles p where p.id = p_id and p.status = 'approved'
                 and private.is_compatible(p.id) and not private.is_blocked_with(p.id)
                 and (not p.hidden or exists (select 1 from likes l where l.from_id = p.id and l.to_id = v) or private.has_open_match(p.id))) then return; end if;
  insert into profile_views as pv (viewer_id, viewed_id) values (v, p_id)
  on conflict (viewer_id, viewed_id) do update
    set times = pv.times + 1, last_at = now()
    where pv.last_at < now() - interval '30 minutes';
end $$;

revoke select on public.profile_views from authenticated;
drop policy if exists "views_own" on public.profile_views;

create or replace function public.my_viewers()
returns table (viewer_id uuid, last_at timestamptz, times int, approved boolean)
language sql stable security definer set search_path = public as $$
  select v.viewer_id, v.last_at, v.times, p.status = 'approved'
    from profile_views v join profiles p on p.id = v.viewer_id
   where v.viewed_id = auth.uid() and p.status in ('approved','pending') and not p.is_admin
   order by v.last_at desc limit 100;
$$;

create or replace function public.my_viewers_count(p_since timestamptz)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from (
    select 1 from profile_views v join profiles p on p.id = v.viewer_id
     where v.viewed_id = auth.uid() and p.status in ('approved','pending') and not p.is_admin
       and v.last_at > coalesce(p_since, '-infinity')
     order by v.last_at desc limit 100) x;
$$;
revoke execute on function public.my_viewers_count(timestamptz) from public, anon;
grant execute on function public.my_viewers_count(timestamptz) to authenticated;

alter table public.profiles drop column if exists view_trace;

-- ============ v0.57 修正：審核中／被退件的會員刪帳號會卡住 ============
-- 上次通過的頭像（approved_avatar_path）也要清掉，照片檔案才刪得掉
create or replace function public.begin_account_deletion()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception '請先登入'; end if;
  if public.my_status() = 'suspended' then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  insert into private.account_deleting (uid) values (auth.uid()) on conflict on constraint account_deleting_pkey do update set at = now();
  perform set_config('halfsugar.deleting', '1', true);
  update public.profiles set hidden = true, avatar_path = null, approved_avatar_path = null where id = uid;
  delete from public.photos where user_id = uid;
  delete from public.wealth_verifications where user_id = uid;
  delete from public.person_verifications where user_id = uid;
  if to_regclass('public.voice_intros') is not null then execute 'delete from public.voice_intros where user_id = $1' using uid; end if;
  perform set_config('halfsugar.deleting', '0', true);
end $$;
