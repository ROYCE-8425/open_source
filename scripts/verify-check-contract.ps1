# scripts/verify-check-contract.ps1 - BR001-R3 Comprehensive Contract Verifier
$ErrorActionPreference = 'Stop'

if (-not (Test-Path ".git")) {
    throw "verify-check-contract.ps1 must be executed from the repository root"
}

$repoRoot = (Get-Item .).FullName

function Assert-SafePathChain {
    param([string]$Path, [string]$ExpectedRoot)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootFullPath = [System.IO.Path]::GetFullPath($ExpectedRoot)

    if (-not (Test-Path $rootFullPath)) {
        throw "Security violation: Root '$rootFullPath' does not exist"
    }
    $rootItem = Get-Item $rootFullPath -Force
    if ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Security violation: Root '$rootFullPath' is a reparse point"
    }

    $rootWithSep = $rootFullPath
    if (-not $rootWithSep.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $rootWithSep += [System.IO.Path]::DirectorySeparatorChar
    }
    if (-not $fullPath.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase) -and -not $fullPath.Equals($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Security violation: Path '$fullPath' escapes expected root '$rootFullPath'"
    }

    $current = $fullPath
    while ($true) {
        if (Test-Path $current) {
            $item = Get-Item $current -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Security violation: Path '$current' in ancestor chain is a reparse point"
            }
        }
        if ($current.Equals($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parentDir = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parentDir) -or $parentDir -eq $current) {
            break
        }
        $current = $parentDir
    }
    return $fullPath
}

[void](Assert-SafePathChain $repoRoot $repoRoot)
$qgRootDir = Join-Path $repoRoot "artifacts\quality-gate"
if (-not (Test-Path $qgRootDir)) {
    New-Item -ItemType Directory -Path $qgRootDir -Force | Out-Null
}
[void](Assert-SafePathChain $qgRootDir $repoRoot)

$expectedLocks = @(
    "src\DXOS.Api\packages.lock.json",
    "src\DXOS.AppHost\packages.lock.json",
    "src\DXOS.Application\packages.lock.json",
    "src\DXOS.Domain\packages.lock.json",
    "src\DXOS.Infrastructure\packages.lock.json",
    "src\DXOS.Workflows\packages.lock.json",
    "tests\DXOS.Architecture.Tests\packages.lock.json",
    "tests\DXOS.Integration.Tests\packages.lock.json",
    "tests\DXOS.Unit.Tests\packages.lock.json"
)

function Get-StrictLockSnapshot {
    $snapshot = @{}
    $allLocks = Get-ChildItem -Path $repoRoot -Filter "packages.lock.json" -Recurse -File
    if ($allLocks.Count -ne 9) {
        throw "Assertion failed: Expected exactly 9 packages.lock.json files, found $($allLocks.Count)"
    }
    foreach ($lock in $expectedLocks) {
        $fullPath = Join-Path $repoRoot $lock
        if (-not (Test-Path $fullPath)) {
            throw "Assertion failed: Missing required lock file: $lock"
        }
        $file = Get-Item $fullPath
        $hash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash.ToLower()
        $snapshot[$lock] = @{ Length = $file.Length; Hash = $hash }
    }
    return $snapshot
}

function Escape-Argument($arg) {
    if ([string]::IsNullOrEmpty($arg)) { return '""' }
    if ($arg -match "[\s`"]") {
        $escaped = [regex]::Replace($arg, '(\\+)(?=")', '$1$1')
        $escaped = $escaped -replace '"', '\"'
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
        return "`"$escaped`""
    }
    return $arg
}

$script:trackedProcs = @()
$verifierTemp = $null

function Register-Proc($p) {
    if ($null -ne $p) {
        $script:trackedProcs += $p
    }
}

function Stop-AllTrackedProcs {
    foreach ($p in $script:trackedProcs) {
        if ($null -ne $p) {
            try {
                if (-not $p.HasExited) {
                    $kill = Start-Process -FilePath "taskkill.exe" -ArgumentList "/T", "/F", "/PID", "$($p.Id)" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                    if ($null -ne $kill) {
                        try { [void]$kill.WaitForExit(5000) } catch {}
                        $kill.Dispose()
                    }
                    $p.Kill()
                }
            } catch {}
            try { $p.Dispose() } catch {}
        }
    }
}

function Invoke-CheckBounded {
    param(
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 60,
        [string]$WorkingDir = $repoRoot
    )

    $stepGuid = [guid]::NewGuid().ToString()
    $outTemp = Join-Path $verifierTemp "bounded-${stepGuid}.tmp.out"
    $errTemp = Join-Path $verifierTemp "bounded-${stepGuid}.tmp.err"
    $proc = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()

    try {
        $encodedArgs = ($ArgumentList | ForEach-Object { Escape-Argument $_ }) -join ' '

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.WorkingDirectory = $WorkingDir
        $psi.Arguments = $encodedArgs
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null
        Register-Proc $proc

        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $completed = $proc.WaitForExit($TimeoutSeconds * 1000)
        $sw.Stop()

        if (-not $completed) {
            try {
                $kill = Start-Process -FilePath "taskkill.exe" -ArgumentList "/T", "/F", "/PID", "$($proc.Id)" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                if ($null -ne $kill) {
                    try { [void]$kill.WaitForExit(5000) } catch {}
                    $kill.Dispose()
                }
                $proc.Kill()
            } catch {}
            throw "Process timed out after ${TimeoutSeconds}s"
        }

        [void]$stdoutTask.Wait(5000)
        [void]$stderrTask.Wait(5000)

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $exitCode = $proc.ExitCode

        return @{
            ExitCode = $exitCode
            Stdout = $stdout
            Stderr = $stderr
            DurationSeconds = [Math]::Round($sw.Elapsed.TotalSeconds, 2)
        }
    } finally {
        if ($null -ne $proc) {
            try { $proc.Dispose() } catch {}
        }
        if (Test-Path $outTemp) { Remove-Item $outTemp -Force -ErrorAction SilentlyContinue }
        if (Test-Path $errTemp) { Remove-Item $errTemp -Force -ErrorAction SilentlyContinue }
    }
}

try {
    Write-Host "Initializing Verifier Lifecycle..." -ForegroundColor Cyan

    $preQGItems = @{}
    foreach ($f in (Get-ChildItem -Path $qgRootDir -File)) {
        $preQGItems[$f.FullName] = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    }

    $guid = [guid]::NewGuid().ToString()
    $verifierTemp = Join-Path $repoRoot "artifacts\quality-gate\verifier-temp-$guid"
    [void](Assert-SafePathChain $verifierTemp $repoRoot)
    New-Item -ItemType Directory -Path $verifierTemp -Force | Out-Null

    $initialLockSnapshot = Get-StrictLockSnapshot
    $initialContractHash = (Get-FileHash -Path (Join-Path $repoRoot "scripts\check-contract.json") -Algorithm SHA256).Hash.ToLower()

    $initialSourceHashes = @{}
    $sourceFiles = @(
        "src\DXOS.Api\Program.cs",
        "src\DXOS.AppHost\Program.cs",
        "src\DXOS.Application\Class1.cs",
        "src\DXOS.Domain\Class1.cs",
        "src\DXOS.Infrastructure\Class1.cs",
        "src\DXOS.Workflows\Class1.cs"
    )
    foreach ($sf in $sourceFiles) {
        $initialSourceHashes[$sf] = (Get-FileHash -Path (Join-Path $repoRoot $sf) -Algorithm SHA256).Hash.ToLower()
    }

    Write-Host "Running Verifier Assertions..." -ForegroundColor Green

    # Fixtures inside verifierTemp
    $mockContractPath = Join-Path $verifierTemp "mock-contract.json"
    $mockContractRel = $mockContractPath.Substring($repoRoot.Length).TrimStart('\')

    $captureScriptPath = Join-Path $verifierTemp "capture-args.ps1"
    $captureScriptRel = $captureScriptPath.Substring($repoRoot.Length).TrimStart('\')
    $argsOutPath = Join-Path $verifierTemp "args.txt"
    $argsOutRel = $argsOutPath.Substring($repoRoot.Length).TrimStart('\')

    $spawnScriptPath = Join-Path $verifierTemp "spawn-tree.ps1"
    $spawnScriptRel = $spawnScriptPath.Substring($repoRoot.Length).TrimStart('\')
    $descendantPidPath = Join-Path $verifierTemp "descendant-pid.txt"

    # Write capture-args.ps1
    $captureCode = @"
`$ErrorActionPreference = 'Stop'
[IO.File]::WriteAllLines('$argsOutPath', `$args, [System.Text.Encoding]::UTF8)
exit 0
"@
    [IO.File]::WriteAllText($captureScriptPath, $captureCode, [System.Text.Encoding]::UTF8)

    # Write spawn-tree.ps1 (spawns child process and records child PID)
    $spawnCode = @"
`$ErrorActionPreference = 'Stop'
`$child = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 30' -PassThru -WindowStyle Hidden
[IO.File]::WriteAllText('$descendantPidPath', "`$(`$child.Id)", [System.Text.Encoding]::UTF8)
Start-Sleep -Seconds 30
exit 0
"@
    [IO.File]::WriteAllText($spawnScriptPath, $spawnCode, [System.Text.Encoding]::UTF8)

    $mockContract = @{
        schemaVersion = "1.0"
        profiles = @{
            MissingToolTest = @{ gates = @("missing-tool", "missing-tool-later-gate") }
            Native42Test = @{ gates = @("native-42", "should-not-run") }
            TimeoutTest = @{ gates = @("timeout-test", "timeout-later-gate") }
            ArgumentTest = @{ gates = @("argument-test") }
            OutputTest = @{ gates = @("untruncated-output") }
        }
        gates = @(
            @{
                id = "missing-tool"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-Command", "exit 0")
                requiredTools = @("this-tool-does-not-exist-12345")
                requiredFiles = @()
                expectedOutputs = @()
            },
            @{
                id = "missing-tool-later-gate"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-Command", "exit 0")
                requiredTools = @()
                requiredFiles = @()
                expectedOutputs = @()
            },
            @{
                id = "native-42"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-Command", "exit 42")
                requiredTools = @()
                requiredFiles = @()
                expectedOutputs = @()
            },
            @{
                id = "should-not-run"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-Command", "exit 0")
                requiredTools = @()
                requiredFiles = @()
                expectedOutputs = @()
            },
            @{
                id = "timeout-test"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 2
                command = "powershell.exe"
                arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $spawnScriptRel)
                requiredTools = @()
                requiredFiles = @($spawnScriptRel)
                expectedOutputs = @()
            },
            @{
                id = "timeout-later-gate"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-Command", "exit 0")
                requiredTools = @()
                requiredFiles = @()
                expectedOutputs = @()
            },
            @{
                id = "argument-test"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @(
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    $captureScriptRel,
                    "",
                    "with space",
                    "with `"quote`"",
                    "trailing\"
                )
                requiredTools = @()
                requiredFiles = @($captureScriptRel)
                expectedOutputs = @($argsOutRel)
            },
            @{
                id = "untruncated-output"
                status = "READY"
                task = "BR001-R3.0"
                activation = "always"
                timeoutSeconds = 60
                command = "powershell.exe"
                arguments = @(
                    "-NoProfile",
                    "-Command",
                    "Write-Output 'FIRST_OUT_SENTINEL'; 1..10000 | ForEach-Object { Write-Output `$_ }; Write-Output 'LAST_OUT_SENTINEL'; Write-Output 'SECRET_KEY=12345'; [Console]::Error.WriteLine('FIRST_ERR_SENTINEL'); [Console]::Error.WriteLine('LAST_ERR_SENTINEL')"
                )
                requiredTools = @()
                requiredFiles = @()
                expectedOutputs = @()
            }
        )
    }

    $mockContract | ConvertTo-Json -Depth 10 | Set-Content -Path $mockContractPath -Encoding UTF8

    # 1. Missing Tool Preflight Test with Machine-Readable Evidence & Field Assertions
    $missingToolEvidencePath = Join-Path $verifierTemp "evidence-missing-tool-test.json"
    $missingToolEvidenceRel = $missingToolEvidencePath.Substring($repoRoot.Length).TrimStart('\')

    $resMissing = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "MissingToolTest",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $missingToolEvidenceRel
    )

    if ($resMissing.ExitCode -ne 1) {
        throw "Assertion failed: Missing tool preflight should exit 1, got $($resMissing.ExitCode)"
    }
    if (-not (Test-Path $missingToolEvidencePath)) {
        throw "Assertion failed: Machine-readable evidence was not generated for missing tool preflight"
    }
    $missingEvJson = Get-Content $missingToolEvidencePath -Raw | ConvertFrom-Json
    if ($missingEvJson.overallResult -ne "FAIL" -or $missingEvJson.firstFailure -ne "missing-tool") {
        throw "Assertion failed: Missing tool evidence overallResult='$($missingEvJson.overallResult)', firstFailure='$($missingEvJson.firstFailure)'"
    }
    if ($missingEvJson.gates.Count -ne 1 -or $missingEvJson.gates[0].id -ne "missing-tool") {
        throw "Assertion failed: Missing tool evidence contains unexpected gate executions ($($missingEvJson.gates.Count) gates)"
    }
    if ($missingEvJson.gates[0].processState -ne "preflight-failure") {
        throw "Assertion failed: Missing tool processState is '$($missingEvJson.gates[0].processState)' (expected 'preflight-failure')"
    }
    if ($missingEvJson.gates[0].exitCode -ne -1) {
        throw "Assertion failed: Missing tool exitCode is $($missingEvJson.gates[0].exitCode) (expected -1)"
    }
    if (-not $missingEvJson.gates[0].error.Contains("this-tool-does-not-exist-12345")) {
        throw "Assertion failed: Missing tool error does not name missing tool"
    }
    $missingLaterGate = $missingEvJson.gates | Where-Object { $_.id -eq "missing-tool-later-gate" }
    if ($null -ne $missingLaterGate) {
        throw "Assertion failed: Dependent gate 'missing-tool-later-gate' ran after preflight failure"
    }
    Write-Host "[PASS] Missing tool preflight generates machine-readable evidence (exitCode=-1, processState=preflight-failure) and blocks dependent gates" -ForegroundColor Green

    # 2. Native Exit 42 and Later Success Masking
    $native42EvidencePath = Join-Path $verifierTemp "evidence-native-42-test.json"
    $native42EvidenceRel = $native42EvidencePath.Substring($repoRoot.Length).TrimStart('\')

    $res42 = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "Native42Test",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $native42EvidenceRel
    )
    if ($res42.ExitCode -ne 1) {
        throw "Assertion failed: Native 42 test runner should exit 1, got $($res42.ExitCode)"
    }
    if (-not (Test-Path $native42EvidencePath)) {
        throw "Assertion failed: Machine-readable evidence was not generated for native 42 test"
    }
    $native42Ev = Get-Content $native42EvidencePath -Raw | ConvertFrom-Json
    if ($native42Ev.overallResult -ne "FAIL" -or $native42Ev.firstFailure -ne "native-42") {
        throw "Assertion failed: Native 42 overallResult='$($native42Ev.overallResult)', firstFailure='$($native42Ev.firstFailure)'"
    }
    if ($native42Ev.gates.Count -ne 1 -or $native42Ev.gates[0].id -ne "native-42") {
        throw "Assertion failed: Native 42 evidence gate count mismatch ($($native42Ev.gates.Count))"
    }
    if ($native42Ev.gates[0].exitCode -ne 42) {
        throw "Assertion failed: Native 42 gate exit code is $($native42Ev.gates[0].exitCode) (expected 42)"
    }
    $shouldNotRunGate = $native42Ev.gates | Where-Object { $_.id -eq "should-not-run" }
    if ($null -ne $shouldNotRunGate) {
        throw "Assertion failed: Gate 'should-not-run' was executed after native-42 failure"
    }
    Write-Host "[PASS] Native exit 42 captured, firstFailure=native-42, exitCode=42 in evidence, and downstream gate omitted" -ForegroundColor Green

    # 3. Executable Timeout Verifier with Process-Tree & Unrelated-Process Proof
    $sentinelProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "Start-Sleep -Seconds 60" -PassThru -WindowStyle Hidden
    Register-Proc $sentinelProc
    $sentinelPid = $sentinelProc.Id

    $timeoutEvidencePath = Join-Path $verifierTemp "evidence-timeout-test.json"
    $timeoutEvidenceRel = $timeoutEvidencePath.Substring($repoRoot.Length).TrimStart('\')

    $resTimeout = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "TimeoutTest",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $timeoutEvidenceRel
    )

    if ($resTimeout.ExitCode -ne 1) {
        throw "Assertion failed: Timeout test should exit 1, got $($resTimeout.ExitCode)"
    }
    if (-not (Test-Path $timeoutEvidencePath)) {
        throw "Assertion failed: Timeout evidence file missing"
    }
    $timeoutEv = Get-Content $timeoutEvidencePath -Raw | ConvertFrom-Json
    $timeoutGate = $timeoutEv.gates | Where-Object { $_.id -eq "timeout-test" } | Select-Object -First 1
    if ($null -eq $timeoutGate) { throw "Assertion failed: timeout-test gate missing from evidence" }
    if ($timeoutGate.exitCode -ne -1 -or $timeoutGate.error -ne "TIMEOUT" -or $timeoutGate.processState -ne "timeout") {
        throw "Assertion failed: Timeout gate properties mismatch (exitCode=$($timeoutGate.exitCode), error=$($timeoutGate.error), processState=$($timeoutGate.processState))"
    }
    if ($timeoutGate.durationSeconds -lt 0.8 -or $timeoutGate.durationSeconds -gt 5.0) {
        throw "Assertion failed: Timeout duration not bounded (was $($timeoutGate.durationSeconds)s)"
    }
    if ($timeoutEv.gates.Count -ne 1) {
        throw "Assertion failed: Downstream gate ran after timeout (gates count = $($timeoutEv.gates.Count))"
    }

    # Verify descendant process was spawned and is now fully terminated (no orphan)
    if (-not (Test-Path $descendantPidPath)) {
        throw "Assertion failed: Descendant PID file was not created by timeout fixture"
    }
    $descendantPid = [int](Get-Content $descendantPidPath -Raw).Trim()
    $orphanCheck = Get-Process -Id $descendantPid -ErrorAction SilentlyContinue
    if ($null -ne $orphanCheck) {
        throw "Assertion failed: Orphan process detected! PID $descendantPid is still alive after timeout cleanup"
    }

    # Verify unrelated sentinel process remained alive throughout timeout cleanup
    $sentinelCheck = Get-Process -Id $sentinelPid -ErrorAction SilentlyContinue
    if ($null -eq $sentinelCheck) {
        throw "Assertion failed: Unrelated sentinel process PID $sentinelPid was killed during timeout cleanup!"
    }
    try { $sentinelProc.Kill(); $sentinelProc.Dispose() } catch {}

    Write-Host "[PASS] Timeout execution bounded ($($timeoutGate.durationSeconds)s), process-tree terminated, no orphans, unrelated process survived, blocked later gates" -ForegroundColor Green

    # 4. Argument Vector Boundaries Comparison
    if (Test-Path $argsOutPath) { Remove-Item $argsOutPath -Force }
    $argEvidencePath = Join-Path $verifierTemp "evidence-arg-test.json"
    $argEvidenceRel = $argEvidencePath.Substring($repoRoot.Length).TrimStart('\')

    $resArgs = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "ArgumentTest",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $argEvidenceRel
    )
    if ($resArgs.ExitCode -ne 0) {
        throw "Assertion failed: Argument test should exit 0, got $($resArgs.ExitCode)"
    }
    if (-not (Test-Path $argsOutPath)) {
        throw "Assertion failed: Argument output file was not created"
    }
    $capturedArgs = [IO.File]::ReadAllLines($argsOutPath)
    $expectedArgs = @(
        "",
        "with space",
        "with `"quote`"",
        "trailing\"
    )
    if ($capturedArgs.Length -ne $expectedArgs.Length) {
        throw "Assertion failed: Argument count mismatch (expected $($expectedArgs.Length), got $($capturedArgs.Length))"
    }
    for ($i = 0; $i -lt $expectedArgs.Length; $i++) {
        if ($capturedArgs[$i] -ne $expectedArgs[$i]) {
            throw "Assertion failed: Argument [$i] mismatch (expected '$($expectedArgs[$i])', got '$($capturedArgs[$i])')"
        }
    }
    Write-Host "[PASS] Argument boundaries survive with exact count, order, and values" -ForegroundColor Green

    # 5. Unrelated Solution Shielding & Non-Root Directory Shielding
    $unrelatedFixture = Join-Path $verifierTemp "unrelated-fixture"
    New-Item -ItemType Directory -Path $unrelatedFixture -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $unrelatedFixture "Unrelated.sln"), "Microsoft Visual Studio Solution File", [System.Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $unrelatedFixture "Unrelated.csproj"), "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>", [System.Text.Encoding]::UTF8)

    $realCheckScriptAbs = Join-Path $repoRoot "scripts\check.ps1"
    $resUnrelated = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $realCheckScriptAbs,
        "-Profile", "Foundation"
    ) -WorkingDir $unrelatedFixture

    if ($resUnrelated.ExitCode -ne 1) {
        throw "Assertion failed: check.ps1 executed outside root should exit 1 (got $($resUnrelated.ExitCode))"
    }
    if (-not $resUnrelated.Stderr.Contains("check.ps1 must be executed from the repository root")) {
        throw "Assertion failed: Stderr did not contain repository root guard message (got '$($resUnrelated.Stderr)')"
    }
    if ((Test-Path (Join-Path $unrelatedFixture "bin")) -or (Test-Path (Join-Path $unrelatedFixture "obj"))) {
        throw "Assertion failed: Unrelated project was restored/built"
    }
    Write-Host "[PASS] Unrelated solution and non-root directory shielding (real runner root guard verified)" -ForegroundColor Green

    # 6. Untruncated Output, Exact 10k Line Ordering, Secret Redaction, and Stderr Sentinels
    $outputEvPath = Join-Path $verifierTemp "evidence-output-test.json"
    $outputEvRel = $outputEvPath.Substring($repoRoot.Length).TrimStart('\')

    $resOutput = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "OutputTest",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $outputEvRel
    )
    if ($resOutput.ExitCode -ne 0) {
        throw "Assertion failed: Output test should exit 0, got $($resOutput.ExitCode)"
    }
    if (-not (Test-Path $outputEvPath)) {
        throw "Assertion failed: Output evidence file missing"
    }
    $outputEv = Get-Content $outputEvPath -Raw | ConvertFrom-Json
    $outputGate = $outputEv.gates | Where-Object { $_.id -eq "untruncated-output" } | Select-Object -First 1
    $outputFilePath = Join-Path $verifierTemp $outputGate.outputPath
    if (-not (Test-Path $outputFilePath)) {
        throw "Assertion failed: Gate output log file missing ($outputFilePath)"
    }
    $outLines = [IO.File]::ReadAllLines($outputFilePath)

    # Validate stdout boundary sentinels and full 1..10000 sequence
    $stdoutStartIdx = [Array]::IndexOf($outLines, "--- STDOUT ---")
    $stderrStartIdx = [Array]::IndexOf($outLines, "--- STDERR ---")
    if ($stdoutStartIdx -eq -1 -or $stderrStartIdx -eq -1 -or $stderrStartIdx -le $stdoutStartIdx) {
        throw "Assertion failed: Output file missing STDOUT/STDERR boundary headers"
    }

    $firstOutSentinelIdx = [Array]::IndexOf($outLines, "FIRST_OUT_SENTINEL")
    $lastOutSentinelIdx = [Array]::IndexOf($outLines, "LAST_OUT_SENTINEL")
    if ($firstOutSentinelIdx -eq -1 -or $lastOutSentinelIdx -eq -1) {
        throw "Assertion failed: Output missing FIRST_OUT_SENTINEL or LAST_OUT_SENTINEL"
    }

    $numberCount = $lastOutSentinelIdx - $firstOutSentinelIdx - 1
    if ($numberCount -ne 10000) {
        throw "Assertion failed: Expected exactly 10,000 numeric lines between sentinels, found $numberCount"
    }

    # Verify complete ordering for every single element from 1 to 10,000
    for ($i = 1; $i -le 10000; $i++) {
        $expectedLine = "$i"
        $actualLine = $outLines[$firstOutSentinelIdx + $i]
        if ($actualLine -ne $expectedLine) {
            throw "Assertion failed: Line sequence mismatch at position $i (expected '$expectedLine', got '$actualLine')"
        }
    }

    # Secret redaction check
    $rawText = [IO.File]::ReadAllText($outputFilePath)
    if ($rawText.Contains("SECRET_KEY=12345")) {
        throw "Assertion failed: Secret was not redacted from log file"
    }
    if (-not $rawText.Contains("SECRET_KEY=***REDACTED***")) {
        throw "Assertion failed: Redaction marker missing from log file"
    }

    # Stderr sentinels check
    if (-not $rawText.Contains("FIRST_ERR_SENTINEL") -or -not $rawText.Contains("LAST_ERR_SENTINEL")) {
        throw "Assertion failed: Stderr sentinels missing from log file"
    }
    Write-Host "[PASS] Output untruncated (complete 10,000 sequential lines verified), boundary sentinels confirmed, secrets redacted, stderr captured" -ForegroundColor Green

    # Common expected 6 gates sequence for Runtime and Full
    $expectedSixGates = @(
        @{ id = "foundation-restore"; exitCode = 0 },
        @{ id = "foundation-format"; exitCode = 0 },
        @{ id = "foundation-build"; exitCode = 0 },
        @{ id = "foundation-openspec"; exitCode = 0 },
        @{ id = "foundation-hygiene"; exitCode = 0 },
        @{ id = "runtime-unit-tests"; exitCode = 1 }
    )

    # 7. Real Foundation Profile (Exact 5 gates)
    $foundEvTestPath = Join-Path $verifierTemp "evidence-foundation-test.json"
    $foundEvTestRel = $foundEvTestPath.Substring($repoRoot.Length).TrimStart('\')

    $resFound = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "Foundation",
        "-EvidencePath", $foundEvTestRel
    )
    if ($resFound.ExitCode -ne 0) {
        throw "Assertion failed: Real Foundation profile should exit 0, got $($resFound.ExitCode). Stderr: $($resFound.Stderr)"
    }
    if (-not (Test-Path $foundEvTestPath)) { throw "Assertion failed: Missing Foundation test evidence file" }
    $foundEv = Get-Content $foundEvTestPath -Raw | ConvertFrom-Json
    if ($foundEv.overallResult -ne "PASS" -or $null -ne $foundEv.firstFailure) {
        throw "Assertion failed: Foundation evidence overallResult is '$($foundEv.overallResult)' (expected PASS)"
    }
    if ($foundEv.gates.Count -ne 5) {
        throw "Assertion failed: Expected exactly 5 gates in Foundation profile, got $($foundEv.gates.Count))"
    }
    for ($i = 0; $i -lt 5; $i++) {
        if ($foundEv.gates[$i].id -ne $expectedSixGates[$i].id -or $foundEv.gates[$i].exitCode -ne 0) {
            throw "Assertion failed: Foundation gate [$i] mismatch ($($foundEv.gates[$i].id), exit=$($foundEv.gates[$i].exitCode))"
        }
    }
    Write-Host "[PASS] Real Foundation exit 0, overallResult PASS, exact 5 gates passed in order" -ForegroundColor Green

    # 8. Real Runtime Profile (Exact 6 gates in order)
    $runtimeEvTestPath = Join-Path $verifierTemp "evidence-runtime-test.json"
    $runtimeEvTestRel = $runtimeEvTestPath.Substring($repoRoot.Length).TrimStart('\')

    $resRuntime = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "Runtime",
        "-EvidencePath", $runtimeEvTestRel
    )
    if ($resRuntime.ExitCode -ne 1) {
        throw "Assertion failed: Real Runtime profile should exit 1, got $($resRuntime.ExitCode)"
    }
    if (-not (Test-Path $runtimeEvTestPath)) { throw "Assertion failed: Missing Runtime test evidence file" }
    $runtimeEv = Get-Content $runtimeEvTestPath -Raw | ConvertFrom-Json
    if ($runtimeEv.overallResult -ne "FAIL" -or $runtimeEv.firstFailure -ne "runtime-unit-tests") {
        throw "Assertion failed: Runtime evidence failure mismatch (overallResult='$($runtimeEv.overallResult)', firstFailure='$($runtimeEv.firstFailure)')"
    }
    if ($runtimeEv.gates.Count -ne 6) {
        throw "Assertion failed: Runtime gate count is $($runtimeEv.gates.Count) (expected exactly 6)"
    }
    for ($i = 0; $i -lt 6; $i++) {
        if ($runtimeEv.gates[$i].id -ne $expectedSixGates[$i].id) {
            throw "Assertion failed: Runtime gate [$i] ID is '$($runtimeEv.gates[$i].id)' (expected '$($expectedSixGates[$i].id)')"
        }
        if ($runtimeEv.gates[$i].exitCode -ne $expectedSixGates[$i].exitCode) {
            throw "Assertion failed: Runtime gate [$i] exitCode is $($runtimeEv.gates[$i].exitCode) (expected $($expectedSixGates[$i].exitCode))"
        }
    }
    Write-Host "[PASS] Real Runtime failure boundary: exact 6 gates in order, firstFailure at runtime-unit-tests (exit 1, overallResult FAIL)" -ForegroundColor Green

    # 9. Real Full Profile via Default Invocation (no -Profile) (Exact 6 gates in order)
    $fullEvTestPath = Join-Path $verifierTemp "evidence-full-test.json"
    $fullEvTestRel = $fullEvTestPath.Substring($repoRoot.Length).TrimStart('\')

    $resFull = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-EvidencePath", $fullEvTestRel
    )
    if ($resFull.ExitCode -ne 1) {
        throw "Assertion failed: Real Full profile (default) should exit 1, got $($resFull.ExitCode)"
    }
    if (-not (Test-Path $fullEvTestPath)) { throw "Assertion failed: Missing Full test evidence file" }
    $fullEv = Get-Content $fullEvTestPath -Raw | ConvertFrom-Json
    if ($fullEv.profile -ne "Full") {
        throw "Assertion failed: Default check.ps1 profile is '$($fullEv.profile)' (expected 'Full')"
    }
    if ($fullEv.overallResult -ne "FAIL" -or $fullEv.firstFailure -ne "runtime-unit-tests") {
        throw "Assertion failed: Full evidence failure mismatch (overallResult='$($fullEv.overallResult)', firstFailure='$($fullEv.firstFailure)')"
    }
    if ($fullEv.gates.Count -ne 6) {
        throw "Assertion failed: Full gate count is $($fullEv.gates.Count) (expected exactly 6)"
    }
    for ($i = 0; $i -lt 6; $i++) {
        if ($fullEv.gates[$i].id -ne $expectedSixGates[$i].id) {
            throw "Assertion failed: Full gate [$i] ID is '$($fullEv.gates[$i].id)' (expected '$($expectedSixGates[$i].id)')"
        }
        if ($fullEv.gates[$i].exitCode -ne $expectedSixGates[$i].exitCode) {
            throw "Assertion failed: Full gate [$i] exitCode is $($fullEv.gates[$i].exitCode) (expected $($expectedSixGates[$i].exitCode))"
        }
    }
    Write-Host "[PASS] Real Full default profile failure boundary: exact 6 gates in order, firstFailure at runtime-unit-tests (exit 1, overallResult FAIL)" -ForegroundColor Green

    # 10. Immutability Verification: 9 Locks, Production Contract, and 6 Source Files
    $finalLockSnapshot = Get-StrictLockSnapshot
    foreach ($lock in $expectedLocks) {
        $init = $initialLockSnapshot[$lock]
        $fin = $finalLockSnapshot[$lock]
        if ($init.Hash -ne $fin.Hash -or $init.Length -ne $fin.Length) {
            throw "Assertion failed: Lock file mutated ($lock)"
        }
    }
    $finalContractHash = (Get-FileHash -Path (Join-Path $repoRoot "scripts\check-contract.json") -Algorithm SHA256).Hash.ToLower()
    if ($initialContractHash -ne $finalContractHash) {
        throw "Assertion failed: check-contract.json mutated during test execution"
    }
    foreach ($sf in $sourceFiles) {
        $finHash = (Get-FileHash -Path (Join-Path $repoRoot $sf) -Algorithm SHA256).Hash.ToLower()
        if ($initialSourceHashes[$sf] -ne $finHash) {
            throw "Assertion failed: Source file mutated ($sf)"
        }
    }
    Write-Host "[PASS] Immutability of exactly 9 locks, production contract, and 6 source files proven" -ForegroundColor Green

    Write-Host "`nAll verifier assertions passed safely!" -ForegroundColor Green
} finally {
    Stop-AllTrackedProcs
    if ($null -ne $verifierTemp -and (Test-Path $verifierTemp)) {
        try {
            [void](Assert-SafePathChain $verifierTemp $repoRoot)
            Remove-Item -Path $verifierTemp -Recurse -Force -ErrorAction Stop
        } catch {
            throw "Fatal cleanup failure on $verifierTemp : $_"
        }
        if (Test-Path $verifierTemp) {
            throw "Fatal cleanup failure: $verifierTemp still exists after cleanup"
        }
    }

    # Verify quality-gate inventory after cleanup matches pre-inventory exactly
    $postQGItems = @{}
    foreach ($f in (Get-ChildItem -Path $qgRootDir -File)) {
        $postQGItems[$f.FullName] = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash
    }

    if ($preQGItems.Count -ne $postQGItems.Count) {
        throw "Residual artifact leak in quality-gate root: expected $($preQGItems.Count) files, found $($postQGItems.Count)"
    }
    foreach ($k in $preQGItems.Keys) {
        if (-not $postQGItems.ContainsKey($k) -or $preQGItems[$k] -ne $postQGItems[$k]) {
            throw "Quality-gate file mutated during verifier execution: $k"
        }
    }
}
exit 0
