-- SuperFit backend schema.
--
-- Paste this into the Supabase dashboard under SQL Editor and run it once.
-- Everything here is idempotent, so running it again after an app update is
-- safe.
--
-- Design note: one row per user holding a whole-account snapshot, rather than a
-- table per model. The app already has a tested Codable archive of every model
-- with a merge/replace restore, so this carries a payload that is known to
-- round-trip instead of introducing a second schema that could drift from the
-- SwiftData one.

create table if not exists public.backups (
    user_id     uuid        primary key references auth.users (id) on delete cascade,
    archive     jsonb       not null,
    updated_at  timestamptz not null default now(),
    app_version text
);

-- Row-level security is the whole security model here.
--
-- The app ships with the anon key, which is public by design and grants nothing
-- on its own. What stops one signed-in user reading another's logs is these
-- policies: every one of them is scoped to `auth.uid()`, the id baked into the
-- caller's JWT, which a client cannot forge.
--
-- Without this line the table would be readable by anyone holding the anon key,
-- which means anyone with a copy of the app.
alter table public.backups enable row level security;

drop policy if exists "own backup: read"   on public.backups;
drop policy if exists "own backup: insert" on public.backups;
drop policy if exists "own backup: update" on public.backups;
drop policy if exists "own backup: delete" on public.backups;

create policy "own backup: read"
    on public.backups for select
    using (auth.uid() = user_id);

-- `with check` on insert and update is what stops a user writing a row that
-- claims to belong to someone else.
create policy "own backup: insert"
    on public.backups for insert
    with check (auth.uid() = user_id);

create policy "own backup: update"
    on public.backups for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "own backup: delete"
    on public.backups for delete
    using (auth.uid() = user_id);

-- Keep updated_at honest even if a future client forgets to send it.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists backups_touch_updated_at on public.backups;
create trigger backups_touch_updated_at
    before update on public.backups
    for each row execute function public.touch_updated_at();
