-- 半糖 E2E 權限測試：全部在一個交易裡執行，最後故意丟出例外讓一切回滾（不留下任何資料）
do $t$
declare
  A uuid := gen_random_uuid(); B uuid := gen_random_uuid(); C uuid := gen_random_uuid();
  D uuid := gen_random_uuid(); E uuid := gen_random_uuid();
  F uuid := gen_random_uuid(); G uuid := gen_random_uuid(); H uuid := gen_random_uuid(); rid uuid;
  out text[] := '{}'; n int; v text; mid uuid; ok boolean;
begin
  perform set_config('storage.allow_delete_query','true',true);
  insert into auth.users (id, email, aud, role) values
    (A,'e2e-a@test.invalid','authenticated','authenticated'),(B,'e2e-b@test.invalid','authenticated','authenticated'),
    (C,'e2e-c@test.invalid','authenticated','authenticated'),(D,'e2e-d@test.invalid','authenticated','authenticated'),
    (E,'e2e-e@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='A', gender='male', looking_for='female', role='daddy', birth_year=1985, city='台北市', status='approved', avatar_path=A||'/av.jpg', age_confirmed=true, agreed_terms_at=now() where id=A;
  update public.profiles set nickname='B', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved', avatar_path=B||'/av.jpg', age_confirmed=true, agreed_terms_at=now() where id=B;
  update public.profiles set gender='female', looking_for='male' where id=C; -- incomplete
  update public.profiles set nickname='D', gender='female', looking_for='male', role='baby', birth_year=1997, city='台北市', status='approved', hidden=true where id=D;
  update public.profiles set nickname='E', gender='male', looking_for='male', role='daddy', birth_year=1980, city='台北市', status='approved' where id=E;
  insert into public.photos (user_id, path, is_private, status) values (B, B||'/1.jpg', false, 'approved'), (B, B||'/2.jpg', true, 'approved'), (A, A||'/p.jpg', true, 'approved');
  insert into storage.objects (bucket_id, name) values ('photos', B||'/1.jpg'), ('photos', B||'/2.jpg'), ('photos', B||'/av.jpg');

  -- helper: act as user
  -- 1 未建檔的 C 看不到任何照片
  perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', C::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.photos; out := array_append(out, (('1 未審核帳號看到照片數 = '||n||' (應為0)'))::text);
  select count(*) into n from storage.objects where bucket_id='photos'; out := array_append(out, (('1b 未審核帳號看到檔案數 = '||n||' (應為0)'))::text);
  begin perform public.request_private_photos(B); out := array_append(out, ('7 未審核帳號索取私密照：沒被擋 ✗')::text);
  exception when others then out := array_append(out, (('7 未審核帳號索取私密照被擋 ✓ '||sqlerrm))::text); end;
  begin insert into public.photo_requests (requester_id, owner_id) values (C, B); out := array_append(out, ('7b 直接寫入索取：沒被擋 ✗')::text);
  exception when others then out := array_append(out, (('7b 直接寫入索取被擋 ✓'))::text); end;
  execute 'reset role';

  -- 2 A 看 B 的照片：只有公開照；看不到隱身的 D
  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.photos where user_id=B; out := array_append(out, (('2 A 看到 B 的照片數 = '||n||' (應為1，私密照要授權)'))::text);
  select count(*) into n from storage.objects where name like B||'/%'; out := array_append(out, (('2b A 能讀 B 的檔案數 = '||n||' (應為2：頭像+公開照)'))::text);
  select count(*) into n from public.profiles where id=D; out := array_append(out, (('3 A 看到隱身 D = '||n||' (應為0)'))::text);
  -- 10 改性別無效
  update public.profiles set gender='female' where id=A;
  select gender into v from public.profiles where id=A; out := array_append(out, (('10 A 改性別後 = '||v||' (應為male)'))::text);
  -- 9 私密照改公開 → 待審
  update public.photos set is_private=false where user_id=A;
  select status into v from public.photos where user_id=A; out := array_append(out, (('9 私密照改公開後狀態 = '||v||' (應為pending)'))::text);
  -- 自己核准自己的照片
  update public.photos set status='approved' where user_id=A;
  select status into v from public.photos where user_id=A; out := array_append(out, (('9b 自己核准照片後 = '||v||' (應為pending)'))::text);
  -- 5 喜歡
  insert into public.likes (from_id, to_id) values (A, B);
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub',E,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', E::text, true);
  execute 'set local role authenticated';
  begin insert into public.likes (from_id, to_id) values (E, B); out := array_append(out, ('11 方向不合的喜歡：沒被擋 ✗')::text);
  exception when others then out := array_append(out, ('11 方向不合的喜歡被擋 ✓')::text); end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  -- 4 照片調包：刪掉已登記的檔案
  delete from storage.objects where name = B||'/1.jpg'; get diagnostics n = row_count;
  out := array_append(out, (('4 B 刪除已登記照片檔 = '||n||' 筆 (應為0)'))::text);
  insert into public.likes (from_id, to_id) values (B, A);
  select id into mid from public.matches where user_a=least(A,B) and user_b=greatest(A,B);
  out := array_append(out, (('5 互相喜歡後配對 = '||coalesce(mid::text,'無')||''))::text);
  insert into public.messages (match_id, sender_id, body) values (mid, B, '舊訊息');
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  update public.messages set created_at = now() - interval '1 hour' where match_id=mid;
  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', B::text, true);
  -- 4b 管理員刪掉檔案後，B 用同檔名重新上傳
  delete from storage.objects where name = B||'/1.jpg';
  execute 'set local role authenticated';
  begin insert into storage.objects (bucket_id, name, owner) values ('photos', B||'/1.jpg', B); out := array_append(out, ('4b 同檔名重新上傳：沒被擋 ✗')::text);
  exception when others then out := array_append(out, ('4b 同檔名重新上傳被擋 ✓')::text); end;
  begin insert into storage.objects (bucket_id, name, owner) values ('photos', A||'/x.jpg', B); out := array_append(out, ('4c 上傳到別人資料夾：沒被擋 ✗')::text);
  exception when others then out := array_append(out, ('4c 上傳到別人資料夾被擋 ✓')::text); end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  update public.messages set body='被改過' where match_id=mid;
  execute 'reset role'; select body into v from public.messages where match_id=mid; out := array_append(out, (('12 A 竄改 B 的訊息後 = '||v||' (應為舊訊息)'))::text);
  execute 'set local role authenticated';
  -- 8 私密照索取與冷卻
  perform public.request_private_photos(B); out := array_append(out, ('8 A 索取 B 私密照 ✓')::text);
  perform public.unmatch(mid);
  select count(*) into n from public.messages where match_id=mid; out := array_append(out, (('5b 解除配對後 A 看到訊息 = '||n||' (應為0)'))::text);
  insert into public.likes (from_id, to_id) values (A, B);
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  update public.photo_requests set status='denied' where owner_id=B and requester_id=A;
  insert into public.likes (from_id, to_id) values (B, A);
  select count(*) into n from public.matches where id=mid; out := array_append(out, (('5c 重新配對 = '||n||' (應為1)'))::text);
  select count(*) into n from public.messages where match_id=mid; out := array_append(out, (('5d 重新配對後看到舊訊息 = '||n||' (應為0)'))::text);
  select count(*) into n from public.related_names(array[A,C,D]); out := array_append(out, (('13 B 用名單函式查不相關的人 = '||n||' (應為1：只有索取過的 A)'))::text);
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  begin perform public.request_private_photos(B); out := array_append(out, ('8b 被婉拒後馬上再問：沒被擋 ✗')::text);
  exception when others then out := array_append(out, (('8b 被婉拒後馬上再問被擋 ✓ '||sqlerrm))::text); end;
  delete from public.photo_requests where requester_id=A; get diagnostics n = row_count;
  out := array_append(out, (('8c A 刪掉被婉拒的紀錄再重送 = '||n||' 筆 (應為0)'))::text);
  -- 6 封鎖 → 自動解除配對
  insert into public.blocks (blocker_id, blocked_id) values (A, B);
  execute 'reset role';
  select count(*) into n from public.matches where id=mid and closed_at is null; out := array_append(out, (('6 封鎖後配對仍開著 = '||n||' (應為0)'))::text);
  select count(*) into n from public.likes where (from_id=A and to_id=B) or (from_id=B and to_id=A); out := array_append(out, (('6b 封鎖後殘留喜歡 = '||n||' (應為0)'))::text);
  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.matches where id=mid; out := array_append(out, (('6c 被封鎖者看到配對 = '||n||' (應為0)'))::text);
  select count(*) into n from public.profiles where id=A; out := array_append(out, (('6d 被封鎖者看到 A 的檔案 = '||n||' (應為0)'))::text);
  execute 'reset role';

  -- 14 手機驗證：沒驗證手機就算資料填完也不能送審
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users (id, email, aud, role) values (F,'e2e-f@test.invalid','authenticated','authenticated');
  perform set_config('request.jwt.claims', json_build_object('sub',F,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', F::text, true);
  execute 'set local role authenticated';
  update public.profiles set nickname='F', gender='male', looking_for='female', role='daddy', birth_year=1980, city='台北市',
    avatar_path=F||'/a.jpg', age_confirmed=true, agreed_terms_at=now() where id=F;
  select status into v from public.profiles where id=F; out := array_append(out, ('14 沒驗證手機送審後狀態 = '||v||' (應為incomplete)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  update auth.users set phone='886900000001', phone_confirmed_at=now() where id=F;
  perform set_config('request.jwt.claims', json_build_object('sub',F,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', F::text, true);
  execute 'set local role authenticated';
  update public.profiles set bio='hi' where id=F;
  select status into v from public.profiles where id=F; out := array_append(out, ('14b 驗證手機後送審狀態 = '||v||' (應為pending)')::text);
  execute 'reset role';
  -- 15 一支手機只能綁一個帳號
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  begin update auth.users set phone='886900000001' where id=E; out := array_append(out, '15 同一支手機綁第二個帳號：沒被擋 ✗'::text);
  exception when unique_violation then out := array_append(out, '15 同一支手機綁第二個帳號被擋 ✓'::text); end;
  -- 16 刪除帳號
  update auth.users set phone='886900000002', phone_confirmed_at=now() where id=B;
  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  begin perform public.delete_my_account(); out := array_append(out, '16g 檔案沒刪就刪帳號：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '16g 檔案沒刪完不能刪帳號 ✓'::text); end;
  perform public.begin_account_deletion();
  execute 'reset role';
  delete from storage.objects where name like B::text || '/%';
  execute 'set local role authenticated';
  perform public.delete_my_account();
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from auth.users where id=B; out := array_append(out, ('16 刪除後帳號殘留 = '||n||' (應為0)')::text);
  select count(*) into n from public.profiles where id=B; out := array_append(out, ('16b 刪除後檔案殘留 = '||n||' (應為0)')::text);
  select count(*) into n from public.photos where user_id=B; out := array_append(out, ('16c 刪除後照片殘留 = '||n||' (應為0)')::text);
  select count(*) into n from public.messages where sender_id=B; out := array_append(out, ('16d 刪除後訊息殘留 = '||n||' (應為0)')::text);
  begin update auth.users set phone='886900000002' where id=E; out := array_append(out, '16e 刪除後手機可重新綁定 ✓'::text);
  exception when others then out := array_append(out, ('16e 刪除後手機仍被占用 ✗ '||sqlerrm)::text); end;
  begin perform public.delete_my_account(); out := array_append(out, '16f 沒登入也能刪除：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '16f 沒登入呼叫刪除被擋 ✓'::text); end;

  -- 17 欄位權限
  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  begin select count(*) into n from (select is_admin, review_note from public.profiles) x; out := array_append(out, '17 會員讀到管理員/退件欄位：沒被擋 ✗'::text);
  exception when insufficient_privilege then out := array_append(out, '17 會員讀不到管理員/退件欄位 ✓'::text); end;
  select count(*) into n from public.get_me(); out := array_append(out, ('17b 讀自己的完整資料 = '||n||' 筆 (應為1)')::text);
  begin perform * from public.admin_profiles(); out := array_append(out, '17c 一般會員用管理員查詢：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '17c 一般會員用管理員查詢被擋 ✓'::text); end;
  select count(*) into n from public.profiles where id=E; out := array_append(out, ('17d 方向不合的會員檔案可見 = '||n||' (應為0)')::text);
  execute 'reset role';

  -- 18 其他新規則
  perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', C::text, true);
  execute 'set local role authenticated';
  begin insert into public.photos (user_id, path) values (C, C||'/123.jpg'); out := array_append(out, '18 未完成註冊上傳照片：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '18 未完成註冊不能上傳照片 ✓'::text); end;
  begin update public.profiles set city='加LINE abc' where id=C; out := array_append(out, '18b 地區亂填：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '18b 地區只能選清單內 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',E,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', E::text, true);
  execute 'set local role authenticated';
  insert into public.blocks (blocker_id, blocked_id) values (E, D);
  update public.blocks set blocked_id = A where blocker_id = E; get diagnostics n = row_count;
  out := array_append(out, ('18c 修改封鎖對象 = '||n||' 筆 (應為0)')::text);
  begin perform private.is_compatible(A); out := array_append(out, '18d 內部函式（從資料庫內）可用 ✓'::text);
  exception when others then out := array_append(out, ('18d 內部函式不能用 ✗ '||sqlerrm)::text); end;
  execute 'reset role';

  -- 19 停權與手機黑名單
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  update auth.users set phone='886900000009', phone_confirmed_at=now() where id=E;
  update public.profiles set status='suspended' where id=E;
  perform set_config('request.jwt.claims', json_build_object('sub',E,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', E::text, true);
  execute 'set local role authenticated';
  begin perform public.begin_account_deletion(); out := array_append(out, '19 停權帳號自己刪除：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '19 停權帳號不能自己刪除 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  delete from auth.users where id=E;   -- 模擬管理員刪除
  -- 用同一支手機重新註冊
  update auth.users set phone='886900000009', phone_confirmed_at=now() where id=C;
  update public.profiles set nickname='C', role='baby', birth_year=1999, city='台北市', avatar_path=C||'/1.jpg', age_confirmed=true, agreed_terms_at=now(), status='incomplete' where id=C;
  perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', C::text, true);
  execute 'set local role authenticated';
  begin update public.profiles set bio='hi' where id=C; select status into v from public.profiles where id=C;
    out := array_append(out, ('19b 停權手機重新註冊：沒被擋 ✗ '||v)::text);
  exception when others then out := array_append(out, ('19b 停權手機不能重新註冊 ✓ '||sqlerrm)::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from public.banned_phones where phone_hash like '%886900000009%'; out := array_append(out, ('19c 黑名單存明碼 = '||n||' (應為0)')::text);
  -- 被檢舉中不能自刪
  insert into public.reports (reporter_id, reported_id, reason) values (A, F, 'harass');
  perform set_config('request.jwt.claims', json_build_object('sub',F,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', F::text, true);
  execute 'set local role authenticated';
  begin perform public.begin_account_deletion(); out := array_append(out, '19d 被檢舉中自己刪除：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '19d 被檢舉中不能自己刪除 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  delete from auth.users where id=A;
  select count(*) into n from public.reports where reported_id=F; out := array_append(out, ('19e 檢舉人刪帳號後檢舉仍保留 = '||n||' (應為1)')::text);

  -- 20 審核中聊天、檢舉證據、重新送審、年齡、停權關閉配對
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users (id, email, aud, role) values (G,'e2e-g@test.invalid','authenticated','authenticated'),(H,'e2e-h@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='G', gender='male', looking_for='female', role='daddy', birth_year=1980, city='台北市', status='approved' where id=G;
  update public.profiles set nickname='H', gender='female', looking_for='male', role='baby', birth_year=1999, city='台北市', status='approved' where id=H;
  insert into public.matches (user_a, user_b) values (least(G,H), greatest(G,H)) returning id into mid;
  insert into public.messages (match_id, sender_id, body) values (mid, G, '你好'), (mid, H, '嗨');
  perform set_config('request.jwt.claims', json_build_object('sub',H,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', H::text, true);
  execute 'set local role authenticated';
  update public.profiles set bio='改了自介' where id=H;
  select status into v from public.profiles where id=H; out := array_append(out, ('20 改自介後狀態 = '||v||' (應為pending)')::text);
  begin insert into public.messages (match_id, sender_id, body) values (mid, H, '審核中也能聊'); out := array_append(out, '20b 審核中可以和已配對的人聊天 ✓'::text);
  exception when others then out := array_append(out, ('20b 審核中不能聊天 ✗ '||sqlerrm)::text); end;
  begin update public.profiles set birth_year = extract(year from now())::int - 17 where id=H; out := array_append(out, '20c 改成未滿 18 歲：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '20c 未滿 18 歲被擋 ✓'::text); end;
  insert into public.reports (reporter_id, reported_id, reason) values (H, G, 'harass') returning id into rid;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',G,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', G::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.profiles where id=H; out := array_append(out, ('20d 對方審核中仍看得到檔案 = '||n||' (應為1)')::text);
  select count(*) into n from public.report_evidence; out := array_append(out, ('20e 一般會員讀到檢舉證據 = '||n||' (應為0)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from public.report_evidence where report_id=rid; out := array_append(out, ('20f 檢舉時備份的對話 = '||n||' 則 (應為3)')::text);
  update public.profiles set status='suspended' where id=G;
  select count(*) into n from public.matches where id=mid and closed_at is null; out := array_append(out, ('20g 停權後配對仍開著 = '||n||' (應為0)')::text);
  update public.profiles set status='rejected' where id=H;
  perform set_config('request.jwt.claims', json_build_object('sub',H,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', H::text, true);
  execute 'set local role authenticated';
  perform public.resubmit_profile();
  select status into v from public.profiles where id=H; out := array_append(out, ('20h 退件後重新送審 = '||v||' (應為pending)')::text);
  execute 'reset role';

  raise exception E'E2E 結果（已全部回滾）:\n%', array_to_string(out, E'\n');
end $t$;
