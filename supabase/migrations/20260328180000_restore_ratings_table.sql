create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  from_user_id uuid not null references public.profiles (id) on delete cascade,
  to_user_id uuid not null references public.profiles (id) on delete cascade,
  stars integer not null check (stars >= 1 and stars <= 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (listing_id, from_user_id, to_user_id)
);

create index if not exists ratings_to_user_idx on public.ratings (to_user_id);

alter table public.ratings enable row level security;

drop policy if exists "ratings_select_authenticated" on public.ratings;
create policy "ratings_select_authenticated"
  on public.ratings for select
  to authenticated
  using (true);

drop policy if exists "ratings_insert_participant" on public.ratings;
create policy "ratings_insert_participant"
  on public.ratings for insert
  to authenticated
  with check (
    auth.uid() = from_user_id
    and from_user_id <> to_user_id
    and exists (
      select 1
      from public.listings l
      where l.id = listing_id
        and l.status = 'completed'
        and (l.giver_id = auth.uid() or l.collector_id = auth.uid())
        and (to_user_id = l.giver_id or to_user_id = l.collector_id)
    )
  );

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
  return new;
end;
$$;

drop trigger if exists ratings_refresh_stats on public.ratings;
create trigger ratings_refresh_stats
  after insert on public.ratings
  for each row execute function public.after_rating_insert();
