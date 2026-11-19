begin;
insert into vault.secrets_t values ('resend_api_key','k');
insert into auth.users(id,email,email_confirmed_at,created_at) values ('00000000-0000-0000-0000-0000000000ad','admin@x.com',now(),now());
update public.profiles set is_admin = true where id = '00000000-0000-0000-0000-0000000000ad';
delete from net.calls;
insert into auth.users(id,email,phone,phone_confirmed_at,email_confirmed_at,created_at) values
 ('00000000-0000-0000-0000-0000000000e1','e@x.com','886912000009',now(),now(),now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',true);
update public.profiles set nickname='小E<b>', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市',
  avatar_path='00000000-0000-0000-0000-0000000000e1/x.jpg', age_confirmed=true, agreed_terms_at=now() where id='00000000-0000-0000-0000-0000000000e1';
select 'E status', status from public.profiles where id='00000000-0000-0000-0000-0000000000e1';
select set_config('request.jwt.claim.sub','',true);
select body->>'subject' as subj, body->'to' as to_, position('&lt;b&gt;' in body->>'html')>0 as escaped from net.calls order by 1;
-- 管理員信箱設定後改寄這裡
update private.mail_config set admin_email='boss@x.com';
delete from net.calls;
insert into auth.users(id,email,email_confirmed_at,created_at) values ('00000000-0000-0000-0000-0000000000f1','f@x.com',now(),now());
select body->'to' from net.calls;
rollback;
