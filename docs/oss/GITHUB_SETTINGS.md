# Target GitHub Repository Settings & Configuration

This document specifies the target configuration, repository metadata, security features, and branch protection rules for the official DX-OS open-source repository at `https://github.com/ROYCE-8425/open_source`.

---

## 1. General Repository Metadata

- **Repository Name**: `open_source` (canonical project: `DX-OS`)
- **Owner**: `ROYCE-8425`
- **Visibility**: `Public`
- **Description**: `Open-source AI-native operating system for SME marketing workflows, automation, analytics and governed AI agents.`
- **Website**: `https://github.com/ROYCE-8425/open_source`
- **Topics**: `dotnet`, `aspnet-core`, `csharp`, `postgresql`, `workflow-automation`, `elsa-workflows`, `open-source`, `marketing-automation`, `ai-agents`, `sme`

---

## 2. Features & Community Engagement

| Feature | State | Rationale |
| :--- | :---: | :--- |
| **Issues** | **Enabled** | Community bug reporting and feature tracking with structured issue forms. |
| **Discussions** | **Enabled** | Q&A, RFC discussions, and community workflow sharing. |
| **Projects** | **Enabled** | Milestone and release tracking. |
| **Wikis** | **Disabled** | All documentation is version-controlled in the `docs/` folder in Git. |
| **Sponsorships** | Optional | Open for community sponsorship enablement. |

---

## 3. Pull Request Merge Strategy

- **Allow Merge Commits**: Disabled (keep linear history).
- **Allow Squash Merging**: **Enabled** (Default). Pull requests are squashed with PR title and description.
- **Allow Rebase Merging**: **Enabled**.
- **Automatically Delete Head Branches**: **Enabled** (keeps repository branch namespace clean).

---

## 4. Branch Protection Rules (`main`)

- **Branch Name Pattern**: `main`
- **Require a Pull Request before merging**:
  - Required approvals: `1`
  - Dismiss stale pull request approvals when new commits are pushed: `Enabled`
  - Require review from Code Owners: `Enabled`
- **Require Status Checks to Pass**:
  - Require branches to be up to date before merging: `Enabled`
  - Required status checks:
    - `build-and-test` (GitHub Actions CI workflow)
- **Require Conversation Resolution**: `Enabled` (all review comments must be resolved).
- **Require Signed Commits**: Recommended.
- **Do Not Allow Force Pushes**: `Enabled` (blocks `--force` / `--delete`).
- **Do Not Allow Deletions**: `Enabled`.

---

## 5. Security & Vulnerability Features

- **Private Vulnerability Reporting**: **Enabled** (Allows confidential security disclosures).
- **Dependency Graph**: **Enabled**.
- **Dependabot Alerts**: **Enabled**.
- **Dependabot Security Updates**: **Enabled**.
- **Secret Scanning**: **Enabled** (complements local Gitleaks gate).
- **Push Protection for Secrets**: **Enabled**.
- **CodeQL Analysis / OpenSSF Scorecard**: **Configured** via `.github/workflows/scorecard.yml`.
