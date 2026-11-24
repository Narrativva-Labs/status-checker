# Status Checker

[![CI](https://github.com/Narrativva-Labs/status-checker/actions/workflows/ci.yml/badge.svg)](https://github.com/Narrativva-Labs/status-checker/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

The open-source app behind **[Narrativva Status](https://status.narrativva.com)**:
uptime monitoring for websites with a 30-day status history and Discord alerts,
built with Flutter web, Supabase (Postgres, Auth, Edge Functions) and Netlify.

## Features

- Public status page with the latest check and a 30-day history per site,
  no account needed. The page refreshes itself every 5 minutes.
- Passwordless login with a magic link (Supabase Auth).
- Add, edit and delete your own URLs (up to 10 per user, enforced in the
  database).
- Optional `expect_text` per page (up to 200 characters): an exact, case-sensitive
  substring required in the first 64 KiB of the final UTF-8 response. Empty or
  null keeps status-only checks. The configured value is not displayed publicly.
- Discord alerts when a site goes down and when it is back up. Before a webhook
  is saved, a one-time code is sent to the channel to confirm the URL works and
  that you can read the channel. Adding, editing and deleting a page also posts
  a short message there.
- History in UTC or Prague time ⏰, light and dark mode 🌙.

## How it works

```
 pg_cron ──every 5 min──▶ status-checker ──GET──▶ monitored URLs
                               │  └────────────▶ Discord webhook (on state change)
                               ▼
                          pages_logs ──daily──▶ update_daily_status ──▶ page_daily_status
                               │                                              │
                               └──────────── Flutter web app ◀────────────────┘
```

1. **`status-checker`** runs every 5 minutes. Pages of admin users are checked
   every 5 minutes, all others every 15 minutes. A check fails on a network
   error, a timeout (10 s, including reading the body), an HTTP status ≥ 400,
   or a missing `expect_text` substring when configured; redirects are followed
   hop by hop, and every hop must be a public address. Each result is stored in
   `pages_logs`. When a page changes state, its owner gets a Discord message
   (with up to three delivery attempts that respect `Retry-After`).
2. **`update_daily_status`** runs once a day. It turns the logs of the last
   three closed days into one `page_daily_status` row per page and day, for
   both UTC and Europe/Prague: **green** (no failed checks), **orange**
   (some), **red** (12 or more) or **grey** (no data). Re-running it is safe,
   and a run missed within the last three days is caught up. Logs of a fully healthy day are
   deleted once both time zones have aggregated it.
3. **The Flutter app** shows the daily records, today's status computed from
   the raw logs with the same rules, and the result of the latest check.

The status rules exist twice, in Dart for the app and in TypeScript for the
functions, and both are covered by unit tests.

## Project structure

| Path | Contents |
|---|---|
| `lib/` | Flutter app: pages, widgets, models, Supabase and Discord services |
| `lib/utils/status_utils.dart` | Time zone and status rules of the app |
| `test/` | Unit tests of the rules and widget tests of the status bar |
| `supabase/functions/` | Edge functions; shared rules and their tests in `_shared/` |
| `supabase/schema.sql` | Tables, Row Level Security, page limit and cron jobs |
| `supabase/config.toml` | Supabase CLI settings for deploying the functions |
| `.github/workflows/` | CI (analyze, tests, build) and the edge function deploy |
| `web/` | `index.html` with SEO tags, static `about.html`, icons |
| `netlify_build.sh`, `netlify.toml` | Netlify build and redirects |

## Setup

### 1. Supabase

1. Create a Supabase project and run [`supabase/schema.sql`](supabase/schema.sql)
   in the SQL editor. It creates the tables with Row Level Security, so the
   public anon key used by the app can only read public pages and the
   signed-in user's own data.
2. Deploy the edge functions, or let GitHub Actions do it (see
   [Deployment](#3-deployment)):
   ```sh
   supabase functions deploy --remote=<project-ref>
   ```
3. Schedule both functions with `pg_cron`, see the commented block at the end
   of `schema.sql`.
4. Optional: restrict who can run the functions. Set a secret and send the
   same value in the `x-cron-secret` header from **both** cron jobs; once the
   secret is set, requests without it are rejected.
   ```sh
   supabase secrets set CRON_SECRET=<random string> --remote=<project-ref>
   ```
5. To make a user an admin (5-minute checks), set `is_admin = true` in
   `user_settings`. Public pages are marked with `is_public = true` in `pages`.

### Upgrading an existing database

Before deploying the updated app and functions, run this SQL in the Supabase
SQL editor. It adds the optional field and owner update permission without
changing existing RLS policies. Content mismatches are stored as
`content mismatch` in `pages_logs.error` with the actual HTTP status.

```sql
alter table public.pages add column if not exists expect_text text null;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.pages'::regclass
      and conname = 'pages_expect_text_length'
  ) then
    alter table public.pages add constraint pages_expect_text_length
      check (char_length(expect_text) <= 200);
  end if;
end;
$$;

grant update (url, url_name, expect_text) on public.pages to authenticated;
```

### 2. App

Requirements: Flutter 3.27 or newer (CI and Netlify use 3.47.9) and, for the
function tests, Deno 2.

Create a `.env` file:

```
SUPABASE_URL=<your Supabase project URL>
SUPABASE_ANON_KEY=<anon key>
EMAIL_REDIRECT_URL=http://localhost:5000
```

Then run `make chrome`. It passes the variables to Flutter as `--dart-define`
values and opens the app on port 5000.

```sh
flutter analyze                  # static analysis
flutter test                     # Dart unit and widget tests
deno test supabase/functions     # edge function tests
```

### 3. Deployment

**Web app (Netlify).** `netlify_build.sh` installs the pinned Flutter SDK and
runs `flutter build web` with `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`EMAIL_REDIRECT_URL` taken from the Netlify environment. The output goes to
`build/web`; `netlify.toml` serves `/about` and routes everything else to the
Flutter app.

**Edge functions (GitHub Actions).** Every push to `main` that changes
`supabase/functions/` deploys the functions with
[`deploy-functions.yml`](.github/workflows/deploy-functions.yml). It needs:

| Name | Type | Value |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | repository secret | a [Supabase access token](https://supabase.com/dashboard/account/tokens) |
| `SUPABASE_PROJECT_ID` | repository variable | the project reference (`<ref>` in `<ref>.supabase.co`) |

Without them the workflow is skipped. It can also be started by hand from the
Actions tab.

## Known limitations

- The SSRF guard checks host names and IP literals, not DNS records, so a
  public domain that resolves to a private address is not blocked; the
  hosting runtime is relied on not to reach private networks.
- A Discord alert that still fails after three attempts is logged, not
  queued for later.
- The status is sampled every 5 or 15 minutes, so a shorter outage between
  two checks is not seen.

## License

[MIT](LICENSE)

---

Created as part of the [Narrativva Labs project](https://github.com/Narrativva-Labs).
