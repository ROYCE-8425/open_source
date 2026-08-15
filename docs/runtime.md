# DX-OS Engineering Runtime Guide

This document describes the runtime spike architecture, development orchestration paths, health model, and verification workflows for DX-OS bootstrap milestone BR001-R4.

---

## 1. Runtime Architecture

DX-OS uses two independent runtime paths for developer workflows and containerized demo environments:

1. **.NET Aspire Developer Control Plane** (`src/DXOS.AppHost`):
   - Orchestrates local dependencies (`postgres:18.4-alpine`) and the API host (`src/DXOS.Api`).
   - Surfaces structured telemetry, logs, resources, and endpoints for local development.
   - Run via `dotnet run --project src/DXOS.AppHost/DXOS.AppHost.csproj`.

2. **Docker Compose Demo Path** (`compose.yaml`):
   - Standalone container deployment running PostgreSQL 18.4 and a multi-stage containerized `dxos-api` build.
   - Independent of Aspire; requires only Docker Engine & Docker Compose.
   - Run via `docker compose -f compose.yaml up -d --build`.

---

## 2. Persistence & Migrations

- **Database Engine**: PostgreSQL 18.4 (`postgres:18.4-alpine`).
- **Entity Framework Core**: DbContext lives in `DXOS.Infrastructure.Persistence.BootstrapDbContext`.
- **Engineering Checkpoints**: Minimal `runtime_probes` table tracking probe executions.
- **Migration Execution**:
  - Automatically applied on startup when `Database:AutoMigrate=true`.
  - Or manually applied using:
    ```powershell
    dotnet ef database update --project src/DXOS.Infrastructure/DXOS.Infrastructure.csproj --startup-project src/DXOS.Api/DXOS.Api.csproj
    ```

---

## 3. Endpoints & Health Model

| Endpoint | Method | Purpose | Behavior |
|---|---|---|---|
| `/health/live` | `GET` | Liveness Probe | Returns `200 OK` if the web host is alive; does **not** query PostgreSQL. |
| `/health/ready` | `GET` | Readiness Probe | Performs a real database connectivity check on PostgreSQL. Returns `200 OK` when ready, or `503 Service Unavailable` if unreachable. |
| `/smoke/workflow` | `POST` | Elsa Smoke Workflow | Executes the deterministic `EngineeringSmokeWorkflow` via Elsa 3 `IWorkflowRunner`. Returns `200 OK` with workflow instance ID, status `Completed`, and deterministic output `DXOS_SMOKE_OK`. Fails fast (`503/500`) if dependencies are unavailable. |

---

## 4. Runtime Smoke Automation

The script `scripts/smoke-runtime.ps1` executes automated end-to-end smoke verification for either runtime mode:

### Docker Compose Mode
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-runtime.ps1 -Mode Compose
```

### Aspire Mode
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\smoke-runtime.ps1 -Mode Aspire
```

The script:
1. Validates the repository root.
2. Starts the target environment with bounded startup timeouts.
3. Verifies PostgreSQL readiness and API liveness/readiness.
4. Executes the Elsa workflow smoke and validates instance ID, `Completed` status, deterministic output, and correlation ID.
5. Tests negative dependency handling (database unavailability).
6. Tears down and cleans task-owned processes, containers, and resources fail-closed in `try ... finally`.
