-- Repair hosted schema drift where migration history is current but the
-- listings table is missing lifecycle columns expected by the app/RPCs.

alter table public.listings
add column if not exists moderation_reason text;
