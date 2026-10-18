insert into public.permissions(code,description) values
 ('terminal.operate','Usar el teléfono como terminal escolar y consultar con tarjeta'),
 ('terminal.unlock','Autorizar cambios de modo y desbloquear el terminal'),
 ('council.open','Abrir y cerrar el período de postulaciones') on conflict do nothing;
insert into public.role_permissions(role_id,permission_code)
 select r.id,p.code from public.roles r cross join public.permissions p where r.name in ('admin','rector','encargado_consejo') and p.code in ('terminal.operate','terminal.unlock','council.open') on conflict do nothing;
alter table public.school_polls add column applications_open boolean not null default false;
create function public.set_council_applications_open(p_poll_id uuid,p_open boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.has_permission('council.open') then raise exception 'forbidden' using errcode='42501';end if;
 update public.school_polls set applications_open=p_open where id=p_poll_id and kind='council' and status='draft';
 if not found then raise exception 'applications_closed';end if;
end;$$;
create function public.guard_council_application_window() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not public.has_permission('council.review') and not exists(select 1 from public.school_polls where id=new.poll_id and kind='council' and status='draft' and applications_open) then raise exception 'applications_closed';end if;
 return new;
end;$$;
create trigger council_window before insert or update on public.council_applications for each row execute function public.guard_council_application_window();
revoke all on function public.guard_council_application_window() from public,anon,authenticated;

create table public.terminal_unlock_tickets(id uuid primary key default gen_random_uuid(),operator_id uuid not null references public.profiles(id),expires_at timestamptz not null default now()+interval '60 seconds',used boolean not null default false);
create table public.terminal_profile_access(operator_id uuid primary key references public.profiles(id),student_id uuid not null references public.profiles(id),expires_at timestamptz not null);
alter table public.terminal_unlock_tickets enable row level security;
alter table public.terminal_profile_access enable row level security;
revoke all on public.terminal_unlock_tickets,public.terminal_profile_access from anon,authenticated;

create function public.authorize_terminal_card(p_card_uid text) returns uuid language plpgsql security definer set search_path='' as $$
declare card_user uuid; token uuid;
begin
 if auth.uid() is null or not public.has_permission('terminal.operate') then raise exception 'forbidden' using errcode='42501';end if;
 select p.id into card_user from public.nfc_cards c join public.profiles p on p.id=c.profile_id
 where c.active and p.status='active' and upper(regexp_replace(c.card_uid,'[^0-9A-Fa-f]','','g'))=upper(regexp_replace(p_card_uid,'[: -]','','g'))
 and exists(select 1 from public.role_permissions rp where rp.role_id=p.role_id and rp.permission_code='terminal.unlock') limit 1;
 if card_user is null then raise exception 'card_not_authorized' using errcode='42501';end if;
 insert into public.terminal_unlock_tickets(operator_id) values(auth.uid()) returning id into token;
 return token;
end;$$;
-- El token aleatorio de un solo uso se entrega solo tras validar tarjeta y operador.
-- Android lo canjea sin almacenar ni compartir la sesión de la web.
create function public.consume_terminal_unlock(p_token uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 update public.terminal_unlock_tickets set used=true where id=p_token and not used and expires_at>now();
 return found;
end;$$;
create function public.terminal_student_profile(p_card_uid text) returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid; result jsonb;
begin
 if auth.uid() is null or not public.has_permission('terminal.operate') then raise exception 'forbidden' using errcode='42501';end if;
 select p.id into student from public.nfc_cards c join public.profiles p on p.id=c.profile_id
 where c.active and p.status='active' and upper(regexp_replace(c.card_uid,'[^0-9A-Fa-f]','','g'))=upper(regexp_replace(p_card_uid,'[: -]','','g')) limit 1;
 if student is null then raise exception 'invalid_card';end if;
 insert into public.terminal_profile_access(operator_id,student_id,expires_at) values(auth.uid(),student,now()+interval '2 minutes')
 on conflict(operator_id) do update set student_id=excluded.student_id,expires_at=excluded.expires_at;
 select jsonb_build_object('id',p.id,'full_name',p.full_name,'nickname',c.nickname,'headline',c.headline,'bio',c.bio,'accent',c.accent,'badge',c.badge,'level',sl.name,
 'grades',coalesce((select jsonb_agg(jsonb_build_object('subject',s.name,'period',gp.name,'score',g.score) order by gp.order_index,s.name) from public.grades g join public.subjects s on s.id=g.subject_id join public.grade_periods gp on gp.id=g.period_id where g.student_id=p.id),'[]'::jsonb)) into result
 from public.profiles p left join public.profile_customizations c on c.profile_id=p.id left join public.student_details sd on sd.profile_id=p.id left join public.school_levels sl on sl.id=sd.level_id where p.id=student;
 return result;
end;$$;
create or replace function public.profile_photo_visible(p_folder text) returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and public.is_active() and (
    p_folder=auth.uid()::text or public.has_permission('users.manage') or exists(
      select 1 from public.profile_customizations c join public.profiles p on p.id=c.profile_id
      where c.profile_id::text=p_folder and c.visibility='public' and p.status='active') or
    (public.has_permission('terminal.operate') and exists(select 1 from public.terminal_profile_access where operator_id=auth.uid() and student_id::text=p_folder and expires_at>now())));
$$;
revoke all on function public.set_council_applications_open(uuid,boolean),public.authorize_terminal_card(text),public.terminal_student_profile(text),public.consume_terminal_unlock(uuid) from public,anon;
grant execute on function public.set_council_applications_open(uuid,boolean),public.authorize_terminal_card(text),public.terminal_student_profile(text) to authenticated;
grant execute on function public.consume_terminal_unlock(uuid) to anon,authenticated;
