/** Adopt a complete batch, or release every successful sibling on cancellation/failure. */
export async function settleOwnedResources   (pending              , release                       , cancelled               )                      {
  const results = await Promise.allSettled(pending);
  const resources = results.flatMap(result => result.status === "fulfilled" ? [result.value] : []);
  const failure = results.find(result => result.status === "rejected");
  if (cancelled() || failure) {
    resources.forEach(release);
    if (!cancelled() && failure?.status === "rejected") throw failure.reason;
    return null;
  }
  return resources;
}
