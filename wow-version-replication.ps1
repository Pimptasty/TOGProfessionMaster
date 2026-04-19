param(
    [string]$Source = $PSScriptRoot
)

$AddonName   = "TOGProfessionMaster"
$WowBase     = "${env:ProgramFiles(x86)}\World of Warcraft"
$WowVersions = @("_classic_era_", "_classic_", "_anniversary_")

# Build list of addon install directories that actually exist on disk
# Exclude the version that contains the source folder to avoid copying to itself
$Destinations = foreach ($ver in $WowVersions) {
    $addonsDir = Join-Path $WowBase "$ver\Interface\AddOns"
    $dest = Join-Path $addonsDir $AddonName
    if ((Test-Path $addonsDir) -and ($Source -notlike "$dest*")) {
        if (-not (Test-Path $dest)) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
        }
        $dest
    }
}

if (-not $Destinations) {
    Write-Host "No WoW installation found under $WowBase. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== TOG Profession Master Dev Sync ===" -ForegroundColor Magenta
Write-Host "Source : $Source"                        -ForegroundColor White
foreach ($d in $Destinations) {
    Write-Host "Target : $d" -ForegroundColor Green
}
Write-Host "Press Ctrl+C to stop." -ForegroundColor White
Write-Host ""

# Relative paths matching these patterns are never synced to WoW
$SkipPatterns = @(
    '(^|\\)\.git(\\|$)',
    '(^|\\)\.github(\\|$)',
    '(^|\\)\.vscode(\\|$)',
    '(^|\\)\.luarc\.json$',
    '(^|\\)\.markdownlint\.json$',
    '(^|\\)\.gitignore$',
    '(^|\\)\.pkgmeta$',
    '(^|\\)wow-version-replication\.ps1$',
    '(^|\\).*\.code-workspace$',
    '(^|\\)docs(\\|$)'
)

function Skip-Path([string]$rel) {
    foreach ($p in $SkipPatterns) {
        if ($rel -match $p) { return $true }
    }
    return $false
}

function Sync-File([string]$fullPath, [string]$verb) {
    $rel = $fullPath.Substring($Source.Length).TrimStart('\','/')
    if (Skip-Path $rel) { return }

    $ts = Get-Date -Format "HH:mm:ss"

    foreach ($dest in $Destinations) {
        $target = Join-Path $dest $rel
        if ($verb -eq "Deleted") {
            if (Test-Path $target) {
                Remove-Item $target -Force -Recurse -ErrorAction SilentlyContinue
                Write-Host "[$ts] DEL  $rel" -ForegroundColor Red
            }
        } else {
            $dir = Split-Path $target -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Copy-Item $fullPath $target -Force
            Write-Host "[$ts] $($verb.PadRight(7)) $rel" -ForegroundColor Cyan
        }
    }
}

# Full initial sync
Write-Host "Initial sync..." -ForegroundColor Yellow
Get-ChildItem -Path $Source -Recurse -File | ForEach-Object { Sync-File $_.FullName "SYNC" }
Write-Host "Ready." -ForegroundColor Green
Write-Host ""

# File system watcher
$fsw = [System.IO.FileSystemWatcher]::new($Source)
$fsw.IncludeSubdirectories = $true
$fsw.EnableRaisingEvents   = $true
$fsw.NotifyFilter = [System.IO.NotifyFilters]::FileName `
                  -bor [System.IO.NotifyFilters]::DirectoryName `
                  -bor [System.IO.NotifyFilters]::LastWrite

$h_Change  = Register-ObjectEvent $fsw Changed  -Action { Sync-File $Event.SourceEventArgs.FullPath "Changed" }
$h_Create  = Register-ObjectEvent $fsw Created  -Action { Sync-File $Event.SourceEventArgs.FullPath "Created" }
$h_Delete  = Register-ObjectEvent $fsw Deleted  -Action { Sync-File $Event.SourceEventArgs.FullPath "Deleted" }
$h_Rename  = Register-ObjectEvent $fsw Renamed  -Action { Sync-File $Event.SourceEventArgs.FullPath "Renamed" }

try {
    while ($true) { Start-Sleep -Seconds 1 }
} finally {
    $fsw.EnableRaisingEvents = $false
    $h_Change, $h_Create, $h_Delete, $h_Rename | ForEach-Object {
        Unregister-Event -SourceIdentifier $_.Name -ErrorAction SilentlyContinue
    }
    $fsw.Dispose()
    Write-Host "Watcher stopped." -ForegroundColor Yellow
}
