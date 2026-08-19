[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Get-Item $PSScriptRoot\..).FullName
$ciWorkflowPath = Join-Path $repoRoot ".github\workflows\ci.yaml"
$globalJsonPath = Join-Path $repoRoot "global.json"

if (-not (Test-Path $ciWorkflowPath)) {
    throw "CI workflow file missing at: $ciWorkflowPath"
}
if (-not (Test-Path $globalJsonPath)) {
    throw "global.json file missing at: $globalJsonPath"
}

Write-Host "Verifying CI workflow mechanical schema and cross-platform parity policy..." -ForegroundColor Cyan

# 1. Parse global.json
$globalJson = Get-Content $globalJsonPath -Raw | ConvertFrom-Json
$expectedSdkVersion = $globalJson.sdk.version
if ([string]::IsNullOrWhiteSpace($expectedSdkVersion)) {
    throw "global.json does not declare sdk.version"
}

# 2. Parse ci.yaml
$ciContent = Get-Content $ciWorkflowPath -Raw

# Check runner and permissions
if (-not ($ciContent -match "runs-on:\s*ubuntu-latest")) {
    throw "CI workflow must run on ubuntu-latest for container/Linux parity."
}

if (-not ($ciContent -match "permissions:\s*\r?\n\s*contents:\s*read")) {
    throw "CI workflow must declare strict least-privilege permissions (contents: read)."
}

# 3. Check 40-character commit SHA pinning for all actions
$actionMatches = [regex]::Matches($ciContent, 'uses:\s*([^\s@]+)@([^\s#\r\n]+)')
if ($actionMatches.Count -eq 0) {
    throw "No GitHub Actions found in CI workflow."
}

foreach ($m in $actionMatches) {
    $actionName = $m.Groups[1].Value
    $actionRef = $m.Groups[2].Value

    if ($actionRef -notmatch '^[0-9a-f]{40}$') {
        throw "Action '$actionName' uses non-immutable ref '$actionRef'. All CI actions MUST be pinned to a 40-character commit SHA."
    }
}

# 4. Strict SDK version comparison with global.json
$sdkMatch = [regex]::Match($ciContent, "dotnet-version:\s*['`"]?([^'`"\s\r\n]+)['`"]?")
if (-not $sdkMatch.Success) {
    throw "CI workflow missing dotnet-version specification in setup-dotnet step."
}
$ciSdkVersion = $sdkMatch.Groups[1].Value.Trim()
if ($ciSdkVersion -ne $expectedSdkVersion) {
    throw "CI workflow .NET SDK version mismatch! ci.yaml specifies '$ciSdkVersion', but global.json requires '$expectedSdkVersion'."
}

# 5. Assert tool acquisitions and setup steps
if (-not ($ciContent -match "actions/setup-node@")) {
    throw "CI workflow missing actions/setup-node for OpenSpec CLI execution."
}
if (-not ($ciContent -match "@fission-ai/openspec@1\.8\.0")) {
    throw "CI workflow missing pinned @fission-ai/openspec@1.8.0 installation."
}
if (-not ($ciContent -match "actions/setup-dotnet@")) {
    throw "CI workflow missing actions/setup-dotnet step."
}
if (-not ($ciContent -match "setup-security-tools\.ps1")) {
    throw "CI workflow missing pinned security tools acquisition step."
}
if (-not ($ciContent -match "verify-security-canaries\.ps1")) {
    throw "CI workflow missing security canaries verification step."
}
if (-not ($ciContent -match "check\.ps1\s+-Profile\s+Full")) {
    throw "CI workflow must execute Full quality gate profile."
}

# 6. Assert zero continue-on-error, zero secrets, zero deploy/publish steps
if ($ciContent -match "continue-on-error:\s*true") {
    throw "CI workflow contains 'continue-on-error: true' which violates zero-tolerance quality gates."
}

if ($ciContent -match "secrets\.") {
    throw "CI workflow references secrets context. CI quality gate must be fully reproducible without proprietary credentials."
}

if ($ciContent -match "(?i)\b(deploy|publish_release|upload_release|create_release)\b" -or $ciContent -match "(?i)uses:\s*[^@\s]+/(gh-release|action-gh-release|release-action)") {
    throw "CI workflow contains deployment/publishing steps. CI must remain strictly a quality gate."
}

# 7. R8 exclusion check
if ($ciContent -match "(?i)(full-identity-clean-clone|full-release-metadata|full-documented-demo|clean-clone|release-metadata|demo)") {
    throw "CI workflow illegally references R8 gates or concepts."
}

# 8. Artifact upload validation
if (-not ($ciContent -match "actions/upload-artifact@")) {
    throw "CI workflow missing actions/upload-artifact step."
}

# 9. Cross-platform command preflight check in check-contract.json
$contractFile = Join-Path $repoRoot "scripts\check-contract.json"
if (-not (Test-Path $contractFile)) {
    throw "Missing scripts/check-contract.json"
}
$contract = Get-Content $contractFile -Raw | ConvertFrom-Json
$fullGates = $contract.gates | Where-Object { $_.profiles -contains "Full" }

foreach ($g in $fullGates) {
    if ($g.command -match "\.cmd$|\.bat$") {
        throw "Gate '$($g.id)' specifies Windows-only command '$($g.command)' in check-contract.json"
    }
}

Write-Host "PASS: CI workflow satisfies mechanical structure, exact SDK equality with global.json ($expectedSdkVersion), 40-character SHA pinning, and semantic parity requirements." -ForegroundColor Green
