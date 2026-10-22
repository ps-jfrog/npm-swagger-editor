#!/usr/bin/env bash
# Full breakdown of the Watch's violations in Xray (pages through the API; the default page is only 500).
# Git-repo scans from Frogbot show up here once Xray has processed them (counts can keep rising for 1-2 min).
set -euo pipefail; cd "$(dirname "$0")"; source ./00-env.sh
python3 - "$SERVER_ID" "$WATCH_NAME" <<'PY'
import json, subprocess, sys, collections
server, watch = sys.argv[1:3]
c, kinds, tot, page = collections.Counter(), collections.Counter(), 0, 1
while True:
    body = json.dumps({"filters": {"watch_name": watch}, "pagination": {"limit": 500, "offset": page}})
    out = subprocess.run(["jf", "rt", "curl", "-s", "-X", "POST", "/../xray/api/v1/violations", "--server-id", server,
                          "-H", "Content-Type: application/json", "-d", body], capture_output=True, text=True).stdout
    if not out.strip(): print("empty response for page", page, file=sys.stderr); break
    d = json.loads(out); tot = d["total_violations"]
    if not d["violations"]: break
    for v in d["violations"]:
        c[(v["type"], v["severity"])] += 1
        if v["type"] == "Security":   # XRAY-* = CVE / malicious package, EXP-* = JAS exposures (secrets, IaC, SAST, ...)
            kinds[("exposure: " + v["description"][:60]) if v["issue_id"].startswith("EXP-") else "CVE / malicious package (XRAY-*)"] += 1
    page += 1
    if sum(c.values()) >= tot: break
print(f"watch={watch} total={tot} counted={sum(c.values())}")
for k, n in sorted(c.items()): print(f"  {k[0]:<17}{k[1]:<9}{n}")
print("Security violations by kind:")
for k, n in kinds.most_common(): print(f"  {n:>4}  {k}")
PY
