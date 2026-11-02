-- Synthetic terminal accounts and cards only; everything rolls back.
begin;
do $test$
declare
  v_operator_id uuid := gen_random_uuid();
  v_second_operator_id uuid := gen_random_uuid();
  v_student_id uuid := gen_random_uuid();
  v_no_access_id uuid := gen_random_uuid();
  level_id uuid;
  v_subject_id uuid := gen_random_uuid();
  period_id uuid;
  v_admin_uid text := rtrim(regexp_replace(upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 14)), '(..)', '\1:', 'g'), ':');
  v_student_uid text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 14));
  v_inactive_uid text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 14));
  v_token uuid;
  v_legacy_token uuid;
  v_expired_ticket uuid;
  v_payload jsonb;
  was_blocked boolean;
  v_before_tickets bigint;
  v_after_tickets bigint;
  v_event_count integer;
begin
  insert into auth.users(id, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at)
  values
    (v_operator_id, 'qa-terminal-' || v_operator_id || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Terminal Operator"}', now()),
    (v_second_operator_id, 'qa-terminal-' || v_second_operator_id || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Second Operator"}', now()),
    (v_student_id, 'qa-terminal-' || v_student_id || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Terminal Student"}', now()),
    (v_no_access_id, 'qa-terminal-' || v_no_access_id || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA No Access"}', now());

  update public.profiles set role_id = (select id from public.roles where name = 'admin') where id = v_operator_id;
  update public.profiles set role_id = (select id from public.roles where name = 'rector') where id = v_second_operator_id;
  update public.profiles set role_id = (select id from public.roles where name = 'estudiante') where id in (v_student_id, v_no_access_id);

  insert into public.nfc_cards(profile_id, card_uid, card_type, active)
  values (v_operator_id, v_admin_uid, 'admin', true),
         (v_student_id, v_student_uid, 'estudiante', true),
         (v_student_id, v_inactive_uid, 'estudiante', false);

  select id into level_id from public.school_levels order by order_index limit 1;
  select id into period_id from public.grade_periods order by order_index limit 1;
  if level_id is null or period_id is null then
    raise exception 'terminal test needs seeded school levels and grade periods';
  end if;
  insert into public.student_details(profile_id, level_id) values (v_student_id, level_id);
  insert into public.subjects(id, name, code, level_id)
  values (v_subject_id, 'QA Terminal Subject', 'QA-' || substr(replace(v_subject_id::text, '-', ''), 1, 10), level_id);
  insert into public.grades(student_id, subject_id, period_id, score)
  values (v_student_id, v_subject_id, period_id, 8.75);

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_no_access_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  was_blocked := false;
  begin
    perform public.terminal_scan(v_admin_uid);
  exception when insufficient_privilege then
    was_blocked := sqlerrm = 'forbidden';
  end;
  if not was_blocked then raise exception 'terminal_scan accepted a user without terminal.operate'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_operator_id, 'role', 'authenticated')::text, true);
  v_payload := public.terminal_scan(v_admin_uid);
  if v_payload->>'kind' <> 'admin' or nullif(v_payload->>'ticket', '') is null then
    raise exception 'admin scan did not return an admin ticket';
  end if;
  if v_payload ? 'profile' or v_payload ? 'grades' then raise exception 'admin scan returned profile or grades'; end if;
  v_token := (v_payload->>'ticket')::uuid;
  if (v_payload->>'pin_set')::boolean or (v_payload->>'pin_ok')::boolean then raise exception 'new admin should have no pin'; end if;
  if public.consume_terminal_unlock(v_token) then raise exception 'ticket without PIN unlocked the terminal'; end if;
  if (public.terminal_pin_set(v_token, '482913')->>'ok')::boolean is not true then raise exception 'could not set PIN'; end if;

  v_legacy_token := public.authorize_terminal_card(v_admin_uid);
  reset role;
  if not exists (
    select 1 from public.terminal_unlock_tickets t
    where t.id = v_legacy_token and t.card_profile_id = v_operator_id
  ) then raise exception 'authorize_terminal_card did not save the card owner'; end if;
  select count(*) into v_before_tickets from public.terminal_unlock_tickets t where t.operator_id = v_operator_id;
  set local role authenticated;
  v_payload := public.terminal_scan(v_student_uid);
  reset role;
  select count(*) into v_after_tickets from public.terminal_unlock_tickets t where t.operator_id = v_operator_id;
  if v_payload->>'kind' <> 'person' or v_payload#>>'{profile,id}' <> v_student_id::text then
    raise exception 'student scan did not return the expected profile';
  end if;
  if jsonb_array_length(v_payload#>'{profile,grades}') = 0 then raise exception 'student profile is missing grades'; end if;
  if v_before_tickets <> v_after_tickets then raise exception 'student scan created an unlock ticket'; end if;
  if not exists (
    select 1 from public.terminal_profile_access a
    where a.operator_id = v_operator_id and a.student_id = v_student_id
      and a.expires_at > now() + interval '110 seconds'
      and a.expires_at < now() + interval '130 seconds'
  ) then raise exception 'student photo access is not valid for about two minutes'; end if;

  set local role authenticated;
  was_blocked := false;
  begin
    perform public.terminal_scan(v_inactive_uid);
  exception when raise_exception then
    was_blocked := sqlerrm = 'invalid_card';
  end;
  if not was_blocked then raise exception 'inactive card was accepted'; end if;
  was_blocked := false;
  begin
    perform public.terminal_scan('F00DBAAD01234');
  exception when raise_exception then
    was_blocked := sqlerrm = 'invalid_card';
  end;
  if not was_blocked then raise exception 'unknown card was accepted'; end if;

  reset role;
  set local role anon;
  if not public.consume_terminal_unlock(v_token) then raise exception 'valid terminal ticket was rejected'; end if;
  if public.consume_terminal_unlock(v_token) then raise exception 'terminal ticket was reusable'; end if;
  reset role;
  select count(*) into v_event_count from public.terminal_events e where e.event = 'unlock' and e.actor_id = v_operator_id;
  set local role authenticated;
  if v_event_count <> 1 then raise exception 'unlock did not create exactly one event with its card owner'; end if;

  was_blocked := false;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_second_operator_id, 'role', 'authenticated')::text, true);
  begin
    perform public.log_terminal_event(v_token, 'mode_changed', '{"mode":"profile"}'::jsonb);
  exception when insufficient_privilege then
    was_blocked := sqlerrm = 'invalid_ticket';
  end;
  if not was_blocked then raise exception 'event log accepted another operator ticket'; end if;

  reset role;
  insert into public.terminal_unlock_tickets(operator_id, card_profile_id, expires_at)
  values (v_operator_id, v_operator_id, now() - interval '16 minutes') returning id into v_expired_ticket;
  set local role authenticated;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_operator_id, 'role', 'authenticated')::text, true);
  was_blocked := false;
  begin
    perform public.log_terminal_event(v_expired_ticket, 'mode_changed', '{}'::jsonb);
  exception when insufficient_privilege then
    was_blocked := sqlerrm = 'invalid_ticket';
  end;
  if not was_blocked then raise exception 'event log accepted a ticket older than 15 minutes'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_student_id, 'role', 'authenticated')::text, true);
  was_blocked := false;
  begin
    perform * from public.list_terminal_events(100);
  exception when insufficient_privilege then
    was_blocked := sqlerrm = 'forbidden';
  end;
  if not was_blocked then raise exception 'event list accepted a user without users.manage'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_operator_id, 'role', 'authenticated')::text, true);
  if not exists (
    select 1 from public.list_terminal_events(100) e
    where e.event = 'admin_card' and e.actor_name = 'QA Terminal Operator'
  ) then raise exception 'authorized event list did not return the admin scan'; end if;
  reset role;
  if exists (
    select 1 from public.terminal_events e
    where e.detail::text like '%' || v_admin_uid || '%'
       or e.detail::text like '%' || v_student_uid || '%'
       or e.detail::text ilike '%private student note%'
       or e.detail::text ilike '%grades%'
       or e.detail::text ilike '%score%'
  ) then raise exception 'terminal activity contains a card UID or note'; end if;
  if (select count(*) from public.terminal_events where event = 'admin_card') <> 1 then
    raise exception 'student profile lookup was logged';
  end if;
end
$test$;
rollback;
select 'Passed terminal scan, privacy, ticket, activity and permission checks. All synthetic data rolled back.' as result;
