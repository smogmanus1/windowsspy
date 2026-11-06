<#
.SYNOPSIS
    Windows 10/11 Weekly Observation Task -- runs unattended via Task Scheduler
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    The non-interactive script that the WindowsSpy weekly scheduled task
    invokes. Designed to run silently and write a brief report to the
    user's Desktop.

    Workflow:
      1. Run Win11Snapshot.ps1 to capture the current state
      2. Compare new snapshot against the most recent prior snapshot
         (NOT the baseline -- this gives "what changed this week",
         not "what changed since Day 1")
      3. Write a brief one-page report to Desktop

    For the cumulative since-baseline view, run Win11Timeline.ps1
    (launcher option T).

    No user interaction. Designed for unattended execution.
.NOTES
    Not meant to be run directly by users -- use Win11ScheduleWeekly.ps1
    to install/uninstall the scheduled task that calls this.

    Logs to %USERPROFILE%\Documents\Win11Hardener\WeeklyTask_<date>.log
    in addition to writing the user-facing Desktop report.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$snapDir   = "$env:USERPROFILE\Documents\Win11Hardener"
$stamp     = Get-Date -Format 'yyyy-MM-dd'

# -- Logging --------------------------------------------------------------
$taskLog = Join-Path $snapDir "WeeklyTask_$stamp.log"
function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Add-Content -Path $taskLog -Value $line -Encoding ASCII
}

Log "WindowsSpy Weekly Task starting"
Log "Script directory: $scriptDir"

# -- Find prior snapshot (NOT baseline -- the most recent before now) ---
$priorSnapshots = Get-ChildItem -Path $snapDir -Filter 'Win11Snapshot_*.xml' -File |
    Where-Object { $_.Name -notmatch '_LATEST\.xml$' } |
    Sort-Object LastWriteTime

$priorFile = $null
if ($priorSnapshots -and $priorSnapshots.Count -gt 0) {
    # Find the most recent non-baseline snapshot
    $nonBaseline = $priorSnapshots | Where-Object { $_.Name -notmatch '_BASELINE\.xml$' }
    if ($nonBaseline -and $nonBaseline.Count -gt 0) {
        $priorFile = $nonBaseline[-1].FullName
    } else {
        # Only baseline exists -- compare to that
        $priorFile = ($priorSnapshots | Where-Object { $_.Name -match '_BASELINE\.xml$' })[0].FullName
    }
}

if (-not $priorFile) {
    Log "ERROR: No prior snapshot found. Cannot diff."
    exit 1
}
Log "Prior snapshot: $priorFile"

# -- Take new snapshot ----------------------------------------------------
$snapScript = Join-Path $scriptDir 'Win11Snapshot.ps1'
if (-not (Test-Path $snapScript)) {
    Log "ERROR: Win11Snapshot.ps1 not found at $snapScript"
    exit 1
}

Log "Running snapshot..."
& $snapScript *> $null

$latest = Join-Path $snapDir 'Win11Snapshot_LATEST.xml'
if (-not (Test-Path $latest)) {
    Log "ERROR: Snapshot did not produce LATEST.xml"
    exit 1
}
Log "New snapshot complete: $latest"

# -- Run the diff ---------------------------------------------------------
$diffScript = Join-Path $scriptDir 'Win11Diff.ps1'
if (-not (Test-Path $diffScript)) {
    Log "ERROR: Win11Diff.ps1 not found at $diffScript"
    exit 1
}

$reportPath = "$env:USERPROFILE\Desktop\WindowsSpy_Weekly_$stamp.txt"
Log "Running diff vs $priorFile -> $reportPath"

$diffResult = & $diffScript -BaselineXml $priorFile -CurrentXml $latest -OutputPath $reportPath

# -- Write a friendlier weekly briefing on top of the technical report --
$briefing = @()
$briefing += "================================================================"
$briefing += "  WindowsSpy WEEKLY BRIEFING -- $stamp"
$briefing += "================================================================"
$briefing += ""
$briefing += "  This is your one-page summary of what changed on this PC"
$briefing += "  in the past week -- mostly things Microsoft did without"
$briefing += "  asking you."
$briefing += ""

$total = 0
if ($diffResult -and $diffResult.TotalEvents) { $total = $diffResult.TotalEvents }

if ($total -eq 0) {
    $briefing += "  QUIET WEEK."
    $briefing += "  No tracked changes detected. Either Windows behaved"
    $briefing += "  itself, or no major updates installed."
} else {
    $briefing += "  CHANGES THIS WEEK: $total"
    $briefing += ""
    if ($diffResult.Events.Appx -and $diffResult.Events.Appx.Count -gt 0) {
        $appAdds = $diffResult.Events.Appx | Where-Object { $_.Kind -in @('AppInstalled','ProvisionedAdded') }
        if ($appAdds -and $appAdds.Count -gt 0) {
            $briefing += "  APPS APPEARED (Microsoft installed these silently):"
            foreach ($a in $appAdds) {
                $briefing += "    + $($a.Name)"
            }
            $briefing += ""
        }
    }
    if ($diffResult.Events.Registry -and $diffResult.Events.Registry.Count -gt 0) {
        $reg = $diffResult.Events.Registry | Where-Object { $_.Group -in @('Telemetry','Ads','Cortana','Edge','OneDrive','Copilot','Recall','CloudContent') }
        if ($reg -and $reg.Count -gt 0) {
            $briefing += "  PRIVACY/TELEMETRY SETTINGS CHANGED:"
            foreach ($r in $reg | Select-Object -First 10) {
                $briefing += "    $($r.Group): $($r.Name)  $($r.OldValue) -> $($r.NewValue)"
            }
            if ($reg.Count -gt 10) { $briefing += "    ... and $($reg.Count - 10) more (see full report below)" }
            $briefing += ""
        }
    }
    if ($diffResult.Events.Services -and $diffResult.Events.Services.Count -gt 0) {
        $briefing += "  SERVICE START-TYPE CHANGES:"
        foreach ($s in $diffResult.Events.Services | Select-Object -First 5) {
            $briefing += "    $($s.Name)  $($s.OldValue) -> $($s.NewValue)"
        }
        $briefing += ""
    }
}

$briefing += ""
$briefing += "----------------------------------------------------------------"
$briefing += "  WHAT THIS MEANS"
$briefing += "----------------------------------------------------------------"
$briefing += "  - Items prefixed '+' are NEW since last week"
$briefing += "  - Items prefixed '-' were REMOVED since last week"
$briefing += "  - Privacy settings that changed are most likely the result"
$briefing += "    of a Windows Update reverting policies you applied"
$briefing += ""
$briefing += "  Full technical report is below this briefing."
$briefing += ""
$briefing += "  To act on any of these changes:"
$briefing += "  - Run RunWindowsSpy.bat from your WindowsSpy folder"
$briefing += "  - Pick T to see cumulative timeline since baseline"
$briefing += "  - Pick H to access the hardening menu"
$briefing += ""
$briefing += "================================================================"
$briefing += "  TECHNICAL DETAIL BELOW"
$briefing += "================================================================"
$briefing += ""

# Prepend our briefing to the diff report
if (Test-Path $reportPath) {
    $existing = Get-Content -Path $reportPath -Raw
    ($briefing -join "`r`n") + "`r`n`r`n" + $existing | Out-File -FilePath $reportPath -Encoding ASCII
}

Log "Weekly briefing written: $reportPath"
Log "WindowsSpy Weekly Task done. Total events: $total"

# -- Toast notification (best-effort, no failure if not available) -------
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
    $msg = if ($total -eq 0) { "Quiet week -- no changes detected." } else { "$total changes this week. See Desktop." }
    $template = "<toast><visual><binding template='ToastText02'><text id='1'>WindowsSpy weekly report</text><text id='2'>$msg</text></binding></visual></toast>"
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("WindowsSpy").Show($toast)
} catch {
    Log "Toast notification unavailable: $($_.Exception.Message)"
}

exit 0
