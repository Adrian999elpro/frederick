-- 0007 · Endurecimiento de seguridad (votación NFC, asistencia, notas, permisos de funciones)
-- Aplicar DESPUÉS de 0001–0006. Idempotente: se puede ejecutar más de una vez.

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Configuración de asistencia (zona horaria y hora límite configurables)
--    Ajusta 'timezone' si el colegio cambia de zona. Antes se usaba la hora UTC del servidor.
-- ───────────────────────────────────────────────────────────────────────────
insert into public.app_settings(key, value) values
  ('attendance', '{"timezone":"America/Guayaquil","late_after":"07:45"}')
on conflict (key) do nothing;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Cerrar el EXECUTE por defecto (PUBLIC) en las funciones de 0003–0006.
--    Solo las funciones de ranking siguen siendo públicas (decisión de producto, ver 0005).
-- ───────────────────────────────────────────────────────────────────────────
revoke all on function
  public.record_attendance_nfc(text),
  public.validate_admin_card(text),
  public.cast_vote_nfc(uuid, uuid, text),
  public.upload_grades_batch(jsonb),
  public.get_teacher_assignments(uuid),
  public.update_student_custom_profile(text, text, text),
  public.update_student_specialties(uuid, text[]),
  public.save_nfc_card_binding(uuid, text, uuid, text, text, boolean)
from public, anon;

grant execute on function
  public.record_attendance_nfc(text),
  public.validate_admin_card(text),
  public.cast_vote_nfc(uuid, uuid, text),
  public.upload_grades_batch(jsonb),
  public.get_teacher_assignments(uuid),
  public.update_student_custom_profile(text, text, text),
  public.update_student_specialties(uuid, text[]),
  public.save_nfc_card_binding(uuid, text, uuid, text, text, boolean)
to authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. search_path fijo en todas las funciones SECURITY DEFINER que no lo tenían
-- ───────────────────────────────────────────────────────────────────────────
alter function public.get_academic_ranking(uuid)                                     set search_path = public;
alter function public.get_teacher_assignments(uuid)                                  set search_path = public;
alter function public.update_student_custom_profile(text, text, text)                set search_path = public;
alter function public.update_student_specialties(uuid, text[])                       set search_path = public;
alter function public.get_specialty_ranking(uuid, uuid)                              set search_path = public;
alter function public.get_subject_ranking(uuid)                                      set search_path = public;
alter function public.save_nfc_card_binding(uuid, text, uuid, text, text, boolean)   set search_path = public;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Asistencia NFC: solo terminales con permiso, hora local y sin carreras
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.record_attendance_nfc(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card record;
  v_rec record;
  v_level_name text;
  v_cfg jsonb := coalesce((select value from public.app_settings where key = 'attendance'), '{}'::jsonb);
  v_local timestamp := now() at time zone coalesce(v_cfg->>'timezone', 'UTC');
  v_date date := v_local::date;
  v_time time := v_local::time;
  v_status text := 'present';
begin
  if not public.has_permission('nfc.attendance') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_card_uid is null or length(trim(p_card_uid)) not between 1 and 64 then
    return jsonb_build_object('ok', false, 'code', 'card_not_found', 'message', 'Tarjeta no registrada o inactiva.');
  end if;

  select c.profile_id, c.card_uid, p.full_name, p.status as profile_status
    into v_card
    from public.nfc_cards c
    join public.profiles p on p.id = c.profile_id
   where c.card_uid = upper(trim(p_card_uid)) and c.active = true;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'card_not_found', 'message', 'Tarjeta no registrada o inactiva.');
  end if;
  if v_card.profile_status <> 'active' then
    return jsonb_build_object('ok', false, 'code', 'user_inactive', 'message', 'El estudiante está inactivo en el sistema.');
  end if;

  select * into v_rec from public.attendance_records
   where student_id = v_card.profile_id and check_date = v_date;
  if found then
    return jsonb_build_object('ok', false, 'code', 'already_registered_today',
      'message', 'La asistencia ya fue registrada hoy para este estudiante.',
      'student_name', v_card.full_name, 'previous_time', to_char(v_rec.check_time, 'HH24:MI:SS'));
  end if;

  if v_time > coalesce((v_cfg->>'late_after')::time, '07:45'::time) then
    v_status := 'late';
  end if;

  begin
    insert into public.attendance_records (student_id, card_uid, check_date, check_time, status)
    values (v_card.profile_id, v_card.card_uid, v_date, v_time, v_status);
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'already_registered_today',
      'message', 'La asistencia ya fue registrada hoy para este estudiante.', 'student_name', v_card.full_name);
  end;

  select l.name into v_level_name
    from public.student_details sd join public.school_levels l on l.id = sd.level_id
   where sd.profile_id = v_card.profile_id;

  return jsonb_build_object('ok', true, 'code', 'attendance_recorded',
    'student_name', v_card.full_name, 'level_name', coalesce(v_level_name, 'Sin grado asignado'),
    'check_date', v_date, 'check_time', to_char(v_time, 'HH24:MI:SS'), 'status', v_status);
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Tarjeta de administrador: exige terminal autorizado y deja rastro de los rechazos
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.validate_admin_card(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_name text;
begin
  if not public.has_permission('nfc.attendance') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select (r.name = 'admin' or c.card_type = 'admin'), p.full_name
    into v_is_admin, v_name
    from public.nfc_cards c
    join public.profiles p on p.id = c.profile_id
    join public.roles r on r.id = p.role_id
   where c.card_uid = upper(trim(coalesce(p_card_uid, ''))) and c.active = true and p.status = 'active';

  if not found or not coalesce(v_is_admin, false) then
    perform public.log_event('nfc.admin_card_denied');
    return jsonb_build_object('is_admin', false, 'message', 'Tarjeta no autorizada como Administrador');
  end if;

  return jsonb_build_object('is_admin', true, 'admin_name', v_name);
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Voto NFC: mismas reglas que cast_vote (elección abierta, lista válida, votante habilitado)
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.cast_vote_nfc(p_election uuid, p_list uuid, p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.elections;
  v_voter uuid;
  v_eligible boolean;
begin
  if not public.has_permission('nfc.attendance') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into e from public.elections where id = p_election;
  if not found or e.status <> 'open' or now() < e.starts_at or now() > e.ends_at then
    return jsonb_build_object('ok', false, 'code', 'election_not_open', 'message', 'La votación no está abierta.');
  end if;
  if p_list is not null and not exists (
       select 1 from public.election_lists where id = p_list and election_id = p_election) then
    return jsonb_build_object('ok', false, 'code', 'invalid_list', 'message', 'La lista no pertenece a esta elección.');
  end if;

  select c.profile_id,
         exists (select 1 from public.role_permissions rp
                  where rp.role_id = p.role_id and rp.permission_code = 'elections.vote')
    into v_voter, v_eligible
    from public.nfc_cards c
    join public.profiles p on p.id = c.profile_id
   where c.card_uid = upper(trim(coalesce(p_card_uid, ''))) and c.active = true and p.status = 'active';

  if not found then
    return jsonb_build_object('ok', false, 'code', 'card_not_found', 'message', 'Tarjeta NFC no reconocida.');
  end if;
  if not v_eligible then
    return jsonb_build_object('ok', false, 'code', 'not_eligible', 'message', 'Esta tarjeta no está habilitada para votar.');
  end if;

  begin
    insert into public.vote_receipts (election_id, voter_id) values (p_election, v_voter);
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'already_voted', 'message', 'Este estudiante ya emitió su voto en esta elección.');
  end;

  insert into public.ballots (election_id, list_id) values (p_election, p_list);
  perform public.log_event('election.vote_nfc', p_election::text);  -- sin votante ni lista: el voto sigue siendo secreto

  return jsonb_build_object('ok', true, 'code', 'vote_recorded', 'message', 'Voto emitido correctamente.');
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. Subida de notas: el docente solo puede calificar sus materias (grades.manage lo salta)
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.upload_grades_batch(p_grades jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  v_subject uuid;
  v_count int := 0;
  v_any boolean := public.has_permission('grades.manage');
begin
  if not public.has_permission('grades.upload') then
    raise exception 'forbidden: No tiene permiso para subir calificaciones' using errcode = '42501';
  end if;
  if p_grades is null or jsonb_typeof(p_grades) <> 'array' then
    raise exception 'invalid_payload: se esperaba una lista de notas';
  end if;

  for item in select * from jsonb_array_elements(p_grades) loop
    if item->>'student_id' is null or item->>'subject_id' is null
       or item->>'period_id' is null or item->>'score' is null then
      raise exception 'invalid_row: faltan student_id, subject_id, period_id o score';
    end if;
    v_subject := (item->>'subject_id')::uuid;

    if not v_any and not exists (
         select 1 from public.subject_teachers where subject_id = v_subject and teacher_id = auth.uid()) then
      raise exception 'forbidden_subject: no está asignado a esta materia' using errcode = '42501';
    end if;

    insert into public.grades (student_id, subject_id, period_id, score, feedback, uploaded_by, updated_at)
    values ((item->>'student_id')::uuid, v_subject, (item->>'period_id')::uuid,
            (item->>'score')::numeric, left(coalesce(item->>'feedback', ''), 500), auth.uid(), now())
    on conflict (student_id, subject_id, period_id) do update set
      score = excluded.score, feedback = excluded.feedback,
      uploaded_by = excluded.uploaded_by, updated_at = now();
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'processed', v_count);
end;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 8. Integridad e índices
-- ───────────────────────────────────────────────────────────────────────────
alter table public.student_details
  drop constraint if exists student_details_bio_len,
  add  constraint student_details_bio_len check (char_length(coalesce(bio, '')) <= 300) not valid;

create index if not exists attendance_records_date_idx on public.attendance_records (check_date);
create index if not exists nfc_cards_profile_idx       on public.nfc_cards (profile_id);
create index if not exists grades_subject_period_idx   on public.grades (subject_id, period_id);
