// Runs every 5 minutes (Supabase cron). Checks the monitored URLs, stores the
// results in `pages_logs` and notifies the page owner on Discord when a URL
// goes down or comes back up.
//
// Admin users' pages are checked every 5 minutes, everyone else's every 15.
import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.39.3";

import {
  CONTENT_MISMATCH,
  failureReason,
  isDiscordWebhook,
  isPublicHttpUrl,
  type LogState,
  notificationState,
} from "../_shared/status.ts";
import { matchesExpectedText, readBodyPrefix } from "../_shared/content.ts";
import { sendDiscordNotification } from "../_shared/discord.ts";

/** How many URLs are fetched in parallel. */
const BATCH_SIZE = 10;
/** A URL that does not answer within this time counts as down. */
const REQUEST_TIMEOUT_MS = 10_000;
/** Redirects are followed manually, so every hop passes the SSRF check. */
const MAX_REDIRECTS = 5;

type Page = {
  id: string;
  user_id: string | null;
  url: string;
  url_name: string | null;
  expect_text: string | null;
};
type Settings = {
  user_id: string;
  discord_webhook_url: string | null;
  is_admin: boolean | null;
};
type CheckLog = {
  page_id: string;
  checked_at: string;
  status_code: number | null;
  error: string | null;
};

/** Fetches the URL (following up to MAX_REDIRECTS redirects) and returns the final status. */
async function fetchStatus(
  startUrl: string,
  expected: string | null,
): Promise<LogState> {
  const signal = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
  let url = startUrl;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (!isPublicHttpUrl(url)) {
      throw new Error("URL is not a public http(s) address");
    }
    const resp = await fetch(url, {
      method: "GET",
      redirect: "manual",
      signal,
      headers: { "User-Agent": "NarrativvaStatusChecker/1.0" },
    });
    const location = resp.headers.get("location");
    if (resp.status < 300 || resp.status >= 400 || !location) {
      if (!expected) {
        await resp.body?.cancel();
        return { status_code: resp.status, error: null };
      }
      try {
        const text = await readBodyPrefix(resp.body);
        return {
          status_code: resp.status,
          error: matchesExpectedText(text, expected) ? null : CONTENT_MISMATCH,
        };
      } catch (e) {
        return {
          status_code: resp.status,
          error: e instanceof Error ? e.message : String(e),
        };
      }
    }
    await resp.body?.cancel();
    url = new URL(location, url).toString();
  }
  throw new Error("Too many redirects");
}

async function checkUrl(page: Page): Promise<CheckLog> {
  let status_code: number | null = null;
  let error: string | null = null;
  try {
    ({ status_code, error } = await fetchStatus(page.url, page.expect_text));
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  }
  return {
    page_id: page.id,
    checked_at: new Date().toISOString(),
    status_code,
    error,
  };
}

/** Latest stored check of a page (of any age), or null if there is none. */
async function previousCheck(
  supabase: SupabaseClient,
  pageId: string,
): Promise<LogState | null> {
  const { data, error } = await supabase
    .from("pages_logs")
    .select("status_code, error")
    .eq("page_id", pageId)
    .order("checked_at", { ascending: false })
    .limit(1);
  if (error) throw new Error("DB error: " + error.message);
  return data?.[0] ?? null;
}

serve(async (req) => {
  // Shared secret, so only the cron job can trigger the checks. Without it the
  // function is protected only by the Supabase JWT check (anon key).
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (!cronSecret) {
    console.warn(
      "CRON_SECRET is not set; set it to restrict who can run checks.",
    );
  }
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { searchParams } = new URL(req.url);
  const minuteParam = searchParams.get("minute");
  const minute = minuteParam !== null
    ? Number(minuteParam)
    : new Date().getUTCMinutes();

  const { data: pages, error: pagesError } = await supabase
    .from("pages")
    .select("id, user_id, url, url_name, expect_text");
  if (pagesError) {
    return new Response("DB error: " + pagesError.message, { status: 500 });
  }

  const userIds = [
    ...new Set((pages as Page[]).map((p) => p.user_id).filter(Boolean)),
  ];
  const { data: settingsRows, error: settingsError } = userIds.length
    ? await supabase.from("user_settings").select("*").in("user_id", userIds)
    : { data: [], error: null };
  if (settingsError) {
    return new Response("DB error: " + settingsError.message, { status: 500 });
  }

  const settingsByUser = new Map<string, Settings>();
  for (const s of (settingsRows ?? []) as Settings[]) {
    settingsByUser.set(s.user_id, s);
  }

  // Users without a settings row are regular users without notifications;
  // their pages are still checked.
  const duePages = (pages as Page[]).filter((page) => {
    const isAdmin =
      !!(page.user_id && settingsByUser.get(page.user_id)?.is_admin);
    return minute % (isAdmin ? 5 : 15) === 0;
  });

  const logs: CheckLog[] = [];
  for (let i = 0; i < duePages.length; i += BATCH_SIZE) {
    const batch = duePages.slice(i, i + BATCH_SIZE);
    logs.push(...(await Promise.all(batch.map(checkUrl))));
  }

  // Previous check of each page, to notify only when the state changes.
  const previousByPage = new Map<string, LogState | null>();
  if (logs.length) {
    try {
      const previous = await Promise.all(
        logs.map((l) => previousCheck(supabase, l.page_id)),
      );
      logs.forEach((l, i) => previousByPage.set(l.page_id, previous[i]));
    } catch (e) {
      return new Response(e instanceof Error ? e.message : String(e), {
        status: 500,
      });
    }

    const { error: insertError } = await supabase.from("pages_logs").insert(
      logs,
    );
    if (insertError) {
      return new Response("Failed to store logs: " + insertError.message, {
        status: 500,
      });
    }
  }

  // Discord notifications on state changes only (down / back up), instead of
  // one message per failed check. Awaited, because the runtime may stop the
  // function as soon as the response is returned.
  const pageById = new Map(duePages.map((p) => [p.id, p]));
  const notifications = logs.flatMap((log) => {
    const page = pageById.get(log.page_id)!;
    const webhook = page.user_id
      ? settingsByUser.get(page.user_id)?.discord_webhook_url
      : null;
    if (!webhook || !isDiscordWebhook(webhook)) return [];

    const previous = previousByPage.get(log.page_id);
    const state = notificationState(previous, log);
    if (!state) return [];

    const name = page.url_name ? `${page.url_name} (${page.url})` : page.url;
    const content = state === "down"
      ? `❗️URL DOWN: ${name} (status: ${log.status_code ?? log.error}${
        log.error === CONTENT_MISMATCH
          ? `, ${failureReason(log)!.toLowerCase()}`
          : ""
      })`
      : `✅ URL BACK UP: ${name} (status: ${log.status_code})`;
    return [sendDiscordNotification(webhook, content)];
  });
  await Promise.allSettled(notifications);

  return new Response(`OK: checked ${logs.length} of ${pages.length} pages`);
});
