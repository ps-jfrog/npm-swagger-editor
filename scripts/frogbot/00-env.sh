#!/usr/bin/env bash
# Shared settings for the Frogbot v3 lab (sourced by the other scripts). Override via environment.
export SERVER_ID="${SERVER_ID:-psazuse}"                       # jf config server id
export PROJECT_KEY="${PROJECT_KEY:-npmapptrust}"               # JFrog Project holding app "swagger-app"
export GH_REPO="${GH_REPO:-ps-jfrog/npm-swagger-editor}"       # GitHub owner/repo
export GIT_RESOURCE="${GIT_RESOURCE:-github.com/${GH_REPO}.git}"  # name used by Xray git-repository watches
export GIT_CLONE_URL="https://${GIT_RESOURCE}"                 # HTTPS clone URL Frogbot sends to Xray
export FROGBOT_REPO="${FROGBOT_REPO:-${PROJECT_KEY}-frogbot}"  # <project-key>-frogbot when JF_PROJECT_KEY is used
export WATCH_NAME="${WATCH_NAME:-${PROJECT_KEY}-swagger-editor-frogbot}"
export POL_SEC="${POL_SEC:-${PROJECT_KEY}-frogbot-security}"
export POL_LIC="${POL_LIC:-${PROJECT_KEY}-frogbot-license}"
export POL_OPR="${POL_OPR:-${PROJECT_KEY}-frogbot-opsrisk}"

# api <METHOD> <path-under-platform-root> [json-body]   e.g. api GET xray/api/v2/watches
api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    jf rt curl -s -X "$method" "/../${path}" --server-id "$SERVER_ID" -H "Content-Type: application/json" -d "$body"
  else
    jf rt curl -s -X "$method" "/../${path}" --server-id "$SERVER_ID"
  fi
}
http_code() { jf rt curl -s -o /dev/null -w '%{http_code}' -X "$1" "/../$2" --server-id "$SERVER_ID"; }
