
-- ============ v0.68 討論區 ============
-- 只有通過審核的會員看得到、發得了文。每篇文、每則留言都可以選：0 顯示暱稱、1 匿名但顯示身分、2 完全匿名。
-- 匿名是真的匿名：資料表不開放直接查詢，只能透過下面的函式讀，回傳的資料裡沒有匿名作者的代號；只有管理員處理檢舉時看得到。
-- 同一篇裡，匿名留言的人依第一次出現的順序編號（匿名 1、匿名 2…），原作者在自己的文章下一律標「原PO」、身分跟文章一致。
create table if not exists public.forum_posts (
  id               bigint generated always as identity primary key,
  author_id        uuid not null references public.profiles(id) on delete cascade,
  board            text not null check (board in ('date','qa','safety','chat')),
  title            text not null check (char_length(title) between 2 and 40),
  body             text not null check (char_length(body) between 5 and 2000),
  anon             smallint not null default 0 check (anon in (0,1,2)),
  author_role      text,                                   -- 發文當下的身分（匿名但顯示身分用）
  created_at       timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  hidden           boolean not null default false,         -- 被 3 人檢舉自動隱藏，或管理員下架
  removed_at       timestamptz                             -- 管理員下架（保留內容當證據）
);
create index if not exists forum_posts_board_idx on public.forum_posts (board, last_activity_at desc);
create index if not exists forum_posts_new_idx on public.forum_posts (last_activity_at desc);
create index if not exists forum_posts_author_idx on public.forum_posts (author_id);

create table if not exists public.forum_comments (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.forum_posts(id) on delete cascade,
  author_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 500),
  anon        smallint not null default 0 check (anon in (0,1,2)),
  author_role text,
  anon_no     int,                                         -- 這篇裡的匿名編號（原PO 不編號）
  created_at  timestamptz not null default now(),
  hidden      boolean not null default false,
  removed_at  timestamptz
);
create index if not exists forum_comments_post_idx on public.forum_comments (post_id, id);
create index if not exists forum_comments_author_idx on public.forum_comments (author_id);

create table if not exists public.forum_likes (
  post_id    bigint not null references public.forum_posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.forum_reports (
  id          bigint generated always as identity primary key,
  reporter_id uuid references public.profiles(id) on delete set null,
  post_id     bigint references public.forum_posts(id) on delete cascade,
  comment_id  bigint references public.forum_comments(id) on delete cascade,
  reason      text not null check (reason in ('money','adult_industry','contact','harass','privacy','spam','other')),
  detail      text check (detail is null or char_length(detail) <= 200),
  status      text not null default 'open' check (status in ('open','resolved','dismissed')),
  created_at  timestamptz not null default now(),
  check ((post_id is null) <> (comment_id is null))
);
create unique index if not exists forum_reports_once on public.forum_reports (reporter_id, coalesce(post_id, 0), coalesce(comment_id, 0));
create index if not exists forum_reports_open_idx on public.forum_reports (status, created_at desc);

alter table public.forum_posts enable row level security;
alter table public.forum_comments enable row level security;
alter table public.forum_likes enable row level security;
alter table public.forum_reports enable row level security;
revoke all on public.forum_posts, public.forum_comments, public.forum_likes, public.forum_reports from anon, authenticated;

-- 發文內容檢查：敏感字（跟自介同一份）＋不能留聯絡方式或網址（要認識請用站內的心動與訊息）
create or replace function private.forum_check(t text)
returns void language plpgsql immutable set search_path = public as $$
declare b text; l text := lower(coalesce(t, ''));
begin
  b := private.bad_words(t, false);
  if b is not null then raise exception '內容含不允許的字眼：%', b; end if;
  if l ~ '(https?://|www\.|[a-z0-9-]+\.(com|tw|net|org|me|cc|io|co|app|link|ly)\y)' then
    raise exception '討論區不能貼網址';
  end if;
  if regexp_replace(l, '[\s\-\.()（）]', '', 'g') ~ '(\+?886|0)9\d{8}' then
    raise exception '討論區不能留電話號碼';
  end if;
  if l ~ '(line|賴|ｌｉｎｅ|ig|instagram|telegram|tg|wechat|微信|微訊)\s*(id)?\s*[:：@＠]\s*[a-z0-9_.\-]{3,}' or l ~ '加\s*(line|賴|ig|微信)' or l ~ '(^|\s)[@＠][a-z0-9_.]{3,}' then
    raise exception '討論區不能留聯絡方式，想認識對方請用站內的心動與訊息';
  end if;
end $$;
revoke all on function private.forum_check(text) from public, anon, authenticated;

-- 身分顯示文字
create or replace function private.forum_role_label(r text)
returns text language sql immutable as $$
  select case r when 'daddy' then 'Sugar Daddy' when 'mommy' then 'Sugar Mommy' when 'baby' then '甜心' else null end;
$$;
revoke all on function private.forum_role_label(text) from public, anon, authenticated;

-- 這位作者的內容我看不看得到：停權的人全部不顯示；顯示暱稱的內容，有封鎖關係的雙方互相看不到
create or replace function private.forum_author_ok(author uuid, anon smallint)
returns boolean language sql stable security definer set search_path = public as $$
  select author = auth.uid() or public.is_admin()
      or (exists (select 1 from public.profiles p where p.id = author and p.status <> 'suspended')
          and (anon > 0 or not private.is_blocked_with(author)));
$$;
revoke all on function private.forum_author_ok(uuid, smallint) from public, anon, authenticated;

create or replace function private.forum_can_read()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or private.can_browse();
$$;
revoke all on function private.forum_can_read() from public, anon, authenticated;

-- 一篇文章給前端的樣子（不含匿名作者的代號）
create or replace function private.forum_post_json(p public.forum_posts, full_body boolean)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'board', p.board, 'title', p.title,
    'body', case when full_body then p.body else left(p.body, 140) end,
    'anon', p.anon,
    'name', case when p.anon = 0 then coalesce(pr.nickname, '會員') else '匿名' end,
    'role', case when p.anon < 2 then private.forum_role_label(case when p.anon = 0 then pr.role else p.author_role end) end,
    'author_id', case when p.anon = 0 and private.profile_visible(p.author_id) then p.author_id end,
    'mine', p.author_id = auth.uid(),
    'liked', exists (select 1 from public.forum_likes l where l.post_id = p.id and l.user_id = auth.uid()),
    'likes', (select count(*) from public.forum_likes l where l.post_id = p.id),
    'comments', (select count(*) from public.forum_comments c where c.post_id = p.id and c.removed_at is null and not c.hidden
                   and private.forum_author_ok(c.author_id, case when c.author_id = p.author_id then p.anon else c.anon end)),
    'created_at', p.created_at, 'last_activity_at', p.last_activity_at,
    'hidden', case when p.author_id = auth.uid() or public.is_admin() then p.hidden or p.removed_at is not null end
  ) || case when public.is_admin() then jsonb_build_object('real_author_id', p.author_id, 'real_name', pr.nickname,
                                                          'reports', (select count(*) from public.forum_reports r where r.post_id = p.id and r.status = 'open'))
            else '{}'::jsonb end
    from public.profiles pr where pr.id = p.author_id;
$$;
revoke all on function private.forum_post_json(public.forum_posts, boolean) from public, anon, authenticated;

-- 文章列表：board 不給 = 全部；sort = 'new'（最新回應）或 'hot'（近 7 天按讚＋留言多）；before = 上一頁最後一篇的時間；mine = 只看我發的
create or replace function public.forum_list(p_board text default null, p_sort text default 'new', p_before timestamptz default null, p_limit int default 20, p_mine boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if auth.uid() is null or not private.forum_can_read() then raise exception '檔案審核通過後才能使用討論區'; end if;
  select coalesce(jsonb_agg(private.forum_post_json(x.pp, false) order by x.ord desc, (x.pp).last_activity_at desc), '[]'::jsonb) into res
    from (select p as pp, case when p_sort = 'hot'
                           then (select count(*) from public.forum_likes l where l.post_id = p.id) * 2
                              + (select count(*) from public.forum_comments c where c.post_id = p.id and c.removed_at is null and not c.hidden)
                           else 0 end as ord
            from public.forum_posts p
           where (p_board is null or p.board = p_board)
             and (case when p_mine then p.author_id = auth.uid()
                       else p.removed_at is null and (not p.hidden or p.author_id = auth.uid())
                            and private.forum_author_ok(p.author_id, p.anon) end)
             and (p_sort <> 'hot' or p.created_at > now() - interval '7 days')
             and (p_before is null or p.last_activity_at < p_before)
           order by 2 desc, p.last_activity_at desc
           limit least(greatest(coalesce(p_limit, 20), 1), 50)) x;
  return res;
end $$;
revoke execute on function public.forum_list(text, text, timestamptz, int, boolean) from anon, public;
grant execute on function public.forum_list(text, text, timestamptz, int, boolean) to authenticated;

-- 單篇文章＋留言
create or replace function public.forum_get(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.forum_posts; cs jsonb; adm boolean := public.is_admin();
begin
  if auth.uid() is null or not private.forum_can_read() then raise exception '檔案審核通過後才能使用討論區'; end if;
  select * into p from public.forum_posts where id = p_id;
  if p.id is null or (not adm and p.author_id <> auth.uid()
                      and (p.removed_at is not null or p.hidden or not private.forum_author_ok(p.author_id, p.anon))) then
    raise exception '這篇文章已經不在了';
  end if;
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', c.id, 'body', c.body,
             'op', c.author_id = p.author_id,
             'anon', case when c.author_id = p.author_id then p.anon else c.anon end,
             'name', case when c.author_id = p.author_id then (case when p.anon = 0 then coalesce(pr.nickname, '會員') else '匿名' end)
                          when c.anon = 0 then coalesce(pr.nickname, '會員')
                          else '匿名 ' || c.anon_no end,
             'role', case when c.author_id = p.author_id then (case when p.anon < 2 then private.forum_role_label(case when p.anon = 0 then pr.role else p.author_role end) end)
                          when c.anon < 2 then private.forum_role_label(case when c.anon = 0 then pr.role else c.author_role end) end,
             'author_id', case when (case when c.author_id = p.author_id then p.anon else c.anon end) = 0 and private.profile_visible(c.author_id) then c.author_id end,
             'mine', c.author_id = auth.uid(),
             'created_at', c.created_at,
             'hidden', case when c.author_id = auth.uid() or adm then c.hidden or c.removed_at is not null end
           ) || case when adm then jsonb_build_object('real_author_id', c.author_id, 'real_name', pr.nickname,
                                                     'reports', (select count(*) from public.forum_reports r where r.comment_id = c.id and r.status = 'open'))
                     else '{}'::jsonb end
           order by c.id), '[]'::jsonb) into cs
    from public.forum_comments c join public.profiles pr on pr.id = c.author_id
   where c.post_id = p.id
     and (adm or c.author_id = auth.uid()
          or (c.removed_at is null and not c.hidden
              and private.forum_author_ok(c.author_id, case when c.author_id = p.author_id then p.anon else c.anon end)));
  return jsonb_build_object('post', private.forum_post_json(p, true), 'comments', cs);
end $$;
revoke execute on function public.forum_get(bigint) from anon, public;
grant execute on function public.forum_get(bigint) to authenticated;

-- 發文
create or replace function public.forum_post(p_board text, p_title text, p_body text, p_anon smallint)
returns bigint language plpgsql security definer set search_path = public as $$
declare nid bigint; r text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.my_status() <> 'approved' and not public.is_admin() then raise exception '檔案審核通過後才能發文'; end if;
  if p_anon not in (0,1,2) then raise exception '請選擇發文身分'; end if;
  p_title := btrim(coalesce(p_title, '')); p_body := btrim(coalesce(p_body, ''));
  if char_length(p_title) < 2 or char_length(p_title) > 40 then raise exception '標題請寫 2 到 40 字'; end if;
  if char_length(p_body) < 5 or char_length(p_body) > 2000 then raise exception '內文請寫 5 到 2000 字'; end if;
  if not public.is_admin() then
    perform private.forum_check(p_title || ' ' || p_body);
    if (select count(*) from public.forum_posts where author_id = auth.uid() and created_at > now() - interval '1 day') >= 3 then
      raise exception '一天最多發 3 篇文，明天再來';
    end if;
  end if;
  select role into r from public.profiles where id = auth.uid();
  insert into public.forum_posts (author_id, board, title, body, anon, author_role)
  values (auth.uid(), p_board, p_title, p_body, p_anon, r) returning id into nid;
  return nid;
end $$;
revoke execute on function public.forum_post(text, text, text, smallint) from anon, public;
grant execute on function public.forum_post(text, text, text, smallint) to authenticated;

-- 留言
create or replace function public.forum_comment(p_post bigint, p_body text, p_anon smallint)
returns bigint language plpgsql security definer set search_path = public as $$
declare p public.forum_posts; nid bigint; n int; r text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.my_status() <> 'approved' and not public.is_admin() then raise exception '檔案審核通過後才能留言'; end if;
  if p_anon not in (0,1,2) then raise exception '請選擇留言身分'; end if;
  p_body := btrim(coalesce(p_body, ''));
  if char_length(p_body) < 1 or char_length(p_body) > 500 then raise exception '留言請寫 1 到 500 字'; end if;
  select * into p from public.forum_posts where id = p_post for update;
  if p.id is null or p.removed_at is not null or (p.hidden and p.author_id <> auth.uid())
     or not private.forum_author_ok(p.author_id, p.anon) then raise exception '這篇文章已經不在了'; end if;
  if not public.is_admin() then
    perform private.forum_check(p_body);
    if (select count(*) from public.forum_comments where author_id = auth.uid() and created_at > now() - interval '1 day') >= 50 then
      raise exception '今天留言太多了，明天再來';
    end if;
  end if;
  if p.author_id = auth.uid() then
    p_anon := p.anon; n := null;                         -- 原PO：身分跟文章一致、不編號
  elsif p_anon > 0 then
    select anon_no into n from public.forum_comments where post_id = p.id and author_id = auth.uid() and anon_no is not null limit 1;
    if n is null then select coalesce(max(anon_no), 0) + 1 into n from public.forum_comments where post_id = p.id; end if;
  end if;
  select role into r from public.profiles where id = auth.uid();
  insert into public.forum_comments (post_id, author_id, body, anon, author_role, anon_no)
  values (p.id, auth.uid(), p_body, p_anon, r, n) returning id into nid;
  update public.forum_posts set last_activity_at = now() where id = p.id;
  return nid;
end $$;
revoke execute on function public.forum_comment(bigint, text, smallint) from anon, public;
grant execute on function public.forum_comment(bigint, text, smallint) to authenticated;

-- 按讚／收回
create or replace function public.forum_like(p_post bigint, on_ boolean)
returns int language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.my_status() <> 'approved' then raise exception '檔案審核通過後才能按讚'; end if;
  if on_ then
    if not exists (select 1 from public.forum_posts p where p.id = p_post and p.removed_at is null and not p.hidden
                    and private.forum_author_ok(p.author_id, p.anon)) then raise exception '這篇文章已經不在了'; end if;
    insert into public.forum_likes (post_id, user_id) values (p_post, auth.uid()) on conflict do nothing;
  else
    delete from public.forum_likes where post_id = p_post and user_id = auth.uid();
  end if;
  return (select count(*) from public.forum_likes where post_id = p_post);
end $$;
revoke execute on function public.forum_like(bigint, boolean) from anon, public;
grant execute on function public.forum_like(bigint, boolean) to authenticated;

-- 刪除自己的文章或留言（管理員可以刪任何一則）
create or replace function public.forum_delete(p_post bigint default null, p_comment bigint default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if p_post is not null then
    delete from public.forum_posts where id = p_post and (author_id = auth.uid() or public.is_admin());
  elsif p_comment is not null then
    delete from public.forum_comments where id = p_comment and (author_id = auth.uid() or public.is_admin());
  end if;
  if not found then raise exception '找不到這則內容，或你沒有權限刪除'; end if;
end $$;
revoke execute on function public.forum_delete(bigint, bigint) from anon, public;
grant execute on function public.forum_delete(bigint, bigint) to authenticated;

-- 檢舉：同一則只能檢舉一次；3 位不同會員檢舉就先自動隱藏，等管理員處理
create or replace function public.forum_report(p_post bigint, p_comment bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a uuid; n int;
begin
  if auth.uid() is null or not private.forum_can_read() then raise exception '請先登入'; end if;
  if (p_post is null) = (p_comment is null) then raise exception '請選擇要檢舉的內容'; end if;
  if p_post is not null then select author_id into a from public.forum_posts where id = p_post and removed_at is null;
  else select author_id into a from public.forum_comments where id = p_comment and removed_at is null; end if;
  if a is null then raise exception '這則內容已經不在了'; end if;
  if a = auth.uid() then raise exception '不能檢舉自己'; end if;
  if (select count(*) from public.forum_reports where reporter_id = auth.uid() and created_at > now() - interval '1 day') >= 20 then
    raise exception '今天檢舉太多次了，請明天再試或聯絡客服';
  end if;
  insert into public.forum_reports (reporter_id, post_id, comment_id, reason, detail)
  values (auth.uid(), p_post, p_comment, p_reason, nullif(left(btrim(coalesce(p_detail, '')), 200), ''))
  on conflict do nothing;
  select count(distinct reporter_id) into n from public.forum_reports
   where status = 'open' and (case when p_post is not null then post_id = p_post else comment_id = p_comment end);
  if n >= 3 then
    if p_post is not null then update public.forum_posts set hidden = true where id = p_post;
    else update public.forum_comments set hidden = true where id = p_comment; end if;
  end if;
end $$;
revoke execute on function public.forum_report(bigint, bigint, text, text) from anon, public;
grant execute on function public.forum_report(bigint, bigint, text, text) to authenticated;

-- 後台：有人檢舉或被隱藏的內容（附真實作者）
create or replace function public.forum_admin_queue()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '沒有權限'; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'last_report' desc nulls last) from (
      select jsonb_build_object('kind', 'post', 'id', p.id, 'post_id', p.id, 'title', p.title, 'body', p.body, 'anon', p.anon,
                                'real_author_id', p.author_id, 'real_name', pr.nickname, 'created_at', p.created_at,
                                'hidden', p.hidden, 'removed', p.removed_at is not null,
                                'reports', (select coalesce(jsonb_agg(jsonb_build_object('reason', r.reason, 'detail', r.detail, 'at', r.created_at) order by r.created_at), '[]'::jsonb)
                                              from public.forum_reports r where r.post_id = p.id and r.status = 'open'),
                                'last_report', (select max(r.created_at) from public.forum_reports r where r.post_id = p.id and r.status = 'open')) x
        from public.forum_posts p join public.profiles pr on pr.id = p.author_id
       where p.removed_at is null and (p.hidden or exists (select 1 from public.forum_reports r where r.post_id = p.id and r.status = 'open'))
      union all
      select jsonb_build_object('kind', 'comment', 'id', c.id, 'post_id', c.post_id, 'title', p.title, 'body', c.body, 'anon', c.anon,
                                'real_author_id', c.author_id, 'real_name', pr.nickname, 'created_at', c.created_at,
                                'hidden', c.hidden, 'removed', c.removed_at is not null,
                                'reports', (select coalesce(jsonb_agg(jsonb_build_object('reason', r.reason, 'detail', r.detail, 'at', r.created_at) order by r.created_at), '[]'::jsonb)
                                              from public.forum_reports r where r.comment_id = c.id and r.status = 'open'),
                                'last_report', (select max(r.created_at) from public.forum_reports r where r.comment_id = c.id and r.status = 'open'))
        from public.forum_comments c join public.forum_posts p on p.id = c.post_id join public.profiles pr on pr.id = c.author_id
       where c.removed_at is null and (c.hidden or exists (select 1 from public.forum_reports r where r.comment_id = c.id and r.status = 'open'))
    ) q(x)), '[]'::jsonb);
end $$;
revoke execute on function public.forum_admin_queue() from anon, public;
grant execute on function public.forum_admin_queue() to authenticated;

-- 後台處理：restore 恢復顯示並駁回檢舉；remove 下架（保留內容當證據）並結案
create or replace function public.forum_admin_set(p_post bigint, p_comment bigint, p_action text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '沒有權限'; end if;
  if p_action not in ('restore','remove') then raise exception '動作不正確'; end if;
  if p_post is not null then
    update public.forum_posts set hidden = (p_action = 'remove'), removed_at = case when p_action = 'remove' then now() end where id = p_post;
    update public.forum_reports set status = case when p_action = 'remove' then 'resolved' else 'dismissed' end where post_id = p_post and status = 'open';
  else
    update public.forum_comments set hidden = (p_action = 'remove'), removed_at = case when p_action = 'remove' then now() end where id = p_comment;
    update public.forum_reports set status = case when p_action = 'remove' then 'resolved' else 'dismissed' end where comment_id = p_comment and status = 'open';
  end if;
end $$;
revoke execute on function public.forum_admin_set(bigint, bigint, text) from anon, public;
grant execute on function public.forum_admin_set(bigint, bigint, text) to authenticated;
