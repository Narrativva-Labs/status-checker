-- Database schema for Status Checker (Supabase / PostgreSQL).
--
-- Run it once in the SQL editor of a new Supabase project. The Flutter app
-- uses the public anon key, so Row Level Security below is what keeps users'
-- data private. The edge functions use the service role key and bypass RLS.

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- Monitored URLs. Public pages (is_public = true) are shown to everyone.
create table if not exists public.pages (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references auth.users (id) on delete cascade,
  url         text not null,
  url_name    text,
  is_public   boolean not null default false,
  created_at  timestamptz not null default now()
);

-- One row per check. Logs of healthy days are deleted by update_daily_status.
create table if not exists public.pages_logs (
  id           bigserial primary key,
  page_id      uuid not null references public.pages (id) on delete cascade,
  checked_at   timestamptz not null default now(),
  status_code  integer,
  error        text
);

create index if not exists pages_logs_page_checked_idx
  on public.pages_logs (page_id, checked_at);

-- Daily summary per page and time zone: green / orange / red / grey.
create table if not exists public.page_daily_status (
  id        bigserial primary key,
  page_id   uuid not null references public.pages (id) on delete cascade,
  day       date not null,
  timezone  varchar not null default 'UTC',
  status    varchar not null,
  unique (page_id, day, timezone)
);

-- Per-user settings. is_admin (5-minute checks instead of 15) is set by hand
-- in the database and cannot be changed from the app (see grants below).
create table if not exists public.user_settings (
  user_id              uuid primary key references auth.users (id) on delete cascade,
  discord_webhook_url  text,
  is_admin             boolean not null default false
);

-- At most 10 pages per user (the app shows the same limit).
create or replace function public.enforce_page_limit()
returns trigger language plpgsql as $$
begin
  if new.user_id is null then
    return new;
  end if;
  -- Serialise inserts of one user, so parallel requests cannot pass the limit.
  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  if (
    select count(*) from public.pages where user_id = new.user_id
  ) >= 10 then
    raise exception 'Page limit reached (10 pages per user)';
  end if;
  return new;
end;
$$;

drop trigger if exists pages_limit on public.pages;
create trigger pages_limit
  before insert on public.pages
  for each row execute function public.enforce_page_limit();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.pages             enable row level security;
alter table public.pages_logs        enable row level security;
alter table public.page_daily_status enable row level security;
alter table public.user_settings     enable row level security;

-- pages: everyone sees public pages, users manage their own private pages.
create policy "Public and own pages are readable"
  on public.pages for select
  using (is_public or user_id = auth.uid());

create policy "Users add their own private pages"
  on public.pages for insert to authenticated
  with check (user_id = auth.uid() and is_public = false);

create policy "Users update their own pages"
  on public.pages for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Users delete their own pages"
  on public.pages for delete to authenticated
  using (user_id = auth.uid());

-- Only the URL and the name can be edited from the app (not is_public / owner).
revoke update on public.pages from anon, authenticated;
grant update (url, url_name) on public.pages to authenticated;

-- Logs and daily statuses: readable for pages the user can see; written only
-- by the edge functions (service role).
create policy "Logs of visible pages are readable"
  on public.pages_logs for select
  using (exists (
    select 1 from public.pages p
    where p.id = page_id and (p.is_public or p.user_id = auth.uid())
  ));

create policy "Daily statuses of visible pages are readable"
  on public.page_daily_status for select
  using (exists (
    select 1 from public.pages p
    where p.id = page_id and (p.is_public or p.user_id = auth.uid())
  ));

-- user_settings: each user reads and edits only their own row, and only the
-- webhook column (is_admin stays read-only for the app).
create policy "Users read their own settings"
  on public.user_settings for select to authenticated
  using (user_id = auth.uid());

create policy "Users create their own settings"
  on public.user_settings for insert to authenticated
  with check (user_id = auth.uid());

create policy "Users update their own settings"
  on public.user_settings for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke insert, update on public.user_settings from anon, authenticated;
grant insert (user_id, discord_webhook_url) on public.user_settings to authenticated;
grant update (user_id, discord_webhook_url) on public.user_settings to authenticated;

-- ---------------------------------------------------------------------------
-- Scheduling (pg_cron + pg_net)
-- ---------------------------------------------------------------------------
-- Replace <project-ref>, <anon-key> and <cron-secret> (the CRON_SECRET secret
-- of the edge functions) before running.
--
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- select cron.schedule('status-checker', '*/5 * * * *', $$
--   select net.http_post(
--     url := 'https://<project-ref>.supabase.co/functions/v1/status-checker?minute='
--            || extract(minute from now())::int,
--     headers := jsonb_build_object(
--       'Authorization', 'Bearer <anon-key>',
--       'x-cron-secret', '<cron-secret>'
--     ),
--     timeout_milliseconds := 30000
--   );
-- $$);
--
-- -- Must run after midnight UTC and before 22:00 UTC (see the function).
-- select cron.schedule('update-daily-status', '15 0 * * *', $$
--   select net.http_post(
--     url := 'https://<project-ref>.supabase.co/functions/v1/update_daily_status',
--     headers := jsonb_build_object(
--       'Authorization', 'Bearer <anon-key>',
--       'x-cron-secret', '<cron-secret>'
--     ),
--     timeout_milliseconds := 30000
--   );
-- $$);
--
-- -- Keep logs (failed checks of unhealthy days) for 30 days.
-- select cron.schedule('delete-old-logs', '0 3 * * *', $$
--   delete from public.pages_logs where checked_at < now() - interval '30 days';
-- $$);
