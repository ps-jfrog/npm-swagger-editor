#!/usr/bin/env bash
# Pre-create the Frogbot repository so the CI identity does not need admin rights.
# Doc: https://docs.jfrog.com/security/docs/frogbot#pre-create-the-frogbot-repository
set -euo pipefail; cd "$(dirname "$0")"; source ./00-env.sh

if [[ "$(http_code GET "artifactory/api/repositories/${FROGBOT_REPO}")" == "200" ]]; then
  echo "repo ${FROGBOT_REPO} already exists"
else
  echo "creating generic local repo ${FROGBOT_REPO} in project ${PROJECT_KEY}"
  api PUT "artifactory/api/repositories/${FROGBOT_REPO}?" \
    "{\"key\":\"${FROGBOT_REPO}\",\"projectKey\":\"${PROJECT_KEY}\",\"rclass\":\"local\",\"packageType\":\"generic\",\"xrayIndex\":true,\"description\":\"Frogbot v3 scan artifacts\"}"
  echo
fi

echo "ensuring ${FROGBOT_REPO} is indexed by Xray (xrayIndex=true)"
if [[ "$(api GET "artifactory/api/repositories/${FROGBOT_REPO}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("xrayIndex"))')" == "True" ]]; then
  echo "already indexed"
else
  api POST "artifactory/api/repositories/${FROGBOT_REPO}" '{"xrayIndex":true}'; echo
fi
# Without this Frogbot's SBOM upload is never scanned: "artifact at path <repo>/... does not exist in Artifactory"
echo "NOTE: grant the Frogbot identity (token user) 'Deploy' on ${FROGBOT_REPO}:"
echo "      Administration > User Management > Permissions (or the project's Roles)."
