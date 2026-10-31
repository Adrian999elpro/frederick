-- Keep the one-time marker's profile references efficiently addressable.
create index if not exists initial_admin_card_registration_profile_id_idx
  on fwt_private.initial_admin_card_registration (profile_id);
create index if not exists initial_admin_card_registration_registered_by_idx
  on fwt_private.initial_admin_card_registration (registered_by);
