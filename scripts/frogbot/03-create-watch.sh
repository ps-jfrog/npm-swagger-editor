#!/usr/bin/env bash
# Create (or update) a project-scoped Xray Watch that watches the GitHub repo and assigns the demo policies.
# Frogbot never selects a Watch by name: Xray applies every active Watch attached to the repo URL / project.
set -euo pipefail; cd "$(dirname "$0")"; source ./00-env.sh

BODY=$(cat <<J
{"general_data":{"name":"${WATCH_NAME}","description":"Frogbot v3 demo: git repo ${GIT_RESOURCE}","active":true},
 "project_resources":{"resources":[{"type":"gitRepository","name":"${GIT_RESOURCE}","bin_mgr_id":"default",
   "filters":[{"type":"ant-patterns","value":{"ExcludePatterns":[],"IncludePatterns":["**"]}}]}]},
 "assigned_policies":[
   {"name":"${POL_SEC}","type":"security"},
   {"name":"${POL_LIC}","type":"license"},
   {"name":"${POL_OPR}","type":"operational_risk"}]}
J
)
if [[ "$(http_code GET "xray/api/v2/watches/${WATCH_NAME}")" == "200" ]]; then
  echo "updating watch ${WATCH_NAME}";  api PUT  "xray/api/v2/watches/${WATCH_NAME}?projectKey=${PROJECT_KEY}" "$BODY"
else
  echo "creating watch ${WATCH_NAME}";  api POST "xray/api/v2/watches?projectKey=${PROJECT_KEY}" "$BODY"
fi; echo
