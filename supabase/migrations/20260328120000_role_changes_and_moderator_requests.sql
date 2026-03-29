alter table public.profiles
add column if not exists moderator_request_status text not null default 'none'
check (moderator_request_status in ('none', 'pending', 'rejected'));

create or replace function public.update_own_participation_roles(p_can_give boolean, p_can_receive boolean)
returns void
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
end;
$$;

create or replace function public.request_moderator_role()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set
    moderator_request_status = 'pending',
    updated_at = now()
  where id = auth.uid()
    and staff_role = 'user'
    and moderator_request_status <> 'pending';

  if not found then
    raise exception 'Cannot request moderator role';
  end if;
end;
$$;

create or replace function public.admin_review_moderator_application(p_target uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.staff_role = 'admin'
  ) then
    raise exception 'Not admin';
  end if;

  update public.profiles
  set
    staff_role = case when p_approve then 'moderator' else staff_role end,
    moderator_request_status = case when p_approve then 'none' else 'rejected' end,
    updated_at = now()
  where id = p_target
    and staff_role = 'user'
    and moderator_request_status = 'pending';

  if not found then
    raise exception 'No pending moderator application';
  end if;
end;
$$;

create or replace function public.admin_set_staff_role(p_target uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.staff_role = 'admin') then
    raise exception 'Not admin';
  end if;
  if p_target = auth.uid() then
    raise exception 'Cannot change own role';
  end if;
  if p_role not in ('user', 'moderator', 'admin') then
    raise exception 'Invalid role';
  end if;

  update public.profiles
  set
    staff_role = p_role,
    moderator_request_status = 'none',
    updated_at = now()
  where id = p_target;
end;
$$;

grant execute on function public.update_own_participation_roles(boolean, boolean) to authenticated;
grant execute on function public.request_moderator_role() to authenticated;
grant execute on function public.admin_review_moderator_application(uuid, boolean) to authenticated;
