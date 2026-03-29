-- Migration: Optimize RPC functions to return updated rows
-- Date: 2026-03-28
-- Purpose: Reduce post-mutation queries by returning the updated state from RPC functions

-- Drop existing functions first so we can change their return types
drop function if exists public.claim_listing(uuid);
drop function if exists public.mark_listing_picked_up(uuid);
drop function if exists public.confirm_listing_pickup(uuid);
drop function if exists public.release_listing_claim(uuid);
drop function if exists public.update_own_participation_roles(boolean, boolean);

-- Replace claim_listing to return the updated listing
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
  set status = 'reserved', collector_id = uid
  where l.id = p_listing_id
    and l.status = 'available'
    and l.giver_id <> uid;

  if not found then
    raise exception 'Cannot claim listing';
  end if;

  return query
  select * from public.listings where id = p_listing_id;
end;
$$;

-- Replace mark_listing_picked_up to return the updated listing
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
  set status = 'awaitingGiverConfirmation', picked_up_at = now()
  where l.id = p_listing_id
    and l.status = 'reserved'
    and l.collector_id = uid;

  if not found then
    raise exception 'Cannot mark picked up';
  end if;

  return query
  select * from public.listings where id = p_listing_id;
end;
$$;

-- Replace confirm_listing_pickup to return the updated listing
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
    and l.status = 'awaitingGiverConfirmation'
    and l.giver_id = uid;

  if not found then
    raise exception 'Cannot confirm pickup';
  end if;

  return query
  select * from public.listings where id = p_listing_id;
end;
$$;

-- Replace release_listing_claim to return the updated listing
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
    picked_up_at = null
  where l.id = p_listing_id
    and l.status = 'reserved'
    and l.collector_id = uid;

  if not found then
    raise exception 'Cannot release claim';
  end if;

  return query
  select * from public.listings where id = p_listing_id;
end;
$$;

-- Optimize update_own_participation_roles to return updated profile
create or replace function public.update_own_participation_roles(p_can_give boolean, p_can_receive boolean)
returns table (
    id uuid,
    display_name text,
    email text,
    can_give boolean,
    can_receive boolean,
    staff_role text,
    moderator_request_status text,
    average_rating double precision,
    rating_count integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not coalesce(p_can_give, false) and not coalesce(p_can_receive, false) then
    raise exception 'Choose at least one role';
  end if;

  update public.profiles
  set
    can_give = p_can_give,
    can_receive = p_can_receive,
    updated_at = now()
  where id = auth.uid();

  if not found then
    raise exception 'Profile not found';
  end if;

  return query
  select id, display_name, email, can_give, can_receive, staff_role, moderator_request_status, average_rating, rating_count
  from public.profiles where id = auth.uid();
end;
$$;
