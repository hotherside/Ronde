-- Hosted migration version: 20260830055502
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.library_items (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  source_name text check (source_name is null or char_length(source_name) <= 255),
  captured_at timestamptz not null,
  duration_seconds double precision not null default 0 check (duration_seconds >= 0 and duration_seconds <= 60),
  place_name text check (place_name is null or char_length(place_name) <= 120),
  club_name text check (club_name is null or char_length(club_name) <= 80),
  note text not null default '' check (char_length(note) <= 1000),
  is_favourite boolean not null default false,
  trace_provenance text not null default 'unavailable'
    check (trace_provenance in ('unavailable', 'observed', 'observed_and_estimated', 'manual')),
  observed_point_count integer not null default 0 check (observed_point_count >= 0),
  estimated_carry_lower_metres integer check (estimated_carry_lower_metres is null or estimated_carry_lower_metres >= 0),
  estimated_carry_upper_metres integer check (estimated_carry_upper_metres is null or estimated_carry_upper_metres >= estimated_carry_lower_metres),
  device_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id)
);

create index library_items_user_captured_idx
  on public.library_items (user_id, captured_at desc);

create index library_items_user_favourite_idx
  on public.library_items (user_id, is_favourite)
  where is_favourite;

alter table public.profiles enable row level security;
alter table public.library_items enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "library_items_select_own"
  on public.library_items for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "library_items_insert_own"
  on public.library_items for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "library_items_update_own"
  on public.library_items for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "library_items_delete_own"
  on public.library_items for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.library_items to authenticated;

create function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger library_items_set_updated_at
before update on public.library_items
for each row execute function public.set_updated_at();

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
