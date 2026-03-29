alter table public.listings
drop constraint if exists listings_status_check;

update public.listings
set status = 'pending_pickup'
where status = 'claimed';

alter table public.listings
add constraint listings_status_check
check (status in ('available', 'pending_pickup', 'completed', 'removed'));

create or replace function public.claim_listing(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = uid
      and (p.can_receive or p.staff_role in ('moderator', 'admin'))
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
end;
$$;

create or replace function public.mark_listing_picked_up(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  update public.listings l
  set
    status = 'completed',
    picked_up_at = now(),
    giver_confirmed_at = coalesce(giver_confirmed_at, now())
  where l.id = p_listing_id
    and l.status = 'pending_pickup'
    and l.collector_id = uid;

  if not found then
    raise exception 'Cannot mark picked up';
  end if;
end;
$$;

create or replace function public.confirm_listing_pickup(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

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
end;
$$;

create or replace function public.release_listing_claim(p_listing_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

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
end;
$$;

grant execute on function public.claim_listing(uuid) to authenticated;
grant execute on function public.mark_listing_picked_up(uuid) to authenticated;
grant execute on function public.confirm_listing_pickup(uuid) to authenticated;
grant execute on function public.release_listing_claim(uuid) to authenticated;
