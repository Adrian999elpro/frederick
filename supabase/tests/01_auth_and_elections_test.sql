\set ON_ERROR_STOP off
create temp table t_res(name text, ok boolean, info text);
grant all on t_res to public;

-- helper: ejecuta SQL y registra si falló / pasó
create function pg_temp.expect_fail(name text, stmt text, must_contain text default '') returns void language plpgsql as $$
begin
  begin execute stmt; insert into t_res values (name, false, 'NO falló');
  exception when others then
    insert into t_res values (name, (must_contain = '' or sqlerrm like '%'||must_contain||'%'), sqlerrm);
  end;
end $$;
create function pg_temp.expect_ok(name text, stmt text) returns void language plpgsql as $$
begin
  begin execute stmt; insert into t_res values (name, true, '');
  exception when others then insert into t_res values (name, false, sqlerrm);
  end;
end $$;

-- 1) Registro cerrado
select pg_temp.expect_fail('registro cerrado bloquea signUp', $$insert into auth.users(email) values ('x@y.com')$$, 'registration_closed');

-- 2) Usuarios provisionados por el servidor
insert into auth.users(id,email,raw_app_meta_data) values
 ('00000000-0000-0000-0000-0000000000a1','admin@x.com','{"provisioned":true,"role":"admin"}'),
 ('00000000-0000-0000-0000-0000000000b1','est1@x.com','{"provisioned":true,"role":"estudiante"}'),
 ('00000000-0000-0000-0000-0000000000b2','est2@x.com','{"provisioned":true,"role":"estudiante"}'),
 ('00000000-0000-0000-0000-0000000000c1','doc@x.com','{"provisioned":true,"role":"docente"}');
insert into t_res select 'perfiles creados por trigger', (select count(*)=4 from public.profiles), '';

-- 3) Modo dominio y modo abierto; rol admin no permitido para auto-registro
update public.app_settings set value='{"mode":"domain","allowed_domains":["escuela.edu"],"default_role":"estudiante"}' where key='registration';
select pg_temp.expect_fail('dominio no permitido', $$insert into auth.users(email) values ('a@gmail.com')$$, 'domain_not_allowed');
select pg_temp.expect_ok('dominio permitido -> rol por defecto', $$insert into auth.users(id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000d1','Nuevo@Escuela.edu','{"full_name":"Nuevo"}')$$);
insert into t_res select 'rol por defecto aplicado + email en minúsculas', (select r.name='estudiante' and p.email='nuevo@escuela.edu' from public.profiles p join public.roles r on r.id=p.role_id where p.id='00000000-0000-0000-0000-0000000000d1'), '';
update public.app_settings set value='{"mode":"open","allowed_domains":[],"default_role":"admin"}' where key='registration';
select pg_temp.expect_fail('default_role admin no permitido en auto-registro', $$insert into auth.users(email, raw_user_meta_data) values ('h@x.com','{"role":"admin"}')$$, 'role_not_allowed_for_signup');
update public.app_settings set value='{"mode":"open","allowed_domains":[],"default_role":"usuario"}' where key='registration';
select pg_temp.expect_ok('modo abierto', $$insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data) values ('00000000-0000-0000-0000-0000000000e1','h2@x.com','{"role":"admin"}','{}')$$);
insert into t_res select 'metadata del usuario NO puede elegir rol', (select r.name='usuario' from public.profiles p join public.roles r on r.id=p.role_id where p.id='00000000-0000-0000-0000-0000000000e1'), '';
update public.app_settings set value='{"mode":"closed","allowed_domains":[],"default_role":"usuario"}' where key='registration';
select pg_temp.expect_fail('constraint de forma en settings', $$update public.app_settings set value='{"mode":"loquesea","allowed_domains":[]}' where key='registration'$$, 'registration_shape');
-- ===== Como usuarios autenticados (RLS real) =====
-- como estudiante 1
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.expect_fail('estudiante no puede subir su rol', $$update public.profiles set role_id=(select id from public.roles where name='admin') where id=auth.uid()$$, 'permission denied');
select pg_temp.expect_fail('estudiante no puede cambiar su estado', $$update public.profiles set status='active' where id=auth.uid()$$, 'permission denied');
select pg_temp.expect_ok('estudiante edita su nombre', $$update public.profiles set full_name='Ana' where id=auth.uid()$$);
insert into t_res select 'estudiante solo ve su propio perfil', (select count(*)=1 from public.profiles), '';
select pg_temp.expect_fail('estudiante no lee ajustes', $$select 1/(select count(*) from public.app_settings)$$, 'division by zero');
select pg_temp.expect_fail('estudiante no crea roles', $$insert into public.roles(name) values ('hacker')$$, 'row-level security');
select pg_temp.expect_fail('estudiante no llama set_role_permissions', $$select public.set_role_permissions((select id from public.roles where name='usuario'), array['users.manage'])$$, 'forbidden');
select pg_temp.expect_fail('estudiante no crea votaciones', $$insert into public.elections(title,starts_at,ends_at) values ('x x x', now(), now()+interval '1 day')$$, 'row-level security');
select pg_temp.expect_fail('estudiante no lee papeletas', $$select * from public.ballots$$, 'permission denied');
select pg_temp.expect_fail('estudiante no ve estadísticas', $$select public.election_results(gen_random_uuid())$$, 'forbidden');
select pg_temp.expect_fail('log_event no es llamable por el cliente', $$select public.log_event('x')$$, 'permission denied');
reset role;

-- como anon
set role anon;
select pg_temp.expect_fail('anon no ejecuta has_permission', $$select public.has_permission('users.read')$$, 'permission denied');
select pg_temp.expect_ok('anon sí consulta modo de registro', $$select public.public_registration_mode()$$);
select pg_temp.expect_fail('anon no lee profiles', $$select * from public.profiles$$, 'permission denied');
reset role;

-- como admin: crear votación + listas
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.expect_ok('admin crea votación', $$insert into public.elections(title,starts_at,ends_at) values ('Consejo Estudiantil 2026', now()-interval '1 hour', now()+interval '1 day')$$);
select set_config('app.eid', (select id::text from public.elections limit 1), false);
select pg_temp.expect_ok('admin crea listas', $$insert into public.election_lists(election_id,number,name,president_name) values (current_setting('app.eid')::uuid,1,'Lista Uno','Presidente Uno'),(current_setting('app.eid')::uuid,2,'Lista Dos','Presidente Dos')$$);
select pg_temp.expect_fail('lista duplicada (mismo número)', $$insert into public.election_lists(election_id,number,name,president_name) values (current_setting('app.eid')::uuid,1,'Otra','X')$$, 'duplicate key');
select pg_temp.expect_ok('admin ve usuarios', $$select 1/(select (count(*)>=4)::int from public.profiles)$$);
select pg_temp.expect_fail('admin no edita permisos de admin', $$select public.set_role_permissions((select id from public.roles where name='admin'), array[]::text[])$$, 'admin_locked');
select pg_temp.expect_ok('admin edita permisos de rol docente', $$select public.set_role_permissions((select id from public.roles where name='docente'), array['elections.stats','users.read'])$$);
select pg_temp.expect_fail('permiso inexistente rechazado', $$select public.set_role_permissions((select id from public.roles where name='docente'), array['nada.nada'])$$, 'unknown_permission');
select pg_temp.expect_ok('admin abre la votación', $$update public.elections set status='open' where id=current_setting('app.eid')::uuid$$);
select pg_temp.expect_fail('votación abierta no se edita', $$update public.elections set title='Cambio tramposo' where id=current_setting('app.eid')::uuid$$, 'election_locked');
select pg_temp.expect_fail('no se agregan listas con votación abierta', $$insert into public.election_lists(election_id,number,name,president_name) values (current_setting('app.eid')::uuid,3,'Tarde','X')$$, 'row-level security');
select pg_temp.expect_fail('no se vuelve a borrador', $$update public.elections set status='draft' where id=current_setting('app.eid')::uuid$$, 'invalid_transition');
insert into t_res select 'registro de auditoría de permisos', (select count(*)>=1 from public.audit_log where action='roles.permissions'), '';
reset role;

-- votar
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
insert into t_res select 'estudiante ve votación abierta', (select count(*)=1 from public.elections), '';
select pg_temp.expect_ok('estudiante vota por lista 1', $$select public.cast_vote(current_setting('app.eid')::uuid, (select id from public.election_lists where number=1))$$);
select pg_temp.expect_fail('no puede votar dos veces', $$select public.cast_vote(current_setting('app.eid')::uuid, null)$$, 'already_voted');
insert into t_res select 'estudiante ve su comprobante', (select count(*)=1 from public.vote_receipts), '';
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';
select pg_temp.expect_ok('estudiante 2 vota en blanco', $$select public.cast_vote(current_setting('app.eid')::uuid, null)$$);
select pg_temp.expect_fail('lista de otra votación rechazada', $$select public.cast_vote(current_setting('app.eid')::uuid, gen_random_uuid())$$, 'invalid_list');
insert into t_res select 'estudiante 2 no ve comprobante ajeno', (select count(*)=1 and bool_and(voter_id='00000000-0000-0000-0000-0000000000b2') from public.vote_receipts), '';
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
select pg_temp.expect_fail('docente no vota', $$select public.cast_vote(current_setting('app.eid')::uuid, null)$$, 'forbidden');
select pg_temp.expect_fail('docente no ve resultados mientras está abierta', $$select public.election_results(current_setting('app.eid')::uuid)$$, 'results_hidden');
reset role;

-- cierre y resultados
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.expect_ok('admin cierra', $$update public.elections set status='closed' where id=current_setting('app.eid')::uuid$$);
select pg_temp.expect_fail('cerrada no se reabre', $$update public.elections set status='open' where id=current_setting('app.eid')::uuid$$, 'election_closed');
insert into t_res select 'admin ve resultados: 2 votos, 1 en blanco, lista1=1', (select (r->>'total_votes')::int=2 and (r->>'blank')::int=1 and (r->'lists'->0->>'votes')::int=1 from (select public.election_results(current_setting('app.eid')::uuid) r) x), '';
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
insert into t_res select 'docente ve resultados al cerrar (elegibles=4)', (select (r->>'eligible')::int=4 from (select public.election_results(current_setting('app.eid')::uuid) r) x), '';
reset role;

-- usuario desactivado pierde acceso al instante aunque su sesión siga viva
update public.profiles set status='disabled' where id='00000000-0000-0000-0000-0000000000b2';
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';
insert into t_res select 'desactivado: get_my_access devuelve null', (select public.get_my_access() is null), '';
insert into t_res select 'desactivado: no ve votaciones', (select count(*)=0 from public.elections), '';
select pg_temp.expect_fail('desactivado: no puede votar', $$select public.cast_vote(current_setting('app.eid')::uuid, null)$$, 'forbidden');
reset role;

select case when ok then 'OK   ' else 'FALLA' end as r, name, case when ok then '' else info end as detalle from t_res order by ok, name;
select count(*) filter (where ok) as pasaron, count(*) filter (where not ok) as fallaron from t_res;
