insert into public.permissions(code,description) values
 ('council.review','Revisar postulaciones y planes del consejo estudiantil'),
 ('polls.manage','Crear, abrir y cerrar votaciones escolares'),
 ('polls.operate','Operar votaciones con tarjetas de estudiantes') on conflict do nothing;
insert into public.roles(name,description) values
 ('encargado_consejo','Docente encargado: postulaciones, votaciones y anuncios'),
 ('moderador_anuncios','Publicar y destacar comunicados institucionales') on conflict(name) do nothing;
insert into public.role_permissions(role_id,permission_code)
 select r.id,p.code from public.roles r cross join public.permissions p
 where (r.name='admin') or (r.name in ('rector','encargado_consejo') and p.code in ('council.review','polls.manage','polls.operate','announcements.manage','announcements.read','nfc.attendance'))
 or (r.name='moderador_anuncios' and p.code in ('announcements.manage','announcements.read')) on conflict do nothing;
-- Permite que el administrador seleccione los roles nuevos desde Usuarios.
create policy roles_active_read on public.roles for select to authenticated using (public.is_active());

create table public.school_polls(
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('council','custom')),
 title text not null check(length(title) between 3 and 120),
 purpose text not null check(length(purpose) between 10 and 1000),
 duration_minutes int not null check(duration_minutes between 1 and 43200),
 secret boolean not null default true,
 status text not null default 'draft' check(status in ('draft','open','closed')),
 starts_at timestamptz,ends_at timestamptz,
 created_by uuid references public.profiles(id),created_at timestamptz not null default now()
);
create table public.council_applications(
 id uuid primary key default gen_random_uuid(),poll_id uuid not null references public.school_polls(id),
 student_id uuid not null references public.profiles(id),list_name text not null check(length(list_name) between 2 and 80),
 work_plan text not null check(length(work_plan) between 50 and 6000),
 status text not null default 'pending' check(status in ('pending','accepted','rejected')),
 reason text not null default '',reviewed_by uuid references public.profiles(id),updated_at timestamptz not null default now(),
 unique(poll_id,student_id)
);
create table public.school_poll_options(
 id uuid primary key default gen_random_uuid(),poll_id uuid not null references public.school_polls(id),
 label text not null check(length(label) between 1 and 120),application_id uuid unique references public.council_applications(id),
 unique(poll_id,label),unique(poll_id,id)
);
create table public.school_poll_participants(
 poll_id uuid not null references public.school_polls(id),student_id uuid not null references public.profiles(id),
 voted boolean not null default false,primary key(poll_id,student_id)
);
create table public.school_poll_votes(
 id uuid primary key default gen_random_uuid(),poll_id uuid not null references public.school_polls(id),
 option_id uuid not null,student_id uuid references public.profiles(id),
 foreign key(poll_id,option_id) references public.school_poll_options(poll_id,id)
);
create table public.school_poll_tickets(
 id uuid primary key default gen_random_uuid(),poll_id uuid not null references public.school_polls(id),
 voter_id uuid not null references public.profiles(id),operator_id uuid not null references public.profiles(id),
 expires_at timestamptz not null default now()+interval '90 seconds',used boolean not null default false
);
alter table public.school_polls enable row level security;
alter table public.council_applications enable row level security;
alter table public.school_poll_options enable row level security;
alter table public.school_poll_participants enable row level security;
alter table public.school_poll_votes enable row level security;
alter table public.school_poll_tickets enable row level security;
revoke all on public.school_polls,public.council_applications,public.school_poll_options,public.school_poll_participants,public.school_poll_votes,public.school_poll_tickets from anon,authenticated;
grant select on public.school_polls,public.council_applications,public.school_poll_options to authenticated;
create policy polls_read on public.school_polls for select to authenticated using (public.is_active() and (kind='council' or status<>'draft' or public.has_permission('polls.manage')));
create policy poll_options_read on public.school_poll_options for select to authenticated using(public.is_active() and exists(select 1 from public.school_polls p where p.id=poll_id));
create policy applications_read on public.council_applications for select to authenticated using(public.is_active() and (student_id=(select auth.uid()) or public.has_permission('council.review') or status='accepted'));

create function public.create_school_poll(p_kind text,p_title text,p_purpose text,p_duration_minutes int,p_secret boolean,p_options text[] default '{}')
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid; label text;
begin
 if auth.uid() is null or not public.has_permission('polls.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind='custom' and (coalesce(cardinality(p_options),0)<2 or cardinality(p_options)>20) then raise exception 'need_options'; end if;
 insert into public.school_polls(kind,title,purpose,duration_minutes,secret,created_by)
 values(p_kind,trim(p_title),trim(p_purpose),p_duration_minutes,p_secret,auth.uid()) returning school_polls.id into id;
 if p_kind='custom' then foreach label in array p_options loop insert into public.school_poll_options(poll_id,label) values(id,trim(label));end loop;end if;
 return id;
end;$$;
create function public.submit_council_application(p_poll_id uuid,p_list_name text,p_work_plan text)
returns void language plpgsql security definer set search_path='' as $$
declare poll public.school_polls;
begin
 if auth.uid() is null or not public.is_active() or not exists(select 1 from public.profiles p join public.roles r on r.id=p.role_id where p.id=auth.uid() and r.name='estudiante') then raise exception 'forbidden' using errcode='42501'; end if;
 select * into poll from public.school_polls where id=p_poll_id for update;
 if poll.kind is distinct from 'council' or poll.status<>'draft' then raise exception 'applications_closed';end if;
 if exists(select 1 from public.council_applications where poll_id=p_poll_id and student_id=auth.uid() and status='accepted') then raise exception 'already_accepted';end if;
 insert into public.council_applications(poll_id,student_id,list_name,work_plan) values(p_poll_id,auth.uid(),trim(p_list_name),trim(p_work_plan))
 on conflict(poll_id,student_id) do update set list_name=excluded.list_name,work_plan=excluded.work_plan,status='pending',reason='',reviewed_by=null,updated_at=now();
end;$$;
create function public.review_council_application(p_id uuid,p_accept boolean,p_reason text default '')
returns void language plpgsql security definer set search_path='' as $$
declare application public.council_applications; poll public.school_polls;
begin
 if auth.uid() is null or not public.has_permission('council.review') then raise exception 'forbidden' using errcode='42501'; end if;
 select * into application from public.council_applications where id=p_id;
 select * into poll from public.school_polls where id=application.poll_id for update;
 select * into application from public.council_applications where id=p_id for update;
 if application.id is null or application.status<>'pending' or poll.status<>'draft' then raise exception 'application_not_pending';end if;
 if p_accept is null or length(coalesce(p_reason,''))>1000 or (not p_accept and length(trim(coalesce(p_reason,'')))<5) then raise exception 'reason_required';end if;
 update public.council_applications set status=case when p_accept then 'accepted' else 'rejected' end,reason=trim(p_reason),reviewed_by=auth.uid(),updated_at=now() where id=p_id;
 if p_accept then insert into public.school_poll_options(poll_id,label,application_id) values(application.poll_id,application.list_name,application.id);end if;
end;$$;
create function public.change_school_poll_status(p_id uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare poll public.school_polls;
begin
 if auth.uid() is null or not public.has_permission('polls.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 select * into poll from public.school_polls where id=p_id for update;
 if p_action='open' and poll.status='draft' then
   if (select count(*) from public.school_poll_options where poll_id=p_id)< (case when poll.kind='custom' then 2 else 1 end) then raise exception 'need_options';end if;
   insert into public.school_poll_participants(poll_id,student_id) select p_id,p.id from public.profiles p join public.roles r on r.id=p.role_id where r.name='estudiante' and p.status='active';
   update public.school_polls set status='open',starts_at=now(),ends_at=now()+make_interval(mins=>duration_minutes) where id=p_id;
 elsif p_action='close' and poll.status='open' then update public.school_polls set status='closed',ends_at=least(ends_at,now()) where id=p_id;
 else raise exception 'invalid_transition';end if;
end;$$;
create function public.scan_school_poll_card(p_poll_id uuid,p_card_uid text) returns jsonb language plpgsql security definer set search_path='' as $$
declare poll public.school_polls; voter public.profiles; ticket uuid;
begin
 if auth.uid() is null or not public.is_active() then raise exception 'forbidden' using errcode='42501';end if;
 select * into poll from public.school_polls where id=p_poll_id;
 if poll.status is distinct from 'open' or now()>=poll.ends_at then raise exception 'election_not_open';end if;
 select p.* into voter from public.nfc_cards c join public.profiles p on p.id=c.profile_id
 where c.active and p.status='active' and upper(regexp_replace(c.card_uid,'[^0-9A-Fa-f]','','g'))=upper(regexp_replace(p_card_uid,'[: -]','','g')) limit 1;
 if voter.id is null then raise exception 'invalid_card';end if;
 if voter.id<>auth.uid() and not public.has_permission('polls.operate') then raise exception 'forbidden' using errcode='42501';end if;
 if not exists(select 1 from public.school_poll_participants where poll_id=p_poll_id and student_id=voter.id) then raise exception 'not_eligible';end if;
 if exists(select 1 from public.school_poll_participants where poll_id=p_poll_id and student_id=voter.id and voted) then raise exception 'already_voted';end if;
 -- Una nueva lectura invalida los tickets anteriores de este operador.
 update public.school_poll_tickets set used=true where operator_id=auth.uid() and not used;
 insert into public.school_poll_tickets(poll_id,voter_id,operator_id) values(p_poll_id,voter.id,auth.uid()) returning id into ticket;
 return jsonb_build_object('ticket',ticket,'student_name',voter.full_name,'expires_in',90);
end;$$;
create function public.cast_school_poll_vote(p_ticket uuid,p_option uuid) returns void language plpgsql security definer set search_path='' as $$
declare ticket public.school_poll_tickets; poll public.school_polls;
begin
 if auth.uid() is null or not public.is_active() then raise exception 'forbidden' using errcode='42501';end if;
 select * into ticket from public.school_poll_tickets where id=p_ticket and operator_id=auth.uid() for update;
 if ticket.id is null or ticket.used or now()>=ticket.expires_at then raise exception 'scan_required';end if;
 if ticket.voter_id<>auth.uid() and not public.has_permission('polls.operate') then raise exception 'forbidden' using errcode='42501';end if;
 select * into poll from public.school_polls where id=ticket.poll_id for update;
 if poll.status<>'open' or now()>=poll.ends_at then raise exception 'election_not_open';end if;
 if not exists(select 1 from public.profiles where id=ticket.voter_id and status='active') then raise exception 'not_eligible';end if;
 if not exists(select 1 from public.school_poll_options where id=p_option and poll_id=poll.id) then raise exception 'invalid_list';end if;
 update public.school_poll_participants set voted=true where poll_id=poll.id and student_id=ticket.voter_id and not voted;
 if not found then raise exception 'already_voted';end if;
 insert into public.school_poll_votes(poll_id,option_id,student_id) values(poll.id,p_option,case when poll.secret then null else ticket.voter_id end);
 update public.school_poll_tickets set used=true where id=p_ticket;
end;$$;
create function public.school_poll_results(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare poll public.school_polls; total int; eligible int; counts jsonb; people jsonb; closed boolean;
begin
 if auth.uid() is null or not public.is_active() then raise exception 'forbidden' using errcode='42501';end if;
 select * into poll from public.school_polls where id=p_id;
 if poll.id is null then raise exception 'election_not_found';end if;
 closed:=poll.status='closed' or (poll.status='open' and now()>=poll.ends_at);
 if not closed and not public.has_permission('polls.manage') then raise exception 'results_hidden';end if;
 select count(*),count(*) filter(where voted) into eligible,total from public.school_poll_participants where poll_id=p_id;
 select coalesce(jsonb_agg(jsonb_build_object('label',o.label,'votes',(select count(*) from public.school_poll_votes v where v.option_id=o.id)) order by o.label),'[]') into counts from public.school_poll_options o where o.poll_id=p_id;
 if public.has_permission('polls.manage') or (not poll.secret and closed) then
   select coalesce(jsonb_agg(jsonb_build_object('name',p.full_name,'voted',part.voted,'choice',case when poll.secret then null else opt.label end) order by p.full_name),'[]') into people
   from public.school_poll_participants part join public.profiles p on p.id=part.student_id
   left join public.school_poll_votes v on v.poll_id=part.poll_id and v.student_id=part.student_id
   left join public.school_poll_options opt on opt.id=v.option_id
   where part.poll_id=p_id and (public.has_permission('polls.manage') or part.voted);
 end if;
 return jsonb_build_object('closed',closed,'secret',poll.secret,'total',total,'eligible',eligible,'no_vote',eligible-total,'options',counts,'participants',coalesce(people,'[]'::jsonb));
end;$$;
revoke all on function public.create_school_poll(text,text,text,integer,boolean,text[]),public.submit_council_application(uuid,text,text),public.review_council_application(uuid,boolean,text),public.change_school_poll_status(uuid,text),public.scan_school_poll_card(uuid,text),public.cast_school_poll_vote(uuid,uuid),public.school_poll_results(uuid) from public,anon;
grant execute on function public.create_school_poll(text,text,text,integer,boolean,text[]),public.submit_council_application(uuid,text,text),public.review_council_application(uuid,boolean,text),public.change_school_poll_status(uuid,text),public.scan_school_poll_card(uuid,text),public.cast_school_poll_vote(uuid,uuid),public.school_poll_results(uuid) to authenticated;

