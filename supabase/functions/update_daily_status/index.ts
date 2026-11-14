// Runs once a day (Supabase cron, shortly after midnight UTC). Aggregates the
// check logs of the last three closed days into `page_daily_status` for the
// UTC and the Europe/Prague calendar day. Logs of a fully healthy Prague day
// are deleted afterwards to keep `pages_logs` small.
//
// The status rules are mirrored in `lib/utils/status_utils.dart`.
import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.39.3";
import {
  canDeletePragueDay,
  closedDays,
  dailyStatus,
  type Day,
  type LogState,
} from "../_shared/status.ts";

async function loadLogs(
  supabase: SupabaseClient,
  pageId: string,
  day: Day,
): Promise<LogState[]> {
  const { data, error } = await supabase
    .from("pages_logs")
    .select("status_code, error")
    .eq("page_id", pageId)
    .gte("checked_at", day.startUtc)
    .lt("checked_at", day.endUtc);
  if (error) throw new Error(`Failed to load logs: ${error.message}`);
  return data ?? [];
}

serve(async (req) => {
  // Shared secret, so only the cron job can trigger the aggregation.
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (!cronSecret) {
    console.warn(
      "CRON_SECRET is not set; set it to restrict who can run this.",
    );
  }
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = new Date();
  const days = [...closedDays("UTC", now), ...closedDays("Europe/Prague", now)];

  const { data: pages, error: pagesError } = await supabase.from("pages")
    .select("id");
  if (pagesError) {
    return new Response("Failed to load pages: " + pagesError.message, {
      status: 500,
    });
  }

  try {
    const deletions: { pageId: string; day: Day }[] = [];
    for (const page of pages ?? []) {
      for (const day of days) {
        const logs = await loadLogs(supabase, page.id, day);
        const status = dailyStatus(logs);

        // Without logs, never overwrite an existing record: on a re-run the
        // logs of a healthy day may already be deleted.
        const { error } = await supabase.from("page_daily_status").upsert(
          [{ page_id: page.id, day: day.day, timezone: day.timezone, status }],
          {
            onConflict: "page_id,day,timezone",
            ignoreDuplicates: logs.length === 0,
          },
        );
        if (error) {
          throw new Error(
            `Failed to upsert ${day.timezone} status: ${error.message}`,
          );
        }
        if (status === "green" && canDeletePragueDay(day, now)) {
          deletions.push({ pageId: page.id, day });
        }
      }
    }

    // All overlapping closed UTC days have been aggregated before any deletion.
    for (const { pageId, day } of deletions) {
      const { error } = await supabase
        .from("pages_logs")
        .delete()
        .eq("page_id", pageId)
        .gte("checked_at", day.startUtc)
        .lt("checked_at", day.endUtc);
      if (error) throw new Error(`Failed to delete logs: ${error.message}`);
    }
  } catch (e) {
    return new Response(e instanceof Error ? e.message : String(e), {
      status: 500,
    });
  }

  return new Response(
    "Daily statuses for the last three closed UTC and Prague days updated.",
  );
});
