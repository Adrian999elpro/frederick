-- Record the first administrative card in a non-exposed schema. The marker remains
-- after a card is removed so the one-time setup action never appears again.
create schema if not exists fwt_private;
revoke all on schema fwt_private from public, anon, authenticated;

create table if not exists fwt_private.initial_admin_card_registration (
  singleton boolean primary key default true check (singleton),
  card_uid text not null,
  profile_id uuid not null references public.profiles(id),
  registered_by uuid not null references public.profiles(id),
  registered_at timestamptz not null default now()
);

alter table fwt_private.initial_admin_card_registration enable row level security;
revoke all on table fwt_private.initial_admin_card_registration from public, anon, authenticated;

create unique index if not exists nfc_cards_single_admin_type_idx
  on public.nfc_cards (card_type)
  where card_type = 'admin';

insert into fwt_private.initial_admin_card_registration
  (singleton, card_uid, profile_id, registered_by, registered_at)
select true, c.card_uid, c.profile_id, coalesce(c.registered_by, c.profile_id), c.created_at
from public.nfc_cards c
where c.card_type = 'admin' and c.profile_id is not null
order by c.created_at
limit 1
on conflict (singleton) do nothing;

create or replace function fwt_private.remember_admin_card_registration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.card_type = 'admin' then
    if new.profile_id is null
       or upper(trim(coalesce(new.card_uid, ''))) !~ '^([0-9A-F]{2}:){3,9}[0-9A-F]{2}$'
       or not exists (
         select 1
         from public.profiles p
         join public.roles r on r.id = p.role_id
         where p.id = new.profile_id
           and p.status = 'active'
           and r.name = 'admin'
       ) then
      raise exception 'admin_card_must_use_nfc_uid_and_active_admin_account'
        using errcode = '42501';
    end if;

    insert into fwt_private.initial_admin_card_registration
      (singleton, card_uid, profile_id, registered_by)
    values (true, upper(trim(new.card_uid)), new.profile_id, coalesce(new.registered_by, new.profile_id))
    on conflict (singleton) do nothing;
  end if;

  return new;
end;
$$;

revoke all on function fwt_private.remember_admin_card_registration() from public, anon, authenticated;

drop trigger if exists remember_admin_card_registration on public.nfc_cards;
create trigger remember_admin_card_registration
after insert or update of card_type, profile_id on public.nfc_cards
for each row
when (new.card_type = 'admin')
execute function fwt_private.remember_admin_card_registration();

create or replace function public.admin_card_registration_status()
returns boolean
language plpgsql
stable
security definer
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
    from fwt_private.initial_admin_card_registration
    where singleton
  ) or exists (
    select 1
    from public.nfc_cards
    where card_type = 'admin'
  );
end;
$$;

create or replace function public.register_initial_admin_card(p_card_uid text)
returns jsonb
language plpgsql
security definer
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

  insert into fwt_private.initial_admin_card_registration
    (singleton, card_uid, profile_id, registered_by)
  values (true, v_uid, v_user, v_user)
  on conflict (singleton) do nothing;

  if not found then
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
