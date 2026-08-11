## Purpose

Defines the independently owned, reproducible repository and minimal .NET build foundation that DX-OS must establish before product implementation can begin.

## ADDED Requirements

### Requirement: Existing Elsa checkout is preserved
Repository extraction MUST leave the audited Elsa checkout, its Git history, and all original files intact until the new DX-OS repository passes clean-clone verification.

#### Scenario: Extraction starts safely
- **WHEN** repository extraction begins
- **THEN** the existing Elsa checkout remains readable and unchanged
- **AND** no delete, history rewrite, reset, force-push, or remote push is performed against it

### Requirement: DX-OS-owned artifacts are inventoried before copying
The extraction process SHALL produce a reviewed inventory that classifies every candidate artifact as copy, recreate, exclude, or unresolved before any candidate is transferred.

#### Scenario: Candidate artifact is reviewed
- **WHEN** an artifact is considered for the new repository
- **THEN** the inventory records its source path, ownership rationale, transfer action, destination, and review status
- **AND** unresolved artifacts are not copied

### Requirement: New repository has independent identity
The target repository MUST have DX-OS-owned Git history, remote configuration, package metadata, agent instructions, and license decision, and MUST NOT identify Elsa Core as the owning product.

#### Scenario: Repository identity is inspected
- **WHEN** an auditor checks the target repository root, Git remotes, root commit, build metadata, license, and agent instructions
- **THEN** each identifies DX-OS or the approved DX-OS owner
- **AND** no push remote targets `elsa-workflows/elsa-core`

### Requirement: Elsa source is external to the build repository
The target repository MUST NOT contain or depend on the Elsa Core source tree, Elsa solution, Elsa project files, inherited Elsa build files, or Elsa CI workflows.

#### Scenario: Solution and project graph are enumerated
- **WHEN** the target repository and `DXOS.slnx` are enumerated from a clean clone
- **THEN** only reviewed DX-OS-owned projects and intentional non-source assets are present
- **AND** no Elsa source project is compiled or referenced

### Requirement: .NET 10 SDK selection is deterministic
The target repository SHALL pin an approved .NET 10 SDK in `global.json` with an explicit roll-forward policy that permits only the documented compatibility range.

#### Scenario: Unsupported SDK is active
- **WHEN** a developer invokes the documented build with an SDK outside the allowed range
- **THEN** the invocation fails with an actionable SDK-selection error instead of silently using an unapproved SDK

#### Scenario: Approved SDK is active
- **WHEN** the pinned SDK or an allowed roll-forward SDK is installed
- **THEN** restore and build select the expected .NET 10 toolchain

### Requirement: Central Package Management is minimal and owned by DX-OS
The target repository SHALL manage package versions centrally and MUST list only packages intentionally consumed by DX-OS or its tests/build tools.

#### Scenario: Central package catalog is reviewed
- **WHEN** `Directory.Packages.props` and resolved top-level references are compared
- **THEN** every central version has a documented consumer or approved near-term bootstrap purpose
- **AND** no Elsa source-build catalog or unjustified private feed remains

### Requirement: Solution boundaries remain intentionally small
`DXOS.slnx` SHALL include only projects with a current Engineering OS responsibility, and new projects MUST be justified by a durable boundary rather than a small feature or textbook layer.

#### Scenario: Empty or redundant project is proposed
- **WHEN** a project has no distinct runtime, domain, composition, test, or deployment responsibility
- **THEN** it is omitted or consolidated before acceptance

### Requirement: Modular-monolith dependency direction is executable
The production dependency graph MUST enforce Domain independence from Infrastructure, application-level orchestration without persistence leakage, workflow/provider isolation, and composition only at approved hosts.

#### Scenario: Forbidden dependency is introduced
- **WHEN** a project creates a reference that violates an approved dependency rule
- **THEN** an architecture test fails with the violating projects or types identified

### Requirement: Ceremony-heavy patterns are prohibited
The Engineering OS MUST NOT introduce a generic `Repository<T>`, a UnitOfWork wrapper over EF Core, empty `IService`/`Service` pairs, microservices, one-project-per-small-feature structure, or an undemonstrated Kafka/Redis/RabbitMQ dependency.

#### Scenario: Prohibited abstraction is proposed
- **WHEN** an implementation adds one of the prohibited patterns without a separately accepted requirement and ADR
- **THEN** review returns `FIX_REQUIRED`

### Requirement: Clean clone is independent of the old checkout
The target repository SHALL restore, build, test, and start its required bootstrap runtime from a clean clone when the old Elsa checkout is unavailable.

#### Scenario: Old checkout is absent
- **WHEN** verification runs in a clean directory with no Elsa source checkout on disk
- **THEN** no build, test, runtime, documentation, or script path resolves into the old checkout

