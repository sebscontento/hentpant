-- Migration: Add missing indexes for query performance optimization
-- Date: 2026-03-28
-- Purpose: Optimize queries on collector_id, moderator_request_status, and reports table

-- Index on listings.collector_id for efficient filtering of claimed listings
create index if not exists listings_collector_idx on public.listings (collector_id)
where collector_id is not null;

-- Index on profiles.moderator_request_status for filtering pending moderator applications
create index if not exists profiles_moderator_request_status_idx on public.profiles (moderator_request_status)
where moderator_request_status != 'none';

-- Compound index on reports for staff filtering (only if table exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'reports') then
    execute 'create index if not exists reports_staff_view_idx on public.reports (created_at desc, target)';
  end if;
end
$$;

-- Partial index on available listings for faster "available for claims" queries
create index if not exists listings_available_idx on public.listings (created_at desc)
where status = 'available';

-- Index on ratings.from_user_id for user's outgoing ratings
create index if not exists ratings_from_user_idx on public.ratings (from_user_id);

-- Partial index for active listings (those needing moderator attention)
create index if not exists listings_active_idx on public.listings (created_at desc)
where status in ('available', 'reserved', 'awaitingGiverConfirmation');
