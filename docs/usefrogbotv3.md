# Lab: Demo Frogbot v3 on `ps-jfrog/npm-swagger-editor` (app `swagger-app`, project `npmapptrust`, instance `psazuse`)

What this lab shows: `frogbot scan-pull-request` (diff scan + PR decoration + gating), `frogbot scan-repository`
(commit scan + auto-fix PRs + SBOM), centralized Config Profiles, workspaces, the new JAS scanning
capabilities, and where to read the results (GitHub and JFrog Platform).

| Item | Value |
|---|---|
| Git repo | `https://github.com/ps-jfrog/npm-swagger-editor.git` |
| JFrog | `https://psazuse.jfrog.io` (`jf config show psazuse`), Xray **3.156.18** (needs ≥ 3.143.6; workspaces need ≥ 3.150) |
| Project | `npmapptrust` (display name `npm-apptrust`) |
| Workflow | [`.github/workflows/frogbot-scan.yml`](../.github/workflows/frogbot-scan.yml) |
| Platform scripts | [`scripts/frogbot/`](../scripts/frogbot) (`run-all.sh` = steps 01–04) |
| Frogbot version | v3 (`jfrog/frogbot@v3`, source reviewed at tag `v3.8.1`) |

---

## 0. TL;DR – what you can demo

| Capability (JFrog doc) | Demoable here? | How / where in this lab |
|---|---|---|
| PR scan + commit scan ([how-to](https://docs.jfrog.com/security/docs/how-to-commit-scan-and-pr-scan)) | ✅ | §5, §6 |
| GitHub integration ([GitHub](https://docs.jfrog.com/security/docs/github)): PR comments, `pull_request_target`, `frogbot` environment, OIDC or token, Code Scanning, Dependency Graph SBOM | ✅ (Code Scanning needs GitHub Advanced Security or a public repo) | §4, §7 |
| Centralized configuration / Config Profiles | ✅ (UI; no public API to bind a profile to a repo) | §2, §3.4 |
| Pre-create the Frogbot repository | ✅ scripted | §3.1 |
| New scanning capabilities: Snippet Detection, Dynamic Token Validation, Custom Secrets, SAST rule exclusions | ✅ (JFrog Advanced Security entitlement confirmed on `psazuse`) | §8 |
| Workspaces ([doc](https://docs.jfrog.com/security/docs/manage-frogbot-workspaces)) | ✅ (Xray 3.156 ≥ 3.150) | §9 |
| Advanced management & configuration, except Auto-PR ([doc](https://docs.jfrog.com/security/docs/advanced-management-and-configuration)) | ✅ almost all; batch-configure and folder/server inheritance are only meaningful with several repos (the instance already has 45 indexed git repos, so show it on those but **don't edit them**) | §10 |
| Consuming results ([doc](https://docs.jfrog.com/security/docs/how-to-consume-results)) | ✅ | §11 |
| Auto-PR | Out of scope here (it is on by default in the System Default profile, see §2.3) | – |

---

## 1. Audit: what already existed on `psazuse` for this repo

Checked with the `jf` CLI before changing anything:

| Needed for the demo | State found | Action |
|---|---|---|
| Frogbot repo for project scans (`npmapptrust-frogbot`) | ❌ missing (only the global `frogbot` repo existed) | created by `01-precreate-frogbot-repo.sh` |
| Project-scoped policies | ❌ none (`npmapptrust` had no policies or watches) | created by `02-create-policies.sh` |
| Watch on `github.com/ps-jfrog/npm-swagger-editor.git` | ❌ none (other repos such as `spring-petclinic` had Watches) | created by `03-create-watch.sh` |
| Git repo registered in Xray | ❌ not listed in `GET /xray/api/v1/git/repositories` (45 other repos are) | appears after the first Frogbot scan, §2.2 |
| Config Profile for the repo | ❌ none → Frogbot receives the **System_Default_Profile** | optional custom profile, §3.4 |
| **Fail Pull Request** policy action | ❌ cannot be set through the public Xray REST API (v1/v2 reject or silently drop `fail_pull_request`; only `fail_build` persists) | **manual UI step**, §3.3 |

### What the scripts created

| Object | Name | Contents |
|---|---|---|
| Generic local repo, indexed in Xray | `npmapptrust-frogbot` | Frogbot scan artifacts (`<project-key>-frogbot` naming rule) |
| Security policy | `npmapptrust-frogbot-security` | `cve-high-critical` (≥ High, **fail**), `malicious-packages` (**fail**), `secrets-exposed` (≥ High, **fail**), `sast-report-only` (≥ Medium, no fail → comment but green) |
| License policy | `npmapptrust-frogbot-license` | `ban-copyleft`: GPL-2.0/3.0, AGPL-3.0 families (**fail**) |
| Operational-risk policy | `npmapptrust-frogbot-opsrisk` | `high-op-risk` (≥ High, no fail; shows the FAQ Q9 gap: never rendered in the PR comment) |
| Watch | `npmapptrust-swagger-editor-frogbot` | resource type `gitRepository` = `github.com/ps-jfrog/npm-swagger-editor.git`, project `npmapptrust`, all three policies |

Together these cover every violation family Frogbot v3 reports: **CVE (SCA), malicious package, license,
operational risk, secrets, SAST** (IaC/services exposures can be added to `secrets-exposed`).

---

## 2. How the repo "shows up" in psazuse and how centralized configuration reaches it

Reference: [Centralized Configuration via JFrog Platform](https://docs.jfrog.com/security/docs/frogbot#centralized-configuration-via-jfrog-platform),
[Advanced management](https://docs.jfrog.com/security/docs/advanced-management-and-configuration).

### 2.1 There is nothing to register by hand

Frogbot v3 has no per-repo config file. On every run it:

1. Asks the Git provider API for the repo's **HTTPS clone URL** (not a CI variable).
2. `POST /xray/api/v1/xsc/profile_repos {"repo_url": "<clone url>", "workspace_name": "<JF_GIT_WORKSPACE>"}` → returns the **Config Profile** (scanners on/off, include/exclude paths, auto-fix, PR-comment options, fail-on-scanner-error, …).
3. Asks Xray for the active **Watches** for that URL + `JF_PROJECT_KEY` (`GET /xray/api/v1/xsc/watches/resource?git_repository=…&project=…`).
4. Scans, uploads results to Xray.

If the platform has nothing specific for the URL, step 2 returns the built-in **`System_Default_Profile`**
(all scanners on, Auto-Fix PRs on, secrets shown in PR comments, fail-upon-scanner-error off). That is exactly what
`npm-swagger-editor` gets today; run `scripts/frogbot/04-verify.sh` to see it.

### 2.2 First appearance in the platform

The repo becomes visible **when the first Frogbot scan uploads results** (the first v3 scan also switches
the repo to v3 permanently). After the first run it appears in:

- **Administration → Xray Settings → Indexed Resources → Git Repositories** (tree: Git server `github.com` → folder/owner `ps-jfrog` → repo `npm-swagger-editor`), status **Default/Inherited**
- **Xray → Scans List → Git Repositories** (Commits / Pull Requests tabs)
- `GET /xray/api/v1/git/repositories` (what `04-verify.sh` polls)

The **Watch does not need the repo to exist first** (the Watch lookup already returns our Watch; verified by
`04-verify.sh`), so create the Watch/policies *before* the first scan and the first scan is already gated.

### 2.3 Making the configuration "Custom"

Open the repo row → **Configure**. Saving there creates a repo-level profile (status **Custom**; named
`profile-github.com-<n>-…`). Inheritance: Git server → folder (`ps-jfrog`) → repository; children inherit
until overridden. Local/CI settings beat platform settings: **environment variables > Frogbot Configuration
in the platform**. No public REST API binds a profile to a repo, so this part is UI-only (as is **Fail Pull Request**).

---

## 3. Setup (do once)

Prereqs: `jf` configured as `psazuse` (admin), `gh` CLI, a Frogbot token with **Xray Admin + Catalog Admin** (Frogbot ≥ 3.7.0 and Xray ≥ 3.155.0; Platform Admin before that).

### 3.1 Platform objects (scripted, idempotent)

```bash
cd scripts/frogbot
./run-all.sh          # 01 repo → 02 policies → 03 watch → 04 verify
```

| Script | Does | Doc |
|---|---|---|
| `00-env.sh` | shared settings: `SERVER_ID=psazuse`, `PROJECT_KEY=npmapptrust`, repo/watch/policy names | – |
| `01-precreate-frogbot-repo.sh` | creates the generic repo `npmapptrust-frogbot` in the project and ensures it is indexed | [Pre-create the Frogbot repository](https://docs.jfrog.com/security/docs/frogbot#pre-create-the-frogbot-repository) |
| `02-create-policies.sh` | creates the 3 policies | [Policies](https://docs.jfrog.com/security/docs/policies-in-jfrog-xray) |
| `03-create-watch.sh` | creates the git-repository Watch | – |
| `04-verify.sh` | prints Xray version, repo, Watches **as Frogbot will see them**, git-repo registration, and the Config Profile returned for the URL | – |
| `05-github-setup.sh` | GitHub `frogbot` environment, secret, variables, workflow permissions | [GitHub](https://docs.jfrog.com/security/docs/github) |
| `99-teardown.sh` | deletes Watch + policies (`REMOVE_REPO=1` also the repo) | – |

Then give the Frogbot identity **Deploy** on `npmapptrust-frogbot` (Administration → User Management → Permissions, or the project's Roles). Not needed if the token is a Platform Admin token.

### 3.2 GitHub side

```bash
gh auth login
FROGBOT_TOKEN=<token> scripts/frogbot/05-github-setup.sh
```

Sets environment `frogbot`, secret `FROGBOT_ACCESS_TOKEN`, variables `FROGBOT_JF_URL=https://psazuse.jfrog.io`, `JF_PROJECT_KEY=npmapptrust`, Workflow permissions *Read and write* + *Allow GitHub Actions to create and approve pull requests*.
Add **Required reviewers** on the `frogbot` environment (the PR job exposes secrets via `pull_request_target`; the doc requires the environment, mandatory for public repos and Maven/Gradle projects).
*OIDC alternative:* create an OpenID Connect integration + identity mapping (claim `repository` = `ps-jfrog/npm-swagger-editor`, long enough token expiry), `gh variable set JF_OIDC_PROVIDER_NAME --body <name>`, and drop the secret.
*If your org blocks `GITHUB_TOKEN` PR creation:* use a PAT (classic `repo`, or fine-grained Contents + Pull requests = RW) as `JF_GIT_TOKEN`.

### 3.3 Manual UI step: **Fail Pull Request** (required for a red PR check)

Administration → Xray → **Policies** (select project `npmapptrust`): open `npmapptrust-frogbot-security` and
`npmapptrust-frogbot-license`; for rules `cve-high-critical`, `malicious-packages`, `secrets-exposed`, `ban-copyleft`
tick **Actions → Fail Pull Request**, save. Leave `sast-report-only` and `high-op-risk` unticked on purpose, they
show the "visible in comment, check stays green" contrast. (`Fail Build` is already set by the script and gates `scan-repository`.)

### 3.4 Optional: a custom Config Profile

After the first scan: Indexed Resources → Git Repositories → `npm-swagger-editor` → **Configure** and set the options listed in §8–§10, **Apply**. Re-run `04-verify.sh`; `profile_name` changes from `System_Default_Profile` to a repo profile.

---

## 4. The workflow (`frogbot-scan.yml`)

| Event | Job | Command run by the action |
|---|---|---|
| `pull_request_target` (opened/synchronize/reopened) | `scan-pull-request` | `frogbot scan-pull-request` |
| push to `main`, `workflow_dispatch` (nightly cron is commented out) | `scan-repository` | `frogbot scan-repository` |

Env/inputs that matter (all optional ones are repo **variables**, so no YAML edit between demos):

| Setting | Purpose |
|---|---|
| repo variable `FROGBOT_JF_URL` (→ `JF_URL`), secret `FROGBOT_ACCESS_TOKEN` (or `oidc-provider-name`) | connection. UI: repo → Settings → Secrets and variables → Actions → **Variables** tab → *Repository variables* → **New repository variable** |
| `JF_GIT_TOKEN` = `GITHUB_TOKEN` | PR comments, fix PRs |
| `JF_PROJECT_KEY` (default `npmapptrust`) | project Watches/policies + project-scoped `npmapptrust-frogbot` repo |
| `JF_GIT_WORKSPACE` (var, or the manual-run input `workspace`) | workspace to scan, §9 |
| `JF_UPLOAD_PR_SECURITY_RESULTS_TO_VCS` (default `true` in the workflow) | PR findings → GitHub Code Scanning |
| `JF_UPLOAD_SBOM_TO_VCS` (default `true`) | SBOM → GitHub Dependency Graph (repo scan) |
| `JF_RELEASES_REPO` | air-gapped/proxy download of Frogbot + scanners (repo name only) |
| `JF_SAST_DEFAULT_SCAN_MODE` | `codebase` / `directory` / `file` |
| `JFROG_CLI_LOG_LEVEL=DEBUG` | prints Watch matching and fail-rule lines used in the narration |

Not v3 variables: `JF_FAIL`, `JF_WATCHES`, `JF_USE_CONFIG_PROFILE`, `JF_PROJECT`.

---

## 5. Demo A – Pull request scan

```bash
git checkout -b demo/vulnerable-lodash
npm install lodash@4.17.15 --save --package-lock-only    # CVEs: prototype pollution / command injection
git commit -am "chore(deps): add lodash 4.17.15 (demo)" && git push -u github-ps-jfrog demo/vulnerable-lodash
gh pr create --repo ps-jfrog/npm-swagger-editor --base main --title "demo: vulnerable lodash" --body "Frogbot v3 PR scan"
```

Optional additions to the same PR: a file with a fake `ghp_…` token (secrets), a package with a GPL-3.0 license (license violation), a snippet copied from an OSS project (§8).

Show:
1. **Log (DEBUG)**: `one or more violations incurred by 'npmapptrust-swagger-editor-frogbot' watch, which has the 'fail_pull_request' rule action...` and `Security violation with 'fail-pull-request' rule is found`. If you see `No watches were found ... Calculating vulnerabilities` the Watch/URL did not match.
2. **PR comment**: summary table per scanner (`✅ Done`/`ℹ️ Not Scanned`), new violations with severity, impacted/direct dependency, fixed versions, Watch/policy names; inline comments for JAS findings.
3. **Check**: `scan-pull-request` is red. Make it required: Settings → Branches → rule on `main` → *Require status checks* → `scan-pull-request`.
4. **Diff scan**: remove lodash in a new commit → green, nothing reported; issues already on `main` never fail the PR.
5. **Policy-driven gating**: untick *Fail Pull Request* on `cve-high-critical`, re-run → comment still there, check green. No YAML change.
6. **Code Scanning**: Security → Code scanning shows the PR results (§7).

---

## 6. Demo B – Commit (repository) scan

```bash
gh workflow run "Frogbot Scan" --repo ps-jfrog/npm-swagger-editor --ref main
gh run watch --repo ps-jfrog/npm-swagger-editor
```

1. Scans the latest commit of `main` (full scan), applies the Watch; **Fail Build** violations exit with code 3.
2. Existing vulnerabilities are reported and uploaded; Auto-PR (on by default) opens fix PRs, out of scope for this lab but visible if vulnerable direct deps exist.
3. SBOM lands in GitHub's Dependency graph (§7) and the scan in **Xray → Scans List → Git Repositories → Commits**.
4. First run only: the repo appears in the Git Repositories tree (§2.2).

---

## 7. GitHub capabilities and how to demo them

Reference: <https://docs.jfrog.com/security/docs/github>, <https://docs.jfrog.com/security/docs/how-to-consume-results>.

| Capability | Demo |
|---|---|
| `pull_request_target` PR scan with `frogbot` environment | Fork or approve flow: add Required reviewers on the environment; open a PR; the job waits for approval |
| PR summary + inline review comments | §5 |
| Pass/fail check + required status | §5 step 3 |
| **GitHub Code Scanning** alerts | PR job sets `JF_UPLOAD_PR_SECURITY_RESULTS_TO_VCS=true` (v3.4+; needs `security-events: write`, GHAS or public repo). Security → Code scanning → filter by PR |
| **Dependency graph / SBOM** | `scan-repository` uploads the SBOM (`JF_UPLOAD_SBOM_TO_VCS`, needs `contents: write`). Insights → Dependency graph |
| Fix PRs by `GITHUB_TOKEN` | Needs *Allow GitHub Actions to create and approve pull requests*; PRs created with `GITHUB_TOKEN` do not trigger other workflows (use a PAT if you need that) |
| OIDC (no stored token) | §3.2; if scans outlive the token, raise the identity mapping's token expiry |

---

## 8. New scanning capabilities ([doc](https://docs.jfrog.com/security/docs/frogbot#new-scanning-capabilities))

Enable on the repo's Config Profile (Configure → **Scans Configuration**). All need the JFrog Advanced Security entitlement (confirmed on `psazuse`).

| Capability | Switch | Demo |
|---|---|---|
| **Snippet Detection** (SCA, repo level) | SCA → Snippet Detection | Paste a recognizable block (a function copied from an OSS library) into a source file in a PR; the finding names the upstream project/license even though no dependency is declared |
| **Dynamic Token Validation** (Secrets) | Secrets → Validate secrets | Commit a (revoked/test) token; the finding is tagged active / inactive / unknown. Use only tokens you own |
| **Custom Secrets** | Secrets → Custom secrets (+ define the regex patterns in the platform's Advanced Security settings) | Define pattern `swg-[0-9a-f]{16}`, commit `swg-0123456789abcdef`; it is reported as a secret. (Menu path varies by release, check the Advanced Security section of the platform) |
| **SAST rule exclusions** | SAST → Exclude rules | Trigger a SAST finding, add its rule id to the exclusions, re-run, the finding disappears |

Remember `show_secrets_as_pr_comment` ("show findings in PR decoration") for secrets to be visible in the PR; it is on in the System Default profile.

---

## 9. Workspaces ([doc](https://docs.jfrog.com/security/docs/manage-frogbot-workspaces))

A workspace is a named scan unit of one repo with its own profile; every repo has `default`. Needs Xray ≥ 3.150 ✅. In this lab, one repo, two scan units:

1. Indexed Resources → Git Repositories → `npm-swagger-editor` → **Manage Workspaces → + Add Workspace** → `editor-src` and `build-tooling`.
2. **Configure**, pick workspace `editor-src` → *Global Include Paths* `src/**`; pick `build-tooling` → include `vite/**`, `test/**`, `.github/**`, `Dockerfile*`; **Apply**. (Optionally different scanners per workspace, e.g. SAST only in `editor-src`.)
3. Run per workspace:
   ```bash
   gh workflow run "Frogbot Scan" --ref main -f workspace=editor-src
   gh workflow run "Frogbot Scan" --ref main -f workspace=build-tooling
   # or persistently: gh variable set JF_GIT_WORKSPACE --body editor-src
   ```
4. Results: Xray → Scans List → Git Repositories → repo → Commits/Pull Requests, with the **Workspace** column/filter. Frogbot fetches the profile with `workspace_name` (visible in DEBUG logs).
5. Deleting a workspace moves its scan records to `default`. Not to be confused with a Bitbucket workspace (`JF_GIT_OWNER`). `frogbot-config.yml` working dirs are v2.

---

## 10. Advanced management & configuration, except Auto-PR ([doc](https://docs.jfrog.com/security/docs/advanced-management-and-configuration))

| Topic | Demo with this repo / psazuse |
|---|---|
| Config layers: env vars > platform config | Set `JF_UPLOAD_PR_SECURITY_RESULTS_TO_VCS=false` in the workflow while the profile says otherwise; env wins |
| Hierarchy Server → Folder → Repo, statuses Default/Custom/Inherited | Look at `github.com` → `ps-jfrog` → `npm-swagger-editor`; set a **folder-level** profile on `ps-jfrog` and watch the repo flip to *Inherited*. ⚠️ the folder holds 12 other repos; use a throwaway folder profile or skip |
| Batch Configure | Show the multi-select on the tree; don't apply on shared repos |
| Scans tab: SCA / Contextual Analysis / IaC / Secrets / SAST toggles + per-scanner exclude paths | Toggle one scanner off, rerun, watch the PR table show `ℹ️ Not Scanned` |
| SAST **differential scan** (repo level) | Enable; compare scan time/noise on `scan-repository` |
| Global Exclude / Include Paths | Exclude `test/**` or `docs/**`; add an issue there, it is ignored. Exclude `**/.git/**` for the `.git/config` false positive (FAQ Q2/Q4) |
| Advanced: **Fail on scan error** | Enable, then break a scanner (e.g. wrong `JF_RELEASES_REPO`) to see the job fail instead of `Partial results are allowed` |
| Advanced: **Scanner download source** / air-gapped | Create a Generic **remote** repo → `https://releases.jfrog.io` with *Store Artifacts Locally* unchecked; set it in Configure → Advanced and/or `JF_RELEASES_REPO` (repo name only). Instance already has `generic-jfrog-frogbot-remote`; verify it points at the `releases.jfrog.io` root |
| PR Decorations tab: *Show all security finding types*, *Skip comments when no issues* | Toggle and compare a clean PR vs a vulnerable one |
| Env vars (`JF_GIT_PROVIDER`, `JF_GIT_API_ENDPOINT`, `JF_SAST_DEFAULT_SCAN_MODE`, `JF_UPLOAD_*`, `JFROG_CLI_LOG_LEVEL`) | Table in §4 |
| Auto-PR tab | Skipped as requested |

---

## 11. Consuming the results ([doc](https://docs.jfrog.com/security/docs/how-to-consume-results))

| Where | What | How |
|---|---|---|
| **PR conversation** | Summary + inline comments (new issues only) | PR → Conversation / Files changed |
| **Actions run** | Fail reason, Watch name, DEBUG lines | Actions → *Frogbot Scan* |
| **GitHub Security → Code scanning** | JAS/SCA alerts from PR scans | needs `JF_UPLOAD_PR_SECURITY_RESULTS_TO_VCS=true` |
| **GitHub Dependency graph** | SBOM of `main` | Insights → Dependency graph (needs `JF_UPLOAD_SBOM_TO_VCS`) |
| **JFrog Platform** | History, violations, SBOM, per workspace | Xray → Scans List → **Git Repositories** → repo → Commits / Pull Requests (Workspace filter) |
| **Policies/Watch view** | Which Watch/policy fired | Xray → Watches → `npmapptrust-swagger-editor-frogbot` |
| **API** | Is the repo registered, last scanned commit/branches | `scripts/frogbot/04-verify.sh` (`/xray/api/v1/git/repositories`) |

---

## 12. Tests performed

**Done (platform side, from this Mac):**

| Test | Result |
|---|---|
| `run-all.sh` twice (idempotency) | ✅ create then update; no errors |
| Watch lookup exactly as Frogbot does it: `…/xsc/watches/resource?git_repository=github.com/ps-jfrog/npm-swagger-editor.git&project=npmapptrust` | ✅ `{"git_repository_watches":["npmapptrust-swagger-editor-frogbot"],"project_watches":["npmapptrust-swagger-editor-frogbot"]}` |
| Config Profile lookup for the clone URL | ✅ `System_Default_Profile` (expected before customization) |
| Policy/Watch effect: `jf audit --watches npmapptrust-swagger-editor-frogbot` on a throwaway project with `lodash@4.17.15` | ✅ `Found 4 violations: [3 SCA, 1 Operational Risk]`: XRAY-959813 (Critical), XRAY-140575 (High), XRAY-114089 (High), all from `npmapptrust-frogbot-security`; "violations configured to fail the build" (Fail Build works) |
| Public API for `fail_pull_request` | ❌ not persisted, hence the UI step in §3.3 |

**Not run (needs your action):** the GitHub Actions runs. `gh` is not authenticated on this Mac and the workflow is not pushed. Run the checklist:

1. `./scripts/frogbot/run-all.sh`, UI step §3.3, `FROGBOT_TOKEN=… ./scripts/frogbot/05-github-setup.sh`.
2. Push `main` → `scan-repository` green/red per Fail Build; `04-verify.sh` now lists the repo under git repositories.
3. Open the §5 PR → comment + red check + Code Scanning alert.
4. Enable §8 and §9 settings, repeat with `-f workspace=…`.

Re-run the local policy test any time:
```bash
mkdir /tmp/auditdemo && cd /tmp/auditdemo && echo '{"name":"d","version":"1.0.0","dependencies":{"lodash":"4.17.15"}}' > package.json && npm i --package-lock-only
jf audit --server-id psazuse --watches npmapptrust-swagger-editor-frogbot --sca
```

---

## 13. Troubleshooting (from the v3 FAQ)

| Symptom | Cause / fix |
|---|---|
| Violations in comment, job green | Rule lacks **Fail Pull Request** (PR) / **Fail Build** (repo), or no Watch matches (vulnerabilities mode) |
| `No watches were found … Calculating vulnerabilities` | URL mismatch (fork/other host), Watch inactive, wrong `JF_PROJECT_KEY` |
| `Failed to get active defined watches` | transient Xray/permission error; gating lost for the run, re-run |
| `Partial results are allowed, the error is skipped` | A scanner failed. Use `JF_RELEASES_REPO=<repo>` (not `JFROG_CLI_RELEASES_REPO=<server>/<repo>`); enable *Fail on scan error* |
| Secret on `.git/config` | false positive; exclude `**/.git/**` |
| Secrets not in PR comment | enable *show findings in PR decoration* (`show_secrets_as_pr_comment`); gating is independent |
| Op-risk fails check but no comment text | known gap (FAQ Q9); read the job log |
| `OIDC authentication against JFrog platform failed … HTTP 404 … oidc integration doesn't exist` | The action is calling the wrong platform or provider name. Check **org-level** variables too (Settings → Secrets and variables → Actions → Variables → *Organization variables*): the `ps-jfrog` org defines `JF_URL=https://psemea.jfrog.io` and `JF_OIDC_PROVIDER_NAME=krishnam-github-org-all-repos`, so a workflow reading `vars.JF_URL` hit psemea. Fix: set repo variable `FROGBOT_JF_URL=https://psazuse.jfrog.io` (the workflow reads this name). The org provider `krishnam-github-org-all-repos` does exist on psazuse and its mapping `ps-jfrog/**` grants admin for 30 min, so OIDC works once the URL is right. To use a token instead, remove the `oidc-provider-name:` lines from the workflow (an org-level variable can't be blanked per repo) and add the `FROGBOT_ACCESS_TOKEN` secret |
| `failed to run Sast scan … exit status 51` then `frogbot failed with exit code 1` | A scanner errored and the repo's Config Profile has **Fail on scan error** (`fail_upon_any_scanner_error`) on, so the job fails instead of skipping the scanner. Seen when `node_modules` was installed and no exclude paths were set. Install dependencies before Frogbot (npm SCA gives an empty SBOM otherwise) **and** exclude `**/node_modules/**`. Fix: Configure → Scans → **Global Exclude Paths** `**/node_modules/**`, `**/.git/**`; use `JF_SAST_DEFAULT_SCAN_MODE=directory` for large repos; untick *Fail on scan error* if you prefer partial results |
| Scan green, findings counted in the log (`Found 290 SAST…`) but Xray shows **no violations**; log has `artifact at path npmapptrust-frogbot/… does not exist in Artifactory` / `failed to get violations … Partial results are allowed` | The Frogbot repo is not **indexed by Xray** (`xrayIndex` false), so the uploaded SBOM is never scanned and the Watch is never evaluated. Fix: `scripts/frogbot/01-precreate-frogbot-repo.sh` (sets `xrayIndex=true`) or Administration → Xray Settings → Indexed Resources → add the repo. `04-verify.sh` prints the flag |
| `failed to upload SBOM snapshot to GitHub … Dependency graph is disabled` | Enable it: repo Settings → Advanced Security → **Dependency graph** |
| Frogbot repo/index errors on first scan | `npmapptrust-frogbot` missing, not indexed, or no Deploy permission (§3.1) |
| No v2 results after first scan | expected: first v3 scan switches the repo permanently |
| Frogbot proposes a version blocked by Curation | Frogbot does not consult Curation |

---

## 14. JFrog references

- Frogbot overview, centralized config, new scanning capabilities, pre-create repo: <https://docs.jfrog.com/security/docs/frogbot> (v3: <https://docs.jfrog.com/security/docs/frogbot-v3>)
- Commit scan and PR scan: <https://docs.jfrog.com/security/docs/how-to-commit-scan-and-pr-scan>
- Frogbot on GitHub: <https://docs.jfrog.com/security/docs/github>
- Consuming results: <https://docs.jfrog.com/security/docs/how-to-consume-results>
- Workspaces: <https://docs.jfrog.com/security/docs/manage-frogbot-workspaces>
- Advanced management and configuration: <https://docs.jfrog.com/security/docs/advanced-management-and-configuration>
- Xray policies and Watches: <https://docs.jfrog.com/security/docs/policies-in-jfrog-xray>
- IDE scan lab (VS Code extension, how the IDE picks Watches/Project, SwampUp 2025 IDE lab): [`jfrog-ide-scan-vscode.md`](jfrog-ide-scan-vscode.md)
- Source: <https://github.com/jfrog/frogbot> (local clone `~/mycode/github-jfrog/frogbot`, FAQ `docs/frogbot-v3-faq.md`)

---

## 15. Findings demo branch (`demo/frogbot-findings`)

`main` scans clean (SBOM 0, no findings): lockfiles are gitignored here, so Frogbot saw no resolvable dependency graph.
Branch `demo/frogbot-findings` (do **not** merge) adds `demo/frogbot-findings/` with intentionally vulnerable sample content and
installs dependencies before the scan. Verified locally with `jf audit --watches npmapptrust-swagger-editor-frogbot --sca --secrets --sast --iac`:

| Xray category | Seeded by | Local result |
|---|---|---|
| CVEs / Policy violations (security) | `package.json`: lodash 4.17.15, minimist 1.2.0, axios 0.21.1, express 4.17.1, jsonwebtoken 8.5.1, request 2.88.2 | 33 SCA violations (7 Critical, 26 High), 2 applicable (contextual) CVEs |
| Malicious package | `@step-security/malware-simulator@0.0.3`: the safe "EICAR-equivalent" from `xray_sbom_scans/curation/trip_test_demo_kit` (Catalog-flagged `knownToBeMalicious`) | Critical violation XRAY-257512 |
| Software components / License | `glpk.js` (GPL-3.0) vs policy `ban-copyleft` | 1 license violation |
| Operational risk | old/unmaintained deps (e.g. `request`) | 105 violations |
| Exposures: Secrets | `src/config.js` (fake keys, private key) | 5 secrets |
| Exposures: IaC | `iac/main.tf` (public S3, open SG, unencrypted DB) | 8 findings |
| SAST | `src/server.js` (command injection, eval, SQLi, XSS, SSRF, path traversal, weak crypto...) | 19 findings |

Note: the local `jf audit` run only turned SCA/license/op-risk findings into policy violations, but **Frogbot's real run in CI also produced Secrets violations** (see §16.8). IaC and SAST findings stay raw findings (Exposures / SAST tabs) with the current policies.
Heads-up: the default profile has Auto-Fix PRs on, so a scan of this branch may open fix PRs targeting it. Untick *Create automated fixes* in the repo's Configure drawer first if you do not want that (already done for this lab).


---

## 16. Lessons learned and demo tips (from the live runs)

### 16.1 Verified end-to-end result (run on branch `demo/frogbot-findings`)

| What | Value |
|---|---|
| Scan duration (scan-repository, installs + all scanners) | about 2m15s |
| Findings in the Frogbot log | 8 IaC, 5 secrets, 290 SAST (includes the root swagger-editor source), 89 SCA vulnerabilities, 3 applicable (contextual) CVEs, SBOM of about 1,330 components |
| Policy violations in Xray for the Watch (`scripts/frogbot/06-violations-summary.sh`) | 906: 832 operational risk, 72 Security (11 Critical, 50 High, 11 Medium) = 67 CVE/malicious + 5 Secrets exposures, 2 license (GPL) |
| Job result | **red, exit code 3** = a *Fail Build* rule matched (intended) |

### 16.2 Exit codes

| Frogbot exit code | Meaning |
|---|---|
| 0 | scan done, nothing matched a fail rule |
| 3 | a violation matched **Fail Build** (repo scan) or **Fail Pull Request** (PR scan) |
| 1 | a real error (auth, scanner, upload...). Read the log. Seen: OIDC 404, SAST `exit status 51` |

### 16.3 The platform must be set up before the first scan (order matters)

1. Frogbot repo `<project-key>-frogbot` exists **and has `xrayIndex=true`**. If not, Frogbot uploads the SBOM but Xray never scans it, the log warns `artifact at path ... does not exist in Artifactory` and the run still ends green with **zero violations**. `04-verify.sh` prints the flag.
2. Policies + Watch on the git repo URL (`02`, `03`). The Watch does not need the repo to be registered yet.
3. Config Profile tweaks (UI): see 16.5.
4. GitHub: environment, secret/OIDC, variables (`05`), **Dependency graph** enabled if you want the SBOM in GitHub.

### 16.4 Partial results hide failures, so read the log, not just the colour

`Partial results are allowed, the error is skipped` is a *Warn*. A green job can still mean "no violations because the violation step failed". In the log search for: `[Warn]`, `Found N`, `failed to get violations`, `dummy mode` (harmless: it is the analyzer's offline flag), `exit status`.
For quick triage without GitHub login: job steps and annotations are public (`curl https://api.github.com/repos/<repo>/actions/runs/<id>/jobs`, `.../check-runs/<job-id>/annotations`). **Full logs need a login** (UI: run page, gear icon, *Download log archive*, or `gh run view <id> --log`).

### 16.5 Recommended Config Profile for this demo (Configure drawer)

| Setting | Value | Why |
|---|---|---|
| Exclude paths | `**/node_modules/**`, `**/.git/**` | otherwise SAST scans `node_modules` and dies (`exit status 51`) |
| Fail the scan if any scanner fails | **off** for the demo | a flaky scanner then skips instead of failing the job (turn **on** in production) |
| Create automated fixes (Auto-Fix) | off while scanning demo branches | avoids a pile of fix PRs |
| Show findings in PR decoration (secrets) | on | secrets in the PR comment |
| Include vulnerabilities and violations | on | show everything, not only the policy violations |

Verify what Frogbot will really receive (UI edits are easy to mis-save): `scripts/frogbot/04-verify.sh` prints the profile for the clone URL (`fail_upon_any_scanner_error`, `exclude_patterns`).

### 16.6 npm specifics

- Frogbot's npm SCA needs the dependencies **installed** (or resolvable). With no `node_modules` the SBOM is empty and every counter is 0. The workflow runs `setup-node` plus `npm install --ignore-scripts` (non-blocking) before Frogbot. Lockfiles are gitignored here, so the demo folder's lockfile is committed with `git add -f`.
- Pair that with the `node_modules` exclude (16.5). Installing without the exclude breaks SAST.
- Use `--ignore-scripts`: the demo includes `@step-security/malware-simulator` (a harmless EICAR-like package whose `preinstall` makes one benign call).
- Root app scan adds noise (832 operational-risk, many SAST). To keep the demo crisp, exclude `src/**` and the root `package.json` via *Global exclude* / *include paths* `demo/frogbot-findings/**`, or use a workspace (section 9).

### 16.7 Variables: avoid org-level collisions

The `ps-jfrog` org defines `JF_URL` (a different instance) and `JF_OIDC_PROVIDER_NAME`. Repo/workflow code that reads `vars.JF_URL` silently picks the org value, so use the dedicated repo variable `FROGBOT_JF_URL`. The org provider `krishnam-github-org-all-repos` exists on psazuse and maps `ps-jfrog/**` to admin (30 min tokens), so OIDC works with no stored secret.

### 16.8 What turns into a policy violation

| Finding type | Violation with current policies? | Note |
|---|---|---|
| CVEs (SCA), malicious package | yes | `cve-high-critical`, `malicious-packages` |
| Secrets / private keys | **yes** (5 in the run) | `secrets-exposed` (exposures, secrets on) |
| License (GPL) | yes | `ban-copyleft` |
| Operational risk | yes, very many | report-only, tune `op_risk_min_risk` or drop the policy from the Watch if noisy |
| IaC | no, raw findings only | `exposures.iac` is off in the rule; enable it to get IaC violations |
| SAST | no, raw findings only | rule `sast-report-only` (>= Medium) did not match; raise/adjust rules in the policy |

Raw findings show in Scans List (Exposures, SAST tabs); violations show in Watch Violations and the Policy Violations tile.

### 16.9 Reading results programmatically

- `scripts/frogbot/06-violations-summary.sh`: counts per type/severity and Security by kind (`XRAY-*` = CVE/malicious, `EXP-*` = exposure). It pages the Xray violations API (default page is 500, so a naive call under-counts).
- Violations keep arriving for 1 to 2 minutes after the run ends (729 then 906 in one run). Wait before demoing the numbers.
- `POST /xray/api/v1/xsc/profile_repos {"repo_url": "..."}` shows the profile; `GET /xray/api/v1/xsc/watches/resource?git_repository=...&project=...` shows the matched Watches.

### 16.10 Misc

- Re-running a job (`Re-run jobs`) reuses the same commit and the **current** platform settings, so it is the quickest way to test a Config Profile change.
- `No runs found in the SARIF report, skipping upload to GitHub Security Tab` means nothing to upload (or no violations at that moment).
- `failed to upload SBOM snapshot to GitHub ... Dependency graph is disabled`: enable it in repo Settings, Advanced Security.
- Public repo: push protection did not block the fake private key in `demo/frogbot-findings/src/config.js`, but real-looking provider tokens (`ghp_`, `AKIA...`) would be blocked, so the demo uses generic fake secrets.
- The banner "Please review the repository settings and select Push Configuration..." in the Xray UI is about unrelated federated repos.
- Order of the live demo that worked well: (1) show `04-verify.sh` (Watch + profile), (2) push or re-run, (3) log: `Found` lines and the `fail_build` exit code 3, (4) Xray Scans List for the commit, (5) `06-violations-summary.sh`.


---

## 17. What is extra in `demo/frogbot-findings` (vs `main`) and how to use it

`main` carries everything reusable: workflow, docs, `scripts/frogbot/*`, the Xray policies/Watch setup. The branch adds **only** the items below. **Do not merge it into `main`.**

| Extra on `demo/frogbot-findings` | Purpose |
|---|---|
| `demo/frogbot-findings/package.json` + force-added `package-lock.json` | Vulnerable deps for SCA, contextual analysis, license and malicious-package findings: lodash 4.17.15, minimist 1.2.0, axios 0.21.1, express 4.17.1, jsonwebtoken 8.5.1, request 2.88.2, `glpk.js` (GPL-3.0 vs `ban-copyleft`), `@step-security/malware-simulator@0.0.3` (safe EICAR-like test package from the curation trip-test kit) |
| `demo/frogbot-findings/src/server.js` | SAST: command injection, `eval`, path traversal, XSS, SQL injection, open redirect, SSRF, weak hash, insecure cookie; also calls the vulnerable lodash/minimist functions so CVEs are *applicable* |
| `demo/frogbot-findings/src/config.js` | Secrets: fake keys, tokens and an RSA private key block (all fake) |
| `demo/frogbot-findings/iac/main.tf` | IaC: public S3 bucket, `0.0.0.0/0` security group, unencrypted public DB |
| `demo/frogbot-findings/README.md` | Warns that the folder is intentionally vulnerable |
| Workflow: `push` trigger also on `demo/**` | pushing the branch (or any `demo/*` branch) starts a repository scan |
| Workflow: extra install step `npm ci` in `demo/frogbot-findings` | resolves the demo deps (non-blocking) |

Effect: scans of the branch go **red (exit code 3)** by design (Critical/High CVEs, GPL license, secrets match Fail Build rules), while scans of `main` stay green (root app only: operational-risk and sub-High CVEs, nothing matches a fail rule).

### 17.1 Better ways to use the branch

| Goal | How |
|---|---|
| Demo `scan-pull-request` (PR comment, red check, Code Scanning alerts) | Open a PR **from** `demo/frogbot-findings` **into** `main` and **never merge it**. `pull_request_target` runs the workflow as it exists on `main`, so the PR scan uses `main`'s workflow. That version has no demo-folder install, so if the PR scan comes back empty, rely on the committed lockfile or add the demo install step to `main`'s workflow |
| Demo `scan-repository` with real findings on demand | `gh workflow run "Frogbot Scan" --ref demo/frogbot-findings` or push any commit to the branch |
| Keep the dirty fixture away from the team | Leave the branch unmerged. It is the "dirty" fixture; `main` stays clean and green |
| Show before/after of a fix | Branch from `demo/frogbot-findings`, remove or upgrade one dependency (for example lodash to a fixed version), open a PR into the demo branch: the diff scan reports only what changed |
| Reset the lab | Close the demo PR, delete the branch (`git push github-ps-jfrog --delete demo/frogbot-findings`), and run `scripts/frogbot/99-teardown.sh` for the Xray objects |

If someone does want the seeded content on `main` anyway, the safer variant is to merge only `demo/frogbot-findings/` (no workflow changes) and add `demo/**` to the Config Profile's *Global exclude paths*, so team scans stay clean. That hides the findings from `main` scans, so it defeats the demo. A PR from the branch is the better option.
