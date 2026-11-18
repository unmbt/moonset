param (
    [switch]$Uninstall,
    [string]$Version = $env:MOONSET_VERSION
)

$ErrorActionPreference = "Stop"

$Repo = "unmbt/moonset"
$InstallDir = "$env:USERPROFILE\.unmbt"
$BinName = "moonset.exe"
$BinPath = Join-Path $InstallDir $BinName

if ($Uninstall) {
    Write-Host "Uninstalling $BinName..." -ForegroundColor Cyan
    if (Test-Path $BinPath) {
        Remove-Item -Path $BinPath -Force
        Write-Host "Uninstalled successfully." -ForegroundColor Green
    } else {
        Write-Host "Not installed." -ForegroundColor Yellow
    }
    return
}

$Arch = $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant()
if ($Arch -eq "amd64") {
    $AssetName = "moonset-win32-x64.exe"
} else {
    Write-Host "Unsupported architecture: $Arch (only amd64/x64 is currently prebuilt)" -ForegroundColor Red
    exit 1
}

if ($Version) {
    $TargetTag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
    $ReleaseUri = "https://api.github.com/repos/$Repo/releases/tags/$TargetTag"
} else {
    $ReleaseUri = "https://api.github.com/repos/$Repo/releases/latest"
}

Write-Host "Fetching release info from GitHub..." -ForegroundColor Cyan
try {
    $Release = Invoke-RestMethod -Uri $ReleaseUri
    $TargetVersion = $Release.tag_name.TrimStart('v')
    $DownloadUrl = ($Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1).browser_download_url
    $ChecksumUrl = ($Release.assets | Where-Object { $_.name -eq "SHA256SUMS" } | Select-Object -First 1).browser_download_url
} catch {
    Write-Host "Failed to fetch release info. Please check your network or verify a Release exists." -ForegroundColor Red
    exit 1
}

if (-not $TargetVersion -or -not $DownloadUrl -or -not $ChecksumUrl) {
    Write-Host "Failed to locate $AssetName or SHA256SUMS in the release." -ForegroundColor Red
    exit 1
}

if (Test-Path $BinPath) {
    $CurrentRaw = (& $BinPath -V 2>$null)
    if (-not $CurrentRaw) {
        $CurrentRaw = (& $BinPath --version 2>$null)
    }
    $CurrentVersion = if ($CurrentRaw) { "$CurrentRaw".Trim() -replace '^moonset\s+', '' } else { "unknown" }
    if ($CurrentVersion -eq $TargetVersion) {
        Write-Host "✨ You already have moonset v$TargetVersion installed at $BinPath." -ForegroundColor Green
        return
    } else {
        Write-Host "🚀 Updating moonset from $CurrentVersion to $TargetVersion..." -ForegroundColor Cyan
    }
} else {
    Write-Host "🚀 Installing moonset v$TargetVersion..." -ForegroundColor Cyan
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

Write-Host "Downloading $AssetName and SHA256SUMS..." -ForegroundColor Cyan
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("moonset-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$TempBin = Join-Path $TempDir $AssetName
$TempSum = Join-Path $TempDir "SHA256SUMS"

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempBin -ErrorAction Stop
    Invoke-WebRequest -Uri $ChecksumUrl -OutFile $TempSum -ErrorAction Stop

    if (-not (Test-Path $TempBin) -or (Get-Item $TempBin).Length -eq 0) {
        throw "The downloaded file is empty."
    }

    $ExpectedLine = Get-Content -Path $TempSum | Where-Object { $_ -match ("^\s*([0-9a-fA-F]{64})\s+\*?" + [regex]::Escape($AssetName) + "\s*$") } | Select-Object -First 1
    if (-not $ExpectedLine) {
        throw "Asset $AssetName not found in SHA256SUMS."
    }
    $ExpectedHash = $Matches[1].ToLowerInvariant()
    $ActualHash = (Get-FileHash -Path $TempBin -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedHash) {
        throw "SHA-256 checksum mismatch for ${AssetName}: expected $ExpectedHash, got $ActualHash"
    }

    Move-Item -Path $TempBin -Destination $BinPath -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to install ${AssetName}: $($_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n✅ Installed moonset v$TargetVersion successfully to $BinPath" -ForegroundColor Green

$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$PathEntries = if ($UserPath) { $UserPath -split ";" | Where-Object { $_ } } else { @() }
if ($PathEntries -notcontains $InstallDir) {
    $NewPath = if ($UserPath -and -not $UserPath.EndsWith(";")) { "$UserPath;$InstallDir" } elseif ($UserPath) { "$UserPath$InstallDir" } else { $InstallDir }
    [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
    Write-Host "✅ Automatically added $InstallDir to your User PATH!" -ForegroundColor Green
    Write-Host "💡 Note: You may need to restart your terminal for the changes to take effect." -ForegroundColor Yellow
} else {
    Write-Host "✅ $InstallDir is already in your PATH." -ForegroundColor Green
}
