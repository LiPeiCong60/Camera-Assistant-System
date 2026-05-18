param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [ValidateSet("all", "backend", "device", "mobile", "admin", "stage3", "stage4")]
    [string[]]$Target = @("all")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:Results = @()

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet("PASS", "FAIL", "SKIP")]
        [string]$Status,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:Results += [pscustomobject]@{
        Name = $Name
        Status = $Status
        Message = $Message
    }
}

function Resolve-ProjectCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command
        }
    }

    return $null
}

function Invoke-CheckCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$RelativeWorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string[]]$CommandCandidates,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $workingDirectory = Join-Path $ProjectRoot $RelativeWorkingDirectory
    if (-not (Test-Path -LiteralPath $workingDirectory)) {
        Add-CheckResult -Name $Name -Status "SKIP" -Message "Missing directory: $RelativeWorkingDirectory"
        return
    }

    $command = Resolve-ProjectCommand -Candidates $CommandCandidates
    if (-not $command) {
        Add-CheckResult -Name $Name -Status "SKIP" -Message "Missing command: $($CommandCandidates -join ' or ')"
        return
    }

    $commandPath = $command.Source
    if (-not $commandPath) {
        $commandPath = $command.Name
    }

    Write-Host "==> [$Name] $($command.Name) $($Arguments -join ' ')" -ForegroundColor Cyan
    Push-Location -LiteralPath $workingDirectory
    try {
        $global:LASTEXITCODE = 0
        & $commandPath @Arguments
        $exitCode = $global:LASTEXITCODE
        if (-not $?) {
            if ($exitCode -eq 0) {
                $exitCode = 1
            }
        }

        if ($exitCode -eq 0) {
            Add-CheckResult -Name $Name -Status "PASS" -Message "Completed successfully"
        } else {
            Add-CheckResult -Name $Name -Status "FAIL" -Message "Exited with code $exitCode"
        }
    } catch {
        Add-CheckResult -Name $Name -Status "FAIL" -Message $_.Exception.Message
    } finally {
        Pop-Location
    }
}

function Invoke-StaticKeywordCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$RelativePaths,
        [Parameter(Mandatory = $true)]
        [string[]]$Keywords
    )

    $files = @()
    foreach ($relativePath in $RelativePaths) {
        $fullPath = Join-Path $ProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            continue
        }

        $item = Get-Item -LiteralPath $fullPath
        if ($item.PSIsContainer) {
            $files += @(
                Get-ChildItem -LiteralPath $item.FullName -Recurse -File |
                    Where-Object { $_.Extension -in @(".py", ".md", ".sql", ".js", ".vue", ".dart", ".ps1") }
            )
        } else {
            $files += $item
        }
    }

    $files = @($files | Sort-Object -Property FullName -Unique)
    if ($files.Count -eq 0) {
        Add-CheckResult -Name $Name -Status "SKIP" -Message "No files found for static keyword check"
        return
    }

    $missingKeywords = @()
    foreach ($keyword in $Keywords) {
        $found = $false
        foreach ($file in $files) {
            $match = Select-String -LiteralPath $file.FullName -SimpleMatch -Pattern $keyword -List -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $match) {
                $found = $true
                break
            }
        }

        if (-not $found) {
            $missingKeywords += $keyword
        }
    }

    if ($missingKeywords.Count -eq 0) {
        Add-CheckResult -Name $Name -Status "PASS" -Message "Found keywords: $($Keywords -join ', ')"
    } else {
        Add-CheckResult -Name $Name -Status "FAIL" -Message "Missing keywords: $($missingKeywords -join ', ')"
    }
}

function Invoke-BackendCheck {
    param(
        [string]$Name = "backend"
    )

    $compileTargets = @(
        @("backend/app", "backend/tests", "backend/main.py", "backend/init_db.py") |
            Where-Object { Test-Path -LiteralPath (Join-Path $ProjectRoot $_) }
    )

    if ($compileTargets.Count -eq 0) {
        Add-CheckResult -Name $Name -Status "SKIP" -Message "No backend compile targets found"
        return
    }

    Invoke-CheckCommand `
        -Name $Name `
        -RelativeWorkingDirectory "." `
        -CommandCandidates @("python", "py") `
        -Arguments (@("-m", "compileall", "-q") + $compileTargets)
}

function Invoke-DeviceCheck {
    param(
        [string]$Name = "device"
    )

    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "device_runtime"))) {
        Add-CheckResult -Name $Name -Status "SKIP" -Message "Missing directory: device_runtime"
        return
    }

    Invoke-CheckCommand `
        -Name $Name `
        -RelativeWorkingDirectory "." `
        -CommandCandidates @("python", "py") `
        -Arguments @("-m", "compileall", "-q", "device_runtime")
}

function Invoke-MobileCheck {
    Invoke-CheckCommand `
        -Name "mobile analyze" `
        -RelativeWorkingDirectory "mobile_client" `
        -CommandCandidates @("flutter") `
        -Arguments @("analyze")

    Invoke-CheckCommand `
        -Name "mobile test" `
        -RelativeWorkingDirectory "mobile_client" `
        -CommandCandidates @("flutter") `
        -Arguments @("test")
}

function Invoke-AdminCheck {
    Invoke-CheckCommand `
        -Name "admin build" `
        -RelativeWorkingDirectory "admin_web" `
        -CommandCandidates @("npm.cmd", "npm") `
        -Arguments @("run", "build")
}

function Invoke-Stage3Check {
    Invoke-DeviceCheck -Name "stage3 compileall"

    Invoke-StaticKeywordCheck `
        -Name "stage3 track-target keywords" `
        -RelativePaths @(
            "device_runtime/api/routes/control.py",
            "device_runtime/services/control_service.py",
            "device_runtime/control/tracking_controller.py",
            "device_runtime/config.py"
        ) `
        -Keywords @(
            "/track-target",
            "track_target",
            "target_x",
            "target_y",
            "target_type",
            "deadzone_px",
            "max_delta_deg",
            "max_step_deg"
        )

    Invoke-StaticKeywordCheck `
        -Name "stage3 smoke script keywords" `
        -RelativePaths @("scripts/device_track_target_smoke.ps1") `
        -Keywords @(
            "/api/device/session/open",
            "/api/device/control/track-target",
            "BaseUrl",
            "target_x",
            "target_y",
            "RepeatDelayMs"
        )
}

function Invoke-Stage4Check {
    Invoke-BackendCheck -Name "stage4 compileall"

    Invoke-StaticKeywordCheck `
        -Name "stage4 media keywords" `
        -RelativePaths @("backend/app", "backend/tests", "backend/README.md") `
        -Keywords @("captures/upload", "media_type", "duration_ms", "local_album_saved")

    Invoke-StaticKeywordCheck `
        -Name "stage4 AI keywords" `
        -RelativePaths @("backend/app", "backend/tests", "backend/README.md") `
        -Keywords @(
            "ai_tasks",
            "task_type",
            "target_box_norm",
            "recommended_pan_delta",
            "recommended_tilt_delta",
            "batch_pick",
            "analyze_background"
        )

    Invoke-StaticKeywordCheck `
        -Name "stage4 provider keywords" `
        -RelativePaths @("backend/app", "backend/README.md") `
        -Keywords @("ai_provider_config", "AiProviderService", "provider_code", "provider_format")
}

$targetOrder = @("backend", "device", "mobile", "admin", "stage3", "stage4")
if ($Target -contains "all") {
    $selectedTargets = $targetOrder
} else {
    $selectedTargets = $targetOrder | Where-Object { $Target -contains $_ }
}

Write-Host "Project root: $ProjectRoot"
Write-Host "Selected checks: $($selectedTargets -join ', ')"

foreach ($selectedTarget in $selectedTargets) {
    switch ($selectedTarget) {
        "backend" { Invoke-BackendCheck }
        "device" { Invoke-DeviceCheck }
        "mobile" { Invoke-MobileCheck }
        "admin" { Invoke-AdminCheck }
        "stage3" { Invoke-Stage3Check }
        "stage4" { Invoke-Stage4Check }
    }
}

Write-Host ""
Write-Host "Check summary:"
foreach ($result in $script:Results) {
    $color = "Gray"
    if ($result.Status -eq "PASS") {
        $color = "Green"
    } elseif ($result.Status -eq "FAIL") {
        $color = "Red"
    }

    Write-Host ("{0,-14} {1,-4} {2}" -f $result.Name, $result.Status, $result.Message) -ForegroundColor $color
}

$failedResults = @($script:Results | Where-Object { $_.Status -eq "FAIL" })
if ($failedResults.Count -gt 0) {
    exit 1
}

exit 0
