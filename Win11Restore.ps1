<#
.SYNOPSIS
    Windows 10/11 Restore Helper -- Selective re-enable for hardened features
    Author : Brad / CrisisOfTruth.org
    Version: 1.6
.DESCRIPTION
    Companion script to the Win10/11 Hardener Suite. Selectively
    re-enables features that the Privacy / Performance / Extras / Pro
    Hardeners turn off:
        - Hibernate (powercfg -h on)
        - Location Services (policy + lfsvc)
        - Fast Startup (optional)
        - OneDrive (reverses both base + Extras nuke)
        - Remote Desktop (policy + firewall)
        - Cortana / Start menu web search
        - Settings Sync to Microsoft account
        - Cross-device cloud clipboard
        - Find My Device
        - Edge Sign-in and Sync (new in 1.3)
        - Background Apps for UWP notifications (new in 1.3)
        - Camera + Microphone policy block, with automatic gpupdate
          so the change applies without a reboot (new in 1.5);
          also re-allows the machine-wide and desktop-app switches
          that browsers need for telehealth / video calls (1.6)
        - Restore ALL of the above in one pass
    All actions in this script work identically on Windows 10
    and Windows 11. Self-elevates to Administrator automatically.
.NOTES
    Run via RunHardener.bat (option R) or right-click and Run with PowerShell.
    
    This script does NOT re-enable telemetry, advertising ID, activity
    history, or any of the privacy blocks. Use Win11SnapshotRestore.ps1
    (launcher option U) if you need a full back-to-original revert.
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
#  OS DETECTION  (informational only -- everything here works on both)
# ---------------------------------------------------------------------------
$script:OSBuild = 0
try {
    $script:OSBuild = [int]((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuildNumber)
} catch { $script:OSBuild = 0 }
$script:IsWin11 = $script:OSBuild -ge 22000
$script:OSLabel = if ($script:IsWin11) { "Windows 11 (build $script:OSBuild)" } else { "Windows 10 (build $script:OSBuild)" }

# ---------------------------------------------------------------------------
#  HELPERS  (same style as the hardener scripts)
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win10/11 Restore Helper  --  CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host "  Detected: $script:OSLabel" -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Note ($msg) { Write-Host "  [NOTE] $msg" -ForegroundColor DarkYellow }
function Write-Sep        { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }

function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Cyan
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

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return }
    $before = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $before) { return }  # already gone -- success
    Remove-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    # Verify the remove actually took effect (silent-fail-without-admin guard)
    $after = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -ne $after) {
        throw "Remove-RegValue VERIFY FAILED: $Path\$Name still=$after after remove (HKLM write blocked? need admin?)"
    }
}

# ---------------------------------------------------------------------------
#  1 -- HIBERNATE
# ---------------------------------------------------------------------------

function Invoke-HibernateRestore {
    Write-Title "RESTORE HIBERNATE"

    Invoke-Tweak "Re-enable Hibernate (recreates hiberfil.sys)" {
        powercfg -h on | Out-Null
    }

    Invoke-Tweak "Add Hibernate to the Start / Power menu" {
        # Show hibernate option in the shutdown menu
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'ShowHibernateOption' 1
        # Also flip the FlyoutMenuSettings key (Win10 and Win11 both use this)
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings' 'ShowHibernateOption' 1
    }

    Write-Host ""
    Write-Host "  Hibernate is now ON." -ForegroundColor Green
    Write-Host "  If you do not see it in the Start > Power menu yet:" -ForegroundColor Gray
    Write-Host "    Control Panel > Power Options > Choose what the power buttons do" -ForegroundColor Gray
    Write-Host "    > Change settings that are currently unavailable > tick Hibernate." -ForegroundColor Gray
    Write-Host ""
    Write-Note "The Performance Hardener also disabled Fast Startup."
    Write-Note "Hibernate works fine without it. Only re-enable Fast"
    Write-Note "Startup (option 3) if you specifically want it back."
}

# ---------------------------------------------------------------------------
#  2 -- LOCATION
# ---------------------------------------------------------------------------

function Invoke-LocationRestore {
    Write-Title "RESTORE LOCATION SERVICES"

    Invoke-Tweak "Remove Group Policy block on Location" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation'
    }

    Invoke-Tweak "Re-allow Location at the consent layer" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Permissions\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' 1
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Allow' 'String'
    }

    Invoke-Tweak "Set Location service (lfsvc) status flag back to ON" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' 'Status' 1
    }

    Invoke-Tweak "Set Location service (lfsvc) startup to Automatic and start it" {
        Set-Service -Name lfsvc -StartupType Automatic -ErrorAction Stop
        Start-Service -Name lfsvc -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "  Location is now permitted." -ForegroundColor Green
    Write-Host "  Final toggle (per-user / per-app):" -ForegroundColor Gray
    Write-Host "    Settings > Privacy and security > Location" -ForegroundColor Gray
    Write-Host "    Turn on 'Location services' and grant the apps you want." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
#  3 -- (OPTIONAL) FAST STARTUP -- the hardener killed it on purpose
# ---------------------------------------------------------------------------

function Invoke-FastStartupRestore {
    Write-Title "RESTORE FAST STARTUP (optional)"

    Write-Note "Fast Startup was disabled by the Performance Hardener because"
    Write-Note "it can cause driver and Windows Update issues after shutdown."
    Write-Note "Hibernate works just fine without it."
    Write-Host ""

    Invoke-Tweak "Re-enable Fast Startup (HiberbootEnabled = 1)" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1
    }
}

# ---------------------------------------------------------------------------
#  4 -- ONEDRIVE  (handles base disable + Extras full-uninstall)
# ---------------------------------------------------------------------------

function Find-OneDriveExe {
    # Locations where OneDrive.exe might exist after install
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:PROGRAMFILES\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-OneDriveSetup {
    # Locations where the bundled OneDriveSetup.exe might exist
    $candidates = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\System32\OneDriveSetup.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Invoke-OneDriveRestore {
    Write-Title "RESTORE ONEDRIVE"

    # Step 1: always remove the policy keys, regardless of install state
    Invoke-Tweak "Remove OneDrive policy blocks (HKLM Policies\OneDrive)" {
        $polPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
        Remove-RegValue $polPath 'DisableFileSyncNGSC'
        Remove-RegValue $polPath 'DisableFileSync'
        Remove-RegValue $polPath 'DisableLibrariesDefaultSaveToOneDrive'
        Remove-RegValue $polPath 'PreventNetworkTrafficPreUserSignIn'
    }

    # Step 2: figure out current install state
    $existingExe = Find-OneDriveExe
    $setupExe    = Find-OneDriveSetup

    if ($existingExe) {
        Write-Host ""
        Write-Host "  OneDrive.exe found at:" -ForegroundColor Gray
        Write-Host "    $existingExe" -ForegroundColor Gray

        Invoke-Tweak "Restore OneDrive entry to startup (HKCU Run key)" {
            Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'OneDrive' "`"$existingExe`" /background" 'String'
        }

        Invoke-Tweak "Re-enable OneDrive scheduled tasks" {
            Get-ScheduledTask -TaskName 'OneDrive*' -ErrorAction SilentlyContinue |
                Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }

        Invoke-Tweak "Launch OneDrive now" {
            Start-Process -FilePath $existingExe -ArgumentList '/background' -ErrorAction Stop
        }
    }
    elseif ($setupExe) {
        Write-Host ""
        Write-Host "  OneDrive.exe not found, but OneDriveSetup.exe is available:" -ForegroundColor Gray
        Write-Host "    $setupExe" -ForegroundColor Gray

        Invoke-Tweak "Run OneDriveSetup.exe to reinstall OneDrive" {
            Start-Process -FilePath $setupExe -ArgumentList '/silent' -Wait -ErrorAction Stop
        }

        # After reinstall, look again
        Start-Sleep -Seconds 3
        $afterSetup = Find-OneDriveExe
        if ($afterSetup) {
            Invoke-Tweak "Restore OneDrive entry to startup (HKCU Run key)" {
                Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'OneDrive' "`"$afterSetup`" /background" 'String'
            }
            Invoke-Tweak "Launch OneDrive now" {
                Start-Process -FilePath $afterSetup -ArgumentList '/background' -ErrorAction Stop
            }
        } else {
            Write-Fail "OneDriveSetup ran but OneDrive.exe still not found. Manual install required."
        }
    }
    else {
        Write-Note "OneDrive is fully uninstalled and OneDriveSetup.exe is not"
        Write-Note "present on this machine. The Extras hardener removed both."
        Write-Note ""
        Write-Note "To finish restoring OneDrive:"
        Write-Note "  1. Download the latest installer from:"
        Write-Note "     https://www.microsoft.com/en-us/microsoft-365/onedrive/download"
        Write-Note "  2. Run the installer."
        Write-Note "  3. Sign in with your Microsoft account."
        Write-Note ""
        Write-Note "The policy blocks above have already been removed, so the"
        Write-Note "fresh install will be allowed to sync once you sign in."
    }

    Write-Host ""
    Write-Host "  OneDrive policy locks are cleared." -ForegroundColor Green
    Write-Host "  After install + sign-in, files placed in your OneDrive" -ForegroundColor Gray
    Write-Host "  folder will sync to the cloud as normal." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
#  5 -- REMOTE DESKTOP
# ---------------------------------------------------------------------------

function Invoke-RemoteDesktopRestore {
    Write-Title "RESTORE REMOTE DESKTOP"

    Invoke-Tweak "Allow Remote Desktop connections (fDenyTSConnections = 0)" {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 0
    }

    Invoke-Tweak "Enable Windows Firewall rules for Remote Desktop" {
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "  Remote Desktop is now allowed." -ForegroundColor Green
    Write-Note "You must ALSO add at least one user to the Remote Desktop"
    Write-Note "Users group, or be an Administrator, to actually connect."
    Write-Note "Settings > System > Remote Desktop -- toggle ON and"
    Write-Note "select users from there."
}

# ---------------------------------------------------------------------------
#  6 -- CORTANA + START MENU WEB SEARCH
# ---------------------------------------------------------------------------

function Invoke-CortanaRestore {
    Write-Title "RESTORE CORTANA AND START MENU WEB SEARCH"

    Invoke-Tweak "Remove Cortana / Web Search policy blocks (HKLM)" {
        $polPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        Remove-RegValue $polPath 'AllowCortana'
        Remove-RegValue $polPath 'AllowCortanaAboveLock'
        Remove-RegValue $polPath 'DisableWebSearch'
        Remove-RegValue $polPath 'ConnectedSearchUseWeb'
        Remove-RegValue $polPath 'AllowSearchToUseLocation'
    }

    Invoke-Tweak "Re-enable Bing / Cortana suggestions in Start (HKCU)" {
        Remove-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions'
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 1
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent'    1
    }

    Invoke-Tweak "Re-enable Cortana scheduled tasks" {
        Get-ScheduledTask -TaskPath '\Microsoft\Windows\Cortana\' -ErrorAction SilentlyContinue |
            Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Host ""
    Write-Host "  Cortana and Start menu web search are unblocked." -ForegroundColor Green
    Write-Note "You may need to sign out and back in, or reboot, before"
    Write-Note "Start menu typing shows Bing results again."
}

# ---------------------------------------------------------------------------
#  7 -- SETTINGS SYNC TO MICROSOFT ACCOUNT
# ---------------------------------------------------------------------------

function Invoke-SettingsSyncRestore {
    Write-Title "RESTORE SETTINGS SYNC (Microsoft account)"

    Invoke-Tweak "Remove Settings Sync policy blocks" {
        $polPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
        Remove-RegValue $polPath 'DisableSettingSync'
        Remove-RegValue $polPath 'DisableSettingSyncUserOverride'
        Remove-RegValue $polPath 'DisableApplicationSettingSync'
        Remove-RegValue $polPath 'DisableCredentialsSettingSync'
    }

    Write-Host ""
    Write-Host "  Settings Sync policy locks are cleared." -ForegroundColor Green
    Write-Note "Final per-user toggle is at:"
    Write-Note "  Settings > Accounts > Windows backup"
    Write-Note "Turn on 'Remember my preferences' and 'Remember my apps'."
}

# ---------------------------------------------------------------------------
#  8 -- CROSS-DEVICE CLIPBOARD
# ---------------------------------------------------------------------------

function Invoke-ClipboardRestore {
    Write-Title "RESTORE CROSS-DEVICE CLIPBOARD"

    Invoke-Tweak "Remove cross-device clipboard policy block" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard'
    }

    Write-Host ""
    Write-Host "  Cross-device clipboard policy lock is cleared." -ForegroundColor Green
    Write-Note "Final per-user toggle is at:"
    Write-Note "  Settings > System > Clipboard"
    Write-Note "Turn on 'Clipboard history' and 'Sync across devices'."
}

# ---------------------------------------------------------------------------
#  9 -- FIND MY DEVICE
# ---------------------------------------------------------------------------

function Invoke-FindMyDeviceRestore {
    Write-Title "RESTORE FIND MY DEVICE"

    Invoke-Tweak "Remove Find My Device policy block" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice'
    }

    Write-Host ""
    Write-Host "  Find My Device policy lock is cleared." -ForegroundColor Green
    Write-Note "Final per-user toggle is at:"
    Write-Note "  Settings > Privacy and security > Find my device"
    Write-Note "Requires signing in with a Microsoft account."
}

# ---------------------------------------------------------------------------
#  10 -- EDGE SIGN-IN AND SYNC
# ---------------------------------------------------------------------------

function Invoke-EdgeSignInRestore {
    Write-Title "RESTORE EDGE SIGN-IN AND SYNC"

    Invoke-Tweak "Remove Edge BrowserSignin policy block" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BrowserSignin'
    }

    Invoke-Tweak "Remove Edge SyncDisabled policy block" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SyncDisabled'
    }

    Write-Host ""
    Write-Host "  Edge sign-in and sync are unblocked." -ForegroundColor Green
    Write-Note "Close Edge COMPLETELY (check Task Manager for any lingering"
    Write-Note "msedge.exe processes and end them) before reopening. The"
    Write-Note "sign-in option and sync toggles will then be enabled."
    Write-Note ""
    Write-Note "This restore does NOT re-enable Edge's own telemetry,"
    Write-Note "personalization reporting, shopping assistant, or credit"
    Write-Note "card autofill -- those stay disabled by the Extras hardener."
    Write-Note "Only sign-in and bookmark/password sync are affected."
}

# ---------------------------------------------------------------------------
#  11 -- BACKGROUND APPS (for Mail/Calendar/Outlook notifications)
# ---------------------------------------------------------------------------

function Invoke-BackgroundAppsRestore {
    Write-Title "RESTORE BACKGROUND APPS"

    Write-Note "Background app permission is required for:"
    Write-Note "  - Mail / Calendar / Outlook to receive new-message"
    Write-Note "    notifications when not in the foreground"
    Write-Note "  - Microsoft To Do reminders"
    Write-Note "  - Most UWP app live tile updates"
    Write-Note "  - Cortana scheduled reminders (if Cortana also restored)"
    Write-Host ""

    Invoke-Tweak "Remove machine-wide background apps policy block" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground'
    }

    Invoke-Tweak "Re-enable global per-user background apps switch" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
    }

    Write-Host ""
    Write-Host "  Background apps are re-allowed at the policy level." -ForegroundColor Green
    Write-Note "Final per-app toggles are at:"
    Write-Note "  Settings > Apps > Installed apps > [app] > Advanced options"
    Write-Note "    > Background apps permissions"
    Write-Note "Or globally at:"
    Write-Note "  Settings > Privacy and security > Background apps"
    Write-Note ""
    Write-Note "This does NOT re-enable Wi-Fi Sense or any of the other"
    Write-Note "items in the Extras hardener's BackgroundApps group."
}

# ---------------------------------------------------------------------------
#  12 -- CAMERA + MICROPHONE
# ---------------------------------------------------------------------------

function Invoke-CameraMicRestore {
    Write-Title "RESTORE CAMERA + MICROPHONE"

    Write-Note "The Privacy Hardener sets LetAppsAccessCamera and"
    Write-Note "LetAppsAccessMicrophone to 2 (Deny) at the Group Policy"
    Write-Note "level. This is a machine-wide block that overrides the"
    Write-Note "per-app toggle in Settings, which is why it can survive"
    Write-Note "even after you flip the Settings switch back on."
    Write-Host ""

    Invoke-Tweak "Remove Group Policy block on Camera" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessCamera'
    }

    Invoke-Tweak "Remove Group Policy block on Microphone" {
        Remove-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsAccessMicrophone'
    }

    Invoke-Tweak "Re-allow Microphone at the consent layer (current user)" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone' 'Value' 'Allow' 'String'
    }

    Invoke-Tweak "Re-allow Camera at the consent layer (current user)" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' 'Value' 'Allow' 'String'
    }

    Invoke-Tweak "Re-allow Camera + Microphone master switch (machine-wide)" {
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam' 'Value' 'Allow' 'String'
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone' 'Value' 'Allow' 'String'
    }

    Invoke-Tweak "Re-allow desktop apps (browsers, Zoom) to use Camera + Microphone" {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam\NonPackaged' 'Value' 'Allow' 'String'
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged' 'Value' 'Allow' 'String'
    }

    Invoke-Tweak "Force a policy refresh so apps see the change without a reboot" {
        $p = Start-Process -FilePath 'gpupdate.exe' -ArgumentList '/target:computer','/force' -Wait -WindowStyle Hidden -PassThru
        if ($p.ExitCode -ne 0) { throw "gpupdate exited with code $($p.ExitCode)" }
    }

    Write-Host ""
    Write-Host "  Camera and Microphone policy blocks are lifted." -ForegroundColor Green
    Write-Host "  Final per-app toggle is at:" -ForegroundColor Gray
    Write-Host "    Settings > Privacy and security > Microphone / Camera" -ForegroundColor Gray
    Write-Host "    Turn the global switch on, then allow the apps you want." -ForegroundColor Gray
    Write-Host ""
    Write-Note "A gpupdate /force was run automatically above. If an app"
    Write-Note "you already had open (browser tab, Zoom, Teams, Discord)"
    Write-Note "still shows no mic, close and reopen just that app first --"
    Write-Note "most apps only read the policy once at launch. A full"
    Write-Note "reboot is the fallback if reopening the app doesn't do it."
    Write-Host ""
    Write-Note "Still blocked? Check your antivirus. Bitdefender has its own"
    Write-Note "webcam block: Privacy > Video and Audio Protection. Make sure"
    Write-Note "your browser is not on its blocked list."
}

# ---------------------------------------------------------------------------
#  13 -- RUN ALL RESTORES IN THIS MENU
# ---------------------------------------------------------------------------

function Invoke-RestoreAll {
    Write-Title "RESTORE ALL USER-FACING FEATURES IN THIS MENU"

    Write-Note "This will run every restore in this menu (1, 2, 4-12)."
    Write-Note "Fast Startup (option 3) is intentionally NOT included --"
    Write-Note "it causes shutdown/update issues. Run option 3 separately"
    Write-Note "if you specifically need it."
    Write-Note ""
    Write-Note "This does NOT re-enable telemetry, advertising ID, activity"
    Write-Note "history, or any of the privacy blocks. For a full revert"
    Write-Note "back to original Windows defaults, use Snapshot Restore"
    Write-Note "(launcher option U) against a pre-hardening snapshot."
    Write-Host ""

    $confirm = Read-Host "  Type YES to proceed with the full restore"
    if ($confirm -ne 'YES') {
        Write-Host ""
        Write-Host "  Cancelled. No changes made." -ForegroundColor Yellow
        return
    }

    Invoke-HibernateRestore
    Invoke-LocationRestore
    Invoke-OneDriveRestore
    Invoke-RemoteDesktopRestore
    Invoke-CortanaRestore
    Invoke-SettingsSyncRestore
    Invoke-ClipboardRestore
    Invoke-FindMyDeviceRestore
    Invoke-EdgeSignInRestore
    Invoke-BackgroundAppsRestore
    Invoke-CameraMicRestore

    Write-Host ""
    Write-Host "  All user-facing features restored. Reboot recommended." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
#  LOG + MENU
# ---------------------------------------------------------------------------

function Save-Log {
    $logPath = "$PSScriptRoot\Win11Restore_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $header = @(
        "Win10/11 Restore Helper Log",
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
    Write-Host "  Selectively turn things back on:" -ForegroundColor White
    Write-Host ""
    $opts = @(
        " 1  -- Restore HIBERNATE         (powercfg -h on + Power menu)"
        " 2  -- Restore LOCATION          (lift policy + start lfsvc)"
        " 3  -- Restore FAST STARTUP      (optional -- hardener killed on purpose)"
        " 4  -- Restore ONEDRIVE          (handles base disable + Extras nuke)"
        " 5  -- Restore REMOTE DESKTOP    (policy + firewall)"
        " 6  -- Restore CORTANA / search  (Cortana + Start menu Bing)"
        " 7  -- Restore SETTINGS SYNC     (Microsoft account sync)"
        " 8  -- Restore CROSS-DEVICE CLIPBOARD"
        " 9  -- Restore FIND MY DEVICE"
        "10  -- Restore EDGE SIGN-IN + SYNC (sign-in + bookmark/password sync)"
        "11  -- Restore BACKGROUND APPS    (Mail/Calendar/Outlook notifications)"
        "12  -- Restore CAMERA + MICROPHONE (policy block + consent + gpupdate)"
        ""
        "13  -- Restore HIBERNATE + LOCATION (the original combo)"
        "14  -- Restore ALL user-facing features (1, 2, 4-12)"
        ""
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
    Write-Note "Option 12 runs gpupdate /force automatically -- no reboot"
    Write-Note "needed in most cases. Just relaunch the app that needs the mic."
    Write-Note "For a full revert use Snapshot Restore (launcher option U)."
    Write-Host ""
}

do {
    Show-Menu
    $choice = (Read-Host "  Enter choice").Trim().ToUpper()
    switch ($choice) {
        '1'  { Invoke-HibernateRestore }
        '2'  { Invoke-LocationRestore  }
        '3'  { Invoke-FastStartupRestore }
        '4'  { Invoke-OneDriveRestore }
        '5'  { Invoke-RemoteDesktopRestore }
        '6'  { Invoke-CortanaRestore }
        '7'  { Invoke-SettingsSyncRestore }
        '8'  { Invoke-ClipboardRestore }
        '9'  { Invoke-FindMyDeviceRestore }
        '10' { Invoke-EdgeSignInRestore }
        '11' { Invoke-BackgroundAppsRestore }
        '12' { Invoke-CameraMicRestore }
        '13' {
            Invoke-HibernateRestore
            Invoke-LocationRestore
            Write-Host ""
            Write-Host "  Hibernate and Location are restored. Reboot recommended." -ForegroundColor Green
        }
        '14' { Invoke-RestoreAll }
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
