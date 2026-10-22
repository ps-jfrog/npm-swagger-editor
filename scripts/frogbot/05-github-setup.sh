#!/usr/bin/env bash
# GitHub side of the lab: environment, secret, variables, workflow permissions.
# Docs: https://docs.jfrog.com/security/docs/github
# Usage: FROGBOT_TOKEN=<jfrog access token> ./05-github-setup.sh      (run `gh auth login` first)
set -euo pipefail; cd "$(dirname "$0")"; source ./00-env.sh
: "${FROGBOT_TOKEN:?export FROGBOT_TOKEN=<JFrog access token with Xray Admin + Catalog Admin>}"
PLATFORM_URL=$(jf config show "$SERVER_ID" | awk -F'\t+' '/JFrog Platform URL/{print $2}' | sed 's:/*$::')

gh api -X PUT "repos/${GH_REPO}/environments/frogbot" >/dev/null && echo "environment 'frogbot' ready"
gh secret   set FROGBOT_ACCESS_TOKEN --env frogbot --repo "$GH_REPO" --body "$FROGBOT_TOKEN"
gh variable set FROGBOT_JF_URL   --repo "$GH_REPO" --body "$PLATFORM_URL"
gh variable set JF_PROJECT_KEY   --repo "$GH_REPO" --body "$PROJECT_KEY"
# optional knobs (uncomment to demo):
# gh variable set JF_GIT_WORKSPACE        --repo "$GH_REPO" --body "swagger-app"
# gh variable set JF_RELEASES_REPO        --repo "$GH_REPO" --body "generic-jfrog-frogbot-remote"
# gh variable set JF_SAST_DEFAULT_SCAN_MODE --repo "$GH_REPO" --body "directory"

# Workflow permissions: read+write, and let Actions create PRs (needed for fix PRs)
gh api -X PUT "repos/${GH_REPO}/actions/permissions/workflow" \
   -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true && echo "workflow permissions set"
echo "Optional: required reviewer on the 'frogbot' environment, and a required status check on main:"
echo "  Settings > Environments > frogbot > Required reviewers;  Settings > Branches > require 'scan-pull-request'"
