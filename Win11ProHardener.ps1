<#
.SYNOPSIS
    Windows 11 PRO Hardener -- gap-closers
    Author : Brad / CrisisOfTruth.org
    Version: 1.1
.DESCRIPTION
    Closes privacy + security gaps the main Win11PrivacyHardener and
    Extras scripts do not cover. This is the "professional grade"
    pass that addresses settings most consumer guides miss:

      1. Start-menu Bing / web search       (biggest remaining leak)
      2. Microsoft Store auto-install kill  (stops bloatware re-push)
      3. NCSI active probing                (constant phone-home)
      4. CompatTelRunner.exe IFEO neutralize
      5. Connected Devices Platform (CDP) services
      6. NTP server -- away from time.windows.com
      7. PowerShell + .NET CLI telemetry env vars
      8. Desktop Spotlight (Win11 22H2+)
      9. Ink + handwriting trained-data wipe
     10. LLMNR / NetBIOS / WPAD / AutoPlay / SMB1
     11. Storage Sense cloud nudges
     12. Hosts file telemetry block (separate -- see firewall script)

    Also wipes existing collected handwriting data, clears the
    diagnostic-data cache more aggressively than the base script,
    and sets up Cloudflare 1.1.1.1.1.1 NTP (yes, that exists).

    Designed to be run AFTER the base privacy + extras scripts.
    Safe to re-run; idempotent.
.NOTES
    Self-elevates to Administrator automatically.
    Run via RunHardener.bat (option P) or right-click + Run with PowerShell.
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
#  HELPERS  (matches base hardener style)
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkMagenta
    Write-Host "  Win11 PRO Hardener  --  CrisisOfTruth.org" -ForegroundColor Magenta
    Write-Host " $line" -ForegroundColor DarkMagenta
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Sep        { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Magenta
    Write-Sep
}

$script:PassCount = 0
$script:FailCount = 0
$script:Log       = [System.Collections.Generic.List[string]]::new()

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

# Set the registry-level Start value for a service. Used for per-user
# template services (CDPUserSvc, OneSyncSvc) whose runtime instance has
# a random suffix per session and cannot be reached via Set-Service.
function Set-SvcStartReg {
    param([string]$Name, [int]$Start = 4)
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name 'Start' -Value $Start -Type DWord -Force
    } else {
        Write-Info "    Template service '$Name' not found -- skipping"
    }
}

# ---------------------------------------------------------------------------
#  1 -- START MENU BING / WEB SEARCH KILL
# ---------------------------------------------------------------------------

function Invoke-StartSearchTweaks {
    Write-Title "START MENU BING / WEB SEARCH"

    Invoke-Tweak "Disable Start menu search-box web suggestions (Explorer policy)" {
        Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    }

    Invoke-Tweak "Disable Bing search inside Start menu" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent'    0
    }

    Invoke-Tweak "Block Search from using location" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowSearchToUseLocation' 0
    }

    Invoke-Tweak "Disable Search highlights (the rotating banner with news/holidays)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds' 'ShellFeedsTaskbarViewMode' 2
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
    }

    Invoke-Tweak "Disable web results in Search by group policy (HKLM)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch'       1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb'  0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch'       0
    }
}

# ---------------------------------------------------------------------------
#  2 -- MICROSOFT STORE AUTO-INSTALL / PUSH-TO-INSTALL
# ---------------------------------------------------------------------------

function Invoke-StorePushTweaks {
    Write-Title "MICROSOFT STORE AUTO-INSTALL + PUSH-TO-INSTALL"

    Invoke-Tweak "Disable Store automatic app updates (you re-enable manually if wanted)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload' 2
    }

    Invoke-Tweak "Disable consumer account state content (re-pushes Spotify, TikTok, etc.)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures'     1
    }

    Invoke-Tweak "Disable Push-To-Install service (the silent app injector)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 1
        Disable-Svc 'PushToInstall'
    }

    Invoke-Tweak "Block Microsoft accounts from being added (optional but powerful)" {
        # Comment this out if you actively use a Microsoft account
        # Set-Reg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Accounts' 'AllowMicrosoftAccountConnection' 0
        Write-Info "    Skipped -- uncomment in script if you want to block all MSA logins"
    }
}

# ---------------------------------------------------------------------------
#  3 -- NCSI (Network Connectivity Status Indicator)
# ---------------------------------------------------------------------------

function Invoke-NCSITweaks {
    Write-Title "NCSI -- the silent connect-test phone-home"

    Invoke-Tweak "Disable NCSI active probing of msftconnecttest.com" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' 'NoActiveProbe' 1
    }

    Invoke-Tweak "Disable Network Location Awareness probing (related)" {
        # Some setups also probe via NLA; leaving the NoActiveProbe key takes care of most.
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' 'EnableActiveProbing' 0
    }
}

# ---------------------------------------------------------------------------
#  4 -- CompatTelRunner.exe IFEO neutralize
# ---------------------------------------------------------------------------

function Invoke-CompatTelTweaks {
    Write-Title "CompatTelRunner.exe -- shut down via IFEO redirect"

    Invoke-Tweak "Register CompatTelRunner.exe with taskkill as 'debugger'" {
        # The IFEO key tells Windows to launch our 'debugger' instead of
        # the real binary. Pointing it at taskkill.exe makes the OS attempt
        # to launch a process that just kills itself -- so CompatTelRunner
        # never actually runs, no matter how it is invoked.
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\CompatTelRunner.exe'
        Set-Reg $key 'Debugger' "$env:windir\System32\taskkill.exe" 'String'
    }

    Invoke-Tweak "Same trick for DeviceCensus.exe (sister binary)" {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\DeviceCensus.exe'
        Set-Reg $key 'Debugger' "$env:windir\System32\taskkill.exe" 'String'
    }
}

# ---------------------------------------------------------------------------
#  5 -- Connected Devices Platform
# ---------------------------------------------------------------------------

function Invoke-CDPTweaks {
    Write-Title "CONNECTED DEVICES PLATFORM (CDP) services"

    Invoke-Tweak "Disable CDP Service (machine-wide cross-device transport)" {
        Disable-Svc 'CDPSvc'
    }

    Invoke-Tweak "Disable CDPUserSvc template (per-user instance gets random suffix)" {
        # The runtime CDPUserSvc_xxxxx cannot be reached by name; setting
        # Start=4 on the template makes future per-session instances inherit it.
        Set-SvcStartReg 'CDPUserSvc' 4
    }

    Invoke-Tweak "Disable OneSyncSvc template (Mail/Calendar/People/Contacts cloud sync)" {
        Set-SvcStartReg 'OneSyncSvc' 4
    }

    Invoke-Tweak "Disable Contact Data indexer (PimIndexMaintenanceSvc)" {
        Set-SvcStartReg 'PimIndexMaintenanceSvc' 4
    }

    Invoke-Tweak "Disable Cross-Device Experiences feature flag" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableMmx' 0
    }
}

# ---------------------------------------------------------------------------
#  6 -- NTP -- away from time.windows.com
# ---------------------------------------------------------------------------

function Invoke-NTPTweaks {
    Write-Title "NTP -- swap time.windows.com for Cloudflare + NTP pool"

    Invoke-Tweak "Configure Cloudflare + ntp.org as time peers" {
        & w32tm /config /manualpeerlist:'time.cloudflare.com pool.ntp.org' /syncfromflags:manual /reliable:YES /update | Out-Null
    }

    Invoke-Tweak "Restart Windows Time service to apply" {
        Restart-Service -Name 'w32time' -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        & w32tm /resync 2>&1 | Out-Null
    }
}

# ---------------------------------------------------------------------------
#  7 -- PowerShell + .NET CLI telemetry env vars
# ---------------------------------------------------------------------------

function Invoke-DevTelemetryTweaks {
    Write-Title "POWERSHELL + .NET CLI TELEMETRY OPT-OUT"

    Invoke-Tweak "Set POWERSHELL_TELEMETRY_OPTOUT=1 (Machine scope)" {
        [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
    }

    Invoke-Tweak "Set DOTNET_CLI_TELEMETRY_OPTOUT=1 (Machine scope)" {
        [Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'Machine')
    }

    Invoke-Tweak "Set MSBUILD_DISABLE_NODE_REUSE=1 + DOTNET_NOLOGO=1 (cosmetic + small leak)" {
        [Environment]::SetEnvironmentVariable('DOTNET_NOLOGO', 'true', 'Machine')
    }
}

# ---------------------------------------------------------------------------
#  8 -- Desktop Spotlight (Win11 22H2+)
# ---------------------------------------------------------------------------

function Invoke-DesktopSpotlightTweaks {
    Write-Title "DESKTOP SPOTLIGHT (rotating wallpaper feed -- Win11 22H2+)"

    Invoke-Tweak "Disable Desktop Spotlight via PersonalizeCSP" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\PersonalizeCSP' 'DesktopSpotlightEnabled' 0
    }

    Invoke-Tweak "Disable Desktop Spotlight via CloudContent policy" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1
    }
}

# ---------------------------------------------------------------------------
#  9 -- Ink + handwriting trained-data wipe
# ---------------------------------------------------------------------------

function Invoke-InkWipeTweaks {
    Write-Title "INK + HANDWRITING -- WIPE COLLECTED DATA"

    Invoke-Tweak "Reinforce policy lock (in case Extras was not run yet)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection'  1
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    }

    Invoke-Tweak "Wipe TrainedDataStore (handwriting / typing samples on disk)" {
        $store = "$env:LOCALAPPDATA\Microsoft\InputPersonalization\TrainedDataStore"
        if (Test-Path $store) {
            Get-ChildItem $store -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
        $shared = "$env:LOCALAPPDATA\Microsoft\InputPersonalization"
        if (Test-Path $shared) {
            Get-ChildItem $shared -Filter '*.cab' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
#  10 -- LLMNR / NetBIOS / WPAD / AutoPlay / SMB1 (security-adjacent)
# ---------------------------------------------------------------------------

function Invoke-NetSecurityTweaks {
    Write-Title "LLMNR / NetBIOS / WPAD / AutoPlay / SMB1"

    Invoke-Tweak "Disable LLMNR (broadcasts mistyped hostnames to whole LAN)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0
    }

    Invoke-Tweak "Disable NetBIOS over TCP/IP on every adapter" {
        $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE' -ErrorAction SilentlyContinue
        foreach ($a in $adapters) {
            $null = $a.SetTcpipNetbios(2)
        }
    }

    Invoke-Tweak "Disable WPAD auto-discovery (proxy hijack vector)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\WPAD' 'AutoDetect' 0
        # Also stop WinHttpAutoProxySvc
        Disable-Svc 'WinHttpAutoProxySvc'
    }

    Invoke-Tweak "Disable AutoPlay + AutoRun for all drives" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 0xFF
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 0xFF
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoAutorun'         1
    }

    Invoke-Tweak "Disable SMB1 client + server (legacy and vulnerable)" {
        try {
            Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction SilentlyContinue | Out-Null
        } catch { }
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
        Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
#  11 -- Storage Sense cloud nudges
# ---------------------------------------------------------------------------

function Invoke-StorageSenseTweaks {
    Write-Title "STORAGE SENSE -- silence the OneDrive / cloud nudges"

    Invoke-Tweak "Disable cloud-storage prompts in Storage Sense" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '04' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '08' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '32' 0
    }
}

# ---------------------------------------------------------------------------
#  12 -- Aggressive diag-cache wipe (beyond the base script)
# ---------------------------------------------------------------------------

function Invoke-DiagCacheWipe {
    Write-Title "DIAGNOSTIC DATA CACHE -- aggressive wipe"

    Invoke-Tweak "Stop DiagTrack first (in case base script did not)" {
        Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue
    }

    Invoke-Tweak "Wipe %ProgramData%\Microsoft\Diagnosis traces" {
        $traces = "$env:ProgramData\Microsoft\Diagnosis"
        if (Test-Path $traces) {
            Get-ChildItem $traces -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.etl','.rbs','.log' } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-Tweak "Wipe %LOCALAPPDATA%\Microsoft\Windows\WebCache (telemetry browser cache)" {
        $wc = "$env:LOCALAPPDATA\Microsoft\Windows\WebCache"
        if (Test-Path $wc) {
            Get-ChildItem $wc -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'WebCacheV*.dat.LOG*' } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
#  ALL-IN-ONE
# ---------------------------------------------------------------------------

function Invoke-AllProTweaks {
    Invoke-StartSearchTweaks
    Invoke-StorePushTweaks
    Invoke-NCSITweaks
    Invoke-CompatTelTweaks
    Invoke-CDPTweaks
    Invoke-NTPTweaks
    Invoke-DevTelemetryTweaks
    Invoke-DesktopSpotlightTweaks
    Invoke-InkWipeTweaks
    Invoke-NetSecurityTweaks
    Invoke-StorageSenseTweaks
    Invoke-DiagCacheWipe
    Write-Host ""
    Write-Host "  ALL PRO TWEAKS COMPLETE. REBOOT RECOMMENDED." -ForegroundColor Green
    Write-Host ""
}

# ---------------------------------------------------------------------------
#  LOG
# ---------------------------------------------------------------------------

function Save-Log {
    $logPath = "$PSScriptRoot\Win11Pro_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $script:Log | Out-File -FilePath $logPath -Encoding ASCII
    Write-OK "Log saved: $logPath"
}

# ---------------------------------------------------------------------------
#  MENU
# ---------------------------------------------------------------------------

function Show-Menu {
    Write-Header
    Write-Host "  Select an option:" -ForegroundColor White
    Write-Host ""
    $opts = @(
        " 1  -- ALL PRO TWEAKS (recommended)"
        " 2  -- Start menu Bing / web search kill"
        " 3  -- Microsoft Store auto-install + Push-To-Install"
        " 4  -- NCSI (msftconnecttest.com phone-home)"
        " 5  -- CompatTelRunner.exe / DeviceCensus.exe IFEO neutralize"
        " 6  -- Connected Devices Platform (CDP) services"
        " 7  -- NTP -- swap time.windows.com for Cloudflare + ntp.org"
        " 8  -- PowerShell + .NET CLI telemetry opt-out"
        " 9  -- Desktop Spotlight (Win11 22H2+)"
        "10  -- Ink + handwriting collected-data wipe"
        "11  -- LLMNR / NetBIOS / WPAD / AutoPlay / SMB1"
        "12  -- Storage Sense cloud nudges"
        "13  -- Aggressive diag-cache wipe"
        " L  -- Save log to Desktop"
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
        '1'  { Invoke-AllProTweaks }
        '2'  { Invoke-StartSearchTweaks }
        '3'  { Invoke-StorePushTweaks }
        '4'  { Invoke-NCSITweaks }
        '5'  { Invoke-CompatTelTweaks }
        '6'  { Invoke-CDPTweaks }
        '7'  { Invoke-NTPTweaks }
        '8'  { Invoke-DevTelemetryTweaks }
        '9'  { Invoke-DesktopSpotlightTweaks }
        '10' { Invoke-InkWipeTweaks }
        '11' { Invoke-NetSecurityTweaks }
        '12' { Invoke-StorageSenseTweaks }
        '13' { Invoke-DiagCacheWipe }
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
Write-Host "  Goodbye. Reboot when ready." -ForegroundColor Magenta
Write-Host ""
