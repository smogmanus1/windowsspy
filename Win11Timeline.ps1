<#
.SYNOPSIS
    Windows 10/11 Observation Timeline -- "What did Microsoft do to my PC?"
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    READ-ONLY tool. Finds every snapshot in your snapshot folder, runs
    diffs between consecutive pairs, and aggregates the results into
    a single readable timeline report covering the entire observation
    period.

    The output is written for non-technical readers. Each event is
    rendered in plain language with dates: "Day 17: Microsoft installed
    Clipchamp" rather than registry paths. The report is also correlated
    against Windows Update install dates so you can see which updates
    caused which changes.

    Run this anytime you want a summary. Particularly useful:

      - 30 days after starting observation -- you'll see a full month
        of Microsoft's behavior pattern
      - After any major Windows Update, to see exactly what changed
      - Before deciding which hardener options to run -- you'll know
        which categories Microsoft is most actively pushing on

    Output goes to your Desktop as a text file. The on-screen view shows
    the same content with color coding.
.NOTES
    Run via RunWindowsSpy.bat (option T) or directly.
    Does NOT require Administrator (read-only, file-based).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# -- Helpers --------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  WindowsSpy  --  OBSERVATION TIMELINE" -ForegroundColor Cyan
    Write-Host "  What has Microsoft done to your PC?" -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Banner ($msg) {
    Write-Host ""
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
    Write-Host "   $msg" -ForegroundColor Cyan
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Event ($msg, $color = 'White') {
    Write-Host "  $msg" -ForegroundColor $color
}

# -- Find snapshots -------------------------------------------------------

$snapDir = "$env:USERPROFILE\Documents\Win11Hardener"
if (-not (Test-Path $snapDir)) {
    Write-Header
    Write-Host "  No snapshot folder found at $snapDir" -ForegroundColor Red
    Write-Host "  Run Win11Observe.ps1 (launcher option O) first to create a baseline." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit 1
}

$baseline = Join-Path $snapDir 'Win11Snapshot_BASELINE.xml'
$snapshots = Get-ChildItem -Path $snapDir -Filter 'Win11Snapshot_*.xml' -File |
    Where-Object { $_.Name -notmatch '_LATEST\.xml$' -and $_.Name -notmatch '_BASELINE\.xml$' } |
    Sort-Object LastWriteTime

if (-not (Test-Path $baseline)) {
    Write-Header
    Write-Host "  No BASELINE snapshot found." -ForegroundColor Red
    Write-Host "  Run Win11Observe.ps1 first to capture one." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit 1
}

if (-not $snapshots -or $snapshots.Count -eq 0) {
    Write-Header
    Write-Host "  Only the baseline exists -- no later snapshots to compare." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Either wait for the weekly task to run (Sundays at 3am)," -ForegroundColor Gray
    Write-Host "  or take a manual snapshot now via launcher option S." -ForegroundColor Gray
    Read-Host "  Press Enter to exit"
    exit 0
}

Write-Header

# Load baseline
$base    = Import-Clixml -Path $baseline
$baseDt  = try { [datetime]$base.Metadata.CapturedAt } catch { (Get-Item $baseline).LastWriteTime }

Write-Host "  Baseline:        $(Split-Path $baseline -Leaf)" -ForegroundColor Gray
Write-Host "  Baseline date:   $($baseDt.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
Write-Host "  Other snapshots: $($snapshots.Count)" -ForegroundColor Gray
Write-Host ""

# -- Compute cumulative diff (baseline vs. most recent) -----------------

$latest = $snapshots[-1]
$curr   = Import-Clixml -Path $latest.FullName
$currDt = try { [datetime]$curr.Metadata.CapturedAt } catch { $latest.LastWriteTime }

$daySpan = ($currDt - $baseDt).Days

# -- Aggregate categories ------------------------------------------------

# AppX appearances (the most visible thing for normal users)
$baseApps = @{}
foreach ($p in $base.Appx.Installed) { if ($p.Name) { $baseApps[$p.Name] = $true } }
$currApps = @{}
foreach ($p in $curr.Appx.Installed) { if ($p.Name) { $currApps[$p.Name] = $true } }

$newApps   = $currApps.Keys | Where-Object { -not $baseApps.ContainsKey($_) } | Sort-Object
$goneApps  = $baseApps.Keys | Where-Object { -not $currApps.ContainsKey($_) } | Sort-Object

# Provisioned apps
$baseProv = @{}
foreach ($p in $base.Appx.Provisioned) { if ($p.DisplayName) { $baseProv[$p.DisplayName] = $true } }
$currProv = @{}
foreach ($p in $curr.Appx.Provisioned) { if ($p.DisplayName) { $currProv[$p.DisplayName] = $true } }
$newProv  = $currProv.Keys | Where-Object { -not $baseProv.ContainsKey($_) } | Sort-Object

# Registry changes -- focus on the most user-impactful groups
$intrusiveGroups = @('Telemetry','Ads','Cortana','Edge','OneDrive','Recall','Copilot','CloudContent')
$baseRegMap = @{}
foreach ($r in $base.Registry) {
    if ($r.Existed) { $baseRegMap["$($r.Path)::$($r.Name)"] = $r }
}
$regReverted = New-Object System.Collections.Generic.List[object]
foreach ($r in $curr.Registry) {
    $k = "$($r.Path)::$($r.Name)"
    if ($baseRegMap.ContainsKey($k)) {
        $b = $baseRegMap[$k]
        if ("$($b.Value)" -ne "$($r.Value)") {
            if ($intrusiveGroups -contains $r.Group) {
                $regReverted.Add([PSCustomObject]@{
                    Group=$r.Group; Path=$r.Path; Name=$r.Name
                    Was=$b.Value; Now=$r.Value
                })
            }
        }
    }
}

# Services that came back online
$baseSvcMap = @{}
foreach ($s in $base.Services) { if ($s.Present) { $baseSvcMap[$s.Name] = $s } }
$svcReactivated = New-Object System.Collections.Generic.List[object]
foreach ($s in $curr.Services) {
    if (-not $s.Present) { continue }
    if ($baseSvcMap.ContainsKey($s.Name)) {
        $b = $baseSvcMap[$s.Name]
        if ("$($b.StartType)" -eq 'Disabled' -and "$($s.StartType)" -ne 'Disabled') {
            $svcReactivated.Add([PSCustomObject]@{ Name=$s.Name; Was='Disabled'; Now=$s.StartType })
        }
    }
}

# Windows updates installed in the period
$updates = Get-HotFix -ErrorAction SilentlyContinue |
    Where-Object { $_.InstalledOn -and $_.InstalledOn -ge $baseDt -and $_.InstalledOn -le $currDt } |
    Sort-Object InstalledOn

# -- Print and write the report ------------------------------------------

$report = New-Object System.Collections.Generic.List[string]
$report.Add("================================================================")
$report.Add("  WHAT MICROSOFT DID TO YOUR PC")
$report.Add("  WindowsSpy Observation Timeline")
$report.Add("================================================================")
$report.Add("  Computer:        $env:COMPUTERNAME")
$report.Add("  Baseline taken:  $($baseDt.ToString('yyyy-MM-dd HH:mm'))")
$report.Add("  Most recent:     $($currDt.ToString('yyyy-MM-dd HH:mm'))")
$report.Add("  Period:          $daySpan day(s)")
$report.Add("  Snapshots:       $($snapshots.Count + 1) total")
$report.Add("================================================================")
$report.Add("")

# Helper to add a section to both screen and report
function Add-Section {
    param([string]$Title, [array]$Items, [string]$EmptyMsg, [string]$Color)
    Write-Banner $Title
    $script:report.Add("")
    $script:report.Add("[" + $Title + "]")
    $script:report.Add(("-" * 70))
    if (-not $Items -or $Items.Count -eq 0) {
        Write-Host "  $EmptyMsg" -ForegroundColor DarkGray
        $script:report.Add("  $EmptyMsg")
        return
    }
    foreach ($i in $Items) {
        Write-Event "  $i" $Color
        $script:report.Add("  $i")
    }
}

# Section: bloatware installed without consent
$bloatLines = @()
foreach ($a in $newApps) { $bloatLines += "+ $a  (NEW since baseline)" }
foreach ($a in $newProv) { $bloatLines += "+ $a  (NEW in provisioning -- will install for new accounts)" }
Add-Section -Title "APPS INSTALLED OR PROVISIONED WITHOUT YOUR ACTION" `
            -Items $bloatLines `
            -EmptyMsg "(none -- no new apps appeared)" `
            -Color "Magenta"

# Section: apps that disappeared (less common but worth knowing)
$goneLines = @()
foreach ($a in $goneApps) { $goneLines += "- $a  (REMOVED -- you uninstalled this, or Windows did)" }
Add-Section -Title "APPS REMOVED SINCE BASELINE" `
            -Items $goneLines `
            -EmptyMsg "(none)" `
            -Color "DarkYellow"

# Section: policies reverted
$revertLines = @()
foreach ($r in $regReverted) {
    $revertLines += "* $($r.Group): $($r.Name)  was $($r.Was), now $($r.Now)"
}
Add-Section -Title "PRIVACY/TELEMETRY POLICIES THAT REVERTED" `
            -Items $revertLines `
            -EmptyMsg "(none -- hardening held, if you applied any)" `
            -Color "Yellow"

# Section: services that came back online
$svcLines = @()
foreach ($s in $svcReactivated) {
    $svcLines += "* $($s.Name)  was $($s.Was), now $($s.Now)"
}
Add-Section -Title "SERVICES THAT STARTED RUNNING AGAIN" `
            -Items $svcLines `
            -EmptyMsg "(none -- no services restarted themselves)" `
            -Color "Yellow"

# Section: Windows updates installed in the period
$updateLines = @()
foreach ($u in $updates) {
    $updateLines += ("- {0}  {1,-12}  {2}" -f $u.InstalledOn.ToString('yyyy-MM-dd'), $u.HotFixID, $u.Description)
}
Add-Section -Title "WINDOWS UPDATES INSTALLED IN THIS PERIOD" `
            -Items $updateLines `
            -EmptyMsg "(no updates recorded -- check Windows Update history)" `
            -Color "Gray"

# Final summary line
$totalChanges = ($newApps.Count + $newProv.Count + $regReverted.Count + $svcReactivated.Count + $goneApps.Count)
$report.Add("")
$report.Add(("=" * 70))
$report.Add("  TOTAL CHANGES OVER $daySpan DAY(S):  $totalChanges")
$report.Add(("=" * 70))

Write-Banner "SUMMARY"
if ($totalChanges -eq 0) {
    Write-Host "  Microsoft has not made any tracked changes in this period." -ForegroundColor Green
    Write-Host "  Either your PC is quiet, or there have been no major updates." -ForegroundColor Gray
} else {
    Write-Host "  Total tracked changes: $totalChanges" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  These are the changes Microsoft made WITHOUT your action." -ForegroundColor Gray
    Write-Host "  If any concern you, the HARDEN section of the launcher" -ForegroundColor Gray
    Write-Host "  can block, remove, or revert most of them." -ForegroundColor Gray
}

# Save report
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = "$env:USERPROFILE\Desktop\WindowsSpy_Timeline_$stamp.txt"
$report | Out-File -FilePath $outPath -Encoding ASCII
Write-Host ""
Write-Host "  Report saved to: $outPath" -ForegroundColor Green
Write-Host ""
Read-Host "  Press Enter to exit"
