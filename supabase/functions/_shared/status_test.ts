import {
  canDeletePragueDay,
  closedDays,
  dailyStatus,
  isDiscordWebhook,
  isFailed,
  isPublicHttpUrl,
  notificationState,
} from "./status.ts";
import { sendDiscordNotification } from "./discord.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
const healthy = { status_code: 200, error: null };
const failed = { status_code: 500, error: null };
const webhook = "https://discord.com/api/webhooks/123/token_abc-123";

Deno.test("failure rules and daily status thresholds", () => {
  for (const status of [200, 301, 399]) {
    equal(isFailed({ status_code: status, error: null }), false);
  }
  for (const status of [null, 400, 503]) {
    equal(isFailed({ status_code: status, error: null }), true);
  }
  equal(isFailed({ status_code: 200, error: "timeout" }), true);
  equal(dailyStatus([]), "grey");
  equal(dailyStatus([healthy]), "green");
  equal(dailyStatus([healthy, failed]), "orange");
  equal(dailyStatus(Array(11).fill(failed)), "orange");
  equal(dailyStatus([...Array(12).fill(failed), healthy]), "red");
});

Deno.test("public URL guard rejects local and non-public literals", () => {
  for (
    const url of [
      "invalid",
      "file:///etc/passwd",
      "ftp://example.com",
      "http://localhost/",
      "http://localhost./",
      "http://a.localhost./",
      "http://host.local./",
      "http://host.internal",
      "http://intranet",
      "http://0.0.0.0",
      "http://0.1.2.3",
      "http://10.1.2.3",
      "http://127.0.0.1",
      "http://127.1",
      "http://2130706433",
      "http://169.254.169.254",
      "http://172.16.0.1",
      "http://172.31.255.255",
      "http://192.168.1.1",
      "http://100.64.0.1",
      "http://100.127.255.255",
      "http://224.0.0.1",
      "http://255.255.255.255",
      "http://198.18.0.1",
      "http://[::]",
      "http://[::1]",
      "http://[fc00::1]",
      "http://[fd00::1]",
      "http://[fe80::1]",
      "http://[febf::1]",
      "http://[ff02::1]",
      "http://[::ffff:127.0.0.1]",
      "http://[::ffff:8.8.8.8]",
      "http://[0:0:0:0:0:ffff:7f00:1]",
      "http://[::127.0.0.1]",
    ]
  ) equal([url, isPublicHttpUrl(url)], [url, false]);
  for (
    const url of [
      "https://example.com/",
      "http://example.com./",
      "https://8.8.8.8",
      "http://172.15.255.255",
      "http://172.32.0.1",
      "http://100.128.0.1",
      "https://[2606:4700:4700::1111]",
      "https://[2001:4860:4860::8888]",
    ]
  ) equal([url, isPublicHttpUrl(url)], [url, true]);
});

Deno.test("Discord endpoint validation", () => {
  for (
    const host of [
      "discord.com",
      "discordapp.com",
      "ptb.discord.com",
      "canary.discord.com",
    ]
  ) {
    equal(isDiscordWebhook(webhook.replace("discord.com", host)), true);
  }
  for (
    const url of [
      "invalid",
      webhook.replace("https:", "http:"),
      webhook.replace("discord.com", "discord.com.evil.com"),
      "https://discord.com/api/webhooks/",
      "https://discord.com/api/webhooks/123",
      "https://discord.com/api/webhooks/123/token/extra",
      webhook.replace("https://", "https://user:pass@"),
      webhook.replace("discord.com", "discord.com:8443"),
    ]
  ) equal(isDiscordWebhook(url), false);
});

Deno.test("notifications only on transitions, including first failure", () => {
  equal(notificationState(null, healthy), null);
  equal(notificationState(null, failed), "down");
  equal(notificationState(healthy, healthy), null);
  equal(notificationState(healthy, failed), "down");
  equal(notificationState(failed, failed), null);
  equal(notificationState(failed, healthy), "up");
});

Deno.test("Prague closed days span the 23-hour and 25-hour DST days", () => {
  for (
    const [now, day, start, end, hours] of [
      [
        "2026-03-30T12:00:00Z",
        "2026-03-29",
        "2026-03-28T23:00:00.000Z",
        "2026-03-29T22:00:00.000Z",
        23,
      ],
      [
        "2026-10-26T12:00:00Z",
        "2026-10-25",
        "2026-10-24T22:00:00.000Z",
        "2026-10-25T23:00:00.000Z",
        25,
      ],
    ] as const
  ) {
    const days = closedDays("Europe/Prague", new Date(now));
    equal(days.length, 3);
    equal(days[2], {
      timezone: "Europe/Prague",
      day,
      startUtc: start,
      endUtc: end,
    });
    equal((Date.parse(end) - Date.parse(start)) / 3_600_000, hours);
    equal(days[0].endUtc, days[1].startUtc);
    equal(days[1].endUtc, days[2].startUtc);
  }
  const now = new Date("2027-01-01T23:30:00Z");
  equal(closedDays("UTC", now).map((d) => d.day), [
    "2026-12-29",
    "2026-12-30",
    "2026-12-31",
  ]);
  equal(closedDays("Europe/Prague", now).map((d) => d.day), [
    "2026-12-30",
    "2026-12-31",
    "2027-01-01",
  ]);
});

Deno.test("Prague logs are retained until overlapping UTC days close", () => {
  for (const instant of ["2026-03-29T22:30:00Z", "2026-10-25T23:30:00Z"]) {
    const now = new Date(instant);
    const day = closedDays("Europe/Prague", now)[2];
    equal(canDeletePragueDay(day, now), false);
    const next = new Date(now);
    next.setUTCDate(next.getUTCDate() + 1);
    next.setUTCHours(0, 0, 0, 0);
    equal(canDeletePragueDay(day, next), true);
    equal(
      canDeletePragueDay({ ...day, endUtc: next.toISOString() }, next),
      true,
    );
    equal(canDeletePragueDay({ ...day, timezone: "UTC" }, next), false);
  }
});

Deno.test("Discord retries with injected fetch and no network", async () => {
  async function run(responses: (number | Error)[], retryAfter?: string) {
    let now = Date.parse("2026-01-01T00:00:00Z");
    let attempts = 0;
    const delays: number[] = [];
    const errors: string[] = [];
    const delivered = await sendDiscordNotification(webhook, "test", {
      fetch: (() => {
        const result = responses[attempts++];
        if (result instanceof Error) return Promise.reject(result);
        return Promise.resolve(
          new Response(null, {
            status: result,
            headers: retryAfter ? { "Retry-After": retryAfter } : {},
          }),
        );
      }) as typeof fetch,
      now: () => now,
      sleep: (ms) => {
        delays.push(ms);
        now += ms;
        return Promise.resolve();
      },
      error: (message) => errors.push(message),
    });
    equal(errors.length, delivered ? 0 : 1);
    equal(errors.some((error) => error.includes(webhook)), false);
    return { delivered, attempts, delays };
  }
  equal(await run([204]), { delivered: true, attempts: 1, delays: [] });
  equal(await run([429, 503, 204], "2"), {
    delivered: true,
    attempts: 3,
    delays: [2000, 2000],
  });
  equal(await run([new Error(webhook), 502, 204]), {
    delivered: true,
    attempts: 3,
    delays: [500, 1000],
  });
  equal(await run([500, 500, 500]), {
    delivered: false,
    attempts: 3,
    delays: [500, 1000],
  });
  equal(await run([401, 204]), { delivered: false, attempts: 1, delays: [] });
  equal(await run([429], "11"), { delivered: false, attempts: 1, delays: [] });
  equal(await run([429, 204], "Thu, 01 Jan 2026 00:00:03 GMT"), {
    delivered: true,
    attempts: 2,
    delays: [3000],
  });
  equal(await run([429, 429, 204], "6"), {
    delivered: false,
    attempts: 2,
    delays: [6000],
  });
});
