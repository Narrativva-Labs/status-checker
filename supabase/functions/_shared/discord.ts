import { isDiscordWebhook } from "./status.ts";

type Dependencies = {
  fetch: typeof fetch;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  error: (message: string) => void;
};

/** At most three attempts within a shared ten-second deadline. */
export async function sendDiscordNotification(
  webhook: string,
  content: string,
  dependencies: Partial<Dependencies> = {},
): Promise<boolean> {
  const deps: Dependencies = {
    fetch,
    now: Date.now,
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    error: (message) => console.error(message),
    ...dependencies,
  };
  if (!isDiscordWebhook(webhook)) {
    deps.error("Discord notification failed: invalid endpoint");
    return false;
  }
  const deadline = deps.now() + 10_000;
  for (let attempt = 0; attempt < 3; attempt++) {
    const remaining = deadline - deps.now();
    if (remaining <= 0) break;
    let delay = 500 * 2 ** attempt;
    try {
      const response = await deps.fetch(webhook, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content }),
        signal: AbortSignal.timeout(Math.ceil(remaining)),
        redirect: "error",
      });
      await response.body?.cancel();
      if (response.ok) return true;
      if (response.status !== 429 && response.status < 500) break;
      const retryAfter = response.headers.get("Retry-After");
      if (retryAfter !== null) {
        const seconds = Number(retryAfter);
        const retryMs = Number.isFinite(seconds)
          ? seconds * 1000
          : Date.parse(retryAfter) - deps.now();
        if (Number.isFinite(retryMs)) delay = Math.max(0, retryMs);
      }
    } catch {
      // Network errors are retryable; never log exception text containing URLs.
    }
    if (attempt === 2 || delay >= deadline - deps.now()) break;
    await deps.sleep(delay);
  }
  deps.error("Discord notification failed after delivery attempts");
  return false;
}
