param(
    [string]$Source = $PSScriptRoot,
    # When set, no files are copied or deleted -- output shows what *would*
    # happen. Use to verify the destination list, .pkgmeta parsing and skip
    # patterns before letting the watcher mutate target installs: everything in
    # the released zip should read WOULD, everything else [skip].
    [switch]$DryRun
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
# A DRY RUN TAKES NO MUTEX. It copies and deletes nothing, so there is no
# resource to hold and nothing to race -- while the guard applies to it, the
# verification step cannot be run at all on the normal setup, because VS Code
# launches the real watcher on folder open and it holds the mutex for the whole
# session. The check exists to stop two WRITING watchers, not to stop reading.
if (-not $DryRun) {
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
#
# The exclusions are READ FROM .pkgmeta, not copied from it. This block used to
# be a hand-maintained regex list whose own comment said "update BOTH this list
# and .pkgmeta together" -- a declared coupling with nothing enforcing it, and it
# had already drifted: `Tests` and `CHANGELOG_ARCHIVE.md` were in .pkgmeta and
# missing here, so the harness submodule (which now carries a loadable addon of
# its own under perf/, plus a Python tree under mcp/) replicated into every other
# WoW install. Audit finding 25.
#
# The point of this script is that a synced install looks like the PACKAGED
# release, so it must implement the packager's rules -- which means reading the
# packager's own input rather than a second copy of it.

function Convert-GlobToRegex([string]$glob) {
    # Normalize forward slashes to backslashes (file paths come in Windows-style)
    $g = $glob -replace '/', '\'

    # "**\" prefix -> match anywhere in the tree, not just at the root
    $matchAnywhere = $false
    if ($g.StartsWith('**\')) {
        $g = $g.Substring(3)
        $matchAnywhere = $true
    }

    # Trailing "\" marks a directory; strip it for the literal match
    $isDir = $g.EndsWith('\')
    if ($isDir) {
        $g = $g.TrimEnd('\')
    }

    # A bare name that IS a directory in the repo means "that folder and
    # everything under it", exactly as release.sh's parse_ignore does:
    #     if [ -d "$topdir/$yaml_item" ]; then yaml_item="$yaml_item/*"; fi
    # Without this a folder entry compiles to `^docs$`, which matches a FILE
    # literally named "docs" and nothing else -- so `docs` and `Tests` would be
    # listed in .pkgmeta, reported as loaded at startup, and replicated anyway.
    # Wildcard entries are left alone: Test-Path would glob them and could match
    # an unrelated directory.
    if (-not $isDir -and $g -notmatch '[*?]') {
        $candidate = Join-Path $Source $g
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $isDir = $true
        }
    }

    # Escape regex specials, then turn glob wildcards back into regex equivalents
    $escaped = [regex]::Escape($g)
    $escaped = $escaped -replace '\\\*', '[^\\]*'   # * -> any segment-internal chars
    $escaped = $escaped -replace '\\\?', '[^\\]'    # ? -> one char

    $prefix = if ($matchAnywhere) { '(^|\\)' } else { '^' }
    $suffix = if ($isDir)         { '(\\|$)' } else { '$' }
    return "$prefix$escaped$suffix"
}

function Get-PkgmetaIgnores([string]$pkgmetaPath) {
    if (-not (Test-Path $pkgmetaPath)) { return @() }
    $ignores  = @()
    $inIgnore = $false
    $lineNo   = 0
    foreach ($raw in Get-Content $pkgmetaPath) {
        $lineNo++
        # A comment on its OWN line is fine and is stripped. A comment TRAILING a
        # list item is not -- see the refusal below; this strip is what would
        # otherwise hide it.
        $line = $raw -replace '#.*$', ''

        # Audit finding 28. THE PACKAGER DOES NOT STRIP COMMENTS, and this parser
        # must not be more permissive than the thing it is modelling.
        #
        # release.sh's yaml_listitem() trims a leading `-`, whitespace, and ONE
        # leading and trailing quote -- nothing else. On
        #     - "*.ps1"   # every dev script
        # the leading quote is trimmed and the CLOSING quote survives mid-string.
        # That value is interpolated into `cdt_args+=" -i \"$ignore\""` and
        # re-parsed by `eval copy_directory_tree ...`; the stray quote breaks the
        # re-parse, `_cdt_destdir` becomes empty, and EVERY FILE IS COPIED
        # NOWHERE. The packager exits 0 and uploads an archive containing only
        # the bare addon folder -- that shipped two empty Dibs releases.
        #
        # So a trailing comment here would dry-run perfectly clean while the real
        # zip shipped nothing: the verification step would be CONFIRMING a broken
        # .pkgmeta. Refuse it loudly instead of silently repairing it.
        if ($inIgnore -and $raw -match '^\s*-' -and $raw -match '#') {
            throw ("$pkgmetaPath line ${lineNo}: a list item carries a trailing comment. " +
                   "The BigWigs packager does not strip comments -- the surviving quote " +
                   "breaks its eval and the release ships an EMPTY zip, exit 0. " +
                   "Move the comment to its own line. Offending line: $raw")
        }
        if ($inIgnore -and $line -match '^\s*-\s*(.+?)\s*$') {
            # An unbalanced quote is the same failure without a comment to cause
            # it. One quote at exactly one end is what release.sh mishandles.
            $v = $matches[1]
            $opens  = $v.StartsWith('"') -or $v.StartsWith("'")
            $closes = $v.EndsWith('"')   -or $v.EndsWith("'")
            if (($opens -and -not $closes) -or ($closes -and -not $opens)) {
                throw ("$pkgmetaPath line ${lineNo}: list item has an unbalanced quote. " +
                       "release.sh trims one quote from each end and would leave a stray " +
                       "one mid-string, which breaks its eval and ships an EMPTY zip. " +
                       "Offending line: $raw")
            }
        }

        if ($line -match '^ignore:\s*$') {
            $inIgnore = $true
            continue
        }
        if (-not $inIgnore) { continue }
        # End of the ignore block: any line starting at column 0 with non-list
        # content (i.e. a new top-level YAML key)
        if ($line -match '^\S' -and $line -notmatch '^-') {
            $inIgnore = $false
            continue
        }
        if ($line -match '^\s*-\s+(.+?)\s*$') {
            $entry = $matches[1].Trim()
            # Strip surrounding quotes (single or double)
            $entry = $entry -replace '^["'']', '' -replace '["'']$', ''
            if ($entry) { $ignores += $entry }
        }
    }
    return $ignores
}

# Always-skip -- the two rules .pkgmeta genuinely CANNOT express.
#
# ANY path component beginning with a dot. This mirrors the packager exactly:
# copy_directory_tree() prunes dotfiles and dot-folders unconditionally --
#     _cdt_find_cmd+=" \( -name \".*\" -a \! -name \".\" \) -prune"
# -- which is precisely why listing .git / .github / .vscode / .luarc.json /
# .markdownlint.json / .busted / .luacheckrc in .pkgmeta's `ignore:` block does
# NOTHING there. The rule has to live here instead.
#
# It is load-bearing rather than cosmetic: in these repos `.git` is a one-line
# gitdir POINTER FILE (the real git dir lives outside the WoW tree so
# Battle.net's fix_permissions sweep cannot trip over read-only git objects), so
# copying it into another flavor would aim that copy at the wrong repository.
#
# The second entry is this script itself, which no .pkgmeta entry covers because
# the released zip legitimately has no opinion about it.
$AlwaysSkip = @(
    '(^|\\)\.',
    '(^|\\)wow-version-replication\.ps1$'
)

$pkgmetaPath = Join-Path $Source ".pkgmeta"
$pkgIgnores  = Get-PkgmetaIgnores $pkgmetaPath
$pkgPatterns = $pkgIgnores | ForEach-Object { Convert-GlobToRegex $_ }

$SkipPatterns = $AlwaysSkip + $pkgPatterns

if ($pkgIgnores) {
    Write-Host ("Loaded {0} ignore globs from .pkgmeta:" -f $pkgIgnores.Count) -ForegroundColor DarkGray
    foreach ($g in $pkgIgnores) {
        Write-Host "  $g" -ForegroundColor DarkGray
    }
} else {
    Write-Host "WARNING: no ignore globs read from .pkgmeta -- dev files may replicate." -ForegroundColor Yellow
}
Write-Host ""

function Skip-Path([string]$rel) {
    foreach ($p in $SkipPatterns) {
        if ($rel -match $p) { return $true }
    }
    return $false
}

function Sync-File([string]$fullPath, [string]$verb) {
    $rel = $fullPath.Substring($Source.Length).TrimStart('\','/')
    if (Skip-Path $rel) {
        if ($DryRun) {
            Write-Host "[skip] $rel" -ForegroundColor DarkGray
        }
        return
    }

    $ts  = Get-Date -Format "HH:mm:ss"
    $tag = if ($DryRun) { "WOULD" } else { $verb }

    foreach ($dest in $Destinations) {
        $target = Join-Path $dest $rel
        if ($verb -eq "Deleted") {
            if (Test-Path $target) {
                if (-not $DryRun) {
                    Remove-Item $target -Force -Recurse -ErrorAction SilentlyContinue
                }
                Write-Host "[$ts] $($tag.PadRight(7)) DEL $rel" -ForegroundColor Red
            }
        } else {
            $dir = Split-Path $target -Parent
            if (-not (Test-Path $dir) -and -not $DryRun) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
            }
            if ($DryRun) {
                Write-Host "[$ts] $($tag.PadRight(7)) $rel" -ForegroundColor Cyan
            } else {
                # A locked target (WoW open + reading the file, AV scan, editor
                # write-replace in flight) makes Copy-Item throw. Don't let one
                # locked file kill the watcher -- log a RETRY and move on; the next
                # change event (or next launch's initial sync) self-heals it.
                try {
                    Copy-Item $fullPath $target -Force -ErrorAction Stop
                    Write-Host "[$ts] $($tag.PadRight(7)) $rel" -ForegroundColor Cyan
                } catch {
                    Write-Host "[$ts] RETRY   $rel (target busy: $($_.Exception.Message))" -ForegroundColor DarkYellow
                }
            }
        }
    }
}

# Full initial sync. Per-file try/catch so one unreadable/locked file (or a
# file that vanishes between enumeration and copy) can't abort the whole
# initial sync and exit the script before the watcher ever starts.
Write-Host "Initial sync..." -ForegroundColor Yellow
# -Force so hidden/dot files are ENUMERATED. They are then skipped by
# $AlwaysSkip, which is the point: a dry run has to be able to show a dotfile as
# [skip] rather than never seeing it, or the report cannot distinguish "excluded"
# from "not looked at".
Get-ChildItem -Path $Source -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try { Sync-File $_.FullName "SYNC" }
    catch { Write-Host "[init] skipped $($_.Exception.Message)" -ForegroundColor DarkYellow }
}
Write-Host "Ready." -ForegroundColor Green
Write-Host ""

# In dry-run mode, stop after the initial sync. The whole point is "show me what
# would happen"; sitting in a watcher loop afterwards adds nothing.
if ($DryRun) {
    Write-Host "Dry run complete. Nothing was copied or deleted." -ForegroundColor Yellow
    if ($script:InstanceMutex) {
        try { $script:InstanceMutex.ReleaseMutex() } catch {}
        $script:InstanceMutex.Dispose()
    }
    exit 0
}

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
