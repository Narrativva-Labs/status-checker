// Runs once a day (Supabase cron, shortly after midnight UTC). Aggregates the
// check logs of the previous day into `page_daily_status`, separately for the
// UTC and the Europe/Prague calendar day. Logs of a fully healthy Prague day
// are deleted afterwards to keep `pages_logs` small.
//
// The status rules are mirrored in `lib/utils/status_utils.dart`.
import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { DateTime } from "https://esm.sh/luxon@3.4.4";

/** Number of failed checks in one day from which the day is shown as red. */
const RED_DAY_FAILED_CHECKS = 12;

type Log = { status_code: number | null; error: string | null };
type Day = { timezone: string; day: string; startUtc: string; endUtc: string };

function isFailed(log: Log): boolean {
  return !!log.error || log.status_code === null || log.status_code >= 400;
}

function dailyStatus(logs: Log[]): string {
  if (logs.length === 0) return "grey";
  const failed = logs.filter(isFailed).length;
  if (failed >= RED_DAY_FAILED_CHECKS) return "red";
  if (failed > 0) return "orange";
  return "green";
}

/** Yesterday in [zone] as a half-open UTC range [startUtc, endUtc). */
function yesterday(zone: string): Day {
  const start = DateTime.now().setZone(zone).startOf("day").minus({ days: 1 });
  const end = start.plus({ days: 1 });
  return {
    timezone: zone,
    day: start.toISODate()!,
    startUtc: start.toUTC().toISO()!,
    endUtc: end.toUTC().toISO()!,
  };
}

async function loadLogs(supabase: SupabaseClient, pageId: string, day: Day): Promise<Log[]> {
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
  if (!cronSecret) console.warn("CRON_SECRET is not set; set it to restrict who can run this.");
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const utcDay = yesterday("UTC");
  const pragueDay = yesterday("Europe/Prague");

  const { data: pages, error: pagesError } = await supabase.from("pages").select("id");
  if (pagesError) {
    return new Response("Failed to load pages: " + pagesError.message, { status: 500 });
  }

  try {
    for (const page of pages ?? []) {
      const statuses: Record<string, string> = {};

      for (const day of [utcDay, pragueDay]) {
        const logs = await loadLogs(supabase, page.id, day);
        const status = dailyStatus(logs);
        statuses[day.timezone] = status;

        // Without logs, never overwrite an existing record: on a re-run the
        // logs of a healthy day may already be deleted.
        const { error } = await supabase.from("page_daily_status").upsert(
          [{ page_id: page.id, day: day.day, timezone: day.timezone, status }],
          { onConflict: "page_id,day,timezone", ignoreDuplicates: logs.length === 0 },
        );
        if (error) throw new Error(`Failed to upsert ${day.timezone} status: ${error.message}`);
      }

      // Prague days tile the timeline without gaps, and the UTC days covering
      // yesterday's Prague day are aggregated by now, so a healthy Prague day
      // can be deleted without losing data needed for any later aggregation.
      if (statuses[pragueDay.timezone] === "green") {
        const { error } = await supabase
          .from("pages_logs")
          .delete()
          .eq("page_id", page.id)
          .gte("checked_at", pragueDay.startUtc)
          .lt("checked_at", pragueDay.endUtc);
        if (error) throw new Error(`Failed to delete logs: ${error.message}`);
      }
    }
  } catch (e) {
    return new Response(e instanceof Error ? e.message : String(e), { status: 500 });
  }

  return new Response(
    `Daily statuses for ${utcDay.day} (UTC) and ${pragueDay.day} (Europe/Prague) updated.`,
  );
});
