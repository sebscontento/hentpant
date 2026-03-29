grant delete on public.listings to authenticated;

drop policy if exists "listings_delete_own_unclaimed" on public.listings;
create policy "listings_delete_own_unclaimed"
  on public.listings for delete
  to authenticated
  using (
    auth.uid() = giver_id
    and status = 'available'
    and collector_id is null
  );
