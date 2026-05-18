param(
    [string]$BaseUrl = "http://127.0.0.1:8001",
    [string]$SessionCode = "stage3-smoke-$((Get-Date).ToString('yyyyMMdd-HHmmss'))",
    [int]$FrameWidth = 1000,
    [int]$FrameHeight = 1000,
    [ValidateSet("shoulder_center", "face_center")]
    [string]$TargetType = "shoulder_center",
    [int]$RepeatDelayMs = 140,
    [double]$Offset = 0.08,
    [switch]$KeepSessionOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-BaseUrl {
    param([Parameter(Mandatory = $true)][string]$RawBaseUrl)

    $normalized = $RawBaseUrl.Trim()
    while ($normalized.EndsWith("/")) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }
    if ($normalized.EndsWith("/api")) {
        $normalized = $normalized.Substring(0, $normalized.Length - 4)
    }
    return $normalized
}

function Invoke-DevicePost {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Body
    )

    $uri = "$Base$Path"
    $json = $Body | ConvertTo-Json -Depth 8
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -ContentType "application/json" `
        -Body $json

    if ($null -eq $response.success -or -not [bool]$response.success) {
        throw "Device request failed: $uri"
    }
    return $response.data
}

function Write-TrackResult {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)]$Data
    )

    $line = "{0,-10} target=({1:N3},{2:N3}) applied={3} pan_delta={4:N3} tilt_delta={5:N3} current=({6:N3},{7:N3})" -f `
        $Label,
        [double]$Data.target_x,
        [double]$Data.target_y,
        [bool]$Data.applied,
        [double]$Data.pan_delta,
        [double]$Data.tilt_delta,
        [double]$Data.current_pan,
        [double]$Data.current_tilt
    Write-Host $line
}

$base = Normalize-BaseUrl -RawBaseUrl $BaseUrl
$baseUri = [Uri]$base
$isLoopback = $baseUri.Host -in @("127.0.0.1", "localhost", "::1")

Write-Host "Device track-target smoke"
Write-Host "BaseUrl: $base"
Write-Host "SessionCode: $SessionCode"
Write-Host "TargetType: $TargetType"
if (-not $isLoopback) {
    Write-Warning "Remote device target selected. Start the Pi with small angle limits before running this smoke."
}

$sessionBody = @{
    session_code = $SessionCode
    stream_url = "mobile_push"
    mode = "gimbal_follow"
    preview_source = "phone_camera"
    start_mode = "AUTO_TRACK"
    mirror_view = $false
}

$null = Invoke-DevicePost -Base $base -Path "/api/device/session/open" -Body $sessionBody

$steps = @(
    @{ Label = "center"; X = 0.50; Y = 0.50; Confidence = 1.00 },
    @{ Label = "right-1"; X = 0.50 + $Offset; Y = 0.50; Confidence = 0.95 },
    @{ Label = "right-2"; X = 0.50 + $Offset; Y = 0.50; Confidence = 0.95 },
    @{ Label = "left-1"; X = 0.50 - $Offset; Y = 0.50; Confidence = 0.95 },
    @{ Label = "down-1"; X = 0.50; Y = 0.50 + $Offset; Confidence = 0.95 },
    @{ Label = "up-1"; X = 0.50; Y = 0.50 - $Offset; Confidence = 0.95 }
)

try {
    foreach ($step in $steps) {
        $timestampMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $body = @{
            target_type = $TargetType
            target_x = [Math]::Round([double]$step.X, 4)
            target_y = [Math]::Round([double]$step.Y, 4)
            confidence = [double]$step.Confidence
            source = "stage3_smoke"
            frame = @{
                width = $FrameWidth
                height = $FrameHeight
                orientation = "smoke"
                mirror = $false
            }
            timestamp_ms = $timestampMs
        }

        $data = Invoke-DevicePost -Base $base -Path "/api/device/control/track-target" -Body $body
        Write-TrackResult -Label ([string]$step.Label) -Data $data
        Start-Sleep -Milliseconds $RepeatDelayMs
    }
} finally {
    if (-not $KeepSessionOpen) {
        try {
            $null = Invoke-DevicePost `
                -Base $base `
                -Path "/api/device/session/close" `
                -Body @{ session_code = $SessionCode }
            Write-Host "Session closed."
        } catch {
            Write-Warning "Failed to close smoke session: $($_.Exception.Message)"
        }
    }
}
