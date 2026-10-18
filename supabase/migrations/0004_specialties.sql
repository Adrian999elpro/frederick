-- ==============================================================================
-- 0004_specialties.sql
-- FWT: Especialidades Oficiales de Bachillerato Técnico
-- (Mecanizado, Música, Desarrollo de Software, Automotriz)
-- Y Orientación Vocacional con Selección Múltiple para Básica (8vo a 10mo EGB)
-- ==============================================================================

-- 1. Tabla de Especialidades de Bachillerato Técnico FWT
create table if not exists public.technical_specialties (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  short_name text not null,
  description text default '',
  icon text default 'school',
  created_at timestamptz not null default now()
);

-- Insertar las 4 especialidades oficiales investigadas del sitio frederickwinslowtaylor.com
insert into public.technical_specialties (code, name, short_name, description, icon) values
  ('mecanizado', 'Mecanizado y Construcciones Metálicas', 'Mecanizado', 'Mecánica industrial, diseño, mecanizado por arranque de viruta, soldadura y automatización de procesos de producción.', 'settings'),
  ('software', 'Desarrollo de Software', 'Desarrollo de Software', 'Diseño y desarrollo de aplicaciones web, móviles y de escritorio, lógica de programación, bases de datos y seguridad informática.', 'laptop_mac'),
  ('automotriz', 'Electromecánica Automotriz', 'Automotriz', 'Mantenimiento integral de sistemas mecánicos, eléctricos y electrónicos de vehículos, inyección y diagnóstico automotriz.', 'directions_car'),
  ('musica', 'Música y Gestión Cultural', 'Música', 'Formación instrumental, ensamble, teoría musical, producción sonora, expresión artística y gestión cultural.', 'music_note')
on conflict (code) do nothing;

-- 2. Modificar student_details para albergar:
-- a) chosen_specialty_id: Especialidad asignada (para 1ro a 3ro de Bachillerato)
-- b) interested_specialties: Array de códigos de especialidades que le gustan a los de básica (selección múltiple)
alter table public.student_details
  add column if not exists chosen_specialty_id uuid references public.technical_specialties(id) on delete set null,
  add column if not exists interested_specialties text[] default '{}';

-- 3. Función RPC para actualizar especialidad (Bachillerato) o intereses vocacionales múltiples (Básica)
create or replace function public.update_student_specialties(
  p_chosen_specialty_id uuid default null,
  p_interested_specialties text[] default '{}'
)
returns jsonb
language plpgsql
security definer
as $$
begin
  insert into public.student_details (profile_id, chosen_specialty_id, interested_specialties, updated_at)
  values (auth.uid(), p_chosen_specialty_id, p_interested_specialties, now())
  on conflict (profile_id)
  do update set
    chosen_specialty_id = coalesce(excluded.chosen_specialty_id, public.student_details.chosen_specialty_id),
    interested_specialties = excluded.interested_specialties,
    updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

-- 4. Actualizar get_academic_ranking para incluir la especialidad
-- NOTA POSTGRES: Es obligatorio hacer DROP FUNCTION antes de cambiar las columnas del tipo RETURNS TABLE
drop function if exists public.get_academic_ranking(uuid);

create or replace function public.get_academic_ranking(p_level_id uuid default null)
returns table (
  student_id uuid,
  full_name text,
  level_name text,
  level_code text,
  level_order int,
  specialty_name text,
  specialty_code text,
  interested_specialties text[],
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
    sl.order_index as level_order,
    coalesce(ts.short_name, '') as specialty_name,
    coalesce(ts.code, '') as specialty_code,
    coalesce(sd.interested_specialties, '{}') as interested_specialties,
    round(avg(g.score), 2) as average_score,
    count(distinct g.subject_id) as total_subjects,
    sd.notes_visibility,
    coalesce(sd.bio, '') as bio,
    coalesce(sd.avatar_theme, 'classic') as avatar_theme
  from public.student_details sd
  join public.profiles p on p.id = sd.profile_id
  join public.school_levels sl on sl.id = sd.level_id
  left join public.technical_specialties ts on ts.id = sd.chosen_specialty_id
  join public.grades g on g.student_id = p.id
  where p.status = 'active'
    and sd.notes_visibility = 'public'
    and (p_level_id is null or sd.level_id = p_level_id)
  group by p.id, p.full_name, sl.name, sl.code, sl.order_index, ts.short_name, ts.code, sd.interested_specialties, sd.notes_visibility, sd.bio, sd.avatar_theme
  having count(g.id) > 0
  order by average_score desc, sl.order_index asc;
$$;

-- Permisos
grant select on public.technical_specialties to authenticated, anon;
grant execute on function public.update_student_specialties(uuid, text[]) to authenticated;
grant execute on function public.get_academic_ranking(uuid) to authenticated, anon;
