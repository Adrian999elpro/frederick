-- =====================================================================
-- 0002_elections.sql
-- Votaciones estudiantiles: listas con foto del presidente, voto secreto
-- y Estadísticas Electorales. Depende de 0001_auth_core.sql.
-- =====================================================================

create table public.elections (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 120),
  description text not null default '' check (char_length(description) <= 500),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'draft' check (status in ('draft','open','closed')),
  created_by uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.election_lists (
  id uuid primary key default gen_random_uuid(),
  election_id uuid not null references public.elections(id) on delete cascade,
  number int not null check (number between 1 and 99),
  name text not null check (char_length(name) between 1 and 80),
  slogan text not null default '' check (char_length(slogan) <= 160),
  president_name text not null check (char_length(president_name) between 1 and 80),
  president_photo text check (president_photo is null or char_length(president_photo) <= 200),
  created_at timestamptz not null default now(),
  unique (election_id, number)
);

-- Quién ya votó (sin enlace con la papeleta) y papeletas (sin quién ni cuándo).
create table public.vote_receipts (
  election_id uuid not null references public.elections(id) on delete cascade,
  voter_id uuid references public.profiles(id) on delete set null,
  voted_at timestamptz not null default now(),
  unique (election_id, voter_id)
);
create table public.ballots (
  election_id uuid not null references public.elections(id) on delete cascade,
  list_id uuid references public.election_lists(id)      -- null = voto en blanco
);
create index ballots_election_list_idx on public.ballots(election_id, list_id);

-- Una votación abierta o cerrada no se puede editar; el estado solo avanza.
create function public.elections_guard() returns trigger language plpgsql as $$
begin
  if old.status = 'closed' then raise exception 'election_closed'; end if;
  if old.status = 'open' and new.status = 'draft' then raise exception 'invalid_transition'; end if;
  if old.status <> 'draft' and (new.title, new.description, new.starts_at, new.ends_at)
     is distinct from (old.title, old.description, old.starts_at, old.ends_at) then
    raise exception 'election_locked';
  end if;
  return new;
end $$;
create trigger elections_guard_trg before update on public.elections for each row execute function public.elections_guard();

-- ---------- Funciones ----------
create function public.cast_vote(p_election uuid, p_list uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare e public.elections;
begin
  if not public.has_permission('elections.vote') then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into e from public.elections where id = p_election;
  if not found or e.status <> 'open' or now() < e.starts_at or now() > e.ends_at then
    raise exception 'election_not_open';
  end if;
  if p_list is not null and not exists (
    select 1 from public.election_lists where id = p_list and election_id = p_election) then
    raise exception 'invalid_list';
  end if;
  begin
    insert into public.vote_receipts(election_id, voter_id) values (p_election, auth.uid());
  exception when unique_violation then
    raise exception 'already_voted';
  end;
  insert into public.ballots(election_id, list_id) values (p_election, p_list);
end $$;

-- Estadísticas Electorales en una sola llamada. Mientras la votación está abierta
-- solo las ve quien administra votaciones, para no influir en el voto.
create function public.election_results(p_election uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.elections; v_eligible int; v_total int; v_blank int; v_lists jsonb;
begin
  if not public.has_permission('elections.stats') then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into e from public.elections where id = p_election;
  if not found then raise exception 'election_not_found'; end if;
  if e.status <> 'closed' and not public.has_permission('elections.manage') then raise exception 'results_hidden'; end if;

  select count(*) into v_eligible
    from public.profiles p join public.role_permissions rp
      on rp.role_id = p.role_id and rp.permission_code = 'elections.vote'
   where p.status = 'active';
  select count(*) filter (where list_id is null), count(*) into v_blank, v_total
    from public.ballots where election_id = p_election;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'number', l.number, 'name', l.name, 'president_name', l.president_name,
           'president_photo', l.president_photo, 'votes', coalesce(c.n, 0)) order by l.number), '[]'::jsonb)
    into v_lists
    from public.election_lists l
    left join (select list_id, count(*) n from public.ballots where election_id = p_election group by list_id) c
      on c.list_id = l.id
   where l.election_id = p_election;

  return jsonb_build_object('status', e.status, 'eligible', v_eligible, 'total_votes', v_total,
                            'blank', v_blank, 'lists', v_lists);
end $$;

-- ---------- Permisos y roles de ejemplo ----------
insert into public.permissions(code, description) values
  ('elections.manage', 'Crear y administrar votaciones, listas y fotos'),
  ('elections.vote',   'Votar en votaciones abiertas'),
  ('elections.stats',  'Ver las Estadísticas Electorales');

insert into public.roles(name, description) values
  ('docente',    'Personal docente'),
  ('estudiante', 'Estudiante con derecho a voto')
on conflict (name) do nothing;

insert into public.role_permissions(role_id, permission_code)
  select r.id, p.code from public.roles r cross join public.permissions p where r.name = 'admin'
on conflict do nothing;
insert into public.role_permissions(role_id, permission_code)
  select r.id, 'elections.vote' from public.roles r where r.name = 'estudiante' on conflict do nothing;
insert into public.role_permissions(role_id, permission_code)
  select r.id, 'elections.stats' from public.roles r where r.name = 'docente' on conflict do nothing;

-- ---------- RLS y privilegios ----------
alter table public.elections      enable row level security;
alter table public.election_lists enable row level security;
alter table public.vote_receipts  enable row level security;
alter table public.ballots        enable row level security;   -- sin políticas: solo funciones

revoke all on public.elections, public.election_lists, public.vote_receipts, public.ballots from anon, authenticated;
grant select on public.elections, public.election_lists, public.vote_receipts to authenticated;
grant insert (title, description, starts_at, ends_at), update (title, description, starts_at, ends_at, status), delete
  on public.elections to authenticated;
grant insert (election_id, number, name, slogan, president_name, president_photo),
      update (number, name, slogan, president_name, president_photo), delete
  on public.election_lists to authenticated;

create policy elections_read on public.elections for select to authenticated using (
  (select public.has_permission('elections.manage'))
  or (status in ('open','closed') and ((select public.has_permission('elections.vote')) or (select public.has_permission('elections.stats')))));
create policy elections_insert on public.elections for insert to authenticated
  with check ((select public.has_permission('elections.manage')));
create policy elections_update on public.elections for update to authenticated
  using ((select public.has_permission('elections.manage'))) with check ((select public.has_permission('elections.manage')));
create policy elections_delete on public.elections for delete to authenticated
  using ((select public.has_permission('elections.manage')) and status = 'draft');

create policy lists_read on public.election_lists for select to authenticated
  using (exists (select 1 from public.elections e where e.id = election_lists.election_id));  -- hereda la visibilidad
create policy lists_insert on public.election_lists for insert to authenticated
  with check ((select public.has_permission('elections.manage'))
              and exists (select 1 from public.elections e where e.id = election_id and e.status = 'draft'));
create policy lists_update on public.election_lists for update to authenticated
  using ((select public.has_permission('elections.manage'))
         and exists (select 1 from public.elections e where e.id = election_id and e.status = 'draft'))
  with check ((select public.has_permission('elections.manage')));
create policy lists_delete on public.election_lists for delete to authenticated
  using ((select public.has_permission('elections.manage'))
         and exists (select 1 from public.elections e where e.id = election_id and e.status = 'draft'));

create policy receipts_read on public.vote_receipts for select to authenticated using (voter_id = (select auth.uid()));

revoke all on function public.elections_guard(), public.cast_vote(uuid,uuid), public.election_results(uuid)
  from public, anon, authenticated;
grant execute on function public.cast_vote(uuid,uuid), public.election_results(uuid) to authenticated;

-- ---------- Fotos de los presidentes (bucket privado, URLs firmadas) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('election-photos', 'election-photos', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy election_photos_read   on storage.objects for select to authenticated
  using (bucket_id = 'election-photos' and (select public.is_active()));
create policy election_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'election-photos' and (select public.has_permission('elections.manage')));
create policy election_photos_update on storage.objects for update to authenticated
  using (bucket_id = 'election-photos' and (select public.has_permission('elections.manage')));
create policy election_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'election-photos' and (select public.has_permission('elections.manage')));
