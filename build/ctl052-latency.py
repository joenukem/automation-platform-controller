#!/usr/bin/env python3
"""CTL-052 probe — launch a real job and measure event-delivery lag under load.
For each job_event, lag = (server 'Date' header at first sighting) - event.created.
Both are the controller's clock (skew-free). Reports the max lag across events of
N jobs launched back-to-back while the soak hammers the controller."""
import os, sys, time, json, base64, urllib.request, email.utils

B = os.environ["BASE"].rstrip("/") + "/api/v2"
AUTH = "Basic " + base64.b64encode(f'admin:{os.environ["PASS"]}'.encode()).decode()
JT = os.environ["JT"]
NJOBS = int(os.environ.get("NJOBS", "3"))


def call(method, path, body=None):
    r = urllib.request.Request(f"{B}/{path}", data=(json.dumps(body).encode() if body is not None else None), method=method)
    r.add_header("Authorization", AUTH)
    if body is not None:
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, timeout=30) as resp:
        server_now = email.utils.parsedate_to_datetime(resp.headers["Date"]).timestamp()
        return resp.status, json.loads(resp.read()), server_now


def iso(ts):
    import datetime
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()


max_lag = 0.0
total_events = 0
for j in range(NJOBS):
    _, d, _ = call("POST", f"job_templates/{JT}/launch/", {})
    job = d.get("id") or d.get("job")
    seen = set()
    # poll events fast until the job is done
    while True:
        st, jd, _ = call("GET", f"jobs/{job}/")
        status = jd.get("status")
        _, ev, server_now = call("GET", f"jobs/{job}/job_events/?page_size=200&order_by=created")
        for e in ev.get("results", []):
            if e["id"] in seen:
                continue
            seen.add(e["id"])
            if not e.get("created"):
                continue
            lag = server_now - iso(e["created"])
            total_events += 1
            if lag > max_lag:
                max_lag = lag
        if status in ("successful", "failed", "error", "canceled"):
            break
        time.sleep(0.4)
    print(f"job {job}: status={status} events={len(seen)} running_max_lag={max_lag:.2f}s", flush=True)

print(f"\nCTL-052: {NJOBS} jobs, {total_events} events, MAX delivery lag = {max_lag:.2f}s (threshold <=5s)")
print("VERDICT:", "PASS" if max_lag <= 5.0 else "FAIL")
sys.exit(0 if max_lag <= 5.0 else 1)
