param(
    [string]$Source = $PSScriptRoot
)

$AddonName   = "TOGProfessionMaster"
$WowBase     = "${env:ProgramFiles(x86)}\World of Warcraft"

# -----------------------------------------------------------------------------
# Single-instance guard -- PER REPO, not per-script-name.
#
# This same watcher script runs concurrently in many addon repos. We must NOT
# bail just because *a* wow-version-replication.ps1 is running somewhere else
# (that's a different addon). The guard is keyed on THIS repo's own source path,
# so:
#   * a second launch on the SAME repo (e.g. a VS Code window reload firing the
#     folderOpen task again) finds the mutex held and exits cleanly -- no racing
#     watchers mangling the same files;
#   * a watcher for a DIFFERENT addon has a different source path -> different
#     mutex name -> both run happily side by side.
#
# A named Mutex (kernel object) is used rather than scanning process command
# lines, because command-line matching is fragile. The mutex is released
# automatically when this process exits (crash, Ctrl+C, or normal stop), so a
# dead watcher never blocks a fresh one.
$script:InstanceMutex = $null
# Resolve to a canonical absolute path, lowercased, so the same repo always
# yields the same key regardless of how it was launched. Non-alphanumeric
# chars -> '_' because mutex names can't contain '\'.
$repoKey = (Resolve-Path -LiteralPath $Source -ErrorAction SilentlyContinue).Path
if (-not $repoKey) { $repoKey = $Source }
$repoKey = ($repoKey.ToLowerInvariant() -replace '[^a-z0-9]', '_')
$mutexName = "Global\WowDevSync_$repoKey"
$createdNew = $false
try {
    $script:InstanceMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)
} catch {
    # If the mutex can't be created for any reason, fail open (run anyway)
    # rather than refusing to sync.
    $createdNew = $true
}
if (-not $createdNew) {
    Write-Host "A dev sync watcher is already running for this repo ($Source). Exiting." -ForegroundColor Yellow
    exit 0
}

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

# Relative paths matching these patterns are never synced to WoW.
# Mirrors the `ignore:` list in .pkgmeta — anything excluded from the
# CurseForge package should also be excluded from local dev sync, so
# every WoW client we sync to ends up with the same file set the
# packaged release would have. Update BOTH this list and .pkgmeta
# together when adding new dev-only files / directories.
$SkipPatterns = @(
    # Dev / version control
    '(^|\\)\.git(\\|$)',
    '(^|\\)\.github(\\|$)',
    '(^|\\)\.vscode(\\|$)',
    '(^|\\)\.claude(\\|$)',
    '(^|\\)\.gitignore$',
    '(^|\\)\.pkgmeta$',
    # Dev-only tooling and scripts
    '(^|\\)tools(\\|$)',
    '(^|\\)docs(\\|$)',
    '(^|\\).*\.ps1$',
    '(^|\\).*\.bat$',
    '(^|\\).*\.code-workspace$',
    # Lint config
    '(^|\\)\.luarc\.json$',
    '(^|\\)\.markdownlint\.json$',
    '(^|\\)\.markdownlintignore$',
    # Project docs not shipped to clients
    '(^|\\)CLAUDE\.md$'
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
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
            }
            # A locked target (WoW open + reading the file, AV scan, editor
            # write-replace in flight) makes Copy-Item throw. Don't let one
            # locked file kill the watcher -- log a RETRY and move on; the next
            # change event (or next launch's initial sync) self-heals it.
            try {
                Copy-Item $fullPath $target -Force -ErrorAction Stop
                Write-Host "[$ts] $($verb.PadRight(7)) $rel" -ForegroundColor Cyan
            } catch {
                Write-Host "[$ts] RETRY   $rel (target busy: $($_.Exception.Message))" -ForegroundColor DarkYellow
            }
        }
    }
}

# Full initial sync. Per-file try/catch so one unreadable/locked file (or a
# file that vanishes between enumeration and copy) can't abort the whole
# initial sync and exit the script before the watcher ever starts.
Write-Host "Initial sync..." -ForegroundColor Yellow
Get-ChildItem -Path $Source -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { Sync-File $_.FullName "SYNC" }
    catch { Write-Host "[init] skipped $($_.Exception.Message)" -ForegroundColor DarkYellow }
}
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
    while ($true) {
        # The actual sync work runs in the Register-ObjectEvent action blocks;
        # this is just the keep-alive. Wrapped so a transient error here can
        # never tear the watcher down -- log the blip and keep waiting.
        try {
            Start-Sleep -Seconds 1
        } catch {
            $ts = Get-Date -Format "HH:mm:ss"
            Write-Host "[$ts] WARN    poll skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
} finally {
    $fsw.EnableRaisingEvents = $false
    $h_Change, $h_Create, $h_Delete, $h_Rename | ForEach-Object {
        Unregister-Event -SourceIdentifier $_.Name -ErrorAction SilentlyContinue
    }
    $fsw.Dispose()
    Write-Host "Watcher stopped." -ForegroundColor Yellow
    # Release the per-repo single-instance mutex so the next launch can start.
    if ($script:InstanceMutex) {
        try { $script:InstanceMutex.ReleaseMutex() } catch {}
        $script:InstanceMutex.Dispose()
    }
}
