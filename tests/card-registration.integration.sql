-- Registro de tarjetas solo para administradores + activación de cuenta con código de 24 h.
-- Usa cuentas sintéticas; todo se revierte al final (rollback).
begin;
do $test$
declare
  v_admin uuid := gen_random_uuid();
  v_rector uuid := gen_random_uuid();
  v_student uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_plain uuid := gen_random_uuid();
  v_admin_uid1 text := '04:A1:B2:C3:D4:E5:01';
  v_admin_uid2 text := '04:A1:B2:C3:D4:E5:02';
  v_uid1 text := '04:11:22:33:44:55:01';
  v_uid2 text := '04:11:22:33:44:55:02';
  v_uid3 text := '04:11:22:33:44:55:03';
  v_ok boolean;
  v_json jsonb;
  v_code text;
  v_code2 text;
  v_level uuid;
  v_n int;
  v_t1 uuid;
  v_t2 uuid;
  v_t3 uuid;
begin
  insert into auth.users(id, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at) values
    (v_admin,  'qa-admin-'  || v_admin  || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Admin"}', now()),
    (v_rector, 'qa-rector-' || v_rector || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Rector"}', now()),
    (v_other,  'qa-other-'  || v_other  || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Otro Estudiante"}', now()),
    (v_plain,  'qa-plain-'  || v_plain  || '@example.invalid', '{"provider":"email"}', '{"full_name":"QA Sin Permisos"}', now()),
    -- Cuenta pendiente, como la crea la Edge Function terminal-register-card
    (v_student, 'pendiente-' || replace(v_student::text, '-', '') || '@pendiente.frederick.invalid',
      '{"provider":"email","provisioned":true,"role":"estudiante"}', '{"full_name":"QA Alumno Nuevo"}', now());
  update public.profiles set role_id = (select id from public.roles where name = 'admin')      where id = v_admin;
  update public.profiles set role_id = (select id from public.roles where name = 'rector')     where id = v_rector;
  update public.profiles set role_id = (select id from public.roles where name = 'estudiante') where id in (v_other, v_plain, v_student);
  select id into v_level from public.school_levels order by order_index limit 1;
  insert into public.nfc_cards(card_uid, profile_id, card_type, active) values (v_admin_uid1, v_admin, 'admin', true);

  -- 0. Permiso y funciones auxiliares
  if not exists (select 1 from public.role_permissions where permission_code = 'cards.register'
                 and role_id = (select id from public.roles where name = 'admin')) then
    raise exception 'admin lacks cards.register';
  end if;
  if exists (select 1 from public.role_permissions where permission_code = 'cards.register'
             and role_id <> (select id from public.roles where name = 'admin')) then
    raise exception 'cards.register granted to a non-admin role';
  end if;

  -- 1. Solo el administrador registra; el rector (nfc.manage) ya no
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_rector, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if public.can_register_cards() then raise exception 'rector can register cards'; end if;
  foreach v_code in array array['assign', 'search', 'block'] loop
    v_ok := false;
    begin
      if v_code = 'assign' then perform public.terminal_assign_card(v_uid1, v_other, false);
      elsif v_code = 'search' then perform * from public.terminal_search_people('qa');
      else perform public.set_card_active(gen_random_uuid(), false); end if;
    exception when insufficient_privilege then v_ok := sqlerrm = 'forbidden'; end;
    if not v_ok then raise exception 'rector was not blocked from %', v_code; end if;
  end loop;
  v_ok := false;
  begin
    insert into public.nfc_cards(card_uid, profile_id, card_type) values ('04:99:99:99:99:99:99', v_other, 'estudiante');
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'authenticated can still write nfc_cards directly'; end if;
  v_ok := false;
  begin
    perform public.save_nfc_card_binding(null, '04:98:98:98:98:98:98', v_other, 'estudiante', '', true);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'save_nfc_card_binding is still callable'; end if;
  reset role;

  -- 2. Registro de persona nueva (Edge Function con service_role)
  set local role service_role;
  v_json := public.card_registration_precheck('04-11-22-33-44-55-01');
  if (v_json->>'taken')::boolean or v_json->>'uid' <> v_uid1 then raise exception 'precheck wrong: %', v_json; end if;
  perform public.finalize_card_registration(v_admin, v_student, v_uid1, '  QA Alumno Nuevo  ', v_level);
  v_ok := false;
  begin perform public.finalize_card_registration(v_admin, v_other, v_uid1, 'QA Duplicada', null);
  exception when raise_exception then v_ok := sqlerrm = 'card_already_assigned'; end;
  if not v_ok then raise exception 'duplicate card accepted'; end if;
  v_json := public.card_registration_precheck(v_uid1);
  if not (v_json->>'taken')::boolean or v_json->>'owner_name' <> 'QA Alumno Nuevo' then raise exception 'precheck owner wrong'; end if;
  reset role;
  if not exists (select 1 from public.profiles where id = v_student and activation_pending and full_name = 'QA Alumno Nuevo') then
    raise exception 'profile not pending after registration';
  end if;
  if not exists (select 1 from public.student_details where profile_id = v_student and level_id = v_level) then
    raise exception 'level not stored';
  end if;
  if not exists (select 1 from public.nfc_cards where card_uid = v_uid1 and profile_id = v_student and card_type = 'estudiante' and active and registered_by = v_admin) then
    raise exception 'card not stored correctly';
  end if;
  v_ok := false;
  set local role anon;
  begin perform public.finalize_card_registration(v_admin, v_other, v_uid3, 'X Y', null);
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  if not v_ok then raise exception 'anon can call finalize_card_registration'; end if;

  -- 3. El perfil del terminal avisa que falta activar; el código se pide con la tarjeta
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_json := public.terminal_scan(v_uid1);
  if (v_json#>>'{profile,activation_pending}')::boolean is not true then raise exception 'payload lacks activation_pending'; end if;
  v_json := public.terminal_issue_activation_code(v_uid1);
  v_code := v_json->>'code';
  if v_code !~ '^[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$' then raise exception 'bad code format: %', v_code; end if;
  if (v_json->>'expires_at')::timestamptz < now() + interval '23 hours 59 minutes'
     or (v_json->>'expires_at')::timestamptz > now() + interval '24 hours 1 minute' then
    raise exception 'code is not valid for 24 hours';
  end if;
  v_json := public.terminal_issue_activation_code(v_uid1);
  v_code2 := v_json->>'code';
  reset role;
  select count(*) into v_n from public.account_activation_codes where profile_id = v_student;
  if v_n <> 1 then raise exception 'expected one code row, got %', v_n; end if;
  if exists (select 1 from public.account_activation_codes where code_hash like v_code || '%') then raise exception 'plain code stored'; end if;

  set local role service_role;
  if v_code <> v_code2 and public.activation_lookup(v_code) is not null then raise exception 'old code still valid after reissue'; end if;
  if public.activation_lookup(lower(replace(v_code2, '-', ' '))) is distinct from v_student then raise exception 'lookup failed for normalized code'; end if;
  if public.activation_lookup('ZZZZ-ZZZZ') is not null then raise exception 'random code accepted'; end if;
  reset role;
  update public.account_activation_codes set expires_at = now() - interval '1 second' where profile_id = v_student;
  set local role service_role;
  if public.activation_lookup(v_code2) is not null then raise exception 'expired code accepted'; end if;
  reset role;
  update public.account_activation_codes set expires_at = now() + interval '1 hour' where profile_id = v_student;

  -- Una tarjeta ajena o desconocida no da código; un usuario sin permiso tampoco
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_plain, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_ok := false;
  begin perform public.terminal_issue_activation_code(v_uid1);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'user without terminal.operate got a code'; end if;
  reset role;

  -- 4. Directorio para la web (rector lo ve, sin UID completo ni correo provisional)
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_rector, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.list_card_directory() d
   where d.profile_id = v_student and d.email is null and d.activation_pending and d.code_valid
     and d.card_hint = '••' || right(v_uid1, 5) and d.card_active and d.level is not null;
  if v_n <> 1 then raise exception 'directory row for pending student wrong'; end if;
  select count(*) into v_n from public.list_card_directory() d where d.profile_id = v_other and d.card_id is null;
  if v_n <> 1 then raise exception 'directory should list people without cards'; end if;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_plain, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_ok := false;
  begin perform * from public.list_card_directory();
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  if not v_ok then raise exception 'student can read the directory'; end if;

  -- 5. Activación completa
  set local role service_role;
  if not public.complete_account_activation(v_student, 'Alumno.QA@Example.com') then raise exception 'activation not completed'; end if;
  if public.complete_account_activation(v_student, 'otro@example.com') then raise exception 'activation completed twice'; end if;
  reset role;
  if not exists (select 1 from public.profiles where id = v_student and not activation_pending and email = 'alumno.qa@example.com') then
    raise exception 'profile not activated';
  end if;
  if exists (select 1 from public.account_activation_codes where profile_id = v_student) then raise exception 'code survived activation'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_ok := false;
  begin perform public.terminal_issue_activation_code(v_uid1);
  exception when raise_exception then v_ok := sqlerrm = 'already_activated'; end;
  if not v_ok then raise exception 'code issued for an activated account'; end if;

  -- 5b. PIN de administrador y sesión de administrador
  v_ok := false;
  begin perform public.terminal_assign_card(v_uid3, v_other, false);
  exception when insufficient_privilege then v_ok := sqlerrm = 'admin_session_required'; end;
  if not v_ok then raise exception 'assign worked without an admin session'; end if;
  v_ok := false;
  begin perform * from public.terminal_search_people('qa');
  exception when insufficient_privilege then v_ok := sqlerrm = 'admin_session_required'; end;
  if not v_ok then raise exception 'search worked without an admin session'; end if;

  v_json := public.terminal_scan(v_admin_uid1);
  v_t1 := (v_json->>'ticket')::uuid;
  if (v_json->>'pin_set')::boolean or (v_json->>'pin_ok')::boolean then raise exception 'fresh admin has pin flags'; end if;
  if public.consume_terminal_unlock(v_t1) then raise exception 'unlock without PIN'; end if;
  v_ok := false;
  begin perform public.log_terminal_event(v_t1, 'mode_changed', '{}'::jsonb);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'event logged without PIN'; end if;
  foreach v_code in array array['12', 'abcdef', '1234567'] loop
    v_ok := false;
    begin perform public.terminal_pin_set(v_t1, v_code);
    exception when raise_exception then v_ok := sqlerrm = 'invalid_pin'; end;
    if not v_ok then raise exception 'invalid pin accepted: %', v_code; end if;
  end loop;
  foreach v_code in array array['111111', '123456'] loop
    v_ok := false;
    begin perform public.terminal_pin_set(v_t1, v_code);
    exception when raise_exception then v_ok := sqlerrm = 'weak_pin'; end;
    if not v_ok then raise exception 'weak pin accepted: %', v_code; end if;
  end loop;
  if (public.terminal_pin_set(v_t1, '482913')->>'ok')::boolean is not true then raise exception 'pin_set failed'; end if;
  if (public.terminal_admin_session_status()->>'active')::boolean is not true then raise exception 'no session after pin_set'; end if;
  v_json := public.terminal_scan(v_admin_uid1);
  if (v_json->>'pin_ok')::boolean is not true then raise exception 'active session should skip the PIN'; end if;
  if not public.consume_terminal_unlock((v_json->>'ticket')::uuid) then raise exception 'unlock with PIN failed'; end if;
  perform public.terminal_search_people('qa'); -- ya funciona

  -- Sesión cerrada: hay que verificar el PIN, con límite de intentos
  perform public.terminal_end_admin_session();
  v_json := public.terminal_scan(v_admin_uid1);
  v_t2 := (v_json->>'ticket')::uuid;
  if (v_json->>'pin_set')::boolean is not true or (v_json->>'pin_ok')::boolean then raise exception 'expected pin_set and not pin_ok'; end if;
  v_json := public.terminal_pin_verify(v_t2, '000001');
  if (v_json->>'ok')::boolean or (v_json->>'attempts_left')::int <> 4 then raise exception 'wrong pin result: %', v_json; end if;
  v_json := public.terminal_pin_verify(v_t2, '000002');
  v_json := public.terminal_pin_verify(v_t2, '000003');
  v_json := public.terminal_pin_verify(v_t2, '000004');
  if (v_json->>'attempts_left')::int <> 1 then raise exception 'attempt counter wrong: %', v_json; end if;
  v_json := public.terminal_pin_verify(v_t2, '000005');
  if (v_json->>'ok')::boolean or v_json->>'locked_until' is null then raise exception 'not locked after 5 failures: %', v_json; end if;
  v_json := public.terminal_pin_verify(v_t2, '482913');
  if (v_json->>'ok')::boolean then raise exception 'correct PIN accepted while locked'; end if;
  reset role;
  if (select count(*) from public.terminal_events where event = 'pin_failed') < 5 then raise exception 'pin failures not logged'; end if;
  update public.terminal_admin_pins set locked_until = null where profile_id = v_admin;
  set local role authenticated;
  v_json := public.terminal_pin_verify(v_t2, '482913');
  if (v_json->>'ok')::boolean is not true then raise exception 'correct PIN rejected: %', v_json; end if;
  reset role;
  if not exists (select 1 from public.terminal_unlock_tickets where id = v_t2 and pin_ok) then raise exception 'ticket not marked pin_ok'; end if;
  set local role service_role;
  if not public.operator_admin_session(v_admin) then raise exception 'service check of the session failed'; end if;
  if public.operator_admin_session(v_other) then raise exception 'session leaked to another operator'; end if;
  reset role;
  set local role authenticated;

  -- Cambiar el PIN exige el anterior
  v_t3 := (public.terminal_scan(v_admin_uid1)->>'ticket')::uuid;
  v_json := public.terminal_pin_set(v_t3, '731905', '111222');
  if (v_json->>'ok')::boolean then raise exception 'PIN changed with a wrong old PIN'; end if;
  v_json := public.terminal_pin_set(v_t3, '731905', '482913');
  if (v_json->>'ok')::boolean is not true then raise exception 'PIN change failed'; end if;
  -- Restablecer: solo uno mismo (con terminal.unlock) o un administrador
  perform public.reset_terminal_pin();
  if (public.terminal_scan(v_admin_uid1)->>'pin_set')::boolean then raise exception 'PIN survived reset'; end if;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_plain, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_ok := false;
  begin perform public.reset_terminal_pin(v_admin);
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'a student reset an admin PIN'; end if;
  reset role;
  -- Dejar al administrador con PIN y sesión para la siguiente sección
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_t3 := (public.terminal_scan(v_admin_uid1)->>'ticket')::uuid;
  perform public.terminal_pin_set(v_t3, '482913');

  -- 6. Asignar tarjeta a una persona con cuenta, duplicados y reemplazo
  v_json := public.terminal_assign_card(v_uid2, v_other, false);
  if not (v_json->>'ok')::boolean then raise exception 'assign failed'; end if;
  v_ok := false;
  begin perform public.terminal_assign_card(v_uid2, v_student, false);
  exception when raise_exception then v_ok := sqlerrm = 'card_already_assigned'; end;
  if not v_ok then raise exception 'card assigned to two people'; end if;
  v_ok := false;
  begin perform public.terminal_assign_card(v_uid3, v_other, false);
  exception when raise_exception then v_ok := sqlerrm = 'person_has_card'; end;
  if not v_ok then raise exception 'second card accepted without replace'; end if;
  v_json := public.terminal_assign_card(v_uid3, v_other, true);
  if not (v_json->>'replaced')::boolean then raise exception 'replace flag missing'; end if;
  select count(*) into v_n from public.terminal_search_people('otro est');
  if v_n <> 1 then raise exception 'search failed'; end if;
  reset role;
  if exists (select 1 from public.nfc_cards where card_uid = v_uid2 and active) then raise exception 'old card still active'; end if;
  if not exists (select 1 from public.nfc_cards where card_uid = v_uid3 and active and profile_id = v_other) then raise exception 'new card missing'; end if;

  -- Tarjeta de administrador: se reemplaza borrando la anterior (solo existe una de tipo admin)
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.terminal_assign_card(v_admin_uid1, v_admin, false);
  perform public.terminal_assign_card(v_admin_uid2, v_admin, true);
  reset role;
  select count(*) into v_n from public.nfc_cards where profile_id = v_admin;
  if v_n <> 1 or not exists (select 1 from public.nfc_cards where card_uid = v_admin_uid2 and card_type = 'admin' and active) then
    raise exception 'admin card replacement wrong (% rows)', v_n;
  end if;

  -- 7. Bloquear una tarjeta
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.set_card_active((select id from public.nfc_cards where card_uid = v_uid3), false);
  v_ok := false;
  begin perform public.terminal_scan(v_uid3);
  exception when raise_exception then v_ok := sqlerrm = 'invalid_card'; end;
  if not v_ok then raise exception 'blocked card still readable'; end if;
  reset role;

  -- 8. Eventos registrados
  select count(*) into v_n from public.terminal_events
   where event in ('card_registered', 'activation_code', 'account_activated', 'card_assigned', 'card_replaced', 'card_blocked');
  if v_n < 7 then raise exception 'expected audit events, got %', v_n; end if;

  raise notice 'card-registration: todas las comprobaciones pasaron';
end
$test$;
rollback;
