-- 註冊漏斗：「尚未完成建檔」的帳號卡在哪一步（只讀，不改資料）
-- 在 Supabase SQL Editor 執行
with u as (
  select au.id, au.created_at, au.email_confirmed_at, au.last_sign_in_at,
         (au.phone_confirmed_at is not null and nullif(au.phone,'') is not null) as phone_ok,
         (select count(*) from public.sms_sends s where s.user_id = au.id) as sms_sent,
         p.status, p.nickname, p.role,
         (select count(*) from public.photos ph where ph.user_id = au.id) as photos
  from auth.users au left join public.profiles p on p.id = au.id
  where coalesce(p.is_admin,false) = false
)
select
  case
    when status <> 'incomplete' then '0 已送審以上（' || coalesce(status,'?') || '）'
    when email_confirmed_at is null then '1 Email 還沒驗證'
    when last_sign_in_at is null then '2 Email 驗證了但沒登入過'
    when not phone_ok and sms_sent = 0 then '3 登入了，沒按「傳送驗證碼」'
    when not phone_ok and sms_sent > 0 then '4 收到簡訊但沒完成驗證'
    when phone_ok and nickname is null then '5 手機驗證完，沒填資料'
    when phone_ok and photos = 0 then '6 填了資料，沒傳照片'
    else '7 其他（資料或照片不完整）'
  end as stage,
  count(*) as n,
  min(created_at) as first_signup,
  max(created_at) as last_signup
from u group by 1 order by 1;
