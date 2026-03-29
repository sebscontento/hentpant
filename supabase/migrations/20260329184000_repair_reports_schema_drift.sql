-- Repair hosted schema drift where migration history is current but the
-- reports table and its policies are missing from the actual database.

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  target text not null check (target in ('listing', 'user')),
  target_id text not null,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

alter table public.reports enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and policyname = 'reports_insert_own'
  ) then
    create policy "reports_insert_own"
      on public.reports for insert
      to authenticated
      with check (auth.uid() = reporter_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'reports'
      and policyname = 'reports_select_staff'
  ) then
    create policy "reports_select_staff"
      on public.reports for select
      to authenticated
      using (
        exists (
          select 1
          from public.profiles p
          where p.id = auth.uid()
            and p.staff_role in ('moderator', 'admin')
        )
      );
  end if;
end
$$;

create index if not exists reports_staff_view_idx
  on public.reports (created_at desc, target);
