-- Migration: Add push notification support
-- Date: 2026-03-28
-- Purpose: Track device tokens for push notifications

-- Add device tokens to profiles table
alter table public.profiles add column if not exists device_tokens text[] default '{}';
alter table public.profiles add column if not exists last_notification_date timestamptz;

-- Create index for efficient device token lookups
create index if not exists profiles_device_tokens_idx on public.profiles using gin (device_tokens);

-- RPC function to register or update device token
create or replace function public.register_device_token(p_device_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Add token if not already present, update last_notification_date
  update public.profiles
  set 
    device_tokens = case 
      when not (device_tokens @> array[p_device_token]) then array_append(device_tokens, p_device_token)
      else device_tokens
    end,
    last_notification_date = now()
  where id = uid;
end;
$$;

-- RPC function to unregister device token
create or replace function public.unregister_device_token(p_device_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set device_tokens = array_remove(device_tokens, p_device_token)
  where id = uid;
end;
$$;

-- RPC function to send notification to user (for moderators/admins)
create or replace function public.send_notification_to_user(
  p_target_user_id uuid,
  p_title text,
  p_body text,
  p_data jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id uuid := auth.uid();
  v_sender_role text;
  v_tokens text[];
  v_result jsonb;
begin
  if v_sender_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Check if sender is moderator or admin
  select staff_role into v_sender_role from public.profiles where id = v_sender_id;
  if v_sender_role not in ('moderator', 'admin') then
    raise exception 'Only moderators or admins can send notifications';
  end if;

  -- Get target user's device tokens
  select device_tokens into v_tokens from public.profiles where id = p_target_user_id;

  -- Return notification payload (in production, would integrate with FCM)
  v_result := jsonb_build_object(
    'target_user_id', p_target_user_id,
    'title', p_title,
    'body', p_body,
    'data', coalesce(p_data, '{}'::jsonb),
    'device_count', array_length(v_tokens, 1),
    'sent_at', now()
  );

  return v_result;
end;
$$;

-- RPC function to notify listing participants of status change
create or replace function public.notify_listing_participants(
  p_listing_id uuid,
  p_event_type text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_giver_id uuid;
  v_collector_id uuid;
  v_result jsonb;
begin
  -- Get listing participants
  select giver_id, collector_id into v_giver_id, v_collector_id
  from public.listings where id = p_listing_id;

  if v_giver_id is null then
    raise exception 'Listing not found';
  end if;

  -- Build notification payload
  v_result := jsonb_build_object(
    'listing_id', p_listing_id::text,
    'event_type', p_event_type,
    'message', p_message,
    'giver_notified', v_giver_id is not null,
    'collector_notified', v_collector_id is not null,
    'sent_at', now()
  );

  return v_result;
end;
$$;

grant execute on function public.register_device_token(text) to authenticated;
grant execute on function public.unregister_device_token(text) to authenticated;
grant execute on function public.send_notification_to_user(uuid, text, text, jsonb) to authenticated;
grant execute on function public.notify_listing_participants(uuid, text, text) to authenticated;
