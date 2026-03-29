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

drop policy if exists "listing_photos_public_read" on storage.objects;
create policy "listing_photos_public_read"
  on storage.objects for select
  to public
  using (bucket_id = 'listing-photos');

drop policy if exists "listing_photos_insert_owner" on storage.objects;
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

drop policy if exists "listing_photos_delete_owner" on storage.objects;
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
