-- Migration: Fix update_own_participation_roles column ambiguity
-- Date: 2026-03-29
-- Problem: The RPC returns a table with an output column named `id`.
-- In PL/pgSQL, output columns are variables in scope, so unqualified references
-- like `where id = auth.uid()` become ambiguous against `public.profiles.id`.

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
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  if not coalesce(p_can_give, false) and not coalesce(p_can_receive, false) then
    raise exception 'Choose at least one role';
  end if;

  update public.profiles p
  set
    can_give = p_can_give,
    can_receive = p_can_receive,
    updated_at = now()
  where p.id = uid;

  if not found then
    raise exception 'Profile not found';
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.email,
    p.can_give,
    p.can_receive,
    p.staff_role,
    p.moderator_request_status,
    p.average_rating,
    p.rating_count
  from public.profiles p
  where p.id = uid;
end;
$$;

grant execute on function public.update_own_participation_roles(boolean, boolean) to authenticated;
