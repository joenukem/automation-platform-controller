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
