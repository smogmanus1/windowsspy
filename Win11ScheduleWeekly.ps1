<#
.SYNOPSIS
    Windows 10/11 Weekly Task Installer -- install or remove the scheduled task
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    Manages the Windows Task Scheduler entry that runs WindowsSpy weekly.

    Task details:
      - Folder:     \WindowsSpy\
      - Name:       WeeklyObservation
      - Trigger:    Every Sunday at 3:00 AM
      - Action:     Runs Win11WeeklyTask.ps1 in the same folder
      - Run level:  Highest (Administrator)
      - User:       Currently signed-in user (interactive)

    The task uses the script's current folder location, so DO NOT move
    the WindowsSpy folder after installing the task without re-installing.

    To verify the task installed correctly: open Task Scheduler,
    expand 'Task Scheduler Library' -> 'WindowsSpy' -> 'WeeklyObservation'.
.PARAMETER Install
    Install the weekly task. If a task already exists with the same name,
    it will be removed and recreated.
.PARAMETER Uninstall
    Remove the weekly task.
.PARAMETER Status
    Show the status of the task (default if no switch given).
.NOTES
    Run via RunWindowsSpy.bat (option W) or directly:
        .\Win11ScheduleWeekly.ps1 -Install
        .\Win11ScheduleWeekly.ps1 -Uninstall
        .\Win11ScheduleWeekly.ps1 -Status
    Self-elevates to Administrator.
#>

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

# Self-elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
    $argline = @()
    if ($Install)   { $argline += '-Install' }
    if ($Uninstall) { $argline += '-Uninstall' }
    if ($Status)    { $argline += '-Status' }
    $argStr = $argline -join ' '
    try {
        Start-Process PowerShell -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`" {1}" -f $MyInvocation.MyCommand.Path, $argStr) -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "ABORT: Self-elevation failed -- $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# -- Constants ------------------------------------------------------------
$TaskPath = '\WindowsSpy\'
$TaskName = 'WeeklyObservation'
$FullName = "$TaskPath$TaskName"

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$weeklyTask  = Join-Path $scriptDir 'Win11WeeklyTask.ps1'

# -- Default to status if no switch -------------------------------------
if (-not $Install -and -not $Uninstall -and -not $Status) {
    $Status = $true
}

# -- Status ---------------------------------------------------------------
function Show-Status {
    Write-Host ""
    Write-Host "  WindowsSpy Weekly Task -- Status" -ForegroundColor Cyan
    Write-Host "  --------------------------------" -ForegroundColor DarkCyan
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) {
        Write-Host "  Status: NOT INSTALLED" -ForegroundColor Yellow
        Write-Host "  Run with -Install to set it up." -ForegroundColor Gray
        return
    }
    Write-Host "  Status: INSTALLED" -ForegroundColor Green
    Write-Host "  State:  $($t.State)"
    $info = Get-ScheduledTaskInfo -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($info) {
        Write-Host "  Next run:   $($info.NextRunTime)"
        Write-Host "  Last run:   $($info.LastRunTime)"
        Write-Host "  Last result: $($info.LastTaskResult) (0 = success)"
    }
    Write-Host ""
    foreach ($trig in $t.Triggers) {
        Write-Host "  Trigger: $($trig.GetType().Name)" -ForegroundColor Gray
    }
    foreach ($act in $t.Actions) {
        Write-Host "  Action:  $($act.Execute) $($act.Arguments)" -ForegroundColor Gray
    }
}

# -- Uninstall ------------------------------------------------------------
function Do-Uninstall {
    Write-Host ""
    Write-Host "  Removing WindowsSpy weekly task..." -ForegroundColor Yellow
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) {
        Write-Host "  Task was not installed -- nothing to remove." -ForegroundColor Gray
        return
    }
    Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    Write-Host "  [OK] Task removed." -ForegroundColor Green

    # Try to remove the \WindowsSpy\ folder if now empty
    $remaining = Get-ScheduledTask -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $remaining) {
        try {
            $sched = New-Object -ComObject 'Schedule.Service'
            $sched.Connect()
            $folder = $sched.GetFolder($TaskPath.TrimEnd('\'))
            $parent = $sched.GetFolder('\')
            $parent.DeleteFolder($TaskPath.Trim('\'), 0)
            Write-Host "  [OK] Task folder $TaskPath removed (was empty)." -ForegroundColor Green
        } catch {
            # Folder removal is best-effort
        }
    }
}

# -- Install --------------------------------------------------------------
function Do-Install {
    Write-Host ""
    Write-Host "  Installing WindowsSpy weekly task..." -ForegroundColor Cyan

    if (-not (Test-Path $weeklyTask)) {
        Write-Host "  ABORT: Win11WeeklyTask.ps1 not found at $weeklyTask" -ForegroundColor Red
        Write-Host "  This script must live alongside Win11WeeklyTask.ps1." -ForegroundColor Red
        exit 1
    }

    # Remove existing if present (clean re-install)
    $existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  Existing task found -- replacing." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Build the task
    $action = New-ScheduledTaskAction `
        -Execute 'PowerShell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$weeklyTask`"" `
        -WorkingDirectory $scriptDir

    # Trigger: every Sunday at 3:00 AM
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am

    # Settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
        -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

    # Principal -- current user, highest privileges, interactive logon
    $userId = "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal `
        -UserId $userId `
        -LogonType Interactive `
        -RunLevel Highest

    # Register
    Register-ScheduledTask `
        -TaskPath $TaskPath `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "WindowsSpy: weekly snapshot + diff. CrisisOfTruth.org" `
        -Force | Out-Null

    Write-Host ""
    Write-Host "  [OK] Weekly task installed." -ForegroundColor Green
    Write-Host "       Folder:   $TaskPath" -ForegroundColor Gray
    Write-Host "       Name:     $TaskName" -ForegroundColor Gray
    Write-Host "       Trigger:  Every Sunday at 3:00 AM" -ForegroundColor Gray
    Write-Host "       Script:   $weeklyTask" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  The task will run automatically. To see it sooner, open" -ForegroundColor Gray
    Write-Host "  Task Scheduler, find it, right-click, Run." -ForegroundColor Gray
}

# -- Main dispatch --------------------------------------------------------
if ($Install)   { Do-Install;   Show-Status }
elseif ($Uninstall) { Do-Uninstall; Show-Status }
else                { Show-Status }

Write-Host ""
