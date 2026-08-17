# CTL-050 first concurrency probe — 2026-08-16

Six known-green DO467 labs dispatched **fully concurrently** (MAX=7) against
the candidate (`0.0.2-g08940bb3f5`, patches 0001+0002) through the whole
platform.

Result: **4 PASS / 2 FAIL** — vs the frozen engine's hard ceiling of ~3
concurrent sessions, where identical labs failed at *whatever console modal
lost the race* (LAB-PLATFORM-REFERENCE §3c).

The two failures are a different, narrower class: late-stage list-render
waits (a `run-verify` job row not yet in the Jobs list; a project-sync
`Failed` status not yet rendered) about 4 minutes after the four passes
completed. Both labs pass serially. This is the D-4 event/list latency
budget (CTL-052), not scheduler collapse — the dispatcherd line degrades by
*slowing down* where the frozen engine degraded by *corrupting interactions*.

Next steps for the gate: event-pipeline latency work (D-4) and re-probe;
CTL-050 proper needs the full in-scope set at MAX≥8 for 2 hours.

## Second probe (same six labs, MAX=7, content freshly deployed)

**5 PASS / 1 FAIL.** The one failure is another UI render-timing wait (the
inventory detail Access tab), same narrow class as before; the two labs that
failed in probe 1 both passed. Combined picture across probes: every lab in
the set passes concurrently in at least one probe, failures rotate randomly
through late-stage render waits, and nothing resembles the frozen engine's
deterministic modal-race collapse at 3 concurrent.

Supporting measurement: the controller's own 20-row jobs list costs
**~424ms p50 at IDLE** (DRF serialization weight) while the session gateway
adds only ~60ms — the D-4 latency budget work should start at the
controller's list serialization, not the proxy tier.

Operational note that invalidated one probe entirely: a webapp rollout by
another session reset the content emptyDir mid-run and all six labs 404'd
for hours — CI runs MUST deploy content immediately before dispatch, and a
sudden all-labs-404 pattern means content reset, never lab failure.

## Patch 0003 result

`/api/v2/jobs/` (20-row page, warm, in-process): **33 -> 13 SQL queries**,
~66ms steady. The 20x per-row `execution_environment` lookup was the last
N+1 — fixed in both `JobAccess.select_related` and
`UnifiedJobAccess.prefetch_related`. Deployed as `0.0.2-gb549851aae`;
tripwire exact (1232/13/116); ex467-06 green serially after the (recurring,
unrelated) content-reset was re-deployed.

