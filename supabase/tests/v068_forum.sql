-- 討論區權限測試：全部在一個交易裡，最後丟出例外讓一切回滾（不留下任何資料）
do $t$
declare A uuid := gen_random_uuid(); B uuid := gen_random_uuid(); C uuid := gen_random_uuid(); D uuid := gen_random_uuid();
  out text[] := '{}'; p1 bigint; p2 bigint; j jsonb; e text;
begin
  insert into auth.users (id, email, aud, role) values (A,'f-a@test.invalid','authenticated','authenticated'),(B,'f-b@test.invalid','authenticated','authenticated'),(C,'f-c@test.invalid','authenticated','authenticated'),(D,'f-d@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='FA', gender='male', looking_for='female', role='daddy', birth_year=1985, city='台北市', status='approved', approved_at=now(), age_confirmed=true, agreed_terms_at=now() where id=A;
  update public.profiles set nickname='FB', gender='female', looking_for='male', role='baby', birth_year=1996, city='台北市', status='approved', approved_at=now(), age_confirmed=true, agreed_terms_at=now() where id in (B,C);
  update public.profiles set nickname='FD', gender='female', looking_for='male', role='baby', birth_year=1996, city='台北市', status='pending', approved_at=null where id=D;
  perform set_config('request.jwt.claim.sub', A::text, true); perform set_config('request.jwt.claims', json_build_object('sub',A,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  p1 := public.forum_post('qa','測試匿名文章','這是一篇完全匿名的測試內容', 2::smallint);
  p2 := public.forum_post('date','測試具名文章','這是一篇具名的測試內容喔', 0::smallint);
  begin perform public.forum_post('chat','聯絡','加line abc12345 喔', 0::smallint); out := array_append(out, ('FAIL contact allowed')::text); exception when others then out := array_append(out, (('ok contact blocked: '||sqlerrm))::text); end;
  begin perform count(*) from public.forum_posts; out := array_append(out, ('FAIL table readable')::text); exception when others then out := array_append(out, ('ok table not readable')::text); end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', B::text, true); perform set_config('request.jwt.claims', json_build_object('sub',B,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.forum_comment(p1, 'B 匿名留言', 2::smallint);
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', C::text, true); perform set_config('request.jwt.claims', json_build_object('sub',C,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.forum_comment(p1, 'C 匿名留言', 1::smallint);
  j := public.forum_get(p1);
  out := array_append(out, (format('anon post author leaked to C: %s', position(A::text in j::text) > 0))::text);
  out := array_append(out, (format('B leaked to C: %s', position(B::text in j::text) > 0))::text);
  out := array_append(out, (format('names: %s', (select string_agg(x->>'name', ' / ') from jsonb_array_elements(j->'comments') x)))::text);
  out := array_append(out, (format('list leaks A on anon post: %s', exists (select 1 from jsonb_array_elements(public.forum_list()) x where (x->>'id')::bigint = p1 and x::text like '%'||A::text||'%')))::text);
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', D::text, true); perform set_config('request.jwt.claims', json_build_object('sub',D,'role','authenticated')::text, true);
  execute 'set local role authenticated';
  begin perform public.forum_list(); out := array_append(out, ('FAIL pending can read')::text); exception when others then out := array_append(out, ('ok pending blocked')::text); end;
  execute 'reset role';
  raise exception 'FORUM_TEST_RESULT %', array_to_string(out, ' || ');
end $t$;
