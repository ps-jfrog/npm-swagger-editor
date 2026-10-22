# Frogbot v3 findings demo (DO NOT MERGE TO main)

Intentionally vulnerable sample app used to light up every Frogbot / Xray finding category:

| Category | File |
|---|---|
| CVEs (SCA, incl. contextual analysis) | `package.json` (+ calls in `src/server.js`) |
| License violation (GPL-3.0, Watch policy `ban-copyleft`) | `glpk.js` dependency in `package.json` |
| Operational risk | old / unmaintained dependencies in `package.json` |
| Secrets / exposures | `src/config.js` (all values are fake) |
| SAST | `src/server.js` |
| IaC | `iac/main.tf` |

Everything here is fake or sample code. Never reuse any of it.
