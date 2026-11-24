/** Maximum decoded response prefix, measured in bytes. */
export const RESPONSE_BYTE_LIMIT = 64 * 1024;

/** Reads only the bounded UTF-8 prefix and cancels the remaining response. */
export async function readBodyPrefix(
  body: ReadableStream<Uint8Array> | null,
  limit = RESPONSE_BYTE_LIMIT,
): Promise<string> {
  if (!body) return "";
  const reader = body.getReader();
  const decoder = new TextDecoder("utf-8");
  let text = "";
  let remaining = limit;
  try {
    while (remaining > 0) {
      const { value, done } = await reader.read();
      if (done) break;
      const prefix = value.subarray(0, remaining);
      text += decoder.decode(prefix, { stream: true });
      remaining -= prefix.byteLength;
    }
    // Flush complete characters at EOF, but do not turn a character cut by the
    // byte limit into a replacement character that could falsely match.
    if (remaining > 0) text += decoder.decode();
    return text;
  } finally {
    try {
      await reader.cancel();
    } finally {
      reader.releaseLock();
    }
  }
}

/** Empty expectations preserve status-only checks; matching is case-sensitive. */
export function matchesExpectedText(
  text: string,
  expected?: string | null,
): boolean {
  return !expected || text.includes(expected);
}
