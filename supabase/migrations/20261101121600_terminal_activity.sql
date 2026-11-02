-- Registra operaciones administrativas del terminal. Los estudiantes que
-- solo consultan su perfil no generan eventos.
create table public.terminal_events (
  id bigint generated always as identity primary key,
  operator_id uuid not null references public.profiles(id),
  actor_id uuid references public.profiles(id),
  event text not null check (event in (
    'admin_card', 'mode_changed', 'poll_pinned', 'poll_created',
    'poll_status', 'applications_toggled', 'unlock'
  )),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index terminal_events_created_idx
  on public.terminal_events(created_at desc);

alter table public.terminal_events enable row level security;
revoke all on public.terminal_events from anon, authenticated;

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
    and t.expires_at > now() - interval '15 minutes';

  if ticket.id is null then
    raise exception 'invalid_ticket' using errcode = '42501';
  end if;

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (auth.uid(), ticket.card_profile_id, p_event, safe_detail);
end;
$$;

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
  where t.id = p_token and not t.used and t.expires_at > now()
  returning t.operator_id, t.card_profile_id into ticket_operator, ticket_actor;

  if not found then
    return false;
  end if;

  insert into public.terminal_events(operator_id, actor_id, event, detail)
  values (ticket_operator, ticket_actor, 'unlock', '{}'::jsonb);
  return true;
end;
$$;

create or replace function public.list_terminal_events(p_limit int default 100)
returns table (
  event_id bigint,
  created_at timestamptz,
  operator_name text,
  operator_email text,
  actor_name text,
  event text,
  detail jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.has_permission('users.manage') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select e.id,
         e.created_at,
         coalesce(nullif(op.full_name, ''), op.email),
         op.email,
         coalesce(nullif(actor.full_name, ''), actor.email),
         e.event,
         e.detail
  from public.terminal_events e
  join public.profiles op on op.id = e.operator_id
  left join public.profiles actor on actor.id = e.actor_id
  order by e.created_at desc, e.id desc
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

-- El uso de la tarjeta del administrador sí se registra; la consulta de una
-- tarjeta de estudiante nunca queda anotada.
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
    insert into public.terminal_unlock_tickets(operator_id, card_profile_id)
    values (auth.uid(), card_profile)
    returning id into token;
    insert into public.terminal_events(operator_id, actor_id, event, detail)
    values (auth.uid(), card_profile, 'admin_card', '{}'::jsonb);
    return jsonb_build_object('kind', 'admin', 'ticket', token, 'name', card_name);
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

revoke all on function public.log_terminal_event(uuid, text, jsonb) from public, anon;
revoke all on function public.consume_terminal_unlock(uuid) from public, anon;
revoke all on function public.list_terminal_events(integer) from public, anon;
revoke all on function public.terminal_scan(text) from public, anon;
grant execute on function public.log_terminal_event(uuid, text, jsonb) to authenticated;
grant execute on function public.consume_terminal_unlock(uuid) to anon, authenticated;
grant execute on function public.list_terminal_events(integer) to authenticated;
grant execute on function public.terminal_scan(text) to authenticated;
