#!/usr/bin/env bash
# Remove the lab objects from the platform (keeps the Frogbot repo unless REMOVE_REPO=1).
set -uo pipefail; cd "$(dirname "$0")"; source ./00-env.sh
api DELETE "xray/api/v2/watches/${WATCH_NAME}"; echo
for p in "$POL_SEC" "$POL_LIC" "$POL_OPR"; do api DELETE "xray/api/v2/policies/${p}"; echo; done
[[ "${REMOVE_REPO:-0}" == 1 ]] && api DELETE "artifactory/api/repositories/${FROGBOT_REPO}"
