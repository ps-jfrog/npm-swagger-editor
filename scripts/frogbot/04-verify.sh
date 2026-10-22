#!/usr/bin/env bash
# Verify the platform side the way Frogbot sees it.
set -uo pipefail; cd "$(dirname "$0")"; source ./00-env.sh
echo "== Xray version";                  api GET xray/api/v1/system/version; echo
echo "== Frogbot repo ${FROGBOT_REPO}";  http_code GET "artifactory/api/repositories/${FROGBOT_REPO}"; echo
echo "== xrayIndex flag (must be True)"; api GET "artifactory/api/repositories/${FROGBOT_REPO}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("xrayIndex"))'
echo "== Watch";                         api GET "xray/api/v2/watches/${WATCH_NAME}" | python3 -m json.tool | head -40
echo "== Watches Frogbot will find (same call Frogbot makes: git repo + project)"
for k in "${GIT_RESOURCE%.git}" "${GIT_RESOURCE}"; do
  echo "-- git_repository=$k"; api GET "xray/api/v1/xsc/watches/resource?git_repository=${k}&project=${PROJECT_KEY}"; echo
done
echo "== Git repo registered in Xray yet? (appears after the first Frogbot scan)"
api GET xray/api/v1/git/repositories | python3 -c "
import sys,json
r=[x for x in json.load(sys.stdin)['repositories'] if 'npm-swagger-editor' in x['url']]
print(json.dumps(r,indent=1) if r else 'NOT YET - run a Frogbot scan first')"
echo "== Config profile Frogbot will receive for ${GIT_CLONE_URL}"
api POST xray/api/v1/xsc/profile_repos "{\"repo_url\":\"${GIT_CLONE_URL}\"}" | python3 -m json.tool | head -40
