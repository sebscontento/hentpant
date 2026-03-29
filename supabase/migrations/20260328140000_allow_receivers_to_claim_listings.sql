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
  set status = 'reserved', collector_id = uid
  where l.id = p_listing_id
    and l.status = 'available'
    and l.giver_id <> uid;

  if not found then
    raise exception 'Cannot claim listing';
  end if;
end;
$$;

grant execute on function public.claim_listing(uuid) to authenticated;
