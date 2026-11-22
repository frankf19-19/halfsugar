-- ============ v0.75 管理員：註冊流程追蹤（漏斗） ============
-- 看最近 N 天註冊的人，各走到哪一步；並列出還沒上架的人卡在哪一步（只有管理員能用）
create or replace function public.admin_funnel(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, private as $$
declare since timestamptz; d date := (now() at time zone 'Asia/Taipei')::date; r jsonb;
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  since := case when p_days is null or p_days <= 0 then '-infinity'::timestamptz
                else ((d - (p_days - 1))::timestamp at time zone 'Asia/Taipei') end;
  with c as (
    select p.id, p.nickname, p.role, p.status, p.created_at, p.is_admin,
           u.email_confirmed_at is not null as email_ok,
           (u.phone_confirmed_at is not null and nullif(u.phone,'') is not null) as phone_ok,
           (nullif(btrim(p.nickname),'') is not null and p.role is not null and p.birth_year is not null and p.city is not null) as basic_ok,
           p.avatar_path is not null as avatar_ok,
           (p.status in ('pending','approved','rejected','suspended') or p.submitted_at is not null) as submit_ok,
           (p.status = 'approved' or p.approved_at is not null) as approved_ok,
           exists (select 1 from public.likes l where l.from_id = p.id) as like_ok,
           exists (select 1 from public.messages m where m.sender_id = p.id) as msg_ok,
           p.approved_at
      from public.profiles p join auth.users u on u.id = p.id
     where p.created_at >= since and not p.is_admin
  )
  select jsonb_build_object(
    'days', p_days,
    'visitors', (select count(distinct vid) from private.site_visits where p_days is null or p_days <= 0 or day >= d - (p_days - 1)),
    'steps', jsonb_build_array(
      jsonb_build_object('k','signup',  'n', (select count(*) from c)),
      jsonb_build_object('k','email',   'n', (select count(*) from c where email_ok)),
      jsonb_build_object('k','phone',   'n', (select count(*) from c where phone_ok)),
      jsonb_build_object('k','basic',   'n', (select count(*) from c where phone_ok and basic_ok)),
      jsonb_build_object('k','avatar',  'n', (select count(*) from c where phone_ok and basic_ok and avatar_ok)),
      jsonb_build_object('k','submit',  'n', (select count(*) from c where submit_ok)),
      jsonb_build_object('k','approved','n', (select count(*) from c where approved_ok)),
      jsonb_build_object('k','like',    'n', (select count(*) from c where approved_ok and like_ok)),
      jsonb_build_object('k','msg',     'n', (select count(*) from c where approved_ok and msg_ok))
    ),
    'by_role', (select coalesce(jsonb_object_agg(rl, jsonb_build_object('signup', s, 'approved', a)), '{}') from
                (select coalesce(role,'none') rl, count(*) s, count(*) filter (where approved_ok) a from c group by 1) x),
    'hours_to_approve', (select round(percentile_cont(0.5) within group (order by extract(epoch from (approved_at - created_at))/3600)::numeric, 1)
                           from c where approved_at is not null and approved_at > created_at),
    'stuck', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', nickname, 'role', role, 'at', created_at,
                 'step', case when not email_ok then 'email' when not phone_ok then 'phone' when not basic_ok then 'basic'
                              when not avatar_ok then 'avatar' when status = 'pending' then 'review' when status = 'rejected' then 'rejected'
                              else 'other' end) order by created_at desc), '[]')
              from (select * from c where status in ('incomplete','pending','rejected') order by created_at desc limit 40) s)
  ) into r;
  return r;
end $$;
revoke execute on function public.admin_funnel(int) from public, anon;
grant execute on function public.admin_funnel(int) to authenticated;
