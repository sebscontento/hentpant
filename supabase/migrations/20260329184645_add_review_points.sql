-- Award review points while keeping profile rating aggregates in sync.
create or replace function public.after_rating_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles p
  set
    average_rating = coalesce(
      round((select avg(r.stars)::numeric from public.ratings r where r.to_user_id = new.to_user_id), 1),
      0
    )::double precision,
    rating_count = (select count(*)::int from public.ratings r where r.to_user_id = new.to_user_id)
  where p.id = new.to_user_id;

  perform public.award_points(new.from_user_id, 10, 'Review left');

  return new;
end;
$$;
