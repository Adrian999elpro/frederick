create or replace function public.guard_council_application_window() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='pending' and not exists(select 1 from public.school_polls where id=new.poll_id and kind='council' and status='draft' and applications_open) then raise exception 'applications_closed';end if;
 return new;
end;$$;
create function public.queue_student_registration() returns trigger language plpgsql security definer set search_path='' as $$
declare level uuid; raw_uid text; card text;
begin
 if not exists(select 1 from public.profiles p join public.roles r on r.id=p.role_id where p.id=new.id and r.name='estudiante') then return new;end if;
 if coalesce(new.raw_user_meta_data->>'registration_level','')='' then return new;end if;
 level=(new.raw_user_meta_data->>'registration_level')::uuid;
 if not exists(select 1 from public.school_levels where id=level) then raise exception 'invalid_level';end if;
 raw_uid=upper(regexp_replace(coalesce(new.raw_user_meta_data->>'registration_card',''),'[: -]','','g'));
 if raw_uid<>'' then
   if raw_uid !~ '^([0-9A-F]{2}){4,10}$' then raise exception 'invalid_card';end if;
   card=regexp_replace(raw_uid,'(..)(?=.)','\1:','g');
 end if;
 update public.profiles set phone=nullif(left(new.raw_user_meta_data->>'phone',30),'') where id=new.id;
 insert into public.enrollment_requests(profile_id,level_id,card_uid) values(new.id,level,card) on conflict do nothing;
 return new;
end;$$;
create trigger zz_queue_student_registration after insert on auth.users for each row execute function public.queue_student_registration();
revoke all on function public.queue_student_registration() from public,anon,authenticated;
create function public.enrollment_confirmation_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='approved' and not exists(select 1 from auth.users u join public.profiles p on p.id=u.id where u.id=new.profile_id and u.email_confirmed_at is not null and p.status='active') then raise exception 'email_confirmation_required';end if;
 return new;
end;$$;
create trigger enrollment_confirmed before update on public.enrollment_requests for each row execute function public.enrollment_confirmation_guard();
revoke all on function public.enrollment_confirmation_guard() from public,anon,authenticated;
create policy role_editor_insert on public.roles for insert to authenticated with check(public.has_permission('roles.manage') and not is_system and name<>'admin');
create policy role_editor_update on public.roles for update to authenticated using(public.has_permission('roles.manage') and not is_system) with check(public.has_permission('roles.manage') and not is_system and name<>'admin');
create policy role_editor_delete on public.roles for delete to authenticated using(public.has_permission('roles.manage') and not is_system);
