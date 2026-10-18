create table public.enrollment_requests (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  level_id uuid references public.school_levels(id),
  card_uid text check(card_uid is null or card_uid ~ '^([0-9A-F]{2}:){3,9}[0-9A-F]{2}$'),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  updated_at timestamptz not null default now()
);
alter table public.enrollment_requests enable row level security;
grant select on public.enrollment_requests to authenticated;
revoke all on public.enrollment_requests from anon;
create policy enrollment_read on public.enrollment_requests for select to authenticated using
  (public.is_active() and (profile_id=(select auth.uid()) or public.has_permission('users.manage')));

create function public.submit_enrollment(p_full_name text,p_phone text,p_level_id uuid,p_card_uid text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare uid text; raw_uid text;
begin
 if auth.uid() is null or not public.is_active() or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'forbidden' using errcode='42501'; end if;
 if length(trim(p_full_name)) not between 2 and 120 or length(coalesce(p_phone,''))>30 then raise exception 'invalid_profile'; end if;
 if p_level_id is not null and not exists(select 1 from public.school_levels where id=p_level_id) then raise exception 'invalid_level'; end if;
 raw_uid=upper(regexp_replace(coalesce(p_card_uid,''),'[: -]','','g'));
 if raw_uid<>'' then
   if raw_uid !~ '^([0-9A-F]{2}){4,10}$' then raise exception 'invalid_card'; end if;
   uid=regexp_replace(raw_uid,'(..)(?=.)','\1:','g');
 end if;
 update public.profiles set full_name=trim(p_full_name),phone=nullif(trim(p_phone),'') where id=auth.uid();
 insert into public.enrollment_requests(profile_id,level_id,card_uid) values(auth.uid(),p_level_id,uid)
 on conflict(profile_id) do update set level_id=excluded.level_id,card_uid=excluded.card_uid,status='pending',updated_at=now();
end; $$;

create function public.review_enrollment(p_profile_id uuid,p_approve boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare request public.enrollment_requests; current_card public.nfc_cards; compact text;
begin
 if auth.uid() is null or not public.has_permission('users.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 select * into request from public.enrollment_requests where profile_id=p_profile_id for update;
 if not found or request.status<>'pending' then raise exception 'request_not_pending'; end if;
 if p_approve then
   if request.card_uid is not null then
     if not public.has_permission('nfc.manage') then raise exception 'forbidden' using errcode='42501'; end if;
     compact=replace(request.card_uid,':','');
     perform pg_advisory_xact_lock(hashtextextended(compact,0));
     select * into current_card from public.nfc_cards where upper(regexp_replace(card_uid,'[^0-9A-Fa-f]','','g'))=compact limit 1 for update;
     if found and current_card.profile_id is distinct from p_profile_id then raise exception 'card_already_assigned'; end if;
     if current_card.id is null then
       insert into public.nfc_cards(card_uid,profile_id,card_type,label,active,registered_by) values(request.card_uid,p_profile_id,'estudiante','Tarjeta personal',true,auth.uid());
     else
       update public.nfc_cards set active=true where id=current_card.id;
     end if;
   end if;
   if request.level_id is not null then
     insert into public.student_details(profile_id,level_id) values(p_profile_id,request.level_id)
     on conflict(profile_id) do update set level_id=excluded.level_id,updated_at=now();
   end if;
 end if;
 update public.enrollment_requests set status=case when p_approve then 'approved' else 'rejected' end,updated_at=now() where profile_id=p_profile_id;
end; $$;
revoke all on function public.submit_enrollment(text,text,uuid,text),public.review_enrollment(uuid,boolean) from public,anon;
grant execute on function public.submit_enrollment(text,text,uuid,text),public.review_enrollment(uuid,boolean) to authenticated;
