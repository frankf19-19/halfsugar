-- 討論區分區測試：全部在一個交易裡，最後丟出例外讓一切回滾（不留下任何資料）
do $t$
declare M uuid := gen_random_uuid(); F uuid := gen_random_uuid(); out text[] := '{}'; pf bigint;
begin
  insert into auth.users (id, email, aud, role) values (M,'a-m@test.invalid','authenticated','authenticated'),(F,'a-f@test.invalid','authenticated','authenticated');
  update public.profiles set nickname='AM', gender='male', looking_for='female', role='daddy', birth_year=1985, city='台北市', status='approved', approved_at=now(), age_confirmed=true, agreed_terms_at=now() where id=M;
  update public.profiles set nickname='AF', gender='female', looking_for='male', role='baby', birth_year=1996, city='台北市', status='approved', approved_at=now(), age_confirmed=true, agreed_terms_at=now() where id=F;
  perform set_config('request.jwt.claim.sub', F::text, true); execute 'set local role authenticated';
  pf := public.forum_post('qa','女生專區測試','只有女生看得到的內容', 2::smallint, 'female');
  begin perform public.forum_post('qa','發到男生區','不應該可以發到男生區', 2::smallint, 'male'); out := array_append(out, 'FAIL female posted to male'); exception when others then out := array_append(out, 'ok female cannot post to male'); end;
  out := array_append(out, format('female sees own area: %s', jsonb_array_length(public.forum_list(p_audience=>'female')) >= 1));
  execute 'reset role'; perform set_config('request.jwt.claim.sub', M::text, true); execute 'set local role authenticated';
  begin perform public.forum_list(p_audience=>'female'); out := array_append(out, 'FAIL male read female area'); exception when others then out := array_append(out, 'ok male blocked from female area'); end;
  begin perform public.forum_get(pf); out := array_append(out, 'FAIL male opened female post'); exception when others then out := array_append(out, 'ok male cannot open female post'); end;
  out := array_append(out, format('female post in male general list: %s', exists (select 1 from jsonb_array_elements(public.forum_list()) x where (x->>'id')::bigint = pf)));
  execute 'reset role';
  raise exception 'AREA_TEST_RESULT %', array_to_string(out, ' || ');
end $t$;
