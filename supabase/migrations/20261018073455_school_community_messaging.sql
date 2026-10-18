-- School discussions. Moderator access explicitly excludes private conversations.
insert into public.permissions(code,description) values
 ('community.moderate','Moderar foros y grupos, retirar mensajes y suspender escritura; sin acceso a chats privados') on conflict do nothing;
insert into public.roles(name,description) values ('moderador_comunidad','Moderar foros y grupos del colegio; no puede leer chats privados') on conflict(name) do nothing;
insert into public.role_permissions(role_id,permission_code)
 select id,'community.moderate' from public.roles where name in ('admin','rector','moderador_comunidad') on conflict do nothing;

create table public.school_chat_rooms(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('forum','group','direct')),
 title text not null check(length(title) between 2 and 100),description text not null default '' check(length(description)<=500),
 owner_id uuid references public.profiles(id),direct_pair text unique,closed boolean not null default false,created_at timestamptz not null default now(),
 check((kind='direct')=(direct_pair is not null))
);
create table public.school_chat_members(room_id uuid references public.school_chat_rooms(id) on delete cascade,user_id uuid references public.profiles(id) on delete cascade,primary key(room_id,user_id));
create table public.school_chat_messages(
 id bigint generated always as identity primary key,room_id uuid not null references public.school_chat_rooms(id),
 author_id uuid not null references public.profiles(id),body text not null default '' check(length(body)<=3000),image_path text unique,
 created_at timestamptz not null default now(),removed_at timestamptz,removed_by uuid references public.profiles(id),removal_reason text,
 check(length(trim(body))>0 or image_path is not null)
);
create index school_chat_messages_room_cursor on public.school_chat_messages(room_id,id desc);
create index school_chat_messages_author_time on public.school_chat_messages(author_id,created_at desc);
create index school_chat_members_user on public.school_chat_members(user_id,room_id);
create table public.school_chat_sanctions(
 user_id uuid primary key references public.profiles(id),until_at timestamptz,permanent boolean not null default false,
 reason text not null check(length(reason) between 5 and 500),issued_by uuid not null references public.profiles(id),issued_at timestamptz not null default now(),
 check(permanent or until_at is not null)
);
alter table public.school_chat_rooms enable row level security;
alter table public.school_chat_members enable row level security;
alter table public.school_chat_messages enable row level security;
alter table public.school_chat_sanctions enable row level security;
revoke all on public.school_chat_rooms,public.school_chat_members,public.school_chat_messages,public.school_chat_sanctions from anon,authenticated;
insert into public.school_chat_rooms(kind,title,description) values('forum','Foro del colegio','Conversaciones y preguntas de la comunidad escolar. Respeta a tus compañeros.');

create function public.school_chat_readable(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.is_active() and exists(select 1 from public.school_chat_rooms r where r.id=p_room and
 (r.kind='forum' or exists(select 1 from public.school_chat_members m where m.room_id=r.id and m.user_id=auth.uid())
 or (r.kind='group' and public.has_permission('community.moderate'))));
$$;
create function public.school_chat_can_write(p_room uuid default null) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.is_active()
 and not exists(select 1 from public.school_chat_sanctions s where s.user_id=auth.uid() and (s.permanent or s.until_at>now()))
 and (p_room is null or exists(select 1 from public.school_chat_rooms r where r.id=p_room and not r.closed
 and (r.kind='forum' or exists(select 1 from public.school_chat_members m where m.room_id=r.id and m.user_id=auth.uid()))));
$$;
create function public.school_person_card(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null or not public.is_active() then null else (
 select jsonb_build_object('id',p.id,'name',p.full_name,'role',r.name,'level',sl.name,
 'subjects',coalesce((select jsonb_agg(s.name order by s.name) from public.subject_teachers st join public.subjects s on s.id=st.subject_id where st.teacher_id=p.id),'[]'::jsonb))
 from public.profiles p join public.roles r on r.id=p.role_id left join public.student_details sd on sd.profile_id=p.id left join public.school_levels sl on sl.id=sd.level_id
 where p.id=p_id and p.status='active') end;
$$;
create function public.school_chat_people(p_search text default '',p_offset int default 0) returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null or not public.is_active() then '[]'::jsonb else coalesce((select jsonb_agg(public.school_person_card(p.id)) from
 (select id from public.profiles where status='active' and id<>auth.uid() and full_name ilike '%'||left(coalesce(p_search,''),80)||'%' order by full_name,id limit 24 offset greatest(coalesce(p_offset,0),0)) p),'[]'::jsonb) end;
$$;
create function public.school_chat_list() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.is_active() then raise exception 'forbidden' using errcode='42501';end if;
 return jsonb_build_object('rooms',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'kind',r.kind,'title',r.title,'description',r.description,'closed',r.closed,
 'joined',exists(select 1 from public.school_chat_members m where m.room_id=r.id and m.user_id=auth.uid()),'readable',public.school_chat_readable(r.id),
 'other',case when r.kind='direct' then (select public.school_person_card(m.user_id) from public.school_chat_members m where m.room_id=r.id and m.user_id<>auth.uid() limit 1) else null end) order by r.created_at desc)
 from public.school_chat_rooms r where r.kind<>'direct' or exists(select 1 from public.school_chat_members m where m.room_id=r.id and m.user_id=auth.uid())),'[]'::jsonb),
 'sanction',(select jsonb_build_object('permanent',s.permanent,'until',s.until_at,'reason',s.reason) from public.school_chat_sanctions s where s.user_id=auth.uid() and (s.permanent or s.until_at>now())));
end;$$;
create function public.school_chat_create(p_kind text,p_title text,p_description text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare room uuid;
begin
 if not public.school_chat_can_write() then raise exception 'writing_suspended' using errcode='42501';end if;
 if p_kind not in ('group','forum') or p_kind is null then raise exception 'invalid_kind';end if;
 if p_kind='forum' and not public.has_permission('community.moderate') then raise exception 'forbidden' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('chat-create:'||auth.uid()::text,0));
 if (select count(*) from public.school_chat_rooms where owner_id=auth.uid() and created_at>now()-interval '1 day')>=10 then raise exception 'chat_rate_limit';end if;
 insert into public.school_chat_rooms(kind,title,description,owner_id) values(p_kind,trim(p_title),trim(p_description),auth.uid()) returning id into room;
 insert into public.school_chat_members values(room,auth.uid());return room;
end;$$;
create function public.school_chat_join(p_room uuid,p_join boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.school_chat_can_write() then raise exception 'writing_suspended' using errcode='42501';end if;
 if not exists(select 1 from public.school_chat_rooms where id=p_room and kind='group' and not closed) then raise exception 'invalid_group';end if;
 if p_join then insert into public.school_chat_members values(p_room,auth.uid()) on conflict do nothing;
 else delete from public.school_chat_members where room_id=p_room and user_id=auth.uid();end if;
end;$$;
create function public.school_chat_direct(p_other uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare room uuid; pair text;
begin
 if not public.school_chat_can_write() then raise exception 'writing_suspended' using errcode='42501';end if;
 if p_other=auth.uid() or not exists(select 1 from public.profiles where id=p_other and status='active') then raise exception 'invalid_recipient';end if;
 pair:=least(auth.uid()::text,p_other::text)||':'||greatest(auth.uid()::text,p_other::text);
 perform pg_advisory_xact_lock(hashtextextended('chat-create:'||auth.uid()::text,0));
 perform pg_advisory_xact_lock(hashtextextended(pair,0));
 select id into room from public.school_chat_rooms where direct_pair=pair;
 if room is null then
  if (select count(*) from public.school_chat_rooms where kind='direct' and owner_id=auth.uid() and created_at>now()-interval '1 hour')>=20 then raise exception 'chat_rate_limit';end if;
  insert into public.school_chat_rooms(kind,title,owner_id,direct_pair) values('direct','Conversación privada',auth.uid(),pair) returning id into room;
  insert into public.school_chat_members values(room,auth.uid()),(room,p_other);
 end if;return room;
end;$$;
create function public.school_chat_messages_page(p_room uuid,p_before bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.school_chat_readable(p_room) then raise exception 'forbidden' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',m.id::text,'author',public.school_person_card(m.author_id),'body',case when m.removed_at is null then m.body else '' end,
 'image_path',case when m.removed_at is null then m.image_path else null end,'created_at',m.created_at,'removed',m.removed_at is not null,
 'reason',case when m.removed_at is not null then m.removal_reason else null end) order by m.id)
 from (select * from public.school_chat_messages where room_id=p_room and (p_before is null or id<p_before) order by id desc limit 50) m),'[]'::jsonb);
end;$$;
create function public.school_chat_send(p_room uuid,p_body text default '',p_image text default null) returns text language plpgsql security definer set search_path='' as $$
declare msg bigint;
begin
 perform pg_advisory_xact_lock(hashtextextended('chat-send:'||coalesce(auth.uid()::text,''),0));
 if not public.school_chat_can_write(p_room) then raise exception 'writing_suspended' using errcode='42501';end if;
 if (select count(*) from public.school_chat_messages where author_id=auth.uid() and created_at>now()-interval '1 minute')>=20 then raise exception 'chat_rate_limit';end if;
 if p_image is not null and (split_part(p_image,'/',1)<>auth.uid()::text or split_part(p_image,'/',2)<>p_room::text or
 not exists(select 1 from storage.objects where bucket_id='school-chat' and name=p_image)) then raise exception 'invalid_photo';end if;
 insert into public.school_chat_messages(room_id,author_id,body,image_path) values(p_room,auth.uid(),trim(coalesce(p_body,'')),p_image) returning id into msg;
 return msg::text;
end;$$;
create function public.school_chat_remove(p_message bigint,p_reason text default '') returns void language plpgsql security definer set search_path='' as $$
declare msg public.school_chat_messages; kind text;
begin
 select * into msg from public.school_chat_messages where id=p_message for update;
 select r.kind into kind from public.school_chat_rooms r where id=msg.room_id;
 if not public.school_chat_readable(msg.room_id) or not (msg.author_id=auth.uid() or (kind<>'direct' and public.has_permission('community.moderate'))) then raise exception 'forbidden' using errcode='42501';end if;
 if msg.author_id<>auth.uid() and length(trim(p_reason))<5 then raise exception 'reason_required';end if;
 update public.school_chat_messages set removed_at=now(),removed_by=auth.uid(),removal_reason=case when msg.author_id=auth.uid() then 'El autor retiró este mensaje.' else left(trim(p_reason),500) end where id=p_message;
end;$$;
create function public.school_chat_sanction(p_user uuid,p_minutes int,p_permanent boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.has_permission('community.moderate') or auth.uid() is null then raise exception 'forbidden' using errcode='42501';end if;
 if p_user=auth.uid() then raise exception 'cannot_change_self';end if;
 if p_minutes=0 and not p_permanent then delete from public.school_chat_sanctions where user_id=p_user;return;end if;
 if p_permanent is null or (not p_permanent and (p_minutes is null or p_minutes not between 1 and 525600)) then raise exception 'invalid_duration';end if;
 insert into public.school_chat_sanctions(user_id,until_at,permanent,reason,issued_by) values(p_user,case when p_permanent then null else now()+make_interval(mins=>p_minutes) end,p_permanent,trim(p_reason),auth.uid())
 on conflict(user_id) do update set until_at=excluded.until_at,permanent=excluded.permanent,reason=excluded.reason,issued_by=excluded.issued_by,issued_at=now();
end;$$;
create function public.school_chat_sanctions_list() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.has_permission('community.moderate') or auth.uid() is null then raise exception 'forbidden' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('person',public.school_person_card(user_id),'until',until_at,'permanent',permanent,'reason',reason)) from public.school_chat_sanctions where permanent or until_at>now()),'[]'::jsonb);
end;$$;
create function public.school_chat_close(p_room uuid,p_closed boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.has_permission('community.moderate') then raise exception 'forbidden' using errcode='42501';end if;
 update public.school_chat_rooms set closed=p_closed where id=p_room and kind<>'direct';
 if not found then raise exception 'forbidden' using errcode='42501';end if;
end;$$;

-- Private media: a moderator cannot read photos from direct conversations.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('school-chat','school-chat',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create function public.school_chat_photo_readable(p_name text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.is_active() and exists(select 1 from public.school_chat_messages m where m.image_path=p_name and m.removed_at is null and public.school_chat_readable(m.room_id));
$$;
create function public.school_chat_photo_writable(p_name text) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if split_part(p_name,'/',1) is distinct from auth.uid()::text or p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$' then return false;end if;
 return public.school_chat_can_write(split_part(p_name,'/',2)::uuid);
exception when invalid_text_representation then return false;
end;$$;
create policy school_chat_photo_insert on storage.objects for insert to authenticated with check(bucket_id='school-chat' and public.school_chat_photo_writable(name));
create policy school_chat_photo_read on storage.objects for select to authenticated using(bucket_id='school-chat' and public.school_chat_photo_readable(name));
create policy school_chat_photo_delete on storage.objects for delete to authenticated using(bucket_id='school-chat' and split_part(name,'/',1)=(select auth.uid())::text);

create function public.school_chat_author_visible(p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.is_active() and exists(select 1 from public.school_chat_messages m where m.author_id::text=p_id and m.removed_at is null and public.school_chat_readable(m.room_id));
$$;
-- Names/photos shown beside messages do not expose private profile details or grades.
do $patch$
declare definition text;
begin
 definition:=pg_get_functiondef('public.profile_photo_visible(text)'::regprocedure);
 definition:=replace(definition,'p_folder=auth.uid()::text or','p_folder=auth.uid()::text or public.school_chat_author_visible(p_folder) or');
 execute definition;
 definition:=pg_get_functiondef('public.school_profiles(uuid,text,integer)'::regprocedure);
 definition:=replace(definition,' or public.has_permission(''users.manage'')','');
 execute definition;
end $patch$;

-- Explicit RPC grants; private tables remain inaccessible through the REST API.
do $grants$
declare fn regprocedure;
begin
 for fn in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'school_chat_%' or p.proname='school_person_card') loop
  execute format('revoke all on function %s from public,anon',fn);
  execute format('grant execute on function %s to authenticated',fn);
 end loop;
end $grants$;
