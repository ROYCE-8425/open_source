# BR001-R7 Verification Report: CI, Security Scanning, SBOM, and OSS Compliance

## Metadata

- **Task**: BR001-R7 (open_source-cab.8)
- **Specification**: openspec/changes/bootstrap-remediation-001/tasks.md#br001-r7-ci-security-scanning-sbom-and-oss-compliance
- **Baseline HEAD**: `72808fa31a303e6d8e25437a354dae7b624fceb2`
- **Date**: 2026-08-16
- **Status**: Ready for Independent Codex Review 3
- **LIVE_CI_STATUS**: PENDING_OWNER_AUTHORIZED_POST_PASS_PUBLICATION

## Targeted Test Matrix Results

| # | Check / Command | Exit Code | Disposition | Description |
|---|---|---|---|---|
| 1 | PowerShell AST Parsing (13 scripts) | 0 | PASS | 0 AST syntax errors across all repository PowerShell scripts |
| 2 | `powershell -ExecutionPolicy Bypass -File scripts/setup-security-tools.ps1 -VerifyOnly` | 0 | PASS | Strict binary verification (path, version, SHA-256, safe path chain) |
| 3 | `powershell -ExecutionPolicy Bypass -File scripts/verify-security-canaries.ps1` | 0 | PASS | 4/4 scanner canaries detect synthetic flaws with exact finding IDs (`github-pat`, `DS-0002`, `requests/urllib3`, `GHSA-jfh8-c2jp-5v3q / CVE-2021-44228`) |
| 4 | `powershell -ExecutionPolicy Bypass -File scripts/verify-check-contract.ps1` | 0 | PASS | Contract mechanics, Full (26 gates) vs ReadyAudit (29 gates), atomic summary, safe TAR, SBOM duplicate, and OSS fixtures |
| 5 | `powershell -ExecutionPolicy Bypass -File scripts/verify-oss-compliance.ps1` (All 5 Checks) | 0 | PASS | Exact bi-directional reconciliation: 228 packages (13 direct, 215 transitive), 3 images, 4 tools, 2 services, 122 SBOM components, 0 duplicates, 0 missing/extra |
| 6 | `powershell -ExecutionPolicy Bypass -File scripts/verify-ci-parity.ps1` | 0 | PASS | CI workflow mechanical schema, 40-char commit SHAs, OpenSpec install, zero continue-on-error, Full gate parity |
| 7 | `git diff --check` | 0 | PASS | Zero whitespace, conflict, or diff syntax errors |
| 8 | Strict UTF-8 / BOM / C0 / Trailing Whitespace Scan | 0 | PASS | 0 C0 control character violations, 0 new BOM violations across 255 text files |
| 9 | `openspec.cmd validate bootstrap-remediation-001 --type change --strict --no-interactive` | 0 | PASS | Strict OpenSpec schema, proposal, and tasks validation |
| 10 | `bd.cmd show open_source-cab.8 --json` & `bd.cmd dep cycles` | 0 | PASS | Task is claimed and `in_progress`, 0 dependency cycles |

## Frozen Full Quality Gate Execution Details

- **Profile**: Full
- **Command**: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1 -Profile Full`
- **PID**: `23936`
- **Start Time**: `2026-08-16T11:34:49.2628451+07:00`
- **End Time**: `2026-08-16T11:35:55.8728451+07:00`
- **Total Duration**: `66.61s`
- **Exit Code**: `0`
- **Overall Result**: `PASS`
- **Evidence Path**: `artifacts/quality-gate/evidence-Full-785f1140-8da5-45b9-97ec-d7ca09296106.json`
- **Total Gates**: 26 (25 active READY gates passed, 1 NOT_APPLICABLE gate skipped)
- **Active R8 Gates in Full**: 0 (R8 gates are isolated to `ReadyAudit`)

### Executed Gates Breakdown

1. `foundation-restore` (BR001-R2.4): READY -> PASS (Exit 0)
2. `foundation-format` (BR001-R2.4): READY -> PASS (Exit 0)
3. `foundation-build` (BR001-R2.4): READY -> PASS (Exit 0)
4. `foundation-openspec` (BR001-R6.2): READY -> PASS (Exit 0)
5. `foundation-hygiene` (BR001-R2.4): READY -> PASS (Exit 0)
6. `runtime-docker-compose` (BR001-R4.4): READY -> PASS (Exit 0)
7. `runtime-smoke-compose` (BR001-R4.4): READY -> PASS (Exit 0)
8. `runtime-smoke-aspire` (BR001-R4.4): READY -> PASS (Exit 0)
9. `runtime-unit-tests` (BR001-R5.2): READY -> PASS (Exit 0)
10. `runtime-architecture-tests` (BR001-R5.2): READY -> PASS (Exit 0)
11. `runtime-integration-tests` (BR001-R5.3): READY -> PASS (Exit 0)
12. `runtime-e2e-tests` (BR001-R5.1): NOT_APPLICABLE -> SKIPPED (Exit 0)
13. `full-gitleaks-scan` (BR001-R7.2): READY -> PASS (Exit 0)
14. `full-trivy-scan` (BR001-R7.2): READY -> PASS (Exit 0)
15. `full-syft-sbom` (BR001-R7.2): READY -> PASS (Exit 0)
16. `full-grype-scan` (BR001-R7.2): READY -> PASS (Exit 0)
17. `full-security-summary` (BR001-R7.2): READY -> PASS (Exit 0)
18. `full-governance-instructions` (BR001-R6.1): READY -> PASS (Exit 0)
19. `full-governance-adr-sync` (BR001-R6.2): READY -> PASS (Exit 0)
20. `full-governance-state` (BR001-R6.3): READY -> PASS (Exit 0)
21. `full-ci-parity` (BR001-R7.3): READY -> PASS (Exit 0)
22. `full-oss-license` (BR001-R7.4): READY -> PASS (Exit 0)
23. `full-oss-attribution` (BR001-R7.4): READY -> PASS (Exit 0)
24. `full-oss-inventory` (BR001-R7.4): READY -> PASS (Exit 0)
25. `full-oss-service-disclosure` (BR001-R7.4): READY -> PASS (Exit 0)
26. `full-identity-public` (BR001-R7.4): READY -> PASS (Exit 0)
