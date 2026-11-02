-- PIN de la tarjeta de administrador.
-- La tarjeta sola ya no basta: para abrir el panel del terminal, desbloquear la app o registrar
-- tarjetas hace falta tarjeta + PIN de 6 dígitos. El PIN se guarda con bcrypt (pgcrypto), se
-- bloquea 15 minutos tras 5 intentos fallidos y se restablece desde la web (Seguridad).
-- Una verificación correcta abre una "sesión de administrador" de 10 minutos (se renueva con
-- cada acción) que el servidor exige para asignar/buscar tarjetas y registrar personas.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter table public.terminal_unlock_tickets add column if not exists pin_ok boolean not null default false;

create table if not exists public.terminal_admin_pins (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  pin_hash text not null,
  failed_attempts int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.terminal_admin_pins enable row level security;
revoke all on public.terminal_admin_pins from public, anon, authenticated;

create table if not exists public.terminal_admin_sessions (
  operator_id uuid primary key references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  expires_at timestamptz not null
);
alter table public.terminal_admin_sessions enable row level security;
revoke all on public.terminal_admin_sessions from public, anon, authenticated;

alter table public.terminal_events drop constraint if exists terminal_events_event_check;
alter table public.terminal_events add constraint terminal_events_event_check check (event in (
  'admin_card', 'mode_changed', 'poll_pinned', 'poll_created', 'poll_status',
  'applications_toggled', 'unlock',
  'card_registered', 'card_assigned', 'card_replaced', 'card_blocked',
  'activation_code', 'account_activated',
  'pin_set', 'pin_failed', 'pin_reset'
));

-- ---------------------------------------------------------------------------
-- Comprobación del PIN con límite de intentos (interna)
-- Devuelve el resultado en vez de lanzar error para que el conteo de fallos se conserve.
-- ---------------------------------------------------------------------------
create or replace function public.terminal_pin_check(p_admin uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cur public.terminal_admin_pins;
  left_tries int;
begin
  select * into cur from public.terminal_admin_pins where profile_id = p_admin for update;
  if not found then return jsonb_build_object('ok', false, 'no_pin', true); end if;
  if cur.locked_until is not null and cur.locked_until > now() then
    return jsonb_build_object('ok', false, 'locked_until', cur.locked_until);
  end if;
  if p_pin is not null and cur.pin_hash = extensions.crypt(p_pin, cur.pin_hash) then
    update public.terminal_admin_pins set failed_attempts = 0, locked_until = null where profile_id = p_admin;
    return jsonb_build_object('ok', true);
  end if;
  if cur.failed_attempts + 1 >= 5 then
    update public.terminal_admin_pins set failed_attempts = 0, locked_until = now() + interval '15 minutes'
     where profile_id = p_admin;
    insert into public.terminal_events(operator_id, actor_id, event, detail)
    values (auth.uid(), p_admin, 'pin_failed', '{"locked":true}'::jsonb);
    return jsonb_build_object('ok', false, 'locked_until', now() + interval '15 minutes');
  end if;
  update public.terminal_admin_pins set failed_attempts = cur.failed_attempts + 1 where profile_id = p_admin;
  left_tries := 5 - (cur.failed_attempts + 1);
  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), p_admin, 'pin_failed', jsonb_build_object('attempts_left', left_tries));
  return jsonb_build_object('ok', false, 'attempts_left', left_tries);
end;
$$;
revoke all on function public.terminal_pin_check(uuid, text) from public, anon, authenticated;

-- Valida un ticket del operador (no usado, de hace menos de ~3 minutos)
create or replace function public.terminal_open_ticket(p_ticket uuid)
returns public.terminal_unlock_tickets
language plpgsql
security definer
set search_path = ''
as $$
declare t public.terminal_unlock_tickets;
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into t from public.terminal_unlock_tickets
   where id = p_ticket and operator_id = auth.uid() and not used and expires_at > now() - interval '2 minutes';
  if not found or t.card_profile_id is null then
    raise exception 'invalid_ticket' using errcode = '42501';
  end if;
  return t;
end;
$$;
revoke all on function public.terminal_open_ticket(uuid) from public, anon, authenticated;

create or replace function public.terminal_start_admin_session(p_ticket uuid, p_admin uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.terminal_unlock_tickets set pin_ok = true where id = p_ticket;
  insert into public.terminal_admin_sessions(operator_id, admin_id, expires_at)
  values (auth.uid(), p_admin, now() + interval '10 minutes')
  on conflict (operator_id) do update set admin_id = excluded.admin_id, expires_at = excluded.expires_at;
end;
$$;
revoke all on function public.terminal_start_admin_session(uuid, uuid) from public, anon, authenticated;

-- Crear el PIN (primera vez) o cambiarlo (con el PIN anterior). Requiere la tarjeta (ticket).
create or replace function public.terminal_pin_set(p_ticket uuid, p_pin text, p_old_pin text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.terminal_unlock_tickets := public.terminal_open_ticket(p_ticket);
  res jsonb;
begin
  if p_pin is null or p_pin !~ '^[0-9]{6}$' then raise exception 'invalid_pin'; end if;
  if p_pin ~ '^([0-9])\1{5}$' or p_pin in ('123456', '654321', '012345', '123123', '121212') then
    raise exception 'weak_pin';
  end if;
  if exists (select 1 from public.terminal_admin_pins where profile_id = t.card_profile_id) then
    res := public.terminal_pin_check(t.card_profile_id, p_old_pin);
    if not (res->>'ok')::boolean then return res; end if;
  end if;
  insert into public.terminal_admin_pins(profile_id, pin_hash, failed_attempts, locked_until, updated_at)
  values (t.card_profile_id, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)), 0, null, now())
  on conflict (profile_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, updated_at = now();
  perform public.terminal_start_admin_session(p_ticket, t.card_profile_id);
  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), t.card_profile_id, 'pin_set', '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.terminal_pin_verify(p_ticket uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.terminal_unlock_tickets := public.terminal_open_ticket(p_ticket);
  res jsonb;
begin
  res := public.terminal_pin_check(t.card_profile_id, p_pin);
  if (res->>'ok')::boolean then
    perform public.terminal_start_admin_session(p_ticket, t.card_profile_id);
  end if;
  return res;
end;
$$;

-- Sesión de administrador: estado, cierre y exigencia
create or replace function public.terminal_admin_session_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare s public.terminal_admin_sessions;
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into s from public.terminal_admin_sessions where operator_id = auth.uid() and expires_at > now();
  if not found then return jsonb_build_object('active', false); end if;
  return jsonb_build_object('active', true, 'seconds_left', greatest(0, extract(epoch from s.expires_at - now())::int));
end;
$$;

create or replace function public.terminal_end_admin_session()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  delete from public.terminal_admin_sessions where operator_id = auth.uid();
end;
$$;

-- Exige una sesión vigente cuya tarjeta sea de un administrador activo; la renueva.
create or replace function public.terminal_require_admin_session()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid;
begin
  update public.terminal_admin_sessions s
     set expires_at = now() + interval '10 minutes'
   where s.operator_id = auth.uid() and s.expires_at > now()
     and exists (select 1 from public.profiles p join public.roles r on r.id = p.role_id
                 where p.id = s.admin_id and p.status = 'active' and r.name = 'admin')
  returning s.admin_id into v_admin;
  if v_admin is null then raise exception 'admin_session_required' using errcode = '42501'; end if;
  return v_admin;
end;
$$;
revoke all on function public.terminal_require_admin_session() from public, anon, authenticated;

-- Para las Edge Functions (service_role)
create or replace function public.operator_admin_session(p_operator uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_admin uuid;
begin
  update public.terminal_admin_sessions s
     set expires_at = now() + interval '10 minutes'
   where s.operator_id = p_operator and s.expires_at > now()
     and exists (select 1 from public.profiles p join public.roles r on r.id = p.role_id
                 where p.id = s.admin_id and p.status = 'active' and r.name = 'admin')
  returning s.admin_id into v_admin;
  return v_admin is not null;
end;
$$;
revoke all on function public.operator_admin_session(uuid) from public, anon, authenticated;
grant execute on function public.operator_admin_session(uuid) to service_role;

-- Restablecer un PIN olvidado: uno mismo (con permiso terminal.unlock) o un administrador a otra persona.
create or replace function public.reset_terminal_pin(p_profile_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_target uuid := coalesce(p_profile_id, auth.uid());
begin
  if auth.uid() is null then raise exception 'forbidden' using errcode = '42501'; end if;
  if v_target = auth.uid() then
    if not public.has_permission('terminal.unlock') then raise exception 'forbidden' using errcode = '42501'; end if;
  elsif not public.can_register_cards() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  delete from public.terminal_admin_pins where profile_id = v_target;
  delete from public.terminal_admin_sessions where admin_id = v_target;
  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), v_target, 'pin_reset', '{}'::jsonb);
end;
$$;

revoke all on function public.terminal_pin_set(uuid, text, text), public.terminal_pin_verify(uuid, text),
  public.terminal_admin_session_status(), public.terminal_end_admin_session(), public.reset_terminal_pin(uuid)
from public, anon;
grant execute on function public.terminal_pin_set(uuid, text, text), public.terminal_pin_verify(uuid, text),
  public.terminal_admin_session_status(), public.terminal_end_admin_session(), public.reset_terminal_pin(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- terminal_scan: la tarjeta de administrador informa si ya hay PIN y si la sesión sigue abierta
-- ---------------------------------------------------------------------------
create or replace function public.terminal_scan(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  card_profile uuid;
  card_name text;
  is_admin_card boolean;
  token uuid;
  v_pin_set boolean;
  v_session boolean;
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select p.id, p.full_name,
         exists (
           select 1 from public.role_permissions rp
           where rp.role_id = p.role_id and rp.permission_code = 'terminal.unlock'
         )
    into card_profile, card_name, is_admin_card
  from public.nfc_cards c
  join public.profiles p on p.id = c.profile_id
  where c.active
    and p.status = 'active'
    and upper(regexp_replace(c.card_uid, '[^0-9A-Fa-f]', '', 'g')) = upper(regexp_replace(p_card_uid, '[: -]', '', 'g'))
  limit 1;

  if card_profile is null then
    raise exception 'invalid_card';
  end if;

  if is_admin_card then
    v_pin_set := exists (select 1 from public.terminal_admin_pins where profile_id = card_profile);
    v_session := v_pin_set and exists (
      select 1 from public.terminal_admin_sessions s
      where s.operator_id = auth.uid() and s.admin_id = card_profile and s.expires_at > now()
    );
    insert into public.terminal_unlock_tickets(operator_id, card_profile_id, pin_ok)
    values (auth.uid(), card_profile, v_session)
    returning id into token;
    insert into public.terminal_events(operator_id, actor_id, event, detail)
    values (auth.uid(), card_profile, 'admin_card', '{}'::jsonb);
    return jsonb_build_object('kind', 'admin', 'ticket', token, 'name', card_name,
                              'pin_set', v_pin_set, 'pin_ok', v_session);
  end if;

  insert into public.terminal_profile_access(operator_id, student_id, expires_at)
  values (auth.uid(), card_profile, now() + interval '2 minutes')
  on conflict (operator_id) do update
    set student_id = excluded.student_id,
        expires_at = excluded.expires_at;

  return jsonb_build_object(
    'kind', 'person',
    'profile', public.terminal_profile_payload(card_profile)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Desbloquear y registrar eventos exigen un ticket con PIN verificado
-- ---------------------------------------------------------------------------
create or replace function public.consume_terminal_unlock(p_token uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket_operator uuid;
  ticket_actor uuid;
begin
  update public.terminal_unlock_tickets as t
  set used = true
  where t.id = p_token and not t.used and t.pin_ok and t.expires_at > now()
  returning t.operator_id, t.card_profile_id into ticket_operator, ticket_actor;

  if not found then
    return false;
  end if;

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (ticket_operator, ticket_actor, 'unlock', '{}'::jsonb);
  return true;
end;
$$;

create or replace function public.log_terminal_event(
  p_ticket uuid,
  p_event text,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket public.terminal_unlock_tickets%rowtype;
  safe_detail jsonb := coalesce(p_detail, '{}'::jsonb);
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_event is null or p_event not in (
    'mode_changed', 'poll_pinned', 'poll_created',
    'poll_status', 'applications_toggled'
  ) then
    raise exception 'invalid_event';
  end if;

  if length(safe_detail::text) > 2000 then
    raise exception 'detail_too_large';
  end if;

  if jsonb_typeof(safe_detail) <> 'object' then
    raise exception 'invalid_detail';
  end if;

  select t.* into ticket
  from public.terminal_unlock_tickets t
  where t.id = p_ticket
    and t.operator_id = auth.uid()
    and t.pin_ok
    and t.expires_at > now() - interval '15 minutes';

  if ticket.id is null then
    raise exception 'invalid_ticket' using errcode = '42501';
  end if;

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), ticket.card_profile_id, p_event, safe_detail);
end;
$$;

-- ---------------------------------------------------------------------------
-- Asignar/buscar tarjetas exigen la sesión de administrador (tarjeta + PIN)
-- ---------------------------------------------------------------------------
create or replace function public.terminal_assign_card(
  p_card_uid text,
  p_profile_id uuid,
  p_replace boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_compact text;
  v_profile public.profiles;
  v_existing public.nfc_cards;
  v_type text;
  v_replaced boolean := false;
begin
  if not public.can_register_cards() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform public.terminal_require_admin_session();

  v_uid := public.normalize_card_uid(p_card_uid);
  v_compact := replace(v_uid, ':', '');
  perform pg_advisory_xact_lock(hashtextextended(v_compact, 0));

  select * into v_profile from public.profiles where id = p_profile_id and status = 'active';
  if not found then raise exception 'person_not_found'; end if;

  select * into v_existing from public.nfc_cards
  where upper(regexp_replace(card_uid, '[^0-9A-Fa-f]', '', 'g')) = v_compact
  limit 1 for update;

  if found then
    if v_existing.profile_id is distinct from p_profile_id then
      raise exception 'card_already_assigned'
        using detail = coalesce((select full_name from public.profiles where id = v_existing.profile_id), '');
    end if;
    if v_existing.active then
      return jsonb_build_object('ok', true, 'already', true, 'name', v_profile.full_name);
    end if;
  end if;

  -- ¿Ya tiene otra tarjeta activa?
  if exists (select 1 from public.nfc_cards where profile_id = p_profile_id and active
             and upper(regexp_replace(card_uid, '[^0-9A-Fa-f]', '', 'g')) <> v_compact) then
    if not p_replace then raise exception 'person_has_card'; end if;
    v_type := public.card_default_type(p_profile_id);
    if v_type = 'admin' then
      delete from public.nfc_cards where profile_id = p_profile_id and card_type = 'admin';
    end if;
    update public.nfc_cards
       set active = false, label = 'Reemplazada', updated_at = now()
     where profile_id = p_profile_id and active
       and upper(regexp_replace(card_uid, '[^0-9A-Fa-f]', '', 'g')) <> v_compact;
    v_replaced := true;
  end if;

  v_type := public.card_default_type(p_profile_id);
  if v_existing.id is not null then
    update public.nfc_cards set active = true, label = 'Tarjeta personal', updated_at = now()
     where id = v_existing.id;
  else
    begin
      insert into public.nfc_cards(card_uid, profile_id, card_type, label, active, registered_by)
      values (v_uid, p_profile_id, v_type, 'Tarjeta personal', true, auth.uid());
    exception when unique_violation then
      raise exception 'admin_card_already_registered';
    end;
  end if;

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), p_profile_id, case when v_replaced then 'card_replaced' else 'card_assigned' end,
          jsonb_build_object('name', v_profile.full_name));

  return jsonb_build_object('ok', true, 'replaced', v_replaced, 'name', v_profile.full_name);
end;
$$;

create or replace function public.terminal_search_people(p_query text)
returns table (id uuid, full_name text, role text, level text, has_card boolean, activation_pending boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare q text := lower(trim(coalesce(p_query, '')));
begin
  if not public.can_register_cards() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  perform public.terminal_require_admin_session();
  if length(q) < 2 then return; end if;
  return query
    select p.id, p.full_name, r.name::text, sl.name::text,
           exists (select 1 from public.nfc_cards c where c.profile_id = p.id and c.active),
           p.activation_pending
    from public.profiles p
    join public.roles r on r.id = p.role_id
    left join public.student_details sd on sd.profile_id = p.id
    left join public.school_levels sl on sl.id = sd.level_id
    where p.status = 'active'
      and (position(q in lower(p.full_name)) > 0 or position(q in lower(p.email)) > 0)
    order by p.full_name
    limit 20;
end;
$$;
