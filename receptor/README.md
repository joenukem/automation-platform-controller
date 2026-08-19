# receptor (log-streaming sidecar)

The controller Deployment runs `receptor` as a sidecar next to `awx-task`. That
sidecar — not the controller — owns the Kubernetes log stream of every ephemeral
`automation-job-<id>-*` pod, and it is where platform defect **F30** actually
lives (see `lab-content/docs/AAP-PLATFORM-DEFECTS.md`).

Upstream: https://github.com/ansible/receptor at tag **v1.4.8** (the version
shipped in `ansible/awx-ee:24.6.1`, reported as `1.4.8+d7fe592`).

`patches/` holds our fixes as unified diffs against that tag, applied in filename
order by `build/build-receptor.sh`, which produces

    <registry>/automation-platform/receptor-ee:24.6.1-<suffix>

an image identical to `awx-ee:24.6.1` except for `/usr/bin/receptor`. It is used
ONLY as the `receptor` container of `awx-controller-task`; the execution
environment used by job pods is untouched.

## 0001 — keep streaming while the pod is still running

`kubeLoggingWithReconnect` gives a log stream five retries. Every retry is spent
on a benign reconnect: the API server closes an idle `follow` stream, and the
reconnect re-requests logs `SinceTime` — which has one-second granularity, so it
replays lines already emitted. Those replayed lines are filtered out, and only a
*newer* line resets the budget. A job that goes quiet for a second (any ansible
task that takes a moment) therefore burns all five retries in about a second, and
receptor closes the job's stdout underneath a **Running** pod. ansible-runner's
Processor reads the resulting zero-length line, treats it as fatal, and the
controller records a healthy job as `error` with rc=None:

    Unexpected empty line encountered during worker stream.
    Worker did not produce events or streaming was aborted, check execution node health.

The patch asks the pod before giving up: while it is Pending or Running there is
more output coming, so the retry budget is refilled and the stream reconnected.
A pod in a terminal phase falls through to the original happy path, so the loop
still terminates.
