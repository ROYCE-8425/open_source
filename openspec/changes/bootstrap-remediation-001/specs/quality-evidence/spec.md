## Purpose

Defines the deterministic local and CI evidence that must replace placeholder tests and false-green tooling before DX-OS bootstrap can be declared READY.

## ADDED Requirements

### Requirement: Quality gate fails fast and propagates failure
The documented quality command MUST check required tool availability, invoke each required gate explicitly against DX-OS targets, stop on the first required failure, and return a non-zero process exit code.

#### Scenario: Required tool is missing
- **WHEN** any required executable is unavailable
- **THEN** the quality command stops before dependent checks
- **AND** returns non-zero with the missing tool and remediation guidance identified

#### Scenario: Required command fails
- **WHEN** restore, format, build, test, runtime, security, SBOM, or OpenSpec validation fails
- **THEN** later success cannot overwrite the failure
- **AND** the final process exit code remains non-zero

### Requirement: Quality gate targets are unambiguous
The quality command SHALL name `DXOS.slnx`, test projects, Compose file, OpenSpec change, and output paths explicitly so unrelated solution files cannot change the selected target.

#### Scenario: Unrelated solution exists in the working directory
- **WHEN** the quality command runs beside another solution file
- **THEN** all .NET operations still target only the documented DX-OS solution and tests

### Requirement: Tests provide meaningful evidence
Every counted unit, architecture, or integration test MUST reference production behavior or an executable architectural rule and MUST contain an assertion that can fail when the protected behavior regresses.

#### Scenario: Empty placeholder test is present
- **WHEN** verification detects a test that contains no meaningful assertion or production/reference boundary
- **THEN** it is excluded from PASS evidence and remediation remains incomplete

### Requirement: PostgreSQL integration tests use a real engine
Persistence and migration evidence SHALL execute against an isolated real PostgreSQL instance and MUST NOT substitute an in-memory provider or fake repository for database behavior.

#### Scenario: Database integration suite runs
- **WHEN** integration tests execute in a supported environment
- **THEN** they provision isolated PostgreSQL, apply migrations, perform a real operation, and clean up their resources

### Requirement: Architecture rules are executable
Architecture tests SHALL enforce the approved project/type dependency direction and the prohibition on source-project Elsa coupling.

#### Scenario: Architecture remains compliant
- **WHEN** architecture tests run on compiled production assemblies
- **THEN** all required boundaries are evaluated and reported
- **AND** the test count cannot be satisfied by an empty placeholder

### Requirement: E2E status is truthful
E2E SHALL be reported as `NOT_APPLICABLE` until a real user interface or end-to-end surface and executable scenario exist; an empty test MUST NOT be reported as PASS.

#### Scenario: No real UI exists
- **WHEN** the bootstrap quality report is produced before UI implementation
- **THEN** E2E is recorded as `NOT_APPLICABLE` with the reason and activation condition

### Requirement: Required security and supply-chain checks execute
The accepted quality/CI path SHALL execute Gitleaks, Trivy, Syft SBOM generation, and Grype or an approved equivalent with pinned/documented versions and machine-readable artifacts where supported.

#### Scenario: Security scan finds a blocking issue
- **WHEN** a configured policy threshold is exceeded
- **THEN** local/CI verification fails non-zero
- **AND** the report identifies the tool, rule/advisory, affected artifact, and disposition path

### Requirement: SBOM reflects resolved deliverables
The generated SBOM SHALL describe the actual resolved application/container dependencies for the verified commit and SHALL be retained as a CI/task evidence artifact.

#### Scenario: SBOM is generated
- **WHEN** the quality or release evidence workflow runs
- **THEN** the SBOM file exists in the documented format
- **AND** its metadata identifies the DX-OS component and verified revision

### Requirement: CI and local required gates remain aligned
DX-OS CI SHALL execute the same required correctness/security contracts as the documented local gate, with platform-specific wrappers allowed only when they preserve semantics and failure behavior.

#### Scenario: Pull request verification runs
- **WHEN** a change is proposed to the DX-OS repository
- **THEN** CI reports separate results for restore, format, build, tests, runtime/container validation, security scans, SBOM, and OpenSpec validation

### Requirement: OSS disclosures match actual dependencies
`OPEN_SOURCE.md`, `THIRD_PARTY_NOTICES.md`, license records, and dependency approval evidence SHALL cover actual shipped packages, tools, copied material, and external services without claiming unintegrated components.

#### Scenario: Dependency inventory changes
- **WHEN** an approved dependency is added, removed, or upgraded
- **THEN** disclosure and license evidence are updated in the same reviewed task when required

### Requirement: READY is established only by clean-clone evidence
Bootstrap MUST remain `NOT_READY` until a clean-clone re-audit records PASS for every required READY gate and no placeholder evidence is counted.

#### Scenario: One required gate is not executable
- **WHEN** the follow-up audit finds a required gate failed, skipped, missing, or not verified
- **THEN** the verdict is not `READY`

