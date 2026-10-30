-- =====================================================================
-- 半糖 HALF SUGAR — Supabase 資料庫結構  (schema v0.2.0)
-- 在 Supabase Dashboard → SQL Editor 整段貼上執行（可重複執行）
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0. 共用：判斷目前登入者是否為管理員
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select is_admin from public.profiles where id = auth.uid()), false);
end $$;

-- ---------------------------------------------------------------------
-- 1. profiles  會員檔案（與 auth.users 一對一）
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  nickname        text,
  gender          text check (gender in ('male','female')),
  looking_for     text check (looking_for in ('male','female','any')),
  role            text check (role in ('daddy','mommy','baby')),   -- Sugar Daddy / Sugar Mommy / 甜心
  birth_year      int  check (birth_year between 1900 and 2100),
  city            text,
  height_cm       int  check (height_cm between 100 and 250),
  occupation      text,
  bio             text,
  tags            text[] default '{}',
  avatar_path     text,                                  -- storage 路徑（photos bucket）
  status          text not null default 'incomplete'
                  check (status in ('incomplete','pending','approved','rejected','suspended')),
  review_note     text,                                  -- 管理員退件原因
  is_admin        boolean not null default false,
  agreed_terms_at timestamptz,
  age_confirmed   boolean not null default false,
  last_active_at  timestamptz default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists profiles_browse_idx on public.profiles(status, gender, city, last_active_at desc);
alter table public.profiles add column if not exists role text check (role in ('daddy','mommy','baby'));

-- 新使用者註冊時自動建立 profile
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- 一般會員不得自行改 status / is_admin / review_note；改了資料就退回待審
create or replace function public.profiles_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare admin boolean := public.is_admin();
begin
  new.updated_at := now();
  if not admin then
    new.is_admin    := old.is_admin;
    new.review_note := old.review_note;
    -- 停權者不可自行解除
    if old.status = 'suspended' then
      new.status := 'suspended';
      return new;
    end if;
    -- 公開欄位有變動 → 退回待審
    if (new.nickname, new.bio, new.avatar_path, new.occupation, new.tags, new.role)
       is distinct from (old.nickname, old.bio, old.avatar_path, old.occupation, old.tags, old.role) then
      new.status := 'pending';
    else
      new.status := old.status;
    end if;
    -- 首次送審：資料齊全才能從 incomplete 進 pending
    if old.status = 'incomplete' and new.nickname is not null and new.gender is not null
       and new.birth_year is not null and new.city is not null and new.avatar_path is not null
       and new.role is not null and new.age_confirmed and new.agreed_terms_at is not null then
      new.status := 'pending';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard_trg on public.profiles;
create trigger profiles_guard_trg before update on public.profiles
  for each row execute function public.profiles_guard();

-- ---------------------------------------------------------------------
-- 2. photos  相簿（公開照 / 私密照）
-- ---------------------------------------------------------------------
create table if not exists public.photos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  path        text not null unique,                      -- storage 路徑 user_id/xxx.jpg
  is_private  boolean not null default false,
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_note text,
  created_at  timestamptz not null default now()
);
create index if not exists photos_user_idx on public.photos(user_id, status);

create or replace function public.photos_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.status      := old.status;       -- 一般會員不能自己改審核狀態
    new.review_note := old.review_note;
  end if;
  return new;
end $$;
drop trigger if exists photos_guard_trg on public.photos;
create trigger photos_guard_trg before update on public.photos
  for each row execute function public.photos_guard();

-- 私密照授權：owner 允許 viewer 看
create table if not exists public.photo_grants (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, viewer_id)
);

-- 私密照索取
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

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;

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
  unique (user_a, user_b),
  check (user_a < user_b)
);

-- 互相按讚 → 自動建立 match
create or replace function public.handle_like()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.likes where from_id = new.to_id and to_id = new.from_id) then
    insert into public.matches (user_a, user_b)
    values (least(new.from_id, new.to_id), greatest(new.from_id, new.to_id))
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists likes_match_trg on public.likes;
create trigger likes_match_trg after insert on public.likes
  for each row execute function public.handle_like();

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
  update public.matches
     set last_message_at = new.created_at,
         last_message    = left(new.body, 80)
   where id = new.match_id;
  return new;
end $$;
drop trigger if exists messages_after_trg on public.messages;
create trigger messages_after_trg after insert on public.messages
  for each row execute function public.handle_message();

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

-- profiles
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select to authenticated
  using (
    id = auth.uid() or public.is_admin()
    or (status = 'approved' and not public.is_blocked_between(id, auth.uid()))
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
    or (status = 'approved' and not public.is_blocked_between(user_id, auth.uid())
        and (not is_private or exists (select 1 from public.photo_grants g
                                       where g.owner_id = user_id and g.viewer_id = auth.uid())))
  );
drop policy if exists "photos_insert_own" on public.photos;
create policy "photos_insert_own" on public.photos for insert to authenticated
  with check (user_id = auth.uid() and path like auth.uid()::text || '/%');
drop policy if exists "photos_update" on public.photos;
create policy "photos_update" on public.photos for update to authenticated
  using (user_id = auth.uid() or public.is_admin());
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
  with check (requester_id = auth.uid());
drop policy if exists "requests_update_owner" on public.photo_requests;
create policy "requests_update_owner" on public.photo_requests for update to authenticated
  using (owner_id = auth.uid());

-- blocks
drop policy if exists "blocks_rw" on public.blocks;
create policy "blocks_rw" on public.blocks for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- likes
drop policy if exists "likes_select" on public.likes;
create policy "likes_select" on public.likes for select to authenticated
  using (from_id = auth.uid() or to_id = auth.uid());
drop policy if exists "likes_insert" on public.likes;
create policy "likes_insert" on public.likes for insert to authenticated
  with check (
    from_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'approved')
    and exists (select 1 from public.profiles p where p.id = to_id and p.status = 'approved')
    and not public.is_blocked_between(from_id, to_id)
  );
drop policy if exists "likes_delete" on public.likes;
create policy "likes_delete" on public.likes for delete to authenticated
  using (from_id = auth.uid());

-- matches
drop policy if exists "matches_select" on public.matches;
create policy "matches_select" on public.matches for select to authenticated
  using (user_a = auth.uid() or user_b = auth.uid() or public.is_admin());
drop policy if exists "matches_delete" on public.matches;
create policy "matches_delete" on public.matches for delete to authenticated
  using (user_a = auth.uid() or user_b = auth.uid());

-- messages
drop policy if exists "messages_select" on public.messages;
create policy "messages_select" on public.messages for select to authenticated
  using (exists (select 1 from public.matches m where m.id = match_id
                 and (m.user_a = auth.uid() or m.user_b = auth.uid())) or public.is_admin());
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (select 1 from public.matches m where m.id = match_id
                and (m.user_a = auth.uid() or m.user_b = auth.uid())
                and not public.is_blocked_between(m.user_a, m.user_b))
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'approved')
  );
drop policy if exists "messages_update_read" on public.messages;
create policy "messages_update_read" on public.messages for update to authenticated
  using (exists (select 1 from public.matches m where m.id = match_id
                 and (m.user_a = auth.uid() or m.user_b = auth.uid())));

-- reports
drop policy if exists "reports_insert" on public.reports;
create policy "reports_insert" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid());
drop policy if exists "reports_select" on public.reports;
create policy "reports_select" on public.reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());
drop policy if exists "reports_update_admin" on public.reports;
create policy "reports_update_admin" on public.reports for update to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- 6. Storage  photos bucket（私有，前端用 signed URL 讀取）
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "photos_storage_insert" on storage.objects;
create policy "photos_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photos_storage_delete" on storage.objects;
create policy "photos_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

drop policy if exists "photos_storage_select" on storage.objects;
create policy "photos_storage_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'photos' and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
      -- 頭像：檔案主人已通過審核即可看
      or exists (select 1 from public.profiles p
                 where p.avatar_path = name and p.status = 'approved'
                   and not public.is_blocked_between(p.id, auth.uid()))
      -- 相簿：照片已審核；私密照需授權
      or exists (select 1 from public.photos ph
                 where ph.path = name and ph.status = 'approved'
                   and not public.is_blocked_between(ph.user_id, auth.uid())
                   and (not ph.is_private or exists (select 1 from public.photo_grants g
                                                     where g.owner_id = ph.user_id and g.viewer_id = auth.uid())))
    )
  );

-- ---------------------------------------------------------------------
-- 7. Realtime：讓前端能訂閱 messages 新增
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 8. 管理員：註冊完成後，把你的帳號設成管理員（把 email 換掉）
-- ---------------------------------------------------------------------
-- update public.profiles set is_admin = true, status = 'approved'
--  where id = (select id from auth.users where email = 'you@example.com');
