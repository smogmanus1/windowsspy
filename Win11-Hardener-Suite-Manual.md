# Win11 Hardener Suite — Manual
**CrisisOfTruth.org**
Covers: `RunHardener.bat`, `Win11PrivacyHardener.ps1`, `Win11PrivacyHardener_Extras.ps1`, `Win11PerfHardener.ps1`, `Win11Restore.ps1`, `Win11Audit.ps1`

This document has two parts. **Part 1 (User Manual)** is for anyone running the suite. **Part 2 (Technical Manual)** is for whoever maintains or extends the code — a "smart computer friend" who wants to know exactly how it works, not just how to click through it.

---

# PART 1 — USER MANUAL

## 1.1 What this suite does

Six files work together to give you two things:

1. **Control** — turn off Windows telemetry, ads, tracking, forced Edge/Copilot behavior, and background bloat; tune performance.
2. **Visibility** — a read-only audit that tells you when Microsoft (usually via Windows Update) quietly turns your settings back on.

Nothing runs silently. Every script prints what it's doing line by line and writes a timestamped log to your Desktop.

## 1.2 Requirements

- Windows 10 or 11, administrator account
- PowerShell (built in) — the `.bat` launcher and every `.ps1` script self-elevate (UAC prompt) automatically, so you don't need to manually "Run as Administrator"
- All six files in the **same folder**
- **A backup taken before you run anything.** The launcher will ask you to confirm this and won't let you skip past it without answering.

## 1.3 File layout

Keep these together in one folder, e.g. `E:\harden-pc\`:

```
RunHardener.bat                     <- start here
Win11PrivacyHardener.ps1
Win11PrivacyHardener_Extras.ps1
Win11PerfHardener.ps1
Win11Restore.ps1
Win11Audit.ps1
```

## 1.4 First run — walkthrough

Double-click `RunHardener.bat`.

**Screen 1 — Disclaimer.** You must type `AGREE` to continue. This is a legal liability screen; CrisisOfTruth.org accepts no responsibility for outcomes.

**Screen 2 — Backup warning.** You must type `YES` (confirming you've backed up) to continue. Recommended tools are listed: Acronis (perpetual license, not subscription), Macrium Reflect Free, Veeam Agent Free. A Windows System Restore point is explicitly called out as *not* a substitute for a real backup. Note: if you only intend to run the read-only Audit, a backup isn't strictly required, but the launcher doesn't currently branch around this screen for that case — you'll still need to answer YES/NO.

**Screen 3 — Final confirmation.** Type `RUN` to reach the main menu.

**Main menu:**

| Key | Action |
|---|---|
| `1` | Privacy Hardener (telemetry, ads, tracking, OneDrive) |
| `2` | Performance Hardener (power, visual effects, network, gaming) |
| `3` | Privacy EXTRAS (Copilot, deeper telemetry, cloud content, background apps, full OneDrive removal) |
| `4` | Run all three back-to-back |
| `A` | **Audit** — read-only, detects drift, no changes made |
| `R` | Restore menu — turn Hibernate / Location back on |
| `Q` | Quit |

Each hardener script (`1`, `2`, `3`) opens its **own** menu once launched — see §1.5–1.7. After any hardener finishes, the launcher tells you a reboot is recommended and returns you to the main menu.

## 1.5 Privacy Hardener (option 1)

Opens a 14-item menu (plus `R`, `L`, `Q`). Option `1` inside that menu runs everything **and creates a System Restore point first**. You can also run individual groups:

2. Telemetry & Diagnostics — kills DiagTrack/dmwappushsvc services, sets `AllowTelemetry=0`, disables related scheduled tasks, clears the diagnostic cache
3. Ads, Suggestions & Start Menu Tracking
4. Activity History & Timeline
5. Delivery Optimization (stops your bandwidth being used to seed updates to strangers)
6. SysMain / SuperFetch (fixes high disk usage on some SSD setups)
7. Cortana
8. Edge Browser Forcing (first-run screen, search widget, News/Interests, startup boost, background mode)
9. OneDrive (blocks silent folder redirection, removes from startup)
10. Location, Camera & Microphone (denies at the app-permission policy level)
11. DNS Privacy — switches all active adapters to Cloudflare (1.1.1.1 / 1.0.0.1) and enables DNS-over-HTTPS auto-upgrade
12. Windows Recall (disables the optional feature + policy key)
13. Remote Access (disables RDP, Remote Registry, Remote Assistance)
14. Bloatware Removal (~20 packages: Xbox apps, Solitaire, Office Hub, Teams, Spotify, TikTok, Disney+, etc. — removes both installed and provisioned copies)

`R` on its own just creates a restore point without applying tweaks. `L` saves the session log to your Desktop.

## 1.6 Privacy EXTRAS (option 3)

A separate, deeper pass — things the base Privacy Hardener doesn't touch:

2. Copilot (machine + user policy, taskbar button, Edge sidebar)
3. Telemetry reinforcement (AutoLogger boot trace, Windows Error Reporting, CEIP, AppCompat inventory/PCA/AIT, PcaSvc)
4. Cloud Content / Find My Device / Settings Sync / cross-device clipboard / Maps auto-download
5. Handwriting, inking & speech (implicit collection, contact harvesting, online speech recognition)
6. Edge's own telemetry (separate from Edge Forcing in the base script — metrics, diagnostic data, shopping assistant, autofill, sign-in/sync)
7. Background apps & Wi-Fi Sense
8. **OneDrive full uninstall** — this is destructive to the OneDrive *application*, not your files: stops processes, runs `OneDriveSetup.exe /uninstall`, deletes the local OneDrive folders/cache, unpins it from Explorer's sidebar, removes its scheduled tasks, and blocks reinstall via policy.

⚠️ **Read before running option 8:** if you have files that only exist inside your OneDrive folder and haven't finished syncing/verifying elsewhere, back them up first. This step removes the local OneDrive folder structure.

## 1.7 Performance Hardener (option 2)

10-item menu:

2. Power Plan — activates the hidden **Ultimate Performance** plan, disables USB selective suspend and HDD spin-down, forces CPU minimum state to 100%, disables Hibernate (frees the `hiberfil.sys` space — note this is the opposite of the Restore script's Hibernate option, see §1.8)
3. Visual Effects & Animations
4. Unnecessary Background Services (Fax, Xbox services, Insider Service, Parental Controls, Retail Demo, ICS, legacy NetBIOS helper, link tracking, Maps broker, Phone, Mobile Hotspot — plus DiagTrack/SysMain again as a backup disable)
5. Startup Program Cleanup (removes common bloat from the Run key: Discord, Spotify, Epic, Steam, Teams, Skype, etc. — **not** aimed at OneDrive here)
6. Disk & Memory (confirms TRIM, disables 8.3 filenames and last-access timestamps, favors programs over cache, clears Temp/Prefetch, runs Optimize-Volume on fixed drives)
7. Network Performance (disables Nagle's algorithm, enables TCP auto-tuning and RSS, removes throttling index, increases IRPStackSize for SMB shares, flushes DNS)
8. Gaming Performance (disables Game Bar/DVR, enables Hardware-Accelerated GPU Scheduling, disables fullscreen optimizations, raises game process priority, disables mouse acceleration)
9. Scheduled Task Cleanup
10. Fast Startup & Boot (disables Fast Startup, enables verbose boot status, sets a 3-second boot menu timeout, enables all logical cores at boot)

## 1.8 Restore Helper (main menu `R`)

For the two settings you may want back after hardening:

1. Restore Hibernate — `powercfg -h on` plus registry flags so it reappears in the Start/Power menu
2. Restore Location — lifts the group policy block, re-allows at the consent layer, and restarts the `lfsvc` service
3. Restore Fast Startup (optional — the Perf Hardener disables it deliberately because it can cause driver/update issues; Hibernate works fine without it)
4. Restore both 1 and 2 together

## 1.9 Audit (main menu `A`)

**Makes zero changes.** Run this any time — especially right after a Windows Update — to see what Microsoft silently reverted.

It checks every setting the three hardener scripts touch, plus:
- Windows Update history for the last 60 days and your current build number (so you can pin drift to a specific KB)
- Bloatware reinstallation
- DNS drift back off Cloudflare, per network adapter
- OneDrive re-appearing after a full uninstall

Each item is tagged:

| Tag | Meaning |
|---|---|
| `[OK]` | Setting matches what the hardener set |
| `[REVERT]` | Setting has drifted back to Microsoft's default |
| `[REINST]` | A removed app package is back |
| `[NOTSET]` | Key was never present — either you haven't run that hardener group yet, or it's genuinely absent |

At the end you get a summary with counts and a list of **which hardener menu options** to re-run to fix what drifted. A full report saves automatically to your Desktop as `Win11Audit_<timestamp>.log`. Two rows are explicitly flagged as "skip if intentional": Location and Hibernate, since the Restore Helper is meant to re-enable those on purpose.

## 1.10 Logs

Every script writes its own timestamped log to `%USERPROFILE%\Desktop`:

- `Win11Privacy_<timestamp>.log`
- `Win11PrivacyExtras_<timestamp>.log`
- `Win11Perf_<timestamp>.log`
- `Win11Restore_<timestamp>.log`
- `Win11Audit_<timestamp>.log`

You can also press `L` in any menu to save on demand without quitting.

## 1.11 Recommended workflow

1. Back up (real image backup, not just a restore point).
2. Run `RunHardener.bat` → option `4` (all three, back-to-back) for a first pass, or cherry-pick groups if you want to go slower.
3. Reboot.
4. If you want Hibernate or Location back, run `R` from the main menu.
5. After any major Windows Update, run `A` (Audit) and re-apply whatever it flags.

---

# PART 2 — TECHNICAL MANUAL

## 2.1 Architecture overview

All five `.ps1` scripts are independent, self-elevating, menu-driven PowerShell programs that share an identical internal pattern:

```
Self-elevate (UAC) → StrictMode + $ErrorActionPreference='SilentlyContinue'
  → define helper functions (Write-OK/Fail/Info/Title, Invoke-Tweak, Set-Reg, Disable-Svc, [Disable-SchdTask])
    → define one function per tweak group ("Invoke-XTweaks")
      → Show-Menu loop reads a keypress and dispatches to the matching Invoke-XTweaks function
        → Save-Log writes $script:Log to the Desktop on demand or at natural exit points
```

`RunHardener.bat` is a pure orchestration layer: three gated confirmation screens (`AGREE` / `YES` / `RUN`), then a menu that shells out to `powershell -NoProfile -ExecutionPolicy Bypass -File <script>.ps1` for each choice. It never touches the registry itself.

### 2.1.1 Self-elevation pattern (identical in every .ps1)

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process PowerShell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
    exit
}
```

This re-launches the same file elevated and exits the non-elevated instance. Because it relies on `$MyInvocation.MyCommand.Path`, the script **must be run from a saved `.ps1` file on disk** — it will not self-elevate correctly if pasted directly into an interactive console.

### 2.1.2 The `Invoke-Tweak` wrapper

Every individual change is wrapped:

```powershell
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
```

This gives consistent console output, running pass/fail counters shown in the menu footer, and a structured log line per action — but see **2.6 Known limitation** below regarding what "OK" actually verifies.

### 2.1.3 `Set-Reg` — the shared registry writer

```powershell
function Set-Reg {
    param([string]$Path, [string]$Name, [object]$Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}
```

Creates the key path if missing, then sets the value. Default type is `DWord`; callers override with `'String'` or `'Binary'` where needed (e.g. `MinAnimate`, `UserPreferencesMask`).

### 2.1.4 `Disable-Svc`

```powershell
function Disable-Svc {
    param([string]$Name)
    if (Get-Service -Name $Name -ErrorAction SilentlyContinue) {
        Stop-Service  -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service   -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
    } else {
        Write-Info "    Service '$Name' not found -- skipping"
    }
}
```

Stops then disables. Silently no-ops if the service doesn't exist on this SKU/build — this is intentional, since some services (e.g. `WpcMonSvc`) aren't present on every edition.

### 2.1.5 Library mode (`Win11PrivacyHardener_Extras.ps1 -AsLibrary`)

The Extras script is designed to be dot-sourced into the base Privacy Hardener rather than run standalone:

```powershell
. "$PSScriptRoot\Win11PrivacyHardener_Extras.ps1" -AsLibrary
```

When `-AsLibrary` is passed, the script:
- Skips self-elevation and `Set-StrictMode`/`$ErrorActionPreference` (assumes the parent already set these)
- Skips redefining helpers if they already exist (`if (-not (Get-Command Write-OK ...))`) — this makes it safe to dot-source into a session that already loaded the base hardener's identical helpers without collision
- Skips its own menu loop entirely (`if (-not $AsLibrary) { ... menu ... }`)

**Current state:** the suite as shipped does *not* actually use this integration — `RunHardener.bat` launches `Win11PrivacyHardener_Extras.ps1` as its own standalone process (option 3), not dot-sourced into option 1. The `-AsLibrary` path exists but is unused by the launcher. If merging them, remember the two scripts define an identically-named `Invoke-Tweak`/`Set-Reg`/etc. set — dot-sourcing after the base script has already run is what makes the `Get-Command` guard necessary.

## 2.2 Fix-group naming contract (Hardener ↔ Audit)

This is the most important cross-file contract in the suite and it is **not enforced by code** — it's a naming convention you have to maintain by hand.

`Win11Audit.ps1` tags every check with a `$FixGroup` string, e.g.:

```powershell
$g = 'Privacy menu opt 2 (Telemetry)'
Check-Service 'DiagTrack' 'DiagTrack service disabled' $g
```

When a check fails, that literal string gets added to `$script:RevertedList` and printed in the final summary as "re-run this to fix it." These strings are **hand-typed to match the menu option labels** in `Win11PrivacyHardener.ps1`, `Win11PrivacyHardener_Extras.ps1`, and `Win11PerfHardener.ps1`. There is no shared constant, enum, or lookup table between the four scripts.

**Practical consequence for maintenance:** if you renumber or rename a menu option in any hardener script, you must manually find and update every matching `$g = '...'` string in `Win11Audit.ps1`, or the audit's "what to run" guidance will point at a stale/nonexistent menu label. Search `Win11Audit.ps1` for the literal option number you're changing before renumbering anything.

Current fix-group strings in use (for reference when editing):

| Fix group string | Source script / option |
|---|---|
| `Privacy menu opt 2` through `opt 14` | `Win11PrivacyHardener.ps1` options 2–14 |
| `Extras menu opt 2` through `opt 8` | `Win11PrivacyHardener_Extras.ps1` options 2–8 |
| `Perf Hardener (option 2 in launcher)` | `Win11PerfHardener.ps1`, several groups collapsed under one label |

Note the Perf Hardener audit coverage (`Audit-PerfHardener`) is intentionally partial — it only checks the items most likely to drift (transparency, taskbar animation, hibernate state, fast startup, GameDVR, HAGS, verbose boot status), not the full 10-option surface (services, network, disk, scheduled tasks aren't individually audited).

## 2.3 `Win11Audit.ps1` check primitives

Three parametrized check functions do all the work:

**`Check-Reg`** — reads a registry value and compares against an expected value. Numeric-aware (`[int64]` cast if the stored type looks numeric, else string compare). Three possible outcomes: `NOTSET` (path or value missing — ambiguous between "never hardened" and "genuinely absent"), `OK` (matches), `REVERT` (present but different).

**`Check-Service`** — `OK` if the service is absent *or* `StartType -eq 'Disabled'`; `REVERT` otherwise. Treating "absent" as OK mirrors `Disable-Svc`'s own no-op behavior for services not present on this SKU.

**`Check-AppxAbsent`** — `OK` if `Get-AppxPackage -AllUsers` finds nothing; `REINST` (a distinct tag from `REVERT`) if found. This is deliberately a separate counter (`$script:ReinstCount`) from `$script:RevertCount` in the summary.

**`Check-DNS`** — the only check that iterates dynamically over live state (`Get-NetAdapter | Where Status -eq 'Up'`) rather than a fixed key. Flags any active adapter whose DNS server list doesn't contain `1.1.1.1` or `1.0.0.1`. This is why DNS drift can appear per-adapter (e.g. Wi-Fi adapter never touched because it wasn't "Up" when the hardener ran, or a VPN adapter added afterward).

Everything funnels into `$script:Log` (full detail, written to the `.log` file) and colored console output separately — the two are not always textually identical (console adds "(now: X, want: Y)" formatting; log uses `now=X want=Y`).

## 2.4 Bloatware list — kept in sync manually in three places

The same ~20-package array appears independently in:
- `Win11PrivacyHardener.ps1` → `Invoke-BloatwareTweaks`
- `Win11Audit.ps1` → `Audit-Bloatware`

These are copy-pasted, not shared via a common file/module. If you add or remove a package from the removal list, update the audit list too, or the audit will report packages as drifted/reinstalled that were never targeted for removal (false REINST), or silently ignore new removals (false OK — since the audit only checks what it's told to check).

Removal itself (`Invoke-BloatwareTweaks`) targets both layers per package:
```powershell
Get-AppxPackage -Name $pkg -AllUsers | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers }
Get-AppxProvisionedPackage -Online | Where DisplayName -eq $pkg | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName }
```
Removing only the installed package (not the provisioned one) is why bloatware sometimes reappears for *new* user profiles even without a Windows Update — the provisioned copy re-provisions it. Both removal calls are present here, which is correct.

## 2.5 Restore Helper — inverse-of relationships

`Win11Restore.ps1` doesn't re-run the hardener in reverse; it hand-codes the inverse of two specific tweak groups:

| Hardener action | Restore action |
|---|---|
| `Invoke-PowerTweaks`: `powercfg -h off` | `Invoke-HibernateRestore`: `powercfg -h on` + `ShowHibernateOption`/`FlyoutMenuSettings` registry flags |
| `Invoke-LocationTweaks`: `DisableLocation=1` policy + `lfsvc` status=0 | `Invoke-LocationRestore`: removes the policy value entirely (not set to 0), sets consent-layer keys, flips `lfsvc` status to 1, sets service to Automatic and starts it |
| `Invoke-BootTweaks`: `HiberbootEnabled=0` | `Invoke-FastStartupRestore`: `HiberbootEnabled=1` |

Note the asymmetry on Location: the hardener sets a policy DWord to `1`; the restore doesn't set it to `0`, it **removes the value** (`Remove-ItemProperty`). Functionally equivalent for that one key (absence = not-blocked), but worth knowing if you're diffing registry state rather than trusting the Audit script's own logic — `Check-Reg` treats "absent" as `NOTSET`, not `OK`, so **running the Audit after using Restore will show Location as `[NOTSET]`, not `[OK]`**, even though it's correctly restored. This is a cosmetic false-flag in the current audit logic worth being aware of, not a functional bug.

Only two of the many hardener groups have a Restore counterpart. Nothing exists to reverse DNS, telemetry, ads, Cortana, Edge forcing, OneDrive, bloatware removal, or any Extras/Perf group other than Hibernate/Fast Startup — those require either manually reversing individual `Set-Reg` calls or a full System Restore.

## 2.6 Known limitation: unverified registry writes

`Set-Reg` calls `Set-ItemProperty` under global `$ErrorActionPreference = 'SilentlyContinue'`. Combined with `Invoke-Tweak`'s `try/catch`, this means:

- `Set-ItemProperty` failures that would normally throw a *terminating* error are suppressed by `-SilentlyContinue` and **never reach the `catch` block**.
- `Invoke-Tweak` reports `[OK]` / `Done` regardless of whether the underlying write actually succeeded.

This matters most for `HKLM:\...` writes when, for any reason, the elevated token doesn't have the access expected (locked-down GPO-managed keys, EDR/AV interception, WMI filtering, some multi-user/RDP session contexts) — the script will log success while the registry is unchanged. It's also why `Win11Audit.ps1` exists as a separate read-only cross-check rather than trusting the hardener's own `[OK]`/`[FAIL]` counts: **always treat the Audit script's findings as the source of truth for whether a tweak actually took, not the hardener's own pass/fail log.**

If hardening this further: wrap `Set-Reg` to read back the value immediately after writing and compare, then have `Invoke-Tweak` fail (not just log) on mismatch — rather than relying on exception propagation that `SilentlyContinue` defeats.

## 2.7 Edge policy caveat

`BrowserSignin` and `SyncDisabled` under `HKLM:\SOFTWARE\Policies\Microsoft\Edge` (set in both `Invoke-EdgeTweaks` in the base script and `Invoke-EdgeTelemetryTweaks` in Extras) are read by Edge at process start, not polled live. Registry write succeeding is not sufficient — **all `msedge.exe` processes must be fully terminated** (not just windows closed; background mode can keep the process alive, which is itself one of the settings being disabled in the same run) before the policy takes effect. Neither script currently automates this kill step; it's a manual "close Edge fully / reboot" requirement worth calling out in the console output if extending this section.

## 2.8 Encoding requirements for editing these files

If you edit any `.ps1`/`.bat` file in this suite: save as **pure 7-bit ASCII with CRLF line endings**. No smart quotes, no em dashes, no emoji — these corrupt silently on transfer to Windows and produce confusing parse errors far from the actual bad character. Verify at the byte level (e.g. a quick Python script checking every byte is `< 128` and every line ending is `\r\n`) before treating an edit as done. `.md` documentation files (like this one) are the exception — UTF-8/LF is fine for those.

## 2.9 Extending the suite — checklist for adding a new tweak group

1. Add `Invoke-<Name>Tweaks` to the relevant hardener script, following the `Write-Title` → series of `Invoke-Tweak` blocks pattern.
2. Add it to that script's `Show-Menu` option list and `switch` dispatch, and to the "run everything" branch (`'1'` in Privacy/Perf, `Invoke-AllExtraPrivacyTweaks` in Extras) if it should be included in a full run.
3. Add a matching `Audit-<Name>` function to `Win11Audit.ps1` using `Check-Reg`/`Check-Service`/`Check-AppxAbsent` as appropriate, with a `$FixGroup` string that **exactly matches** the new menu label (see §2.2).
4. Call the new `Audit-<Name>` function from the `# -- MAIN --` block at the bottom of `Win11Audit.ps1`.
5. If the tweak should be reversible, add a matching `Invoke-<Name>Restore` to `Win11Restore.ps1` and a menu entry there.
6. Re-save all touched `.ps1` files as ASCII/CRLF (§2.8) before testing on a real machine.
7. Test the full loop: run the tweak → run the Audit and confirm `[OK]` → manually revert the registry value → run the Audit and confirm `[REVERT]` with the correct fix-group name shown.

## 2.10 Quick reference — helper function inventory

| Function | Defined in | Purpose |
|---|---|---|
| `Write-Header` / `Write-OK` / `Write-Fail` / `Write-Info` / `Write-Title` / `Write-Sep` | every hardener script (duplicated, not shared) | Console formatting |
| `Write-OK` / `Write-Reverted` / `Write-NotSet` / `Write-Reinst` / `Write-Info` / `Write-Title` | `Win11Audit.ps1` (its own separate palette) | Console formatting for audit states |
| `Invoke-Tweak` | every hardener script | Wraps one change: try/catch, counters, log line |
| `Set-Reg` | every hardener script | Create-path-if-missing + `Set-ItemProperty` |
| `Disable-Svc` | every hardener script | Stop + disable a service if present |
| `Disable-SchdTask` | Privacy Hardener, Perf Hardener | Disable scheduled tasks by path/name pattern |
| `Check-Reg` / `Check-Service` / `Check-AppxAbsent` / `Check-DNS` | `Win11Audit.ps1` only | Drift detection primitives |
| `New-RestorePoint` | Privacy Hardener only | `Enable-ComputerRestore` + `Checkpoint-Computer` |
| `Show-RecentUpdates` | `Win11Audit.ps1` only | `Get-HotFix` last 60 days + current build/DisplayVersion |

---

*End of manual. Keep this file alongside the six scripts and update it whenever a menu option, registry key, or fix-group label changes.*
