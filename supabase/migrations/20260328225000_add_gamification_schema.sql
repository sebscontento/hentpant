-- Migration: Full gamification schema
-- Date: 2026-03-28
-- Purpose: Create user_stats, achievements tables and all gamification RPC functions

-- User stats table
create table if not exists public.user_stats (
    id uuid primary key references auth.users(id) on delete cascade,
    total_listings_posted int not null default 0,
    total_listings_collected int not null default 0,
    total_distance_meters numeric not null default 0,
    total_earnings_dkk numeric not null default 0,
    points int not null default 0,
    level int not null default 1,
    streak_days int not null default 0,
    last_active_date timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Achievements table
create table if not exists public.achievements (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    type text not null,
    unlocked_at timestamptz,
    points_awarded int not null default 0,
    created_at timestamptz not null default now(),
    unique(user_id, type)
);

-- Indexes
create index if not exists idx_achievements_user_id on public.achievements(user_id);
create index if not exists idx_achievements_type on public.achievements(type);
create index if not exists idx_user_stats_points on public.user_stats(points desc);

-- Trigger to create user_stats row when a new profile is created
create or replace function public.create_user_stats()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.user_stats (id)
    values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created
    after insert on public.profiles
    for each row execute function public.create_user_stats();

-- Backfill user_stats for any existing profiles without a row
insert into public.user_stats (id)
select id from public.profiles
on conflict (id) do nothing;

-- Function to award points to a user
create or replace function public.award_points(p_user_id uuid, p_points int, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_new_points int;
    v_new_level int;
begin
    update public.user_stats
    set points = points + p_points,
        updated_at = now()
    where id = p_user_id
    returning points into v_new_points;

    -- Calculate new level (every 500 points = 1 level)
    v_new_level := greatest(1, v_new_points / 500);

    update public.user_stats
    set level = v_new_level,
        updated_at = now()
    where id = p_user_id;
end;
$$;

-- Function to unlock an achievement
create or replace function public.unlock_achievement(p_user_id uuid, p_type text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_achievement_id uuid;
    v_points int;
    v_already_exists boolean;
begin
    -- Check if already unlocked
    select exists(
        select 1 from public.achievements
        where user_id = p_user_id and type = p_type and unlocked_at is not null
    ) into v_already_exists;

    if v_already_exists then
        return false;
    end if;

    -- Determine points for this achievement type
    case p_type
        when 'firstListing'    then v_points := 50;
        when 'firstPickup'     then v_points := 100;
        when 'tenListings'     then v_points := 250;
        when 'tenPickups'      then v_points := 500;
        when 'fiftyPickups'    then v_points := 2000;
        when 'ecoWarrior'      then v_points := 1000;
        when 'nightOwl'        then v_points := 75;
        when 'weekendWarrior'  then v_points := 150;
        when 'quickCollector'  then v_points := 100;
        when 'generousGiver'   then v_points := 750;
        else v_points := 0;
    end case;

    -- Insert or update achievement row
    insert into public.achievements (user_id, type, unlocked_at, points_awarded)
    values (p_user_id, p_type, now(), v_points)
    on conflict (user_id, type) do update
        set unlocked_at = now(), points_awarded = v_points
    returning id into v_achievement_id;

    -- Award the bonus points
    if v_points > 0 then
        perform public.award_points(p_user_id, v_points, 'Achievement: ' || p_type);
    end if;

    return true;
end;
$$;

-- Function to process gamification when a listing is completed
create or replace function public.process_gamification_on_listing_complete(
    p_listing_id uuid,
    p_giver_id uuid,
    p_collector_id uuid,
    p_distance_meters numeric default 0,
    p_bag_size text default 'medium'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_earnings_dkk numeric;
    v_listing_count int;
    v_pickup_count int;
begin
    -- Calculate earnings based on bag size
    case p_bag_size
        when 'small'  then v_earnings_dkk := 15;
        when 'medium' then v_earnings_dkk := 30;
        when 'large'  then v_earnings_dkk := 45;
        else v_earnings_dkk := 25;
    end case;

    -- Update giver stats
    update public.user_stats
    set total_listings_posted = total_listings_posted + 1,
        last_active_date = now(),
        updated_at = now()
    where id = p_giver_id;

    -- Update collector stats
    update public.user_stats
    set total_listings_collected = total_listings_collected + 1,
        total_distance_meters = total_distance_meters + p_distance_meters,
        total_earnings_dkk = total_earnings_dkk + v_earnings_dkk,
        last_active_date = now(),
        updated_at = now()
    where id = p_collector_id;

    -- Award completion points
    perform public.award_points(p_giver_id, 25, 'Listing completed');
    perform public.award_points(p_collector_id, 50, 'Pickup completed');

    -- Giver achievements
    select count(*) into v_listing_count
    from public.listings where giver_id = p_giver_id;

    if v_listing_count >= 1  then perform public.unlock_achievement(p_giver_id, 'firstListing'); end if;
    if v_listing_count >= 10 then perform public.unlock_achievement(p_giver_id, 'tenListings'); end if;
    if v_listing_count >= 25 then perform public.unlock_achievement(p_giver_id, 'generousGiver'); end if;

    -- Collector achievements
    select count(*) into v_pickup_count
    from public.listings where collector_id = p_collector_id and status = 'completed';

    if v_pickup_count >= 1  then perform public.unlock_achievement(p_collector_id, 'firstPickup'); end if;
    if v_pickup_count >= 10 then perform public.unlock_achievement(p_collector_id, 'tenPickups'); end if;
    if v_pickup_count >= 50 then perform public.unlock_achievement(p_collector_id, 'fiftyPickups'); end if;
end;
$$;

-- Row Level Security
alter table public.user_stats enable row level security;
alter table public.achievements enable row level security;

-- Users can view their own stats
do $$ begin
  if not exists (
    select 1 from pg_policies where tablename = 'user_stats' and policyname = 'Users can view own stats'
  ) then
    create policy "Users can view own stats" on public.user_stats
      for select using (auth.uid() = id);
  end if;
end $$;

-- Users can view public leaderboard (all rows, points + level)
do $$ begin
  if not exists (
    select 1 from pg_policies where tablename = 'user_stats' and policyname = 'Users can view leaderboard'
  ) then
    create policy "Users can view leaderboard" on public.user_stats
      for select using (true);
  end if;
end $$;

-- Users can view their own achievements
do $$ begin
  if not exists (
    select 1 from pg_policies where tablename = 'achievements' and policyname = 'Users can view own achievements'
  ) then
    create policy "Users can view own achievements" on public.achievements
      for select using (auth.uid() = user_id);
  end if;
end $$;

-- Grants
grant select on public.user_stats to authenticated;
grant select on public.achievements to authenticated;
grant execute on function public.award_points(uuid, int, text) to authenticated;
grant execute on function public.unlock_achievement(uuid, text) to authenticated;
grant execute on function public.process_gamification_on_listing_complete(uuid, uuid, uuid, numeric, text) to authenticated;
