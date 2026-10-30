-- =====================================================================
-- 半糖 HALF SUGAR — Supabase 資料庫結構  (schema v0.14.0)
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
alter table public.profiles add column if not exists submitted_at timestamptz;   -- 最近一次送審時間（待審名單排序用）
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
  new.created_at  := old.created_at;
  if new.last_active_at is not null then new.last_active_at := least(new.last_active_at, now()); end if;
  -- 性別與想認識的對象：第一次設定後不可更改
  if old.gender is not null then new.gender := old.gender; end if;
  if old.looking_for is not null then new.looking_for := old.looking_for; end if;
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
    if new.nickname is not null and new.gender is not null and new.looking_for is not null and new.role is not null
       and new.birth_year is not null and new.city is not null and new.avatar_path is not null
       and new.age_confirmed and new.agreed_terms_at is not null
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
returns trigger language plpgsql as $$
begin
  if new.status = 'pending' and old.status is distinct from 'pending' then new.submitted_at := now(); end if;
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
    if (select count(*) from public.photos where user_id = auth.uid()) >= 9 then raise exception '相簿最多 9 張'; end if;
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
  update public.matches set closed_at = now() where user_a = a and user_b = b and closed_at is null;
  delete from public.likes where (from_id = a and to_id = b) or (from_id = b and to_id = a);
  delete from public.photo_grants where (owner_id = a and viewer_id = b) or (owner_id = b and viewer_id = a);
  delete from public.photo_requests where (requester_id = a and owner_id = b) or (requester_id = b and owner_id = a);
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


-- 解除配對：關閉對話並清掉雙方的喜歡（要重新互相喜歡才會再配對）
create or replace function public.unmatch(mid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m public.matches;
begin
  select * into m from public.matches where id = mid and (user_a = auth.uid() or user_b = auth.uid());
  if not found then raise exception '找不到這個配對'; end if;
  update public.matches set closed_at = now() where id = mid;
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

create or replace function public.handle_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.matches set last_message_at = new.created_at, last_message = left(new.body, 80)
   where id = new.match_id;
  return new;
end $$;
drop trigger if exists messages_after_trg on public.messages;
create trigger messages_after_trg after insert on public.messages
  for each row execute function public.handle_message();

-- 訊息：時間由伺服器決定；之後只能標記已讀，內容與寄件人不得修改
create or replace function public.messages_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    new.created_at := now(); new.read_at := null;
  else
    new.body := old.body; new.sender_id := old.sender_id; new.match_id := old.match_id; new.created_at := old.created_at;
    if old.sender_id = auth.uid() then new.read_at := old.read_at; end if;
  end if;
  return new;
end $$;
drop trigger if exists messages_guard_trg on public.messages;
create trigger messages_guard_trg before insert or update on public.messages
  for each row execute function public.messages_guard();

-- 我和某人之間是否有未解除的配對
create or replace function private.has_open_match(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.matches m where m.closed_at is null
                 and m.user_a = least(auth.uid(), other) and m.user_b = greatest(auth.uid(), other));
$$;

-- 主動開啟的一方，在對方回覆前只能先傳一則
create or replace function private.can_send(mid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select m.initiator is distinct from auth.uid()
        or exists (select 1 from public.messages x where x.match_id = m.id and x.sender_id <> auth.uid()
                     and (m.reopened_at is null or x.created_at >= m.reopened_at))
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
  select case when private.is_blocked_with(uid) or public.my_status() not in ('pending','approved')
              or not private.is_compatible(uid)
              or not exists (select 1 from public.profiles where id = uid and status = 'approved') then 0
         else (select count(*)::int from public.photos where user_id = uid and is_private and status = 'approved') end;
$$;

revoke execute on function public.private_photo_count(uuid) from anon, public;
grant execute on function public.private_photo_count(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. reports  檢舉
-- ---------------------------------------------------------------------
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
    or (public.my_status() in ('pending','approved')
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
    or (status = 'approved' and public.my_status() in ('pending','approved')
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
  with check (owner_id = auth.uid());
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
  using (((user_a = auth.uid() or user_b = auth.uid()) and closed_at is null) or public.is_admin());
drop policy if exists "matches_delete" on public.matches;

-- messages
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select to authenticated
  using (exists (select 1 from public.matches m where m.id = match_id and m.closed_at is null
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
drop policy if exists "messages_update_read" on public.messages;
create policy "messages_update_read" on public.messages for update to authenticated
  using (sender_id <> auth.uid() and exists (select 1 from public.matches m where m.id = match_id
                 and (m.user_a = auth.uid() or m.user_b = auth.uid())));

-- reports
drop policy if exists "reports_insert" on public.reports;
create policy "reports_insert" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and status = 'open' and public.my_status() in ('pending','approved','rejected'));
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

-- 檔名是否已登記為照片或頭像（登記後檔案不能刪除再用同檔名重傳）
create or replace function private.photo_path_in_use(p text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.photos where path = p)
      or exists (select 1 from public.profiles where avatar_path = p);
$$;

create or replace function private.my_file_count()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from storage.objects where bucket_id = 'photos' and name like auth.uid()::text || '/%';
$$;

drop policy if exists "photos_storage_insert" on storage.objects;
create policy "photos_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and name ~ ('^' || auth.uid()::text || '/[0-9]+\.jpg$')
              and exists (select 1 from public.profiles where id = auth.uid() and status <> 'suspended')
              and private.my_file_count() < 15            -- 每人最多 15 個檔案（相簿 9 + 頭像與更換的餘裕）
              and not private.photo_path_in_use(name));   -- 不可用同檔名覆蓋已登記的照片

drop policy if exists "photos_storage_delete" on storage.objects;
create policy "photos_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (public.is_admin()
         or ((storage.foldername(name))[1] = auth.uid()::text and not private.photo_path_in_use(name))));

drop policy if exists "photos_storage_select" on storage.objects;
create policy "photos_storage_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'photos' and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (select 1 from public.profiles p
                 where p.avatar_path = name and p.status = 'approved'
                   and (storage.foldername(name))[1] = p.id::text
                   and not private.is_blocked_with(p.id))
      or exists (select 1 from public.photos ph
                 where ph.path = name and ph.status = 'approved'
                   and (storage.foldername(name))[1] = ph.user_id::text
                   and not private.is_blocked_with(ph.user_id)
                   and (not ph.is_private or exists (select 1 from public.photo_grants g
                                                     where g.owner_id = ph.user_id and g.viewer_id = auth.uid())))
    )
  );

-- 索取私密照（被婉拒後 3 天才能再問）
create or replace function public.request_private_photos(owner uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.photo_requests;
begin
  if public.my_status() <> 'approved' then raise exception '資料審核通過後才能索取'; end if;
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
       or exists (select 1 from public.photo_requests where owner_id = auth.uid() and requester_id = p.id));
$$;

-- 欄位權限：其他會員只讀得到公開欄位；是否為管理員、退件原因、上線設定、同意紀錄等只有本人與管理員看得到
revoke select on public.profiles from anon, authenticated;
grant select (id, nickname, gender, looking_for, role, birth_year, city, height_cm, occupation, bio, tags,
              avatar_path, status, hidden, last_active_at, created_at, updated_at) on public.profiles to authenticated;

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
create or replace function public.my_start_quota()
returns int language plpgsql stable security definer set search_path = public as $$
declare total int; today_n int; today timestamptz;
begin
  if auth.uid() is null then return 0; end if;
  today := (date_trunc('day', now() at time zone 'Asia/Taipei')) at time zone 'Asia/Taipei';
  select count(*), count(*) filter (where created_at >= today) into total, today_n
    from public.conversation_starts where user_id = auth.uid();
  if total < 10 then return 10 - total; end if;
  return greatest(0, 1 - today_n);
end $$;
revoke execute on function public.my_start_quota() from anon, public;
grant execute on function public.my_start_quota() to authenticated;

-- 傳第一則訊息（直接開啟對話）
create or replace function public.send_first_message(other uuid, body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m public.matches; mid uuid;
begin
  if me is null then raise exception '請先登入'; end if;
  if public.my_status() <> 'approved' then raise exception '檔案審核通過後才能傳訊息'; end if;
  if other = me then raise exception '不能傳訊息給自己'; end if;
  if body is null or char_length(trim(body)) = 0 or char_length(body) > 2000 then raise exception '訊息長度不正確'; end if;
  if private.is_blocked_with(other) or not private.is_compatible(other)
     or not exists (select 1 from public.profiles p where p.id = other and p.status = 'approved'
                    and (not p.hidden or exists (select 1 from public.likes l where l.from_id = other and l.to_id = me))) then
    raise exception '無法傳訊息給這位會員';
  end if;
  select * into m from public.matches where user_a = least(me, other) and user_b = greatest(me, other);
  if found and m.closed_at is null then
    -- 已有對話：照一般規則傳
    if not private.can_send(m.id) then raise exception '對方回覆後才能繼續傳訊息'; end if;
    insert into public.messages (match_id, sender_id, body) values (m.id, me, body);
    return m.id;
  end if;
  if public.my_start_quota() <= 0 then
    raise exception '前 10 個新對話已經用完，之後每天可以再開啟 1 個，明天再來吧';
  end if;
  insert into public.conversation_starts (user_id) values (me);
  if found then
    update public.matches set closed_at = null, reopened_at = now(), initiator = me, last_message = null, last_message_at = null
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
  if public.my_status() = 'suspended'
     or exists (select 1 from public.reports where reported_id = uid and status = 'open') then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  perform set_config('halfsugar.deleting', '1', true);
  update public.profiles set hidden = true, avatar_path = null where id = uid;
  delete from public.photos where user_id = uid;
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
  if public.my_status() = 'suspended'
     or exists (select 1 from public.reports where reported_id = uid and status = 'open') then
    raise exception '你的帳號有待處理的事項，暫時無法自行刪除。如有疑問請聯絡客服。';
  end if;
  if exists (select 1 from storage.objects where bucket_id = 'photos' and name like uid::text || '/%') then
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

create or replace function public.handle_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.report_evidence (report_id, sender_id, body, created_at)
  select new.id, x.sender_id, x.body, x.created_at from (
    select ms.sender_id, ms.body, ms.created_at from public.messages ms
      join public.matches m on m.id = ms.match_id
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

-- 管理員刪除帳號（用於已停權帳號）：手機若在黑名單中仍保留指紋，之後不能再註冊
create or replace function public.admin_delete_account(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  if target = auth.uid() then raise exception '不能刪除自己的管理員帳號'; end if;
  if exists (select 1 from storage.objects where bucket_id = 'photos' and name like target::text || '/%') then
    raise exception '這位會員的照片檔案還沒刪完';
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
