-- v0.67 權限測試：全部在交易裡，最後丟例外回滾（不留資料）
do $t$
declare
  A uuid := gen_random_uuid(); B uuid := gen_random_uuid(); C uuid := gen_random_uuid(); D uuid := gen_random_uuid(); E uuid := gen_random_uuid();
  out text[] := '{}'; n int; v text; ok boolean; mid uuid; msg bigint; r record; j jsonb;
begin
  insert into auth.users (id, email, aud, role) values
    (A,'t67-a@test.invalid','authenticated','authenticated'),(B,'t67-b@test.invalid','authenticated','authenticated'),
    (C,'t67-c@test.invalid','authenticated','authenticated'),(D,'t67-d@test.invalid','authenticated','authenticated'),(E,'t67-e@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='A', gender='male', looking_for='female', role='daddy', budget='50to80k', birth_year=1985, city='台北市', status='approved', avatar_path=A||'/av.jpg', body_type='fit', bio='hi', age_confirmed=true, agreed_terms_at=now() where id=A;
  update public.profiles set nickname='B', gender='female', looking_for='male', role='baby', birth_year=1998, city='台北市', status='approved', avatar_path=B||'/av.jpg', body_type='slim', bio='hi', age_confirmed=true, agreed_terms_at=now() where id=B;
  update public.profiles set gender='female', looking_for='male' where id=C;
  update public.profiles set nickname='D', gender='female', looking_for='male', role='baby', birth_year=1997, city='台北市', status='approved', hidden=true where id=D;
  update public.profiles set nickname='E', gender='male', looking_for='male', role='daddy', budget='50to80k', birth_year=1980, city='台北市', status='approved' where id=E;
  select approved_prompts::text into v from public.profiles where id=A; out := array_append(out, (('0 新帳號 approved_prompts = '||coalesce(v,'null')))::text);

  -- A：悄悄心動 B
  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  ok := public.secret_like(B, true); out := array_append(out, (('1 A 悄悄心動 B，回傳互相 = '||ok||' (應為false)'))::text);
  select count(*) into n from public.my_secret_likes() where mutual; out := array_append(out, (('1b A 的互相數 = '||n||' (應為0)'))::text);
  begin perform public.secret_like(E, true); out := array_append(out, ('2 A 悄悄心動方向不合的 E：沒被擋 ✗'::text)::text); exception when others then out := array_append(out, (('2 方向不合被擋 ✓'))::text); end;
  begin perform public.secret_like(D, true); out := array_append(out, ('2b 悄悄心動隱身 D：沒被擋 ✗'::text)::text); exception when others then out := array_append(out, (('2b 隱身被擋 ✓'))::text); end;
  begin select count(*) into n from public.secret_likes; out := array_append(out, (('2c 直接讀 secret_likes 沒被擋 ✗ '||n))::text); exception when others then out := array_append(out, (('2c 直接讀資料表被擋 ✓'))::text); end;
  -- 破冰問答
  update public.profiles set prompts='[{"q":0,"a":"  安靜的小酒館  "},{"q":"x","a":"bad"},{"q":3,"a":""}]'::jsonb, approved_prompts='[{"q":1,"a":"hack"}]'::jsonb where id=A;
  execute 'reset role';
  select status, prompts::text, coalesce(approved_prompts::text,'null') into r from public.profiles where id=A;
  out := array_append(out, (('3 A 改問答後 status='||r.status||' prompts='||r.prompts||' approved='||r.coalesce||' (應為 pending、只剩1題且去空白、approved 不變)'))::text);
  execute 'set local role authenticated';
  begin update public.profiles set prompts='[{"q":0,"a":"a"},{"q":1,"a":"b"},{"q":2,"a":"c"},{"q":3,"a":"d"}]'::jsonb where id=A; out := array_append(out, ('4 4題沒被擋 ✗'::text)::text); exception when others then out := array_append(out, (('4 超過3題被擋 ✓ '||sqlerrm))::text); end;
  begin update public.profiles set date_type='X' where id=A; out := array_append(out, ('5 date_type=X 沒被擋 ✗'::text)::text); exception when others then out := array_append(out, (('5 錯誤的約會暗號被擋 ✓'))::text); end;
  update public.profiles set date_type='B' where id=A;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
  update public.profiles set status='approved' where id=A;   -- 管理員通過
  select approved_prompts::text into v from public.profiles where id=A; out := array_append(out, (('6 通過後 approved_prompts = '||v))::text);

  -- B：看不到 A 的悄悄心動；回按後互相
  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.my_secret_likes(); out := array_append(out, (('7 B 的悄悄心動名單 = '||n||' (應為0，看不到 A 按了)'))::text);
  select date_type into v from public.profiles where id=A; out := array_append(out, (('7b B 看 A 的約會暗號 = '||coalesce(v,'null')))::text);
  ok := public.secret_like(A, true); out := array_append(out, (('8 B 回按 A，互相 = '||ok||' (應為true)'))::text);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.my_secret_likes() where mutual; out := array_append(out, (('9 A 的互相數 = '||n||' (應為1)'))::text);
  execute 'reset role';

  -- C（未完成）不能悄悄心動
  perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', C::text, true);
  execute 'set local role authenticated';
  begin perform public.secret_like(B, true); out := array_append(out, ('10 未審核 C 悄悄心動沒被擋 ✗'::text)::text); exception when others then out := array_append(out, (('10 未審核被擋 ✓'))::text); end;
  execute 'reset role';

  -- 二選一
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
  insert into public.matches (user_a, user_b, initiator) values (least(A,B), greatest(A,B), A) returning id into mid;
  insert into public.messages (match_id, sender_id, body) values (mid, A, '🎲 二選一｜海邊 還是 山上？') returning id into msg;
  perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', A::text, true);
  execute 'set local role authenticated';
  select * into r from public.chat_pick(msg, 0::smallint); out := array_append(out, (('11 A 選 0：mine='||r.mine||' their_done='||r.their_done||' theirs='||coalesce(r.theirs::text,'null')))::text);
  select * into r from public.chat_pick(msg, 1::smallint); out := array_append(out, (('11b A 改選 1 無效：mine='||r.mine||' (應為0)'))::text);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', B::text, true);
  execute 'set local role authenticated';
  select * into r from public.chat_pick_state(array[msg]); out := array_append(out, (('12 B 還沒選：their_done='||r.their_done||' theirs='||coalesce(r.theirs::text,'null')||' (應為 true、null 看不到答案)'))::text);
  select * into r from public.chat_pick(msg, 0::smallint); out := array_append(out, (('13 B 選 0 後：theirs='||coalesce(r.theirs::text,'null')||' (應為0)'))::text);
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true); perform set_config('request.jwt.claim.sub', C::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.chat_pick_state(array[msg]); out := array_append(out, (('14 局外人 C 看狀態 = '||n||' (應為0)'))::text);
  begin perform public.chat_pick(msg, 1::smallint); out := array_append(out, ('14b 局外人作答沒被擋 ✗'::text)::text); exception when others then out := array_append(out, (('14b 局外人作答被擋 ✓'))::text); end;
  execute 'reset role';
  raise exception E'TEST_RESULT\n%', array_to_string(out, E'\n');
end $t$;
