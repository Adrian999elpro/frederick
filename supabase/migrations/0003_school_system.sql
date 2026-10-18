-- ==============================================================================
-- 0003_school_system.sql
-- FWT: Grados (8vo EGB a 3ro Bachillerato), Perfiles Estudiantiles Customizables,
-- Indicadores de Docentes, Anuncios/Novedades, Calificaciones (Excel),
-- Tarjetas NFC, Asistencia Diaria Única y Votación por Sensor.
-- ==============================================================================

-- 1. Niveles Escolares (8vo EGB a 3ro Bachillerato)
create table if not exists public.school_levels (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text not null unique,
  order_index int not null,
  created_at timestamptz not null default now()
);

-- Insertar grados oficiales
insert into public.school_levels (name, code, order_index) values
  ('8vo Grado de EGB Superior', '8_EGB', 1),
  ('9no Grado de EGB Superior', '9_EGB', 2),
  ('10mo Grado de EGB Superior', '10_EGB', 3),
  ('1ro de Bachillerato General/Técnico', '1_BACH', 4),
  ('2do de Bachillerato General/Técnico', '2_BACH', 5),
  ('3ro de Bachillerato General/Técnico', '3_BACH', 6)
on conflict (code) do nothing;

-- 2. Detalles de Estudiantes (Perfil Customizable + Privacidad de Notas)
create table if not exists public.student_details (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  level_id uuid references public.school_levels(id) on delete set null,
  student_code text unique,
  bio text default '',
  avatar_theme text default 'classic',
  notes_visibility text not null default 'private' check (notes_visibility in ('public', 'private')),
  guardian_name text default '',
  guardian_phone text default '',
  updated_at timestamptz not null default now()
);

-- 3. Materias Configurables
create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null,
  level_id uuid not null references public.school_levels(id) on delete cascade,
  description text default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (level_id, code)
);

-- 4. Asignación de Profesores a Materias (Indicador Docente)
create table if not exists public.subject_teachers (
  subject_id uuid not null references public.subjects(id) on delete cascade,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  primary key (subject_id, teacher_id)
);

-- 5. Períodos Académicos de Calificación
create table if not exists public.grade_periods (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  order_index int not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.grade_periods (name, order_index, active) values
  ('1er Trimestre / Quimestre 1 - P1', 1, true),
  ('1er Trimestre / Quimestre 1 - P2', 2, true),
  ('2do Trimestre / Quimestre 2 - P1', 3, true),
  ('2do Trimestre / Quimestre 2 - P2', 4, true),
  ('3er Trimestre / Examen Quimestral', 5, true)
on conflict (name) do nothing;

-- 6. Calificaciones
create table if not exists public.grades (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  period_id uuid not null references public.grade_periods(id) on delete cascade,
  score numeric(4,2) not null check (score >= 0.00 and score <= 10.00),
  feedback text default '',
  uploaded_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (student_id, subject_id, period_id)
);

-- 7. Anuncios / Novedades Escolares (Rectores, Directores, Profesores)
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  content text not null,
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_role_title text not null default 'Docente', -- Rector, Vicerrector, Director, Docente
  category text not null default 'general' check (category in ('general', 'academico', 'evento', 'urgente')),
  target_level_id uuid references public.school_levels(id) on delete set null, -- null = todo el colegio
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 8. Tarjetas NFC / RFID
create table if not exists public.nfc_cards (
  id uuid primary key default gen_random_uuid(),
  card_uid text not null unique,
  profile_id uuid references public.profiles(id) on delete cascade,
  card_type text not null default 'estudiante' check (card_type in ('estudiante', 'docente', 'admin')),
  label text default '',
  active boolean not null default true,
  registered_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 9. Registro de Asistencia Diaria por Sensor NFC
create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  card_uid text not null,
  check_date date not null default current_date,
  check_time time not null default current_time,
  status text not null default 'present' check (status in ('present', 'late', 'justified')),
  created_at timestamptz not null default now(),
  -- UNA SOLA ASISTENCIA POR DÍA POR ESTUDIANTE
  unique (student_id, check_date)
);

-- ==============================================================================
-- PERMISOS Y ROLES
-- ==============================================================================
insert into public.permissions (code, description) values
  ('nfc.manage', 'Registrar y administrar tarjetas NFC'),
  ('nfc.attendance', 'Operar terminal de asistencia por sensor NFC'),
  ('grades.read', 'Consultar calificaciones académicas'),
  ('grades.upload', 'Subir y calificar estudiantes (Excel o manual)'),
  ('grades.manage', 'Configurar materias y períodos académicos'),
  ('announcements.manage', 'Publicar y editar anuncios institucionales'),
  ('announcements.read', 'Ver cartelera de novedades'),
  ('ranking.read', 'Ver el ranking de mejores estudiantes')
on conflict (code) do nothing;

-- Crear roles adicionales si no existen
insert into public.roles (name, description, is_system) values
  ('rector', 'Rectorado / Dirección Institucional', false),
  ('director', 'Coordinación o Dirección de Área', false)
on conflict (name) do nothing;

-- Asignar permisos a roles
-- Admin: todo
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r, public.permissions p
where r.name = 'admin'
on conflict do nothing;

-- Rector y Director: anuncios, grados, ranking, nfc
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r, public.permissions p
where r.name in ('rector', 'director')
  and p.code in (
    'announcements.manage', 'announcements.read', 'grades.read', 'grades.manage',
    'grades.upload', 'ranking.read', 'nfc.manage', 'nfc.attendance', 'elections.stats'
  )
on conflict do nothing;

-- Docente: subir notas, ver cartelera, publicar avisos, ver sus materias
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r, public.permissions p
where r.name = 'docente'
  and p.code in (
    'grades.read', 'grades.upload', 'announcements.manage', 'announcements.read',
    'ranking.read', 'nfc.attendance', 'elections.read', 'elections.stats'
  )
on conflict do nothing;

-- Estudiante: ver notas, ver novedades, ver ranking (si sus notas son públicas)
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r, public.permissions p
where r.name = 'estudiante'
  and p.code in ('grades.read', 'announcements.read', 'ranking.read', 'elections.vote', 'elections.read')
on conflict do nothing;

-- ==============================================================================
-- FUNCIONES RPC
-- ==============================================================================

-- A) Registro de Asistencia por NFC (Garantiza 1 registro por día)
create or replace function public.record_attendance_nfc(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_card record;
  v_student record;
  v_level record;
  v_rec record;
  v_status text := 'present';
begin
  -- Buscar tarjeta activa
  select c.*, p.full_name, p.email, p.status as profile_status
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

  -- Comprobar si ya registró asistencia hoy
  select * into v_rec
  from public.attendance_records
  where student_id = v_card.profile_id and check_date = current_date;

  if found then
    return jsonb_build_object(
      'ok', false,
      'code', 'already_registered_today',
      'message', 'La asistencia ya fue registrada hoy para este estudiante.',
      'student_name', v_card.full_name,
      'previous_time', to_char(v_rec.check_time, 'HH24:MI:SS')
    );
  end if;

  -- Determinar si es tarde (ej. después de 07:45 AM)
  if current_time > '07:45:00'::time then
    v_status := 'late';
  end if;

  -- Insertar asistencia
  insert into public.attendance_records (student_id, card_uid, check_date, check_time, status)
  values (v_card.profile_id, v_card.card_uid, current_date, current_time, v_status);

  -- Obtener grado
  select l.name into v_level
  from public.student_details sd
  join public.school_levels l on l.id = sd.level_id
  where sd.profile_id = v_card.profile_id;

  return jsonb_build_object(
    'ok', true,
    'code', 'attendance_recorded',
    'student_name', v_card.full_name,
    'level_name', coalesce(v_level.name, 'Sin grado asignado'),
    'check_date', current_date,
    'check_time', to_char(current_time, 'HH24:MI:SS'),
    'status', v_status
  );
end;
$$;

-- B) Validar si una tarjeta es de Administrador (Para desbloquear o salir del modo kiosko)
create or replace function public.validate_admin_card(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean := false;
  v_user_name text;
begin
  select (r.name = 'admin' or c.card_type = 'admin'), p.full_name
  into v_is_admin, v_user_name
  from public.nfc_cards c
  join public.profiles p on p.id = c.profile_id
  join public.roles r on r.id = p.role_id
  where c.card_uid = upper(trim(p_card_uid)) and c.active = true;

  if not found or not v_is_admin then
    return jsonb_build_object('is_admin', false, 'message', 'Tarjeta no autorizada como Administrador');
  end if;

  return jsonb_build_object('is_admin', true, 'admin_name', v_user_name);
end;
$$;

-- C) Ranking Académico Institucional (Solo estudiantes con notas públicas)
create or replace function public.get_academic_ranking(p_level_id uuid default null)
returns table (
  student_id uuid,
  full_name text,
  level_name text,
  level_code text,
  average_score numeric,
  total_subjects bigint,
  notes_visibility text,
  bio text,
  avatar_theme text
)
language sql
security definer
stable
as $$
  select
    p.id as student_id,
    p.full_name,
    sl.name as level_name,
    sl.code as level_code,
    round(avg(g.score), 2) as average_score,
    count(distinct g.subject_id) as total_subjects,
    sd.notes_visibility,
    coalesce(sd.bio, '') as bio,
    coalesce(sd.avatar_theme, 'classic') as avatar_theme
  from public.student_details sd
  join public.profiles p on p.id = sd.profile_id
  join public.school_levels sl on sl.id = sd.level_id
  join public.grades g on g.student_id = p.id
  where p.status = 'active'
    and sd.notes_visibility = 'public' -- FILTRO OBLIGATORIO: Solo notas públicas en ranking
    and (p_level_id is null or sd.level_id = p_level_id)
  group by p.id, p.full_name, sl.name, sl.code, sl.order_index, sd.notes_visibility, sd.bio, sd.avatar_theme
  having count(g.id) > 0
  order by average_score desc, sl.order_index asc;
$$;

-- D) Subir notas masivas (desde Excel / JSON)
create or replace function public.upload_grades_batch(p_grades jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  item jsonb;
  v_inserted int := 0;
  v_updated int := 0;
  v_student_id uuid;
  v_subject_id uuid;
  v_period_id uuid;
  v_score numeric;
begin
  -- Solo usuarios con permiso pueden subir notas
  if not public.has_permission('grades.upload') then
    raise exception 'forbidden: No tiene permiso para subir calificaciones';
  end if;

  for item in select * from jsonb_array_elements(p_grades)
  loop
    v_student_id := (item->>'student_id')::uuid;
    v_subject_id := (item->>'subject_id')::uuid;
    v_period_id  := (item->>'period_id')::uuid;
    v_score      := (item->>'score')::numeric;

    insert into public.grades (student_id, subject_id, period_id, score, feedback, uploaded_by, updated_at)
    values (v_student_id, v_subject_id, v_period_id, v_score, coalesce(item->>'feedback', ''), auth.uid(), now())
    on conflict (student_id, subject_id, period_id)
    do update set
      score = excluded.score,
      feedback = excluded.feedback,
      uploaded_by = excluded.uploaded_by,
      updated_at = now();

    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object('ok', true, 'processed', v_updated);
end;
$$;

-- E) Votación con Tarjeta NFC (Identificación del Estudiante por Sensor)
create or replace function public.cast_vote_nfc(p_election uuid, p_list uuid, p_card_uid text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_card record;
  v_voter_id uuid;
begin
  -- Identificar estudiante mediante tarjeta
  select c.*, p.status as profile_status
  into v_card
  from public.nfc_cards c
  join public.profiles p on p.id = c.profile_id
  where c.card_uid = upper(trim(p_card_uid)) and c.active = true;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'card_not_found', 'message', 'Tarjeta NFC no reconocida.');
  end if;

  v_voter_id := v_card.profile_id;

  -- Comprobar si ya votó
  if exists (select 1 from public.vote_receipts where election_id = p_election and voter_id = v_voter_id) then
    return jsonb_build_object('ok', false, 'code', 'already_voted', 'message', 'Este estudiante ya emitió su voto en esta elección.');
  end if;

  -- Insertar comprobante para evitar doble voto
  insert into public.vote_receipts (election_id, voter_id, voted_at)
  values (p_election, v_voter_id, now());

  -- Insertar voto anónimo
  insert into public.ballots (election_id, list_id)
  values (p_election, p_list);

  return jsonb_build_object('ok', true, 'code', 'vote_recorded', 'message', 'Voto emitido correctamente.');
end;
$$;

-- F) Obtener Materias del Docente (Indicadores para profesores)
create or replace function public.get_teacher_assignments(p_teacher_id uuid default null)
returns table (
  subject_id uuid,
  subject_name text,
  subject_code text,
  level_id uuid,
  level_name text,
  level_code text,
  teacher_id uuid,
  teacher_name text
)
language sql
security definer
stable
as $$
  select
    s.id as subject_id,
    s.name as subject_name,
    s.code as subject_code,
    sl.id as level_id,
    sl.name as level_name,
    sl.code as level_code,
    p.id as teacher_id,
    p.full_name as teacher_name
  from public.subject_teachers st
  join public.subjects s on s.id = st.subject_id
  join public.school_levels sl on sl.id = s.level_id
  join public.profiles p on p.id = st.teacher_id
  where (p_teacher_id is null or st.teacher_id = p_teacher_id)
  order by sl.order_index asc, s.name asc;
$$;

-- G) Actualizar perfil del estudiante (Customización propia)
create or replace function public.update_student_custom_profile(
  p_bio text,
  p_avatar_theme text,
  p_notes_visibility text
)
returns jsonb
language plpgsql
security definer
as $$
begin
  if p_notes_visibility not in ('public', 'private') then
    raise exception 'invalid_visibility';
  end if;

  insert into public.student_details (profile_id, bio, avatar_theme, notes_visibility, updated_at)
  values (auth.uid(), p_bio, p_avatar_theme, p_notes_visibility, now())
  on conflict (profile_id)
  do update set
    bio = excluded.bio,
    avatar_theme = excluded.avatar_theme,
    notes_visibility = excluded.notes_visibility,
    updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

-- Permisos de ejecución
grant execute on function public.record_attendance_nfc(text) to authenticated, anon;
grant execute on function public.validate_admin_card(text) to authenticated, anon;
grant execute on function public.get_academic_ranking(uuid) to authenticated, anon;
grant execute on function public.upload_grades_batch(jsonb) to authenticated;
grant execute on function public.cast_vote_nfc(uuid, uuid, text) to authenticated, anon;
grant execute on function public.get_teacher_assignments(uuid) to authenticated;
grant execute on function public.update_student_custom_profile(text, text, text) to authenticated;

-- Permisos de lectura en tablas
grant select on public.school_levels to authenticated, anon;
grant select on public.grade_periods to authenticated, anon;
grant select on public.subjects to authenticated, anon;
grant select on public.announcements to authenticated, anon;
grant select on public.student_details to authenticated;
grant select on public.subject_teachers to authenticated;
grant select on public.nfc_cards to authenticated;
grant select on public.attendance_records to authenticated;
grant select on public.grades to authenticated;

-- Grants de modificación
grant insert, update, delete on public.announcements to authenticated;
grant insert, update, delete on public.nfc_cards to authenticated;
grant insert, update, delete on public.subjects to authenticated;
grant insert, update, delete on public.subject_teachers to authenticated;
grant insert, update, delete on public.student_details to authenticated;
grant insert, update, delete on public.grades to authenticated;

-- RLS
alter table public.school_levels enable row level security;
alter table public.student_details enable row level security;
alter table public.subjects enable row level security;
alter table public.subject_teachers enable row level security;
alter table public.grade_periods enable row level security;
alter table public.grades enable row level security;
alter table public.announcements enable row level security;
alter table public.nfc_cards enable row level security;
alter table public.attendance_records enable row level security;

-- Políticas RLS
create policy levels_read on public.school_levels for select using (true);
create policy periods_read on public.grade_periods for select using (true);
create policy subjects_read on public.subjects for select using (true);
create policy announcements_read on public.announcements for select using (true);

create policy announcements_write on public.announcements for all using (
  public.has_permission('announcements.manage')
);

create policy student_details_read on public.student_details for select using (
  auth.uid() = profile_id or public.has_permission('grades.read')
);

create policy student_details_write on public.student_details for all using (
  auth.uid() = profile_id or public.has_permission('users.manage')
);

create policy nfc_cards_read on public.nfc_cards for select using (
  auth.uid() = profile_id or public.has_permission('nfc.manage')
);

create policy nfc_cards_manage on public.nfc_cards for all using (
  public.has_permission('nfc.manage')
);

create policy attendance_read on public.attendance_records for select using (
  auth.uid() = student_id or public.has_permission('attendance.read') or public.has_permission('nfc.attendance')
);

create policy grades_policy_read on public.grades for select using (
  auth.uid() = student_id or public.has_permission('grades.read')
);

create policy grades_policy_write on public.grades for all using (
  public.has_permission('grades.upload')
);
