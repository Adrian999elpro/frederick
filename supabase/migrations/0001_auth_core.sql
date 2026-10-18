-- =====================================================================
-- 0001_auth_core.sql
-- Núcleo reutilizable: perfiles, roles, permisos, ajustes y auditoría.
-- Ejecutar en el SQL Editor de Supabase o con `supabase db push`.
-- Toda la autorización vive aquí (RLS + funciones), nunca en el frontend.
-- =====================================================================

-- ---------- Tablas ----------
create table public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (name ~ '^[a-z][a-z0-9_]{1,30}$'),
  description text not null default '' check (char_length(description) <= 200),
  is_system boolean not null default false,          -- no se puede renombrar ni borrar
  created_at timestamptz not null default now()
);

create table public.permissions (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  description text not null default ''
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_code text not null references public.permissions(code) on delete cascade,
  primary key (role_id, permission_code)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null default '' check (char_length(full_name) <= 120),
  phone text check (phone is null or char_length(phone) <= 30),
  role_id uuid not null references public.roles(id),
  status text not null default 'active' check (status in ('active','disabled')),
  must_change_password boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_role_idx on public.profiles(role_id);
create index profiles_email_idx on public.profiles(lower(email));

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  constraint registration_shape check (
    key <> 'registration' or (
      coalesce(value->>'mode','') in ('closed','open','domain')
      and coalesce(jsonb_typeof(value->'allowed_domains'),'') = 'array')
  )
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor uuid references public.profiles(id) on delete set null,
  action text not null,
  target text,
  detail jsonb,
  created_at timestamptz not null default now()
);
create index audit_log_created_idx on public.audit_log(created_at desc);

-- Solo la usa la Edge Function auth-login (service_role). Guarda hashes, no datos crudos.
create table public.login_attempts (
  id bigint generated always as identity primary key,
  email_hash text not null,
  ip_hash text not null,
  success boolean not null,
  created_at timestamptz not null default now()
);
create index login_attempts_email_idx on public.login_attempts(email_hash, created_at desc);
create index login_attempts_ip_idx on public.login_attempts(ip_hash, created_at desc);

create function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger settings_touch before update on public.app_settings for each row execute function public.touch_updated_at();

-- ---------- Funciones de acceso ----------
create function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

create function public.has_permission(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    join public.role_permissions rp on rp.role_id = p.role_id
    where p.id = auth.uid() and p.status = 'active' and rp.permission_code = p_code);
$$;

-- Una sola llamada devuelve perfil + rol + permisos (el frontend la cachea unos minutos).
create function public.get_my_access() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'email', p.email, 'full_name', p.full_name, 'phone', p.phone,
    'role', r.name, 'must_change_password', p.must_change_password,
    'permissions', coalesce((select jsonb_agg(rp.permission_code order by rp.permission_code)
                             from public.role_permissions rp where rp.role_id = p.role_id), '[]'::jsonb))
  from public.profiles p join public.roles r on r.id = p.role_id
  where p.id = auth.uid() and p.status = 'active';
$$;

create function public.public_registration_mode() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select value->>'mode' from public.app_settings where key = 'registration'), 'closed');
$$;

create function public.ack_password_changed() returns void
language sql security definer set search_path = public as $$
  update public.profiles set must_change_password = false where id = auth.uid();
$$;

create function public.log_event(p_action text, p_target text default null, p_detail jsonb default null) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log(actor, action, target, detail) values (auth.uid(), p_action, p_target, p_detail);
$$;

-- Reemplaza TODOS los permisos de un rol en una sola operación atómica.
create function public.set_role_permissions(p_role uuid, p_codes text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.has_permission('roles.manage') then raise exception 'forbidden' using errcode = '42501'; end if;
  if not exists (select 1 from public.roles where id = p_role) then raise exception 'role_not_found'; end if;
  if exists (select 1 from public.roles where id = p_role and name = 'admin') then raise exception 'admin_locked'; end if;
  if exists (select 1 from unnest(p_codes) c where c not in (select code from public.permissions)) then
    raise exception 'unknown_permission';
  end if;
  delete from public.role_permissions where role_id = p_role;
  insert into public.role_permissions(role_id, permission_code)
    select p_role, c from unnest(p_codes) c group by c;
  perform public.log_event('roles.permissions', p_role::text, to_jsonb(p_codes));
end $$;

create function public.purge_old_records() returns void
language sql security definer set search_path = public as $$
  delete from public.login_attempts where created_at < now() - interval '2 days';
$$;

create function public.audit_settings() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public.log_event('settings.update', new.key, new.value); return new; end $$;
create trigger app_settings_audit after update on public.app_settings
  for each row execute function public.audit_settings();

-- ---------- Alta de usuarios: la política de registro se aplica AQUÍ ----------
-- Funciona igual si el alta llega por signUp, por el panel o por la API admin.
-- Los usuarios creados por el administrador llevan app_metadata.provisioned = true
-- (app_metadata solo lo puede escribir el servidor, nunca el usuario).
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cfg jsonb;
  v_mode text;
  v_prov boolean := coalesce((new.raw_app_meta_data->>'provisioned')::boolean, false);
  v_role_name text;
  v_role uuid;
begin
  select value into cfg from public.app_settings where key = 'registration';
  cfg := coalesce(cfg, '{}'::jsonb);
  v_mode := coalesce(cfg->>'mode', 'closed');

  if not v_prov then
    if v_mode = 'closed' then raise exception 'registration_closed'; end if;
    if v_mode = 'domain' and not exists (
      select 1 from jsonb_array_elements_text(coalesce(cfg->'allowed_domains', '[]'::jsonb)) d
      where lower(d) = lower(split_part(new.email, '@', 2))
    ) then raise exception 'domain_not_allowed'; end if;
  end if;

  v_role_name := case when v_prov then coalesce(new.raw_app_meta_data->>'role', cfg->>'default_role', 'usuario')
                      else coalesce(cfg->>'default_role', 'usuario') end;
  select id into v_role from public.roles where name = v_role_name;
  if v_role is null then raise exception 'role_not_found'; end if;

  -- Nunca se puede auto-registrar alguien con un rol que administra algo.
  if not v_prov and exists (
    select 1 from public.role_permissions where role_id = v_role and permission_code like '%.manage'
  ) then raise exception 'role_not_allowed_for_signup'; end if;

  insert into public.profiles(id, email, full_name, role_id)
  values (new.id, lower(new.email), left(coalesce(new.raw_user_meta_data->>'full_name', ''), 120), v_role);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Datos iniciales ----------
insert into public.permissions(code, description) values
  ('users.read',      'Ver la lista de usuarios'),
  ('users.manage',    'Crear, desactivar y eliminar usuarios; cambiar su rol'),
  ('roles.manage',    'Crear roles y asignar permisos'),
  ('settings.manage', 'Configurar el registro y los ajustes'),
  ('audit.read',      'Ver el registro de auditoría');

insert into public.roles(name, description, is_system) values
  ('admin',   'Administrador con todos los permisos', true),
  ('usuario', 'Usuario básico sin permisos especiales', true);

insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code from public.roles r cross join public.permissions p where r.name = 'admin';

insert into public.app_settings(key, value) values
  ('registration', '{"mode":"closed","allowed_domains":[],"default_role":"usuario"}');

-- ---------- RLS y privilegios (mínimo necesario) ----------
alter table public.roles            enable row level security;
alter table public.permissions      enable row level security;
alter table public.role_permissions enable row level security;
alter table public.profiles         enable row level security;
alter table public.app_settings     enable row level security;
alter table public.audit_log        enable row level security;
alter table public.login_attempts   enable row level security;   -- sin políticas: solo service_role

revoke all on public.roles, public.permissions, public.role_permissions, public.profiles,
              public.app_settings, public.audit_log, public.login_attempts from anon, authenticated;

grant select on public.roles, public.permissions, public.role_permissions, public.profiles,
                public.app_settings, public.audit_log to authenticated;
grant insert (name, description), update (name, description), delete on public.roles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;   -- rol y estado NO son editables por el cliente
grant update (value) on public.app_settings to authenticated;

create policy roles_read   on public.roles for select to authenticated using ((select public.is_active()));
create policy roles_insert on public.roles for insert to authenticated
  with check ((select public.has_permission('roles.manage')) and not is_system);
create policy roles_update on public.roles for update to authenticated
  using ((select public.has_permission('roles.manage')) and not is_system)
  with check ((select public.has_permission('roles.manage')) and not is_system);
create policy roles_delete on public.roles for delete to authenticated
  using ((select public.has_permission('roles.manage')) and not is_system);

create policy permissions_read on public.permissions for select to authenticated using ((select public.is_active()));
create policy role_permissions_read on public.role_permissions for select to authenticated using ((select public.is_active()));

create policy profiles_read on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.has_permission('users.read')));
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = (select auth.uid()) and (select public.is_active()))
  with check (id = (select auth.uid()));

create policy settings_read   on public.app_settings for select to authenticated using ((select public.has_permission('settings.manage')));
create policy settings_update on public.app_settings for update to authenticated
  using ((select public.has_permission('settings.manage'))) with check ((select public.has_permission('settings.manage')));

create policy audit_read on public.audit_log for select to authenticated using ((select public.has_permission('audit.read')));

-- Ejecución de funciones: cerrado por defecto, abrir solo lo necesario.
revoke all on function
  public.is_active(), public.has_permission(text), public.get_my_access(), public.public_registration_mode(),
  public.ack_password_changed(), public.log_event(text,text,jsonb), public.set_role_permissions(uuid,text[]),
  public.purge_old_records(), public.audit_settings(), public.handle_new_user()
from public, anon, authenticated;
grant execute on function public.is_active(), public.has_permission(text), public.get_my_access(),
  public.ack_password_changed(), public.set_role_permissions(uuid,text[]) to authenticated;
grant execute on function public.public_registration_mode() to anon, authenticated;

-- Opcional (extensión pg_cron): select cron.schedule('purge-auth', '0 3 * * *', 'select public.purge_old_records()');
