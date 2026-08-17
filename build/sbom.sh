#!/usr/bin/env bash
# CTL-004 — SBOM + license manifest for a controller image, and a license-hygiene
# gate. Every release attaches these artifacts (see STEWARDSHIP.md CVE watch).
#
#   build/sbom.sh <tag>        # e.g. build/sbom.sh airgap-v8
#
# Emits under reports/sbom/:
#   controller-<tag>.spdx.json      full SPDX SBOM (syft)
#   controller-<tag>.syft.json      native syft SBOM
#   controller-<tag>.licenses.csv   per-package name,version,type,license,category
# and prints a PASS/FAIL license-hygiene summary.
#
# Gate: FAIL if any composed source (the forked packages) is non-Apache, or if a
# PYTHON package is strong/plain copyleft WITHOUT a known linking exception.
# Base-OS RPM copyleft (glibc, coreutils, rsyslog, alternatives, …) is mere
# aggregation in a container and is reported, not failed.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:?usage: build/sbom.sh <tag>}"
REG="${REG:-192.168.1.240:30500}"
IMG="$REG/automation-platform/controller:$TAG"
OUT="$here/reports/sbom"; mkdir -p "$OUT"
export SYFT_REGISTRY_INSECURE_SKIP_TLS_VERIFY=true SYFT_REGISTRY_INSECURE_USE_HTTP=true

echo "== syft cataloging $IMG"
syft "registry:$IMG" \
  -o "spdx-json=$OUT/controller-$TAG.spdx.json" \
  -o "syft-json=$OUT/controller-$TAG.syft.json" >/dev/null

python3 - "$OUT/controller-$TAG.syft.json" "$OUT/controller-$TAG.licenses.csv" <<'PY'
import json, re, sys, collections
syft, csvout = sys.argv[1], sys.argv[2]
d = json.load(open(syft))
# composed sources (our fork) must be Apache-2.0; awx sdist metadata is UNKNOWN
# to syft but the tree LICENSE.md is Apache — whitelisted here.
COMPOSED = {'awx','django-ansible-base','dispatcherd','awx-plugins-core',
            'awx-plugins-interfaces','ansible-runner','receptorctl'}
APACHE_OK_UNKNOWN = {'awx'}  # confirmed Apache-2.0 from source LICENSE.md
# python copyleft packages that ship an explicit linking/plugin exception:
PY_EXCEPTION = {'uwsgi'}     # GPLv2 WITH linking exception (runs non-GPL apps)

def cat(expr):
    e=(expr or '').upper()
    if not e or e=='UNKNOWN': return 'unknown'
    if 'AGPL' in e: return 'strong-copyleft'
    if (re.search(r'\bGPL-[0-9]',e) or re.search(r'GPLV[23]',e)) and 'LGPL' not in e and 'WITH ' not in e and 'EXCEPTION' not in e and 'CLASSPATH' not in e: return 'copyleft'
    if 'LGPL' in e or 'MPL' in e: return 'weak-copyleft'
    return 'permissive'

rows=[]
for a in d['artifacts']:
    lic=';'.join(sorted({(l.get('value') or l.get('spdxExpression') or '') for l in (a.get('licenses') or []) if (l.get('value') or l.get('spdxExpression'))})) or 'UNKNOWN'
    rows.append((a['name'],a['version'],a['type'],lic,cat(lic)))

with open(csvout,'w') as f:
    f.write("name,version,type,license,category\n")
    for n,v,t,l,c in sorted(rows): f.write(f'"{n}","{v}","{t}","{l}","{c}"\n')

fails=[]
# 1) composed sources Apache
for n,v,t,l,c in rows:
    if n in COMPOSED:
        if 'APACHE' in l.upper() or 'ASL 2.0' in l.upper(): continue
        if n in APACHE_OK_UNKNOWN and l=='UNKNOWN': continue
        fails.append(f"composed source {n} {v} not Apache: {l}")
# 2) python copyleft without exception
for n,v,t,l,c in rows:
    if t=='python' and c in ('copyleft','strong-copyleft') and n not in PY_EXCEPTION:
        # base-OS python bindings (dnf stack) are aggregation, flag as warn not fail
        if n in {'libcomps','libdnf','rpm','dnf'}: continue
        fails.append(f"python copyleft (no exception) {n} {v}: {l}")

byc=collections.Counter(c for *_,c in ((r[0],r[1],r[2],r[3],r[4]) for r in rows) for c in [r if False else _] ) if False else collections.Counter(r[4] for r in rows)
print(f"artifacts: {len(rows)}  by-category: {dict(byc)}")
print(f"composed sources: " + ", ".join(f"{n}={l}" for n,v,t,l,c in rows if n in COMPOSED))
if fails:
    print("LICENSE GATE: FAIL"); [print("  - "+x) for x in fails]; sys.exit(1)
print("LICENSE GATE: PASS — composed sources Apache-2.0; copyleft is base-OS "
      "aggregation or carries a linking exception (uwsgi).")
PY
echo "== artifacts in $OUT/controller-$TAG.{spdx.json,syft.json,licenses.csv}"
