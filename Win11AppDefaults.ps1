<#
.SYNOPSIS
    Windows 11 App Defaults Manager
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    Snapshots, restores and audits Windows 11 default app associations
    (which app owns which file type -- VLC for video, your PDF reader,
    your browser, etc.).

    Why this script exists:
      Windows feature updates and cumulative updates frequently reset
      file-type ownership back to Microsoft's defaults (Edge, Photos,
      Media Player, etc.) WITHOUT asking. This script:
        1. Captures your CURRENT defaults to an XML snapshot
        2. Lets you re-import that snapshot when Microsoft resets things
        3. Disables the nag screens and policies that TRIGGER resets
        4. Blocks Edge's silent grab of PDFs
        5. Detects drift so you know exactly what changed

    Hard limit you should know about:
      Since Windows 10, Microsoft cryptographically signs the
      "UserChoice" registry keys that decide which app owns each
      file type. If a script writes those keys directly, Windows
      detects the bad signature and silently resets the association.
      That is why this script does NOT just blast registry values --
      it uses the only Microsoft-supported export/import mechanism
      (DISM /Export-DefaultAppAssociations) plus per-app policies.

      The DISM import takes effect immediately for any NEW user
      profile, and serves as a precise checklist of what to re-set
      via Settings > Apps > Default apps for your CURRENT profile.
      The script tells you exactly which extensions changed so you
      can fix them in seconds.
.NOTES
    Run via RunHardener.bat (option D) or right-click and Run with PowerShell.
    Self-elevates to Administrator automatically.
#>

# Self-elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not running as Administrator -- relaunching elevated..." -ForegroundColor Yellow
    Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
    exit
}

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
#  HELPERS  (match style of Win11PrivacyHardener.ps1)
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkCyan
    Write-Host "  Win11 App Defaults Manager  --  CrisisOfTruth.org" -ForegroundColor Cyan
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

# ---------------------------------------------------------------------------
#  SNAPSHOT STORAGE
# ---------------------------------------------------------------------------
# Snapshots live in a dedicated folder so the audit script and the manager
# always agree on where to look. The "_LATEST" file is overwritten each time
# you snapshot; the timestamped file is kept forever as a rollback point.

$script:SnapDir       = Join-Path $env:USERPROFILE 'Documents\Win11Hardener'
$script:LatestSnapXml = Join-Path $script:SnapDir 'AppDefaults_LATEST.xml'
$script:LatestSnapTxt = Join-Path $script:SnapDir 'AppDefaults_Watched_LATEST.txt'

function Ensure-SnapDir {
    if (-not (Test-Path $script:SnapDir)) {
        New-Item -Path $script:SnapDir -ItemType Directory -Force | Out-Null
    }
}

# Extensions used for the human-readable drift report. The XML snapshot
# captures EVERY association on the system; this list is only used for the
# on-screen drift summary so it stays scannable.
$script:WatchedExts = @(
    # Browsers / web
    '.htm','.html','.url','.svg','.webp',
    # Media -- VLC territory
    '.mp4','.mkv','.avi','.mov','.wmv','.webm','.flv','.m4v',
    '.mp3','.flac','.wav','.m4a','.aac','.ogg','.opus','.wma',
    # Documents
    '.pdf','.txt','.rtf','.csv',
    # Images
    '.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.heic','.ico',
    # Archives
    '.zip','.7z','.rar','.tar','.gz',
    # Code / config
    '.json','.xml','.ps1','.bat','.cmd','.reg','.ini','.log','.md'
)

# Returns the current ProgId that owns an extension, or $null if not set.
# Defensive against missing keys / missing properties so it works under
# any error-action setting.
function Get-CurrentProgId {
    param([string]$Ext)
    $path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext\UserChoice"
    if (-not (Test-Path $path)) { return $null }
    $item = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    if ($item.PSObject.Properties.Name -contains 'ProgId') {
        return $item.ProgId
    }
    return $null
}

# ---------------------------------------------------------------------------
#  1 -- SNAPSHOT
# ---------------------------------------------------------------------------

function Invoke-AppDefaultsSnapshot {
    Write-Title "SNAPSHOT CURRENT DEFAULT APPS"

    Ensure-SnapDir

    Invoke-Tweak "Export ALL default app associations via DISM" {
        # Timestamped backup -- kept forever
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $stampFile = Join-Path $script:SnapDir "AppDefaults_$stamp.xml"
        $dismOut = & dism.exe /Online /Export-DefaultAppAssociations:"$stampFile" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "DISM exit $LASTEXITCODE -- $dismOut" }
        # Overwrite LATEST so audit + re-import always know where to look
        Copy-Item -Path $stampFile -Destination $script:LatestSnapXml -Force
        Write-Info "    XML snapshot: $stampFile"
        Write-Info "    LATEST copy : $script:LatestSnapXml"
    }

    Invoke-Tweak "Capture watched-extension list to plain-text companion" {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $txtFile = Join-Path $script:SnapDir "AppDefaults_Watched_$stamp.txt"
        $lines = @(
            "Win11 App Defaults -- watched extensions snapshot",
            "Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "User:     $env:USERNAME",
            ("=" * 60),
            ""
        )
        foreach ($e in $script:WatchedExts) {
            $progId = Get-CurrentProgId $e
            if (-not $progId) { $progId = '(none / not set)' }
            $lines += ("{0,-10}  ->  {1}" -f $e, $progId)
        }
        $lines | Out-File -FilePath $txtFile               -Encoding ASCII
        $lines | Out-File -FilePath $script:LatestSnapTxt  -Encoding ASCII
        Write-Info "    Watched-list: $txtFile"
    }

    Write-Host ""
    Write-Host "  Snapshot complete." -ForegroundColor Green
    Write-Host "  Re-run SNAPSHOT any time you change a default app in" -ForegroundColor Gray
    Write-Host "  Settings > Apps > Default apps -- it overwrites LATEST" -ForegroundColor Gray
    Write-Host "  so future audits compare against your latest preferences." -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
#  2 -- RE-IMPORT SNAPSHOT
# ---------------------------------------------------------------------------

function Invoke-AppDefaultsImport {
    Write-Title "RE-IMPORT LAST SNAPSHOT"

    if (-not (Test-Path $script:LatestSnapXml)) {
        Write-Fail "No snapshot found at $script:LatestSnapXml"
        Write-Info "Run option 1 (SNAPSHOT) first."
        return
    }

    Write-Host "  IMPORTANT -- read this before continuing:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    The DISM import sets defaults that take effect IMMEDIATELY" -ForegroundColor Gray
    Write-Host "    for any NEW Windows user account. For your CURRENT account," -ForegroundColor Gray
    Write-Host "    Microsoft's UserChoice signature lock means the only way to" -ForegroundColor Gray
    Write-Host "    fix associations is via Settings > Apps > Default apps." -ForegroundColor Gray
    Write-Host ""
    Write-Host "    What this option DOES do for you right now:" -ForegroundColor Gray
    Write-Host "      - Updates the system-wide default-association XML so any" -ForegroundColor Gray
    Write-Host "        future user profile starts with YOUR defaults" -ForegroundColor Gray
    Write-Host "      - Prints a checklist of associations that drifted, so you" -ForegroundColor Gray
    Write-Host "        can fix them in Settings in seconds" -ForegroundColor Gray
    Write-Host ""

    Invoke-Tweak "Import default app associations via DISM" {
        $dismOut = & dism.exe /Online /Import-DefaultAppAssociations:"$script:LatestSnapXml" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "DISM exit $LASTEXITCODE -- $dismOut" }
    }

    Show-AppDefaultsDrift
}

# ---------------------------------------------------------------------------
#  3 -- DRIFT DETECTION
# ---------------------------------------------------------------------------

function Show-AppDefaultsDrift {
    Write-Title "DRIFT vs LAST SNAPSHOT"

    if (-not (Test-Path $script:LatestSnapTxt)) {
        Write-Fail "No watched-list snapshot found."
        Write-Info "Run option 1 (SNAPSHOT) first."
        return
    }

    # Parse snapshot file -> hashtable of ext -> progId
    $snap = @{}
    $body = Get-Content -Path $script:LatestSnapTxt -Encoding ASCII |
            Where-Object { $_ -match '^\s*\.[A-Za-z0-9]+\s+->' }
    foreach ($line in $body) {
        $parts = $line -split '->'
        if ($parts.Count -eq 2) {
            $snap[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    $changed = 0
    $same    = 0
    foreach ($e in $script:WatchedExts) {
        $now = Get-CurrentProgId $e
        if (-not $now) { $now = '(none / not set)' }
        $then = if ($snap.ContainsKey($e)) { $snap[$e] } else { '(not in snapshot)' }
        if ($now -eq $then) {
            Write-Host ("  [OK]      {0,-10}  {1}" -f $e, $now) -ForegroundColor Green
            $same++
        } else {
            Write-Host ("  [DRIFT]   {0,-10}  now: {1}" -f $e, $now) -ForegroundColor Red
            Write-Host ("                       was: {0}" -f $then) -ForegroundColor DarkGray
            $changed++
        }
    }

    Write-Host ""
    Write-Host ("  Watched extensions matching snapshot : {0}" -f $same) -ForegroundColor Green
    if ($changed -gt 0) {
        Write-Host ("  Watched extensions DRIFTED           : {0}" -f $changed) -ForegroundColor Red
        Write-Host ""
        Write-Host "  To fix:  Settings > Apps > Default apps" -ForegroundColor Yellow
        Write-Host "  Search for each [DRIFT] extension and reassign the app you want." -ForegroundColor Yellow
    } else {
        Write-Host "  No drift on watched extensions. Your defaults are intact." -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
#  4 -- KILL THE NAGS THAT TRIGGER RESETS
# ---------------------------------------------------------------------------

function Invoke-DisableAppResetNags {
    Write-Title "DISABLE APP-RESET NAGS AND PROMPTS"

    Invoke-Tweak "Disable 'You have new apps that can open this type of file' alert" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'NoNewAppAlert' 1
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts' 'AppAssoToastsEnabled' 0
    }

    Invoke-Tweak "Disable 'Look for an app in the Microsoft Store' open-with prompt" {
        Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'NoUseStoreOpenWith' 1
        Set-Reg 'HKLM:\Software\Policies\Microsoft\Windows\Explorer' 'NoUseStoreOpenWith' 1
    }

    Invoke-Tweak "Disable Edge 'Set Edge as default browser' nag" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DefaultBrowserSettingEnabled' 0
        Set-Reg 'HKCU:\Software\Policies\Microsoft\Edge'  'DefaultBrowserSettingEnabled' 0
    }

    Invoke-Tweak "Disable Edge promotional new-tab content" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'PromotionalTabsEnabled' 0
    }

    Invoke-Tweak "Disable Windows Welcome / 'Get even more out of Windows' tour" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
    }

    Invoke-Tweak "Disable 'Suggested apps' notifications in Settings" {
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0
    }
}

# ---------------------------------------------------------------------------
#  5 -- BLOCK EDGE PDF HIJACK
# ---------------------------------------------------------------------------

function Invoke-BlockEdgePdfHijack {
    Write-Title "BLOCK EDGE PDF HIJACK"

    Invoke-Tweak "Force Edge to download PDFs instead of opening them" {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'AlwaysOpenPdfExternally' 1
    }

    Invoke-Tweak "Strip Edge from PDF Open With shortlist (cosmetic only)" {
        # Cleans the right-click 'Open with' shortlist for PDFs.
        # This is the cosmetic OpenWithList -- NOT the locked UserChoice key,
        # so Windows will not flag it and reset.
        $path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\OpenWithList'
        if (Test-Path $path) {
            $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($props) {
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Value -is [string] -and $p.Value -match 'msedge\.exe') {
                        Remove-ItemProperty -Path $path -Name $p.Name -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    Invoke-Tweak "Block Edge from re-installing as the PDF MIME handler" {
        # Edge re-registers itself as a PDF handler on every browser update.
        # This MRU list is what feeds the 'recently used' picker; clearing
        # the Edge entry stops Windows from suggesting Edge first.
        $path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\OpenWithProgids'
        if (Test-Path $path) {
            $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($props) {
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -match 'MSEdge' -or $p.Name -match 'AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723') {
                        Remove-ItemProperty -Path $path -Name $p.Name -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    Write-Host ""
    Write-Host "  Done. Edge will no longer auto-open PDFs." -ForegroundColor Green
    Write-Host "  After installing your PDF reader (Acrobat, SumatraPDF, Foxit," -ForegroundColor Gray
    Write-Host "  etc.), set it as default in Settings > Apps > Default apps > .pdf" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
#  6 -- SHOW CURRENT DEFAULTS
# ---------------------------------------------------------------------------

function Show-CurrentAppDefaults {
    Write-Title "CURRENT DEFAULT APPS (watched extensions)"
    foreach ($e in $script:WatchedExts) {
        $progId = Get-CurrentProgId $e
        if (-not $progId) { $progId = '(none / not set)' }
        Write-Host ("    {0,-10}  ->  {1}" -f $e, $progId) -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  Tip: take a SNAPSHOT (option 1) any time this list looks the way" -ForegroundColor Cyan
    Write-Host "  you want it. Future audits will compare against that snapshot." -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
#  7 -- LIST OLD SNAPSHOTS
# ---------------------------------------------------------------------------

function Show-SnapshotHistory {
    Write-Title "SNAPSHOT HISTORY"
    if (-not (Test-Path $script:SnapDir)) {
        Write-Info "No snapshot folder yet ($script:SnapDir)."
        return
    }
    $files = Get-ChildItem -Path $script:SnapDir -Filter 'AppDefaults_*.xml' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending
    if (-not $files) {
        Write-Info "No XML snapshots found in $script:SnapDir."
        return
    }
    foreach ($f in $files) {
        $size = [math]::Round($f.Length / 1KB, 1)
        Write-Host ("    {0}  {1,7} KB  {2}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $size, $f.Name) -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host ("  Folder: {0}" -f $script:SnapDir) -ForegroundColor DarkCyan
    Write-Host "  To roll back to an older snapshot, copy it over AppDefaults_LATEST.xml" -ForegroundColor DarkCyan
    Write-Host "  then run option 2 (RE-IMPORT)." -ForegroundColor DarkCyan
}

# ---------------------------------------------------------------------------
#  LOG + MENU
# ---------------------------------------------------------------------------

function Save-Log {
    $logPath = "$PSScriptRoot\Win11AppDefaults_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $script:Log | Out-File -FilePath $logPath -Encoding ASCII
    Write-OK "Log saved: $logPath"
}

function Show-Menu {
    Write-Header
    Write-Host "  Select an option:" -ForegroundColor White
    Write-Host ""
    $opts = @(
        " 1  -- SNAPSHOT current defaults  (run after setting VLC/Acrobat/etc.)"
        " 2  -- RE-IMPORT last snapshot    (after a Microsoft update reset)"
        " 3  -- AUDIT drift                (what changed vs last snapshot?)"
        " 4  -- DISABLE app-reset NAGS     (stop Microsoft from prompting)"
        " 5  -- BLOCK Edge PDF hijack"
        " 6  -- SHOW current defaults      (read-only listing)"
        " 7  -- SHOW snapshot history"
        " 8  -- ALL hardening (4 + 5)      -- does NOT snapshot or import"
        " L  -- Save Log to Desktop"
        " Q  -- Quit"
    )
    foreach ($o in $opts) { Write-Host "  $o" -ForegroundColor Gray }
    Write-Host ""
    if (Test-Path $script:LatestSnapXml) {
        $info = Get-Item $script:LatestSnapXml
        Write-Host ("  Last snapshot: {0}" -f $info.LastWriteTime) -ForegroundColor DarkCyan
    } else {
        Write-Host "  Last snapshot: (none yet -- start with option 1)" -ForegroundColor DarkYellow
    }
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
        '1' { Invoke-AppDefaultsSnapshot }
        '2' { Invoke-AppDefaultsImport }
        '3' { Show-AppDefaultsDrift }
        '4' { Invoke-DisableAppResetNags }
        '5' { Invoke-BlockEdgePdfHijack }
        '6' { Show-CurrentAppDefaults }
        '7' { Show-SnapshotHistory }
        '8' {
            Invoke-DisableAppResetNags
            Invoke-BlockEdgePdfHijack
            Write-Host ""
            Write-Host "  All app-defaults hardening applied. Reboot recommended." -ForegroundColor Green
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

Write-Host ""
Write-Host "  Goodbye. Reboot when ready." -ForegroundColor Cyan
Write-Host ""
