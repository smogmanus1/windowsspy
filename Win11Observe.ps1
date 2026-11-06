<#
.SYNOPSIS
    Windows 10/11 Observe Mode -- New PC? Start here.
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    The new-user entry point for WindowsSpy. Makes ZERO modifications to
    your system. What it does:

      1. Captures a BASELINE SNAPSHOT of your PC right now -- every
         setting WindowsSpy can track. This becomes your "Day 1" reference.

      2. Offers to install a WEEKLY SCHEDULED TASK that automatically
         takes a fresh snapshot and writes a brief report to your Desktop.
         You can see exactly what changes after each Windows Update.

      3. Tells you what to expect and where the reports will appear.

    No hardening. No registry edits. No services disabled. Pure observation.

    After a week or two of observation, you will see exactly what Microsoft
    is doing to your PC silently in the background. THEN, if you decide
    you want to push back on any of it, the hardening menu is one keystroke
    away in the launcher.

    The right order is OBSERVE FIRST, HARDEN SECOND. This script is the
    observe step.
.NOTES
    Run via RunWindowsSpy.bat (option O) or right-click and Run with PowerShell.
    Self-elevates to Administrator (needed to read HKLM and service state).
#>

# Self-elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
    try {
        Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host ""
        Write-Host "ABORT: Self-elevation failed -- $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# -- Helpers (same style as the suite) ----------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  WindowsSpy  --  OBSERVE MODE" -ForegroundColor Cyan
    Write-Host "  Watch what Windows does. Decide what to do about it." -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Note ($msg) { Write-Host "  $msg" -ForegroundColor Gray }
function Write-Step ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray
}

# -- Locate companion scripts --------------------------------------------

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$snapScript  = Join-Path $scriptDir 'Win11Snapshot.ps1'
$schedScript = Join-Path $scriptDir 'Win11ScheduleWeekly.ps1'
$snapDir     = "$env:USERPROFILE\Documents\Win11Hardener"

# -- Welcome + explanation ----------------------------------------------

Write-Header

Write-Host "  WHAT IS THIS?" -ForegroundColor White
Write-Host ""
Write-Note "WindowsSpy is a recording tool. It watches what Windows does"
Write-Note "to your PC -- which settings change after Windows Updates,"
Write-Note "which apps Microsoft silently installs, which services start"
Write-Note "running without your action -- and writes it down."
Write-Note ""
Write-Note "Most people never notice these changes. WindowsSpy gives you"
Write-Note "receipts: a baseline of how your PC looks right now, plus"
Write-Note "weekly reports of what changed."
Write-Note ""
Write-Note "Nothing is modified. No registry edits. No services disabled."
Write-Note "Just a record-keeping exercise. You decide what to do later."
Write-Host ""
Write-Host "  THIS RUN WILL:" -ForegroundColor White
Write-Note "    1. Capture a baseline snapshot (your 'Day 1')"
Write-Note "    2. Offer to schedule a weekly automatic snapshot"
Write-Note "    3. Tell you where the reports will appear"
Write-Host ""

$ok = Read-Host "  Type YES to proceed, or anything else to cancel"
if ($ok -ne 'YES') {
    Write-Host ""
    Write-Host "  Cancelled. No changes were made." -ForegroundColor Yellow
    Read-Host "  Press Enter to exit"
    exit
}

# -- Step 1: Take baseline snapshot --------------------------------------

Write-Step "STEP 1 of 3 -- CAPTURE BASELINE SNAPSHOT"

if (-not (Test-Path $snapScript)) {
    Write-Host "  ABORT: Cannot find Win11Snapshot.ps1 next to this script." -ForegroundColor Red
    Write-Host "  Expected at: $snapScript" -ForegroundColor Red
    Read-Host "  Press Enter to exit"
    exit 1
}

# Check whether a baseline already exists
$baselineMark = Join-Path $snapDir 'Win11Snapshot_BASELINE.xml'
if (Test-Path $baselineMark) {
    Write-Host ""
    Write-Info "A baseline snapshot already exists from a previous run."
    Write-Note "  Location: $baselineMark"
    Write-Note "  Captured: $((Get-Item $baselineMark).LastWriteTime)"
    Write-Host ""
    $replace = Read-Host "  Take a new baseline (overwrites the existing one)? Type YES or NO"
    if ($replace -ne 'YES') {
        Write-Note "Keeping the existing baseline."
        $skipSnapshot = $true
    }
}

if (-not $skipSnapshot) {
    Write-Note "Running Win11Snapshot.ps1 to capture current state..."
    Write-Note "This usually takes about 30 seconds. The snapshot reads"
    Write-Note "every setting WindowsSpy can track -- about 150 registry"
    Write-Note "values, 30 services, scheduled tasks, DNS, power state,"
    Write-Note "and the full Appx inventory."
    Write-Host ""

    # Invoke the snapshot script in-process
    & $snapScript

    # After it runs, copy/promote the LATEST.xml to BASELINE.xml
    $latest = Join-Path $snapDir 'Win11Snapshot_LATEST.xml'
    if (Test-Path $latest) {
        Copy-Item -Path $latest -Destination $baselineMark -Force
        Write-Host ""
        Write-OK "Baseline saved as: Win11Snapshot_BASELINE.xml"
        Write-Note "  Full path: $baselineMark"
    } else {
        Write-Host ""
        Write-Host "  WARNING: Snapshot script ran but no LATEST.xml was produced." -ForegroundColor Red
        Write-Note "Check the snapshot output above for errors."
    }
}

# -- Step 2: Schedule the weekly task ------------------------------------

Write-Step "STEP 2 of 3 -- WEEKLY AUTOMATIC OBSERVATION"

Write-Note "WindowsSpy can install a scheduled task that runs once a week,"
Write-Note "takes a fresh snapshot, compares it to your baseline, and"
Write-Note "writes a one-page report to your Desktop."
Write-Note ""
Write-Note "Default schedule: every Sunday at 3:00 AM."
Write-Note "Default report location: %USERPROFILE%\Desktop\WindowsSpy_Weekly_*.txt"
Write-Note ""
Write-Note "You can remove the task later via RunWindowsSpy.bat option X,"
Write-Note "or manually in Task Scheduler under \WindowsSpy\."
Write-Host ""

$sched = Read-Host "  Install the weekly task now? Type YES or NO"
if ($sched -eq 'YES') {
    if (-not (Test-Path $schedScript)) {
        Write-Host "  ERROR: Cannot find Win11ScheduleWeekly.ps1 next to this script." -ForegroundColor Red
    } else {
        & $schedScript -Install
    }
} else {
    Write-Note ""
    Write-Note "Skipped. You can install the weekly task later via the"
    Write-Note "launcher (RunWindowsSpy.bat option W)."
}

# -- Step 3: What to expect ---------------------------------------------

Write-Step "STEP 3 of 3 -- WHAT TO EXPECT"

Write-Note "From now on:"
Write-Note ""
Write-Note "  - Your baseline lives in:"
Write-Note "      $snapDir"
Write-Note "    Do not delete this folder. It is your reference point."
Write-Note ""
Write-Note "  - Weekly reports (if you installed the scheduled task) will"
Write-Note "    appear on your Desktop with filenames like:"
Write-Note "      WindowsSpy_Weekly_2026-05-25.txt"
Write-Note "    Open them in Notepad. They are plain text, short, and"
Write-Note "    written for non-technical readers."
Write-Note ""
Write-Note "  - To see a CUMULATIVE timeline of everything that has"
Write-Note "    changed since Day 1, run the launcher and pick option T"
Write-Note "    (View Timeline). That produces a single report covering"
Write-Note "    all observation period."
Write-Note ""
Write-Note "  - When you are ready to actually CHANGE things (block"
Write-Note "    telemetry, remove bloatware, etc.), the launcher's"
Write-Note "    HARDEN section is one keystroke away. But observe first."
Write-Host ""

Write-Host "  ============================================================" -ForegroundColor DarkCyan
Write-Host "   You are now in observe mode. WindowsSpy will watch quietly." -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor DarkCyan
Write-Host ""
Read-Host "  Press Enter to exit"
