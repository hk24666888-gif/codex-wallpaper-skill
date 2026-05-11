param(
    [ValidateSet("status", "apply", "restore")]
    [string]$Mode = "status",

    [ValidateSet("yukino", "codex")]
    [string]$Target = "yukino",

    [string]$ImagePath = "",

    [string]$BackupId = "",

    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PatchStart = "/* App Wallpaper Skill Patch */"
$PatchEnd = "/* End App Wallpaper Skill Patch */"
$StateRoot = Join-Path $env:USERPROFILE ".app-wallpaper"

function Get-TargetPackage {
    param([string]$Name)

    $packageName = if ($Name -eq "yukino") { "yukino.akane" } else { "OpenAI.Codex" }
    $pkg = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
    if (-not $pkg) {
        throw "Package not found: $packageName"
    }
    return $pkg
}

function Get-AsarPath {
    param($Package)

    $path = Join-Path $Package.InstallLocation "app\resources\app.asar"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "app.asar not found: $path"
    }
    return $path
}

function Get-ResourcesPath {
    param($Package)
    return (Join-Path $Package.InstallLocation "app\resources")
}

function Stop-TargetProcesses {
    param($Package)

    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($Package.InstallLocation, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

function Start-TargetApp {
    param([string]$Name)

    if ($NoLaunch) {
        return
    }

    $appId = if ($Name -eq "yukino") {
        "shell:AppsFolder\yukino.akane_fnxqm6pztzbs0!App"
    } else {
        "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
    }

    Start-Process $appId
}

function Invoke-CopyWithAccess {
    param(
        [string]$Source,
        [string]$Destination
    )

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return
    } catch {
        Write-Host "Direct copy failed: $($_.Exception.Message)"
        & takeown.exe /F $Destination | Out-Host
        & icacls.exe $Destination /grant "$($env:USERNAME):F" | Out-Host
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Invoke-Asar {
    param([string[]]$Arguments)

    $npx = Get-Command "npx.cmd" -ErrorAction SilentlyContinue
    if (-not $npx) {
        $npx = Get-Command "npx" -ErrorAction SilentlyContinue
    }
    if (-not $npx) {
        throw "npx was not found. Install Node.js or add npx to PATH."
    }

    & $npx.Source --yes "@electron/asar" @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "@electron/asar failed with exit code $LASTEXITCODE"
    }
}

function New-Backup {
    param(
        $Package,
        [string]$TargetName
    )

    $resources = Get-ResourcesPath $Package
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $StateRoot "backups\$TargetName\$($Package.Version)-$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    $asar = Join-Path $resources "app.asar"
    Copy-Item -LiteralPath $asar -Destination (Join-Path $backupDir "app.asar") -Force

    $unpacked = Join-Path $resources "app.asar.unpacked"
    if (Test-Path -LiteralPath $unpacked) {
        robocopy $unpacked (Join-Path $backupDir "app.asar.unpacked") /MIR /XJ /R:2 /W:2 /NFL /NDL /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Failed to back up app.asar.unpacked"
        }
    }

    return $backupDir
}

function Get-LatestBackup {
    param([string]$TargetName)

    $root = Join-Path $StateRoot "backups\$TargetName"
    if (-not (Test-Path -LiteralPath $root)) {
        throw "No backups found for target: $TargetName"
    }

    $backup = Get-ChildItem -LiteralPath $root -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $backup) {
        throw "No backups found for target: $TargetName"
    }
    return $backup.FullName
}

function Test-PatchMarker {
    param([string]$AsarPath)

    $node = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if (-not $node) {
        $node = Get-Command "node" -ErrorAction SilentlyContinue
    }
    if ($node) {
        $code = @"
const fs = require('fs');
const input = process.argv[1];
const marker = Buffer.from('$PatchStart', 'utf8');
const found = fs.readFileSync(input).indexOf(marker) >= 0;
process.stdout.write(found ? 'true' : 'false');
"@
        $result = & $node.Source -e $code $AsarPath
        return ($result -eq "true")
    }

    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($AsarPath))
    return $text.Contains($PatchStart)
}

function Show-Status {
    param(
        $Package,
        [string]$TargetName
    )

    $asar = Get-AsarPath $Package
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $asar).Hash
    Write-Host "Target        : $TargetName"
    Write-Host "Package       : $($Package.Name)"
    Write-Host "Version       : $($Package.Version)"
    Write-Host "Install       : $($Package.InstallLocation)"
    Write-Host "app.asar      : $asar"
    Write-Host "SHA256        : $hash"
    Write-Host "Patch present : $(Test-PatchMarker $asar)"

    $backupRoot = Join-Path $StateRoot "backups\$TargetName"
    if (Test-Path -LiteralPath $backupRoot) {
        Write-Host ""
        Write-Host "Backups:"
        Get-ChildItem -LiteralPath $backupRoot -Directory |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10 Name, FullName, LastWriteTime |
            Format-Table -AutoSize
    }
}

function Apply-Wallpaper {
    param(
        $Package,
        [string]$TargetName,
        [string]$Image
    )

    if (-not $Image) {
        throw "ImagePath is required for apply mode."
    }
    $imageFull = (Resolve-Path -LiteralPath $Image -ErrorAction Stop).Path
    $ext = [IO.Path]::GetExtension($imageFull).ToLowerInvariant()
    if ($ext -notin @(".png", ".jpg", ".jpeg", ".webp", ".gif")) {
        throw "Unsupported image extension: $ext"
    }

    $resources = Get-ResourcesPath $Package
    $asar = Get-AsarPath $Package
    $backup = New-Backup -Package $Package -TargetName $TargetName
    Write-Host "Backup created: $backup"

    $work = Join-Path $env:TEMP "app-wallpaper-$TargetName-$(Get-Date -Format yyyyMMddHHmmss)"
    $extract = Join-Path $work "extract"
    $newAsar = Join-Path $work "app.asar"
    New-Item -ItemType Directory -Force -Path $extract | Out-Null

    Invoke-Asar @("extract", $asar, $extract)

    $unpacked = Join-Path $resources "app.asar.unpacked"
    if (Test-Path -LiteralPath $unpacked) {
        robocopy $unpacked $extract /E /XJ /R:2 /W:2 /NFL /NDL /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Failed to stage app.asar.unpacked"
        }
    }

    $assets = Join-Path $extract "webview\assets"
    if (-not (Test-Path -LiteralPath $assets)) {
        throw "webview assets directory not found in app.asar"
    }

    $css = Get-ChildItem -LiteralPath $assets -File -Filter "app-main-*.css" |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if (-not $css) {
        throw "Could not find app-main CSS asset"
    }

    $wallpaperName = "app-wallpaper$ext"
    Copy-Item -LiteralPath $imageFull -Destination (Join-Path $assets $wallpaperName) -Force

    $cssText = [IO.File]::ReadAllText($css.FullName)
    $regex = [regex]::Escape($PatchStart) + "(?s).*?" + [regex]::Escape($PatchEnd)
    $cssText = [regex]::Replace($cssText, $regex, "")

    $block = @"

$PatchStart
:root {
  --app-wallpaper-skill-image: url("./$wallpaperName");
  --app-wallpaper-skill-sidebar-width: clamp(280px, 27vw, 430px);
  --app-wallpaper-skill-half-width: calc(var(--app-wallpaper-skill-sidebar-width) / 2);
  --app-wallpaper-skill-portrait-half-width: 42.105263vh;
}

[data-codex-window-type=electron] body {
  background-image:
    linear-gradient(90deg,
      color-mix(in srgb, var(--color-token-side-bar-background) 56%, transparent) 0%,
      color-mix(in srgb, var(--color-token-side-bar-background) 70%, transparent) 74%,
      transparent 100%),
    var(--app-wallpaper-skill-image);
  background-position: left top, calc(var(--app-wallpaper-skill-half-width) - var(--app-wallpaper-skill-portrait-half-width)) center;
  background-repeat: no-repeat, no-repeat;
  background-size: var(--app-wallpaper-skill-sidebar-width) 100%, auto 100vh;
}

[data-codex-window-type=electron] .bg-token-side-bar-background,
[data-codex-window-type=electron] .bg-token-side-bar-background\/90 {
  background-color: color-mix(in srgb, var(--color-token-side-bar-background) 70%, transparent);
}

@media (prefers-color-scheme: dark) {
  [data-codex-window-type=electron] .electron\:dark\:bg-token-side-bar-background:where([data-codex-window-type=electron] .electron\:dark\:bg-token-side-bar-background) {
    background-color: color-mix(in srgb, var(--color-token-side-bar-background) 64%, transparent);
  }
}

[data-codex-window-type=electron] .main-surface:where([data-codex-window-type=electron] .main-surface) {
  background-color: var(--color-token-main-surface-primary);
  background-image: none;
}
$PatchEnd
"@

    [IO.File]::WriteAllText($css.FullName, $cssText.TrimEnd() + $block, [Text.Encoding]::UTF8)

    Invoke-Asar @("pack", $extract, $newAsar, "--unpack-dir", "{node_modules,native}")

    Stop-TargetProcesses $Package
    Invoke-CopyWithAccess -Source $newAsar -Destination $asar

    $newUnpacked = "$newAsar.unpacked"
    $destUnpacked = Join-Path $resources "app.asar.unpacked"
    if (Test-Path -LiteralPath $newUnpacked) {
        robocopy $newUnpacked $destUnpacked /MIR /XJ /R:2 /W:2 /NFL /NDL /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Failed to copy app.asar.unpacked"
        }
    }

    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Wallpaper applied."
    Start-TargetApp $TargetName
}

function Restore-Wallpaper {
    param(
        $Package,
        [string]$TargetName,
        [string]$BackupName
    )

    $backup = if ($BackupName) {
        $candidate = Join-Path (Join-Path $StateRoot "backups\$TargetName") $BackupName
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Backup not found: $candidate"
        }
        $candidate
    } else {
        Get-LatestBackup $TargetName
    }

    $backupAsar = Join-Path $backup "app.asar"
    if (-not (Test-Path -LiteralPath $backupAsar)) {
        throw "Backup app.asar missing: $backupAsar"
    }

    $resources = Get-ResourcesPath $Package
    $asar = Get-AsarPath $Package
    Stop-TargetProcesses $Package
    Invoke-CopyWithAccess -Source $backupAsar -Destination $asar

    $backupUnpacked = Join-Path $backup "app.asar.unpacked"
    $destUnpacked = Join-Path $resources "app.asar.unpacked"
    if (Test-Path -LiteralPath $backupUnpacked) {
        robocopy $backupUnpacked $destUnpacked /MIR /XJ /R:2 /W:2 /NFL /NDL /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "Failed to restore app.asar.unpacked"
        }
    }

    Write-Host "Restored backup: $backup"
    Start-TargetApp $TargetName
}

$pkg = Get-TargetPackage $Target

switch ($Mode) {
    "status" {
        Show-Status -Package $pkg -TargetName $Target
    }
    "apply" {
        Apply-Wallpaper -Package $pkg -TargetName $Target -Image $ImagePath
    }
    "restore" {
        Restore-Wallpaper -Package $pkg -TargetName $Target -BackupName $BackupId
    }
}
