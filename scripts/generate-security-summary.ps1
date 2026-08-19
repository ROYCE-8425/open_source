[CmdletBinding()]
param(
    [string]$EvidenceDir = "",
    [string]$ToolsDir = "",
    [string]$RunId = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Get-Item $PSScriptRoot\..).FullName

if (-not $ToolsDir) {
    $ToolsDir = Join-Path $repoRoot ".tools\security"
}
$ToolsDir = [System.IO.Path]::GetFullPath($ToolsDir)

if (-not $EvidenceDir) {
    $evidenceFullDir = Join-Path $repoRoot "artifacts\quality-gate"
} elseif ([System.IO.Path]::IsPathRooted($EvidenceDir)) {
    $evidenceFullDir = [System.IO.Path]::GetFullPath($EvidenceDir)
} else {
    $evidenceFullDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EvidenceDir))
}

$securityDir = Join-Path $repoRoot "artifacts\security"
if (-not (Test-Path $securityDir)) {
    [void](New-Item -ItemType Directory -Path $securityDir -Force)
}

$manifestPath = Join-Path $PSScriptRoot "security-tools.json"
if (-not (Test-Path $manifestPath)) {
    throw "Security manifest not found at: $manifestPath"
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

$platform = "windows-x64"
$exeExt = ".exe"
if ($IsLinux) {
    $platform = "linux-x64"
    $exeExt = ""
}

function Get-StrictToolInfo([string]$Name) {
    $toolDef = $manifest.tools | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $toolDef) { throw "Tool '$Name' not found in manifest" }
    $ver = $toolDef.version
    $art = $toolDef.artifacts.$platform
    $exePath = Join-Path $ToolsDir "$Name/$ver/$Name$exeExt"
    if (-not (Test-Path $exePath)) { throw "Binary not found for '$Name' at: $exePath" }
    $hash = (Get-FileHash -Path $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    return @{
        Name = $Name
        Version = $ver
        Path = $exePath
        Sha256 = $hash
        License = $toolDef.license
    }
}

$gitleaksTool = Get-StrictToolInfo "gitleaks"
$trivyTool = Get-StrictToolInfo "trivy"
$syftTool = Get-StrictToolInfo "syft"
$grypeTool = Get-StrictToolInfo "grype"

# 1. Verify required report files exist on disk
$gitleaksReport = Join-Path $evidenceFullDir "gitleaks-report.json"
$trivyConfigReport = Join-Path $evidenceFullDir "trivy-config-report.json"
$trivyImageReport = Join-Path $evidenceFullDir "trivy-image-report.json"
$sbomReport = Join-Path $repoRoot "artifacts\sbom.cdx.json"
$grypeReport = Join-Path $evidenceFullDir "grype-report.json"

$requiredFiles = @(
    @{ Path = $gitleaksReport; Name = "Gitleaks report" },
    @{ Path = $trivyConfigReport; Name = "Trivy config report" },
    @{ Path = $trivyImageReport; Name = "Trivy image report" },
    @{ Path = $sbomReport; Name = "Deliverable CycloneDX SBOM" },
    @{ Path = $grypeReport; Name = "Grype report" }
)

foreach ($rf in $requiredFiles) {
    if (-not (Test-Path $rf.Path)) {
        throw "Security summary generation failed: $($rf.Name) missing from disk at '$($rf.Path)'"
    }
}

# 2. Calculate current hashes directly from disk
$gitleaksHash = (Get-FileHash -Path $gitleaksReport -Algorithm SHA256).Hash
$trivyConfigHash = (Get-FileHash -Path $trivyConfigReport -Algorithm SHA256).Hash
$trivyImageHash = (Get-FileHash -Path $trivyImageReport -Algorithm SHA256).Hash
$sbomHash = (Get-FileHash -Path $sbomReport -Algorithm SHA256).Hash
$grypeHash = (Get-FileHash -Path $grypeReport -Algorithm SHA256).Hash

# 3. Parse and validate report contents
# Gitleaks
$glJson = Get-Content $gitleaksReport -Raw | ConvertFrom-Json
$glCount = if ($glJson) { $glJson.Count } else { 0 }
if ($glCount -ne 0) { throw "Gitleaks report contains $glCount leak finding(s)" }

# Trivy Config
$tcJson = Get-Content $trivyConfigReport -Raw | ConvertFrom-Json
$tcMisconfigs = 0
if ($tcJson.Results) {
    foreach ($r in $tcJson.Results) {
        if ($r.Misconfigurations) { $tcMisconfigs += $r.Misconfigurations.Count }
    }
}
if ($tcMisconfigs -ne 0) { throw "Trivy config report contains $tcMisconfigs HIGH/CRITICAL misconfiguration(s)" }

# Trivy Image
$tiJson = Get-Content $trivyImageReport -Raw | ConvertFrom-Json
$tiVulns = 0
if ($tiJson.Results) {
    foreach ($r in $tiJson.Results) {
        if ($r.Vulnerabilities) { $tiVulns += $r.Vulnerabilities.Count }
    }
}
if ($tiVulns -ne 0) { throw "Trivy image report contains $tiVulns HIGH/CRITICAL vulnerability(ies)" }

# SBOM
$sbomJson = Get-Content $sbomReport -Raw | ConvertFrom-Json
if ($sbomJson.bomFormat -ne "CycloneDX") { throw "SBOM bomFormat is not 'CycloneDX'" }
if (-not $sbomJson.components -or $sbomJson.components.Count -eq 0) { throw "SBOM components count is 0" }
if (-not $sbomJson.metadata -or -not $sbomJson.metadata.component -or $sbomJson.metadata.component.name -ne "dxos-api") {
    throw "SBOM metadata component does not identify deliverable 'dxos-api'"
}

$rawSbom = Get-Content $sbomReport -Raw
if ($rawSbom -match '(?i)(C:\\Users|/Users/|/home/[a-zA-Z0-9_-]+|OneDrive)' -and -not ($rawSbom -match '<USER_CACHE>')) {
    throw "SBOM contains private machine path leak"
}

# SBOM Canonical duplicate check
$sbomSeen = @{}
$sbomDuplicates = @()
foreach ($c in $sbomJson.components) {
    $purl = if ($c.purl) { $c.purl.ToLowerInvariant() } else { "" }
    $canonicalKey = if ($purl) { $purl } else { "$($c.type):$($c.name)@$($c.version)".ToLowerInvariant() }
    if ($sbomSeen.ContainsKey($canonicalKey)) {
        $sbomDuplicates += $canonicalKey
    } else {
        $sbomSeen[$canonicalKey] = $true
    }
}
if ($sbomDuplicates.Count -ne 0) {
    throw "SBOM duplicate validation failed: $($sbomDuplicates.Count) duplicate canonical component identities found ($($sbomDuplicates -join ', '))"
}

# Grype
$grJson = Get-Content $grypeReport -Raw | ConvertFrom-Json
$grMatches = if ($grJson.matches) { $grJson.matches.Count } else { 0 }
if ($grMatches -ne 0) { throw "Grype report contains $grMatches vulnerability match(es) at/above threshold" }

# 4. Query Scanner Database Evidence
$trivyVerOutput = & $trivyTool.Path version 2>&1 | Out-String
$trivyDbVersion = ""
$trivyDbUpdatedAt = ""
$trivyDbDownloadedAt = ""
$trivyCheckBundleDigest = ""

if ($trivyVerOutput -match "Vulnerability DB:\s*\r?\n\s*Version:\s*([^\r\n]+)") { $trivyDbVersion = $matches[1].Trim() }
if ($trivyVerOutput -match "UpdatedAt:\s*([^\r\n]+)") { $trivyDbUpdatedAt = $matches[1].Trim() }
if ($trivyVerOutput -match "DownloadedAt:\s*([^\r\n]+)") { $trivyDbDownloadedAt = $matches[1].Trim() }
if ($trivyVerOutput -match "Digest:\s*([^\r\n]+)") { $trivyCheckBundleDigest = $matches[1].Trim() }

$grypeDbStatusOutput = & $grypeTool.Path db status 2>&1 | Out-String
$grypeDbSchema = ""
$grypeDbBuilt = ""
$grypeDbChecksum = ""
$grypeDbStatus = ""

if ($grypeDbStatusOutput -match "Schema:\s*([^\r\n]+)") { $grypeDbSchema = $matches[1].Trim() }
if ($grypeDbStatusOutput -match "Built:\s*([^\r\n]+)") { $grypeDbBuilt = $matches[1].Trim() }
if ($grypeDbStatusOutput -match "From:\s*([^\r\n]+checksum=([^\r\n\s]+))") {
    $rawChecksum = $matches[2].Trim()
    $grypeDbChecksum = [System.Uri]::UnescapeDataString($rawChecksum)
}
if ($grypeDbStatusOutput -match "Status:\s*([^\r\n]+)") { $grypeDbStatus = $matches[1].Trim() }

# Sanitize raw outputs from any local machine paths
$sanitizedTrivyRaw = ($trivyVerOutput.Trim() -replace '(?i)[a-zA-Z]:\\[^ \r\n\t"]+\\(cache|AppData|Local|trivy)', '<USER_CACHE>/trivy')
$sanitizedGrypeRaw = ($grypeDbStatusOutput.Trim() -replace '(?i)[a-zA-Z]:\\[^ \r\n\t"]+\\(cache|AppData|Local|grype)', '<USER_CACHE>/grype')

$imageDigest = ""
try {
    $imgInspect = docker inspect --format="{{index .Id}}" dxos-api:0.1.0-spike 2>$null
    if ($imgInspect) { $imageDigest = $imgInspect.Trim() }
} catch {}

$activeRunId = if ($RunId -and -not [string]::IsNullOrWhiteSpace($RunId)) { $RunId } else { [guid]::NewGuid().ToString() }
$revisionSha = (git rev-parse HEAD).Trim()

$summary = @{
    schemaVersion = "1.0"
    runId = $activeRunId
    revisionSha = $revisionSha
    generatedAt = (Get-Date).ToString("o")
    deliverable = @{
        name = "dxos-api"
        version = "0.1.0-spike"
        imageName = "dxos-api:0.1.0-spike"
        imageDigest = $imageDigest
    }
    sbom = @{
        path = "artifacts/sbom.cdx.json"
        sha256 = $sbomHash
        format = $sbomJson.bomFormat
        specVersion = $sbomJson.specVersion
        componentCount = $sbomJson.components.Count
        duplicateCount = 0
        canonicalKeyRule = "purl (case-normalized) if present, else type:name@version (case-normalized)"
    }
    tools = @{
        gitleaks = @{ version = $gitleaksTool.Version; sha256 = $gitleaksTool.Sha256; license = $gitleaksTool.License }
        trivy = @{ version = $trivyTool.Version; sha256 = $trivyTool.Sha256; license = $trivyTool.License }
        syft = @{ version = $syftTool.Version; sha256 = $syftTool.Sha256; license = $syftTool.License }
        grype = @{ version = $grypeTool.Version; sha256 = $grypeTool.Sha256; license = $grypeTool.License }
    }
    scannerDatabases = @{
        trivy = @{
            vulnerabilityDbVersion = $trivyDbVersion
            updatedAt = $trivyDbUpdatedAt
            downloadedAt = $trivyDbDownloadedAt
            checkBundleDigest = $trivyCheckBundleDigest
            rawOutput = $sanitizedTrivyRaw
        }
        grype = @{
            schema = $grypeDbSchema
            built = $grypeDbBuilt
            checksum = $grypeDbChecksum
            status = $grypeDbStatus
            rawOutput = $sanitizedGrypeRaw
        }
    }
    reports = @{
        gitleaks = @{ path = "artifacts/quality-gate/gitleaks-report.json"; sha256 = $gitleaksHash; findings = $glCount }
        trivyConfig = @{ path = "artifacts/quality-gate/trivy-config-report.json"; sha256 = $trivyConfigHash; misconfigurations = $tcMisconfigs }
        trivyImage = @{ path = "artifacts/quality-gate/trivy-image-report.json"; sha256 = $trivyImageHash; vulnerabilities = $tiVulns }
        syftSbom = @{ path = "artifacts/sbom.cdx.json"; sha256 = $sbomHash; components = $sbomJson.components.Count }
        grype = @{ path = "artifacts/quality-gate/grype-report.json"; sha256 = $grypeHash; vulnerabilities = $grMatches }
    }
    policies = @{
        gitleaks = "zero-leaks"
        trivy = "zero-high-critical"
        grype = "fail-on-high"
    }
    dispositions = @{
        gitleaks = "PASS"
        trivyConfig = "PASS"
        trivyImage = "PASS"
        syftSbom = "PASS"
        grype = "PASS"
    }
    overallVerdict = "PASS"
}

# 5. Atomic write and validation
$stagingTemp = Join-Path $securityDir ".staging-summary-$([guid]::NewGuid().ToString('N')).tmp"
$summaryJson = $summary | ConvertTo-Json -Depth 15

# Assert no personal machine path leak
if ($summaryJson -match '(?i)(C:\\Users|/Users/|/home/[a-zA-Z0-9_-]+|OneDrive)' -and -not ($summaryJson -match '<USER_CACHE>')) {
    throw "Security summary contains private machine path leak!"
}

try {
    [System.IO.File]::WriteAllText($stagingTemp, $summaryJson, [System.Text.UTF8Encoding]::new($false))

    # Validate temporary file
    $readBack = Get-Content $stagingTemp -Raw | ConvertFrom-Json
    if ($readBack.overallVerdict -ne "PASS") { throw "Validation failed: overallVerdict is not PASS" }
    if ($readBack.runId -ne $activeRunId) { throw "Validation failed: runId mismatch in summary" }
    if ($readBack.reports.gitleaks.sha256 -ne $gitleaksHash) { throw "Validation failed: Gitleaks report hash mismatch" }
    if ($readBack.reports.trivyConfig.sha256 -ne $trivyConfigHash) { throw "Validation failed: Trivy config hash mismatch" }
    if ($readBack.reports.trivyImage.sha256 -ne $trivyImageHash) { throw "Validation failed: Trivy image hash mismatch" }
    if ($readBack.reports.syftSbom.sha256 -ne $sbomHash) { throw "Validation failed: SBOM hash mismatch" }
    if ($readBack.reports.grype.sha256 -ne $grypeHash) { throw "Validation failed: Grype report hash mismatch" }

    # Atomically replace final destinations
    $finalCommitted = Join-Path $securityDir "security-summary.json"
    $finalEvidence = Join-Path $evidenceFullDir "security-summary.json"

    # Write committed destination
    $commTemp = Join-Path $securityDir ".committed-summary-$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($commTemp, $summaryJson, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path $finalCommitted) {
        Remove-Item -Path $finalCommitted -Force
    }
    Move-Item -Path $commTemp -Destination $finalCommitted -Force

    # Write evidence destination
    $evTemp = Join-Path $evidenceFullDir ".ev-summary-$([guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($evTemp, $summaryJson, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path $finalEvidence) {
        Remove-Item -Path $finalEvidence -Force
    }
    Move-Item -Path $evTemp -Destination $finalEvidence -Force

    Write-Host "Atomically generated and verified security summary (RunId: $activeRunId) at $finalCommitted and $finalEvidence" -ForegroundColor Green
} finally {
    if (Test-Path $stagingTemp) {
        Remove-Item -Path $stagingTemp -Force -ErrorAction SilentlyContinue
    }
}
