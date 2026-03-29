-- Migration: Fix RPC functions to use correct status values
-- Date: 2026-03-29
-- Problem: Migration 20260328210000 (optimize_rpc_functions_return_values) re-introduced
-- old status values ('reserved', 'awaitingGiverConfirmation') that were already renamed
-- to 'pending_pickup' in migration 20260328170000, causing check constraint violations
-- on the listings_status_check constraint which only allows:
-- ('available', 'pending_pickup', 'completed', 'removed')

-- Drop existing overloads so we can redefine cleanly
drop function if exists public.claim_listing(uuid);
drop function if exists public.mark_listing_picked_up(uuid);
drop function if exists public.confirm_listing_pickup(uuid);
drop function if exists public.release_listing_claim(uuid);

-- claim_listing: available → pending_pickup
create or replace function public.claim_listing(p_listing_id uuid)
returns table (
    id uuid,
    giver_id uuid,
    photo_paths text[],
    quantity_text text,
    bag_size text,
    latitude double precision,
    longitude double precision,
    detail text,
    status text,
    collector_id uuid,
    created_at timestamptz,
    picked_up_at timestamptz,
    giver_confirmed_at timestamptz,
    moderation_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = uid and (p.can_receive or p.staff_role in ('moderator', 'admin'))
  ) then
    raise exception 'Cannot collect';
  end if;

  update public.listings l
  set status = 'pending_pickup', collector_id = uid
  where l.id = p_listing_id
    and l.status = 'available'
    and l.giver_id <> uid;

  if not found then
    raise exception 'Cannot claim listing';
  end if;

  return query
  select l.id, l.giver_id, l.photo_paths, l.quantity_text, l.bag_size,
         l.latitude, l.longitude, l.detail, l.status, l.collector_id,
         l.created_at, l.picked_up_at, l.giver_confirmed_at, l.moderation_reason
  from public.listings l where l.id = p_listing_id;
end;
$$;

-- mark_listing_picked_up: pending_pickup → completed (collector action)
create or replace function public.mark_listing_picked_up(p_listing_id uuid)
returns table (
    id uuid,
    giver_id uuid,
    photo_paths text[],
    quantity_text text,
    bag_size text,
    latitude double precision,
    longitude double precision,
    detail text,
    status text,
    collector_id uuid,
    created_at timestamptz,
    picked_up_at timestamptz,
    giver_confirmed_at timestamptz,
    moderation_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  update public.listings l
  set
    status = 'completed',
    picked_up_at = now(),
    giver_confirmed_at = coalesce(l.giver_confirmed_at, now())
  where l.id = p_listing_id
    and l.status = 'pending_pickup'
    and l.collector_id = uid;

  if not found then
    raise exception 'Cannot mark picked up';
  end if;

  return query
  select l.id, l.giver_id, l.photo_paths, l.quantity_text, l.bag_size,
         l.latitude, l.longitude, l.detail, l.status, l.collector_id,
         l.created_at, l.picked_up_at, l.giver_confirmed_at, l.moderation_reason
  from public.listings l where l.id = p_listing_id;
end;
$$;

-- confirm_listing_pickup: pending_pickup → completed (giver action)
create or replace function public.confirm_listing_pickup(p_listing_id uuid)
returns table (
    id uuid,
    giver_id uuid,
    photo_paths text[],
    quantity_text text,
    bag_size text,
    latitude double precision,
    longitude double precision,
    detail text,
    status text,
    collector_id uuid,
    created_at timestamptz,
    picked_up_at timestamptz,
    giver_confirmed_at timestamptz,
    moderation_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  update public.listings l
  set
    status = 'completed',
    giver_confirmed_at = now()
  where l.id = p_listing_id
    and l.status = 'pending_pickup'
    and l.giver_id = uid;

  if not found then
    raise exception 'Cannot confirm pickup';
  end if;

  return query
  select l.id, l.giver_id, l.photo_paths, l.quantity_text, l.bag_size,
         l.latitude, l.longitude, l.detail, l.status, l.collector_id,
         l.created_at, l.picked_up_at, l.giver_confirmed_at, l.moderation_reason
  from public.listings l where l.id = p_listing_id;
end;
$$;

-- release_listing_claim: pending_pickup → available (either party can cancel)
create or replace function public.release_listing_claim(p_listing_id uuid)
returns table (
    id uuid,
    giver_id uuid,
    photo_paths text[],
    quantity_text text,
    bag_size text,
    latitude double precision,
    longitude double precision,
    detail text,
    status text,
    collector_id uuid,
    created_at timestamptz,
    picked_up_at timestamptz,
    giver_confirmed_at timestamptz,
    moderation_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not authenticated'; end if;

  update public.listings l
  set
    status = 'available',
    collector_id = null,
    picked_up_at = null,
    giver_confirmed_at = null
  where l.id = p_listing_id
    and l.status = 'pending_pickup'
    and (l.giver_id = uid or l.collector_id = uid);

  if not found then
    raise exception 'Cannot release claim';
  end if;

  return query
  select l.id, l.giver_id, l.photo_paths, l.quantity_text, l.bag_size,
         l.latitude, l.longitude, l.detail, l.status, l.collector_id,
         l.created_at, l.picked_up_at, l.giver_confirmed_at, l.moderation_reason
  from public.listings l where l.id = p_listing_id;
end;
$$;

-- Also fix the gamification/notification trigger which still checks old status values
create or replace function public.handle_listing_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  -- IF INSERT (Listing created) -> Award 10 points to giver
  if TG_OP = 'INSERT' then
    perform public.award_points(NEW.giver_id, 10, 'Listing posted');

    -- Check if this is their first listing
    select count(*) into v_count from public.listings where giver_id = NEW.giver_id;
    if v_count = 1 then
      perform public.unlock_achievement(NEW.giver_id, 'firstListing');
    end if;

    return NEW;
  end if;

  -- IF UPDATE -> only act when status actually changed
  if TG_OP = 'UPDATE' and OLD.status is distinct from NEW.status then

    -- Listing claimed: status goes to 'pending_pickup'
    if NEW.status = 'pending_pickup' then
      perform public.notify_listing_participants(NEW.id, 'listing_claimed', 'Your listing was just claimed!');
    end if;

    -- Giver confirmed / collector marked picked up: status goes to 'completed'
    if NEW.status = 'completed' then
      perform public.notify_listing_participants(NEW.id, 'listing_completed', 'Pickup confirmed and points awarded!');
      perform public.process_gamification_on_listing_complete(
        NEW.id,
        NEW.giver_id,
        NEW.collector_id,
        0,
        coalesce(NEW.bag_size, 'medium')
      );
    end if;

  end if;

  return NEW;
end;
$$;

grant execute on function public.claim_listing(uuid) to authenticated;
grant execute on function public.mark_listing_picked_up(uuid) to authenticated;
grant execute on function public.confirm_listing_pickup(uuid) to authenticated;
grant execute on function public.release_listing_claim(uuid) to authenticated;
