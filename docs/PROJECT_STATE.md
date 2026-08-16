# DX-OS Project State

Authoritative, evidence-backed summary of DX-OS engineering and governance state. Only independently reviewed and accepted milestones are recorded as completed.

## 1. Current Milestone

- **Active Milestone**: BR001-R6: Agent Governance and Project Memory (Finalized / Transitioning to BR001-R7)
- **OpenSpec Change**: openspec/changes/bootstrap-remediation-001/
- **Active Beads Issue**: open_source-cab.5 (Accepted / Closed)
- **Status**: Milestone accepted via Codex R6 Re-review 2 PASS.

## 2. Accepted Capabilities

| Milestone | Scope | Evidence Summary | Verdict |
|---|---|---|---|
| **BR001-R1** | Repository Extraction & Identity | Clean DX-OS repository initialized; zero Elsa source coupling; provenance and extraction manifest created. | PASS (Codex) |
| **BR001-R2** | Minimal Build System & CPM | .NET 10 CPM configuration; warnings as errors; clean restore and Release build passing. | PASS (Codex) |
| **BR001-R3** | Deterministic Quality Gate | Fail-fast native PowerShell quality runner (scripts/check.ps1), contract verifier, and Foundation profile. | PASS (Codex Re-review 10) |
| **BR001-R4** | Engineering Runtime Spike | Elsa 3.7.1 NuGet integration, PostgreSQL 18.4 migrations/health probes, Aspire 13.4.6 & Docker Compose orchestration, deterministic smoke workflow. | PASS (Codex Re-review 5) |
| **BR001-R5** | Meaningful Test Foundation | xUnit v3 / MTP test suites (9 unit tests, 13 ArchUnitNET architecture rules, 5 PostgreSQL Testcontainers integration tests), fail-closed Docker test boundary, zero-test check, and Runtime quality gate. | PASS (Codex Re-review 10) |
| **BR001-R6** | Agent Governance & Project Memory | DX-OS constitution, authority hierarchy, OpenSpec & Beads mapping, bootstrap ADRs (ADR-0001 through ADR-0007), project state, and evidence index ratified. | PASS (Codex Re-review 2) |

## 3. Active Beads Issue

- **Issue ID**: open_source-cab.5 (closed)
- **Title**: Configure DX-OS OpenSpec, ADRs, and agent governance
- **Status**: closed
- **Owner / Assignee**: ROYCE-8425
- **Dependencies**: open_source-cab.4 (closed)
- **Blocks**: open_source-cab.8 (BR001-R7)

## 4. Current Blockers

- **Operational Blockers**: None within active milestone R6.
- **Release Blockers**:
  - CI security scanners (Gitleaks, Trivy, Syft, Grype) and CycloneDX SBOM validation pending in BR001-R7.
  - Final clean-clone verification and public repository ownership audit pending in BR001-R8.

## 5. Accepted Architectural Decisions

- [ADR-0001](adr/0001-dx-os-open-source-license.md): Default project license is Apache License 2.0.
- [ADR-0002](adr/0002-third-party-services-and-ai-provider-independence.md): External services disclosed separately; AI integrations are provider-independent.
- [ADR-0003](adr/0003-independent-repository-extraction-and-identity.md): Independent DX-OS repository extraction, clean history, and distinct identity.
- [ADR-0004](adr/0004-modular-monolith-architecture.md): Modular monolith with vertical slices and proportionate boundaries.
- [ADR-0005](adr/0005-postgresql-persistence.md): PostgreSQL persistence via EF Core and Testcontainers integration.
- [ADR-0006](adr/0006-elsa-nuget-integration.md): Elsa workflow engine consumption strictly via stable NuGet packages.
- [ADR-0007](adr/0007-aspire-and-docker-compose-orchestration.md): Dual orchestration via .NET Aspire (inner loop) and Docker Compose (deployment).

## 6. Known Debt

- **Browser/UI E2E Suite**: UI E2E tests are explicitly marked N/A during bootstrap remediation because UI frontend components are not yet built.
- **Security Scanners in Quality Gate**: Automated Gitleaks, Trivy, Syft, and Grype scanner canaries and SBOM gates are scheduled for implementation in BR001-R7.
- **Business Work**: Marketing automation and business workflow features have not started; all work to date is foundational infrastructure.

## 7. Next Task

- **Next Workstream**: BR001-R7 (CI Security and OSS Compliance)
- **Beads Issue**: open_source-cab.8
- **Prerequisite**: Independent Codex PASS verdict on open_source-cab.5 and closure of R6.

## 8. Demo Readiness

- **Engineering Demo**: Deterministic smoke workflow is runnable via .NET Aspire AppHost (src/DXOS.AppHost) and Docker Compose (compose.yaml).
- **Product Marketing Demo**: NOT READY (business features and UI layers are not yet implemented).

## 9. Release Readiness

- **Status**: NOT_READY
- **Release Gating Criteria**:
  - [x] Independent DX-OS repository extraction (R1)
  - [x] Deterministic CPM build system (R2)
  - [x] Native fail-fast quality gate (R3)
  - [x] PostgreSQL & Elsa NuGet runtime integration (R4)
  - [x] Unit, architecture, and Testcontainers integration test suites (R5)
  - [x] Agent governance, constitution, and project memory ratified (R6)
  - [ ] CI pipeline, Gitleaks, Trivy, Syft, Grype security gates, and SBOM (R7 - pending)
  - [ ] Clean-clone re-audit from public remote (R8 - pending)
  - [ ] Business product features (Gated until CLEAN CLONE / READY audit PASS)

## 10. Risks

- **Docker Environment Dependency**: Runtime integration tests and Docker Compose deployment require an active, healthy Docker daemon.
- **Third-Party Model API Changes**: External AI model API contracts may shift; mitigated by strict DX-OS application provider abstractions (IChatClient).

## 11. Links to Durable Evidence

- [Evidence Index](EVIDENCE_INDEX.md)
- [Audit 001 Report](audits/BOOTSTRAP-AUDIT-001.md)
- [R1 Implementation Report](../artifacts/task-runs/open_source-cab.1/implementation-report.md) | [R1 Verification](../artifacts/task-runs/open_source-cab.1/verification.md)
- [R2 Implementation Report](../artifacts/task-runs/open_source-cab.2/implementation-report.md) | [R2 Review](../artifacts/task-runs/open_source-cab.2/review.md)
- [R3 Implementation Report](../artifacts/task-runs/open_source-cab.7/implementation-report.md) | [R3 Review](../artifacts/task-runs/open_source-cab.7/review.md)
- [R4 Implementation Report](../artifacts/task-runs/open_source-cab.3/implementation-report.md) | [R4 Review](../artifacts/task-runs/open_source-cab.3/review.md)
- [R5 Implementation Report](../artifacts/task-runs/open_source-cab.4/implementation-report.md) | [R5 Review](../artifacts/task-runs/open_source-cab.4/review.md)
- [R6 Implementation Report](../artifacts/task-runs/open_source-cab.5/implementation-report.md) | [R6 Verification](../artifacts/task-runs/open_source-cab.5/verification.md) | [R6 Review](../artifacts/task-runs/open_source-cab.5/review.md)