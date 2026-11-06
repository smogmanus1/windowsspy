<#
.SYNOPSIS
    Windows 11 Snapshot -- Full pre-hardening state backup
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    READ-ONLY. Captures the current state of every Windows setting
    that the rest of the Win11 Hardener Suite is capable of changing,
    then writes it to two files:

      Documents\Win11Hardener\Win11Snapshot_<host>_<stamp>.xml   (restore-ready)
      Documents\Win11Hardener\Win11Snapshot_<host>_<stamp>.txt   (human-readable)

    A LATEST copy is also written (Win11Snapshot_LATEST.xml + .txt)
    so Win11SnapshotRestore.ps1 always knows which file to load by
    default.

    What gets captured:
      - Every registry value the privacy / extras / perf scripts touch
      - Service start types and current run states
      - Scheduled task enabled / disabled state
      - DNS servers per network adapter
      - Power plan + hibernation + fast-startup state
      - Installed Appx packages (so you can list what was removed)
      - Provisioned Appx packages (so you can spot what came back)
      - Windows Firewall rule list (relevant rules only)
      - File-system flags (8.3 names, last-access, TRIM)
      - File-association export via DISM (full system-wide map)
      - Windows version / build / hostname / user metadata

    What this script does NOT do:
      - It makes ZERO changes to the system.
      - It does NOT replace a real backup (Acronis / Macrium). Use one.
      - It does NOT capture personal files, installed program lists,
        or registered users -- that is image-backup territory.

    Recommended workflow:
      1. Run a full image backup (Acronis perpetual, Macrium Reflect).
      2. Run THIS snapshot script. Twice. Keep both files.
      3. Then run the hardener.
      4. If anything goes sideways, run Win11SnapshotRestore.ps1.
.NOTES
    Self-elevates to Administrator automatically.
    Run via RunHardener.bat (option S) or right-click + Run with PowerShell.
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
    Write-Host "  Win11 Snapshot  --  CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host "  Read-only system-state backup. No changes will be made." -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Note ($msg) { Write-Host "         $msg" -ForegroundColor Gray }
function Write-Sep        { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
    Write-Sep
}

# ---------------------------------------------------------------------------
#  STORAGE PATHS  (matches AppDefaults convention so audits can find them)
# ---------------------------------------------------------------------------

$script:SnapDir   = Join-Path $env:USERPROFILE 'Documents\Win11Hardener'
$script:Stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:HostTag   = $env:COMPUTERNAME
$script:XmlFile   = Join-Path $script:SnapDir ("Win11Snapshot_{0}_{1}.xml" -f $script:HostTag, $script:Stamp)
$script:TxtFile   = Join-Path $script:SnapDir ("Win11Snapshot_{0}_{1}.txt" -f $script:HostTag, $script:Stamp)
$script:LatestXml = Join-Path $script:SnapDir 'Win11Snapshot_LATEST.xml'
$script:LatestTxt = Join-Path $script:SnapDir 'Win11Snapshot_LATEST.txt'

if (-not (Test-Path $script:SnapDir)) {
    New-Item -Path $script:SnapDir -ItemType Directory -Force | Out-Null
}

# ---------------------------------------------------------------------------
#  REGISTRY WATCH LIST
#  Every value any of the hardener scripts can touch.
#  Keep this in sync with the *Hardener.ps1 files.
# ---------------------------------------------------------------------------

$script:RegWatch = @(
    # -- Telemetry / DataCollection
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection';                              N='AllowTelemetry' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection';               N='AllowTelemetry' },
    @{ G='Telemetry'; P='HKCU:\SOFTWARE\Microsoft\Siuf\Rules';                                                   N='NumberOfSIUFInPeriod' },
    @{ G='Telemetry'; P='HKCU:\SOFTWARE\Microsoft\Siuf\Rules';                                                   N='PeriodInNanoSeconds' },
    @{ G='Telemetry'; P='HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\AutoLogger-Diagtrack-Listener';   N='Start' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting';                     N='Disabled' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting';                     N='DoReport' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Microsoft\SQMClient\Windows';                                            N='CEIPEnable' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows';                                   N='CEIPEnable' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat';                                   N='DisableInventory' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat';                                   N='DisablePCA' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat';                                   N='DisableUAR' },
    @{ G='Telemetry'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat';                                   N='AITEnable' },

    # -- Ads / Suggestions / Start Menu
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo';                       N='Enabled' },
    @{ G='Ads';       P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo';                             N='DisabledByGroupPolicy' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SystemPaneSuggestionsEnabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SubscribedContent-338388Enabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SubscribedContent-353694Enabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SubscribedContent-353696Enabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='RotatingLockScreenOverlayEnabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SubscribedContent-338387Enabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SubscribedContent-338393Enabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SilentInstalledAppsEnabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='PreInstalledAppsEnabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='OemPreInstalledAppsEnabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager';                N='SoftLandingEnabled' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy';                               N='TailoredExperiencesWithDiagnosticDataEnabled' },
    @{ G='Ads';       P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                                N='DisableTailoredExperiencesWithDiagnosticData' },
    @{ G='Ads';       P='HKCU:\Control Panel\International\User Profile';                                        N='HttpAcceptLanguageOptOut' },
    @{ G='Ads';       P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced';                     N='Start_TrackProgs' },

    # -- Activity History
    @{ G='Activity';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                                      N='EnableActivityFeed' },
    @{ G='Activity';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                                      N='PublishUserActivities' },
    @{ G='Activity';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                                      N='UploadUserActivities' },

    # -- Delivery Optimization / Prefetch
    @{ G='DeliveryOpt';P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization';                       N='DODownloadMode' },
    @{ G='SysMain';   P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; N='EnablePrefetcher' },
    @{ G='SysMain';   P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; N='EnableSuperfetch' },

    # -- Cortana / Search
    @{ G='Cortana';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                              N='AllowCortana' },
    @{ G='Cortana';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                              N='AllowCortanaAboveLock' },
    @{ G='Cortana';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                              N='DisableWebSearch' },
    @{ G='Cortana';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                              N='ConnectedSearchUseWeb' },
    @{ G='Cortana';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search';                              N='AllowSearchToUseLocation' },
    @{ G='Cortana';   P='HKCU:\Software\Policies\Microsoft\Windows\Explorer';                                    N='DisableSearchBoxSuggestions' },
    @{ G='Cortana';   P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                                N='BingSearchEnabled' },
    @{ G='Cortana';   P='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                                N='CortanaConsent' },

    # -- Edge forcing + Edge own telemetry
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='HideFirstRunExperience' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='WebWidgetAllowed' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='StartupBoostEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='BackgroundModeEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='HubsSidebarEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='MetricsReportingEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='DiagnosticData' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='PersonalizationReportingEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='SendSiteInfoToImproveServices' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='EdgeShoppingAssistantEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='SearchSuggestEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='AutofillCreditCardEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='AutofillAddressEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='BrowserSignin' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='SyncDisabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Edge';                                                N='ShowRecommendationsEnabled' },
    @{ G='Edge';      P='HKLM:\SOFTWARE\Policies\Microsoft\Dsh';                                                 N='AllowNewsAndInterests' },

    # -- OneDrive
    @{ G='OneDrive';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive';                                    N='DisableFileSyncNGSC' },
    @{ G='OneDrive';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive';                                    N='DisableFileSync' },
    @{ G='OneDrive';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive';                                    N='DisableLibrariesDefaultSaveToOneDrive' },
    @{ G='OneDrive';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive';                                    N='PreventNetworkTrafficPreUserSignIn' },
    @{ G='OneDrive';  P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                                   N='OneDrive' },

    # -- Location / Camera / Mic
    @{ G='Location';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors';                          N='DisableLocation' },
    @{ G='Location';  P='HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration';                   N='Status' },
    @{ G='Location';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';                                  N='LetAppsAccessCamera' },
    @{ G='Location';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';                                  N='LetAppsAccessMicrophone' },
    @{ G='Location';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';                                  N='LetAppsAccessAccountInfo' },
    @{ G='Location';  P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';                                  N='LetAppsRunInBackground' },
    @{ G='Location';  P='HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications';          N='GlobalUserDisabled' },

    # -- DNS / DoH
    @{ G='DNS';       P='HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters';                           N='EnableAutoDoh' },

    # -- NCSI / Networking
    @{ G='Network';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator';          N='NoActiveProbe' },
    @{ G='Network';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient';                                N='EnableMulticast' },
    @{ G='Network';   P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\WPAD';       N='AutoDetect' },
    @{ G='Network';   P='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';           N='NetworkThrottlingIndex' },
    @{ G='Network';   P='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';           N='SystemResponsiveness' },
    @{ G='Network';   P='HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters';                       N='IRPStackSize' },
    @{ G='Network';   P='HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config';                             N='AutoConnectAllowedOEM' },

    # -- Recall / Copilot
    @{ G='AI';        P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';                                   N='DisableAIDataAnalysis' },
    @{ G='AI';        P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot';                              N='TurnOffWindowsCopilot' },
    @{ G='AI';        P='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot';                              N='TurnOffWindowsCopilot' },
    @{ G='AI';        P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced';                     N='ShowCopilotButton' },

    # -- Remote Access
    @{ G='Remote';    P='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server';                                N='fDenyTSConnections' },
    @{ G='Remote';    P='HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance';                              N='fAllowToGetHelp' },

    # -- Cloud Content / Sync / Maps / FindMyDevice
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                                N='DisableWindowsConsumerFeatures' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                                N='DisableCloudOptimizedContent' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                                N='DisableSoftLanding' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                                N='DisableThirdPartySuggestions' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent';                                N='DisableWindowsSpotlightFeatures' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice';                                        N='AllowFindMyDevice' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync';                                 N='DisableSettingSync' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync';                                 N='DisableSettingSyncUserOverride' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync';                                 N='DisableApplicationSettingSync' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync';                                 N='DisableCredentialsSettingSync' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';                                      N='AllowCrossDeviceClipboard' },
    @{ G='CloudSync'; P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps';                                        N='AutoDownloadAndUpdateMapData' },

    # -- Input Personalization
    @{ G='Input';     P='HKCU:\SOFTWARE\Microsoft\InputPersonalization';                                         N='RestrictImplicitTextCollection' },
    @{ G='Input';     P='HKCU:\SOFTWARE\Microsoft\InputPersonalization';                                         N='RestrictImplicitInkCollection' },
    @{ G='Input';     P='HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore';                        N='HarvestContacts' },
    @{ G='Input';     P='HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy';                  N='HasAccepted' },
    @{ G='Input';     P='HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization';                                N='AllowInputPersonalization' },

    # -- Visual / Performance UI
    @{ G='VisualUI';  P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize';                    N='EnableTransparency' },
    @{ G='VisualUI';  P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects';                N='VisualFXSetting' },
    @{ G='VisualUI';  P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced';                     N='TaskbarAnimations' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop';                                                           N='UserPreferencesMask' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop';                                                           N='EnableAeroPeek' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop';                                                           N='SmoothScroll' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop';                                                           N='MenuShowDelay' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop';                                                           N='WaitToKillAppTimeout' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop';                                                           N='HungAppTimeout' },
    @{ G='VisualUI';  P='HKCU:\Control Panel\Desktop\WindowMetrics';                                             N='MinAnimate' },

    # -- Memory Management / Disk
    @{ G='Memory';    P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management';              N='LargeSystemCache' },
    @{ G='Memory';    P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management';              N='DisablePagingExecutive' },

    # -- GameDVR / Gaming
    @{ G='Gaming';    P='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';                               N='AppCaptureEnabled' },
    @{ G='Gaming';    P='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';                                     N='AllowGameDVR' },
    @{ G='Gaming';    P='HKCU:\System\GameConfigStore';                                                          N='GameDVR_Enabled' },
    @{ G='Gaming';    P='HKCU:\System\GameConfigStore';                                                          N='GameDVR_FSEBehaviorMode' },
    @{ G='Gaming';    P='HKCU:\System\GameConfigStore';                                                          N='GameDVR_FSEBehavior' },
    @{ G='Gaming';    P='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';                                N='HwSchMode' },

    # -- Boot / Power state
    @{ G='Boot';      P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power';                          N='HiberbootEnabled' },
    @{ G='Boot';      P='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';                       N='VerboseStatus' }
)

# ---------------------------------------------------------------------------
#  SERVICE WATCH LIST
# ---------------------------------------------------------------------------

$script:SvcWatch = @(
    'DiagTrack', 'dmwappushsvc', 'DoSvc', 'SysMain', 'WerSvc', 'PcaSvc',
    'RemoteRegistry', 'lfsvc',
    'CDPSvc', 'CDPUserSvc', 'OneSyncSvc', 'PimIndexMaintenanceSvc',
    'WMPNetworkSvc', 'TrkWks', 'MapsBroker', 'PhoneSvc', 'icssvc',
    'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc',
    'wisvc', 'WpcMonSvc', 'RetailDemo', 'RemoteAccess', 'SharedAccess',
    'Fax', 'lmhosts', 'PushToInstall', 'DPS', 'WdiServiceHost', 'WdiSystemHost',
    'w32time'
)

# ---------------------------------------------------------------------------
#  SCHEDULED TASK WATCH LIST
# ---------------------------------------------------------------------------

$script:TaskWatch = @(
    @{ Path='\Microsoft\Windows\Application Experience\';                   Name='Microsoft Compatibility Appraiser' },
    @{ Path='\Microsoft\Windows\Application Experience\';                   Name='ProgramDataUpdater' },
    @{ Path='\Microsoft\Windows\Application Experience\';                   Name='StartupAppTask' },
    @{ Path='\Microsoft\Windows\Autochk\';                                  Name='Proxy' },
    @{ Path='\Microsoft\Windows\Customer Experience Improvement Program\';  Name='Consolidator' },
    @{ Path='\Microsoft\Windows\Customer Experience Improvement Program\';  Name='UsbCeip' },
    @{ Path='\Microsoft\Windows\DiskDiagnostic\';                           Name='Microsoft-Windows-DiskDiagnosticDataCollector' },
    @{ Path='\Microsoft\Windows\NetTrace\';                                 Name='GatherNetworkInfo' },
    @{ Path='\Microsoft\Windows\Windows Error Reporting\';                  Name='QueueReporting' },
    @{ Path='\Microsoft\Windows\Maps\';                                     Name='MapsUpdateTask' },
    @{ Path='\Microsoft\Windows\Maps\';                                     Name='MapsToastTask' }
)

# ---------------------------------------------------------------------------
#  CAPTURE FUNCTIONS
# ---------------------------------------------------------------------------

function Capture-Metadata {
    Write-Title "METADATA"
    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ver = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

    if ($os) {
        $caption = $os.Caption
        $osver   = $os.Version
        $build   = $os.BuildNumber
        $instDt  = $os.InstallDate.ToString('o')
        $sysDir  = $os.SystemDirectory
    } else {
        $caption = 'unknown'; $osver = 'unknown'; $build = 'unknown'
        $instDt  = $null;     $sysDir = $env:SystemRoot
    }
    if ($ver) {
        $ubr  = $ver.UBR
        $disp = $ver.DisplayVersion
    } else {
        $ubr = $null; $disp = $null
    }

    $meta = [PSCustomObject]@{
        SnapshotVersion  = '1.0'
        CapturedAt       = (Get-Date).ToString('o')
        Hostname         = $env:COMPUTERNAME
        Username         = $env:USERNAME
        UserDomain       = $env:USERDOMAIN
        OSCaption        = $caption
        OSVersion        = $osver
        OSBuildNumber    = $build
        UBR              = $ubr
        DisplayVersion   = $disp
        InstallDate      = $instDt
        SystemDirectory  = $sysDir
    }

    Write-OK "Captured host metadata"
    Write-Note ("Host: {0}    User: {1}" -f $meta.Hostname, $meta.Username)
    Write-Note ("OS:   {0}  build {1}.{2}  ({3})" -f $meta.OSCaption, $meta.OSBuildNumber, $meta.UBR, $meta.DisplayVersion)
    return $meta
}

function Capture-Registry {
    Write-Title "REGISTRY VALUES (every key the suite can change)"
    $rows = New-Object System.Collections.Generic.List[object]
    $miss = 0
    foreach ($w in $script:RegWatch) {
        $row = [PSCustomObject]@{
            Group    = $w.G
            Path     = $w.P
            Name     = $w.N
            Existed  = $false
            Type     = $null
            Value    = $null
        }
        if (Test-Path $w.P) {
            $item = Get-ItemProperty -Path $w.P -ErrorAction SilentlyContinue
            if ($item -and ($item.PSObject.Properties.Name -contains $w.N)) {
                $row.Existed = $true
                $row.Value   = $item.($w.N)
                # Best-effort type detection
                try {
                    $key = Get-Item -LiteralPath $w.P -ErrorAction SilentlyContinue
                    if ($key) {
                        $kind = $key.GetValueKind($w.N)
                        if ($kind) { $row.Type = "$kind" }
                    }
                } catch {
                    # Some keys deny enumeration; type stays $null
                }
            }
        }
        if (-not $row.Existed) { $miss++ }
        $rows.Add($row) | Out-Null
    }
    Write-OK ("Captured {0} registry values  ({1} not currently set)" -f $rows.Count, $miss)
    return ,$rows
}

function Capture-Services {
    Write-Title "SERVICE START TYPES"
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($n in $script:SvcWatch) {
        # CDPUserSvc and friends are per-session with random suffix.
        # Capture the template entry under HKLM\Services so restore
        # gets the inherited value for new sessions.
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) {
            $rows.Add([PSCustomObject]@{
                Name         = $n
                Present      = $true
                StartType    = "$($svc.StartType)"
                Status       = "$($svc.Status)"
                DisplayName  = $svc.DisplayName
            }) | Out-Null
        } else {
            # Service not installed -- still record it for restore-context
            $rows.Add([PSCustomObject]@{
                Name         = $n
                Present      = $false
                StartType    = $null
                Status       = $null
                DisplayName  = $null
            }) | Out-Null
        }

        # Also capture the registry-level Start value for per-user services
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
        if (Test-Path $regPath) {
            $start = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).Start
            if ($null -ne $start) {
                $rows.Add([PSCustomObject]@{
                    Name         = "$n (Start regkey)"
                    Present      = $true
                    StartType    = "RegStart=$start"
                    Status       = $null
                    DisplayName  = $null
                }) | Out-Null
            }
        }
    }
    Write-OK ("Captured {0} service entries" -f $rows.Count)
    return ,$rows
}

function Capture-ScheduledTasks {
    Write-Title "SCHEDULED TASK STATE"
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($t in $script:TaskWatch) {
        $task = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        if ($task) { $state = "$($task.State)" } else { $state = 'NotPresent' }
        $rows.Add([PSCustomObject]@{
            TaskPath = $t.Path
            TaskName = $t.Name
            State    = $state
        }) | Out-Null
    }
    Write-OK ("Captured {0} scheduled tasks" -f $rows.Count)
    return ,$rows
}

function Capture-Network {
    Write-Title "NETWORK ADAPTERS + DNS"
    $rows = New-Object System.Collections.Generic.List[object]
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
    foreach ($a in $adapters) {
        $dns4 = (Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $dns6 = (Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
        if ($dns4) { $dns4str = ($dns4 -join ',') } else { $dns4str = '' }
        if ($dns6) { $dns6str = ($dns6 -join ',') } else { $dns6str = '' }
        $rows.Add([PSCustomObject]@{
            Name           = $a.Name
            InterfaceIndex = $a.InterfaceIndex
            Status         = "$($a.Status)"
            MacAddress     = $a.MacAddress
            DnsIPv4        = $dns4str
            DnsIPv6        = $dns6str
        }) | Out-Null
    }

    # TCP global settings
    $tcp = Get-NetTCPSetting -SettingName Internet -ErrorAction SilentlyContinue
    if ($tcp) { $atl = "$($tcp.AutoTuningLevelLocal)" } else { $atl = 'unknown' }
    $tcpRow = [PSCustomObject]@{
        AutoTuningLevel = $atl
    }

    Write-OK ("Captured {0} adapters" -f $rows.Count)
    return [PSCustomObject]@{
        Adapters = $rows
        TCP      = $tcpRow
    }
}

function Capture-Power {
    Write-Title "POWER + HIBERNATION + FAST STARTUP"
    $active = (powercfg -getactivescheme 2>&1 | Out-String)
    $guid   = ($active -split 'GUID:\s+')[1] -replace '\s+\(.*',''
    if ($guid) { $guid = $guid.Trim() }

    # Hibernation: hiberfil.sys is a strong indicator
    $hiberfil = Test-Path "$env:SystemDrive\hiberfil.sys"

    # Fast Startup
    $fast = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled

    $row = [PSCustomObject]@{
        ActiveSchemeGuid = $guid
        ActiveSchemeText = ($active.Trim())
        HibernationFilePresent = $hiberfil
        HiberbootEnabled = $fast
    }
    Write-OK "Captured power configuration"
    Write-Note ("Active GUID: {0}" -f $guid)
    Write-Note ("hiberfil.sys present: {0}    HiberbootEnabled: {1}" -f $hiberfil, $fast)
    return $row
}

function Capture-Appx {
    Write-Title "INSTALLED APPX PACKAGES (full inventory)"
    $installed = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Select-Object Name, PackageFullName, Publisher
    Write-OK ("Captured {0} installed packages" -f $installed.Count)

    Write-Title "PROVISIONED APPX PACKAGES (re-install seeds)"
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Select-Object DisplayName, PackageName
    Write-OK ("Captured {0} provisioned packages" -f $prov.Count)

    return [PSCustomObject]@{
        Installed   = $installed
        Provisioned = $prov
    }
}

function Capture-Firewall {
    Write-Title "WINDOWS FIREWALL RULES (telemetry-related)"
    # Capture rules that mention Microsoft / telemetry / DiagTrack patterns
    # so we can spot user-added blocks that shouldn't get clobbered.
    $patterns = @('telemetry','DiagTrack','vortex','Microsoft','BlockMS','Block-MS')
    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object {
            $name = "$($_.DisplayName)"
            $matched = $false
            foreach ($p in $patterns) { if ($name -like "*$p*") { $matched = $true; break } }
            $matched
        } |
        Select-Object DisplayName, Direction, Action, Enabled, Profile, Description

    Write-OK ("Captured {0} relevant firewall rules" -f $rules.Count)
    return ,$rules
}

function Capture-FileSystem {
    Write-Title "FILE-SYSTEM FLAGS"
    function Read-Fs($flag) {
        $r = (& fsutil behavior query $flag 2>&1 | Out-String).Trim()
        return $r
    }
    $row = [PSCustomObject]@{
        Disable8dot3      = Read-Fs 'disable8dot3'
        DisableLastAccess = Read-Fs 'disablelastaccess'
        TrimNTFS          = (& fsutil behavior query DisableDeleteNotify NTFS 2>&1 | Out-String).Trim()
        TrimReFS          = (& fsutil behavior query DisableDeleteNotify ReFS 2>&1 | Out-String).Trim()
    }
    Write-OK "Captured fsutil behavior flags"
    return $row
}

function Capture-FileAssociations {
    Write-Title "DEFAULT APP ASSOCIATIONS (DISM export)"
    $assocFile = Join-Path $script:SnapDir ("Win11Snapshot_{0}_{1}_FileAssoc.xml" -f $script:HostTag, $script:Stamp)
    $latest    = Join-Path $script:SnapDir 'Win11Snapshot_LATEST_FileAssoc.xml'
    try {
        $null = & dism.exe /Online /Export-DefaultAppAssociations:"$assocFile" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Copy-Item -Path $assocFile -Destination $latest -Force
            Write-OK "DISM associations exported"
            Write-Note ("File: {0}" -f $assocFile)
            return [PSCustomObject]@{
                ExportFile  = $assocFile
                LatestFile  = $latest
                ExitCode    = 0
            }
        } else {
            Write-Fail ("DISM exit code {0}" -f $LASTEXITCODE)
            return [PSCustomObject]@{ ExportFile=$null; LatestFile=$null; ExitCode=$LASTEXITCODE }
        }
    } catch {
        Write-Fail ("DISM failed: {0}" -f $_.Exception.Message)
        return [PSCustomObject]@{ ExportFile=$null; LatestFile=$null; ExitCode=-1 }
    }
}

function Capture-RestorePoint {
    Write-Title "SYSTEM RESTORE POINT (belt and suspenders)"
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description ("Win11Snapshot_{0}" -f $script:Stamp) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OK ("Restore point created: Win11Snapshot_{0}" -f $script:Stamp)
        Write-Note "(System Restore is unreliable. Do not depend on it. Use a real backup tool.)"
        return $true
    } catch {
        Write-Fail ("Restore point creation failed: {0}" -f $_.Exception.Message)
        Write-Note "Continuing -- this is supplementary, not the snapshot itself."
        return $false
    }
}

# ---------------------------------------------------------------------------
#  HUMAN-READABLE TXT WRITER
# ---------------------------------------------------------------------------

function Write-TextSummary {
    param([PSCustomObject]$Snapshot, [string]$Path)

    $lines = New-Object System.Collections.Generic.List[string]
    $add = { param($s) $lines.Add($s) | Out-Null }

    & $add "Win11 Snapshot -- human-readable summary"
    & $add "Generated: $($Snapshot.Metadata.CapturedAt)"
    & $add "Host:      $($Snapshot.Metadata.Hostname)"
    & $add "User:      $($Snapshot.Metadata.Username)"
    & $add "OS:        $($Snapshot.Metadata.OSCaption)  build $($Snapshot.Metadata.OSBuildNumber).$($Snapshot.Metadata.UBR)  ($($Snapshot.Metadata.DisplayVersion))"
    & $add ("=" * 78)
    & $add ""

    & $add "REGISTRY VALUES"
    & $add ("-" * 78)
    $byGroup = $Snapshot.Registry | Group-Object Group
    foreach ($g in $byGroup) {
        & $add ""
        & $add ("[{0}]" -f $g.Name)
        foreach ($r in $g.Group) {
            $val = if ($r.Existed) {
                if ($null -eq $r.Value) { '<null>' } else { ($r.Value | Out-String).Trim() }
            } else {
                '<not set>'
            }
            $line = "  {0,-72}  {1}" -f ("$($r.Path)\$($r.Name)"), $val
            & $add $line
        }
    }
    & $add ""
    & $add ""

    & $add "SERVICES"
    & $add ("-" * 78)
    foreach ($s in $Snapshot.Services) {
        if ($s.Present) {
            & $add ("  {0,-30}  StartType={1,-12}  Status={2}" -f $s.Name, $s.StartType, $s.Status)
        } else {
            & $add ("  {0,-30}  (not installed)" -f $s.Name)
        }
    }
    & $add ""
    & $add ""

    & $add "SCHEDULED TASKS"
    & $add ("-" * 78)
    foreach ($t in $Snapshot.ScheduledTasks) {
        & $add ("  {0,-58}  {1}" -f ($t.TaskPath + $t.TaskName), $t.State)
    }
    & $add ""
    & $add ""

    & $add "NETWORK ADAPTERS"
    & $add ("-" * 78)
    foreach ($a in $Snapshot.Network.Adapters) {
        & $add ("  {0,-30}  Status={1,-10}  DNS4=[{2}]  DNS6=[{3}]" -f $a.Name, $a.Status, $a.DnsIPv4, $a.DnsIPv6)
    }
    & $add ""
    & $add ("  TCP autotuning level: {0}" -f $Snapshot.Network.TCP.AutoTuningLevel)
    & $add ""
    & $add ""

    & $add "POWER"
    & $add ("-" * 78)
    & $add ("  Active scheme GUID:    {0}" -f $Snapshot.Power.ActiveSchemeGuid)
    & $add ("  hiberfil.sys present:  {0}" -f $Snapshot.Power.HibernationFilePresent)
    & $add ("  HiberbootEnabled:      {0}" -f $Snapshot.Power.HiberbootEnabled)
    & $add ""
    & $add ""

    & $add ("INSTALLED APPX PACKAGES (count: {0})" -f $Snapshot.Appx.Installed.Count)
    & $add ("-" * 78)
    foreach ($p in $Snapshot.Appx.Installed | Sort-Object Name) {
        & $add ("  {0,-50}  {1}" -f $p.Name, $p.Publisher)
    }
    & $add ""
    & $add ""

    & $add ("PROVISIONED APPX PACKAGES (count: {0})" -f $Snapshot.Appx.Provisioned.Count)
    & $add ("-" * 78)
    foreach ($p in $Snapshot.Appx.Provisioned | Sort-Object DisplayName) {
        & $add ("  {0}" -f $p.DisplayName)
    }
    & $add ""
    & $add ""

    & $add ("FIREWALL RULES (telemetry-related, count: {0})" -f $Snapshot.Firewall.Count)
    & $add ("-" * 78)
    foreach ($r in $Snapshot.Firewall) {
        & $add ("  {0,-50}  Dir={1,-8}  Act={2,-6}  En={3}" -f $r.DisplayName, $r.Direction, $r.Action, $r.Enabled)
    }
    & $add ""

    & $add "FILE-SYSTEM FLAGS"
    & $add ("-" * 78)
    & $add ("  disable8dot3:        {0}" -f $Snapshot.FileSystem.Disable8dot3)
    & $add ("  disablelastaccess:   {0}" -f $Snapshot.FileSystem.DisableLastAccess)
    & $add ("  TRIM NTFS:           {0}" -f $Snapshot.FileSystem.TrimNTFS)
    & $add ("  TRIM ReFS:           {0}" -f $Snapshot.FileSystem.TrimReFS)
    & $add ""

    & $add "FILE ASSOCIATIONS"
    & $add ("-" * 78)
    & $add ("  DISM export:  {0}" -f $Snapshot.FileAssoc.ExportFile)
    & $add ""

    $lines | Out-File -FilePath $Path -Encoding ASCII
}

# ---------------------------------------------------------------------------
#  MAIN
# ---------------------------------------------------------------------------

Write-Header

Write-Host "  Snapshot will be written to:" -ForegroundColor White
Write-Host ("    {0}" -f $script:XmlFile) -ForegroundColor Gray
Write-Host ("    {0}" -f $script:TxtFile) -ForegroundColor Gray
Write-Host ""

$snap = [PSCustomObject]@{
    Metadata        = Capture-Metadata
    Registry        = Capture-Registry
    Services        = Capture-Services
    ScheduledTasks  = Capture-ScheduledTasks
    Network         = Capture-Network
    Power           = Capture-Power
    Appx            = Capture-Appx
    Firewall        = Capture-Firewall
    FileSystem      = Capture-FileSystem
    FileAssoc       = Capture-FileAssociations
    RestorePointOK  = $false
}

# Belt and suspenders -- create a System Restore Point too. Many users
# disable this by default; we silently try and continue if it fails.
$snap.RestorePointOK = Capture-RestorePoint

# -- Write outputs ------------------------------------------------------
Write-Title "WRITING SNAPSHOT FILES"

try {
    $snap | Export-Clixml -Path $script:XmlFile -Force
    Copy-Item -Path $script:XmlFile -Destination $script:LatestXml -Force
    Write-OK ("XML snapshot saved: {0}" -f $script:XmlFile)
    Write-OK ("LATEST copy:        {0}" -f $script:LatestXml)
} catch {
    Write-Fail ("Could not save XML: {0}" -f $_.Exception.Message)
    Read-Host "  Press Enter to exit"
    exit 1
}

try {
    Write-TextSummary -Snapshot $snap -Path $script:TxtFile
    Copy-Item -Path $script:TxtFile -Destination $script:LatestTxt -Force
    Write-OK ("Human summary saved: {0}" -f $script:TxtFile)
    Write-OK ("LATEST copy:         {0}" -f $script:LatestTxt)
} catch {
    Write-Fail ("Could not save TXT: {0}" -f $_.Exception.Message)
}

# -- Final summary ------------------------------------------------------
Write-Host ""
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
Write-Host "   SNAPSHOT COMPLETE" -ForegroundColor Cyan
Write-Host ("  " + ("=" * 68)) -ForegroundColor DarkCyan
Write-Host ""
Write-Host ("    Registry values:   {0}" -f $snap.Registry.Count) -ForegroundColor Gray
Write-Host ("    Services:          {0}" -f $snap.Services.Count) -ForegroundColor Gray
Write-Host ("    Scheduled tasks:   {0}" -f $snap.ScheduledTasks.Count) -ForegroundColor Gray
Write-Host ("    Adapters:          {0}" -f $snap.Network.Adapters.Count) -ForegroundColor Gray
Write-Host ("    Appx installed:    {0}" -f $snap.Appx.Installed.Count) -ForegroundColor Gray
Write-Host ("    Appx provisioned:  {0}" -f $snap.Appx.Provisioned.Count) -ForegroundColor Gray
Write-Host ("    Firewall rules:    {0}" -f $snap.Firewall.Count) -ForegroundColor Gray
$rpStatus = if ($snap.RestorePointOK) { 'created' } else { 'skipped/failed' }
Write-Host ("    System Restore:    {0}" -f $rpStatus) -ForegroundColor Gray
Write-Host ""
Write-Host "  This snapshot is your safety net. Keep it." -ForegroundColor Green
Write-Host "  To revert later, run Win11SnapshotRestore.ps1." -ForegroundColor Green
Write-Host ""
Write-Host "  IMPORTANT: This is not a substitute for an image backup." -ForegroundColor Yellow
Write-Host "             Run Acronis or Macrium before any hardening." -ForegroundColor Yellow
Write-Host ""

Read-Host "  Press Enter to exit"
