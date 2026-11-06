<#
.SYNOPSIS
    Windows 11 Hardener Audit -- Drift Detector
    Author : Brad / CrisisOfTruth.org
    Version: 1.1
.DESCRIPTION
    READ-ONLY companion to the Win11 Hardener Suite. Checks every
    setting that Win11PrivacyHardener.ps1, Win11PrivacyHardener_Extras.ps1,
    and Win11PerfHardener.ps1 modify, and reports which ones Microsoft
    has reverted -- usually after a Windows Update.

    Makes ZERO changes to the system. Just reports what drifted.

    Also lists recently installed Windows updates so you can pin
    drift to a specific KB.

    Also checks Secure Boot status and whether a post-June-2026 update
    has landed -- that update carries Microsoft's revocation of 11
    old UEFI shims that ESET found could be used to bypass Secure Boot
    entirely (see: "Microsoft Secure Boot has been broken for most of
    its existence", Ars Technica, July 2026).

    When the audit is done, it tells you exactly which menu option
    in RunHardener.bat will fix what was reverted.
.NOTES
    Run via RunHardener.bat (option A) or right-click + Run with PowerShell.
    Self-elevates to Administrator automatically.
#>

# -- Self elevation -----------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
    Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
    exit
}

$ErrorActionPreference = 'SilentlyContinue'

# -- Output helpers (matches hardener style) ----------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win11 Hardener Audit  --  CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host "  Read-only drift detector. No changes will be made." -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK       ($msg) { Write-Host "  [OK]      $msg" -ForegroundColor Green }
function Write-Reverted ($msg) { Write-Host "  [REVERT]  $msg" -ForegroundColor Red }
function Write-NotSet   ($msg) { Write-Host "  [NOTSET]  $msg" -ForegroundColor DarkYellow }
function Write-Reinst   ($msg) { Write-Host "  [REINST]  $msg" -ForegroundColor Magenta }
function Write-Info     ($msg) { Write-Host "  $msg" -ForegroundColor Gray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray
}

# -- Counters and log ----------------------------------------------------

$script:OkCount      = 0
$script:RevertCount  = 0
$script:NotSetCount  = 0
$script:ReinstCount  = 0
$script:Log          = [System.Collections.Generic.List[string]]::new()
$script:RevertedList = [System.Collections.Generic.List[string]]::new()

function Log-Line ($line) { $script:Log.Add($line) }

# -- Check primitives ----------------------------------------------------

function Check-Reg {
    param(
        [string]$Path,
        [string]$Name,
        $Expected,
        [string]$Desc,
        [string]$FixGroup
    )
    if (-not (Test-Path $Path)) {
        Write-NotSet "$Desc"
        Log-Line ("[NOTSET] {0}    ({1})" -f $Desc, $FixGroup)
        $script:NotSetCount++
        return
    }
    $val = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $val) {
        Write-NotSet "$Desc"
        Log-Line ("[NOTSET] {0}    ({1})" -f $Desc, $FixGroup)
        $script:NotSetCount++
        return
    }
    # numeric compare if both look numeric, else string compare
    $match = $false
    try {
        if ($val -is [int] -or $val -is [long]) {
            $match = ([int64]$val -eq [int64]$Expected)
        } else {
            $match = ("$val" -eq "$Expected")
        }
    } catch {
        $match = ("$val" -eq "$Expected")
    }
    if ($match) {
        Write-OK "$Desc"
        Log-Line ("[OK]     {0}" -f $Desc)
        $script:OkCount++
    } else {
        Write-Reverted "$Desc  (now: $val, want: $Expected)"
        Log-Line ("[REVERT] {0}    now={1}  want={2}    fix={3}" -f $Desc, $val, $Expected, $FixGroup)
        $script:RevertedList.Add($FixGroup)
        $script:RevertCount++
    }
}

function Check-Service {
    param(
        [string]$Name,
        [string]$Desc,
        [string]$FixGroup
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-OK "$Desc  (service not present)"
        Log-Line ("[OK]     {0}  (service absent)" -f $Desc)
        $script:OkCount++
        return
    }
    if ($svc.StartType -eq 'Disabled') {
        Write-OK "$Desc"
        Log-Line ("[OK]     {0}" -f $Desc)
        $script:OkCount++
    } else {
        Write-Reverted "$Desc  (StartType: $($svc.StartType), Status: $($svc.Status))"
        Log-Line ("[REVERT] {0}    StartType={1}    fix={2}" -f $Desc, $svc.StartType, $FixGroup)
        $script:RevertedList.Add($FixGroup)
        $script:RevertCount++
    }
}

function Check-AppxAbsent {
    param(
        [string]$PkgName,
        [string]$FixGroup = 'Privacy / Bloatware'
    )
    $found = Get-AppxPackage -Name $PkgName -AllUsers -ErrorAction SilentlyContinue
    if (-not $found) {
        Write-OK "Bloatware absent: $PkgName"
        Log-Line ("[OK]     Bloatware absent: {0}" -f $PkgName)
        $script:OkCount++
    } else {
        Write-Reinst "Bloatware reinstalled: $PkgName"
        Log-Line ("[REINST] Bloatware reinstalled: {0}    fix={1}" -f $PkgName, $FixGroup)
        $script:RevertedList.Add($FixGroup)
        $script:ReinstCount++
    }
}

function Check-DNS {
    param([string]$FixGroup = 'Privacy / DNS')
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    if (-not $adapters) {
        Write-Info "No active network adapters -- skipping DNS check"
        return
    }
    $allGood = $true
    foreach ($a in $adapters) {
        $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $hasCloudflare = ($dns -contains '1.1.1.1') -or ($dns -contains '1.0.0.1')
        if ($hasCloudflare) {
            Write-OK "DNS on '$($a.Name)' uses Cloudflare ($($dns -join ', '))"
            Log-Line ("[OK]     DNS on {0}: {1}" -f $a.Name, ($dns -join ', '))
            $script:OkCount++
        } else {
            $shown = if ($dns) { $dns -join ', ' } else { '(DHCP / none)' }
            Write-Reverted "DNS on '$($a.Name)' no longer Cloudflare  (now: $shown)"
            Log-Line ("[REVERT] DNS on {0}: now={1}    fix={2}" -f $a.Name, $shown, $FixGroup)
            $script:RevertedList.Add($FixGroup)
            $script:RevertCount++
            $allGood = $false
        }
    }
}

# -- Windows Update history ---------------------------------------------

function Show-RecentUpdates {
    Write-Title "RECENT WINDOWS UPDATES (last 60 days)"
    $cutoff = (Get-Date).AddDays(-60)
    $hot = Get-HotFix -ErrorAction SilentlyContinue |
           Where-Object { $_.InstalledOn -and $_.InstalledOn -gt $cutoff } |
           Sort-Object InstalledOn -Descending
    if (-not $hot) {
        Write-Info "No hotfixes recorded in the last 60 days (or unavailable)."
    } else {
        foreach ($h in $hot) {
            $when = $h.InstalledOn.ToString('yyyy-MM-dd')
            Write-Host ("    {0}  {1}  {2}" -f $when, $h.HotFixID.PadRight(12), $h.Description) -ForegroundColor Gray
            Log-Line ("[UPDATE] {0}  {1}  {2}" -f $when, $h.HotFixID, $h.Description)
        }
    }

    # Also show current OS build (helps tie to KB articles)
    Write-Host ""
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ver = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    if ($os -and $ver) {
        $build = "{0}.{1}" -f $ver.CurrentBuildNumber, $ver.UBR
        Write-Host ("    Current build : {0}    DisplayVersion: {1}" -f $build, $ver.DisplayVersion) -ForegroundColor DarkCyan
        Log-Line ("[BUILD] {0}  DisplayVersion={1}" -f $build, $ver.DisplayVersion)
    }
}

# -- AUDIT GROUPS -------------------------------------------------------

function Audit-SecureBootShims {
    Write-Title "SECURE BOOT / UEFI SHIM REVOCATION"
    Write-Info "Background: ESET found 11 old Microsoft-signed UEFI shims (some from 2013)"
    Write-Info "that can be used to bypass Secure Boot entirely, with no exploit needed --"
    Write-Info "just a copy of the old shim. Microsoft revoked them in the June 2026 patch."
    Write-Info "See: 'Microsoft Secure Boot has been broken for most of its existence', Ars Technica."
    Write-Host ""

    # 1) Is Secure Boot even on?
    $g = 'Firmware setting -- not fixed by this suite (change in BIOS/UEFI setup)'
    $sb = $null
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
    } catch {
        $sb = $null
    }
    if ($sb -eq $true) {
        Write-OK "Secure Boot is ENABLED"
        Log-Line "[OK]     Secure Boot enabled"
        $script:OkCount++
    } elseif ($sb -eq $false) {
        Write-Reverted "Secure Boot is DISABLED in firmware -- no boot integrity protection at all right now"
        Log-Line ("[REVERT] Secure Boot disabled in firmware    fix={0}" -f $g)
        $script:RevertedList.Add($g)
        $script:RevertCount++
    } else {
        Write-NotSet "Could not determine Secure Boot status (legacy BIOS boot, non-UEFI system, or check unsupported here)"
        Log-Line "[NOTSET] Secure Boot status undetermined"
        $script:NotSetCount++
    }

    # 2) Has a post-June-2026 cumulative update landed? (carries the shim revocations)
    $g2 = 'Run Windows Update (Settings > Windows Update)'
    $cutoff = Get-Date -Year 2026 -Month 6 -Day 1
    $hotAfterCutoff = Get-HotFix -ErrorAction SilentlyContinue |
        Where-Object { $_.InstalledOn -and $_.InstalledOn -ge $cutoff } |
        Sort-Object InstalledOn -Descending
    if ($hotAfterCutoff) {
        Write-OK "Cumulative update(s) installed on/after 2026-06-01 found -- shim revocation is likely applied:"
        foreach ($h in ($hotAfterCutoff | Select-Object -First 3)) {
            Write-Host ("      {0}  {1}  {2}" -f $h.InstalledOn.ToString('yyyy-MM-dd'), $h.HotFixID, $h.Description) -ForegroundColor Gray
        }
        Log-Line "[OK]     Post-2026-06-01 update present -- shim revocation likely applied"
        $script:OkCount++
    } else {
        Write-Reverted "No installed update found dated on/after 2026-06-01 -- this machine may still trust the old, vulnerable shims"
        Log-Line ("[REVERT] No update found since 2026-06-01 -- shim revocation may be missing    fix={0}" -f $g2)
        $script:RevertedList.Add($g2)
        $script:RevertCount++
    }

    Write-Host ""
    Write-Info "This is a rough proxy only -- Get-HotFix doesn't reliably list every quality update."
    Write-Info "For a definitive answer:"
    Write-Info "  Settings > Windows Update > Update history  (confirm June 2026 or later is installed)"
    Write-Info "For a technical revocation check, use Microsoft/CERT's uefi-dbx-audit tool:"
    Write-Info "  https://github.com/sei-vsarvepalli/uefi-dbx-audit"
}

function Audit-Telemetry {
    Write-Title "TELEMETRY AND DIAGNOSTICS"
    $g = 'Privacy menu opt 2 (Telemetry)'
    Check-Service 'DiagTrack'     'DiagTrack service disabled' $g
    Check-Service 'dmwappushsvc'  'dmwappushsvc service disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 'AllowTelemetry policy = 0' $g
    Check-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0 'AllowTelemetry (legacy path) = 0' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0 'Feedback frequency NumberOfSIUFInPeriod = 0' $g
}

function Audit-Ads {
    Write-Title "ADS, SUGGESTIONS AND START MENU TRACKING"
    $g = 'Privacy menu opt 3 (Ads)'
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'Advertising ID disabled (HKCU)' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 'Advertising ID disabled (policy)' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0 'Start Menu suggestions disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0 'Start Menu subscribed content (-338388) off' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0 'Start Menu subscribed content (-353694) off' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0 'Start Menu subscribed content (-353696) off' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0 'Lock screen rotating overlay disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0 'Lock screen tips (-338387) disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0 'Settings app suggestions (-338393) disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'Tailored experiences disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 'Tailored experiences disabled (policy)' $g
    Check-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1 'Language list opt-out enabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 'Start menu app launch tracking disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0 'Silent app install disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 0 'Pre-installed apps disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 0 'OEM pre-installed apps disabled' $g
}

function Audit-ActivityHistory {
    Write-Title "ACTIVITY HISTORY"
    $g = 'Privacy menu opt 4 (Activity History)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0 'Activity Feed disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0 'PublishUserActivities = 0' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0 'UploadUserActivities = 0' $g
}

function Audit-DeliveryOpt {
    Write-Title "DELIVERY OPTIMIZATION"
    $g = 'Privacy menu opt 5 (Delivery Optimization)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 'Delivery Optimization mode = 0 (HTTP only)' $g
    Check-Service 'DoSvc' 'Delivery Optimization service disabled' $g
}

function Audit-SysMain {
    Write-Title "SYSMAIN / SUPERFETCH / PREFETCH"
    $g = 'Privacy menu opt 6 (SysMain)'
    Check-Service 'SysMain' 'SysMain service disabled' $g
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher' 0 'Prefetcher disabled' $g
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableSuperfetch' 0 'Superfetch disabled' $g
}

function Audit-Cortana {
    Write-Title "CORTANA"
    $g = 'Privacy menu opt 7 (Cortana)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0 'Cortana disabled (policy)' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortanaAboveLock' 0 'Cortana above lock disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1 'Web search in Search disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0 'Connected web search disabled' $g
}

function Audit-Edge {
    Write-Title "EDGE BROWSER FORCING"
    $g = 'Privacy menu opt 8 (Edge forcing)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1 'Edge first-run experience hidden' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WebWidgetAllowed' 0 'Edge desktop search bar widget off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'News and Interests widget off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0 'Edge startup boost off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0 'Edge background mode off' $g
}

function Audit-OneDrive {
    Write-Title "ONEDRIVE"
    $g = 'Privacy menu opt 9 (OneDrive)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1 'OneDrive sync disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableLibrariesDefaultSaveToOneDrive' 1 'Libraries default save to OneDrive disabled' $g
}

function Audit-Location {
    Write-Title "LOCATION / CAMERA / MICROPHONE"
    Write-Info "(Skip 'Location', 'Camera' or 'Microphone' rows below if you intentionally"
    Write-Info " re-enabled them via Restore -- options 2 and 12. They will show NOT SET.)"
    $g = 'Privacy menu opt 10 (Location/Cam/Mic)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1 'Location services disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessCamera' 2 'App access to Camera = 2 (deny)' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessMicrophone' 2 'App access to Microphone = 2 (deny)' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessAccountInfo' 2 'App access to Account Info = 2 (deny)' $g
}

function Audit-DNS {
    Write-Title "DNS PRIVACY (Cloudflare 1.1.1.1)"
    $g = 'Privacy menu opt 11 (DNS)'
    Check-DNS $g
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableAutoDoh' 2 'DNS-over-HTTPS auto-upgrade enabled' $g
}

function Audit-Recall {
    Write-Title "WINDOWS RECALL"
    $g = 'Privacy menu opt 12 (Recall)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'Windows Recall disabled (policy)' $g
}

function Audit-RemoteAccess {
    Write-Title "REMOTE ACCESS"
    Write-Info "(RemotePC is a separate third-party tool and is not affected.)"
    $g = 'Privacy menu opt 13 (Remote Access)'
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1 'Remote Desktop disabled' $g
    Check-Service 'RemoteRegistry' 'Remote Registry service disabled' $g
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0 'Remote Assistance disabled' $g
}

function Audit-Bloatware {
    Write-Title "BLOATWARE -- HAS ANY OF IT REINSTALLED?"
    $g = 'Privacy menu opt 14 (Bloatware)'
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
    foreach ($p in $bloat) { Check-AppxAbsent $p $g }
}

function Audit-Copilot {
    Write-Title "WINDOWS COPILOT (Extras)"
    $g = 'Extras menu opt 2 (Copilot)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'Copilot disabled (machine policy)' $g
    Check-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1 'Copilot disabled (user policy)' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0 'Copilot taskbar button hidden' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0 'Edge Copilot sidebar disabled' $g
}

function Audit-TelemetryExtras {
    Write-Title "TELEMETRY REINFORCEMENT (Extras)"
    $g = 'Extras menu opt 3 (Telemetry reinforcement)'
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Start' 0 'AutoLogger-Diagtrack-Listener disabled' $g
    Check-Service 'WerSvc' 'Windows Error Reporting service disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 'WER disabled (policy)' $g
    Check-Reg 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 'CEIP disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 'CEIP disabled (policy)' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1 'AppCompat inventory disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisablePCA' 1 'AppCompat PCA disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0 'Application Impact Telemetry off' $g
    Check-Service 'PcaSvc' 'Program Compatibility Assistant service disabled' $g
}

function Audit-CloudContent {
    Write-Title "CLOUD CONTENT, FIND MY DEVICE, SETTINGS SYNC, MAPS (Extras)"
    $g = 'Extras menu opt 4 (Cloud Content)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 'Consumer features disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1 'Cloud-optimized content disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1 'Soft Landing disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1 'Third-party suggestions disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1 'Spotlight features disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0 'Find My Device disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSync' 2 'Settings sync disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableCredentialsSettingSync' 2 'Credential sync disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0 'Cross-device clipboard disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AutoDownloadAndUpdateMapData' 0 'Maps auto-download disabled' $g
}

function Audit-InputPersonalization {
    Write-Title "HANDWRITING / INKING / SPEECH (Extras)"
    $g = 'Extras menu opt 5 (Input Personalization)'
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 'Implicit text collection disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'Implicit ink collection disabled' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0 'Contact harvesting disabled' $g
    Check-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'Online speech recognition off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0 'Input personalization off (policy)' $g
}

function Audit-EdgeTelemetry {
    Write-Title "EDGE OWN TELEMETRY (Extras)"
    $g = 'Extras menu opt 6 (Edge telemetry)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'MetricsReportingEnabled' 0 'Edge metrics reporting off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData' 0 'Edge diagnostic data off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'PersonalizationReportingEnabled' 0 'Edge personalization reporting off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SendSiteInfoToImproveServices' 0 'Edge "send site info" off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeShoppingAssistantEnabled' 0 'Edge shopping assistant off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SearchSuggestEnabled' 0 'Edge address-bar search suggestions off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'AutofillCreditCardEnabled' 0 'Edge credit card autofill off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BrowserSignin' 0 'Edge browser sign-in disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SyncDisabled' 1 'Edge sync disabled' $g
}

function Audit-BackgroundApps {
    Write-Title "BACKGROUND APPS / WI-FI SENSE (Extras)"
    $g = 'Extras menu opt 7 (Background apps)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 'UWP background apps denied (policy)' $g
    Check-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 'Global background apps disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0 'Wi-Fi Sense OEM auto-connect off' $g
}

function Audit-OneDriveFull {
    Write-Title "ONEDRIVE FULL UNINSTALL (Extras)"
    $g = 'Extras menu opt 8 (OneDrive uninstall)'
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSync' 1 'OneDrive file sync disabled' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1 'OneDrive network traffic blocked pre sign-in' $g
    # Detect re-installation
    $oneDriveExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    if (Test-Path $oneDriveExe) {
        Write-Reverted "OneDrive.exe is back at $oneDriveExe"
        Log-Line ("[REVERT] OneDrive.exe reinstalled at {0}    fix={1}" -f $oneDriveExe, $g)
        $script:RevertedList.Add($g)
        $script:RevertCount++
    } else {
        Write-OK "OneDrive.exe not present in user profile"
        Log-Line "[OK]     OneDrive.exe absent"
        $script:OkCount++
    }
}

function Audit-PerfHardener {
    Write-Title "PERFORMANCE HARDENER (key items most likely to drift)"
    $g = 'Perf Hardener (option 2 in launcher)'
    # Visual / UI
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 'Window transparency off' $g
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 'Taskbar animations off' $g
    # Hibernate (note: may be intentionally re-enabled via Restore)
    Write-Info "(Skip Hibernate row if you intentionally re-enabled it via Restore.)"
    $hibFile = Test-Path "$env:SystemDrive\hiberfil.sys"
    if ($hibFile) {
        Write-Reverted "hiberfil.sys exists -- hibernation appears ON"
        Log-Line ("[REVERT] hiberfil.sys present -- hibernation re-enabled    fix={0}" -f $g)
        $script:RevertedList.Add($g)
        $script:RevertCount++
    } else {
        Write-OK "Hibernation off (no hiberfil.sys)"
        Log-Line "[OK]     hiberfil.sys absent"
        $script:OkCount++
    }
    # Hiberboot / fast startup off
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'Fast Startup (HiberbootEnabled) off' $g
    # GameDVR
    Check-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'GameDVR AppCapture off' $g
    Check-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 'GameDVR disabled (policy)' $g
    # Hardware-accelerated GPU scheduling
    Check-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'Hardware GPU scheduling enabled' $g
    # Verbose status (helps diagnose update hangs)
    Check-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 1 'Verbose boot status enabled' $g
}

# -- SUMMARY -------------------------------------------------------------

function Show-Summary {
    Write-Host ""
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
    Write-Host "   SUMMARY" -ForegroundColor Cyan
    Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host ("    [OK]      ") -NoNewline -ForegroundColor Green;     Write-Host $script:OkCount
    Write-Host ("    [REVERT]  ") -NoNewline -ForegroundColor Red;       Write-Host $script:RevertCount
    Write-Host ("    [REINST]  ") -NoNewline -ForegroundColor Magenta;   Write-Host $script:ReinstCount
    Write-Host ("    [NOTSET]  ") -NoNewline -ForegroundColor DarkYellow;Write-Host ("$script:NotSetCount  (key never set, or hardener not yet run)")
    Write-Host ""

    if ($script:RevertCount -eq 0 -and $script:ReinstCount -eq 0) {
        Write-Host "  No drift detected. Your hardening is intact." -ForegroundColor Green
        Write-Host ""
        return
    }

    Write-Host "  THE FOLLOWING GROUPS NEED ATTENTION:" -ForegroundColor Yellow
    Write-Host ""
    $unique = $script:RevertedList | Sort-Object -Unique
    foreach ($u in $unique) {
        Write-Host ("    -> {0}" -f $u) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  For hardener-menu items: easiest fix is to re-run the launcher and pick" -ForegroundColor Cyan
    Write-Host "  option 4 (Privacy + Extras + Perf, back-to-back)." -ForegroundColor Cyan
    Write-Host "  For Secure Boot / firmware / Windows Update items: those aren't controlled" -ForegroundColor Cyan
    Write-Host "  by this suite -- fix them via BIOS/UEFI setup or Settings > Windows Update." -ForegroundColor Cyan
    Write-Host ""
}

function Save-Report {
    $logPath = "$env:USERPROFILE\Desktop\Win11Audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $header = @(
        "Win11 Hardener Audit Report",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Computer:  $env:COMPUTERNAME",
        "User:      $env:USERNAME",
        "",
        "Counts: OK=$script:OkCount   REVERT=$script:RevertCount   REINST=$script:ReinstCount   NOTSET=$script:NotSetCount",
        ("=" * 70),
        ""
    )
    ($header + $script:Log) | Out-File -FilePath $logPath -Encoding ASCII
    Write-Host ("  Full report saved to: {0}" -f $logPath) -ForegroundColor Green
    Write-Host ""
}

# -- MAIN ----------------------------------------------------------------

Write-Header

Show-RecentUpdates
Audit-SecureBootShims

Audit-Telemetry
Audit-Ads
Audit-ActivityHistory
Audit-DeliveryOpt
Audit-SysMain
Audit-Cortana
Audit-Edge
Audit-OneDrive
Audit-Location
Audit-DNS
Audit-Recall
Audit-RemoteAccess
Audit-Bloatware

Audit-Copilot
Audit-TelemetryExtras
Audit-CloudContent
Audit-InputPersonalization
Audit-EdgeTelemetry
Audit-BackgroundApps
Audit-OneDriveFull

Audit-PerfHardener

Show-Summary
Save-Report

Read-Host "  Press Enter to exit"