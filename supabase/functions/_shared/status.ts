// Pure rules shared by the edge functions (unit tested in status_test.ts).
// The same rules are implemented for the app in lib/utils/status_utils.dart.

export type LogState = { status_code: number | null; error: string | null };
export type Day = {
  timezone: string;
  day: string;
  startUtc: string;
  endUtc: string;
};

/** Number of failed checks in one day from which the day is shown as red. */
export const RED_DAY_FAILED_CHECKS = 12;

/** A check fails on a request error, a missing status code or HTTP >= 400. */
export function isFailed(log: LogState): boolean {
  return !!log.error || log.status_code === null || log.status_code >= 400;
}

export function dailyStatus(
  logs: LogState[],
): "grey" | "green" | "orange" | "red" {
  if (!logs.length) return "grey";
  const failed = logs.filter(isFailed).length;
  return failed >= RED_DAY_FAILED_CHECKS ? "red" : failed > 0 ? "orange" : "green";
}

/** Discord notification for a check: only when the page changes state. */
export function notificationState(
  previous: LogState | null | undefined,
  current: LogState,
): "down" | "up" | null {
  const wasDown = previous ? isFailed(previous) : false;
  const isDown = isFailed(current);
  return wasDown === isDown ? null : isDown ? "down" : "up";
}

/** Host-only SSRF guard; DNS resolution is deliberately left to the runtime. */
export function isPublicHttpUrl(raw: string): boolean {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return false;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return false;
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(
    /\.+$/,
    "",
  );
  if (
    host === "localhost" || host.endsWith(".localhost") ||
    host.endsWith(".local") ||
    host.endsWith(".internal") || (!host.includes(".") && !host.includes(":"))
  ) return false;
  const v4 = host.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (v4) {
    const [a, b] = [Number(v4[1]), Number(v4[2])];
    return !(a === 0 || a === 10 || a === 127 || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 100 && b >= 64 && b <= 127) || a >= 224 ||
      (a === 192 && b === 0) || (a === 198 && (b === 18 || b === 19)));
  }
  // Only global unicast IPv6. This also excludes mapped/compatible IPv4,
  // loopback, unspecified, unique-local, link-local and multicast addresses.
  if (host.includes(":")) return /^[23][0-9a-f]{3}:/.test(host);
  return true;
}

/** Only real Discord webhook endpoints receive notifications. */
export function isDiscordWebhook(raw: string): boolean {
  try {
    const url = new URL(raw);
    return url.protocol === "https:" && !url.username && !url.password &&
      !url.port &&
      /^((ptb|canary)\.)?discord(app)?\.com$/.test(url.hostname) &&
      /^\/api\/webhooks\/\d+\/[A-Za-z0-9_-]+\/?$/.test(url.pathname);
  } catch {
    return false;
  }
}

function calendarParts(date: Date, timezone: string): number[] {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date);
  return ["year", "month", "day", "hour", "minute", "second"].map((key) =>
    Number(parts.find((part) => part.type === key)!.value)
  );
}

function midnightUtc(day: Date, timezone: string): string {
  const target = day.getTime();
  let instant = target;
  for (let i = 0; i < 3; i++) {
    const [y, m, d, h, min, s] = calendarParts(new Date(instant), timezone);
    instant += target - Date.UTC(y, m - 1, d, h, min, s);
  }
  return new Date(instant).toISOString();
}

/** Last three closed calendar days, oldest first, as half-open UTC ranges. */
export function closedDays(timezone: string, now: Date): Day[] {
  const [y, m, d] = calendarParts(now, timezone);
  return [3, 2, 1].map((offset) => {
    const start = new Date(Date.UTC(y, m - 1, d - offset));
    const end = new Date(Date.UTC(y, m - 1, d - offset + 1));
    return {
      timezone,
      day: start.toISOString().slice(0, 10),
      startUtc: midnightUtc(start, timezone),
      endUtc: midnightUtc(end, timezone),
    };
  });
}

/**
 * Logs of a healthy Prague day can be deleted once every UTC day it overlaps
 * has closed (and so has been aggregated as well).
 */
export function canDeletePragueDay(day: Day, now: Date): boolean {
  const utcStart = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  );
  return day.timezone === "Europe/Prague" && Date.parse(day.endUtc) <= utcStart;
}
