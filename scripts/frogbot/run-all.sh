#!/usr/bin/env bash
# Platform-side setup in one go (steps 01-04). GitHub side: 05-github-setup.sh
set -euo pipefail; cd "$(dirname "$0")"
./01-precreate-frogbot-repo.sh; ./02-create-policies.sh; ./03-create-watch.sh; ./04-verify.sh
