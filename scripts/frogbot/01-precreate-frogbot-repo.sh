#!/usr/bin/env bash
# Pre-create the Frogbot repository so the CI identity does not need admin rights.
# Doc: https://docs.jfrog.com/security/docs/frogbot#pre-create-the-frogbot-repository
set -euo pipefail; cd "$(dirname "$0")"; source ./00-env.sh

if [[ "$(http_code GET "artifactory/api/repositories/${FROGBOT_REPO}")" == "200" ]]; then
  echo "repo ${FROGBOT_REPO} already exists"
else
  echo "creating generic local repo ${FROGBOT_REPO} in project ${PROJECT_KEY}"
  api PUT "artifactory/api/repositories/${FROGBOT_REPO}?" \
    "{\"key\":\"${FROGBOT_REPO}\",\"projectKey\":\"${PROJECT_KEY}\",\"rclass\":\"local\",\"packageType\":\"generic\",\"description\":\"Frogbot v3 scan artifacts\"}"
  echo
fi

echo "adding ${FROGBOT_REPO} to Xray indexed resources (skips if already indexed)"
if api GET "xray/api/v1/binMgr/default/repos" | grep -q "\"name\":\"${FROGBOT_REPO}\""; then
  echo "already indexed"
else
  api POST "xray/api/v1/binMgr/default/repos" \
    "{\"indexed_repos\":[{\"name\":\"${FROGBOT_REPO}\",\"type\":\"local\",\"pkg_type\":\"Generic\"}]}"
  echo
fi
echo "NOTE: grant the Frogbot identity (token user) 'Deploy' on ${FROGBOT_REPO}:"
echo "      Administration > User Management > Permissions (or the project's Roles)."
