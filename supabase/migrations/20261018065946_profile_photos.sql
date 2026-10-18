-- Perfil escolar: privado por defecto, compartido solo con cuentas activas.
create table public.profile_customizations (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  nickname text not null default '' check (length(nickname) <= 40),
  headline text not null default '' check (length(headline) <= 100),
  bio text not null default '' check (length(bio) <= 400),
  accent text not null default 'red' check (accent in ('red','blue','green','purple','gold')),
  badge text not null default 'school' check (badge in ('school','science','music','sports','code','art')),
  visibility text not null default 'private' check (visibility in ('private','public')),
  show_grades boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.profile_customizations enable row level security;
grant select,insert,update on public.profile_customizations to authenticated;
revoke all on public.profile_customizations from anon;
create policy customization_read on public.profile_customizations for select to authenticated
  using (public.is_active() and (profile_id=(select auth.uid()) or public.has_permission('users.manage')));
create policy customization_insert on public.profile_customizations for insert to authenticated
  with check (public.is_active() and profile_id=(select auth.uid()));
create policy customization_update on public.profile_customizations for update to authenticated
  using (public.is_active() and profile_id=(select auth.uid()))
  with check (profile_id=(select auth.uid()));

insert into public.app_settings(key,value) values ('profile_privacy','{"student_choice":true}') on conflict(key) do nothing;

create function public.profile_privacy_settings() returns jsonb language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is not null and public.is_active()
    then coalesce((select value from public.app_settings where key='profile_privacy'),'{"student_choice":false}'::jsonb)
    else null end;
$$;

create function public.guard_profile_privacy() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.has_permission('users.manage') and
    not coalesce((public.profile_privacy_settings()->>'student_choice')::boolean,false) then
    if (tg_op='INSERT' and (new.visibility<>'private' or new.show_grades)) or
       (tg_op='UPDATE' and (new.visibility is distinct from old.visibility or new.show_grades is distinct from old.show_grades)) then
      raise exception 'privacy_managed_by_school' using errcode='42501';
    end if;
  end if;
  new.updated_at=now();
  return new;
end; $$;
create trigger guard_profile_privacy before insert or update on public.profile_customizations for each row execute function public.guard_profile_privacy();
revoke all on function public.guard_profile_privacy() from public,anon,authenticated;

create function public.set_student_privacy(p_profile_id uuid,p_visibility text,p_show_grades boolean) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_active() or not public.has_permission('users.manage') then raise exception 'forbidden' using errcode='42501'; end if;
  if p_visibility not in ('public','private') or p_show_grades is null then raise exception 'invalid_privacy'; end if;
  insert into public.profile_customizations(profile_id,visibility,show_grades) values(p_profile_id,p_visibility,p_show_grades)
  on conflict(profile_id) do update set visibility=excluded.visibility,show_grades=excluded.show_grades;
end; $$;

-- Usado por las políticas y rankings: un perfil privado nunca publica notas.
create function public.profile_grades_visible(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and public.is_active() and exists(
    select 1 from public.profile_customizations c join public.profiles p on p.id=c.profile_id
    where c.profile_id=p_id and c.visibility='public' and c.show_grades and p.status='active');
$$;
create function public.profile_photo_visible(p_folder text) returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and public.is_active() and (
    p_folder=auth.uid()::text or public.has_permission('users.manage') or exists(
      select 1 from public.profile_customizations c join public.profiles p on p.id=c.profile_id
      where c.profile_id::text=p_folder and c.visibility='public' and p.status='active'));
$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('profile-photos','profile-photos',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy profile_photos_read on storage.objects for select to authenticated using
  (bucket_id='profile-photos' and public.profile_photo_visible((storage.foldername(name))[1]));
create policy profile_photos_insert on storage.objects for insert to authenticated with check
  (bucket_id='profile-photos' and name=(select auth.uid())::text||'/avatar' and public.is_active());
create policy profile_photos_update on storage.objects for update to authenticated using
  (bucket_id='profile-photos' and name=(select auth.uid())::text||'/avatar' and public.is_active()) with check
  (bucket_id='profile-photos' and name=(select auth.uid())::text||'/avatar' and public.is_active());
create policy profile_photos_delete on storage.objects for delete to authenticated using
  (bucket_id='profile-photos' and name=(select auth.uid())::text||'/avatar' and public.is_active());

-- Lectura limitada: no publica correo, teléfono, representantes ni comentarios docentes.
create function public.school_profiles(p_id uuid default null,p_search text default '',p_offset integer default 0)
returns jsonb language sql stable security definer set search_path = '' as $$
select case when auth.uid() is null or not public.is_active() then '[]'::jsonb else coalesce((
  select jsonb_agg(item) from (
    select jsonb_build_object('id',p.id,'full_name',p.full_name,'nickname',c.nickname,'headline',c.headline,
      'bio',c.bio,'accent',c.accent,'badge',c.badge,'visibility',c.visibility,'show_grades',c.show_grades,
      'level',sl.name,'specialty',ts.name,'interests',coalesce(sd.interested_specialties,'{}'),
      'grades',case when p_id is not null and (public.profile_grades_visible(p.id) or p.id=auth.uid() or public.has_permission('grades.manage')) then
        coalesce((select jsonb_agg(jsonb_build_object('subject',s.name,'period',gp.name,'score',g.score) order by gp.order_index,s.name)
          from public.grades g join public.subjects s on s.id=g.subject_id join public.grade_periods gp on gp.id=g.period_id where g.student_id=p.id),'[]'::jsonb)
        else '[]'::jsonb end) as item
    from public.profile_customizations c join public.profiles p on p.id=c.profile_id
    left join public.student_details sd on sd.profile_id=p.id
    left join public.school_levels sl on sl.id=sd.level_id
    left join public.technical_specialties ts on ts.id=sd.chosen_specialty_id
    where p.status='active' and (c.visibility='public' or p.id=auth.uid() or public.has_permission('users.manage'))
      and (p_id is null or p.id=p_id) and (p_id is not null or c.visibility='public')
      and (coalesce(p_search,'')='' or p.full_name ilike '%'||left(p_search,80)||'%' or c.nickname ilike '%'||left(p_search,80)||'%')
    order by p.full_name,p.id limit 24 offset greatest(coalesce(p_offset,0),0)
  ) entries),'[]'::jsonb) end;
$$;

-- La privacidad debe cumplirse también en el acceso directo a las tablas.
drop policy grades_policy_read on public.grades;
create policy grades_policy_read on public.grades for select to authenticated using
  (public.is_active() and (student_id=(select auth.uid()) or public.has_permission('grades.manage') or
    (public.has_permission('grades.upload') and exists(select 1 from public.subject_teachers st where st.subject_id=grades.subject_id and st.teacher_id=(select auth.uid())))));
drop policy student_details_read on public.student_details;
drop policy student_details_write on public.student_details;
create policy student_details_read on public.student_details for select to authenticated using
  (public.is_active() and (profile_id=(select auth.uid()) or public.has_permission('users.read') or public.has_permission('grades.upload') or public.has_permission('grades.manage')));
create policy student_details_insert on public.student_details for insert to authenticated with check
  (public.is_active() and (profile_id=(select auth.uid()) or public.has_permission('users.manage')));
create policy student_details_update on public.student_details for update to authenticated using
  (public.is_active() and (profile_id=(select auth.uid()) or public.has_permission('users.manage'))) with check
  (public.is_active() and (profile_id=(select auth.uid()) or public.has_permission('users.manage')));
create policy student_details_delete on public.student_details for delete to authenticated using (public.has_permission('users.manage'));
-- Un usuario no puede darse permisos administrativos para saltarse la privacidad.
revoke update on public.profiles from authenticated;
grant update(full_name,phone) on public.profiles to authenticated;

-- Conservar las firmas de los rankings y aplicar la misma privacidad en los tres.
do $migration$
declare fn regprocedure; definition text;
begin
  foreach fn in array array['public.get_academic_ranking(uuid)'::regprocedure,'public.get_specialty_ranking(uuid,uuid)'::regprocedure,'public.get_subject_ranking(uuid)'::regprocedure] loop
    definition=pg_get_functiondef(fn);
    if position('sd.notes_visibility = ''public''' in definition)=0 then raise exception 'unexpected_ranking_definition'; end if;
    definition=replace(definition,'sd.notes_visibility = ''public''','public.profile_grades_visible(p.id)');
    execute definition;
    execute format('revoke all on function %s from public, anon',fn);
    execute format('grant execute on function %s to authenticated',fn);
  end loop;
end $migration$;

revoke all on function public.profile_privacy_settings(),public.set_student_privacy(uuid,text,boolean),public.profile_grades_visible(uuid),public.profile_photo_visible(text),public.school_profiles(uuid,text,integer) from public,anon;
grant execute on function public.profile_privacy_settings(),public.set_student_privacy(uuid,text,boolean),public.profile_grades_visible(uuid),public.profile_photo_visible(text),public.school_profiles(uuid,text,integer) to authenticated;
