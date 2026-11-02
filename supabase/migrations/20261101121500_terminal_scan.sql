-- Une la lectura de tarjeta de administrador y la consulta de perfil en una
-- sola RPC. El payload del perfil se comparte con la función ya existente.
alter table public.terminal_unlock_tickets
  add column card_profile_id uuid references public.profiles(id);

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

create or replace function public.authorize_terminal_card(p_card_uid text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  card_user uuid;
  token uuid;
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select p.id into card_user
  from public.nfc_cards c
  join public.profiles p on p.id = c.profile_id
  where c.active
    and p.status = 'active'
    and upper(regexp_replace(c.card_uid, '[^0-9A-Fa-f]', '', 'g')) = upper(regexp_replace(p_card_uid, '[: -]', '', 'g'))
    and exists (
      select 1 from public.role_permissions rp
      where rp.role_id = p.role_id and rp.permission_code = 'terminal.unlock'
    )
  limit 1;

  if card_user is null then
    raise exception 'card_not_authorized' using errcode = '42501';
  end if;

  insert into public.terminal_unlock_tickets(operator_id, card_profile_id)
  values (auth.uid(), card_user)
  returning id into token;
  return token;
end;
$$;

create or replace function public.terminal_student_profile(p_card_uid text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  student uuid;
begin
  if auth.uid() is null or not public.has_permission('terminal.operate') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select p.id into student
  from public.nfc_cards c
  join public.profiles p on p.id = c.profile_id
  where c.active
    and p.status = 'active'
    and upper(regexp_replace(c.card_uid, '[^0-9A-Fa-f]', '', 'g')) = upper(regexp_replace(p_card_uid, '[: -]', '', 'g'))
  limit 1;

  if student is null then
    raise exception 'invalid_card';
  end if;

  insert into public.terminal_profile_access(operator_id, student_id, expires_at)
  values (auth.uid(), student, now() + interval '2 minutes')
  on conflict (operator_id) do update
    set student_id = excluded.student_id,
        expires_at = excluded.expires_at;

  return public.terminal_profile_payload(student);
end;
$$;

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

revoke all on function public.authorize_terminal_card(text) from public, anon;
revoke all on function public.terminal_student_profile(text) from public, anon;
revoke all on function public.terminal_scan(text) from public, anon;
grant execute on function public.authorize_terminal_card(text) to authenticated;
grant execute on function public.terminal_student_profile(text) to authenticated;
grant execute on function public.terminal_scan(text) to authenticated;
