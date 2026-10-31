-- Evaluate the JWT subject once per query, not once per stored marker row.
drop policy if exists initial_admin_card_registration_admin_read
  on fwt_private.initial_admin_card_registration;
create policy initial_admin_card_registration_admin_read
  on fwt_private.initial_admin_card_registration
  for select to authenticated
  using (
    public.has_permission('nfc.manage')
    and exists (
      select 1
      from public.profiles p
      join public.roles r on r.id = p.role_id
      where p.id = (select auth.uid())
        and p.status = 'active'
        and r.name = 'admin'
    )
  );
