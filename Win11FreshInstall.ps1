<#
.SYNOPSIS
    Windows 11 Fresh-Install Bootstrap
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    First-30-minutes work on a brand-new Windows 11 install.
    Fixes the things you have to redo by hand every time you set
    up a PC -- BEFORE the main hardener even runs.

    Designed for "I just finished OOBE, now what" moment.
    Run this first. Then run the main hardener suite.

    Covers:
      - Explorer (file extensions, hidden files, This PC default)
      - Taskbar (widgets, search box, chat, task view, alignment)
      - Start menu (recommendations off, web search off)
      - Context menu (restore Windows 10 "right-click" style)
      - Login / lock screen nags
      - "Let's finish setting up" post-update prompt
      - Unpin Microsoft's default taskbar bloat

    READ-ONLY of the registry from a security standpoint -- this
    only changes UI preferences. None of these unlock attack
    surface or weaken security.
.NOTES
    Run via RunHardener.bat (option N) or right-click and Run with PowerShell.
    Self-elevates to Administrator automatically.
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

# Force UTF-8 for console output so any Unicode characters render
# correctly instead of as garbled CP-437 sequences.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
} catch {
    # Not fatal -- only affects display of Unicode characters.
}

# ---------------------------------------------------------------------------
#  HELPERS (same style as the rest of the suite)
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win11 Fresh-Install Bootstrap  --  CrisisOfTruth.org" -ForegroundColor Cyan
    Write-Host "  First-pass UI cleanup. Run BEFORE the main hardener." -ForegroundColor DarkCyan
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
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
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process explorer.exe
}

# ---------------------------------------------------------------------------
#  1 -- EXPLORER (file extensions, hidden files, This PC default)
# ---------------------------------------------------------------------------

function Invoke-ExplorerTweaks {
    Write-Title "FILE EXPLORER"

    Invoke-Tweak "Show file extensions (no more hidden .exe / .pdf)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0
    }

    Invoke-Tweak "Show hidden files and folders" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1
    }

    Invoke-Tweak "Show protected operating-system files" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSuperHidden' 1
    }

    Invoke-Tweak "Open Explorer to This PC (not Quick Access / Home)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1
    }

    Invoke-Tweak "Disable Quick Access recent files / frequent folders" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
    }

    Invoke-Tweak "Hide gallery / OneDrive nag entries in Explorer sidebar" {
        # Hide Gallery node
        Set-Reg 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' 0
        # Hide Home / Quick Access pinned-to-tree (let user re-enable if they want)
        # (skipped -- some people want Home, leave their choice intact)
    }

    Invoke-Tweak "Restore classic Windows 10 right-click context menu" {
        $key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        Set-ItemProperty -Path $key -Name '(default)' -Value '' -Force
    }
}

# ---------------------------------------------------------------------------
#  2 -- TASKBAR (widgets, search, chat, task view, alignment)
# ---------------------------------------------------------------------------

function Invoke-TaskbarTweaks {
    Write-Title "TASKBAR"

    Invoke-Tweak "Hide Widgets button" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    }

    Invoke-Tweak "Hide Chat (Teams consumer) button" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 3
    }

    Invoke-Tweak "Hide Task View button" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0
    }

    Invoke-Tweak "Collapse Search box to icon only (smaller footprint)" {
        # 0 = hidden, 1 = icon only, 2 = box, 3 = icon + label, 4 = full box
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1
    }

    Invoke-Tweak "Disable Bing web search from Start menu / Search" {
        Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
    }

    Invoke-Tweak "Disable 'highlights' in Search (animated promo content)" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' 0
    }

    Invoke-Tweak "Align taskbar to the left (Windows 10 style) -- optional" {
        # Comment out the next line if you prefer the centered Windows 11 look.
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 0
    }
}

# ---------------------------------------------------------------------------
#  3 -- START MENU (recommendations, web search, MSA promos)
# ---------------------------------------------------------------------------

function Invoke-StartMenuTweaks {
    Write-Title "START MENU"

    Invoke-Tweak "Hide 'Recommended' section recent files" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecentlyAddedApps' 1
    }

    Invoke-Tweak "Hide tips, tricks and suggestions in Start" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
    }

    Invoke-Tweak "Disable Microsoft account-related Start menu nags" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Start' 'ShowAccountNotifications' 0
        # Block 'Sign in to your Microsoft account' nag in Settings
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    }

    Invoke-Tweak "Hide Office / OneDrive promoted items in Start" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
    }
}

# ---------------------------------------------------------------------------
#  4 -- LOGIN / LOCK SCREEN NAGS
# ---------------------------------------------------------------------------

function Invoke-LoginNagTweaks {
    Write-Title "LOGIN / LOCK SCREEN NAGS"

    Invoke-Tweak "Disable 'Let's finish setting up your device' post-update nag" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    }

    Invoke-Tweak "Disable 'Suggest ways I can finish setting up my device'" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    }

    Invoke-Tweak "Disable lock screen tips, tricks and facts (Spotlight overlay)" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
    }

    Invoke-Tweak "Disable 'Get the most out of Windows' welcome page after updates" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
    }
}

# ---------------------------------------------------------------------------
#  5 -- UNPIN MICROSOFT BLOAT FROM TASKBAR
# ---------------------------------------------------------------------------

function Invoke-UnpinTaskbar {
    Write-Title "UNPIN MICROSOFT BLOAT FROM TASKBAR"

    # Strategy: blank the pinned-items layout so taskbar pins reset to nothing.
    # User can re-pin what they actually want.

    Invoke-Tweak "Reset taskbar pins to empty (you re-pin what YOU use)" {
        $key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
        if (Test-Path $key) {
            Remove-ItemProperty -Path $key -Name 'Favorites'        -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $key -Name 'FavoritesResolve' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $key -Name 'FavoritesChanges' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $key -Name 'FavoritesRemovedChanges' -ErrorAction SilentlyContinue
        }
        # Per-user pinned layout file -- delete so Explorer rebuilds empty
        $layout = "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        if (Test-Path $layout) {
            Get-ChildItem $layout -Filter '*.lnk' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'Edge|Store|Outlook|Mail|Teams|Copilot' } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
#  6 -- OOBE / FIRST-RUN NAGS (the ones that appear AFTER a major update)
# ---------------------------------------------------------------------------

function Invoke-OobeTweaks {
    Write-Title "OOBE AND POST-UPDATE NAGS"

    Invoke-Tweak "Disable OneDrive auto-setup prompts" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\OneDrive' 'DisablePersonalSync' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'PreventNetworkTrafficPreUserSignIn' 1
    }

    Invoke-Tweak "Disable Edge first-run welcome / import wizard" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BrowserSignin' 0
    }

    Invoke-Tweak "Disable 'Welcome to Windows' tour after updates" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353698Enabled' 0
    }

    Invoke-Tweak "Disable Settings app suggestions banner" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0
    }
}

# ---------------------------------------------------------------------------
#  RUN-ALL + APPLY (restart explorer to make UI changes visible)
# ---------------------------------------------------------------------------

function Invoke-AllFreshInstallTweaks {
    Invoke-ExplorerTweaks
    Invoke-TaskbarTweaks
    Invoke-StartMenuTweaks
    Invoke-LoginNagTweaks
    Invoke-UnpinTaskbar
    Invoke-OobeTweaks

    Write-Host ""
    Write-Host "  Restarting Explorer to apply UI changes..." -ForegroundColor Yellow
    Restart-Explorer

    Write-Host ""
    Write-Host "  ALL FRESH-INSTALL TWEAKS COMPLETE." -ForegroundColor Green
    Write-Host "  NEXT STEP: run the main hardener suite (Privacy + Extras + Perf)." -ForegroundColor Cyan
    Write-Host ""
}

function Save-Log {
    $logPath = "$PSScriptRoot\Win11FreshInstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $script:Log | Out-File -FilePath $logPath -Encoding UTF8
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
        " 1  -- ALL FRESH-INSTALL TWEAKS (recommended -- run this first)"
        " 2  -- File Explorer (extensions, hidden files, This PC default)"
        " 3  -- Taskbar (widgets, search, chat, task view, alignment)"
        " 4  -- Start Menu (recommendations, web search, MSA nags)"
        " 5  -- Login / Lock screen nags (Spotlight, post-update prompts)"
        " 6  -- Unpin Microsoft bloat from taskbar"
        " 7  -- OOBE / first-run / post-update nags"
        " X  -- Restart Explorer now (apply pending UI changes)"
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
        '1' { Invoke-AllFreshInstallTweaks }
        '2' { Invoke-ExplorerTweaks   }
        '3' { Invoke-TaskbarTweaks    }
        '4' { Invoke-StartMenuTweaks  }
        '5' { Invoke-LoginNagTweaks   }
        '6' { Invoke-UnpinTaskbar     }
        '7' { Invoke-OobeTweaks       }
        'X' { Restart-Explorer; Write-OK "Explorer restarted" }
        'L' { Save-Log }
        'Q' { break }
        default { Write-Host "  Invalid choice." -ForegroundColor Red }
    }
    if ($choice -ne 'Q') {
        Write-Host ""
        Read-Host "  Press Enter to return to menu"
    }
} while ($choice -ne 'Q')

Write-Host ""
Write-Host "  Goodbye. Reboot when ready -- and run the main hardener next." -ForegroundColor Cyan
Write-Host ""
