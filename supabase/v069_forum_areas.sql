
-- ============ v0.69 討論區分區：綜合、女生專區、男生專區 ============

-- 女生專區只有女生會員看得到、發得了文；男生專區只有男生會員；綜合大家都能用。性別建檔後不能改，所以分區不會被繞過。管理員看得到全部。

alter table public.forum_posts add column if not exists audience text not null default 'all';

do $$ begin alter table public.forum_posts add constraint forum_posts_audience_chk check (audience in ('all','female','male')); exception when duplicate_object then null; end $$;

create index if not exists forum_posts_aud_idx on public.forum_posts (audience, last_activity_at desc);

create or replace function private.forum_audience_ok(aud text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(aud, 'all') = 'all' or public.is_admin()
      or exists (select 1 from public.profiles where id = auth.uid() and gender = aud);
$$;
revoke all on function private.forum_audience_ok(text) from public, anon, authenticated;

create or replace function private.forum_post_json(p public.forum_posts, full_body boolean)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'board', p.board, 'audience', p.audience, 'title', p.title,
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

drop function if exists public.forum_list(text, text, timestamptz, int, boolean);

create or replace function public.forum_list(p_board text default null, p_sort text default 'new', p_before timestamptz default null, p_limit int default 20, p_mine boolean default false, p_audience text default 'all')
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if auth.uid() is null or not private.forum_can_read() then raise exception '檔案審核通過後才能使用討論區'; end if;
  if not p_mine and not private.forum_audience_ok(p_audience) then raise exception '這個專區只開放給%會員', case p_audience when 'female' then '女生' else '男生' end; end if;
  select coalesce(jsonb_agg(private.forum_post_json(x.pp, false) order by x.ord desc, (x.pp).last_activity_at desc), '[]'::jsonb) into res
    from (select p as pp, case when p_sort = 'hot'
                           then (select count(*) from public.forum_likes l where l.post_id = p.id) * 2
                              + (select count(*) from public.forum_comments c where c.post_id = p.id and c.removed_at is null and not c.hidden)
                           else 0 end as ord
            from public.forum_posts p
           where (p_board is null or p.board = p_board)
             and (p_mine or p.audience = coalesce(p_audience, 'all'))
             and (case when p_mine then p.author_id = auth.uid()
                       else p.removed_at is null and (not p.hidden or p.author_id = auth.uid())
                            and private.forum_author_ok(p.author_id, p.anon) end)
             and (p_sort <> 'hot' or p.created_at > now() - interval '7 days')
             and (p_before is null or p.last_activity_at < p_before)
           order by 2 desc, p.last_activity_at desc
           limit least(greatest(coalesce(p_limit, 20), 1), 50)) x;
  return res;
end $$;

revoke execute on function public.forum_list(text, text, timestamptz, int, boolean, text) from anon, public;
grant execute on function public.forum_list(text, text, timestamptz, int, boolean, text) to authenticated;

create or replace function public.forum_get(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.forum_posts; cs jsonb; adm boolean := public.is_admin();
begin
  if auth.uid() is null or not private.forum_can_read() then raise exception '檔案審核通過後才能使用討論區'; end if;
  select * into p from public.forum_posts where id = p_id;
  if p.id is null or (not adm and p.author_id <> auth.uid()
                      and (p.removed_at is not null or p.hidden or not private.forum_author_ok(p.author_id, p.anon) or not private.forum_audience_ok(p.audience))) then
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

drop function if exists public.forum_post(text, text, text, smallint);

create or replace function public.forum_post(p_board text, p_title text, p_body text, p_anon smallint, p_audience text default 'all')
returns bigint language plpgsql security definer set search_path = public as $$
declare nid bigint; r text;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if public.my_status() <> 'approved' and not public.is_admin() then raise exception '檔案審核通過後才能發文'; end if;
  if p_anon not in (0,1,2) then raise exception '請選擇發文身分'; end if;
  p_audience := coalesce(p_audience, 'all');
  if p_audience not in ('all','female','male') or not private.forum_audience_ok(p_audience) then raise exception '只能發在綜合討論或自己的專區'; end if;
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
  insert into public.forum_posts (author_id, board, title, body, anon, author_role, audience)
  values (auth.uid(), p_board, p_title, p_body, p_anon, r, p_audience) returning id into nid;
  return nid;
end $$;

revoke execute on function public.forum_post(text, text, text, smallint, text) from anon, public;
grant execute on function public.forum_post(text, text, text, smallint, text) to authenticated;

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
     or not private.forum_author_ok(p.author_id, p.anon) or not private.forum_audience_ok(p.audience) then raise exception '這篇文章已經不在了'; end if;
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

create or replace function public.forum_like(p_post bigint, on_ boolean)
returns int language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.my_status() <> 'approved' then raise exception '檔案審核通過後才能按讚'; end if;
  if on_ then
    if not exists (select 1 from public.forum_posts p where p.id = p_post and p.removed_at is null and not p.hidden
                    and private.forum_author_ok(p.author_id, p.anon) and private.forum_audience_ok(p.audience)) then raise exception '這篇文章已經不在了'; end if;
    insert into public.forum_likes (post_id, user_id) values (p_post, auth.uid()) on conflict do nothing;
  else
    delete from public.forum_likes where post_id = p_post and user_id = auth.uid();
  end if;
  return (select count(*) from public.forum_likes where post_id = p_post);
end $$;

create or replace function public.forum_report(p_post bigint, p_comment bigint, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a uuid; n int;
begin
  if auth.uid() is null or not private.forum_can_read() then raise exception '請先登入'; end if;
  if (p_post is null) = (p_comment is null) then raise exception '請選擇要檢舉的內容'; end if;
  if p_post is not null then select author_id into a from public.forum_posts where id = p_post and removed_at is null and private.forum_audience_ok(audience);
  else select c.author_id into a from public.forum_comments c join public.forum_posts p on p.id = c.post_id where c.id = p_comment and c.removed_at is null and private.forum_audience_ok(p.audience); end if;
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

create or replace function public.forum_admin_queue()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '沒有權限'; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'last_report' desc nulls last) from (
      select jsonb_build_object('kind', 'post', 'id', p.id, 'post_id', p.id, 'audience', p.audience, 'title', p.title, 'body', p.body, 'anon', p.anon,
                                'real_author_id', p.author_id, 'real_name', pr.nickname, 'created_at', p.created_at,
                                'hidden', p.hidden, 'removed', p.removed_at is not null,
                                'reports', (select coalesce(jsonb_agg(jsonb_build_object('reason', r.reason, 'detail', r.detail, 'at', r.created_at) order by r.created_at), '[]'::jsonb)
                                              from public.forum_reports r where r.post_id = p.id and r.status = 'open'),
                                'last_report', (select max(r.created_at) from public.forum_reports r where r.post_id = p.id and r.status = 'open')) x
        from public.forum_posts p join public.profiles pr on pr.id = p.author_id
       where p.removed_at is null and (p.hidden or exists (select 1 from public.forum_reports r where r.post_id = p.id and r.status = 'open'))
      union all
      select jsonb_build_object('kind', 'comment', 'id', c.id, 'post_id', c.post_id, 'audience', p.audience, 'title', p.title, 'body', c.body, 'anon', c.anon,
                                'real_author_id', c.author_id, 'real_name', pr.nickname, 'created_at', c.created_at,
                                'hidden', c.hidden, 'removed', c.removed_at is not null,
                                'reports', (select coalesce(jsonb_agg(jsonb_build_object('reason', r.reason, 'detail', r.detail, 'at', r.created_at) order by r.created_at), '[]'::jsonb)
                                              from public.forum_reports r where r.comment_id = c.id and r.status = 'open'),
                                'last_report', (select max(r.created_at) from public.forum_reports r where r.comment_id = c.id and r.status = 'open'))
        from public.forum_comments c join public.forum_posts p on p.id = c.post_id join public.profiles pr on pr.id = c.author_id
       where c.removed_at is null and (c.hidden or exists (select 1 from public.forum_reports r where r.comment_id = c.id and r.status = 'open'))
    ) q(x)), '[]'::jsonb);
end $$;
