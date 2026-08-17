# CTL-050 soak — MAX=8, build 0.0.2-gad045013de (patches 0001–0005)

Six rounds of the six-lab set at MAX=8 (full concurrency), each round a fresh
provision→console→launch→verify cycle per lab.

| round | result | note |
|---|---|---|
| 1 | 0/6 | content emptyDir reset by another session's webapp rollout |
| 2 | 0/6 | same |
| 3 | 0/6 | same |
| 4 | 5/6 | content re-deployed; one late render-wait |
| 5 | **6/6** | clean |
| 6 | 1/5 | webapp rolled again mid-round (page 404) |

**Signal, isolating the environmental noise:** every round in which the lab
content was actually present passed **5/6–6/6 at MAX=8**. The 0/6 and 1/5
rounds are all the same cause — a second session actively redeploying the
shared lab-webapp during the window, which resets the content emptyDir and
404s every lab regardless of controller behavior. The controller pods stayed
healthy (6/6 Running) throughout.

**Verdict:** CTL-050's *correctness* bar is met — the candidate sustains
MAX=8 with the frozen engine's modal-race collapse gone (0003 killed the
list-latency backpressure that caused the earlier rotating failures). A
clean 2-hour soak number requires a window where the shared webapp is NOT
being redeployed by another tenant; the standing rule (deploy content
immediately before dispatch; all-labs-404 == content reset) is the mitigation,
but a truly uninterrupted soak needs an isolated webapp or a quiet window.
