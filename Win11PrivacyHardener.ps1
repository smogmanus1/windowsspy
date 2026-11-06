<#
.SYNOPSIS
    Windows 10/11 Privacy Hardener
    Author : Brad / CrisisOfTruth.org
    Version: 1.4
.DESCRIPTION
    Disables telemetry, ads, tracking, Delivery Optimization,
    Cortana, OneDrive, forced Edge, Recall, and more.

    Works on both Windows 10 and Windows 11. Sections that
    only exist on Windows 11 (Recall) are automatically
    skipped on Windows 10.

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
#  OS DETECTION  (Win11 = build 22000 or higher)
# ---------------------------------------------------------------------------
$script:OSBuild = 0
try {
    $script:OSBuild = [int]((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuildNumber)
} catch { $script:OSBuild = 0 }
$script:IsWin11 = $script:OSBuild -ge 22000
$script:OSLabel = if ($script:IsWin11) { "Windows 11 (build $script:OSBuild)" } else { "Windows 10 (build $script:OSBuild)" }

# ---------------------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win10/11 Privacy Hardener  --  CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host "  Detected: $script:OSLabel" -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Skip ($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor DarkYellow }
function Write-Sep        { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
    Write-Sep
}

function Skip-IfWin10 {
    param([string]$Reason)
    if (-not $script:IsWin11) {
        Write-Skip "$Reason (Windows 10 detected)"
        return $true
    }
    return $false
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
        Stop-Service  -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service   -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
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
#  RESTORE POINT
# ---------------------------------------------------------------------------

function New-RestorePoint {
    Write-Title "Creating System Restore Point"
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description 'Win11PrivacyHardener_Before' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OK "Restore point created: Win11PrivacyHardener_Before"
    } catch {
        Write-Fail "Could not create restore point: $($_.Exception.Message)"
        Write-Info "Create one manually: System Properties > System Protection"
    }
}

# ---------------------------------------------------------------------------
#  TWEAK GROUPS
# ---------------------------------------------------------------------------

function Invoke-TelemetryTweaks {
    Write-Title "TELEMETRY AND DIAGNOSTICS"

    Invoke-Tweak "Disable DiagTrack (Connected User Experiences and Telemetry) service" {
        Disable-Svc 'DiagTrack'
    }

    Invoke-Tweak "Disable WAP Push Message Routing service (dmwappushsvc)" {
        Disable-Svc 'dmwappushsvc'
    }

    Invoke-Tweak "Set AllowTelemetry to 0 (Security -- minimum possible)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    }

    Invoke-Tweak "Disable telemetry scheduled tasks" {
        $paths = @(
            '\Microsoft\Windows\Application Experience\',
            '\Microsoft\Windows\Customer Experience Improvement Program\',
            '\Microsoft\Windows\DiskDiagnostic\',
            '\Microsoft\Windows\Feedback\Siuf\',
            '\Microsoft\Windows\Windows Error Reporting\'
        )
        foreach ($p in $paths) { Disable-SchdTask $p }
    }

    Invoke-Tweak "Disable feedback frequency nag prompts" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' -1
    }

    Invoke-Tweak "Delete existing diagnostic data cache" {
        $diagPath = "$env:LOCALAPPDATA\Microsoft\Windows\DiagTrack"
        if (Test-Path $diagPath) {
            Get-ChildItem $diagPath -Recurse -Force |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-AdsTweaks {
    Write-Title "ADS, SUGGESTIONS AND START MENU TRACKING"

    Invoke-Tweak "Disable Advertising ID" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
    }

    Invoke-Tweak "Disable Start Menu app suggestions and ads" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0
    }

    Invoke-Tweak "Disable Lock Screen ads and Spotlight tips" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
    }

    Invoke-Tweak "Disable Settings app suggestions" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0
    }

    Invoke-Tweak "Disable Tailored Experiences (diagnostic data used for ads)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    }

    Invoke-Tweak "Disable language list website access (privacy leak)" {
        Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
    }

    Invoke-Tweak "Disable app launch tracking for Start Menu ranking" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0
    }

    Invoke-Tweak "Disable suggested and pre-installed app reinstallation" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0
    }
}

function Invoke-ActivityHistoryTweaks {
    Write-Title "ACTIVITY HISTORY AND TIMELINE"

    Invoke-Tweak "Disable Activity History collection" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
    }

    Invoke-Tweak "Disable Activity History upload to Microsoft cloud" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
    }

    Invoke-Tweak "Clear existing Activity History from registry" {
        $paths = @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\ActivityDataModel',
            'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\TaskFlow'
        )
        foreach ($p in $paths) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }
    }
}

function Invoke-DeliveryOptTweaks {
    Write-Title "DELIVERY OPTIMIZATION (P2P bandwidth usage)"

    Invoke-Tweak "Disable Delivery Optimization -- HTTP only, no P2P uploads" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    }

    Invoke-Tweak "Disable Delivery Optimization service" {
        Disable-Svc 'DoSvc'
    }

    Invoke-Tweak "Clear Delivery Optimization cache" {
        $cache = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
        if (Test-Path $cache) {
            Get-ChildItem $cache -Force |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-SysMainTweaks {
    Write-Title "SYSMAIN / SUPERFETCH (high disk usage fix)"

    Invoke-Tweak "Disable SysMain service" {
        Disable-Svc 'SysMain'
    }

    Invoke-Tweak "Disable Prefetch via registry" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher' 0
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableSuperfetch' 0
    }
}

function Invoke-CortanaTweaks {
    Write-Title "CORTANA"

    Invoke-Tweak "Disable Cortana via group policy" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortanaAboveLock' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
    }

    Invoke-Tweak "Disable Cortana scheduled task" {
        Disable-SchdTask '\Microsoft\Windows\Cortana\'
    }
}

function Invoke-EdgeTweaks {
    Write-Title "EDGE BROWSER FORCING"

    Invoke-Tweak "Disable Edge first-run experience and welcome screen" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
    }

    Invoke-Tweak "Disable Edge Desktop Search Bar widget" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WebWidgetAllowed' 0
    }

    Invoke-Tweak "Disable News and Interests / Widgets taskbar panel" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests\AllowNewsAndInterests' 'value' 0
    }

    Invoke-Tweak "Disable Edge tab pre-loading at Windows startup" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader' 'AllowTabPreloading' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
    }

    Invoke-Tweak "Disable Edge background running after browser closes" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
    }
}

function Invoke-OneDriveTweaks {
    Write-Title "ONEDRIVE"

    Invoke-Tweak "Prevent OneDrive from syncing system folders without consent" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableLibrariesDefaultSaveToOneDrive' 1
    }

    Invoke-Tweak "Remove OneDrive from startup" {
        Remove-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
    }

    Invoke-Tweak "Stop OneDrive process if running" {
        Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-LocationTweaks {
    Write-Title "LOCATION, CAMERA AND MICROPHONE"

    Invoke-Tweak "Disable Location Services" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' 'Status' 0
    }

    Invoke-Tweak "Deny app access to Camera (policy level)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessCamera' 2
    }

    Invoke-Tweak "Deny app access to Microphone (policy level)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessMicrophone' 2
    }

    Invoke-Tweak "Deny app access to Account Info" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessAccountInfo' 2
    }
}

function Invoke-DNSTweaks {
    Write-Title "DNS PRIVACY (Cloudflare 1.1.1.1)"

    Invoke-Tweak "Set DNS to Cloudflare 1.1.1.1 and 1.0.0.1 on all active adapters" {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        if (-not $adapters) { throw 'No active network adapters found' }
        foreach ($a in $adapters) {
            Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses '1.1.1.1','1.0.0.1'
        }
    }

    Invoke-Tweak "Enable DNS over HTTPS auto-upgrade via registry (Win10 21H2+ / Win11)" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableAutoDoh' 2
    }
}

function Invoke-RecallTweaks {
    Write-Title "WINDOWS RECALL"

    if (Skip-IfWin10 "Windows Recall is a Windows 11 (Copilot+) feature") { return }

    Invoke-Tweak "Disable Windows Recall optional feature" {
        Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction SilentlyContinue | Out-Null
    }

    Invoke-Tweak "Disable Recall via policy registry key" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    }
}

function Invoke-RemoteAccessTweaks {
    Write-Title "REMOTE ACCESS"

    Invoke-Tweak "Disable Remote Desktop" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1
        Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    }

    Invoke-Tweak "Disable Remote Registry service" {
        Disable-Svc 'RemoteRegistry'
    }

    Invoke-Tweak "Disable Remote Assistance" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0
    }
}

function Invoke-BloatwareTweaks {
    Write-Title "BLOATWARE REMOVAL"

    # Common to Win10 and Win11. Packages that don't exist on a given
    # OS are silently skipped by Get-AppxPackage.
    $bloat = @(
        'Microsoft.BingNews',
        'Microsoft.BingWeather',
        'Microsoft.GetHelp',
        'Microsoft.Getstarted',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MicrosoftOfficeHub',
        'Microsoft.People',
        'Microsoft.PowerAutomateDesktop',
        'Microsoft.Todos',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsMaps',
        'Microsoft.Xbox.TCUI',
        'Microsoft.XboxGameOverlay',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.YourPhone',
        'MicrosoftTeams',
        'Clipchamp.Clipchamp',
        'SpotifyAB.SpotifyMusic',
        'TikTok',
        'Disney.DisneyPlus'
    )

    Invoke-Tweak "Remove $($bloat.Count) common bloatware packages" {
        $removed = 0
        foreach ($pkg in $bloat) {
            # Get-AppxPackage can return multiple objects for one name
            # so we pipe each result individually rather than passing the array
            Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                    $removed++
                }
            # Also remove provisioned (reinstalls on new accounts) version
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $pkg } |
                ForEach-Object {
                    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
                }
        }
        Write-Info "    Removed $removed package instance(s)"
    }
}

function Save-Log {
    $logPath = "$PSScriptRoot\Win11Privacy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $header = @(
        "Win10/11 Privacy Hardener Log",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Computer:  $env:COMPUTERNAME",
        "OS:        $script:OSLabel",
        ("=" * 70),
        ""
    )
    ($header + $script:Log) | Out-File -FilePath $logPath -Encoding ASCII
    Write-OK "Log saved: $logPath"
}

# ---------------------------------------------------------------------------
#  MENU
# ---------------------------------------------------------------------------

function Show-Menu {
    Write-Header
    Write-Host "  Select an option:" -ForegroundColor White
    Write-Host ""
    $recallLabel = if ($script:IsWin11) { "12  -- Windows Recall" } else { "12  -- Windows Recall  (Win11 only -- will skip)" }
    $opts = @(
        " 1  -- ALL TWEAKS (recommended -- creates restore point first)"
        " 2  -- Telemetry and Diagnostics"
        " 3  -- Ads, Suggestions and Start Menu Tracking"
        " 4  -- Activity History and Timeline"
        " 5  -- Delivery Optimization (P2P bandwidth)"
        " 6  -- SysMain / SuperFetch (high disk usage fix)"
        " 7  -- Cortana"
        " 8  -- Edge Browser Forcing"
        " 9  -- OneDrive"
        "10  -- Location, Camera and Microphone"
        "11  -- DNS Privacy (Cloudflare 1.1.1.1)"
        " $recallLabel"
        "13  -- Remote Access"
        "14  -- Bloatware Removal"
        " R  -- Create System Restore Point only"
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
            New-RestorePoint
            Invoke-TelemetryTweaks
            Invoke-AdsTweaks
            Invoke-ActivityHistoryTweaks
            Invoke-DeliveryOptTweaks
            Invoke-SysMainTweaks
            Invoke-CortanaTweaks
            Invoke-EdgeTweaks
            Invoke-OneDriveTweaks
            Invoke-LocationTweaks
            Invoke-DNSTweaks
            Invoke-RecallTweaks
            Invoke-RemoteAccessTweaks
            Invoke-BloatwareTweaks
            Write-Host ""
            Write-Host "  ALL TWEAKS COMPLETE. REBOOT RECOMMENDED." -ForegroundColor Green
            Write-Host ""
        }
        '2'  { Invoke-TelemetryTweaks }
        '3'  { Invoke-AdsTweaks }
        '4'  { Invoke-ActivityHistoryTweaks }
        '5'  { Invoke-DeliveryOptTweaks }
        '6'  { Invoke-SysMainTweaks }
        '7'  { Invoke-CortanaTweaks }
        '8'  { Invoke-EdgeTweaks }
        '9'  { Invoke-OneDriveTweaks }
        '10' { Invoke-LocationTweaks }
        '11' { Invoke-DNSTweaks }
        '12' { Invoke-RecallTweaks }
        '13' { Invoke-RemoteAccessTweaks }
        '14' { Invoke-BloatwareTweaks }
        'R'  { New-RestorePoint }
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
Write-Host "  Goodbye. Reboot when ready." -ForegroundColor Cyan
Write-Host ""
