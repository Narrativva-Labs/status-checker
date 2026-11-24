import {
  matchesExpectedText,
  readBodyPrefix,
  RESPONSE_BYTE_LIMIT,
} from "./content.ts";

function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`Expected ${expected}, got ${actual}`);
  }
}
const encoder = new TextEncoder();
function stream(chunks: Uint8Array[]) {
  let cancelled = false;
  let reads = 0;
  return {
    body: new ReadableStream<Uint8Array>({
      pull(controller) {
        reads++;
        const chunk = chunks.shift();
        if (chunk) controller.enqueue(chunk);
        else controller.close();
      },
      cancel() {
        cancelled = true;
      },
    }, { highWaterMark: 0 }),
    cancelled: () => cancelled,
    reads: () => reads,
  };
}

Deno.test("exact substring matching preserves empty, whitespace and case semantics", () => {
  equal(matchesExpectedText("", null), true);
  equal(matchesExpectedText("", ""), true);
  equal(matchesExpectedText("", undefined), true);
  equal(
    matchesExpectedText(
      'prefix "rules_complete":true suffix',
      '"rules_complete":true',
    ),
    true,
  );
  equal(matchesExpectedText("OK", "ok"), false);
  equal(matchesExpectedText("ok", " ok"), false);
  equal(matchesExpectedText("", "ok"), false);
});

Deno.test("body prefix spans chunks and cancels without reading past the byte limit", async () => {
  const input = stream([
    encoder.encode("ab"),
    encoder.encode("cdef"),
    encoder.encode("ignored"),
  ]);
  const text = await readBodyPrefix(input.body, 5);
  equal(text, "abcde");
  equal(matchesExpectedText(text, "bcde"), true);
  equal(matchesExpectedText(text, "def"), false);
  equal(input.cancelled(), true);
  equal(input.reads(), 2);
});

Deno.test("default 64 KiB limit includes a match ending exactly at the limit", async () => {
  const input = stream([
    encoder.encode("x".repeat(RESPONSE_BYTE_LIMIT - 2) + "okbeyond"),
  ]);
  const text = await readBodyPrefix(input.body);
  equal(text.length, RESPONSE_BYTE_LIMIT);
  equal(matchesExpectedText(text, "ok"), true);
  equal(matchesExpectedText(text, "beyond"), false);
  equal(input.cancelled(), true);
});

Deno.test("UTF-8 characters split across chunks match at the byte limit", async () => {
  const bytes = encoder.encode("až😀");
  const input = stream([
    bytes.subarray(0, 2),
    bytes.subarray(2, 5),
    bytes.subarray(5),
  ]);
  equal(await readBodyPrefix(input.body, bytes.length), "až😀");
  const cut = stream([bytes]);
  equal(await readBodyPrefix(cut.body, bytes.length - 1), "až");
  equal(await readBodyPrefix(null), "");
  const short = stream([encoder.encode("ž")]);
  equal(await readBodyPrefix(short.body), "ž");
});

Deno.test("body read errors propagate and release the reader", async () => {
  const body = new ReadableStream<Uint8Array>({
    start(c) {
      c.error(new Error("timeout"));
    },
  });
  let message = "";
  try {
    await readBodyPrefix(body);
  } catch (e) {
    message = (e as Error).message;
  }
  equal(message, "timeout");
  equal(body.locked, false);
});
