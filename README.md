# Status Checker

[![CI](https://github.com/Narrativva-Labs/status-checker/actions/workflows/ci.yml/badge.svg)](https://github.com/Narrativva-Labs/status-checker/actions/workflows/ci.yml)

A Flutter web app 👀 that monitors the availability of websites and shows a
30-day status history for each of them. Data lives in Supabase, checks run in
Supabase Edge Functions and outages can be reported to a Discord channel.

**Live:** [status.narrativva.com](https://status.narrativva.com)

## Features

- Public status page with a 30-day history per site, no account needed.
- Passwordless login with a magic link (Supabase Auth).
- Add, edit and delete your own URLs (up to 10 per user).
- Discord alerts when a site goes down and when it is back up, with a
  one-time code that proves you own the webhook.
- Daily history in UTC or Prague time ⏰, light and dark mode 🌙.

## How it works

```
 pg_cron ──every 5 min──▶ status-checker ──GET──▶ monitored URLs
                               │  └────────────▶ Discord webhook (on state change)
                               ▼
                          pages_logs ──daily──▶ update_daily_status ──▶ page_daily_status
                               │                                              │
                               └──────────── Flutter web app ◀────────────────┘
```

1. **`supabase/functions/status-checker/index.ts`** runs every 5 minutes. Pages of
   admin users are checked every 5 minutes, all others every 15 minutes. A
   check fails on a network error, a timeout (10 s) or an HTTP status ≥ 400.
   Every result is stored in `pages_logs`, and the owner gets a Discord
   message when the state of a page changes.
2. **`supabase/functions/update_daily_status/index.ts`** runs once a day after
   midnight UTC. It turns yesterday's logs into one `page_daily_status` row per
   page for both UTC and Europe/Prague: **green** (no failed checks),
   **orange** (some), **red** (12 or more failed checks) or **grey** (no data).
   Logs of a fully healthy day are deleted to keep the table small.
3. **The Flutter app** shows the daily records, and computes today's status
   from the raw logs with the same rules (`lib/utils/status_utils.dart`).

## Project structure

| Path | Contents |
|---|---|
| `lib/` | Flutter app: pages, widgets, Supabase and Discord services |
| `lib/utils/status_utils.dart` | Time zone and status rules (unit tested) |
| `test/` | Unit tests |
| `supabase/schema.sql` | Tables, Row Level Security, page limit and cron jobs |
| `supabase/functions/` | Edge functions for the checks and the daily summary |
| `supabase/config.toml` | Supabase CLI settings for deploying the functions |
| `.github/workflows/` | CI (analyze, test, build) and edge function deploy |
| `web/` | `index.html` with SEO tags, static `about.html`, icons |
| `netlify_build.sh`, `netlify.toml` | Netlify build and redirects |

## Setup

### 1. Supabase

1. Create a Supabase project and run [`supabase/schema.sql`](supabase/schema.sql)
   in the SQL editor. It creates the tables with Row Level Security, so the
   public anon key used by the app can only read public pages and the
   signed-in user's own data.
2. Deploy the edge functions (or let GitHub Actions do it, see
   [Deployment](#3-deployment)) and set a secret that only the scheduler knows:
   ```sh
   supabase functions deploy --remote=<project-ref>
   supabase secrets set CRON_SECRET=<random string> --remote=<project-ref>
   ```
3. Schedule both functions with `pg_cron` — see the commented block at the end
   of `schema.sql`.
4. To make a user an admin (5-minute checks), set `is_admin = true` in
   `user_settings`. Public pages are marked with `is_public = true` in `pages`.

### 2. App

Requirements: Flutter 3.27 or newer (CI and Netlify use 3.47.9).

Create a `.env` file:

```
SUPABASE_URL=<your Supabase project URL>
SUPABASE_ANON_KEY=<anon key>
EMAIL_REDIRECT_URL=http://localhost:5000
```

Then run `make chrome`. It passes the variables to Flutter as `--dart-define`
values and opens the app on port 5000.

```sh
flutter analyze   # static analysis
flutter test      # unit tests
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

## License

[MIT](LICENSE)

---

Created as part of the [Narrativva Labs project](https://labs.narrativva.com).
