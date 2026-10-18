-- ==============================================================================
-- 0006_card_ranks.sql
-- FWT: Soporte de Rangos Institucionales en Tarjetas NFC
-- (Estudiante, Docente, Directivo/Rector, Administrador Kiosko)
-- y función RPC para vincular, actualizar y reasignar tarjetas a cuentas de usuario.
-- ==============================================================================

-- 1. Actualizar la restricción de tipos de tarjeta para incluir rango directivo
alter table public.nfc_cards drop constraint if exists nfc_cards_card_type_check;
alter table public.nfc_cards add constraint nfc_cards_card_type_check
  check (card_type in ('estudiante', 'docente', 'directivo', 'admin'));

-- 2. Función RPC para vincular o actualizar tarjeta NFC con cuenta y rango
create or replace function public.save_nfc_card_binding(
  p_card_id uuid default null,
  p_card_uid text default null,
  p_profile_id uuid default null,
  p_card_type text default 'estudiante',
  p_label text default '',
  p_active boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_uid text;
  v_res_id uuid;
begin
  if not public.has_permission('nfc.manage') and not public.has_permission('users.manage') then
    raise exception 'forbidden: No tiene permiso para administrar tarjetas institucionales';
  end if;

  if p_card_uid is null and p_card_id is null then
    raise exception 'Debe proporcionar el UID o el ID de la tarjeta';
  end if;

  v_uid := upper(trim(p_card_uid));

  if p_card_id is not null then
    -- Actualizar tarjeta existente
    update public.nfc_cards
    set
      profile_id = p_profile_id,
      card_type = p_card_type,
      label = p_label,
      active = p_active,
      updated_at = now()
    where id = p_card_id
    returning id into v_res_id;
  else
    -- Insertar nueva tarjeta o actualizar por UID
    insert into public.nfc_cards (card_uid, profile_id, card_type, label, active, registered_by, created_at, updated_at)
    values (v_uid, p_profile_id, p_card_type, p_label, p_active, auth.uid(), now(), now())
    on conflict (card_uid)
    do update set
      profile_id = excluded.profile_id,
      card_type = excluded.card_type,
      label = excluded.label,
      active = excluded.active,
      updated_at = now()
    returning id into v_res_id;
  end if;

  return jsonb_build_object('ok', true, 'card_id', v_res_id);
end;
$$;

-- Permisos
grant execute on function public.save_nfc_card_binding(uuid, text, uuid, text, text, boolean) to authenticated;
