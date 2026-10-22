#!/usr/bin/env bash
# Create project-scoped Xray policies that exercise every Frogbot v3 reporting/gating path.
# Fail Build -> gates `scan-repository` (exit code 3). "Fail Pull Request" (gates `scan-pull-request`) is NOT
# settable via the public policy REST API (v1/v2 reject or drop it) - enable it in the UI (see end of script).
# Docs: https://docs.jfrog.com/security/docs/how-to-commit-scan-and-pr-scan
set -euo pipefail; cd "$(dirname "$0")"; source ./00-env.sh

upsert_policy() {   # upsert_policy <name> <json>
  local name="$1" body="$2" code
  code=$(http_code GET "xray/api/v2/policies/${name}")
  if [[ "$code" == "200" ]]; then
    echo "updating policy ${name}";  api PUT  "xray/api/v2/policies/${name}?projectKey=${PROJECT_KEY}" "$body"
  else
    echo "creating policy ${name}";  api POST "xray/api/v2/policies?projectKey=${PROJECT_KEY}" "$body"
  fi; echo
}

# 1. Security: CVEs (gate), malicious pkgs (gate), secrets (gate), SAST (report only => green check + comment)
upsert_policy "$POL_SEC" "$(cat <<J
{"name":"${POL_SEC}","type":"security","description":"Frogbot v3 demo - security",
 "rules":[
  {"name":"cve-high-critical","priority":1,
   "criteria":{"min_severity":"High"},
   "actions":{"fail_build":true,"block_download":{"active":false,"unscanned":false}}},
  {"name":"malicious-packages","priority":2,
   "criteria":{"malicious_package":true},
   "actions":{"fail_build":true}},
  {"name":"secrets-exposed","priority":3,
   "criteria":{"exposures":{"min_severity":"High","secrets":true,"applications":false,"iac":false,"services":false}},
   "actions":{"fail_build":true}},
  {"name":"sast-report-only","priority":4,
   "criteria":{"sast":{"min_severity":"Medium"}},
   "actions":{}}
 ]}
J
)"

# 2. License: ban copyleft (gates both)
upsert_policy "$POL_LIC" "$(cat <<J
{"name":"${POL_LIC}","type":"license","description":"Frogbot v3 demo - license",
 "rules":[{"name":"ban-copyleft","priority":1,
   "criteria":{"banned_licenses":["GPL-2.0","GPL-2.0-only","GPL-2.0-or-later","GPL-3.0","GPL-3.0-only","GPL-3.0-or-later","AGPL-3.0","AGPL-3.0-only","AGPL-3.0-or-later"],
               "allow_unknown":true,"multi_license_permissive":true},
   "actions":{"fail_build":true}}]}
J
)"

# 3. Operational risk: gates only. NOTE (FAQ Q9): Frogbot v3 does not render op-risk in the PR comment.
upsert_policy "$POL_OPR" "$(cat <<J
{"name":"${POL_OPR}","type":"operational_risk","description":"Frogbot v3 demo - operational risk (no PR comment; log only)",
 "rules":[{"name":"high-op-risk","priority":1,
   "criteria":{"op_risk_min_risk":"High"},
   "actions":{"fail_build":false}}]}
J
)"

cat <<M

MANUAL STEP (UI only): enable "Fail Pull Request" on the rules that must gate PRs.
  Administration > Xray > Policies (Project: ${PROJECT_KEY}) > ${POL_SEC}, ${POL_LIC}
  edit rules cve-high-critical, malicious-packages, secrets-exposed, ban-copyleft
  > Actions > tick "Fail Pull Request" > Save.   Leave rule 'sast-report-only' unticked on purpose.
M
