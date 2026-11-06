<#
.SYNOPSIS
    Windows 10/11 Performance Hardener
    Author : Brad / CrisisOfTruth.org
    Version: 1.4
.DESCRIPTION
    Maximizes Windows performance: power plans, visual effects,
    services, startup, network stack, disk, memory, gaming, boot.

    Works on both Windows 10 and Windows 11. Detects OS edition
    so Win10 Home gracefully skips the Ultimate Performance plan
    (which Microsoft hides on Home).

    Self-elevates to Administrator automatically.
.NOTES
    Run via RunHardener.bat or right-click and Run with PowerShell.
#>

# Self-elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
    Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
    exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
#  OS DETECTION
# ---------------------------------------------------------------------------
$script:OSBuild = 0
$script:OSEdition = 'Unknown'
try {
    $verKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $script:OSBuild   = [int]$verKey.CurrentBuildNumber
    $script:OSEdition = [string]$verKey.EditionID
} catch { }
$script:IsWin11   = $script:OSBuild -ge 22000
$script:IsHome    = $script:OSEdition -match '(?i)Core|Home'
$script:OSLabel   = if ($script:IsWin11) {
    "Windows 11 $script:OSEdition (build $script:OSBuild)"
} else {
    "Windows 10 $script:OSEdition (build $script:OSBuild)"
}

# ---------------------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkYellow
    Write-Host "  Win10/11 Performance Hardener  --  CrisisOfTruth.org" -ForegroundColor Yellow
    Write-Host "  Detected: $script:OSLabel" -ForegroundColor DarkYellow
    Write-Host " $line" -ForegroundColor DarkYellow
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Skip ($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor DarkYellow }
function Write-Sep        { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Yellow
    Write-Sep
}

$script:PassCount = 0
$script:FailCount = 0
$script:Log = [System.Collections.Generic.List[string]]::new()

function Invoke-Tweak {
    param([string]$Label, [scriptblock]$Action)
    Write-Info $Label
    try {
        & $Action
        Write-OK "Done"
        $script:PassCount++
        $script:Log.Add("[OK] $Label")
    } catch {
        Write-Fail "Failed: $($_.Exception.Message)"
        $script:FailCount++
        $script:Log.Add("[FAIL] $Label -- $($_.Exception.Message)")
    }
}

function Set-Reg {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    # Create the key if needed -- throw if blocked (caught by Invoke-Tweak)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
    # Read back and verify -- catches the silent-fail-without-admin case
    $actual = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $actual) {
        throw "Set-Reg VERIFY FAILED: $Path\$Name reads back as null (HKLM write blocked? need admin?)"
    }
    $match = $false
    try {
        if ($actual -is [int] -or $actual -is [long]) {
            $match = ([int64]$actual -eq [int64]$Value)
        } else {
            $match = ("$actual" -eq "$Value")
        }
    } catch {
        $match = ("$actual" -eq "$Value")
    }
    if (-not $match) {
        throw "Set-Reg VERIFY FAILED: $Path\$Name=$actual but expected $Value (policy override?)"
    }
}

function Disable-Svc {
    param([string]$Name)
    if (Get-Service -Name $Name -ErrorAction SilentlyContinue) {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
    } else {
        Write-Info "    Service '$Name' not found -- skipping"
    }
}

function Disable-SchdTask {
    param([string]$TaskPath, [string]$TaskName = '*')
    Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

# ---------------------------------------------------------------------------
#  1 -- POWER PLAN
# ---------------------------------------------------------------------------

function Invoke-PowerTweaks {
    Write-Title "POWER PLAN"

    if ($script:IsHome) {
        Write-Skip "Ultimate Performance plan -- not available on Home editions"
        Write-Info "Continuing with USB / disk / CPU / hibernate tweaks on the current plan"
    } else {
        Invoke-Tweak "Enable hidden Ultimate Performance power plan" {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
            $guid = (powercfg -list | Select-String 'Ultimate Performance' | Select-Object -Last 1) -replace '.*\(([0-9a-f-]{36})\).*','$1'
            if ($guid) {
                powercfg -setactive $guid | Out-Null
                Write-Info "    Activated GUID: $guid"
            } else {
                throw "Could not find Ultimate Performance plan after creation"
            }
        }
    }

    Invoke-Tweak "Disable USB Selective Suspend (prevents USB stuttering)" {
        powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
        powercfg -setactive SCHEME_CURRENT | Out-Null
    }

    Invoke-Tweak "Disable Hard Disk power-down timeout (prevent spin-down lag)" {
        powercfg -setacvalueindex SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0 | Out-Null
        powercfg -setactive SCHEME_CURRENT | Out-Null
    }

    Invoke-Tweak "Set processor minimum state to 100% (no throttling)" {
        powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
        powercfg -setactive SCHEME_CURRENT | Out-Null
    }

    Invoke-Tweak "Disable Hibernate (reclaims hiberfil.sys disk space)" {
        powercfg -h off | Out-Null
    }
}

# ---------------------------------------------------------------------------
#  2 -- VISUAL EFFECTS
# ---------------------------------------------------------------------------

function Invoke-VisualTweaks {
    Write-Title "VISUAL EFFECTS AND ANIMATIONS"

    Invoke-Tweak "Set Visual Effects to best performance (master switch)" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
        $bytes = [byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)
        Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' $bytes 'Binary'
    }

    Invoke-Tweak "Disable window animations (minimize / maximize / open)" {
        Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
    }

    Invoke-Tweak "Disable transparency effects (Acrylic / Mica)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
    }

    Invoke-Tweak "Disable taskbar animations" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
    }

    Invoke-Tweak "Disable window shadows" {
        Set-Reg 'HKCU:\Control Panel\Desktop' 'EnableAeroPeek' 0
    }

    Invoke-Tweak "Disable smooth-scroll list boxes" {
        Set-Reg 'HKCU:\Control Panel\Desktop' 'SmoothScroll' 0
    }

    Invoke-Tweak "Speed up menu show delay to 20ms (default is 400ms)" {
        Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '20' 'String'
        Set-Reg 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '5000' 'String'
        Set-Reg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '3000' 'String'
    }
}

# ---------------------------------------------------------------------------
#  3 -- UNNECESSARY SERVICES
# ---------------------------------------------------------------------------

function Invoke-ServiceTweaks {
    Write-Title "UNNECESSARY BACKGROUND SERVICES"

    $services = [ordered]@{
        'Fax'               = 'Fax service'
        'XblAuthManager'    = 'Xbox Live Auth Manager'
        'XblGameSave'       = 'Xbox Live Game Save'
        'XboxNetApiSvc'     = 'Xbox Live Networking'
        'XboxGipSvc'        = 'Xbox Accessory Management'
        'wisvc'             = 'Windows Insider Service'
        'WpcMonSvc'         = 'Parental Controls'
        'RetailDemo'        = 'Retail Demo Service'
        'RemoteAccess'      = 'Routing and Remote Access'
        'SharedAccess'      = 'Internet Connection Sharing'
        'lmhosts'           = 'TCP/IP NetBIOS Helper (legacy)'
        'TrkWks'            = 'Distributed Link Tracking Client'
        'MapsBroker'        = 'Downloaded Maps Manager'
        'PhoneSvc'          = 'Phone Service'
        'icssvc'            = 'Windows Mobile Hotspot Service'
        'DiagTrack'         = 'DiagTrack telemetry (backup disable)'
        'SysMain'           = 'SysMain / SuperFetch (backup disable)'
    }

    foreach ($svc in $services.GetEnumerator()) {
        $svcName = $svc.Key
        $svcDesc = $svc.Value
        Invoke-Tweak "Disable: $svcDesc" {
            Disable-Svc $svcName
        }.GetNewClosure()
    }
}

# ---------------------------------------------------------------------------
#  4 -- STARTUP
# ---------------------------------------------------------------------------

function Invoke-StartupTweaks {
    Write-Title "STARTUP PROGRAM CLEANUP"

    Invoke-Tweak "Remove common startup bloat from registry Run key" {
        $keys = @('OneDrive','Discord','Spotify','EpicGamesLauncher','Steam','Teams','MicrosoftTeams','Skype','AdobeAAMUpdater','CCleaner Monitoring')
        $runPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        $removed = 0
        foreach ($k in $keys) {
            if (Get-ItemProperty -Path $runPath -Name $k -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $runPath -Name $k -ErrorAction SilentlyContinue
                $removed++
            }
        }
        Write-Info "    Removed $removed startup entries"
    }

    Invoke-Tweak "Disable startup delay for user-added startup apps" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
    }

    Invoke-Tweak "Disable Windows Tips and Get even more out of Windows nag" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    }
}

# ---------------------------------------------------------------------------
#  5 -- DISK AND MEMORY
# ---------------------------------------------------------------------------

function Invoke-DiskMemoryTweaks {
    Write-Title "DISK AND MEMORY"

    Invoke-Tweak "Confirm TRIM enabled for SSDs (NTFS and ReFS)" {
        fsutil behavior set DisableDeleteNotify NTFS 0 2>&1 | Out-Null
        fsutil behavior set DisableDeleteNotify ReFS 0 2>&1 | Out-Null
    }

    Invoke-Tweak "Disable 8.3 filename creation on NTFS (measurable disk perf gain)" {
        fsutil behavior set disable8dot3 1 | Out-Null
    }

    Invoke-Tweak "Disable last access timestamp on NTFS (reduces disk writes)" {
        fsutil behavior set disablelastaccess 1 | Out-Null
    }

    Invoke-Tweak "Favor programs over cache in memory management" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache' 0
    }

    Invoke-Tweak "Keep kernel in RAM -- disable paging executive to disk" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1
    }

    Invoke-Tweak "Clear Temp files (user and system)" {
        $tempPaths = @($env:TEMP, $env:TMP, "$env:SystemRoot\Temp", "$env:SystemRoot\Prefetch")
        $freed = 0
        foreach ($p in $tempPaths) {
            if (Test-Path $p) {
                Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer } |
                    ForEach-Object {
                        $freed += $_.Length
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    }
            }
        }
        Write-Info "    Freed approximately $([math]::Round($freed / 1MB, 1)) MB"
    }

    Invoke-Tweak "Optimize and TRIM all fixed drives" {
        Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
            ForEach-Object {
                Write-Info "    Optimizing $($_.DriveLetter):..."
                Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -Verbose:$false -ErrorAction SilentlyContinue
            }
    }
}

# ---------------------------------------------------------------------------
#  6 -- NETWORK
# ---------------------------------------------------------------------------

function Invoke-NetworkTweaks {
    Write-Title "NETWORK PERFORMANCE"

    Invoke-Tweak "Disable Nagle Algorithm (reduces TCP latency -- good for gaming and VoIP)" {
        $ifPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
        Get-ChildItem $ifPath | ForEach-Object {
            Set-Reg $_.PSPath 'TcpAckFrequency' 1
            Set-Reg $_.PSPath 'TCPNoDelay' 1
        }
    }

    Invoke-Tweak "Enable TCP Auto-Tuning (optimizes window size automatically)" {
        netsh int tcp set global autotuninglevel=normal | Out-Null
    }

    Invoke-Tweak "Enable RSS (Receive-Side Scaling -- multi-core NIC processing)" {
        netsh int tcp set global rss=enabled | Out-Null
    }

    Invoke-Tweak "Disable Windows background network throughput throttle" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xFFFFFFFF
    }

    Invoke-Tweak "Set System Responsiveness to 0 (max CPU for foreground tasks)" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0
    }

    Invoke-Tweak "Increase IRPStackSize (prevents network share disconnects)" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'IRPStackSize' 20
    }

    Invoke-Tweak "Flush DNS cache" {
        ipconfig /flushdns | Out-Null
    }
}

# ---------------------------------------------------------------------------
#  7 -- GAMING
# ---------------------------------------------------------------------------

function Invoke-GamingTweaks {
    Write-Title "GAMING PERFORMANCE"

    Invoke-Tweak "Disable Game Bar and Xbox DVR overlay (causes FPS drops)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    }

    Invoke-Tweak "Enable Hardware-Accelerated GPU Scheduling (HAGS -- Win10 2004+ or Win11, modern GPU)" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
    }

    Invoke-Tweak "Disable fullscreen optimizations globally" {
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehavior' 2
    }

    Invoke-Tweak "Set GPU and CPU scheduling priority for games" {
        $gamePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
        Set-Reg $gamePath 'GPU Priority' 8
        Set-Reg $gamePath 'Priority' 6
        Set-Reg $gamePath 'Scheduling Category' 'High' 'String'
    }

    Invoke-Tweak "Disable Mouse Acceleration (raw input -- critical for precision)" {
        Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
        Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
        Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
    }
}

# ---------------------------------------------------------------------------
#  8 -- SCHEDULED TASKS
# ---------------------------------------------------------------------------

function Invoke-TaskTweaks {
    Write-Title "UNNECESSARY SCHEDULED TASKS"

    $tasks = @(
        @{ Path = '\Microsoft\Windows\Application Experience\';  Name = 'Microsoft Compatibility Appraiser' },
        @{ Path = '\Microsoft\Windows\Application Experience\';  Name = 'ProgramDataUpdater' },
        @{ Path = '\Microsoft\Windows\Application Experience\';  Name = 'StartupAppTask' },
        @{ Path = '\Microsoft\Windows\Autochk\';                 Name = 'Proxy' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'Consolidator' },
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = 'UsbCeip' },
        @{ Path = '\Microsoft\Windows\DiskDiagnostic\';          Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{ Path = '\Microsoft\Windows\NetTrace\';                Name = 'GatherNetworkInfo' },
        @{ Path = '\Microsoft\Windows\Windows Error Reporting\'; Name = 'QueueReporting' },
        @{ Path = '\Microsoft\Windows\Maps\';                    Name = 'MapsUpdateTask' },
        @{ Path = '\Microsoft\Windows\Maps\';                    Name = 'MapsToastTask' }
    )

    Invoke-Tweak "Disable $($tasks.Count) unnecessary scheduled tasks" {
        foreach ($t in $tasks) {
            $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($task) {
                Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}

# ---------------------------------------------------------------------------
#  9 -- BOOT
# ---------------------------------------------------------------------------

function Invoke-BootTweaks {
    Write-Title "FAST STARTUP AND BOOT"

    Invoke-Tweak "Disable Fast Startup (fixes driver and update issues after shutdown)" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    }

    Invoke-Tweak "Enable verbose boot status messages" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 1
    }

    Invoke-Tweak "Set boot menu timeout to 3 seconds (default is 30)" {
        bcdedit /timeout 3 | Out-Null
    }

    # NOTE: Microsoft now recommends NOT pinning numproc on modern Windows;
    # the scheduler handles core enablement at boot on its own. Left here
    # for symmetry with prior versions, but it is effectively a no-op on
    # current builds.
    Invoke-Tweak "Enable all CPU cores during boot (legacy; modern Windows ignores)" {
        $cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        bcdedit /set numproc $cores | Out-Null
        Write-Info "    Set to $cores logical processors"
    }
}

# ---------------------------------------------------------------------------
#  LOG + MENU
# ---------------------------------------------------------------------------

function Save-Log {
    $logPath = "$PSScriptRoot\Win11Perf_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $header = @(
        "Win10/11 Performance Hardener Log",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Computer:  $env:COMPUTERNAME",
        "OS:        $script:OSLabel",
        ("=" * 70),
        ""
    )
    ($header + $script:Log) | Out-File -FilePath $logPath -Encoding ASCII
    Write-OK "Log saved: $logPath"
}

function Show-Menu {
    Write-Header
    Write-Host "  Select an option:" -ForegroundColor White
    Write-Host ""
    $powerLabel = if ($script:IsHome) {
        " 2  -- Power Plan  (Home edition -- Ultimate Performance will skip)"
    } else {
        " 2  -- Power Plan (Ultimate Performance + USB / disk / CPU tweaks)"
    }
    $opts = @(
        " 1  -- ALL PERFORMANCE TWEAKS (recommended)"
        $powerLabel
        " 3  -- Visual Effects and Animations (speed up the UI)"
        " 4  -- Unnecessary Background Services"
        " 5  -- Startup Program Cleanup"
        " 6  -- Disk and Memory Optimization"
        " 7  -- Network Performance (TCP / latency / throughput)"
        " 8  -- Gaming Performance (Game Bar, HAGS, GPU priority, mouse accel)"
        " 9  -- Scheduled Task Cleanup"
        "10  -- Fast Startup and Boot Options"
        " L  -- Save Log to Desktop"
        " Q  -- Quit"
    )
    foreach ($o in $opts) { Write-Host "  $o" -ForegroundColor Gray }
    Write-Host ""
    Write-Host ("  Applied: ") -NoNewline -ForegroundColor DarkGray
    Write-Host ("$script:PassCount OK  ") -NoNewline -ForegroundColor Green
    $fc = if ($script:FailCount -gt 0) { 'Red' } else { 'DarkGray' }
    Write-Host ("$script:FailCount Failed") -ForegroundColor $fc
    Write-Host ""
}

do {
    Show-Menu
    $choice = (Read-Host "  Enter choice").Trim().ToUpper()
    switch ($choice) {
        '1' {
            Invoke-PowerTweaks
            Invoke-VisualTweaks
            Invoke-ServiceTweaks
            Invoke-StartupTweaks
            Invoke-DiskMemoryTweaks
            Invoke-NetworkTweaks
            Invoke-GamingTweaks
            Invoke-TaskTweaks
            Invoke-BootTweaks
            Write-Host ""
            Write-Host "  ALL PERFORMANCE TWEAKS COMPLETE. REBOOT RECOMMENDED." -ForegroundColor Green
            Write-Host ""
        }
        '2'  { Invoke-PowerTweaks }
        '3'  { Invoke-VisualTweaks }
        '4'  { Invoke-ServiceTweaks }
        '5'  { Invoke-StartupTweaks }
        '6'  { Invoke-DiskMemoryTweaks }
        '7'  { Invoke-NetworkTweaks }
        '8'  { Invoke-GamingTweaks }
        '9'  { Invoke-TaskTweaks }
        '10' { Invoke-BootTweaks }
        'L'  { Save-Log }
        'Q'  { break }
        default { Write-Host "  Invalid choice." -ForegroundColor Red }
    }
    if ($choice -ne 'Q') {
        Write-Host ""
        Read-Host "  Press Enter to return to menu"
    }
} while ($choice -ne 'Q')

Write-Host ""
Write-Host "  Goodbye. Reboot when ready." -ForegroundColor Yellow
Write-Host ""
