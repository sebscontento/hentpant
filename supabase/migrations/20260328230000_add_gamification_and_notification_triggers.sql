-- Migration: Gamification and Notification Trigger
-- Purpose: Automates push notification dispatch and database points when listing status changes

create or replace function public.handle_listing_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  -- IF INSERT (Listing created) -> Award 10 points to giver
  if TG_OP = 'INSERT' then
    perform public.award_points(NEW.giver_id, 10, 'Listing posted');

    -- Check if this is their first listing
    select count(*) into v_count from public.listings where giver_id = NEW.giver_id;
    if v_count = 1 then
      perform public.unlock_achievement(NEW.giver_id, 'firstListing');
    end if;

    return NEW;
  end if;

  -- IF UPDATE -> only act when status actually changed
  if TG_OP = 'UPDATE' and OLD.status is distinct from NEW.status then

    -- Listing claimed: status goes to 'reserved'
    if NEW.status = 'reserved' then
      perform public.notify_listing_participants(NEW.id, 'listing_claimed', 'Your listing was just claimed!');
    end if;

    -- Collector marked picked up: status goes to 'awaitingGiverConfirmation'
    if NEW.status = 'awaitingGiverConfirmation' then
      perform public.notify_listing_participants(NEW.id, 'listing_picked_up', 'Your item was picked up!');
    end if;

    -- Giver confirmed pickup: status goes to 'completed'
    if NEW.status = 'completed' then
      perform public.notify_listing_participants(NEW.id, 'listing_completed', 'Pickup confirmed and points awarded!');
      perform public.process_gamification_on_listing_complete(
        NEW.id,
        NEW.giver_id,
        NEW.collector_id,
        0,
        coalesce(NEW.bag_size, 'medium')
      );
    end if;

  end if;

  return NEW;
end;
$$;

drop trigger if exists on_listing_changed on public.listings;
create trigger on_listing_changed
  after insert or update on public.listings
  for each row execute function public.handle_listing_changes();
