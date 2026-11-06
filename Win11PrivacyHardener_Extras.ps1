<#
.SYNOPSIS
    Windows 10/11 Privacy Hardener -- EXTRAS pack
    Author : Brad / CrisisOfTruth.org
    Version: 1.2
.DESCRIPTION
    Complements Win11PrivacyHardener.ps1 by closing gaps:
      - Copilot                             (Windows 11 only)
      - Telemetry reinforcement (AutoLogger, WER, CEIP, AppCompat)
      - Cloud content / consumer features / Find My Device / Sync / Maps
      - Input personalization (handwriting, speech, cross-device clipboard)
      - Edge's own telemetry (separate from Edge forcing)
      - Background apps + Wi-Fi Sense
      - OneDrive FULL uninstall (not just disable)

    Works on both Windows 10 and Windows 11. Sections that only
    exist on Windows 11 (Copilot) are automatically skipped on
    Windows 10.

    Two ways to use it:

    (A) Standalone -- just run this file. It has its own menu.
        powershell -NoProfile -ExecutionPolicy Bypass -File Win11PrivacyHardener_Extras.ps1

    (B) Integrated -- add this near the top of Win11PrivacyHardener.ps1
        (after the helpers, before Show-Menu):

          . "$PSScriptRoot\Win11PrivacyHardener_Extras.ps1" -AsLibrary

        Then add menu entries for the Invoke-*Tweaks functions defined below.
.NOTES
    Run via its own launcher or right-click and Run with PowerShell.
#>

param(
    [switch]$AsLibrary   # when true, skip self-elevation + menu (dot-source mode)
)

# ---------------------------------------------------------------------------
#  Self-elevation (skipped in library mode)
# ---------------------------------------------------------------------------
if (-not $AsLibrary) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
        Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
        exit
    }
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'SilentlyContinue'
}

# ---------------------------------------------------------------------------
#  OS DETECTION  (only set if not already inherited from a parent script)
# ---------------------------------------------------------------------------
if (-not (Get-Variable -Name 'IsWin11' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:OSBuild = 0
    try {
        $script:OSBuild = [int]((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuildNumber)
    } catch { $script:OSBuild = 0 }
    $script:IsWin11 = $script:OSBuild -ge 22000
    $script:OSLabel = if ($script:IsWin11) { "Windows 11 (build $script:OSBuild)" } else { "Windows 10 (build $script:OSBuild)" }
}

# ---------------------------------------------------------------------------
#  HELPERS -- only define if not already loaded (library mode reuses parent)
# ---------------------------------------------------------------------------

if (-not (Get-Command Write-OK -ErrorAction SilentlyContinue)) {

    function Write-Header {
        Clear-Host
        $line = '=' * 70
        Write-Host ""
        Write-Host " $line" -ForegroundColor DarkCyan
        Write-Host "  Win10/11 Privacy Hardener EXTRAS  --  CrisisOfTruth.org" -ForegroundColor Cyan
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
}

# ---------------------------------------------------------------------------
#  TWEAK GROUPS
# ---------------------------------------------------------------------------

function Invoke-CopilotTweaks {
    Write-Title "WINDOWS COPILOT"

    if (Skip-IfWin10 "Windows Copilot is a Windows 11 feature") { return }

    Invoke-Tweak "Disable Windows Copilot (machine policy)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    }

    Invoke-Tweak "Disable Windows Copilot (user policy)" {
        Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    }

    Invoke-Tweak "Hide Copilot button on the taskbar" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
    }

    Invoke-Tweak "Disable Copilot in Edge sidebar" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 0
    }
}

function Invoke-TelemetryExtraTweaks {
    Write-Title "TELEMETRY -- EXTRA REINFORCEMENT"

    Invoke-Tweak "Disable AutoLogger-Diagtrack-Listener at boot" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener' 'Start' 0
    }

    Invoke-Tweak "Disable Windows Error Reporting (WerSvc + policy)" {
        Disable-Svc 'WerSvc'
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'DoReport' 0
    }

    Invoke-Tweak "Disable Customer Experience Improvement Program (CEIP)" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
    }

    Invoke-Tweak "Disable Application Compatibility telemetry" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisablePCA' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
    }

    Invoke-Tweak "Disable compatibility assistant service (PcaSvc)" {
        Disable-Svc 'PcaSvc'
    }

    Invoke-Tweak "Disable cloud notification service (WpnUserService telemetry path)" {
        Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoCloudApplicationNotification' 1
    }
}

function Invoke-CloudContentTweaks {
    Write-Title "CLOUD CONTENT, CONSUMER FEATURES AND SYNC"

    Invoke-Tweak "Disable Windows Consumer Features (suggested/installed apps)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
    }

    Invoke-Tweak "Disable Find My Device" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0
    }

    Invoke-Tweak "Disable Windows Settings sync to Microsoft account" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSync' 2
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableSettingSyncUserOverride' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableApplicationSettingSync' 2
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' 'DisableCredentialsSettingSync' 2
    }

    Invoke-Tweak "Disable cross-device cloud clipboard sync" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0
    }

    Invoke-Tweak "Disable Maps auto-download of map data" {
        Set-Reg 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AutoDownloadAndUpdateMapData' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' 'AllowUntriggeredNetworkTrafficOnSettingsPage' 0
    }
}

function Invoke-InputPersonalizationTweaks {
    Write-Title "HANDWRITING, INKING AND SPEECH"

    Invoke-Tweak "Disable implicit text + ink collection (handwriting data)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    }

    Invoke-Tweak "Disable harvesting of contacts for input personalization" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    }

    Invoke-Tweak "Disable online speech recognition" {
        Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' 'AllowInputPersonalization' 0
    }

    Invoke-Tweak "Disable typing + inking personalization upload" {
        Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
        Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    }
}

function Invoke-EdgeTelemetryTweaks {
    Write-Title "EDGE -- OWN TELEMETRY (separate from Edge forcing)"

    Invoke-Tweak "Disable Edge metrics and usage data reporting" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'MetricsReportingEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'PersonalizationReportingEnabled' 0
    }

    Invoke-Tweak "Disable Edge 'send site info to improve services'" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SendSiteInfoToImproveServices' 0
    }

    Invoke-Tweak "Disable Edge shopping assistant and coupons" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeShoppingAssistantEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ShowRecommendationsEnabled' 0
    }

    Invoke-Tweak "Disable Edge address bar search suggestions (sent to Bing)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SearchSuggestEnabled' 0
    }

    Invoke-Tweak "Disable Edge autofill for cards + addresses (avoid cloud sync)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'AutofillCreditCardEnabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'AutofillAddressEnabled' 0
    }

    Invoke-Tweak "Disable Edge sign-in to sync" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BrowserSignin' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SyncDisabled' 1
    }
}

function Invoke-BackgroundAppsTweaks {
    Write-Title "BACKGROUND APPS AND WI-FI SENSE"

    Invoke-Tweak "Deny all UWP apps from running in the background (policy)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
    }

    Invoke-Tweak "Disable global background apps (user setting)" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    }

    Invoke-Tweak "Disable Wi-Fi Sense auto-connect to open hotspots" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 0
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' 'Value' 0
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' 'Value' 0
    }
}

function Invoke-OneDriveRemovalTweaks {
    Write-Title "ONEDRIVE -- FULL UNINSTALL (not just disable)"

    Invoke-Tweak "Stop all OneDrive processes" {
        Get-Process -Name 'OneDrive','OneDriveSetup','FileCoAuth' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Invoke-Tweak "Run OneDriveSetup.exe /uninstall" {
        $paths = @(
            "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
            "$env:SystemRoot\System32\OneDriveSetup.exe"
        )
        $ran = $false
        foreach ($p in $paths) {
            if (Test-Path $p) {
                Start-Process $p -ArgumentList '/uninstall' -NoNewWindow -Wait
                $ran = $true
            }
        }
        if (-not $ran) { Write-Info "    OneDriveSetup.exe not found -- already uninstalled?" }
    }

    Invoke-Tweak "Remove leftover OneDrive folders" {
        $folders = @(
            "$env:USERPROFILE\OneDrive",
            "$env:LOCALAPPDATA\Microsoft\OneDrive",
            "$env:PROGRAMDATA\Microsoft OneDrive",
            "$env:SYSTEMDRIVE\OneDriveTemp"
        )
        foreach ($f in $folders) {
            if (Test-Path $f) {
                Remove-Item -Path $f -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Invoke-Tweak "Remove OneDrive from File Explorer sidebar" {
        # HKCR is not mounted by default -- use HKLM\SOFTWARE\Classes equivalent
        $clsids = @(
            'HKLM:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
            'HKLM:\SOFTWARE\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        )
        foreach ($c in $clsids) {
            if (Test-Path $c) {
                Set-Reg $c 'System.IsPinnedToNameSpaceTree' 0
            }
        }
    }

    Invoke-Tweak "Remove OneDrive scheduled tasks" {
        Get-ScheduledTask -TaskName 'OneDrive*' -ErrorAction SilentlyContinue |
            Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
    }

    Invoke-Tweak "Block OneDrive from reinstalling (policy)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSync' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1
    }
}

function Invoke-AllExtraPrivacyTweaks {
    Invoke-CopilotTweaks
    Invoke-TelemetryExtraTweaks
    Invoke-CloudContentTweaks
    Invoke-InputPersonalizationTweaks
    Invoke-EdgeTelemetryTweaks
    Invoke-BackgroundAppsTweaks
    Invoke-OneDriveRemovalTweaks
    Write-Host ""
    Write-Host "  ALL EXTRA TWEAKS COMPLETE. REBOOT RECOMMENDED." -ForegroundColor Green
    Write-Host ""
}

function Save-ExtrasLog {
    $logPath = "$PSScriptRoot\Win11PrivacyExtras_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $header = @(
        "Win10/11 Privacy Hardener EXTRAS Log",
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
#  MENU (only runs when not loaded as a library)
# ---------------------------------------------------------------------------

if (-not $AsLibrary) {

    function Show-ExtrasMenu {
        Write-Header
        Write-Host "  Select an option:" -ForegroundColor White
        Write-Host ""
        $copilotLabel = if ($script:IsWin11) { "2  -- Copilot" } else { "2  -- Copilot  (Win11 only -- will skip)" }
        $opts = @(
            " 1  -- ALL EXTRA TWEAKS (recommended)"
            " $copilotLabel"
            " 3  -- Telemetry reinforcement (AutoLogger, WER, CEIP, AppCompat)"
            " 4  -- Cloud Content / Find My Device / Settings Sync / Maps"
            " 5  -- Handwriting, Inking and Speech"
            " 6  -- Edge's own telemetry"
            " 7  -- Background apps and Wi-Fi Sense"
            " 8  -- OneDrive FULL uninstall"
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
        Show-ExtrasMenu
        $choice = (Read-Host "  Enter choice").Trim().ToUpper()
        switch ($choice) {
            '1' { Invoke-AllExtraPrivacyTweaks }
            '2' { Invoke-CopilotTweaks }
            '3' { Invoke-TelemetryExtraTweaks }
            '4' { Invoke-CloudContentTweaks }
            '5' { Invoke-InputPersonalizationTweaks }
            '6' { Invoke-EdgeTelemetryTweaks }
            '7' { Invoke-BackgroundAppsTweaks }
            '8' { Invoke-OneDriveRemovalTweaks }
            'L' { Save-ExtrasLog }
            'Q' { break }
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
}
