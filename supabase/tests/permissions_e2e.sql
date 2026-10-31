-- 微糖 E2E 權限測試：全部在一個交易裡執行，最後故意丟出例外讓一切回滾（不留下任何資料）
do $t$
declare
  A uuid := gen_random_uuid(); B uuid := gen_random_uuid(); C uuid := gen_random_uuid();
  D uuid := gen_random_uuid(); E uuid := gen_random_uuid();
  Z uuid := gen_random_uuid(); P uuid := gen_random_uuid(); Q uuid := gen_random_uuid(); R uuid := gen_random_uuid(); S2 uuid := gen_random_uuid(); K uuid := gen_random_uuid(); T uuid; i int; F uuid := gen_random_uuid(); G uuid := gen_random_uuid(); H uuid := gen_random_uuid(); rid uuid; Y uuid := gen_random_uuid();
  out text[] := '{}'; n int; v text; mid uuid; ok boolean;
  AD uuid := gen_random_uuid(); W uuid := gen_random_uuid(); X1 uuid := gen_random_uuid(); X2 uuid := gen_random_uuid(); cm uuid; cm2 uuid; m1 bigint; m2 bigint; rid2 uuid;
begin
  perform set_config('storage.allow_delete_query','true',true);
  update public.app_config set value='off' where key='free_launch';   -- 先測正式收費後的規則（交易結束會回滾）
  insert into auth.users (id, email, aud, role) values
    (A,'e2e-a@test.invalid','authenticated','authenticated'),(B,'e2e-b@test.invalid','authenticated','authenticated'),
    (C,'e2e-c@test.invalid','authenticated','authenticated'),(D,'e2e-d@test.invalid','authenticated','authenticated'),
    (E,'e2e-e@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='A', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1985, city='台北市', status='approved', avatar_path=A||'/av.jpg', age_confirmed=true, agreed_terms_at=now() where id=A;
  update public.profiles set nickname='B', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved', avatar_path=B||'/av.jpg', age_confirmed=true, agreed_terms_at=now() where id=B;
  update public.profiles set gender='female', looking_for='male' where id=C; -- incomplete
  update public.profiles set nickname='D', gender='female', looking_for='male', role='baby', birth_year=1997, city='台北市', status='approved', hidden=true where id=D;
  update public.profiles set nickname='E', gender='male', looking_for='male', role='daddy', budget='50to80k', birth_year=1980, city='台北市', status='approved' where id=E;
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
  select public.send_first_message(A, '舊訊息') into mid;
  out := array_append(out, (('5 直接傳訊息開啟對話 = '||coalesce(mid::text,'無')||''))::text);
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
  perform public.send_first_message(B, '重新開始');
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  update public.photo_requests set status='denied' where owner_id=B and requester_id=A;
  select count(*) into n from public.matches where id=mid; out := array_append(out, (('5c 重新開啟對話 = '||n||' (應為1)'))::text);
  select count(*) into n from public.messages where match_id=mid and body='舊訊息'; out := array_append(out, (('5d 重新開啟後看到舊訊息 = '||n||' (應為0)'))::text);
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
  update public.profiles set nickname='F', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1980, city='台北市',
    avatar_path=F||'/a.jpg', age_confirmed=true, agreed_terms_at=now() where id=F;
  select status into v from public.profiles where id=F; out := array_append(out, ('14 沒驗證手機送審後狀態 = '||v||' (應為incomplete)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  update auth.users set phone='886900000001', phone_confirmed_at=now() where id=F;
  perform set_config('request.jwt.claims', json_build_object('sub',F,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', F::text, true);
  execute 'set local role authenticated';
  update public.profiles set bio='hi' where id=F;
  select status into v from public.profiles where id=F; out := array_append(out, ('14a 沒填身材就送審 = '||v||' (應為incomplete)')::text);
  update public.profiles set body_type='fit' where id=F;
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
  begin perform public.begin_account_deletion(); raise exception 'e2e_rollback';
  exception when others then out := array_append(out, (case when sqlerrm='e2e_rollback' then '19d 被檢舉中仍可自己刪除帳號（證據已備份） ✓' else '19d 被檢舉中自己刪除被擋：'||sqlerrm||' ✗' end)::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  delete from auth.users where id=A;
  select count(*) into n from public.reports where reported_id=F; out := array_append(out, ('19e 檢舉人刪帳號後檢舉仍保留 = '||n||' (應為1)')::text);

  -- 20 審核中聊天、檢舉證據、重新送審、年齡、停權關閉配對
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users (id, email, aud, role) values (G,'e2e-g@test.invalid','authenticated','authenticated'),(H,'e2e-h@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='G', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1980, city='台北市', status='approved' where id=G;
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

  -- 21 直接傳訊息：回覆前只能一則、每天 10 個新對話
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users (id, email, aud, role) values (K,'e2e-k@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='K', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1980, city='台北市', status='approved' where id=K;
  for i in 1..11 loop
    T := gen_random_uuid();
    insert into auth.users (id, email, aud, role) values (T, 'e2e-t'||i||'@test.invalid','authenticated','authenticated');
    update public.profiles set nickname='T'||i, gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved' where id=T;
    perform set_config('request.jwt.claims', json_build_object('sub',K,'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', K::text, true);
    execute 'set local role authenticated';
    begin
      select public.send_first_message(T, '你好') into mid;
      if i = 1 then
        begin insert into public.messages (match_id, sender_id, body) values (mid, K, '再一則'); out := array_append(out, '21 對方回覆前傳第二則：沒被擋 ✗'::text);
        exception when others then out := array_append(out, '21 對方回覆前只能傳一則 ✓'::text); end;
      end if;
      if i = 11 then out := array_append(out, '21b 第 11 個新對話：沒被擋 ✗'::text); end if;
    exception when others then
      if i = 11 then out := array_append(out, ('21b 前 10 個用完後當天被擋 ✓ '||sqlerrm)::text);
      else out := array_append(out, ('21x 第 '||i||' 個對話失敗 ✗ '||sqlerrm)::text); end if;
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
    if i = 1 then
      -- 對方回覆後就能繼續
      perform set_config('request.jwt.claims', json_build_object('sub',T,'role','authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', T::text, true);
      execute 'set local role authenticated';
      insert into public.messages (match_id, sender_id, body) values (mid, T, '嗨');
      execute 'reset role';
      perform set_config('request.jwt.claims', json_build_object('sub',K,'role','authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', K::text, true);
      execute 'set local role authenticated';
      begin insert into public.messages (match_id, sender_id, body) values (mid, K, '謝謝回覆'); out := array_append(out, '21c 對方回覆後可以繼續聊 ✓'::text);
      exception when others then out := array_append(out, ('21c 對方回覆後仍不能傳 ✗ '||sqlerrm)::text); end;
      execute 'reset role';
      perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
    end if;
  end loop;
  -- 隔天只再開放 1 個
  update public.conversation_starts set created_at = created_at - interval '1 day' where user_id = K;
  for i in 1..2 loop
    T := gen_random_uuid();
    insert into auth.users (id, email, aud, role) values (T, 'e2e-u'||i||'@test.invalid','authenticated','authenticated');
    update public.profiles set nickname='U'||i, gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved' where id=T;
    perform set_config('request.jwt.claims', json_build_object('sub',K,'role','authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', K::text, true);
    execute 'set local role authenticated';
    begin perform public.send_first_message(T, '你好');
      out := array_append(out, (case when i=1 then '21e 隔天可以再開 1 個 ✓' else '21f 隔天第 2 個：沒被擋 ✗' end)::text);
    exception when others then
      out := array_append(out, (case when i=1 then '21e 隔天第 1 個被擋 ✗ '||sqlerrm else '21f 隔天只能開 1 個 ✓' end)::text);
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  end loop;

  -- 未審核帳號不能主動傳
  perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', C::text, true);
  execute 'set local role authenticated';
  begin perform public.send_first_message(K, 'hi'); out := array_append(out, '21d 未審核帳號主動傳訊息：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '21d 未審核帳號不能主動傳訊息 ✓'::text); end;
  execute 'reset role';

  -- 22 收件人保護：第一則內容、結束對話、只接受心動過的人、自己關掉重開
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users (id, email, aud, role) values (P,'e2e-p@test.invalid','authenticated','authenticated'),(Q,'e2e-q@test.invalid','authenticated','authenticated'),
    (R,'e2e-r@test.invalid','authenticated','authenticated'),(S2,'e2e-s@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='P', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1980, city='台北市', status='approved' where id=P;
  update public.profiles set nickname='Q', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved' where id in (Q,R,S2);
  update public.profiles set accept_from='liked' where id=R;
  perform set_config('request.jwt.claims', json_build_object('sub',P,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', P::text, true);
  execute 'set local role authenticated';
  begin perform public.send_first_message(Q, '加我 line 0912-345-678'); raise exception 'e2e_rollback';
  exception when others then out := array_append(out, (case when sqlerrm='e2e_rollback' then '22 第一則可以留聯絡方式（站長決定開放） ✓' else '22 第一則留聯絡方式被擋：'||sqlerrm||' ✗' end)::text); end;
  select public.send_first_message(Q, '你好，想認識你') into mid;
  begin perform public.send_first_message(R, '你好'); out := array_append(out, '22b 對方只收心動過的人：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '22b 對方只收心動過的人 ✓'::text); end;
  perform public.send_first_message(S2, '你好');
  perform public.unmatch((select id from public.matches where user_a=least(P,S2) and user_b=greatest(P,S2)));
  begin perform public.send_first_message(S2, '再試一次'); out := array_append(out, '22c 自己關掉再重開洗訊息：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '22c 對方沒回覆前不能自己關掉重開 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  perform public.unmatch(mid);   -- 不感興趣
  select count(*) into n from public.matches where id=mid; out := array_append(out, ('22d 結束的人看到對話 = '||n||' (應為0)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',P,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', P::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.messages where match_id=mid; out := array_append(out, ('22e 另一方仍可唯讀看到訊息 = '||n||' (應為1)')::text);
  begin perform public.send_first_message(Q, '為什麼不理我'); out := array_append(out, '22f 被結束後重開：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '22f 被對方結束後不能再開 ✓'::text); end;
  begin insert into public.messages (match_id, sender_id, body) values (mid, P, '還在嗎'); out := array_append(out, '22g 對已結束的對話傳訊：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '22g 已結束的對話不能傳訊 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 23 每月預算
  perform set_config('request.jwt.claims', json_build_object('sub',F,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', F::text, true);
  execute 'set local role authenticated';
  begin update public.profiles set budget = null where id=F; out := array_append(out, '23 Daddy 清空預算：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '23 Daddy 一定要有預算 ✓'::text); end;
  begin update public.profiles set budget = '一百萬' where id=F; out := array_append(out, '23b 預算亂填：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '23b 預算只能選清單 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 24 財力認證
  perform set_config('request.jwt.claims', json_build_object('sub',P,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', P::text, true);
  execute 'set local role authenticated';
  update public.profiles set wealth_verified_at = now() where id=P;
  select count(*) into n from public.profiles where id=P and wealth_verified_at is not null; out := array_append(out, ('24 自己標記財力認證 = '||n||' (應為0)')::text);
  insert into public.wealth_verifications (user_id, kind, path) values (P, 'deposit', P||'/123.jpg');
  begin insert into public.wealth_verifications (user_id, kind, path) values (P, 'income', P||'/124.jpg'); out := array_append(out, '24b 同時送兩份：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '24b 同時只能有一份待審 ✓'::text); end;
  begin update public.wealth_verifications set status='approved' where user_id=P; get diagnostics n = row_count; out := array_append(out, ('24c 自己核准 = '||n||' 筆 (應為0)')::text);
  exception when others then out := array_append(out, '24c 自己核准被擋 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.wealth_verifications; out := array_append(out, ('24d 別人看到財力文件紀錄 = '||n||' (應為0)')::text);
  begin insert into public.wealth_verifications (user_id, kind, path) values (Q, 'deposit', Q||'/1.jpg'); out := array_append(out, '24e 甜心申請財力認證：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '24e 財力認證只限 Daddy／Mommy ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 25 甜心申請查看財力文件
  update public.wealth_verifications set status='approved', reviewed_at=now() where user_id=P;
  update public.profiles set wealth_verified_at=now() where id=P;
  insert into storage.objects (bucket_id, name) values ('verify', P||'/123.jpg');
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  select state into v from public.wealth_doc_status(P); out := array_append(out, ('25 甜心看到的狀態 = '||v||' (應為can_request)')::text);
  select count(*) into n from storage.objects where bucket_id='verify' and name = P||'/123.jpg'; out := array_append(out, ('25b 未允許前讀到文件 = '||n||' (應為0)')::text);
  perform public.request_wealth_view(P);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',P,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', P::text, true);
  execute 'set local role authenticated';
  update public.wealth_requests set status='granted' where owner_id=P and requester_id=Q;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='verify' and name = P||'/123.jpg'; out := array_append(out, ('25c 允許後讀到文件 = '||n||' (應為1)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',R,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', R::text, true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id='verify' and name = P||'/123.jpg'; out := array_append(out, ('25d 沒被允許的人讀到文件 = '||n||' (應為0)')::text);
  begin update public.wealth_requests set status='granted' where owner_id=P; get diagnostics n = row_count; out := array_append(out, ('25e 別人替自己核准 = '||n||' 筆 (應為0)')::text);
  exception when others then out := array_append(out, '25e 別人替自己核准被擋 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 26 篩選欄位
  perform set_config('request.jwt.claims', json_build_object('sub',P,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', P::text, true);
  execute 'set local role authenticated';
  update public.profiles set body_type='athletic', cup='D', relation_types=array['dinner','travel'], meet_freq='monthly' where id=P;
  select coalesce(cup,'無') into v from public.profiles where id=P; out := array_append(out, ('26 男性罩杯 = '||v||' (應為無)')::text);
  begin update public.profiles set relation_types=array['sex'] where id=P; out := array_append(out, '26b 相處方式亂填：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '26b 相處方式只能選清單 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 27 新會員第一次審核通過前不能瀏覽
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  insert into auth.users (id, email, aud, role) values (Z,'e2e-z@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='Z', gender='female', looking_for='male', role='baby', birth_year=1999, city='台北市', status='pending' where id=Z;
  perform set_config('request.jwt.claims', json_build_object('sub',Z,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Z::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.profiles where id=P; out := array_append(out, ('27 新會員審核前看到其他會員 = '||n||' (應為0)')::text);
  select count(*) into n from public.photos where user_id<>Z; out := array_append(out, ('27b 新會員審核前看到別人照片 = '||n||' (應為0)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  update public.profiles set status='approved' where id=Z;
  perform set_config('request.jwt.claims', json_build_object('sub',Z,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Z::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.profiles where id=P; out := array_append(out, ('27c 通過後看到其他會員 = '||n||' (應為1)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 28 真人認證
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  update public.profiles set person_verified_at = now() where id=Q;
  select count(*) into n from public.profiles where id=Q and person_verified_at is not null; out := array_append(out, ('28 自己標記真人認證 = '||n||' (應為0)')::text);
  select (public.start_person_verification()).id into rid;
  begin perform public.submit_person_verification(rid, Q||'/1.jpg', Q||'/2.mp4'); out := array_append(out, '28b 沒上傳檔案就送出：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '28b 檔案沒上傳不能送出 ✓'::text); end;
  begin insert into public.person_verifications (user_id, photo_task, video_task, code) values (Q,'自選','自選','0000'); out := array_append(out, '28c 自己指定動作：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '28c 動作只能由系統指定 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',R,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', R::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.person_verifications; out := array_append(out, ('28d 別人看到真人認證資料 = '||n||' (應為0)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 29 新會員不能自己把 approved_at 填上來跳過審核
  insert into auth.users (id, email, aud, role) values (Y,'e2e-y@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='Y', gender='female', looking_for='male', role='baby', birth_year=1999, city='台北市', status='pending' where id=Y;
  perform set_config('request.jwt.claims', json_build_object('sub',Y,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Y::text, true);
  execute 'set local role authenticated';
  begin update public.profiles set approved_at = now(), submitted_at = '2000-01-01' where id=Y; exception when others then null; end;
  select count(*) into n from public.profiles where id=P; out := array_append(out, ('29b 自己改完後看到其他會員 = '||n||' (應為0)')::text);
  execute 'reset role';
  select count(*) into n from public.profiles where id=Y and (approved_at is not null or submitted_at < '2001-01-01'); out := array_append(out, ('29 自己填 approved_at / submitted_at = '||n||' (應為0)')::text);
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 30 客服留言：只有自己和管理員看得到，不能冒名
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  insert into public.support_tickets (user_id, email, body, status) values (R, 'fake@x.com', '我需要協助處理帳號', 'done');
  select count(*) into n from public.support_tickets where user_id=Q and email='e2e-q@test.invalid' and status='open'; out := array_append(out, ('30 客服留言自動帶入本人資料 = '||n||' (應為1)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',R,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', R::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.support_tickets; out := array_append(out, ('30b 別人看到客服留言 = '||n||' (應為0)')::text);
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 31 暱稱送審後不能改
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  update public.profiles set nickname='改名了' where id=Q;
  execute 'reset role';
  select nickname into v from public.profiles where id=Q; out := array_append(out, ('31 上架後改暱稱 = '||v||' (應為Q)')::text);
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 32 創始會員編號：自己不能改，第一次通過審核時由系統給
  perform set_config('request.jwt.claims', json_build_object('sub',Q,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', Q::text, true);
  execute 'set local role authenticated';
  begin update public.profiles set founder_no = 99999 where id=Q; exception when others then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from public.profiles where id=Q and founder_no = 99999; out := array_append(out, ('32 自己填創始會員編號 = '||n||' (應為0)')::text);
  update public.profiles set status='approved' where id=Y;
  select count(*) into n from public.profiles where id=Y and founder_no is not null; out := array_append(out, ('32b 第一次通過審核拿到創始編號 = '||n||' (應為1)')::text);
  select count(*) into n from public.profiles where id=Y and founder_boost_until > now() + interval '50 days'; out := array_append(out, ('32c 甜心創始會員有優先曝光期 = '||n||' (應為1)')::text);

  -- 33 免費開站期：主動開新對話不限次數
  update public.app_config set value='on' where key='free_launch';
  perform set_config('request.jwt.claims', json_build_object('sub',K,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', K::text, true);
  execute 'set local role authenticated';
  select public.my_start_quota() into n; out := array_append(out, ('33 免費開站期的新對話額度 = '||n||' (應為999)')::text);
  begin update public.app_config set value='off' where key='free_launch'; exception when others then null; end;
  execute 'reset role';
  select count(*) into n from public.app_config where key='free_launch' and value='on'; out := array_append(out, ('33b 會員自己關掉免費期 = '||(1-n)||' (應為0)')::text);
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);

  -- 34 v0.26：不能檢舉自己；管理員用一般登入身分核准會員要成功（觸發器以定義者權限執行）
  insert into auth.users (id, email, aud, role) values (AD,'e2e-ad@test.invalid','authenticated','authenticated'),(W,'e2e-w@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='AD', is_admin=true, status='approved' where id=AD;
  update public.profiles set nickname='W', gender='female', looking_for='male', role='baby', birth_year=1999, city='台北市', status='pending' where id=W;
  perform set_config('request.jwt.claims', json_build_object('sub',K,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', K::text, true);
  execute 'set local role authenticated';
  begin insert into public.reports (reporter_id, reported_id, reason) values (K, K, 'other'); out := array_append(out, '34 檢舉自己：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '34 不能檢舉自己 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',AD,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', AD::text, true);
  execute 'set local role authenticated';
  begin update public.profiles set status='approved' where id=W; exception when others then out := array_append(out, ('34b 管理員核准時出錯：'||sqlerrm||' ✗')::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from public.profiles where id=W and status='approved' and approved_at is not null; out := array_append(out, ('34c 管理員核准成功 = '||n||' (應為1)')::text);
  update public.profiles set status='suspended' where id=W; update public.profiles set status='pending' where id=W;
  select count(*) into n from public.profiles where id=W and approved_at is null; out := array_append(out, ('34d 解除停權後要重新審核 = '||n||' (應為1)')::text);

  -- 35 v0.27 聊天照片與收回
  insert into auth.users (id, email, aud, role) values (X1,'e2e-x1@test.invalid','authenticated','authenticated'),(X2,'e2e-x2@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='X1', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1985, city='台北市', status='approved' where id=X1;
  update public.profiles set nickname='X2', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved' where id=X2;
  insert into public.matches (user_a, user_b, initiator, replied_at) values (least(X1,X2), greatest(X1,X2), X1, now()) returning id into cm;
  perform set_config('request.jwt.claims', json_build_object('sub',X1,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', X1::text, true);
  execute 'set local role authenticated';
  begin insert into public.messages (match_id, sender_id, body, image_path) values (cm, X1, '', X2||'/'||cm||'-1.jpg'); out := array_append(out, '35 用別人的路徑傳照片：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '35 照片路徑必須是自己的 ✓'::text); end;
  insert into public.messages (match_id, sender_id, body, image_path) values (cm, X1, '', X1||'/'||cm||'-1.jpg') returning id into m1;
  insert into public.messages (match_id, sender_id, body) values (cm, X1, '想收回的話') returning id into m2;
  update public.messages set recalled_at = now() where id in (m1, m2);
  execute 'reset role';
  select count(*) into n from public.messages where id in (m1,m2) and recalled_at is not null and body = '' and image_path is null; out := array_append(out, ('35b 寄件人收回後內容清空 = '||n||' (應為2)')::text);
  select count(*) into n from public.message_recalls where message_id in (m1,m2) and (body='想收回的話' or image_path is not null); out := array_append(out, ('35e 收回的原內容有備份給管理員 = '||n||' (應為2)')::text);
  select count(*) into n from public.matches where id=cm and last_message='訊息已收回'; out := array_append(out, ('35c 收回最後一則後預覽更新 = '||n||' (應為1)')::text);
  insert into public.messages (match_id, sender_id, body) values (cm, X1, '對方不能收回我的訊息') returning id into m2;
  perform set_config('request.jwt.claims', json_build_object('sub',X2,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', X2::text, true);
  execute 'set local role authenticated';
  update public.messages set recalled_at = now(), body = 'x' where id = m2;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from public.messages where id=m2 and recalled_at is null and body='對方不能收回我的訊息';
  perform set_config('request.jwt.claims', json_build_object('sub',X1,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', X1::text, true);
  execute 'set local role authenticated';
  begin select count(*) into n from public.message_recalls; out := array_append(out, '35f 會員讀到收回備份：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '35f 會員讀不到收回備份 ✓'::text); end;
  begin perform public.admin_messages(cm); out := array_append(out, '35g 會員呼叫管理員對話檢視：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '35g 只有管理員能看所有對話 ✓'::text); end;
  begin perform public.admin_contacts(array[X2]); out := array_append(out, '35h 會員查別人 Email／手機：沒被擋 ✗'::text);
  exception when others then out := array_append(out, '35h 只有管理員能看 Email／手機 ✓'::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true); out := array_append(out, ('35d 對方無法收回或改我的訊息 = '||n||' (應為1)')::text);

  -- 36 v0.29：對方回覆前不能收回第一則；被檢舉人刪帳號後檢舉與證據保留
  update public.matches set closed_at = now() where id = cm;
  insert into public.matches (user_a, user_b, initiator) values (least(X2,AD), greatest(X2,AD), X2) returning id into cm2;
  update public.profiles set gender='male', looking_for='female' where id=AD;
  perform set_config('request.jwt.claims', json_build_object('sub',X2,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', X2::text, true);
  execute 'set local role authenticated';
  insert into public.messages (match_id, sender_id, body) values (cm2, X2, '第一則') returning id into m1;
  begin update public.messages set recalled_at = now() where id = m1; exception when others then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claims','',true); perform set_config('request.jwt.claim.sub','',true);
  select count(*) into n from public.messages where id=m1 and recalled_at is null; out := array_append(out, ('36 對方回覆前收回第一則被擋 = '||n||' (應為1)')::text);
  insert into public.reports (reporter_id, reported_id, reason) values (X1, X2, 'harass') returning id into rid2;
  delete from auth.users where id = X2;
  select count(*) into n from public.reports where id=rid2 and reported_id is null and reported_nickname='X2'; out := array_append(out, ('36b 被檢舉人刪帳號後檢舉仍保留 = '||n||' (應為1)')::text);
  select count(*) into n from public.report_evidence where report_id=rid2; out := array_append(out, ('36c 檢舉證據含照片與收回原文 = '||n||' (應為4)')::text);

  raise exception E'E2E 結果（已全部回滾）:\n%', array_to_string(out, E'\n');
end $t$;
