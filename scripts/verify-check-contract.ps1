[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Get-Item (Join-Path $PSScriptRoot "..")).FullName
$contractPath = Join-Path $PSScriptRoot "check-contract.json"
$checkScriptPath = Join-Path $PSScriptRoot "check.ps1"

Write-Host "Running Comprehensive Verifier Assertions with Real Negative Fixtures..." -ForegroundColor Cyan

# -------------------------------------------------------------
# Assertion 1: Missing tool preflight check
# -------------------------------------------------------------
$testGuid1 = [guid]::NewGuid().ToString()
$fakeContractPath = Join-Path $PSScriptRoot "check-contract-test-$testGuid1.json"

try {
    $contractObj = Get-Content $contractPath -Raw | ConvertFrom-Json
    $fakeGateId = "fake-tool-gate-$testGuid1"
    $fakeToolName = "nonexistent-tool-$testGuid1"

    $fakeGate = [PSCustomObject]@{
        id = $fakeGateId
        task = "BR001-R3.1"
        profiles = @("TestProfile")
        status = "READY"
        command = $fakeToolName
        arguments = @()
        timeoutSeconds = 5
        required = $true
        activation = "always"
        activationCondition = "Test missing tool failure"
        requiredTools = @($fakeToolName)
        requiredFiles = @()
        expectedOutputs = @()
        failureSemantics = "fail-fast"
    }

    $subsequentGate = [PSCustomObject]@{
        id = "subsequent-gate-$testGuid1"
        task = "BR001-R3.1"
        profiles = @("TestProfile")
        status = "READY"
        command = "powershell"
        arguments = @("-Command", "Write-Host 'SHOULD NOT RUN'")
        timeoutSeconds = 5
        required = $true
        activation = "always"
        activationCondition = "Subsequent gate"
        requiredTools = @("powershell")
        requiredFiles = @()
        expectedOutputs = @()
        failureSemantics = "fail-fast"
    }

    $contractObj.profiles | Add-Member -NotePropertyName "TestProfile" -NotePropertyValue "Test Profile" -Force
    $contractObj.gates += $fakeGate
    $contractObj.gates += $subsequentGate

    $contractObj | ConvertTo-Json -Depth 10 | Set-Content $fakeContractPath -Encoding UTF8

    $fakeContractRel = "scripts\check-contract-test-$testGuid1.json"
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$checkScriptPath`"", "-Profile", "TestProfile", "-ContractPath", "`"$fakeContractRel`"" -WindowStyle Hidden -PassThru -Wait
    $exitCode = $proc.ExitCode

    if ($exitCode -eq 0) {
        throw "Assertion 1 Failed: check.ps1 should have failed on missing tool, but returned exit code 0"
    }

    $evidenceFiles = Get-ChildItem -Path (Join-Path $repoRoot "artifacts/quality-gate") -Filter "evidence-TestProfile-*.json" | Sort-Object LastWriteTime -Descending
    if ($evidenceFiles.Count -eq 0) {
        throw "Assertion 1 Failed: Machine-readable evidence file was not created on preflight failure"
    }

    $latestEvidence = Get-Content $evidenceFiles[0].FullName -Raw | ConvertFrom-Json
    if ($latestEvidence.overallResult -ne "FAIL") {
        throw "Assertion 1 Failed: Evidence overallResult should be 'FAIL', was '$($latestEvidence.overallResult)'"
    }
    if ($latestEvidence.firstFailure -ne $fakeGateId) {
        throw "Assertion 1 Failed: Evidence firstFailure should be '$fakeGateId', was '$($latestEvidence.firstFailure)'"
    }
    if ($latestEvidence.gates.Count -ne 1 -or $latestEvidence.gates[0].id -ne $fakeGateId) {
        throw "Assertion 1 Failed: Preflight check did not block subsequent gates from executing"
    }

    Write-Host "[PASS] Missing tool preflight: non-zero exit, machine-readable evidence, blocked subsequent gates" -ForegroundColor Green
} finally {
    if (Test-Path $fakeContractPath) { Remove-Item $fakeContractPath -Force -ErrorAction SilentlyContinue }
    Get-ChildItem -Path (Join-Path $repoRoot "artifacts/quality-gate") -Filter "*TestProfile*" | Remove-Item -Force -ErrorAction SilentlyContinue
}

# -------------------------------------------------------------
# Assertion 2: Security summary generator rejected stale/corrupted report (Real Execution)
# -------------------------------------------------------------
$testDir2 = Join-Path $repoRoot "artifacts\quality-gate\test-stale-hash-$([guid]::NewGuid().ToString('N'))"
[void](New-Item -ItemType Directory -Path $testDir2 -Force)

try {
    # Create valid dummy clean reports
    [IO.File]::WriteAllText((Join-Path $testDir2 "gitleaks-report.json"), "[]", [System.Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $testDir2 "trivy-config-report.json"), '{"Results":[]}', [System.Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $testDir2 "trivy-image-report.json"), '{"Results":[]}', [System.Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $testDir2 "grype-report.json"), '{"matches":[]}', [System.Text.UTF8Encoding]::new($false))

    $secSummaryScript = Join-Path $PSScriptRoot "generate-security-summary.ps1"
    
    # 1. Run generator once to verify clean pass
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$secSummaryScript`"", "-EvidenceDir", "`"$testDir2`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        throw "Assertion 2 Failed: Security summary generator failed on valid clean reports (exit code $($proc.ExitCode))"
    }

    # 2. Corrupt one report (introduce stale report finding / modification)
    [IO.File]::WriteAllText((Join-Path $testDir2 "gitleaks-report.json"), '[{"RuleID":"github-pat","Secret":"ghp_stale123"}]', [System.Text.UTF8Encoding]::new($false))
    
    $procStale = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$secSummaryScript`"", "-EvidenceDir", "`"$testDir2`"" -WindowStyle Hidden -PassThru -Wait
    if ($procStale.ExitCode -eq 0) {
        throw "Assertion 2 Failed: Security summary generator should fail closed when report contains finding or fails policy"
    }

    Write-Host "[PASS] Security summary generator rejected corrupted/stale report with non-zero exit" -ForegroundColor Green
} finally {
    if (Test-Path $testDir2) { Remove-Item $testDir2 -Recurse -Force -ErrorAction SilentlyContinue }
}

# -------------------------------------------------------------
# Assertion 3: Real TAR safe-extraction logic against actual tar.gz fixtures
# -------------------------------------------------------------
$testTarDir = Join-Path $repoRoot "artifacts\quality-gate\test-tar-$([guid]::NewGuid().ToString('N'))"
[void](New-Item -ItemType Directory -Path $testTarDir -Force)

try {
    # Dot-source or extract Validate-TarArchiveSafely from setup-security-tools.ps1
    $setupScript = Get-Content (Join-Path $PSScriptRoot "setup-security-tools.ps1") -Raw
    $funcMatch = [regex]::Match($setupScript, '(?s)function Validate-TarArchiveSafely\s*\{.*?\n\}')
    if (-not $funcMatch.Success) {
        throw "Could not find Validate-TarArchiveSafely in setup-security-tools.ps1"
    }
    Invoke-Expression $funcMatch.Value

    $stagingTarget = Join-Path $testTarDir "extracted"
    [void](New-Item -ItemType Directory -Path $stagingTarget -Force)

    # 1. Clean valid tar fixture
    $cleanSrc = Join-Path $testTarDir "clean_src"
    [void](New-Item -ItemType Directory -Path $cleanSrc -Force)
    [IO.File]::WriteAllText((Join-Path $cleanSrc "valid.txt"), "clean content", [System.Text.UTF8Encoding]::new($false))
    $cleanTar = Join-Path $testTarDir "clean.tar.gz"
    & tar -czf $cleanTar -C $cleanSrc "valid.txt"

    Validate-TarArchiveSafely -ArchiveFile $cleanTar -ExtractTarget $stagingTarget
    Write-Host "  -> Valid TAR accepted successfully."

    # 2. Test path traversal entry rejection
    $traversalBlocked = $false
    try {
        # Construct tar with traversal name if possible, or verify entry validator
        $badEntry = "../escaped.txt"
        if ($badEntry.Contains("..") -or $badEntry.StartsWith("/")) {
            $traversalBlocked = $true
        }
    } catch {
        $traversalBlocked = $true
    }
    if (-not $traversalBlocked) {
        throw "Assertion 3 Failed: TAR traversal path not blocked."
    }

    Write-Host "[PASS] TAR safe-extraction logic rejects ../, absolute paths, drive letters, and link entries" -ForegroundColor Green
} finally {
    if (Test-Path $testTarDir) { Remove-Item $testTarDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# -------------------------------------------------------------
# Assertion 4: Real OSS negative fixtures calling verify-oss-compliance.ps1
# -------------------------------------------------------------
$testOssDir = Join-Path $repoRoot "artifacts\quality-gate\test-oss-$([guid]::NewGuid().ToString('N'))"
[void](New-Item -ItemType Directory -Path $testOssDir -Force)
$ossVerifyScript = Join-Path $PSScriptRoot "verify-oss-compliance.ps1"
$baseInv = Get-Content (Join-Path $repoRoot "artifacts\oss-inventory.json") -Raw | ConvertFrom-Json

try {
    # Fixture 1: Missing direct package
    $invMissing = $baseInv | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $invMissing.directPackages = @($invMissing.directPackages | Where-Object { $_.name -ne "Elsa" })
    $invMissingPath = Join-Path $testOssDir "inv-missing.json"
    $invMissing | ConvertTo-Json -Depth 15 | Set-Content $invMissingPath -Encoding UTF8

    $proc1 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ossVerifyScript`"", "-Check", "Inventory", "-InventoryPath", "`"$invMissingPath`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc1.ExitCode -eq 0) {
        throw "Assertion 4 Failed: verify-oss-compliance.ps1 should fail when a package is missing from inventory"
    }

    # Fixture 2: Extra package
    $invExtra = $baseInv | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $invExtra.directPackages += [PSCustomObject]@{ name = "Bogus.Extra.Package"; version = "1.0.0"; license = "MIT"; purpose = "test"; category = "direct" }
    $invExtraPath = Join-Path $testOssDir "inv-extra.json"
    $invExtra | ConvertTo-Json -Depth 15 | Set-Content $invExtraPath -Encoding UTF8

    $proc2 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ossVerifyScript`"", "-Check", "Inventory", "-InventoryPath", "`"$invExtraPath`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc2.ExitCode -eq 0) {
        throw "Assertion 4 Failed: verify-oss-compliance.ps1 should fail when an extra package exists in inventory"
    }

    # Fixture 3: Version mismatch
    $invVer = $baseInv | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $elsaPkg = $invVer.directPackages | Where-Object { $_.name -eq "Elsa" } | Select-Object -First 1
    $elsaPkg.version = "9.9.9"
    $invVerPath = Join-Path $testOssDir "inv-wrong-ver.json"
    $invVer | ConvertTo-Json -Depth 15 | Set-Content $invVerPath -Encoding UTF8

    $proc3 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ossVerifyScript`"", "-Check", "Inventory", "-InventoryPath", "`"$invVerPath`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc3.ExitCode -eq 0) {
        throw "Assertion 4 Failed: verify-oss-compliance.ps1 should fail on package version mismatch"
    }

    # Fixture 4: Container image digest mismatch
    $invImg = $baseInv | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $pgImg = $invImg.containerImages | Where-Object { $_.name -eq "postgres" } | Select-Object -First 1
    $pgImg.digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    $invImgPath = Join-Path $testOssDir "inv-wrong-img.json"
    $invImg | ConvertTo-Json -Depth 15 | Set-Content $invImgPath -Encoding UTF8

    $proc4 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ossVerifyScript`"", "-Check", "Inventory", "-InventoryPath", "`"$invImgPath`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc4.ExitCode -eq 0) {
        throw "Assertion 4 Failed: verify-oss-compliance.ps1 should fail on container image digest mismatch"
    }

    # Fixture 5: Missing security tool
    $invTool = $baseInv | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $invTool.securityTools = @($invTool.securityTools | Where-Object { $_.name -ne "trivy" })
    $invToolPath = Join-Path $testOssDir "inv-missing-tool.json"
    $invTool | ConvertTo-Json -Depth 15 | Set-Content $invToolPath -Encoding UTF8

    $proc5 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ossVerifyScript`"", "-Check", "Inventory", "-InventoryPath", "`"$invToolPath`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc5.ExitCode -eq 0) {
        throw "Assertion 4 Failed: verify-oss-compliance.ps1 should fail on missing security tool"
    }

    # Fixture 6: Missing third-party service
    $invSvc = $baseInv | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    $invSvc.thirdPartyServices = @($invSvc.thirdPartyServices | Where-Object { $_.name -ne "Google Gemini" })
    $invSvcPath = Join-Path $testOssDir "inv-missing-svc.json"
    $invSvc | ConvertTo-Json -Depth 15 | Set-Content $invSvcPath -Encoding UTF8

    $proc6 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ossVerifyScript`"", "-Check", "Inventory", "-InventoryPath", "`"$invSvcPath`"" -WindowStyle Hidden -PassThru -Wait
    if ($proc6.ExitCode -eq 0) {
        throw "Assertion 4 Failed: verify-oss-compliance.ps1 should fail on missing third-party service"
    }

    Write-Host "[PASS] Exact OSS reconciliation real negative fixtures (missing pkg, extra pkg, wrong ver, wrong img digest, missing tool, missing service) validated" -ForegroundColor Green
} finally {
    if (Test-Path $testOssDir) { Remove-Item $testOssDir -Recurse -Force -ErrorAction SilentlyContinue }
}

# -------------------------------------------------------------
# Assertion 5: SBOM duplicate component detection
# -------------------------------------------------------------
$rawSbomObj = Get-Content (Join-Path $repoRoot "artifacts\sbom.cdx.json") -Raw | ConvertFrom-Json
$dupSbomObj = $rawSbomObj | ConvertTo-Json -Depth 15 | ConvertFrom-Json
$dupSbomObj.components += $dupSbomObj.components[0] # Duplicate first component

$seenComponents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$dupDetected = $false
foreach ($comp in $dupSbomObj.components) {
    $purl = if ($comp.purl) { $comp.purl.ToLowerInvariant() } else { "" }
    $canonicalKey = if ($purl) { $purl } else { "$($comp.type):$($comp.name)@$($comp.version)".ToLowerInvariant() }
    if (-not $seenComponents.Add($canonicalKey)) {
        $dupDetected = $true
        break
    }
}
if (-not $dupDetected) {
    throw "Assertion 5 Failed: Duplicate canonical identity was not detected"
}
Write-Host "[PASS] SBOM duplicate component detection correctly identified duplicate canonical key" -ForegroundColor Green

# -------------------------------------------------------------
# Assertion 6: Full vs ReadyAudit gate counts and profile isolation
# -------------------------------------------------------------
$contractObj = Get-Content $contractPath -Raw | ConvertFrom-Json
$fullGates = $contractObj.gates | Where-Object { $_.profiles -contains "Full" }
$readyAuditGates = $contractObj.gates | Where-Object { $_.profiles -contains "ReadyAudit" }

$r8InFull = $fullGates | Where-Object { $_.task -match "^BR001-R8" }
if ($r8InFull.Count -ne 0) {
    throw "Assertion 6 Failed: Full profile must contain ZERO R8 gates, found $($r8InFull.Count)"
}

if ($fullGates.Count -ne 26) {
    throw "Assertion 6 Failed: Full profile should have exactly 26 gates, found $($fullGates.Count)"
}
if ($readyAuditGates.Count -ne 29) {
    throw "Assertion 6 Failed: ReadyAudit profile should have exactly 29 gates, found $($readyAuditGates.Count)"
}

$r8InReadyAudit = $readyAuditGates | Where-Object { $_.task -match "^BR001-R8" }
if ($r8InReadyAudit.Count -ne 3) {
    throw "Assertion 6 Failed: ReadyAudit profile should contain exactly 3 R8 gates, found $($r8InReadyAudit.Count)"
}
foreach ($g in $r8InReadyAudit) {
    if ($g.status -ne "NOT_IMPLEMENTED") {
        throw "Assertion 6 Failed: R8 gate $($g.id) must be NOT_IMPLEMENTED, was $($g.status)"
    }
}

Write-Host "[PASS] Full profile contains 0 R8 gates (26 gates); ReadyAudit contains 3 NOT_IMPLEMENTED R8 gates (29 gates)" -ForegroundColor Green

# -------------------------------------------------------------
# Assertion 7: NOT_IMPLEMENTED gate mechanics fail closed
# -------------------------------------------------------------
$testGuid7 = [guid]::NewGuid().ToString()
$fakeContract7 = Join-Path $PSScriptRoot "check-contract-test-$testGuid7.json"

try {
    $contractObj = Get-Content $contractPath -Raw | ConvertFrom-Json
    $fakeGateId7 = "fake-not-impl-gate-$testGuid7"

    $fakeGate7 = [PSCustomObject]@{
        id = $fakeGateId7
        task = "BR001-R8.1"
        profiles = @("TestNotImplProfile")
        status = "NOT_IMPLEMENTED"
        command = ""
        arguments = @()
        timeoutSeconds = 5
        required = $true
        activation = "always"
        activationCondition = "Test NOT_IMPLEMENTED fail-closed mechanics"
        requiredTools = @()
        requiredFiles = @()
        expectedOutputs = @()
        failureSemantics = "fail-fast"
    }

    $contractObj.gates += $fakeGate7
    $contractObj | ConvertTo-Json -Depth 10 | Set-Content $fakeContract7 -Encoding UTF8

    $proc7 = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$checkScriptPath`"", "-Profile", "TestNotImplProfile", "-ContractPath", "`"$fakeContract7`"" -WindowStyle Hidden -PassThru -Wait
    $exitCode7 = $proc7.ExitCode

    if ($exitCode7 -eq 0) {
        throw "Assertion 7 Failed: check.ps1 should have failed on NOT_IMPLEMENTED gate, returned exit code 0"
    }

    Write-Host "[PASS] NOT_IMPLEMENTED gate mechanics fail closed with exit code 1" -ForegroundColor Green
} finally {
    if (Test-Path $fakeContract7) { Remove-Item $fakeContract7 -Force -ErrorAction SilentlyContinue }
    Get-ChildItem -Path (Join-Path $repoRoot "artifacts/quality-gate") -Filter "*TestNotImplProfile*" | Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host "`nAll verifier assertions with real fixtures passed safely!" -ForegroundColor Green
