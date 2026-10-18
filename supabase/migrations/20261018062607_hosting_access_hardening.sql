-- Compatible con el esquema existente instalado manualmente en Frederick.
-- No recrea tablas, no reasigna usuarios ni borra datos.

revoke all on public.roles, public.permissions, public.role_permissions,
  public.profiles, public.app_settings, public.audit_log, public.login_attempts
  from anon, authenticated;
grant select on public.roles, public.permissions, public.role_permissions,
  public.profiles, public.app_settings, public.audit_log to authenticated;
grant insert (name, description), update (name, description), delete
  on public.roles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;
grant update (value) on public.app_settings to authenticated;

revoke all on public.elections, public.election_lists, public.vote_receipts,
  public.ballots from anon, authenticated;
grant select on public.elections, public.election_lists, public.vote_receipts to authenticated;
grant insert (title, description, starts_at, ends_at),
  update (title, description, starts_at, ends_at, status), delete
  on public.elections to authenticated;
grant insert (election_id, number, name, slogan, president_name, president_photo),
  update (number, name, slogan, president_name, president_photo), delete
  on public.election_lists to authenticated;

revoke all on function public.is_active(), public.has_permission(text),
  public.get_my_access(), public.public_registration_mode(),
  public.ack_password_changed(), public.log_event(text,text,jsonb),
  public.set_role_permissions(uuid,text[]), public.purge_old_records(),
  public.audit_settings(), public.handle_new_user(), public.elections_guard(),
  public.cast_vote(uuid,uuid), public.election_results(uuid)
  from public, anon, authenticated;
grant execute on function public.is_active(), public.has_permission(text),
  public.get_my_access(), public.ack_password_changed(),
  public.set_role_permissions(uuid,text[]), public.cast_vote(uuid,uuid),
  public.election_results(uuid) to authenticated;
grant execute on function public.public_registration_mode() to anon, authenticated;

-- Las funciones de triggers no son endpoints de la API.
do $$
declare fn record;
begin
  for fn in select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prorettype in ('trigger'::regtype, 'event_trigger'::regtype)
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn.signature);
  end loop;
end $$;

-- Reponer políticas de gestión ausentes en el script consolidado histórico.
drop policy if exists roles_insert on public.roles;
create policy roles_insert on public.roles for insert to authenticated
  with check ((select public.has_permission('roles.manage')) and not is_system);
drop policy if exists roles_update on public.roles;
create policy roles_update on public.roles for update to authenticated
  using ((select public.has_permission('roles.manage')) and not is_system)
  with check ((select public.has_permission('roles.manage')) and not is_system);
drop policy if exists roles_delete on public.roles;
create policy roles_delete on public.roles for delete to authenticated
  using ((select public.has_permission('roles.manage')) and not is_system);

drop policy if exists elections_delete on public.elections;
create policy elections_delete on public.elections for delete to authenticated
  using ((select public.has_permission('elections.manage')) and status = 'draft');
drop policy if exists lists_insert on public.election_lists;
create policy lists_insert on public.election_lists for insert to authenticated
  with check ((select public.has_permission('elections.manage')) and exists
    (select 1 from public.elections e where e.id = election_id and e.status = 'draft'));
drop policy if exists lists_update on public.election_lists;
create policy lists_update on public.election_lists for update to authenticated
  using ((select public.has_permission('elections.manage')) and exists
    (select 1 from public.elections e where e.id = election_id and e.status = 'draft'))
  with check ((select public.has_permission('elections.manage')) and exists
    (select 1 from public.elections e where e.id = election_id and e.status = 'draft'));
drop policy if exists lists_delete on public.election_lists;
create policy lists_delete on public.election_lists for delete to authenticated
  using ((select public.has_permission('elections.manage')) and exists
    (select 1 from public.elections e where e.id = election_id and e.status = 'draft'));

drop policy if exists subjects_manage on public.subjects;
create policy subjects_manage on public.subjects for all to authenticated
  using ((select public.has_permission('grades.manage')))
  with check ((select public.has_permission('grades.manage')));
drop policy if exists subject_teachers_read on public.subject_teachers;
create policy subject_teachers_read on public.subject_teachers for select to authenticated
  using ((select public.has_permission('grades.read')));
drop policy if exists subject_teachers_manage on public.subject_teachers;
create policy subject_teachers_manage on public.subject_teachers for all to authenticated
  using ((select public.has_permission('grades.manage')))
  with check ((select public.has_permission('grades.manage')));

-- El frontend ya utiliza URLs firmadas para estas fotografías.
update storage.buckets set public = false, file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg','image/png','image/webp']
  where id = 'election-photos';
