# BR001-R7 Implementation Report: CI, Security Scanning, SBOM, and OSS Compliance

## Metadata

- **Task**: BR001-R7 (open_source-cab.8)
- **Specification**: openspec/changes/bootstrap-remediation-001/tasks.md#br001-r7-ci-security-scanning-sbom-and-oss-compliance
- **Baseline HEAD**: `72808fa31a303e6d8e25437a354dae7b624fceb2`
- **Date**: 2026-08-16
- **Status**: Ready for Independent Codex Review 3
- **LIVE_CI_STATUS**: PENDING_OWNER_AUTHORIZED_POST_PASS_PUBLICATION

## Exact Scope of Changes & Codex Re-review 2 Fixes

1. **Atomic & Current Security Summary (Codex Blocker 1 & 6)**:
   - Created [scripts/generate-security-summary.ps1](../../../scripts/generate-security-summary.ps1) as a dedicated gate (`full-security-summary`) running after all 4 scanners.
   - Reads every scanner report and [artifacts/sbom.cdx.json](../../sbom.cdx.json) directly from disk, computes current SHA-256 digests, validates schema/policies, captures Trivy and Grype DB metadata (version, timestamps, digests, and checksums), writes to staging, validates, and atomically updates [artifacts/security/security-summary.json](../../security/security-summary.json) and evidence files.
   - Added negative fixture in [scripts/verify-check-contract.ps1](../../../scripts/verify-check-contract.ps1) proving stale/corrupted reports fail closed.

2. **Canonical SBOM Deduplication & Mechanical Validation (Codex Blocker 2)**:
   - Defined canonical component identity key: `purl (case-normalized) if present, else type:name@version (case-normalized)`.
   - Updated [scripts/run-security-scan.ps1](../../../scripts/run-security-scan.ps1) during Syft generation to canonicalize and deduplicate components across catalogs, eliminating genuine duplicates while preserving primary records.
   - Generated canonical deliverable SBOM at [artifacts/sbom.cdx.json](../../sbom.cdx.json) cataloging exactly 122 components with 0 duplicates, 0 private paths, and metadata component `dxos-api:0.1.0-spike`.
   - Added mechanical duplicate detection assertion and negative fixture.

3. **Executable Ubuntu CI Parity (Codex Blocker 3)**:
   - Configured [.github/workflows/ci.yaml](../../../.github/workflows/ci.yaml) running on `ubuntu-latest` with `pwsh`, adding pinned `actions/setup-node@0a44ba7841725637a54e280ec667c276c6cb814d` and `@fission-ai/openspec@1.8.0` installation.
   - Made [scripts/check.ps1](../../../scripts/check.ps1) and [scripts/check-contract.json](../../../scripts/check-contract.json) platform-neutral (`command: "powershell"`, `command: "openspec"`), resolving `pwsh` / `openspec` on Linux and `powershell.exe` / `openspec.cmd` on Windows.
   - Updated [scripts/verify-ci-parity.ps1](../../../scripts/verify-ci-parity.ps1) to validate mechanical YAML structure, 40-character commit SHAs, zero continue-on-error, zero secrets, zero deploy/release actions, and Full gate parity.

4. **Safe TAR Archive Extraction (Codex Blocker 4)**:
   - Hardened [scripts/setup-security-tools.ps1](../../../scripts/setup-security-tools.ps1) with safe TAR listing (`tar -tf` and `tar -tvf`), pre-validating entry paths to reject `..` traversal, absolute paths, drive letters, path escape, symlinks, and hardlinks before extraction.
   - Preserved zip-slip protections and strict `Assert-SafePathChain` on staging and targets.

5. **Exact Bi-Directional OSS Inventory Reconciliation (Codex Blocker 5)**:
   - Generated complete machine-readable inventory at [artifacts/oss-inventory.json](../../oss-inventory.json) parsing all 9 `packages.lock.json` files and strictly excluding `type == "Project"` entries (eliminating the 6 blank project references).
   - Normalized exact 13 direct CPM packages, 215 transitive packages (228 total packages), 3 container images, 4 security tools, 2 third-party services, and 0 reused source.
   - Updated [scripts/verify-oss-compliance.ps1](../../../scripts/verify-oss-compliance.ps1) to perform bi-directional exact set comparisons and added negative fixtures for missing package, extra package, and version mismatch.

6. **Quality Gate Integration & Profile Isolation**:
   - Isolated R8 `NOT_IMPLEMENTED` gates to `ReadyAudit` profile; `Full` profile contains exactly the 26 R1–R7 gates (25 active `READY` gates + 1 `NOT_APPLICABLE` gate).
   - Executed single frozen Full quality gate run (`PID: 23936`, exit code `0`, duration `66.61s`).

## Pinned Security Tools & Scanner Databases

| Tool | Version | License | Executable SHA-256 (Windows x64) | Vulnerability DB Metadata |
|---|---|---|---|---|
| **Gitleaks** | 8.30.0 | MIT | `9d08e3f5cfb35a98f230b97bcda24f8d3fc66363c91868ffc98dac0afebdcb72` | Static rule engine (0 leaks) |
| **Trivy** | 0.72.0 | Apache-2.0 | `5c233d1514d6fd91f7a4f834beb92070f8a9793c71801f7f2149a7b30f90b821` | DB Version: 2; UpdatedAt: `2026-08-16 00:59:19 UTC`; CheckBundle Digest: `sha256:1583562f8b90ed2a071b99f0e5ffff6b57e4ceb6ca3e4796577b4e6a339eb74c` |
| **Syft** | 1.50.0 | Apache-2.0 | `98a3779f229905fec96e16018adf27ed7a93adc2869d17e6fb21961eb501d398` | CycloneDX 1.7 generator (122 deduplicated components) |
| **Grype** | 0.116.1 | Apache-2.0 | `0ab5d366118e20784222ce13c0f696e5997ae42bbcea80420d264a9c42098b57` | DB Schema: `v6.1.9`; Built: `2026-08-15T06:13:48Z`; Checksum: `sha256:5f8172952b86c8af2726ab5f17c323c16fde7cf99e76b87768f93fba68705a85` |

## Deliverable & Scan Evidence Summary

- **Deliverable Name**: `dxos-api`
- **Deliverable Version**: `0.1.0-spike`
- **Deliverable Image**: `dxos-api:0.1.0-spike`
- **Image Digest**: `sha256:0aa9797046b17878b52f9d5c8de472d070055839b20b074afc52a1c0afe60018`
- **Deliverable SBOM Path**: `artifacts/sbom.cdx.json`
- **SBOM Format / SpecVersion**: `CycloneDX 1.7` (122 components, 0 duplicates)
- **SBOM SHA-256**: `8E6CA2E6C11F5E16B3569B643904F34949E2AC71EFCC1359874C9051236C73F9`
- **Security Summary Path**: `artifacts/security/security-summary.json`
- **Security Summary SHA-256**: `09C26F8A9367CF309812722A407E9C473FFC638C8BDF5F53C751F9B85A9A7980`
- **OSS Inventory Path**: `artifacts/oss-inventory.json`
- **OSS Inventory SHA-256**: `6CE148111960ED5685D02F6C78C82153B9906FDBE932F531333E73E3267BBEA1`
- **Gitleaks Scan**: 0 leaks detected across history and working tree (`gitleaks-report.json` SHA-256: `37517E5F3DC66819F61F5A7BB8ACE1921282415F10551D2DEFA5C3EB0985B570`)
- **Trivy Config Scan**: 0 HIGH/CRITICAL misconfigurations (`trivy-config-report.json` SHA-256: `9F7003559AD7AECAAB1904ED50CB3E60908FA809240C2C2EE5B7AA136C98690D`)
- **Trivy Image Scan**: 0 HIGH/CRITICAL vulnerabilities on `dxos-api:0.1.0-spike` (`trivy-image-report.json` SHA-256: `BAC93D3F75518F51FAB9FA8B83B92A373E418130111343125010FAD72DC3E07D`)
- **Grype SBOM Scan**: 0 vulnerabilities at/above HIGH severity (`grype-report.json` SHA-256: `D2007F05EE8465B33E88DF60311353465A6192919F0AE1B943245B50C2B1D00B`)
- **Overall Quality Gate Result**: `PASS` (Full profile: 25 active READY gates passed, 1 NOT_APPLICABLE gate skipped, duration 66.61s)
