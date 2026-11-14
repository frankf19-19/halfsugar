
-- ============ v0.70 討論區：管理員具名發文顯示「微糖小編・官方」，不連到個人檔案 ============
create or replace function private.forum_post_json(p public.forum_posts, full_body boolean)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'board', p.board, 'audience', p.audience, 'title', p.title,
    'body', case when full_body then p.body else left(p.body, 140) end,
    'anon', p.anon,
    'name', case when p.anon = 0 then (case when pr.is_admin then '微糖小編' else coalesce(pr.nickname, '會員') end) else '匿名' end,
    'role', case when p.anon = 0 and pr.is_admin then '官方' when p.anon < 2 then private.forum_role_label(case when p.anon = 0 then pr.role else p.author_role end) end,
    'author_id', case when p.anon = 0 and not pr.is_admin and private.profile_visible(p.author_id) then p.author_id end,
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
             'name', case when c.author_id = p.author_id then (case when p.anon = 0 then (case when pr.is_admin then '微糖小編' else coalesce(pr.nickname, '會員') end) else '匿名' end)
                          when c.anon = 0 then (case when pr.is_admin then '微糖小編' else coalesce(pr.nickname, '會員') end)
                          else '匿名 ' || c.anon_no end,
             'role', case when pr.is_admin and (case when c.author_id = p.author_id then p.anon else c.anon end) = 0 then '官方' when c.author_id = p.author_id then (case when p.anon < 2 then private.forum_role_label(case when p.anon = 0 then pr.role else p.author_role end) end)
                          when c.anon < 2 then private.forum_role_label(case when c.anon = 0 then pr.role else c.author_role end) end,
             'author_id', case when (case when c.author_id = p.author_id then p.anon else c.anon end) = 0 and not pr.is_admin and private.profile_visible(c.author_id) then c.author_id end,
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
