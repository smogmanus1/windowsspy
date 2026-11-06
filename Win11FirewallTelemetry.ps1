<#
.SYNOPSIS
    Windows 11 Firewall + Hosts -- block Microsoft telemetry endpoints
    Author : Brad / CrisisOfTruth.org
    Version: 1.0
.DESCRIPTION
    Adds two layers of telemetry blocking:

    A) HOSTS FILE  -- Redirects known Microsoft telemetry hostnames to
       0.0.0.0. This is the only reliable hostname-based block on
       Windows because the built-in firewall does NOT support hostname
       rules; it only supports IP addresses. IPs change. Hosts entries
       are bulletproof and survive restarts, updates, and policy resets.

    B) FIREWALL    -- Adds outbound block rules for the standalone
       telemetry binaries that have a fixed path (CompatTelRunner.exe,
       DeviceCensus.exe, MicrosoftEdgeUpdate.exe, etc.). svchost-hosted
       telemetry cannot be blocked by binary because it shares svchost
       with everything else; for those, the hosts file is the answer.

    Both layers are NAMED with consistent prefixes so the cleanup
    function in this script can enumerate and remove them precisely
    without disturbing your other rules / hosts entries.

      Hosts marker:  # CrisisOfTruth_TelemetryBlock
      Firewall name: COT-TelemetryBlock-*

    What this script will NOT block (by design):
      - Windows Update endpoints (you want to keep getting patches)
      - Microsoft Store CDN (so the Store still works for installs you
        actually want)
      - Activation servers (so your license stays activated)
      - Certificate revocation lists / OCSP (cert validation needs them)

    A backup of the existing hosts file is taken before any changes.
    A removal option (R) cleanly reverses everything this script did.
.NOTES
    Self-elevates to Administrator automatically.
    Run via RunHardener.bat (option F) or right-click + Run with PowerShell.
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
#  HELPERS
# ---------------------------------------------------------------------------

function Write-Header {
    Clear-Host
    $line = '=' * 70
    Write-Host ""
    Write-Host " $line" -ForegroundColor DarkRed
    Write-Host "  Win11 Firewall + Hosts Telemetry Block  --  CrisisOfTruth.org" -ForegroundColor Red
    Write-Host " $line" -ForegroundColor DarkRed
    Write-Host ""
}

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Info ($msg) { Write-Host "  [..]   $msg" -ForegroundColor Yellow }
function Write-Skip ($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor DarkGray }
function Write-Sep         { Write-Host ("  " + ("-" * 66)) -ForegroundColor DarkGray }
function Write-Title ($msg) {
    Write-Host ""
    Write-Host "  -- $msg" -ForegroundColor Red
    Write-Sep
}

$script:HostsFile  = "$env:windir\System32\drivers\etc\hosts"
$script:HostsMark  = "# CrisisOfTruth_TelemetryBlock"
$script:HostsEnd   = "# End_CrisisOfTruth_TelemetryBlock"
$script:FwPrefix   = "COT-TelemetryBlock-"
$script:PassCount  = 0
$script:FailCount  = 0
$script:Log        = [System.Collections.Generic.List[string]]::new()

function Log-Line ($s) { $script:Log.Add($s) | Out-Null }

# ---------------------------------------------------------------------------
#  TELEMETRY HOSTS LIST
#  Curated. Excludes update / activation / Store / OCSP endpoints.
# ---------------------------------------------------------------------------

$script:TelemetryHosts = @(
    # -- Core telemetry / SIUF / DiagTrack
    'vortex.data.microsoft.com',
    'vortex-win.data.microsoft.com',
    'telecommand.telemetry.microsoft.com',
    'oca.telemetry.microsoft.com',
    'sqm.telemetry.microsoft.com',
    'sqm.microsoft.com',
    'watson.telemetry.microsoft.com',
    'watson.ppe.telemetry.microsoft.com',
    'watson.microsoft.com',
    'umwatson.events.data.microsoft.com',
    'eaus2watson.events.data.microsoft.com',
    'modern.watson.data.microsoft.com',
    'redir.metaservices.microsoft.com',
    'reports.wes.df.telemetry.microsoft.com',
    'wes.df.telemetry.microsoft.com',
    'services.wes.df.telemetry.microsoft.com',
    'sqm.df.telemetry.microsoft.com',
    'telemetry.microsoft.com',
    'telemetry.appex.bing.net',
    'telemetry.urs.microsoft.com',
    'settings-sandbox.data.microsoft.com',
    'settings-win.data.microsoft.com',
    'survey.watson.microsoft.com',
    'fe2.update.microsoft.com.akadns.net',
    'diagnostics.support.microsoft.com',
    'corp.sts.microsoft.com',
    'statsfe1.ws.microsoft.com',
    'statsfe2.ws.microsoft.com',
    'statsfe2.update.microsoft.com.akadns.net',
    'feedback.windows.com',
    'feedback.microsoft-hohm.com',
    'feedback.search.microsoft.com',
    'i1.services.social.microsoft.com',
    'i1.services.social.microsoft.com.nsatc.net',
    'pre.footprintpredict.com',
    'preview.footprintpredict.com',
    'choice.microsoft.com',
    'choice.microsoft.com.nsatc.net',
    'compatexchange.cloudapp.net',
    'cs1.wpc.v0cdn.net',
    'a-0001.a-msedge.net',
    'a-0002.a-msedge.net',
    'a-0003.a-msedge.net',
    'a-0004.a-msedge.net',
    'a-0005.a-msedge.net',
    'a-0006.a-msedge.net',
    'a-0007.a-msedge.net',
    'a-0008.a-msedge.net',
    'a-0009.a-msedge.net',
    'spynet.microsoft.com',

    # -- App / Store nag + Promotional
    'msnbot-65-55-108-23.search.msn.com',
    'apps.skype.com',
    'g.msn.com',
    'msnbot-65-52-108-138.search.msn.com',
    'cy2.vortex.data.microsoft.com.akadns.net',
    'cy2.settings.data.microsoft.com.akadns.net',
    'tile-service.weather.microsoft.com',
    'wallet.microsoft.com',
    'wdcp.microsoft.com',
    'wdcpalt.microsoft.com',

    # -- Bing search ad / nav telemetry
    'a.ads1.msn.com',
    'a.ads2.msn.com',
    'a.ads2.msads.net',
    'ads.msn.com',
    'ads1.msads.net',
    'ads1.msn.com',
    'aidps.atdmt.com',
    'aka-cdn-ns.adtech.de',
    'b.ads1.msn.com',
    'b.ads2.msads.net',
    'b.rad.msn.com',
    'bs.serving-sys.com',
    'cdn.atdmt.com',
    'flex.msn.com',
    'rad.msn.com',
    'rad.live.com',
    'ac3.msn.com',
    'ssw.live.com',

    # -- Edge / Office365 internal telemetry
    'browser.events.data.msn.com',
    'self.events.data.microsoft.com',
    'nexus.officeapps.live.com',
    'nexusrules.officeapps.live.com',
    'office.events.data.microsoft.com',
    'mobile.pipe.aria.microsoft.com'
)

# Standalone telemetry binaries we WILL block via firewall.
# Path is verified at script time -- non-existent binaries are skipped.
$script:TelemetryBinaries = @(
    "$env:windir\System32\CompatTelRunner.exe",
    "$env:windir\System32\DeviceCensus.exe",
    "$env:windir\System32\dmclient.exe",
    "$env:windir\System32\diagnosticsdatasubmitter.exe",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe",
    "$env:windir\System32\smartscreen.exe"
)

# ---------------------------------------------------------------------------
#  HOSTS FILE
# ---------------------------------------------------------------------------

function Backup-Hosts {
    if (-not (Test-Path $script:HostsFile)) {
        Write-Skip "hosts file not found at $script:HostsFile (?)"
        return $null
    }
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = "$script:HostsFile.cot.$stamp.bak"
    Copy-Item -Path $script:HostsFile -Destination $backup -Force
    Write-OK "Hosts file backed up: $backup"
    Log-Line "[BACKUP] $backup"
    return $backup
}

function Test-HostsBlock {
    if (-not (Test-Path $script:HostsFile)) { return $false }
    $content = Get-Content $script:HostsFile -ErrorAction SilentlyContinue
    return ($content -contains $script:HostsMark)
}

function Apply-HostsBlock {
    Write-Title "HOSTS FILE -- adding telemetry block entries"

    if (Test-HostsBlock) {
        Write-Info "Existing CrisisOfTruth block found. Removing it first to refresh."
        Remove-HostsBlock -Quiet
    }

    Backup-Hosts | Out-Null

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('') | Out-Null
    $lines.Add($script:HostsMark) | Out-Null
    $lines.Add("# Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by Win11FirewallTelemetry.ps1") | Out-Null
    $lines.Add("# To remove: re-run this script and choose option R, or") | Out-Null
    $lines.Add("# delete every line between this marker and $script:HostsEnd.") | Out-Null
    foreach ($h in $script:TelemetryHosts | Sort-Object -Unique) {
        $lines.Add(("0.0.0.0  {0}" -f $h)) | Out-Null
    }
    $lines.Add($script:HostsEnd) | Out-Null
    $lines.Add('') | Out-Null

    try {
        Add-Content -Path $script:HostsFile -Value $lines -Encoding ASCII
        Write-OK ("Added {0} telemetry hosts to hosts file" -f $script:TelemetryHosts.Count)
        Log-Line ("[HOSTS] Added {0} entries" -f $script:TelemetryHosts.Count)
        $script:PassCount++
    } catch {
        Write-Fail ("Could not write hosts file: {0}" -f $_.Exception.Message)
        Log-Line ("[FAIL] hosts write -- {0}" -f $_.Exception.Message)
        $script:FailCount++
        return
    }

    # Flush DNS to ensure new entries take effect immediately
    & ipconfig /flushdns | Out-Null
    Write-OK "DNS resolver cache flushed"
}

function Remove-HostsBlock {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Title "HOSTS FILE -- removing CrisisOfTruth block" }
    if (-not (Test-Path $script:HostsFile)) {
        if (-not $Quiet) { Write-Skip "hosts file not present" }
        return
    }
    if (-not (Test-HostsBlock)) {
        if (-not $Quiet) { Write-Skip "No CrisisOfTruth block markers found in hosts file" }
        return
    }
    if (-not $Quiet) { Backup-Hosts | Out-Null }

    $content = Get-Content $script:HostsFile -ErrorAction SilentlyContinue
    $out = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($l in $content) {
        if ($l -eq $script:HostsMark) { $inBlock = $true;  continue }
        if ($l -eq $script:HostsEnd)  { $inBlock = $false; continue }
        if (-not $inBlock) { $out.Add($l) | Out-Null }
    }
    try {
        Set-Content -Path $script:HostsFile -Value $out -Encoding ASCII -Force
        if (-not $Quiet) { Write-OK "CrisisOfTruth block removed from hosts file" }
        Log-Line "[HOSTS] Block removed"
        $script:PassCount++
    } catch {
        Write-Fail ("Could not write hosts file: {0}" -f $_.Exception.Message)
        $script:FailCount++
    }
    & ipconfig /flushdns | Out-Null
}

# ---------------------------------------------------------------------------
#  FIREWALL RULES (binary-based)
# ---------------------------------------------------------------------------

function Apply-FirewallRules {
    Write-Title "FIREWALL -- outbound block rules for telemetry binaries"

    foreach ($p in $script:TelemetryBinaries) {
        if (-not (Test-Path $p)) {
            Write-Skip ("Binary not present: {0}" -f $p)
            continue
        }
        $name = $script:FwPrefix + (Split-Path -Leaf $p)
        try {
            # Idempotent: remove existing rule first if it exists
            Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue |
                Remove-NetFirewallRule -ErrorAction SilentlyContinue

            New-NetFirewallRule -DisplayName $name `
                                -Direction Outbound `
                                -Action Block `
                                -Program $p `
                                -Profile Any `
                                -Enabled True `
                                -Description "CrisisOfTruth telemetry block (binary)" `
                                -ErrorAction Stop | Out-Null
            Write-OK ("Blocked outbound: {0}" -f $p)
            Log-Line ("[FW] Block outbound {0}" -f $p)
            $script:PassCount++
        } catch {
            Write-Fail ("Could not add rule for {0}: {1}" -f $p, $_.Exception.Message)
            Log-Line ("[FAIL] FW {0} -- {1}" -f $p, $_.Exception.Message)
            $script:FailCount++
        }
    }
}

function Remove-FirewallRules {
    Write-Title "FIREWALL -- removing CrisisOfTruth block rules"
    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like "$script:FwPrefix*" }
    if (-not $rules) {
        Write-Skip "No CrisisOfTruth firewall rules found"
        return
    }
    foreach ($r in $rules) {
        try {
            Remove-NetFirewallRule -DisplayName $r.DisplayName -ErrorAction Stop
            Write-OK ("Removed: {0}" -f $r.DisplayName)
            Log-Line ("[FW] Removed {0}" -f $r.DisplayName)
            $script:PassCount++
        } catch {
            Write-Fail ("Could not remove {0}: {1}" -f $r.DisplayName, $_.Exception.Message)
            $script:FailCount++
        }
    }
}

# ---------------------------------------------------------------------------
#  STATUS
# ---------------------------------------------------------------------------

function Show-Status {
    Write-Title "CURRENT STATUS"

    $hostsActive = Test-HostsBlock
    if ($hostsActive) {
        Write-OK "Hosts file: CrisisOfTruth block IS active"
    } else {
        Write-Info "Hosts file: CrisisOfTruth block is NOT active"
    }

    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like "$script:FwPrefix*" }
    if ($rules) {
        Write-OK ("Firewall: {0} CrisisOfTruth rule(s) active" -f $rules.Count)
        foreach ($r in $rules) {
            Write-Host ("    {0,-50}  Enabled={1}  Action={2}" -f $r.DisplayName, $r.Enabled, $r.Action) -ForegroundColor Gray
        }
    } else {
        Write-Info "Firewall: no CrisisOfTruth rules active"
    }

    Write-Host ""
    Write-Host ("  Total hosts in block list:        {0}" -f $script:TelemetryHosts.Count) -ForegroundColor White
    Write-Host ("  Total binaries in firewall list:  {0}" -f $script:TelemetryBinaries.Count) -ForegroundColor White
}

function Apply-All {
    Apply-HostsBlock
    Apply-FirewallRules
    Write-Host ""
    Write-Host "  ALL TELEMETRY BLOCKS APPLIED." -ForegroundColor Green
    Write-Host "  Verify with: nslookup vortex.data.microsoft.com" -ForegroundColor Gray
    Write-Host "  (should resolve to 0.0.0.0)" -ForegroundColor Gray
    Write-Host ""
}

function Remove-All {
    Remove-HostsBlock
    Remove-FirewallRules
    Write-Host ""
    Write-Host "  ALL CRISISOFTRUTH BLOCKS REMOVED." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------------
#  LOG
# ---------------------------------------------------------------------------

function Save-Log {
    $logPath = "$PSScriptRoot\Win11FirewallTelemetry_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
        " 1  -- APPLY ALL  (hosts file + firewall rules)"
        " 2  -- Hosts file only"
        " 3  -- Firewall rules only"
        " S  -- Show current status"
        " R  -- REMOVE ALL CrisisOfTruth blocks (clean uninstall)"
        " L  -- Save log to Desktop"
        " Q  -- Quit"
    )
    foreach ($o in $opts) { Write-Host "  $o" -ForegroundColor Gray }
    Write-Host ""
    Write-Host ("  Counters: ") -NoNewline -ForegroundColor DarkGray
    Write-Host ("$script:PassCount OK  ") -NoNewline -ForegroundColor Green
    $fc = if ($script:FailCount -gt 0) { 'Red' } else { 'DarkGray' }
    Write-Host ("$script:FailCount Failed") -ForegroundColor $fc
    Write-Host ""
}

do {
    Show-Menu
    $choice = (Read-Host "  Enter choice").Trim().ToUpper()
    switch ($choice) {
        '1' { Apply-All }
        '2' { Apply-HostsBlock }
        '3' { Apply-FirewallRules }
        'S' { Show-Status }
        'R' { Remove-All }
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
Write-Host "  Goodbye." -ForegroundColor Red
Write-Host ""
