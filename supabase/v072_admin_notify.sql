-- v0.72.0 管理員通知信：有人註冊、有人送出檔案待審核時，寄 Email 給管理員。
-- 收件人：private.mail_config.admin_email；沒填就寄給所有 is_admin 會員的登入信箱。
-- 寄信失敗絕不影響註冊或送審（例外全部吞掉）。
alter table private.mail_config add column if not exists admin_email text;

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
      'html', '<div style="font-family:sans-serif;font-size:15px;line-height:1.8;color:#111;max-width:520px">' || body_html
              || '<p><a href="https://onethirdsugar.com/#/admin" style="display:inline-block;background:#111;color:#fff;padding:10px 22px;text-decoration:none">打開後台</a></p></div>'));
end $$;
revoke execute on function private.admin_mail(text, text) from public, anon, authenticated;

create or replace function private.profiles_admin_notify()
returns trigger language plpgsql security definer set search_path = public, private, extensions as $$
declare em text; total int; role_t text; gender_t text;
begin
  begin
    if coalesce(new.is_admin, false) then return new; end if;
    if tg_op = 'INSERT' then
      select email into em from auth.users where id = new.id;
      select count(*) into total from profiles where not coalesce(is_admin, false);
      perform private.admin_mail('微糖：有新會員註冊（第 ' || total || ' 位）',
        '<p>剛剛有人註冊微糖。</p><p>登入信箱：' || coalesce(em, '（手機註冊）') || '<br>時間：'
        || to_char(now() at time zone 'Asia/Taipei', 'YYYY-MM-DD HH24:MI') || '（台灣時間）<br>目前會員數：' || total || ' 位</p>'
        || '<p style="color:#777;font-size:13px">接下來對方要完成手機驗證、建立檔案，送審時會再寄一封通知給你。</p>');
    elsif tg_op = 'UPDATE' and new.status = 'pending' and old.status is distinct from 'pending' then
      role_t := case new.role when 'daddy' then 'Sugar Daddy' when 'mommy' then 'Sugar Mommy' when 'baby' then '甜心' else '未填' end;
      gender_t := case new.gender when 'male' then '男' when 'female' then '女' else '未填' end;
      perform private.admin_mail('微糖：有檔案等你審核（' || coalesce(nullif(btrim(new.nickname), ''), '新會員') || '）',
        '<p>有會員送出檔案，等你審核。</p><p>暱稱：' || replace(replace(coalesce(new.nickname, ''), '<', '&lt;'), '>', '&gt;')
        || '<br>身分：' || role_t || '／' || gender_t
        || '<br>年齡：' || coalesce((extract(year from now())::int - new.birth_year)::text, '未填')
        || '<br>地區：' || replace(replace(coalesce(new.city, '未填'), '<', '&lt;'), '>', '&gt;') || '</p>'
        || '<p style="color:#777;font-size:13px">檔案頁寫著 24 小時內審核，記得早點處理。</p>');
    end if;
  exception when others then
    null;
  end;
  return new;
end $$;
revoke execute on function private.profiles_admin_notify() from public, anon, authenticated;

drop trigger if exists profiles_admin_notify on public.profiles;
create trigger profiles_admin_notify after insert or update on public.profiles
  for each row execute function private.profiles_admin_notify();
