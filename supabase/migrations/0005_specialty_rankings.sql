-- ==============================================================================
-- 0005_specialty_rankings.sql
-- FWT: Materias únicas por especialidad técnica (Mecanizado, Música, Software, Automotriz)
-- y Rankings especializados:
-- 1. Ranking de los mejores estudiantes por Especialidad Técnica
-- 2. Ranking de mejores estudiantes por Materia Única / Específica
-- ==============================================================================

-- 1. Vincular materias con una especialidad técnica (null = materia del tronco común)
alter table public.subjects
  add column if not exists specialty_id uuid references public.technical_specialties(id) on delete set null;

-- 2. Insertar materias técnicas representativas para cada especialidad en Bachillerato
do $$
declare
  v_bach1 uuid;
  v_bach2 uuid;
  v_bach3 uuid;
  v_spec_soft uuid;
  v_spec_meca uuid;
  v_spec_auto uuid;
  v_spec_musi uuid;
begin
  select id into v_bach1 from public.school_levels where code = '1_BACH';
  select id into v_bach2 from public.school_levels where code = '2_BACH';
  select id into v_bach3 from public.school_levels where code = '3_BACH';

  select id into v_spec_soft from public.technical_specialties where code = 'software';
  select id into v_spec_meca from public.technical_specialties where code = 'mecanizado';
  select id into v_spec_auto from public.technical_specialties where code = 'automotriz';
  select id into v_spec_musi from public.technical_specialties where code = 'musica';

  if v_bach1 is not null and v_spec_soft is not null then
    -- Materias Técnicas: Desarrollo de Software
    insert into public.subjects (name, code, level_id, specialty_id, description) values
      ('Programación y Bases de Datos', 'SOFT-PBD-1B', v_bach1, v_spec_soft, 'Fundamentos de programación, estructuras de control y bases de datos relacionales'),
      ('Diseño y Desarrollo Web', 'SOFT-WEB-1B', v_bach1, v_spec_soft, 'Maquetación HTML5, CSS3, JavaScript y desarrollo de aplicaciones web responsivas'),
      ('Sistemas Operativos y Redes', 'SOFT-RED-2B', v_bach2, v_spec_soft, 'Administración de servidores Linux/Windows y arquitectura de redes'),
      ('Desarrollo de Aplicaciones Móviles', 'SOFT-APP-3B', v_bach3, v_spec_soft, 'Programación de apps móviles nativas y multiplataforma con Flutter')
    on conflict do nothing;

    -- Materias Técnicas: Mecanizado y Construcciones Metálicas
    insert into public.subjects (name, code, level_id, specialty_id, description) values
      ('Mecanizado por Arranque de Viruta (Torno)', 'MECA-TOR-1B', v_bach1, v_spec_meca, 'Operación de torno paralelo, cilindrado, refrentado y roscado'),
      ('Dibujo Técnico Mecánico Asistido (CAD)', 'MECA-CAD-1B', v_bach1, v_spec_meca, 'Diseño e interpretación de planos mecánicos normalizados'),
      ('Soldadura y Estructuras Metálicas', 'MECA-SOL-2B', v_bach2, v_spec_meca, 'Procesos de soldadura SMAW, GMAW/MIG y GTAW/TIG'),
      ('Mecanizado por Control Numérico (CNC)', 'MECA-CNC-3B', v_bach3, v_spec_meca, 'Programación en código G y M para centro de mecanizado CNC')
    on conflict do nothing;

    -- Materias Técnicas: Electromecánica Automotriz
    insert into public.subjects (name, code, level_id, specialty_id, description) values
      ('Motores de Combustión Interna', 'AUTO-MOT-1B', v_bach1, v_spec_auto, 'Ciclo de funcionamiento, desarmado, verificación y ajuste de motores'),
      ('Electricidad y Electrónica Automotriz', 'AUTO-ELE-1B', v_bach1, v_spec_auto, 'Circuitos de alumbrado, arranque, carga y sensores del vehículo'),
      ('Sistemas de Inyección Electrónica', 'AUTO-INJ-2B', v_bach2, v_spec_auto, 'Diagnóstico por escáner OBD-II, actuadores y telemetría automotriz'),
      ('Transmisión y Tren de Rodaje', 'AUTO-TRA-3B', v_bach3, v_spec_auto, 'Cajas de cambio manuales/automáticas, frenos ABS y dirección electroasistida')
    on conflict do nothing;

    -- Materias Técnicas: Música y Gestión Cultural
    insert into public.subjects (name, code, level_id, specialty_id, description) values
      ('Lenguaje Musical, Solfeo y Armonía', 'MUSI-ARM-1B', v_bach1, v_spec_musi, 'Lectoescritura musical, escalas, intervalos y armonía funcional'),
      ('Instrumento Principal y Práctica Solista', 'MUSI-INS-1B', v_bach1, v_spec_musi, 'Técnica instrumental y repertorio solista'),
      ('Ensamble y Agrupaciones Musicales', 'MUSI-ENS-2B', v_bach2, v_spec_musi, 'Práctica coral, ensamble instrumental y repertorio orquestal FWT'),
      ('Producción de Audio y Gestión Cultural', 'MUSI-PRO-3B', v_bach3, v_spec_musi, 'Grabación en estudio, mezcla y diseño de eventos culturales')
    on conflict do nothing;
  end if;
end $$;

-- 3. RPC: Ranking de los Mejores Estudiantes por Especialidad Técnica
-- (Calcula el promedio general de estudiantes pertenecientes a una especialidad)
create or replace function public.get_specialty_ranking(
  p_specialty_id uuid,
  p_level_id uuid default null
)
returns table (
  student_id uuid,
  full_name text,
  level_name text,
  specialty_name text,
  specialty_code text,
  average_score numeric,
  technical_average numeric,
  total_subjects bigint,
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
    ts.name as specialty_name,
    ts.code as specialty_code,
    round(avg(g.score), 2) as average_score,
    round(coalesce(avg(case when s.specialty_id = p_specialty_id then g.score else null end), avg(g.score)), 2) as technical_average,
    count(distinct g.subject_id) as total_subjects,
    coalesce(sd.bio, '') as bio,
    coalesce(sd.avatar_theme, 'classic') as avatar_theme
  from public.student_details sd
  join public.profiles p on p.id = sd.profile_id
  join public.school_levels sl on sl.id = sd.level_id
  join public.technical_specialties ts on ts.id = sd.chosen_specialty_id
  join public.grades g on g.student_id = p.id
  join public.subjects s on s.id = g.subject_id
  where p.status = 'active'
    and sd.notes_visibility = 'public' -- REGLA: Solo notas públicas
    and sd.chosen_specialty_id = p_specialty_id
    and (p_level_id is null or sd.level_id = p_level_id)
  group by p.id, p.full_name, sl.name, sl.order_index, ts.name, ts.code, sd.bio, sd.avatar_theme
  having count(g.id) > 0
  order by technical_average desc, average_score desc;
$$;

-- 4. RPC: Ranking de Estudiantes por Materia Específica / Única
-- (Muestra los mejores estudiantes en una asignatura en particular)
create or replace function public.get_subject_ranking(p_subject_id uuid)
returns table (
  student_id uuid,
  full_name text,
  level_name text,
  specialty_name text,
  subject_name text,
  subject_code text,
  is_technical boolean,
  score numeric,
  feedback text,
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
    coalesce(ts.short_name, 'Tronco Común') as specialty_name,
    s.name as subject_name,
    s.code as subject_code,
    (s.specialty_id is not null) as is_technical,
    g.score,
    coalesce(g.feedback, '') as feedback,
    coalesce(sd.bio, '') as bio,
    coalesce(sd.avatar_theme, 'classic') as avatar_theme
  from public.grades g
  join public.profiles p on p.id = g.student_id
  join public.student_details sd on sd.profile_id = p.id
  join public.subjects s on s.id = g.subject_id
  join public.school_levels sl on sl.id = s.level_id
  left join public.technical_specialties ts on ts.id = s.specialty_id
  where p.status = 'active'
    and sd.notes_visibility = 'public' -- REGLA: Solo notas públicas
    and g.subject_id = p_subject_id
  order by g.score desc, p.full_name asc;
$$;

-- Permisos de ejecución
grant execute on function public.get_specialty_ranking(uuid, uuid) to authenticated, anon;
grant execute on function public.get_subject_ranking(uuid) to authenticated, anon;
