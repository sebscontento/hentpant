-- PantCollect: profiles, listings, ratings, reports + RLS, storage, RPC mutations.

-- Extensions
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  email text not null default '',
  can_give boolean not null default true,
  can_receive boolean not null default true,
  staff_role text not null default 'user' check (staff_role in ('user', 'moderator', 'admin')),
  average_rating double precision not null default 0,
  rating_count integer not null default 0,
  updated_at timestamptz not null default now()
);

create index profiles_staff_role_idx on public.profiles (staff_role);

-- New auth user → profile row (reads signup metadata)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email, can_give, can_receive)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
      split_part(coalesce(new.email, 'user@local'), '@', 1)
    ),
    coalesce(new.email, ''),
    coalesce((new.raw_user_meta_data->>'can_give')::boolean, true),
    coalesce((new.raw_user_meta_data->>'can_receive')::boolean, true)
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Prevent non-admins from changing staff_role
create or replace function public.profiles_enforce_staff_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.staff_role is distinct from old.staff_role then
    if not exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.staff_role = 'admin'
    ) then
      raise exception 'Only admins can change staff roles';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_staff_guard on public.profiles;
create trigger profiles_staff_guard
  before update on public.profiles
  for each row execute function public.profiles_enforce_staff_role();

alter table public.profiles enable row level security;

create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- Listings
-- ---------------------------------------------------------------------------
create table public.listings (
  id uuid primary key default gen_random_uuid(),
  giver_id uuid not null references public.profiles (id) on delete cascade,
  photo_paths text[] not null default '{}',
  quantity_text text not null,
  bag_size text not null check (bag_size in ('small', 'medium', 'large')),
  latitude double precision not null,
  longitude double precision not null,
  detail text,
  status text not null default 'available' check (
    status in ('available', 'reserved', 'awaitingGiverConfirmation', 'completed', 'removed')
  ),
  collector_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  picked_up_at timestamptz,
  giver_confirmed_at timestamptz,
  moderation_reason text
);

create index listings_status_idx on public.listings (status);
create index listings_giver_idx on public.listings (giver_id);
create index listings_created_idx on public.listings (created_at desc);

alter table public.listings enable row level security;

create policy "listings_select_authenticated"
  on public.listings for select
  to authenticated
  using (true);

create policy "listings_insert_giver"
  on public.listings for insert
  to authenticated
  with check (auth.uid() = giver_id);

-- ---------------------------------------------------------------------------
-- Ratings
-- ---------------------------------------------------------------------------
create table public.ratings (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  from_user_id uuid not null references public.profiles (id) on delete cascade,
  to_user_id uuid not null references public.profiles (id) on delete cascade,
  stars integer not null check (stars >= 1 and stars <= 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (listing_id, from_user_id, to_user_id)
);

create index ratings_to_user_idx on public.ratings (to_user_id);

alter table public.ratings enable row level security;

create policy "ratings_select_authenticated"
  on public.ratings for select
  to authenticated
  using (true);

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

-- ---------------------------------------------------------------------------
-- Reports
-- ---------------------------------------------------------------------------
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  target text not null check (target in ('listing', 'user')),
  target_id text not null,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

alter table public.reports enable row level security;

create policy "reports_insert_own"
  on public.reports for insert
  to authenticated
  with check (auth.uid() = reporter_id);

create policy "reports_select_staff"
  on public.reports for select
  to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.staff_role in ('moderator', 'admin'))
  );

-- ---------------------------------------------------------------------------
-- RPC: listing lifecycle (SECURITY DEFINER bypasses missing UPDATE policies)
-- ---------------------------------------------------------------------------
create or replace function public.set_listing_photo_paths(p_listing_id uuid, p_paths text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  update public.listings l
  set photo_paths = p_paths
  where l.id = p_listing_id and l.giver_id = auth.uid();
  if not found then
    raise exception 'Listing not found or not owner';
  end if;
end;
$$;

create or replace function public.claim_listing(p_listing_id uuid)
returns void
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
  if uid is null then raise exception 'Not authenticated'; end if;

  update public.listings l
  set status = 'awaitingGiverConfirmation', picked_up_at = now()
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
  if uid is null then raise exception 'Not authenticated'; end if;

  update public.listings l
  set status = 'completed', giver_confirmed_at = now()
  where l.id = p_listing_id
    and l.status = 'awaitingGiverConfirmation'
    and l.giver_id = uid;

  if not found then
    raise exception 'Cannot confirm pickup';
  end if;
end;
$$;

create or replace function public.moderate_remove_listing(p_listing_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.staff_role in ('moderator', 'admin')
  ) then
    raise exception 'Not moderator';
  end if;

  update public.listings
  set status = 'removed', moderation_reason = nullif(trim(p_reason), '')
  where id = p_listing_id;
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

  update public.profiles set staff_role = p_role where id = p_target;
end;
$$;

create or replace function public.admin_delete_user(p_target uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid() and p.staff_role = 'admin') then
    raise exception 'Not admin';
  end if;
  if p_target = auth.uid() then
    raise exception 'Cannot delete self';
  end if;

  delete from auth.users where id = p_target;
end;
$$;

grant execute on function public.set_listing_photo_paths(uuid, text[]) to authenticated;
grant execute on function public.claim_listing(uuid) to authenticated;
grant execute on function public.mark_listing_picked_up(uuid) to authenticated;
grant execute on function public.confirm_listing_pickup(uuid) to authenticated;
grant execute on function public.moderate_remove_listing(uuid, text) to authenticated;
grant execute on function public.admin_set_staff_role(uuid, text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: public read, authenticated upload to own listing folder
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'listing-photos',
  'listing-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "listing_photos_public_read"
  on storage.objects for select
  to public
  using (bucket_id = 'listing-photos');

create policy "listing_photos_insert_owner"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'listing-photos'
    and exists (
      select 1
      from public.listings l
      where l.id::text = split_part(name, '/', 1)
        and l.giver_id = auth.uid()
    )
  );

create policy "listing_photos_delete_owner"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'listing-photos'
    and exists (
      select 1
      from public.listings l
      where l.id::text = split_part(name, '/', 1)
        and l.giver_id = auth.uid()
    )
  );
