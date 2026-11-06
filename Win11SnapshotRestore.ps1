<#
.SYNOPSIS
    Windows 11 Snapshot Restore -- revert from a Win11Snapshot.ps1 backup
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    Loads a snapshot file produced by Win11Snapshot.ps1 and reverts the
    captured registry values, services, and scheduled-task states back
    to what they were at the time of capture.

    Two ways to use this script:

      A) "Restore everything"   -- pull every captured setting back
                                   to its snapshot value in one shot.
      B) "Restore by group"     -- pick a group (Telemetry, Ads, DNS,
                                   Edge, Cortana, etc.) and only revert
                                   that subset.

    Before doing anything, this script ALWAYS captures a fresh snapshot
    of the CURRENT state. That way, if the restore makes things worse,
    you can roll forward by treating that pre-restore snapshot as your
    new baseline.

    What this script restores:
      - Every registry value listed in the snapshot
      - Service start types (Automatic / Manual / Disabled)
      - Scheduled task enabled / disabled state
      - DNS servers per adapter
      - Hibernation on/off (powercfg -h)
      - Fast Startup on/off (HiberbootEnabled)
      - File-system flags (8.3 names, last-access)

    What this script DOES NOT restore:
      - Removed Appx packages. If you removed bloatware you cannot
        reinstall it from the registry. The script lists which Appx
        packages have changed since the snapshot, so you can decide.
      - File-type associations. The DISM export from snapshot time is
        re-imported, but Windows only honours that for NEW user
        profiles. For your current profile, the script lists which
        extensions changed so you can fix them in Settings.
      - Personal data, installed programs outside the registry, or
        anything else outside the captured surface area.
.NOTES
    Self-elevates to Administrator automatically.
    Run via RunHardener.bat (option U) or right-click + Run with PowerShell.
#>

# -- Self elevation -----------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
    Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
    exit
}

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win11 Snapshot Restore  --  CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK    ($msg) { Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Fail  ($msg) { Write-Host "  [FAIL]  $msg" -ForegroundColor Red }
function Write-Info  ($msg) { Write-Host "  [..]    $msg" -ForegroundColor Yellow }
function Write-Skip  ($msg) { Write-Host "  [SKIP]  $msg" -ForegroundColor DarkGray }
function Write-Note  ($msg) { Write-Host "          $msg" -ForegroundColor Gray }
function Write-Sep         { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
    Write-Sep
}

$script:ChangedCount = 0
$script:NoOpCount    = 0
$script:FailCount    = 0
$script:Log          = [System.Collections.Generic.List[string]]::new()

function Log-Line ($s) { $script:Log.Add($s) | Out-Null }

# ---------------------------------------------------------------------------
#  LOCATE + LOAD SNAPSHOT
# ---------------------------------------------------------------------------

$script:SnapDir   = Join-Path $env:USERPROFILE 'Documents\Win11Hardener'
$script:LatestXml = Join-Path $script:SnapDir   'Win11Snapshot_LATEST.xml'

function Find-Snapshot {
    Write-Title "LOCATE SNAPSHOT"

    if (-not (Test-Path $script:SnapDir)) {
        Write-Fail "Snapshot folder does not exist: $script:SnapDir"
        Write-Note "Run Win11Snapshot.ps1 first."
        return $null
    }

    $candidates = Get-ChildItem -Path $script:SnapDir -Filter 'Win11Snapshot_*.xml' -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notlike '*_FileAssoc.xml' } |
                  Sort-Object LastWriteTime -Descending

    if (-not $candidates) {
        Write-Fail "No snapshot files found in $script:SnapDir"
        Write-Note "Run Win11Snapshot.ps1 first."
        return $null
    }

    Write-Host "  Available snapshots (newest first):" -ForegroundColor White
    Write-Host ""
    $i = 1
    $list = @()
    foreach ($c in $candidates | Select-Object -First 12) {
        $marker = if ($c.Name -eq 'Win11Snapshot_LATEST.xml') { '  (LATEST)' } else { '' }
        Write-Host ("   {0,2}  {1,-50}  {2}{3}" -f $i, $c.Name, $c.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $marker) -ForegroundColor Gray
        $list += $c
        $i++
    }
    Write-Host ""
    Write-Host "    Press Enter to use LATEST, or type a number:" -ForegroundColor White
    $pick = (Read-Host "  Choice").Trim()
    if (-not $pick) {
        if (Test-Path $script:LatestXml) { return $script:LatestXml }
        return $list[0].FullName
    }
    if ($pick -as [int] -and [int]$pick -ge 1 -and [int]$pick -le $list.Count) {
        return $list[[int]$pick - 1].FullName
    }
    Write-Fail "Invalid choice"
    return $null
}

function Load-Snapshot ($Path) {
    Write-Title "LOAD SNAPSHOT"
    try {
        $snap = Import-Clixml -Path $Path
        Write-OK ("Loaded: {0}" -f $Path)
        Write-Note ("Captured: {0}" -f $snap.Metadata.CapturedAt)
        Write-Note ("Host:     {0}" -f $snap.Metadata.Hostname)
        Write-Note ("Build:    {0}.{1}  ({2})" -f $snap.Metadata.OSBuildNumber, $snap.Metadata.UBR, $snap.Metadata.DisplayVersion)
        if ($snap.Metadata.Hostname -ne $env:COMPUTERNAME) {
            Write-Host ""
            Write-Host "  WARNING: This snapshot is from a DIFFERENT host." -ForegroundColor Red
            Write-Host ("           Snapshot host: {0}" -f $snap.Metadata.Hostname) -ForegroundColor Red
            Write-Host ("           Current host:  {0}" -f $env:COMPUTERNAME) -ForegroundColor Red
            Write-Host ""
            $proceed = (Read-Host "  Type CONTINUE to proceed anyway").Trim()
            if ($proceed -ne 'CONTINUE') {
                Write-Note "Aborted."
                return $null
            }
        }
        return $snap
    } catch {
        Write-Fail ("Failed to load snapshot: {0}" -f $_.Exception.Message)
        return $null
    }
}

# ---------------------------------------------------------------------------
#  SAFETY: pre-restore snapshot of CURRENT state
# ---------------------------------------------------------------------------

function New-PreRestoreSnapshot {
    Write-Title "PRE-RESTORE SAFETY SNAPSHOT"
    $snapScript = Join-Path $PSScriptRoot 'Win11Snapshot.ps1'
    if (-not (Test-Path $snapScript)) {
        Write-Skip "Win11Snapshot.ps1 not found in this folder -- skipping safety snapshot."
        Write-Note "Restore will proceed but you will not have a one-click roll-forward."
        return
    }
    Write-Info "Running Win11Snapshot.ps1 to capture CURRENT state before restoring..."
    $proc = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$snapScript) `
        -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -eq 0) {
        Write-OK "Pre-restore snapshot complete."
    } else {
        Write-Fail ("Pre-restore snapshot returned exit code {0}" -f $proc.ExitCode)
        Write-Note "Continuing anyway -- but you have no automatic roll-forward."
    }
}

# ---------------------------------------------------------------------------
#  REGISTRY RESTORE PRIMITIVE
# ---------------------------------------------------------------------------

function Restore-RegRow {
    param([PSCustomObject]$Row)

    $tag = "$($Row.Path)\$($Row.Name)"

    if ($Row.Existed) {
        # Set / restore the value -------------------------------------
        if (-not (Test-Path $Row.Path)) {
            try {
                New-Item -Path $Row.Path -Force | Out-Null
            } catch {
                Write-Fail "Cannot create $($Row.Path)"
                Log-Line "[FAIL] $tag -- could not create key"
                $script:FailCount++
                return
            }
        }
        $current = (Get-ItemProperty -Path $Row.Path -ErrorAction SilentlyContinue).($Row.Name)
        if ("$current" -eq "$($Row.Value)") {
            Write-Skip "$tag already at snapshot value"
            Log-Line "[NOOP] $tag = $($Row.Value)"
            $script:NoOpCount++
            return
        }
        try {
            $type = if ($Row.Type) { $Row.Type } else { 'DWord' }
            # Convert object types Export-Clixml rehydrated as strings back to expected forms
            $val = $Row.Value
            if ($type -eq 'DWord' -or $type -eq 'QWord') {
                $val = [int64]$Row.Value
            }
            Set-ItemProperty -Path $Row.Path -Name $Row.Name -Value $val -Type $type -Force
            Write-OK "$tag <= $($Row.Value)"
            Log-Line "[SET]  $tag = $($Row.Value)  (type=$type)"
            $script:ChangedCount++
        } catch {
            Write-Fail "$tag -- $($_.Exception.Message)"
            Log-Line "[FAIL] $tag -- $($_.Exception.Message)"
            $script:FailCount++
        }
    } else {
        # Snapshot recorded the value as NOT SET -- so delete it
        # (this is critical: leaving it set means we have not actually restored)
        if (Test-Path $Row.Path) {
            $cur = Get-ItemProperty -Path $Row.Path -ErrorAction SilentlyContinue
            if ($cur -and ($cur.PSObject.Properties.Name -contains $Row.Name)) {
                try {
                    Remove-ItemProperty -Path $Row.Path -Name $Row.Name -Force
                    Write-OK "$tag deleted (was unset at snapshot)"
                    Log-Line "[DEL]  $tag (was unset at snapshot time)"
                    $script:ChangedCount++
                } catch {
                    Write-Fail "$tag -- $($_.Exception.Message)"
                    Log-Line "[FAIL] $tag delete -- $($_.Exception.Message)"
                    $script:FailCount++
                }
                return
            }
        }
        Write-Skip "$tag already absent"
        $script:NoOpCount++
    }
}

# ---------------------------------------------------------------------------
#  SERVICE RESTORE
# ---------------------------------------------------------------------------

function Restore-ServiceRow {
    param([PSCustomObject]$Row)
    if (-not $Row.Present)            { return }   # nothing to restore
    if ($Row.Name -like '* (Start regkey)') {
        # Reg-level service Start -- write directly
        $svcName = ($Row.Name -split ' ')[0]
        $val     = [int](($Row.StartType -split '=')[1])
        $path    = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
        if (Test-Path $path) {
            try {
                Set-ItemProperty -Path $path -Name 'Start' -Value $val -Type DWord -Force
                Write-OK "$svcName Start regkey <= $val"
                Log-Line "[SVCREG] $svcName Start=$val"
                $script:ChangedCount++
            } catch {
                Write-Fail "$svcName Start regkey -- $($_.Exception.Message)"
                $script:FailCount++
            }
        }
        return
    }
    $svc = Get-Service -Name $Row.Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Skip "$($Row.Name) (no longer installed)"
        return
    }
    if ("$($svc.StartType)" -eq "$($Row.StartType)") {
        Write-Skip "$($Row.Name) already $($Row.StartType)"
        $script:NoOpCount++
        return
    }
    try {
        Set-Service -Name $Row.Name -StartupType $Row.StartType -ErrorAction Stop
        Write-OK "$($Row.Name) StartType <= $($Row.StartType)"
        Log-Line "[SVC]  $($Row.Name) StartType=$($Row.StartType)"
        $script:ChangedCount++
    } catch {
        Write-Fail "$($Row.Name) -- $($_.Exception.Message)"
        Log-Line "[FAIL] $($Row.Name) StartType -- $($_.Exception.Message)"
        $script:FailCount++
    }
}

# ---------------------------------------------------------------------------
#  TASK RESTORE
# ---------------------------------------------------------------------------

function Restore-TaskRow {
    param([PSCustomObject]$Row)
    $task = Get-ScheduledTask -TaskPath $Row.TaskPath -TaskName $Row.TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Skip "$($Row.TaskName) not present on this system"
        return
    }
    $current = "$($task.State)"
    if ($current -eq $Row.State) {
        Write-Skip "$($Row.TaskName) already $current"
        $script:NoOpCount++
        return
    }
    try {
        if ($Row.State -eq 'Disabled') {
            Disable-ScheduledTask -TaskPath $Row.TaskPath -TaskName $Row.TaskName -ErrorAction Stop | Out-Null
        } else {
            # Ready / Running -> Enable
            Enable-ScheduledTask -TaskPath $Row.TaskPath -TaskName $Row.TaskName -ErrorAction Stop | Out-Null
        }
        Write-OK "$($Row.TaskName) <= $($Row.State)"
        Log-Line "[TASK] $($Row.TaskPath)$($Row.TaskName) State=$($Row.State)"
        $script:ChangedCount++
    } catch {
        Write-Fail "$($Row.TaskName) -- $($_.Exception.Message)"
        Log-Line "[FAIL] $($Row.TaskName) -- $($_.Exception.Message)"
        $script:FailCount++
    }
}

# ---------------------------------------------------------------------------
#  HIGH-LEVEL RESTORE GROUPS
# ---------------------------------------------------------------------------

function Restore-RegistryGroup {
    param([PSCustomObject]$Snapshot, [string]$Group)
    Write-Title ("REGISTRY: {0}" -f $Group)
    $rows = $Snapshot.Registry | Where-Object { $_.Group -eq $Group }
    if (-not $rows) { Write-Note "(no rows in this group)"; return }
    foreach ($r in $rows) { Restore-RegRow -Row $r }
}

function Restore-AllRegistry {
    param([PSCustomObject]$Snapshot)
    $groups = $Snapshot.Registry | Select-Object -ExpandProperty Group -Unique
    foreach ($g in $groups) {
        Restore-RegistryGroup -Snapshot $Snapshot -Group $g
    }
}

function Restore-AllServices {
    param([PSCustomObject]$Snapshot)
    Write-Title "SERVICES"
    foreach ($r in $Snapshot.Services) { Restore-ServiceRow -Row $r }
}

function Restore-AllTasks {
    param([PSCustomObject]$Snapshot)
    Write-Title "SCHEDULED TASKS"
    foreach ($r in $Snapshot.ScheduledTasks) { Restore-TaskRow -Row $r }
}

function Restore-DNS {
    param([PSCustomObject]$Snapshot)
    Write-Title "DNS PER ADAPTER"
    foreach ($a in $Snapshot.Network.Adapters) {
        $current = Get-NetAdapter -Name $a.Name -ErrorAction SilentlyContinue
        if (-not $current) {
            Write-Skip "$($a.Name) (adapter no longer present)"
            continue
        }
        $servers4 = if ($a.DnsIPv4) { $a.DnsIPv4 -split ',' } else { @() }
        try {
            if ($servers4.Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $current.InterfaceIndex -ServerAddresses $servers4 -ErrorAction Stop
                Write-OK ("{0}: DNS <= {1}" -f $a.Name, ($servers4 -join ','))
                Log-Line ("[DNS]  {0} = {1}" -f $a.Name, ($servers4 -join ','))
                $script:ChangedCount++
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $current.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
                Write-OK ("{0}: DNS reset to DHCP (was unset at snapshot)" -f $a.Name)
                Log-Line ("[DNS]  {0} reset to DHCP" -f $a.Name)
                $script:ChangedCount++
            }
        } catch {
            Write-Fail ("{0}: {1}" -f $a.Name, $_.Exception.Message)
            $script:FailCount++
        }
    }
}

function Restore-Power {
    param([PSCustomObject]$Snapshot)
    Write-Title "POWER + HIBERNATION"
    if ($Snapshot.Power.HibernationFilePresent) {
        powercfg -h on | Out-Null
        Write-OK "Hibernation enabled (powercfg -h on)"
        Log-Line "[POWER] hibernate ON"
        $script:ChangedCount++
    } else {
        powercfg -h off | Out-Null
        Write-OK "Hibernation disabled (powercfg -h off)"
        Log-Line "[POWER] hibernate OFF"
        $script:ChangedCount++
    }
    if ($null -ne $Snapshot.Power.HiberbootEnabled) {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
            -Name 'HiberbootEnabled' -Value ([int]$Snapshot.Power.HiberbootEnabled) -Type DWord -Force
        Write-OK ("HiberbootEnabled <= {0}" -f $Snapshot.Power.HiberbootEnabled)
        Log-Line "[POWER] HiberbootEnabled=$($Snapshot.Power.HiberbootEnabled)"
        $script:ChangedCount++
    }
    if ($Snapshot.Power.ActiveSchemeGuid) {
        try {
            powercfg -setactive $Snapshot.Power.ActiveSchemeGuid | Out-Null
            Write-OK ("Power scheme <= {0}" -f $Snapshot.Power.ActiveSchemeGuid)
            $script:ChangedCount++
        } catch {
            Write-Fail ("Could not set scheme: {0}" -f $_.Exception.Message)
            $script:FailCount++
        }
    }
}

function Restore-FileSystem {
    param([PSCustomObject]$Snapshot)
    Write-Title "FILE-SYSTEM FLAGS"
    $fs = $Snapshot.FileSystem
    function Parse-FsValue ($s) {
        # fsutil output is "DisableXxx = 0" -- pull the trailing int
        if ($s -match '=\s*(\d+)') { return [int]$Matches[1] }
        return $null
    }
    $v8 = Parse-FsValue $fs.Disable8dot3
    $vL = Parse-FsValue $fs.DisableLastAccess
    if ($null -ne $v8) {
        & fsutil behavior set disable8dot3 $v8 | Out-Null
        Write-OK "disable8dot3 <= $v8"
        $script:ChangedCount++
    }
    if ($null -ne $vL) {
        & fsutil behavior set disablelastaccess $vL | Out-Null
        Write-OK "disablelastaccess <= $vL"
        $script:ChangedCount++
    }
}

function Restore-FileAssociations {
    param([PSCustomObject]$Snapshot)
    Write-Title "FILE ASSOCIATIONS"
    if (-not $Snapshot.FileAssoc -or -not $Snapshot.FileAssoc.ExportFile) {
        Write-Skip "No DISM export captured at snapshot time"
        return
    }
    if (-not (Test-Path $Snapshot.FileAssoc.ExportFile)) {
        Write-Fail ("Export file no longer exists: {0}" -f $Snapshot.FileAssoc.ExportFile)
        return
    }
    $null = & dism.exe /Online /Import-DefaultAppAssociations:"$($Snapshot.FileAssoc.ExportFile)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "DISM import succeeded (applies to NEW user profiles)"
        Write-Note "For your CURRENT profile, set defaults in Settings > Apps > Default apps."
        Write-Note "See companion .txt for the per-extension list at snapshot time."
        $script:ChangedCount++
    } else {
        Write-Fail ("DISM import failed (exit {0})" -f $LASTEXITCODE)
        $script:FailCount++
    }
}

function Show-AppxDelta {
    param([PSCustomObject]$Snapshot)
    Write-Title "APPX DELTA SINCE SNAPSHOT"
    $now = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    $then = $Snapshot.Appx.Installed | Select-Object -ExpandProperty Name
    $removed = $then | Where-Object { $now -notcontains $_ } | Sort-Object -Unique
    $added   = $now  | Where-Object { $then -notcontains $_ } | Sort-Object -Unique
    if ($removed.Count -eq 0 -and $added.Count -eq 0) {
        Write-OK "No Appx changes since snapshot."
        return
    }
    if ($removed.Count -gt 0) {
        Write-Host "  Packages REMOVED since snapshot (cannot auto-restore):" -ForegroundColor Yellow
        foreach ($n in $removed) { Write-Host "    -- $n" -ForegroundColor Yellow }
        Write-Note "Reinstall via Microsoft Store if desired."
    }
    if ($added.Count -gt 0) {
        Write-Host "  Packages ADDED since snapshot:" -ForegroundColor Cyan
        foreach ($n in $added) { Write-Host "    ++ $n" -ForegroundColor Cyan }
    }
}

# ---------------------------------------------------------------------------
#  ALL-IN-ONE
# ---------------------------------------------------------------------------

function Invoke-FullRestore {
    param([PSCustomObject]$Snapshot)
    Restore-AllRegistry      $Snapshot
    Restore-AllServices      $Snapshot
    Restore-AllTasks         $Snapshot
    Restore-DNS              $Snapshot
    Restore-Power            $Snapshot
    Restore-FileSystem       $Snapshot
    Restore-FileAssociations $Snapshot
    Show-AppxDelta           $Snapshot
}

# ---------------------------------------------------------------------------
#  LOG
# ---------------------------------------------------------------------------

function Save-Log {
    $logPath = "$env:USERPROFILE\Desktop\Win11SnapshotRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $header = @(
        "Win11 Snapshot Restore Log",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Computer:  $env:COMPUTERNAME",
        "User:      $env:USERNAME",
        "Counts: CHANGED=$script:ChangedCount   NOOP=$script:NoOpCount   FAIL=$script:FailCount",
        ("=" * 70),
        ""
    )
    ($header + $script:Log) | Out-File -FilePath $logPath -Encoding ASCII
    Write-OK "Log saved: $logPath"
}

# ---------------------------------------------------------------------------
#  SUMMARY
# ---------------------------------------------------------------------------

function Show-Summary {
    Write-Host ""
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
    Write-Host "   RESTORE SUMMARY" -ForegroundColor Cyan
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host ("    [CHANGED] {0}" -f $script:ChangedCount) -ForegroundColor Green
    Write-Host ("    [NO-OP]   {0}  (already at snapshot value)" -f $script:NoOpCount) -ForegroundColor DarkGray
    if ($script:FailCount -gt 0) {
        Write-Host ("    [FAIL]    {0}" -f $script:FailCount) -ForegroundColor Red
    } else {
        Write-Host ("    [FAIL]    0") -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  REBOOT recommended to ensure all reverted settings take effect." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
#  MENU
# ---------------------------------------------------------------------------

function Show-Menu {
    param([PSCustomObject]$Snap)
    Write-Header
    Write-Host "  Loaded snapshot:" -ForegroundColor White
    Write-Host ("    Captured {0}  Host {1}  Build {2}.{3}" -f `
        $Snap.Metadata.CapturedAt, $Snap.Metadata.Hostname,
        $Snap.Metadata.OSBuildNumber, $Snap.Metadata.UBR) -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Select what to restore:" -ForegroundColor White
    Write-Host ""
    $opts = @(
        " 1  -- FULL RESTORE  (everything in snapshot)"
        " 2  -- Registry only"
        " 3  -- Services only"
        " 4  -- Scheduled tasks only"
        " 5  -- DNS only"
        " 6  -- Power / hibernation only"
        " 7  -- File-system flags only"
        " 8  -- File associations (DISM /Import + per-ext list)"
        " 9  -- Show Appx delta (no changes)"
        "10  -- Pick one registry GROUP"
        " L  -- Save log to Desktop"
        " Q  -- Quit"
    )
    foreach ($o in $opts) { Write-Host "  $o" -ForegroundColor Gray }
    Write-Host ""
    Write-Host ("  Counters: ") -NoNewline -ForegroundColor DarkGray
    Write-Host ("$script:ChangedCount changed  ") -NoNewline -ForegroundColor Green
    Write-Host ("$script:NoOpCount no-op  ") -NoNewline -ForegroundColor DarkGray
    $failColor = if ($script:FailCount -gt 0) { 'Red' } else { 'DarkGray' }
    Write-Host ("$script:FailCount failed") -ForegroundColor $failColor
    Write-Host ""
}

# ---------------------------------------------------------------------------
#  MAIN
# ---------------------------------------------------------------------------

Write-Header

$path = Find-Snapshot
if (-not $path) {
    Read-Host "  Press Enter to exit"
    exit 1
}
$snap = Load-Snapshot $path
if (-not $snap) {
    Read-Host "  Press Enter to exit"
    exit 1
}

# ALWAYS take a pre-restore safety snapshot before changes
Write-Host ""
Write-Host "  Before any changes, a fresh snapshot of the CURRENT state will be" -ForegroundColor Yellow
Write-Host "  captured. This is your roll-forward path if the restore goes badly." -ForegroundColor Yellow
Write-Host ""
$go = (Read-Host "  Press Enter to continue, or type SKIP to skip safety snapshot").Trim().ToUpper()
if ($go -ne 'SKIP') {
    New-PreRestoreSnapshot
}

do {
    Show-Menu -Snap $snap
    $choice = (Read-Host "  Enter choice").Trim().ToUpper()
    switch ($choice) {
        '1'  { Invoke-FullRestore        $snap }
        '2'  { Restore-AllRegistry       $snap }
        '3'  { Restore-AllServices       $snap }
        '4'  { Restore-AllTasks          $snap }
        '5'  { Restore-DNS               $snap }
        '6'  { Restore-Power             $snap }
        '7'  { Restore-FileSystem        $snap }
        '8'  { Restore-FileAssociations  $snap }
        '9'  { Show-AppxDelta            $snap }
        '10' {
            $groups = $snap.Registry | Select-Object -ExpandProperty Group -Unique | Sort-Object
            Write-Host ""
            for ($i=0; $i -lt $groups.Count; $i++) {
                Write-Host ("   {0,2}  {1}" -f ($i+1), $groups[$i]) -ForegroundColor Gray
            }
            Write-Host ""
            $g = (Read-Host "  Group number").Trim()
            if ($g -as [int] -and [int]$g -ge 1 -and [int]$g -le $groups.Count) {
                Restore-RegistryGroup -Snapshot $snap -Group $groups[[int]$g - 1]
            }
        }
        'L' { Save-Log }
        'Q' { break }
        default { Write-Host "  Invalid choice." -ForegroundColor Red }
    }
    if ($choice -ne 'Q') {
        Write-Host ""
        Read-Host "  Press Enter to return to menu"
    }
} while ($choice -ne 'Q')

Show-Summary
Save-Log
Read-Host "  Press Enter to exit"
