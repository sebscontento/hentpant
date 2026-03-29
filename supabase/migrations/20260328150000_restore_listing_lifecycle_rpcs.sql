alter table public.listings
add column if not exists picked_up_at timestamptz,
add column if not exists giver_confirmed_at timestamptz;

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
    status = 'awaitingGiverConfirmation',
    picked_up_at = now()
  where l.id = p_listing_id
    and l.status = 'reserved'
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
    and l.status = 'awaitingGiverConfirmation'
    and l.giver_id = uid;

  if not found then
    raise exception 'Cannot confirm pickup';
  end if;
end;
$$;

grant execute on function public.mark_listing_picked_up(uuid) to authenticated;
grant execute on function public.confirm_listing_pickup(uuid) to authenticated;
