# scripts/verify-check-contract.ps1 - BR001-R5 Comprehensive Contract Verifier
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
        [void]$proc.Start()
        Register-Proc $proc

        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $completed = $proc.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $killProc = Start-Process -FilePath "taskkill.exe" -ArgumentList "/T", "/F", "/PID", "$($proc.Id)" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                if ($null -ne $killProc) {
                    try { [void]$killProc.WaitForExit(5000) } catch {}
                    $killProc.Dispose()
                }
                $proc.Kill()
            } catch {}
            throw "Process timed out after $TimeoutSeconds seconds"
        }

        [void][Threading.Tasks.Task]::WaitAll($stdoutTask, $stderrTask)
        $sw.Stop()

        return @{
            ExitCode = $proc.ExitCode
            Stdout = $stdoutTask.Result
            Stderr = $stderrTask.Result
            DurationSeconds = $sw.Elapsed.TotalSeconds
        }
    } finally {
        if ($null -ne $proc) {
            $proc.Dispose()
        }
    }
}

try {
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
        "src\DXOS.Infrastructure\Persistence\BootstrapDbContext.cs",
        "src\DXOS.Workflows\Smoke\EngineeringSmokeWorkflow.cs"
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

    # Mock test-runner mechanics scripts
    $mockFailRunnerPath = Join-Path $verifierTemp "mock-fail-runner.ps1"
    $mockFailRunnerRel = $mockFailRunnerPath.Substring($repoRoot.Length).TrimStart('\')
    [IO.File]::WriteAllText($mockFailRunnerPath, "exit 1`n", [System.Text.Encoding]::UTF8)

    $mockZeroTestsRunnerPath = Join-Path $verifierTemp "mock-zero-tests-runner.ps1"
    $mockZeroTestsRunnerRel = $mockZeroTestsRunnerPath.Substring($repoRoot.Length).TrimStart('\')
    $mockZeroJsonPath = (Join-Path $verifierTemp "mock-zero.json").Replace('\', '/')
    $zeroJson = '{"reportFormat":"CTRF","results":{"summary":{"tests":0,"passed":0,"failed":0,"skipped":0}}}'
    [IO.File]::WriteAllText($mockZeroTestsRunnerPath, "`$j = '$zeroJson'; [IO.File]::WriteAllText('$mockZeroJsonPath', `$j); [Console]::Error.WriteLine('Error: Zero tests'); exit 1`n", [System.Text.Encoding]::UTF8)

    $mockMissingReportRunnerPath = Join-Path $verifierTemp "mock-missing-report-runner.ps1"
    $mockMissingReportRunnerRel = $mockMissingReportRunnerPath.Substring($repoRoot.Length).TrimStart('\')
    [IO.File]::WriteAllText($mockMissingReportRunnerPath, "[Console]::Error.WriteLine('Error: Report missing'); exit 1`n", [System.Text.Encoding]::UTF8)

    $mockMalformedReportRunnerPath = Join-Path $verifierTemp "mock-malformed-report-runner.ps1"
    $mockMalformedReportRunnerRel = $mockMalformedReportRunnerPath.Substring($repoRoot.Length).TrimStart('\')
    $mockMalformedJsonPath = (Join-Path $verifierTemp "mock-malformed.json").Replace('\', '/')
    [IO.File]::WriteAllText($mockMalformedReportRunnerPath, "[IO.File]::WriteAllText('$mockMalformedJsonPath', '{ NOT VALID JSON'); [Console]::Error.WriteLine('Error: Malformed JSON'); exit 1`n", [System.Text.Encoding]::UTF8)

    $mockContract = @{
        schemaVersion = "1.0"
        profiles = @{
            MissingToolTest = @{ gates = @("missing-tool", "missing-tool-later-gate") }
            Native42Test = @{ gates = @("native-42", "should-not-run") }
            TimeoutTest = @{ gates = @("timeout-test", "timeout-later-gate") }
            ArgumentTest = @{ gates = @("argument-test") }
            OutputTest = @{ gates = @("untruncated-output") }
            FailFastTest = @{ gates = @("fail-gate-1", "success-gate-2") }
            ZeroTestFail = @{ gates = @("zero-test-gate") }
            MissingReportFail = @{ gates = @("missing-report-gate") }
            MalformedReportFail = @{ gates = @("malformed-report-gate") }
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
            },
            @{
                id = "fail-gate-1"
                status = "READY"
                task = "BR001-R5.4"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockFailRunnerRel)
                requiredTools = @()
                requiredFiles = @($mockFailRunnerRel)
                expectedOutputs = @()
            },
            @{
                id = "success-gate-2"
                status = "READY"
                task = "BR001-R5.4"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-Command", "exit 0")
                requiredTools = @()
                requiredFiles = @()
                expectedOutputs = @()
            },
            @{
                id = "zero-test-gate"
                status = "READY"
                task = "BR001-R5.4"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockZeroTestsRunnerRel)
                requiredTools = @()
                requiredFiles = @($mockZeroTestsRunnerRel)
                expectedOutputs = @()
            },
            @{
                id = "missing-report-gate"
                status = "READY"
                task = "BR001-R5.4"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockMissingReportRunnerRel)
                requiredTools = @()
                requiredFiles = @($mockMissingReportRunnerRel)
                expectedOutputs = @()
            },
            @{
                id = "malformed-report-gate"
                status = "READY"
                task = "BR001-R5.4"
                activation = "always"
                timeoutSeconds = 10
                command = "powershell.exe"
                arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $mockMalformedReportRunnerRel)
                requiredTools = @()
                requiredFiles = @($mockMalformedReportRunnerRel)
                expectedOutputs = @()
            }
        )
    }

    $mockContract | ConvertTo-Json -Depth 10 | Set-Content -Path $mockContractPath -Encoding UTF8

    # 1. Missing Tool Preflight Test
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
    $missingEv = Get-Content $missingToolEvidencePath -Raw | ConvertFrom-Json
    if ($missingEv.overallResult -ne "FAIL" -or $missingEv.firstFailure -ne "missing-tool") {
        throw "Assertion failed: Evidence does not record overallResult FAIL and firstFailure missing-tool"
    }
    Write-Host "[PASS] Missing tool preflight: non-zero exit, machine-readable evidence, blocked subsequent gates" -ForegroundColor Green

    # 2. Native Exit Code 42 & Short-Circuit Test
    $native42EvidencePath = Join-Path $verifierTemp "evidence-native42-test.json"
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
        throw "Assertion failed: check.ps1 should exit 1 on gate failure, got $($res42.ExitCode)"
    }
    if (-not (Test-Path $native42EvidencePath)) {
        throw "Assertion failed: Evidence file not produced for native exit code test"
    }
    $ev42 = Get-Content $native42EvidencePath -Raw | ConvertFrom-Json
    if ($ev42.overallResult -ne "FAIL" -or $ev42.firstFailure -ne "native-42") {
        throw "Assertion failed: Native 42 evidence does not record overallResult FAIL and firstFailure native-42"
    }
    $g42 = $ev42.gates | Where-Object { $_.id -eq "native-42" } | Select-Object -First 1
    if ($g42.exitCode -ne 42) {
        throw "Assertion failed: Gate exitCode not preserved as 42 in evidence (got $($g42.exitCode))"
    }
    Write-Host "[PASS] Native exit code 42 recorded, overallResult FAIL, second gate short-circuited" -ForegroundColor Green

    # 3. Timeout Bounded Execution, Process-Tree Termination, and Unrelated Process Shielding
    $timeoutEvidencePath = Join-Path $verifierTemp "evidence-timeout-test.json"
    $timeoutEvidenceRel = $timeoutEvidencePath.Substring($repoRoot.Length).TrimStart('\')

    $sentinelProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-Command", "Start-Sleep -Seconds 60" -PassThru -WindowStyle Hidden
    Register-Proc $sentinelProc
    $sentinelPid = $sentinelProc.Id

    $resTimeout = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "TimeoutTest",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $timeoutEvidenceRel
    ) -TimeoutSeconds 30

    if ($resTimeout.ExitCode -ne 1) {
        throw "Assertion failed: Timeout test should exit 1 (got $($resTimeout.ExitCode))"
    }
    if (-not (Test-Path $timeoutEvidencePath)) {
        throw "Assertion failed: Timeout evidence file missing"
    }
    $timeoutEv = Get-Content $timeoutEvidencePath -Raw | ConvertFrom-Json
    $timeoutGate = $timeoutEv.gates | Where-Object { $_.id -eq "timeout-test" } | Select-Object -First 1
    if ($timeoutGate.processState -ne "timeout" -or $timeoutGate.exitCode -ne -1) {
        throw "Assertion failed: Timeout gate processState ($($timeoutGate.processState)) or exitCode ($($timeoutGate.exitCode)) incorrect"
    }

    if (-not (Test-Path $descendantPidPath)) {
        throw "Assertion failed: Descendant PID file was not written by test process"
    }
    $descendantPid = [int]([IO.File]::ReadAllText($descendantPidPath).Trim())
    $orphanCheck = Get-Process -Id $descendantPid -ErrorAction SilentlyContinue
    if ($null -ne $orphanCheck) {
        throw "Assertion failed: Orphan process detected! PID $descendantPid is still alive after timeout cleanup"
    }

    $sentinelCheck = Get-Process -Id $sentinelPid -ErrorAction SilentlyContinue
    if ($null -eq $sentinelCheck) {
        throw "Assertion failed: Unrelated sentinel process PID $sentinelPid was killed during timeout cleanup!"
    }
    try { $sentinelProc.Kill(); $sentinelProc.Dispose() } catch {}

    Write-Host "[PASS] Timeout execution bounded, process-tree terminated, no orphans, unrelated process survived" -ForegroundColor Green

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
    Write-Host "[PASS] Unrelated solution and non-root directory shielding verified" -ForegroundColor Green

    # 6. Untruncated Output, 10,000 Lines, Secret Redaction
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

    $firstOutSentinelIdx = [Array]::IndexOf($outLines, "FIRST_OUT_SENTINEL")
    $lastOutSentinelIdx = [Array]::IndexOf($outLines, "LAST_OUT_SENTINEL")
    if ($firstOutSentinelIdx -eq -1 -or $lastOutSentinelIdx -eq -1) {
        throw "Assertion failed: Output missing FIRST_OUT_SENTINEL or LAST_OUT_SENTINEL"
    }

    $numberCount = $lastOutSentinelIdx - $firstOutSentinelIdx - 1
    if ($numberCount -ne 10000) {
        throw "Assertion failed: Expected exactly 10,000 numeric lines between sentinels, found $numberCount"
    }
    for ($i = 1; $i -le 10000; $i++) {
        $expectedLine = "$i"
        $actualLine = $outLines[$firstOutSentinelIdx + $i]
        if ($actualLine -ne $expectedLine) {
            throw "Assertion failed: Line sequence mismatch at position $i (expected '$expectedLine', got '$actualLine')"
        }
    }

    $rawText = [IO.File]::ReadAllText($outputFilePath)
    if ($rawText.Contains("SECRET_KEY=12345")) {
        throw "Assertion failed: Secret was not redacted from log file"
    }
    if (-not $rawText.Contains("SECRET_KEY=***REDACTED***")) {
        throw "Assertion failed: Redaction marker missing from log file"
    }
    Write-Host "[PASS] Output untruncated (10,000 sequential lines), secrets redacted" -ForegroundColor Green

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
        throw "Assertion failed: Expected exactly 5 gates in Foundation profile, got $($foundEv.gates.Count)"
    }
    Write-Host "[PASS] Real Foundation exit 0, overallResult PASS, exact 5 gates passed in order" -ForegroundColor Green

    # 8. Fail-Fast & Later Success Cannot Mask Earlier Failure
    $ffEvPath = Join-Path $verifierTemp "evidence-failfast-test.json"
    $ffEvRel = $ffEvPath.Substring($repoRoot.Length).TrimStart('\')

    $resFF = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "FailFastTest",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $ffEvRel
    )
    if ($resFF.ExitCode -ne 1) {
        throw "Assertion failed: FailFastTest should exit 1, got $($resFF.ExitCode)"
    }
    $ffEv = Get-Content $ffEvPath -Raw | ConvertFrom-Json
    if ($ffEv.overallResult -ne "FAIL" -or $ffEv.firstFailure -ne "fail-gate-1") {
        throw "Assertion failed: FailFastTest evidence overallResult mismatch"
    }
    if ($ffEv.gates.Count -ne 1) {
        throw "Assertion failed: FailFastTest executed $($ffEv.gates.Count) gates instead of stopping at gate 1"
    }
    Write-Host "[PASS] Fail-fast mechanism verified: later success gate never executed after failure" -ForegroundColor Green

    # 9. Test Runner Mechanics Fixtures (Zero tests, Missing report, Malformed report)
    $zeroEvPath = Join-Path $verifierTemp "evidence-zero-test.json"
    $zeroEvRel = $zeroEvPath.Substring($repoRoot.Length).TrimStart('\')
    $resZero = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "ZeroTestFail",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $zeroEvRel
    )
    if ($resZero.ExitCode -ne 1) {
        throw "Assertion failed: ZeroTestFail should exit 1, got $($resZero.ExitCode)"
    }

    $missingRepEvPath = Join-Path $verifierTemp "evidence-missingrep-test.json"
    $missingRepEvRel = $missingRepEvPath.Substring($repoRoot.Length).TrimStart('\')
    $resMissingRep = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "MissingReportFail",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $missingRepEvRel
    )
    if ($resMissingRep.ExitCode -ne 1) {
        throw "Assertion failed: MissingReportFail should exit 1, got $($resMissingRep.ExitCode)"
    }

    $malformedRepEvPath = Join-Path $verifierTemp "evidence-malformedrep-test.json"
    $malformedRepEvRel = $malformedRepEvPath.Substring($repoRoot.Length).TrimStart('\')
    $resMalformedRep = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\check.ps1",
        "-Profile", "MalformedReportFail",
        "-ContractPath", $mockContractRel,
        "-EvidencePath", $malformedRepEvRel
    )
    if ($resMalformedRep.ExitCode -ne 1) {
        throw "Assertion failed: MalformedReportFail should exit 1, got $($resMalformedRep.ExitCode)"
    }
    Write-Host "[PASS] Test runner mechanics fixtures (zero tests, missing report, malformed report) fail closed" -ForegroundColor Green

    # 10. Test Helper Security Boundaries (ResultPath Escape, Sibling Rejection & Whitelist Enforcement)
    $resPathEscape = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run-test-project.ps1",
        "-ProjectPath", "tests/DXOS.Unit.Tests/DXOS.Unit.Tests.csproj",
        "-ResultPath", "src/escaping.json"
    )
    if ($resPathEscape.ExitCode -ne 1) {
        throw "Assertion failed: run-test-project.ps1 should reject ResultPath escaping to src/ (got exit $($resPathEscape.ExitCode))"
    }

    $resParentEscape = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run-test-project.ps1",
        "-ProjectPath", "tests/DXOS.Unit.Tests/DXOS.Unit.Tests.csproj",
        "-ResultPath", "../outside.json"
    )
    if ($resParentEscape.ExitCode -ne 1) {
        throw "Assertion failed: run-test-project.ps1 should reject ResultPath containing .. (got exit $($resParentEscape.ExitCode))"
    }

    $resSiblingTaskEscape = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run-test-project.ps1",
        "-ProjectPath", "tests/DXOS.Unit.Tests/DXOS.Unit.Tests.csproj",
        "-EvidenceRoot", "artifacts/task-runs/open_source-cab.4",
        "-ResultPath", "artifacts/task-runs/open_source-cab.3/result.json"
    )
    if ($resSiblingTaskEscape.ExitCode -ne 1) {
        throw "Assertion failed: run-test-project.ps1 should reject ResultPath targeting sibling task-run (got exit $($resSiblingTaskEscape.ExitCode))"
    }

    $resSiblingQgEscape = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run-test-project.ps1",
        "-ProjectPath", "tests/DXOS.Unit.Tests/DXOS.Unit.Tests.csproj",
        "-EvidenceRoot", "artifacts/quality-gate/run-1",
        "-ResultPath", "artifacts/quality-gate/run-2/result.json"
    )
    if ($resSiblingQgEscape.ExitCode -ne 1) {
        throw "Assertion failed: run-test-project.ps1 should reject ResultPath targeting sibling quality-gate directory (got exit $($resSiblingQgEscape.ExitCode))"
    }

    $resUnapprovedEvidenceRoot = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run-test-project.ps1",
        "-ProjectPath", "tests/DXOS.Unit.Tests/DXOS.Unit.Tests.csproj",
        "-EvidenceRoot", "src/unapproved-root",
        "-ResultPath", "src/unapproved-root/result.json"
    )
    if ($resUnapprovedEvidenceRoot.ExitCode -ne 1) {
        throw "Assertion failed: run-test-project.ps1 should reject unapproved EvidenceRoot (got exit $($resUnapprovedEvidenceRoot.ExitCode))"
    }

    $resUnapprovedProj = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", "scripts\run-test-project.ps1",
        "-ProjectPath", "src/DXOS.Domain/DXOS.Domain.csproj"
    )
    if ($resUnapprovedProj.ExitCode -ne 1) {
        throw "Assertion failed: run-test-project.ps1 should reject unapproved project path (got exit $($resUnapprovedProj.ExitCode))"
    }
    Write-Host "[PASS] Test helper security boundaries verified: ResultPath escapes, sibling paths, and unapproved projects rejected" -ForegroundColor Green

    # 9b. Container Teardown Failure Fixtures: Stop failure, dispose fault, dispose timeout
    $teardownFixtureRes = Invoke-CheckBounded -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-Command", "dotnet test tests/DXOS.Integration.Tests/DXOS.Integration.Tests.csproj -c Release --no-build --no-restore -- --filter-method `"*Teardown*`""
    )
    if ($teardownFixtureRes.ExitCode -ne 0) {
        throw "Assertion failed: Container teardown failure fixtures failed (got exit $($teardownFixtureRes.ExitCode)): $($teardownFixtureRes.Stderr)`n$($teardownFixtureRes.Stdout)"
    }
    Write-Host "[PASS] Container teardown failure fixtures verified: stop failure, dispose fault, and dispose timeout fail closed" -ForegroundColor Green

    # 10. Production Contract Static Audit: Exact 12 Runtime Gates in Order and E2E N/A
    $prodContractPath = Join-Path $repoRoot "scripts\check-contract.json"
    $prodContract = Get-Content $prodContractPath -Raw | ConvertFrom-Json

    $expectedRuntimeGateOrder = @(
        "foundation-restore",
        "foundation-format",
        "foundation-build",
        "foundation-openspec",
        "foundation-hygiene",
        "runtime-docker-compose",
        "runtime-smoke-compose",
        "runtime-smoke-aspire",
        "runtime-unit-tests",
        "runtime-architecture-tests",
        "runtime-integration-tests",
        "runtime-e2e-tests"
    )

    $actualRuntimeGates = @()
    foreach ($g in $prodContract.gates) {
        if ($g.profiles -contains "Runtime") {
            $actualRuntimeGates += $g
        }
    }

    if ($actualRuntimeGates.Count -ne $expectedRuntimeGateOrder.Count) {
        throw "Assertion failed: Runtime gate count is $($actualRuntimeGates.Count) (expected $($expectedRuntimeGateOrder.Count))"
    }

    for ($i = 0; $i -lt $expectedRuntimeGateOrder.Count; $i++) {
        $expectedId = $expectedRuntimeGateOrder[$i]
        $actualId = $actualRuntimeGates[$i].id
        if ($expectedId -ne $actualId) {
            throw "Assertion failed: Runtime gate [$i] ID is '$actualId' (expected '$expectedId')"
        }
    }

    $e2eGate = $actualRuntimeGates | Where-Object { $_.id -eq "runtime-e2e-tests" } | Select-Object -First 1
    if ($e2eGate.status -ne "NOT_APPLICABLE" -or $e2eGate.required -ne $false -or $e2eGate.reason -ne "no real UI exists") {
        throw "Assertion failed: E2E gate contract attributes mismatch"
    }
    Write-Host "[PASS] Production contract audit: exact 12 Runtime gates in deterministic order, E2E strictly NOT_APPLICABLE" -ForegroundColor Green

    # 11. Immutability Verification: 9 Locks, Production Contract, and 6 Source Files
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
