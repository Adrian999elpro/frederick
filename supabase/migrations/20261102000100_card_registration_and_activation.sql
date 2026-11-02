-- Registro de tarjetas solo para administradores (desde el terminal) y activación de la
-- cuenta web con un código de un solo uso válido 24 horas.
--
-- Flujo:
--  1. El administrador registra en el terminal: tarjeta + nombre (+ rol y curso). La Edge
--     Function terminal-register-card crea una cuenta "pendiente" con correo provisional.
--  2. La persona acerca su tarjeta al terminal y pide su código (terminal_issue_activation_code).
--  3. En la web (activar.html) escribe su correo, el código y su contraseña (Edge Function
--     activate-account). La cuenta queda ligada a su nombre y a su tarjeta.

-- ---------------------------------------------------------------------------
-- 1. Cuentas pendientes de activar
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists activation_pending boolean not null default false;

create table if not exists public.account_activation_codes (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  issued_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.account_activation_codes enable row level security;
revoke all on public.account_activation_codes from public, anon, authenticated;

create table if not exists public.activation_attempts (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  success boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists activation_attempts_ip_idx on public.activation_attempts(ip_hash, created_at desc);
alter table public.activation_attempts enable row level security;
revoke all on public.activation_attempts from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Permiso: solo administradores registran tarjetas
-- ---------------------------------------------------------------------------
insert into public.permissions(code, description)
values ('cards.register', 'Registrar y reemplazar tarjetas NFC desde el terminal')
on conflict do nothing;

insert into public.role_permissions(role_id, permission_code)
select r.id, 'cards.register' from public.roles r where r.name = 'admin'
on conflict do nothing;

create or replace function public.can_register_cards()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.has_permission('cards.register')
    and exists (
      select 1
      from public.profiles p
      join public.roles r on r.id = p.role_id
      where p.id = auth.uid() and p.status = 'active' and r.name = 'admin'
    );
$$;
revoke all on function public.can_register_cards() from public, anon;
grant execute on function public.can_register_cards() to authenticated;

-- Nadie escribe en nfc_cards desde el cliente: todo pasa por funciones de administrador.
drop policy if exists nfc_cards_manage on public.nfc_cards;
revoke insert, update, delete on public.nfc_cards from authenticated, anon;
-- Se retiran la vinculación manual de tarjetas y el registro por solicitud (el estudiante
-- escribía su tarjeta en la web). Solo si la función existe en esta base.
do $retire$
declare f text;
begin
  foreach f in array array[
    'public.save_nfc_card_binding(uuid,text,uuid,text,text,boolean)',
    'public.submit_enrollment(text,text,uuid,text)',
    'public.review_enrollment(uuid,boolean)'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('revoke execute on function %s from public, anon, authenticated', f);
    end if;
  end loop;
end
$retire$;

-- ---------------------------------------------------------------------------
-- 3. Eventos del terminal (nuevos tipos)
-- ---------------------------------------------------------------------------
alter table public.terminal_events drop constraint if exists terminal_events_event_check;
alter table public.terminal_events add constraint terminal_events_event_check check (event in (
  'admin_card', 'mode_changed', 'poll_pinned', 'poll_created', 'poll_status',
  'applications_toggled', 'unlock',
  'card_registered', 'card_assigned', 'card_replaced', 'card_blocked',
  'activation_code', 'account_activated'
));

-- ---------------------------------------------------------------------------
-- 4. Utilidades internas
-- ---------------------------------------------------------------------------
create or replace function public.normalize_card_uid(p_uid text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare raw text := upper(regexp_replace(coalesce(p_uid, ''), '[: -]', '', 'g'));
begin
  if raw !~ '^([0-9A-F]{2}){4,10}$' then
    raise exception 'invalid_card' using errcode = '22023';
  end if;
  return regexp_replace(raw, '(..)(?=.)', '\1:', 'g');
end;
$$;
revoke all on function public.normalize_card_uid(text) from public, anon, authenticated;

create or replace function public.normalize_activation_code(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$ select upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); $$;
revoke all on function public.normalize_activation_code(text) from public, anon, authenticated;

create or replace function public.hash_activation_code(p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to(public.normalize_activation_code(p_code), 'utf8')), 'hex');
$$;
revoke all on function public.hash_activation_code(text) from public, anon, authenticated;

-- Código de 8 caracteres sin letras ni números que se confunden (0, 1, O, I, L).
create or replace function public.gen_activation_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  pick constant int[] := array[0, 1, 2, 3, 4, 5, 9, 10]; -- evita los bytes con bits de versión
  out text := '';
  i int;
begin
  foreach i in array pick loop
    out := out || substr(alphabet, (get_byte(bytes, i) % 31) + 1, 1);
  end loop;
  return out;
end;
$$;
revoke all on function public.gen_activation_code() from public, anon, authenticated;

create or replace function public.card_default_type(p_profile_id uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select case r.name when 'admin' then 'admin' when 'docente' then 'docente' else 'estudiante' end
  from public.profiles p join public.roles r on r.id = p.role_id
  where p.id = p_profile_id;
$$;
revoke all on function public.card_default_type(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Asignar o reemplazar la tarjeta de una persona que ya tiene cuenta
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

-- Bloquear o desbloquear una tarjeta (tarjeta perdida). No necesita leer NFC: se puede hacer desde la web.
create or replace function public.set_card_active(p_card_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_card public.nfc_cards;
begin
  if not public.can_register_cards() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.nfc_cards set active = coalesce(p_active, false), updated_at = now()
   where id = p_card_id returning * into v_card;
  if not found then raise exception 'card_not_found'; end if;
  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), v_card.profile_id, 'card_blocked', jsonb_build_object('active', coalesce(p_active, false)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Código de activación (lo pide la propia persona con su tarjeta en el terminal)
-- ---------------------------------------------------------------------------
create or replace function public.terminal_issue_activation_code(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_compact text;
  v_code text;
  v_expires timestamptz := now() + interval '24 hours';
  v_try int := 0;
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v_compact := replace(public.normalize_card_uid(p_card_uid), ':', '');

  select p.* into v_profile
  from public.nfc_cards c
  join public.profiles p on p.id = c.profile_id
  where c.active and p.status = 'active'
    and upper(regexp_replace(c.card_uid, '[^0-9A-Fa-f]', '', 'g')) = v_compact
  limit 1;
  if not found then raise exception 'invalid_card'; end if;
  if not v_profile.activation_pending then raise exception 'already_activated'; end if;

  loop
    v_try := v_try + 1;
    v_code := public.gen_activation_code();
    begin
      insert into public.account_activation_codes(profile_id, code_hash, expires_at, issued_by)
      values (v_profile.id, public.hash_activation_code(v_code), v_expires, auth.uid())
      on conflict (profile_id) do update
        set code_hash = excluded.code_hash, expires_at = excluded.expires_at,
            issued_by = excluded.issued_by, created_at = now();
      exit;
    exception when unique_violation then
      if v_try >= 5 then raise exception 'try_again'; end if;
    end;
  end loop;

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), v_profile.id, 'activation_code', '{}'::jsonb);

  return jsonb_build_object(
    'code', substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4),
    'expires_at', v_expires,
    'name', v_profile.full_name
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Funciones solo para las Edge Functions (service_role)
-- ---------------------------------------------------------------------------
create or replace function public.card_registration_precheck(p_card_uid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_uid text := public.normalize_card_uid(p_card_uid); v_owner uuid;
begin
  select c.profile_id into v_owner from public.nfc_cards c
  where upper(regexp_replace(c.card_uid, '[^0-9A-Fa-f]', '', 'g')) = replace(v_uid, ':', '') limit 1;
  return jsonb_build_object('uid', v_uid, 'taken', found,
    'owner_name', (select full_name from public.profiles where id = v_owner));
end;
$$;

create or replace function public.finalize_card_registration(
  p_actor uuid, p_profile_id uuid, p_card_uid text, p_full_name text, p_level_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid text := public.normalize_card_uid(p_card_uid); v_type text; v_name text := trim(coalesce(p_full_name, ''));
begin
  if length(v_name) not between 2 and 120 then raise exception 'invalid_name'; end if;
  perform pg_advisory_xact_lock(hashtextextended(replace(v_uid, ':', ''), 0));
  if exists (select 1 from public.nfc_cards
             where upper(regexp_replace(card_uid, '[^0-9A-Fa-f]', '', 'g')) = replace(v_uid, ':', '')) then
    raise exception 'card_already_assigned';
  end if;
  v_type := public.card_default_type(p_profile_id);
  if v_type = 'admin' then raise exception 'invalid_role'; end if;

  update public.profiles
     set full_name = v_name, activation_pending = true, must_change_password = false, updated_at = now()
   where id = p_profile_id;
  if not found then raise exception 'person_not_found'; end if;

  if p_level_id is not null then
    insert into public.student_details(profile_id, level_id) values (p_profile_id, p_level_id)
    on conflict (profile_id) do update set level_id = excluded.level_id, updated_at = now();
  end if;

  insert into public.nfc_cards(card_uid, profile_id, card_type, label, active, registered_by)
  values (v_uid, p_profile_id, v_type, 'Tarjeta personal', true, p_actor);

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (p_actor, p_profile_id, 'card_registered', jsonb_build_object('name', v_name));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.activation_lookup(p_code text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.profile_id
  from public.account_activation_codes a
  join public.profiles p on p.id = a.profile_id
  where a.code_hash = public.hash_activation_code(p_code)
    and a.expires_at > now()
    and p.activation_pending and p.status = 'active';
$$;

create or replace function public.complete_account_activation(p_profile_id uuid, p_email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set email = lower(trim(p_email)), activation_pending = false, must_change_password = false, updated_at = now()
   where id = p_profile_id and activation_pending;
  if not found then return false; end if;
  delete from public.account_activation_codes where profile_id = p_profile_id;
  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (p_profile_id, p_profile_id, 'account_activated', '{}'::jsonb);
  return true;
end;
$$;

revoke all on function
  public.card_registration_precheck(text),
  public.finalize_card_registration(uuid, uuid, text, text, uuid),
  public.activation_lookup(text),
  public.complete_account_activation(uuid, text)
from public, anon, authenticated;
grant execute on function
  public.card_registration_precheck(text),
  public.finalize_card_registration(uuid, uuid, text, text, uuid),
  public.activation_lookup(text),
  public.complete_account_activation(uuid, text)
to service_role;

-- ---------------------------------------------------------------------------
-- 8. Directorio de tarjetas para la web (solo lectura)
-- ---------------------------------------------------------------------------
create or replace function public.list_card_directory()
returns table (
  profile_id uuid, full_name text, email text, role text, level text, status text,
  card_id uuid, card_hint text, card_type text, card_active boolean, card_since timestamptz,
  registered_by_name text, activation_pending boolean, code_valid boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_permission('nfc.manage') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
    select p.id, p.full_name,
           case when p.activation_pending then null else p.email end,
           r.name::text, sl.name::text, p.status::text,
           c.id, case when c.id is null then null else '••' || right(c.card_uid, 5) end,
           c.card_type::text, c.active, c.created_at,
           (select rp.full_name from public.profiles rp where rp.id = c.registered_by),
           p.activation_pending,
           exists (select 1 from public.account_activation_codes a
                   where a.profile_id = p.id and a.expires_at > now())
    from public.profiles p
    join public.roles r on r.id = p.role_id
    left join public.student_details sd on sd.profile_id = p.id
    left join public.school_levels sl on sl.id = sd.level_id
    left join lateral (
      select * from public.nfc_cards x where x.profile_id = p.id
      order by x.active desc, x.created_at desc limit 1
    ) c on true
    order by p.full_name, p.email;
end;
$$;

revoke all on function public.terminal_assign_card(text, uuid, boolean),
  public.terminal_search_people(text), public.set_card_active(uuid, boolean),
  public.terminal_issue_activation_code(text), public.list_card_directory()
from public, anon;
grant execute on function public.terminal_assign_card(text, uuid, boolean),
  public.terminal_search_people(text), public.set_card_active(uuid, boolean),
  public.terminal_issue_activation_code(text), public.list_card_directory()
to authenticated;

-- ---------------------------------------------------------------------------
-- 9. El perfil del terminal avisa si falta activar el acceso web
-- ---------------------------------------------------------------------------
create or replace function public.terminal_profile_payload(p_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'full_name', p.full_name,
    'nickname', c.nickname,
    'headline', c.headline,
    'bio', c.bio,
    'accent', c.accent,
    'badge', c.badge,
    'level', sl.name,
    'activation_pending', p.activation_pending,
    'grades', coalesce((
      select jsonb_agg(
        jsonb_build_object('subject', s.name, 'period', gp.name, 'score', g.score)
        order by gp.order_index, s.name
      )
      from public.grades g
      join public.subjects s on s.id = g.subject_id
      join public.grade_periods gp on gp.id = g.period_id
      where g.student_id = p.id
    ), '[]'::jsonb)
  )
  from public.profiles p
  left join public.profile_customizations c on c.profile_id = p.id
  left join public.student_details sd on sd.profile_id = p.id
  left join public.school_levels sl on sl.id = sd.level_id
  where p.id = p_profile_id;
$$;
revoke all on function public.terminal_profile_payload(uuid) from public, anon, authenticated;
