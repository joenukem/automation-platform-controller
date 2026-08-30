# receptor (log-streaming sidecar)

The controller Deployment runs `receptor` as a sidecar next to `awx-task`. That
sidecar — not the controller — owns the Kubernetes log stream of every ephemeral
`automation-job-<id>-*` pod, and it is where platform defect **F30** actually
lives (see `lab-content/docs/AAP-PLATFORM-DEFECTS.md`).

Upstream: https://github.com/ansible/receptor at tag **v1.6.7**, the Receptor
version shipped with the AAP 2.7-6 product release.

`patches/` holds our fixes as unified diffs against that tag, applied in filename
order by `build/build-receptor.sh`, which produces

    <registry>/automation-platform/receptor-ee:1.6.7-<suffix>

an image identical to `awx-ee:24.6.1` except for `/usr/bin/receptor`. It is used
ONLY as the `receptor` container of `awx-controller-task`; the execution
environment used by job pods is untouched.

## 0001 — retain stdout results across work-unit recovery

Receptor 1.6.7 supersedes the earlier local Kubernetes log reconnect patch with
its upstream reconnect implementation and updated client limits. The remaining
control-side result reader fix treats a briefly missing stdout path as a
recoverable work-unit transition instead of aborting after three seconds. It
keeps the current descriptor until recovery recreates the path, then adopts the
replacement inode at the last delivered byte offset so events are not replayed.
