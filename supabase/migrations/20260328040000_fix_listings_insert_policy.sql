grant usage on schema public to authenticated;
grant select, insert on public.listings to authenticated;

drop policy if exists "listings_select_authenticated" on public.listings;
create policy "listings_select_authenticated"
  on public.listings for select
  to authenticated
  using (true);

drop policy if exists "listings_insert_giver" on public.listings;
create policy "listings_insert_giver"
  on public.listings for insert
  to authenticated
  with check (
    auth.uid() = giver_id
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and (p.can_give or p.staff_role in ('moderator', 'admin'))
    )
  );
