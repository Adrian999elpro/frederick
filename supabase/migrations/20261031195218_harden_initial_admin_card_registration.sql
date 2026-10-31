-- Expose the one-time setup marker only to an active administrator with NFC management access.
grant usage on schema fwt_private to authenticated;
grant select on table fwt_private.initial_admin_card_registration to authenticated;

drop policy if exists initial_admin_card_registration_admin_read
  on fwt_private.initial_admin_card_registration;
create policy initial_admin_card_registration_admin_read
  on fwt_private.initial_admin_card_registration
  for select to authenticated
  using (
    public.has_permission('nfc.manage')
    and exists (
      select 1
      from public.profiles p
      join public.roles r on r.id = p.role_id
      where p.id = auth.uid()
        and p.status = 'active'
        and r.name = 'admin'
    )
  );

create or replace function public.admin_card_registration_status()
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null
     or not public.has_permission('nfc.manage')
     or not exists (
       select 1
       from public.profiles p
       join public.roles r on r.id = p.role_id
       where p.id = v_user
         and p.status = 'active'
         and r.name = 'admin'
     ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return exists (
    select 1
    from fwt_private.initial_admin_card_registration marker
    where marker.singleton
  );
end;
$$;

create or replace function public.register_initial_admin_card(p_card_uid text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_uid text := upper(trim(coalesce(p_card_uid, '')));
  v_card_id uuid;
begin
  if v_user is null
     or not public.has_permission('nfc.manage')
     or not exists (
       select 1
       from public.profiles p
       join public.roles r on r.id = p.role_id
       where p.id = v_user
         and p.status = 'active'
         and r.name = 'admin'
     ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if v_uid !~ '^([0-9A-F]{2}:){3,9}[0-9A-F]{2}$' then
    raise exception 'invalid_nfc_uid' using errcode = '22023';
  end if;

  if exists (
    select 1
    from fwt_private.initial_admin_card_registration marker
    where marker.singleton
  ) then
    raise exception 'admin_card_already_registered' using errcode = '23505';
  end if;

  insert into public.nfc_cards
    (card_uid, profile_id, card_type, label, active, registered_by, created_at, updated_at)
  values
    (v_uid, v_user, 'admin', 'Tarjeta administrativa principal', true, v_user, now(), now())
  returning id into v_card_id;

  return jsonb_build_object(
    'ok', true,
    'card_id', v_card_id,
    'card_uid', v_uid
  );
end;
$$;

revoke all on function public.admin_card_registration_status() from public, anon;
revoke all on function public.register_initial_admin_card(text) from public, anon;
grant execute on function public.admin_card_registration_status() to authenticated;
grant execute on function public.register_initial_admin_card(text) to authenticated;
