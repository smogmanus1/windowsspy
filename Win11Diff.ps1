<#
.SYNOPSIS
    Windows 10/11 Snapshot Diff -- Compare two snapshots, show what changed
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    READ-ONLY tool. Compares two snapshot XML files (produced by
    Win11Snapshot.ps1) and reports every difference, organized by category:

        - Registry values   (added / removed / value changed)
        - Services          (start type changes, status changes)
        - Scheduled tasks   (newly disabled, newly enabled, missing)
        - Appx packages     (newly installed -- bloatware reappearing!)
        - Provisioned Appx  (provisioning changes -- reinstall seeds)
        - Network / DNS     (DNS server changes)
        - Power             (active scheme, hiberfil, HiberbootEnabled)
        - File system flags (TRIM, last-access, 8.3 names)
        - Firewall rules    (telemetry-related rules added/removed)

    Output: a text report plus a structured PowerShell object you can pipe
    elsewhere. Writes to your Desktop by default. Makes ZERO changes.

    This is the engine behind weekly observation -- run it against a
    baseline (Day 1) and any later snapshot to see what Microsoft has
    done to your PC since then. Particularly useful AFTER a Windows
    Update, when policies often silently revert.

    Use the launcher's OBSERVE mode for guided weekly comparisons, or
    run this script directly to compare any two snapshots.
.PARAMETER BaselineXml
    Path to the BEFORE snapshot. Default: Win11Snapshot_BASELINE.xml in
    Documents\Win11Hardener\. If that does not exist, falls back to the
    oldest snapshot in that folder.
.PARAMETER CurrentXml
    Path to the AFTER snapshot. Default: Win11Snapshot_LATEST.xml.
.PARAMETER OutputPath
    Where to write the readable report. Default: Desktop\Win11Diff_<date>.txt
.NOTES
    Run via RunWindowsSpy.bat (option D) or invoke directly:
        .\Win11Diff.ps1
        .\Win11Diff.ps1 -BaselineXml "C:\path\base.xml" -CurrentXml "C:\path\now.xml"

    Does NOT require Administrator rights -- it only reads files. But the
    snapshots themselves had to be taken with admin to capture the full
    HKLM and service data.
#>

param(
    [string]$BaselineXml = '',
    [string]$CurrentXml  = '',
    [string]$OutputPath  = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# -- Helpers (same style as the rest of the suite) -----------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win10/11 Snapshot Diff  --  WindowsSpy by CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK    ($msg) { Write-Host "  [OK]      $msg" -ForegroundColor Green }
function Write-Add   ($msg) { Write-Host "  [+ ADD]   $msg" -ForegroundColor Magenta }
function Write-Rem   ($msg) { Write-Host "  [- REM]   $msg" -ForegroundColor DarkYellow }
function Write-Chg   ($msg) { Write-Host "  [~ CHG]   $msg" -ForegroundColor Yellow }
function Write-Fail  ($msg) { Write-Host "  [FAIL]    $msg" -ForegroundColor Red }
function Write-Info  ($msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Note  ($msg) { Write-Host "  [NOTE]    $msg" -ForegroundColor DarkGray }
function Write-Sep         { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
    Write-Sep
}

# -- Snapshot file resolution --------------------------------------------

$snapDir = "$env:USERPROFILE\Documents\Win11Hardener"

function Resolve-SnapshotFile {
    param([string]$Hint, [string]$DefaultName)

    if ($Hint -and (Test-Path $Hint)) { return (Resolve-Path $Hint).Path }

    $direct = Join-Path $snapDir $DefaultName
    if (Test-Path $direct) { return $direct }

    # Fall back: pick from the folder
    return $null
}

function Find-Snapshots {
    if (-not (Test-Path $snapDir)) { return @() }
    Get-ChildItem -Path $snapDir -Filter 'Win11Snapshot_*.xml' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '_LATEST\.xml$' } |
        Sort-Object LastWriteTime
}

# -- Core diff functions -------------------------------------------------

function Diff-Registry {
    param($Base, $Curr)

    Write-Title "REGISTRY VALUES"

    # Build hashtables keyed by Path + Name
    $baseMap = @{}
    foreach ($r in $Base) {
        $k = "$($r.Path)::$($r.Name)"
        $baseMap[$k] = $r
    }
    $currMap = @{}
    foreach ($r in $Curr) {
        $k = "$($r.Path)::$($r.Name)"
        $currMap[$k] = $r
    }

    $added = 0; $removed = 0; $changed = 0
    $events = New-Object System.Collections.Generic.List[object]

    foreach ($k in $currMap.Keys) {
        $c = $currMap[$k]
        if (-not $c.Existed) { continue }   # not present in current, skip
        if (-not $baseMap.ContainsKey($k)) {
            Write-Add ("{0}\{1} = {2}  [{3}]" -f $c.Path, $c.Name, $c.Value, $c.Group)
            $events.Add([PSCustomObject]@{ Kind='Add'; Group=$c.Group; Path=$c.Path; Name=$c.Name; OldValue=$null; NewValue=$c.Value })
            $added++
            continue
        }
        $b = $baseMap[$k]
        if (-not $b.Existed) {
            Write-Add ("{0}\{1} = {2}  (was unset)  [{3}]" -f $c.Path, $c.Name, $c.Value, $c.Group)
            $events.Add([PSCustomObject]@{ Kind='Add'; Group=$c.Group; Path=$c.Path; Name=$c.Name; OldValue=$null; NewValue=$c.Value })
            $added++
            continue
        }
        # Both existed -- compare values
        if ("$($b.Value)" -ne "$($c.Value)") {
            Write-Chg ("{0}\{1}  {2} -> {3}  [{4}]" -f $c.Path, $c.Name, $b.Value, $c.Value, $c.Group)
            $events.Add([PSCustomObject]@{ Kind='Change'; Group=$c.Group; Path=$c.Path; Name=$c.Name; OldValue=$b.Value; NewValue=$c.Value })
            $changed++
        }
    }

    foreach ($k in $baseMap.Keys) {
        $b = $baseMap[$k]
        if (-not $b.Existed) { continue }
        if (-not $currMap.ContainsKey($k) -or -not $currMap[$k].Existed) {
            Write-Rem ("{0}\{1} (was {2})  [{3}]" -f $b.Path, $b.Name, $b.Value, $b.Group)
            $events.Add([PSCustomObject]@{ Kind='Remove'; Group=$b.Group; Path=$b.Path; Name=$b.Name; OldValue=$b.Value; NewValue=$null })
            $removed++
        }
    }

    if ($added -eq 0 -and $removed -eq 0 -and $changed -eq 0) {
        Write-OK "No registry-value drift."
    }
    Write-Host ""
    Write-Info ("  Total: {0} added, {1} removed, {2} changed" -f $added, $removed, $changed)
    return $events
}

function Diff-Services {
    param($Base, $Curr)

    Write-Title "SERVICES"

    $baseMap = @{}
    foreach ($s in $Base) { $baseMap[$s.Name] = $s }
    $currMap = @{}
    foreach ($s in $Curr) { $currMap[$s.Name] = $s }

    $changes = 0
    $events = New-Object System.Collections.Generic.List[object]

    foreach ($k in $currMap.Keys) {
        $c = $currMap[$k]
        if ($baseMap.ContainsKey($k)) {
            $b = $baseMap[$k]
            if ("$($b.StartType)" -ne "$($c.StartType)") {
                Write-Chg ("{0}  StartType: {1} -> {2}" -f $c.Name, $b.StartType, $c.StartType)
                $events.Add([PSCustomObject]@{ Kind='ServiceStart'; Name=$c.Name; OldValue=$b.StartType; NewValue=$c.StartType })
                $changes++
            }
        } else {
            Write-Add ("{0}  (new entry)  StartType={1}" -f $c.Name, $c.StartType)
            $events.Add([PSCustomObject]@{ Kind='ServiceAdd'; Name=$c.Name; OldValue=$null; NewValue=$c.StartType })
            $changes++
        }
    }
    foreach ($k in $baseMap.Keys) {
        if (-not $currMap.ContainsKey($k)) {
            $b = $baseMap[$k]
            Write-Rem ("{0}  (gone)  was StartType={1}" -f $b.Name, $b.StartType)
            $events.Add([PSCustomObject]@{ Kind='ServiceRemove'; Name=$b.Name; OldValue=$b.StartType; NewValue=$null })
            $changes++
        }
    }

    if ($changes -eq 0) { Write-OK "No service drift." }
    return $events
}

function Diff-Tasks {
    param($Base, $Curr)

    Write-Title "SCHEDULED TASKS"

    $baseMap = @{}
    foreach ($t in $Base) { $baseMap["$($t.TaskPath)$($t.TaskName)"] = $t }
    $currMap = @{}
    foreach ($t in $Curr) { $currMap["$($t.TaskPath)$($t.TaskName)"] = $t }

    $changes = 0
    $events = New-Object System.Collections.Generic.List[object]

    foreach ($k in $currMap.Keys) {
        $c = $currMap[$k]
        if ($baseMap.ContainsKey($k)) {
            $b = $baseMap[$k]
            if ("$($b.State)" -ne "$($c.State)") {
                Write-Chg ("{0}{1}  {2} -> {3}" -f $c.TaskPath, $c.TaskName, $b.State, $c.State)
                $events.Add([PSCustomObject]@{ Kind='TaskState'; Name="$($c.TaskPath)$($c.TaskName)"; OldValue=$b.State; NewValue=$c.State })
                $changes++
            }
        }
    }

    if ($changes -eq 0) { Write-OK "No scheduled-task drift." }
    return $events
}

function Diff-Appx {
    param($BaseAppx, $CurrAppx)

    Write-Title "INSTALLED APPS (Appx packages -- bloatware tracking)"

    $baseInstalled = @{}
    foreach ($p in $BaseAppx.Installed) {
        if ($p -and $p.Name) { $baseInstalled[$p.Name] = $true }
    }
    $currInstalled = @{}
    foreach ($p in $CurrAppx.Installed) {
        if ($p -and $p.Name) { $currInstalled[$p.Name] = $true }
    }

    $newApps    = $currInstalled.Keys | Where-Object { -not $baseInstalled.ContainsKey($_) } | Sort-Object
    $goneApps   = $baseInstalled.Keys | Where-Object { -not $currInstalled.ContainsKey($_) } | Sort-Object

    $events = New-Object System.Collections.Generic.List[object]

    if ($newApps -and $newApps.Count -gt 0) {
        Write-Host ""
        Write-Host "  NEW since baseline:" -ForegroundColor Magenta
        foreach ($n in $newApps) {
            Write-Add $n
            $events.Add([PSCustomObject]@{ Kind='AppInstalled'; Name=$n })
        }
    }
    if ($goneApps -and $goneApps.Count -gt 0) {
        Write-Host ""
        Write-Host "  REMOVED since baseline:" -ForegroundColor DarkYellow
        foreach ($g in $goneApps) {
            Write-Rem $g
            $events.Add([PSCustomObject]@{ Kind='AppRemoved'; Name=$g })
        }
    }
    if ((-not $newApps) -and (-not $goneApps)) {
        Write-OK "No Appx package drift."
    }

    # Provisioned packages (the seed list that re-installs on new accounts)
    Write-Host ""
    Write-Title "PROVISIONED APPS (re-install seeds)"
    $baseProv = @{}
    foreach ($p in $BaseAppx.Provisioned) {
        if ($p -and $p.DisplayName) { $baseProv[$p.DisplayName] = $true }
    }
    $currProv = @{}
    foreach ($p in $CurrAppx.Provisioned) {
        if ($p -and $p.DisplayName) { $currProv[$p.DisplayName] = $true }
    }
    $newProv  = $currProv.Keys | Where-Object { -not $baseProv.ContainsKey($_) } | Sort-Object
    $goneProv = $baseProv.Keys | Where-Object { -not $currProv.ContainsKey($_) } | Sort-Object

    if ($newProv -and $newProv.Count -gt 0) {
        Write-Host "  NEWLY PROVISIONED (will be auto-installed for new accounts):" -ForegroundColor Magenta
        foreach ($n in $newProv) {
            Write-Add $n
            $events.Add([PSCustomObject]@{ Kind='ProvisionedAdded'; Name=$n })
        }
    }
    if ($goneProv -and $goneProv.Count -gt 0) {
        Write-Host "  REMOVED from provisioning:" -ForegroundColor DarkYellow
        foreach ($g in $goneProv) {
            Write-Rem $g
            $events.Add([PSCustomObject]@{ Kind='ProvisionedRemoved'; Name=$g })
        }
    }
    if ((-not $newProv) -and (-not $goneProv)) { Write-OK "No provisioning drift." }

    return $events
}

function Diff-Network {
    param($Base, $Curr)

    Write-Title "NETWORK / DNS"

    $changes = 0
    $events = New-Object System.Collections.Generic.List[object]

    $baseMap = @{}
    foreach ($a in $Base.Adapters) { $baseMap[$a.Name] = $a }
    $currMap = @{}
    foreach ($a in $Curr.Adapters) { $currMap[$a.Name] = $a }

    foreach ($k in $currMap.Keys) {
        $c = $currMap[$k]
        if ($baseMap.ContainsKey($k)) {
            $b = $baseMap[$k]
            if ($b.DnsIPv4 -ne $c.DnsIPv4) {
                Write-Chg ("Adapter '{0}'  DNS IPv4: {1} -> {2}" -f $c.Name, $b.DnsIPv4, $c.DnsIPv4)
                $events.Add([PSCustomObject]@{ Kind='DnsChange'; Name=$c.Name; OldValue=$b.DnsIPv4; NewValue=$c.DnsIPv4 })
                $changes++
            }
        }
    }

    if ("$($Base.TCP.AutoTuningLevel)" -ne "$($Curr.TCP.AutoTuningLevel)") {
        Write-Chg ("TCP AutoTuningLevel: {0} -> {1}" -f $Base.TCP.AutoTuningLevel, $Curr.TCP.AutoTuningLevel)
        $events.Add([PSCustomObject]@{ Kind='TcpTuning'; OldValue=$Base.TCP.AutoTuningLevel; NewValue=$Curr.TCP.AutoTuningLevel })
        $changes++
    }

    if ($changes -eq 0) { Write-OK "No network drift." }
    return $events
}

function Diff-Power {
    param($Base, $Curr)

    Write-Title "POWER / HIBERNATION / FAST STARTUP"

    $changes = 0
    $events = New-Object System.Collections.Generic.List[object]

    if ($Base.ActiveSchemeGuid -ne $Curr.ActiveSchemeGuid) {
        Write-Chg ("Active power scheme GUID: {0} -> {1}" -f $Base.ActiveSchemeGuid, $Curr.ActiveSchemeGuid)
        $events.Add([PSCustomObject]@{ Kind='PowerScheme'; OldValue=$Base.ActiveSchemeGuid; NewValue=$Curr.ActiveSchemeGuid })
        $changes++
    }
    if ($Base.HibernationFilePresent -ne $Curr.HibernationFilePresent) {
        Write-Chg ("hiberfil.sys present: {0} -> {1}" -f $Base.HibernationFilePresent, $Curr.HibernationFilePresent)
        $events.Add([PSCustomObject]@{ Kind='HiberFile'; OldValue=$Base.HibernationFilePresent; NewValue=$Curr.HibernationFilePresent })
        $changes++
    }
    if ("$($Base.HiberbootEnabled)" -ne "$($Curr.HiberbootEnabled)") {
        Write-Chg ("HiberbootEnabled (Fast Startup): {0} -> {1}" -f $Base.HiberbootEnabled, $Curr.HiberbootEnabled)
        $events.Add([PSCustomObject]@{ Kind='FastStartup'; OldValue=$Base.HiberbootEnabled; NewValue=$Curr.HiberbootEnabled })
        $changes++
    }
    if ($changes -eq 0) { Write-OK "No power drift." }
    return $events
}

function Diff-FileSystem {
    param($Base, $Curr)
    Write-Title "FILE SYSTEM FLAGS"
    $changes = 0
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($prop in @('Disable8dot3', 'DisableLastAccess', 'TrimNTFS', 'TrimReFS')) {
        $bv = $Base.$prop
        $cv = $Curr.$prop
        if ("$bv" -ne "$cv") {
            Write-Chg ("{0}: changed" -f $prop)
            $events.Add([PSCustomObject]@{ Kind='FsFlag'; Name=$prop; OldValue=$bv; NewValue=$cv })
            $changes++
        }
    }
    if ($changes -eq 0) { Write-OK "No file-system drift." }
    return $events
}

function Diff-Firewall {
    param($Base, $Curr)

    Write-Title "FIREWALL RULES (telemetry-related)"

    $baseMap = @{}
    foreach ($r in $Base) { $baseMap[$r.DisplayName] = $r }
    $currMap = @{}
    foreach ($r in $Curr) { $currMap[$r.DisplayName] = $r }

    $changes = 0
    $events = New-Object System.Collections.Generic.List[object]

    foreach ($k in $currMap.Keys) {
        if (-not $baseMap.ContainsKey($k)) {
            Write-Add ("Rule '{0}'  ({1})" -f $k, $currMap[$k].Action)
            $events.Add([PSCustomObject]@{ Kind='FwAdd'; Name=$k; NewValue=$currMap[$k].Action })
            $changes++
        }
    }
    foreach ($k in $baseMap.Keys) {
        if (-not $currMap.ContainsKey($k)) {
            Write-Rem ("Rule '{0}'  (was {1})" -f $k, $baseMap[$k].Action)
            $events.Add([PSCustomObject]@{ Kind='FwRemove'; Name=$k; OldValue=$baseMap[$k].Action })
            $changes++
        }
    }
    if ($changes -eq 0) { Write-OK "No firewall drift." }
    return $events
}

# -- Main flow -----------------------------------------------------------

Write-Header

# Resolve baseline
if (-not $BaselineXml) {
    $BaselineXml = Resolve-SnapshotFile -Hint '' -DefaultName 'Win11Snapshot_BASELINE.xml'
    if (-not $BaselineXml) {
        # Fall back: oldest snapshot in the folder
        $all = Find-Snapshots
        if ($all -and $all.Count -gt 0) {
            $BaselineXml = $all[0].FullName
            Write-Note "No BASELINE.xml found -- using oldest snapshot: $(Split-Path $BaselineXml -Leaf)"
        }
    }
}

# Resolve current
if (-not $CurrentXml) {
    $CurrentXml = Resolve-SnapshotFile -Hint '' -DefaultName 'Win11Snapshot_LATEST.xml'
    if (-not $CurrentXml) {
        $all = Find-Snapshots
        if ($all -and $all.Count -gt 0) {
            $CurrentXml = $all[-1].FullName
            Write-Note "No LATEST.xml found -- using newest snapshot: $(Split-Path $CurrentXml -Leaf)"
        }
    }
}

if (-not $BaselineXml -or -not (Test-Path $BaselineXml)) {
    Write-Fail "Could not find a baseline snapshot to compare against."
    Write-Host ""
    Write-Host "  Run Win11Snapshot.ps1 first (launcher option S or O) to capture a baseline." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit 1
}
if (-not $CurrentXml -or -not (Test-Path $CurrentXml)) {
    Write-Fail "Could not find a current snapshot to compare to."
    Write-Host ""
    Write-Host "  Run Win11Snapshot.ps1 again to capture the current state." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit 1
}
if ((Resolve-Path $BaselineXml).Path -eq (Resolve-Path $CurrentXml).Path) {
    Write-Fail "Baseline and Current are the same file. Nothing to diff."
    Read-Host "  Press Enter to exit"
    exit 1
}

Write-Host "  Baseline: $(Split-Path $BaselineXml -Leaf)" -ForegroundColor Gray
Write-Host "  Current:  $(Split-Path $CurrentXml -Leaf)" -ForegroundColor Gray
Write-Host ""

# Load snapshots
$base = Import-Clixml -Path $BaselineXml
$curr = Import-Clixml -Path $CurrentXml

# Date range
$baseDate = $base.Metadata.CapturedAt
$currDate = $curr.Metadata.CapturedAt
if ($baseDate -and $currDate) {
    try {
        $bd = [datetime]$baseDate
        $cd = [datetime]$currDate
        $span = ($cd - $bd).Days
        Write-Host ("  Period: {0} to {1}  ({2} days)" -f $bd.ToString('yyyy-MM-dd'), $cd.ToString('yyyy-MM-dd'), $span) -ForegroundColor DarkCyan
    } catch { }
}

# Run all diffs
$allEvents = @{
    Registry      = (Diff-Registry      $base.Registry        $curr.Registry)
    Services      = (Diff-Services      $base.Services        $curr.Services)
    Tasks         = (Diff-Tasks         $base.ScheduledTasks  $curr.ScheduledTasks)
    Appx          = (Diff-Appx          $base.Appx            $curr.Appx)
    Network       = (Diff-Network       $base.Network         $curr.Network)
    Power         = (Diff-Power         $base.Power           $curr.Power)
    FileSystem    = (Diff-FileSystem    $base.FileSystem      $curr.FileSystem)
    Firewall      = (Diff-Firewall      $base.Firewall        $curr.Firewall)
}

# -- Summary -------------------------------------------------------------
$total = 0
foreach ($k in $allEvents.Keys) {
    if ($allEvents[$k]) { $total += $allEvents[$k].Count }
}

Write-Host ""
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
Write-Host "   SUMMARY" -ForegroundColor Cyan
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
foreach ($cat in @('Registry','Services','Tasks','Appx','Network','Power','FileSystem','Firewall')) {
    $cnt = if ($allEvents[$cat]) { $allEvents[$cat].Count } else { 0 }
    $col = if ($cnt -gt 0) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("    {0,-14} {1,4} change(s)" -f $cat, $cnt) -ForegroundColor $col
}
Write-Host ""
if ($total -eq 0) {
    Write-Host "  No drift detected between the two snapshots." -ForegroundColor Green
} else {
    Write-Host ("  Total drift events: {0}" -f $total) -ForegroundColor Yellow
}
Write-Host ""

# -- Write report file ---------------------------------------------------
if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputPath = "$env:USERPROFILE\Desktop\Win11Diff_$stamp.txt"
}

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("Win10/11 Snapshot Diff Report")
$reportLines.Add("Generated:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$reportLines.Add("Baseline:   $BaselineXml")
$reportLines.Add("Current:    $CurrentXml")
$reportLines.Add("Computer:   $env:COMPUTERNAME")
$reportLines.Add(("=" * 70))

foreach ($cat in @('Registry','Services','Tasks','Appx','Network','Power','FileSystem','Firewall')) {
    $events = $allEvents[$cat]
    if (-not $events -or $events.Count -eq 0) { continue }
    $reportLines.Add("")
    $reportLines.Add("[$cat]  ($($events.Count) event(s))")
    $reportLines.Add(("-" * 70))
    foreach ($e in $events) {
        # Render each event as a one-line summary
        $parts = @($e.Kind)
        if ($e.PSObject.Properties.Name -contains 'Group' -and $e.Group)     { $parts += "group=$($e.Group)" }
        if ($e.PSObject.Properties.Name -contains 'Path'  -and $e.Path)      { $parts += "path=$($e.Path)" }
        if ($e.PSObject.Properties.Name -contains 'Name'  -and $e.Name)      { $parts += "name=$($e.Name)" }
        if ($e.PSObject.Properties.Name -contains 'OldValue' -and $null -ne $e.OldValue) { $parts += "old=$($e.OldValue)" }
        if ($e.PSObject.Properties.Name -contains 'NewValue' -and $null -ne $e.NewValue) { $parts += "new=$($e.NewValue)" }
        $reportLines.Add("  " + ($parts -join '  '))
    }
}

$reportLines.Add("")
$reportLines.Add(("=" * 70))
$reportLines.Add("END OF REPORT")

$reportLines | Out-File -FilePath $OutputPath -Encoding ASCII
Write-OK "Report saved: $OutputPath"
Write-Host ""

# Return the structured object so callers (Timeline, scheduled task) can use it
[PSCustomObject]@{
    BaselineFile = $BaselineXml
    CurrentFile  = $CurrentXml
    BaselineDate = $baseDate
    CurrentDate  = $currDate
    TotalEvents  = $total
    Events       = $allEvents
    ReportPath   = $OutputPath
}
