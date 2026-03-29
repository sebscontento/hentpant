-- Update handle_new_user to explicitly set moderator_request_status
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email, can_give, can_receive, moderator_request_status)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
      split_part(coalesce(new.email, 'user@local'), '@', 1)
    ),
    coalesce(new.email, ''),
    coalesce((new.raw_user_meta_data->>'can_give')::boolean, true),
    coalesce((new.raw_user_meta_data->>'can_receive')::boolean, true),
    'none'
  );
  return new;
end;
$$;
