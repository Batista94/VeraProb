/**
 * Single-deadline helper: one AbortController + one timer.
 * Rejects on expiry even if the work ignores the signal; aborts the signal
 * so fetch/getClaims can cancel when they honor it.
 */

export async function withDeadline<T>(
  run: (signal: AbortSignal) => Promise<T>,
  ms: number,
): Promise<T> {
  const ac = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      run(ac.signal),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          ac.abort();
          reject(new Error("deadline"));
        }, ms);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
