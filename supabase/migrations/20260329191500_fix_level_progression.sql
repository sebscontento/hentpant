-- Migration: Fix level progression thresholds
-- Date: 2026-03-29
-- Problem: award_points kept users at level 1 until 1000 points because
-- the previous formula used integer division with a minimum level of 1.

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
    insert into public.user_stats (id)
    values (p_user_id)
    on conflict (id) do nothing;

    update public.user_stats
    set points = points + p_points,
        updated_at = now()
    where id = p_user_id
    returning points into v_new_points;

    -- Level 1 covers 0-499 points, level 2 starts at 500, etc.
    v_new_level := greatest(1, (v_new_points / 500) + 1);

    update public.user_stats
    set level = v_new_level,
        updated_at = now()
    where id = p_user_id;
end;
$$;

update public.user_stats
set level = greatest(1, (points / 500) + 1),
    updated_at = now()
where level is distinct from greatest(1, (points / 500) + 1);
