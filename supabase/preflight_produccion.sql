-- SOLO LECTURA. Ejecútalo en el SQL Editor de Supabase ANTES de aplicar las 4 migraciones nuevas.
-- Cada fila debe decir ok = true. Si alguna dice false, no apliques nada y pásame el resultado.
with checks(descripcion, ok) as (values
  -- tablas que las migraciones usan
  ('tabla profiles',                 to_regclass('public.profiles') is not null),
  ('tabla roles',                    to_regclass('public.roles') is not null),
  ('tabla permissions',              to_regclass('public.permissions') is not null),
  ('tabla role_permissions',         to_regclass('public.role_permissions') is not null),
  ('tabla nfc_cards',                to_regclass('public.nfc_cards') is not null),
  ('tabla student_details',          to_regclass('public.student_details') is not null),
  ('tabla school_levels',            to_regclass('public.school_levels') is not null),
  ('tabla grades',                   to_regclass('public.grades') is not null),
  ('tabla subjects',                 to_regclass('public.subjects') is not null),
  ('tabla grade_periods',            to_regclass('public.grade_periods') is not null),
  ('tabla profile_customizations',   to_regclass('public.profile_customizations') is not null),
  ('tabla terminal_unlock_tickets',  to_regclass('public.terminal_unlock_tickets') is not null),
  ('tabla terminal_profile_access',  to_regclass('public.terminal_profile_access') is not null),
  ('tabla audit_log',                to_regclass('public.audit_log') is not null),
  -- funciones existentes que se reemplazan o se usan
  ('función has_permission(text)',        to_regprocedure('public.has_permission(text)') is not null),
  ('función authorize_terminal_card',     to_regprocedure('public.authorize_terminal_card(text)') is not null),
  ('función terminal_student_profile',    to_regprocedure('public.terminal_student_profile(text)') is not null),
  ('función consume_terminal_unlock',     to_regprocedure('public.consume_terminal_unlock(uuid)') is not null),
  -- permisos y roles
  ('permiso terminal.operate',       exists (select 1 from public.permissions where code = 'terminal.operate')),
  ('permiso terminal.unlock',        exists (select 1 from public.permissions where code = 'terminal.unlock')),
  ('permiso nfc.manage',             exists (select 1 from public.permissions where code = 'nfc.manage')),
  ('rol admin',                      exists (select 1 from public.roles where name = 'admin')),
  ('rol estudiante',                 exists (select 1 from public.roles where name = 'estudiante')),
  ('rol docente',                    exists (select 1 from public.roles where name = 'docente')),
  -- lo que NO debe existir todavía (si existe, la migración correspondiente fallaría)
  ('NO existe terminal_events',                       to_regclass('public.terminal_events') is null),
  ('NO existe columna terminal_unlock_tickets.card_profile_id',
     not exists (select 1 from information_schema.columns where table_schema='public' and table_name='terminal_unlock_tickets' and column_name='card_profile_id')),
  ('NO existe columna profiles.activation_pending',
     not exists (select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='activation_pending')),
  ('NO existe terminal_scan',                         to_regprocedure('public.terminal_scan(text)') is null),
  -- extensión para el PIN
  ('pgcrypto en el esquema extensions',
     exists (select 1 from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pgcrypto' and n.nspname = 'extensions')
     or not exists (select 1 from pg_extension where extname = 'pgcrypto'))
)
select descripcion, ok from checks order by ok, descripcion;
