-- ============ v0.76 網站錯誤回報 ============
-- 會員瀏覽器裡發生的程式錯誤，自動記下來給管理員看（同一個錯誤 10 分鐘內只算次數，不重複存）
create table if not exists private.client_errors (
  id        bigint generated always as identity primary key,
  first_at  timestamptz not null default now(),
  last_at   timestamptz not null default now(),
  hits      int not null default 1,
  user_id   uuid,
  vid       text,
  kind      text,
  msg       text not null,
  src       text,
  line      int,
  col       int,
  stack     text,
  page      text,
  ua        text,
  build     text
);
create index if not exists client_errors_at_idx on private.client_errors(last_at desc);
create index if not exists client_errors_msg_idx on private.client_errors(md5(msg), last_at desc);
revoke all on private.client_errors from public, anon, authenticated;

create or replace function public.log_client_error(p jsonb)
returns void language plpgsql security definer set search_path = public, private as $$
declare v_msg text := left(btrim(coalesce(p->>'msg','')), 500); v_vid text := left(coalesce(p->>'vid',''), 40); v_id bigint;
begin
  if v_msg = '' then return; end if;
  -- 防灌：同一個訪客一小時最多 30 筆、全站一天最多 5000 筆
  if (select count(*) from private.client_errors where (vid = v_vid or (auth.uid() is not null and user_id = auth.uid())) and last_at > now() - interval '1 hour') >= 30 then return; end if;
  if (select count(*) from private.client_errors where first_at > now() - interval '1 day') >= 5000 then return; end if;
  select id into v_id from private.client_errors
   where md5(msg) = md5(v_msg) and coalesce(vid,'') = v_vid and last_at > now() - interval '10 minutes'
   order by last_at desc limit 1;
  if v_id is not null then
    update private.client_errors set hits = hits + 1, last_at = now() where id = v_id; return;
  end if;
  insert into private.client_errors (user_id, vid, kind, msg, src, line, col, stack, page, ua, build)
  values (auth.uid(), nullif(v_vid,''), left(p->>'kind', 20), v_msg, left(p->>'src', 300),
          nullif(p->>'line','')::int, nullif(p->>'col','')::int, left(p->>'stack', 2000),
          left(p->>'page', 200), left(p->>'ua', 300), left(p->>'build', 20));
exception when others then return;   -- 記錄錯誤本身不能再讓網站出錯
end $$;
revoke execute on function public.log_client_error(jsonb) from public;
grant execute on function public.log_client_error(jsonb) to anon, authenticated;

-- 管理員：近 N 天的錯誤，依錯誤訊息分組
create or replace function public.admin_client_errors(p_days int default 7)
returns jsonb language plpgsql stable security definer set search_path = public, private as $$
begin
  if not public.is_admin() then raise exception '只有管理員可以使用'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'last_at' desc), '[]') from (
    select jsonb_build_object('msg', msg, 'hits', sum(hits), 'people', count(distinct coalesce(user_id::text, vid)),
             'last_at', max(last_at), 'first_at', min(first_at),
             'page', (array_agg(page order by last_at desc))[1], 'src', (array_agg(src order by last_at desc))[1],
             'line', (array_agg(line order by last_at desc))[1], 'stack', (array_agg(stack order by last_at desc))[1],
             'ua', (array_agg(ua order by last_at desc))[1], 'build', (array_agg(build order by last_at desc))[1],
             'members', (select coalesce(jsonb_agg(distinct p.nickname), '[]') from private.client_errors e2 join public.profiles p on p.id = e2.user_id
                          where e2.msg = e.msg and e2.last_at > now() - make_interval(days => greatest(p_days,1)))) x
      from private.client_errors e
     where last_at > now() - make_interval(days => greatest(p_days,1))
     group by msg order by max(last_at) desc limit 50) s);
end $$;
revoke execute on function public.admin_client_errors(int) from public, anon;
grant execute on function public.admin_client_errors(int) to authenticated;

-- 超過 60 天的錯誤紀錄自動清掉（每天跑一次）
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'client_errors_purge';
    perform cron.schedule('client_errors_purge', '23 4 * * *', $c$delete from private.client_errors where last_at < now() - interval '60 days'$c$);
  end if;
end $$;
