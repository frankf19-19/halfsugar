begin;
insert into vault.secrets_t values ('resend_api_key','k');
-- 三個人：A 手機驗過、資料不含 bio/身材；B 沒手機；C 已上架
insert into auth.users(id,email,phone,phone_confirmed_at,email_confirmed_at,created_at) values
 ('00000000-0000-0000-0000-0000000000a1','a@x.com','886912000001',now(),now(),now()-interval '2 days'),
 ('00000000-0000-0000-0000-0000000000b1','b@x.com',null,null,now(),now()-interval '30 hours'),
 ('00000000-0000-0000-0000-0000000000c1','c@x.com',null,null,now(),now()-interval '3 hours'),
 ('00000000-0000-0000-0000-0000000000d1','d@x.com',null,null,null,now()-interval '3 days');
update public.profiles set created_at = u.created_at from auth.users u where u.id=profiles.id and u.email in ('a@x.com','b@x.com','c@x.com','d@x.com');
select id, status from public.profiles where id::text like '00000000-0000-0000-0000-0000000000%1' order by id;
-- A 送出精簡資料（沒有 bio、body_type）
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
update public.profiles set nickname='小A', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市',
  avatar_path='00000000-0000-0000-0000-0000000000a1/x.jpg', age_confirmed=true, agreed_terms_at=now() where id='00000000-0000-0000-0000-0000000000a1';
select 'A after submit', status from public.profiles where id='00000000-0000-0000-0000-0000000000a1';
-- B 沒手機：一樣送精簡資料，應維持 incomplete
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
update public.profiles set nickname='小B', gender='male', looking_for='female', role='daddy', budget=(select budget from public.profiles where budget is not null limit 1), birth_year=1985, city='台北市',
  avatar_path='00000000-0000-0000-0000-0000000000b1/x.jpg', age_confirmed=true, agreed_terms_at=now() where id='00000000-0000-0000-0000-0000000000b1';
select 'B after submit', status from public.profiles where id='00000000-0000-0000-0000-0000000000b1';
select set_config('request.jwt.claim.sub','',true);
-- 提醒信：A 已送審不寄；B（30 小時、沒手機）寄 phone；C（3 小時）不寄；D（email 未驗證）不寄
select 'sent', private.onboard_remind_run();
select o.stage, u.email from private.onboard_reminders o join auth.users u on u.id=o.user_id order by 2;
select 'second run', private.onboard_remind_run();
select body->>'subject', body->'to' from net.calls;
rollback;
