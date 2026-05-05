param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Copy-SelectedTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    $sourcePath = Join-Path $SourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        return 0
    }

    $item = Get-Item -LiteralPath $sourcePath
    if (-not $item.PSIsContainer) {
        $targetFile = Join-Path $DestinationRoot (Join-Path $ModuleName $RelativePath)
        $targetDir = Split-Path -Parent $targetFile
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $targetFile -Force
        return 1
    }

    $copied = 0
    $files = Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force |
        Where-Object {
            $_.Name -notlike "*.pyc" -and
            $_.Name -notlike "*.pyo" -and
            $_.Name -notlike "*.log" -and
            $_.Name -notlike "GeneratedPluginRegistrant.*" -and
            $_.FullName -notmatch "(^|[\\/])__pycache__([\\/]|$)" -and
            $_.FullName -notmatch "(^|[\\/])\.dart_tool([\\/]|$)" -and
            $_.FullName -notmatch "(^|[\\/])build([\\/]|$)" -and
            $_.FullName -notmatch "(^|[\\/])dist([\\/]|$)" -and
            $_.FullName -notmatch "(^|[\\/])node_modules([\\/]|$)" -and
            $_.FullName -notmatch "(^|[\\/])\.venv([\\/]|$)"
        }

    foreach ($file in $files) {
        $relativeFile = Get-RelativePath -BasePath $SourceRoot -TargetPath $file.FullName
        $targetFile = Join-Path $DestinationRoot (Join-Path $ModuleName $relativeFile)
        $targetDir = Split-Path -Parent $targetFile
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $targetFile -Force
        $copied += 1
    }

    return $copied
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $normalizedBase = [System.IO.Path]::GetFullPath($BasePath)
    $normalizedTarget = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $normalizedBase.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $normalizedBase += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($normalizedBase)
    $targetUri = New-Object System.Uri($normalizedTarget)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', '\')
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $resolvedProjectRoot "deliverables\first_party_source"
}

$resolvedOutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$resolvedDeliverablesDir = [System.IO.Path]::GetFullPath((Join-Path $resolvedProjectRoot "deliverables"))
if (-not $resolvedOutputDir.StartsWith($resolvedDeliverablesDir, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDir must stay inside $resolvedDeliverablesDir"
}

if (Test-Path -LiteralPath $resolvedOutputDir) {
    Remove-Item -LiteralPath $resolvedOutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null

$modules = @(
    @{
        Name = "admin_web"
        Include = @(
            "src",
            "index.html",
            "package.json",
            "vite.config.js"
        )
    },
    @{
        Name = "backend"
        Include = @(
            "app",
            "tests",
            ".env.example",
            "init_db.py",
            "main.py",
            "requirements.txt"
        )
    },
    @{
        Name = "device_runtime"
        Include = @(
            "api",
            "control",
            "interfaces",
            "repositories",
            "services",
            "templates",
            "tests",
            "utils",
            "vision",
            "__init__.py",
            "app_core.py",
            "config.py",
            "main.py",
            "mode_manager.py",
            "requirements.txt"
        )
    },
    @{
        Name = "mobile_client"
        Include = @(
            "lib",
            "test",
            "analysis_options.yaml",
            "pubspec.yaml",
            "android\app\build.gradle.kts",
            "android\app\src\debug\AndroidManifest.xml",
            "android\app\src\main\AndroidManifest.xml",
            "android\app\src\main\java",
            "android\app\src\main\kotlin",
            "android\app\src\profile\AndroidManifest.xml",
            "android\build.gradle.kts",
            "android\gradle.properties",
            "android\settings.gradle.kts",
            "ios\Runner\AppDelegate.swift",
            "ios\Runner\Info.plist",
            "ios\Runner\Runner-Bridging-Header.h",
            "ios\Runner\SceneDelegate.swift",
            "ios\Runner\Base.lproj",
            "ios\RunnerTests",
            "ios\Runner.xcodeproj\project.pbxproj",
            "ios\Runner.xcodeproj\xcshareddata\xcschemes\Runner.xcscheme",
            "ios\Runner.xcworkspace\contents.xcworkspacedata"
        )
    },
    @{
        Name = "database"
        Include = @(
            "schema.sql",
            "migrations"
        )
    }
)

$moduleStats = @()
$totalFiles = 0

foreach ($module in $modules) {
    $moduleName = $module.Name
    $moduleRoot = Join-Path $resolvedProjectRoot $moduleName
    if (-not (Test-Path -LiteralPath $moduleRoot)) {
        continue
    }

    $fileCount = 0
    foreach ($relativePath in $module.Include) {
        $fileCount += Copy-SelectedTree -ModuleName $moduleName -SourceRoot $moduleRoot -RelativePath $relativePath -DestinationRoot $resolvedOutputDir
    }

    $moduleStats += [pscustomobject]@{
        Module = $moduleName
        Files  = $fileCount
        Paths  = ($module.Include -join ", ")
    }
    $totalFiles += $fileCount
}

$manifestLines = @(
    "# First-Party Source Collection",
    "",
    "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Output directory: $resolvedOutputDir",
    "",
    "## Included Scope",
    "",
    "- admin_web: business frontend source and Vite project config.",
    "- backend: FastAPI backend source, tests, and startup config.",
    "- device_runtime: device runtime source, tests, and startup config.",
    "- mobile_client: Flutter app source, tests, and project config.",
    "- database: schema and migration scripts.",
    "",
    "## Explicit Exclusions",
    "",
    "- Developer tools and IDE metadata such as .idea, .git, and log files.",
    "- Virtual environments and dependency directories such as .venv, node_modules, and .dart_tool.",
    "- Build outputs and caches such as dist, build, __pycache__, and .pyc files.",
    "- Runtime data and assets such as captures, uploads, demo outputs, and rendered documents.",
    "- Document helper tools and third-party document utility code such as scripts/scripts.",
    "",
    "## File Counts",
    ""
)

foreach ($stat in $moduleStats) {
    $manifestLines += "- $($stat.Module): $($stat.Files) files"
}

$manifestLines += @(
    "",
    "Total: $totalFiles files",
    "",
    "## Layout",
    "",
    "Collected files keep their original relative paths inside each module for easier review and packaging."
)

$manifestPath = Join-Path $resolvedOutputDir "README.md"
$manifestLines | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Output "Collected $totalFiles files into $resolvedOutputDir"
