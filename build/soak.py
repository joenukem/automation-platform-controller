#!/usr/bin/env python3
"""CTL-050 soak/load harness — drive N concurrent "lab sessions" against a
controller and measure the requirement's thresholds:
  - no 5xx from list endpoints
  - provisioning p95 <= 60s
  - list endpoints p95 <= 2s   (meaningful only with ~10k historical jobs seeded)

Each worker loops: provision (org+inventory+project+job_template) -> hammer the
list endpoints -> tear down (async org deletion). Usage:

  BASE=http://127.0.0.1:19052 USER=admin PASS=... WORKERS=10 DURATION=7200 \
    python3 build/soak.py
"""
import os, time, threading, statistics, urllib.request, urllib.error, base64, json, sys

BASE = os.environ["BASE"].rstrip("/")
USER = os.environ.get("USER_", os.environ.get("USER", "admin"))
PASS = os.environ["PASS"]
WORKERS = int(os.environ.get("WORKERS", "10"))
DURATION = int(os.environ.get("DURATION", "300"))
AUTH = "Basic " + base64.b64encode(f"{USER}:{PASS}".encode()).decode()

LIST_EPS = ["jobs/?page_size=20&order_by=-finished", "unified_jobs/?page_size=20",
            "inventories/?page_size=20", "job_templates/?page_size=20"]

lock = threading.Lock()
prov_times, list_times = [], []
counts = {"ops": 0, "5xx_list": 0, "err": 0, "prov": 0, "teardown": 0}
stop_at = None


def req(method, path, body=None):
    url = f"{BASE}/api/v2/{path}"
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", AUTH)
    if data:
        r.add_header("Content-Type", "application/json")
    t0 = time.time()
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return resp.status, time.time() - t0, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, time.time() - t0, e.read()
    except Exception:
        return 0, time.time() - t0, b""


def worker(wid):
    n = 0
    while time.time() < stop_at:
        n += 1
        tag = f"soak-w{wid}-{n}"
        # provision: org -> inventory -> project -> job_template
        t0 = time.time()
        st, _, b = req("POST", "organizations/", {"name": tag})
        if st not in (200, 201):
            with lock: counts["err"] += 1
            continue
        org = json.loads(b)["id"]
        ok = True
        inv_id = None
        for path, payload in [("inventories/", {"name": tag, "organization": org}),
                              ("projects/", {"name": tag, "organization": org,
                                             "scm_type": "", "local_path": "_"})]:
            st, _, b = req("POST", path, payload)
            ok = ok and st in (200, 201)
            if path.startswith("inv") and st in (200, 201):
                inv_id = json.loads(b)["id"]
        st, _, b = req("POST", "job_templates/",
                       {"name": tag, "inventory": inv_id, "project": None,
                        "playbook": "p.yml", "ask_inventory_on_launch": True})
        prov = time.time() - t0
        with lock:
            counts["prov"] += 1
            prov_times.append(prov)
        # hammer list endpoints
        for ep in LIST_EPS:
            st, dt, _ = req("GET", ep)
            with lock:
                counts["ops"] += 1
                list_times.append(dt)
                if st >= 500:
                    counts["5xx_list"] += 1
        # teardown (async org deletion state machine)
        st, _, _ = req("DELETE", f"organizations/{org}/")
        with lock:
            counts["teardown"] += 1


def pct(xs, p):
    if not xs:
        return 0.0
    xs = sorted(xs)
    k = int(round((p / 100.0) * (len(xs) - 1)))
    return xs[k]


def main():
    global stop_at
    stop_at = time.time() + DURATION
    threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(WORKERS)]
    for t in threads:
        t.start()
    # progress ticker
    while time.time() < stop_at:
        time.sleep(30)
        with lock:
            lp95 = pct(list_times, 95); pp95 = pct(prov_times, 95)
            print(f"[{int(stop_at - time.time())}s left] ops={counts['ops']} prov={counts['prov']} "
                  f"5xx_list={counts['5xx_list']} err={counts['err']} "
                  f"list_p95={lp95:.3f}s prov_p95={pp95:.1f}s", flush=True)
    for t in threads:
        t.join(timeout=65)
    with lock:
        lp95 = pct(list_times, 95); lp99 = pct(list_times, 99)
        pp95 = pct(prov_times, 95)
        print("\n=== SOAK RESULT ===")
        print(f"workers={WORKERS} duration={DURATION}s")
        print(f"provisions={counts['prov']} teardowns={counts['teardown']} list_ops={counts['ops']} errors={counts['err']}")
        print(f"list p95={lp95:.3f}s p99={lp99:.3f}s  (threshold <=2s)")
        print(f"provisioning p95={pp95:.1f}s  (threshold <=60s)")
        print(f"5xx from list endpoints={counts['5xx_list']}  (threshold 0)")
        ok = counts["5xx_list"] == 0 and lp95 <= 2.0 and pp95 <= 60.0
        print("VERDICT:", "PASS" if ok else "FAIL")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
