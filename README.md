# WindowsSpy

**Watch what Windows does. Decide what to do about it.**

A PowerShell toolkit for **observing** what Microsoft changes on your Windows 10/11 PC over time, with optional **hardening** if you decide to push back on what you observe.

By Brad / CrisisOfTruth.org · https://crisisoftruth.org/windowsspy

---

## What this is

Most "debloat Windows" tools take a stance first and ask questions later: they apply a long list of changes the author believes are correct, and leave you to clean up the breakage. That works for people who already trust the author's judgment, but it doesn't help curious users who just want to understand what's actually happening on their PC.

WindowsSpy starts somewhere different. It's a **record-keeper**. Install it, run Observe Mode, and it captures a complete baseline of how your PC is configured right now. Then, weekly (or whenever you ask), it takes a fresh snapshot, compares it to the baseline, and writes a plain-text report of what changed. You see the evidence in plain English: which apps Microsoft silently installed, which settings reverted after the last Windows Update, which services started running again.

Once you've watched for a while, you have an informed basis for action. If you want to push back, the same toolkit includes hardeners - privacy, performance, gap-closers. But the hardening is **secondary**. The primary purpose is the record-keeping.

**Observe first. Decide what bothers you. Harden selectively. Audit ongoing.**

---

## Quick start

See [QuickStart.md](QuickStart.md) for the 5-minute version.

The short version:

1. Right-click `RunWindowsSpy.bat` -> Run as administrator
2. Type `AGREE`, then press `O` (Observe Mode)
3. Type `YES` twice (baseline snapshot + weekly task)
4. Done. Reports appear on your Desktop every Sunday.

---

## Architecture

WindowsSpy ships as a single folder containing one batch launcher and a set of PowerShell scripts. The launcher self-elevates to Administrator (required to read HKLM and service state) and provides a menu of all the actions. Every action is also runnable standalone if you prefer.

```
WindowsSpy/
+-- RunWindowsSpy.bat            <- main launcher
+-- QuickStart.md                <- 5-minute new-user guide
+-- README.md                    <- this file
|
+-- [ OBSERVATION - read-only ]
|   +-- Win11Observe.ps1         <- first-run wizard
|   +-- Win11Snapshot.ps1        <- captures current state
|   +-- Win11Diff.ps1            <- compares two snapshots
|   +-- Win11Timeline.ps1        <- cumulative readable report
|   +-- Win11Audit.ps1           <- detects post-update drift
|   +-- Win11WeeklyTask.ps1      <- runs unattended each week
|   +-- Win11ScheduleWeekly.ps1  <- installer for the weekly task
|   +-- Win11SnapshotRestore.ps1 <- revert to a saved snapshot
|
+-- [ SETUP - new-PC convenience, optional ]
|   +-- Win11FreshInstall.ps1    <- Explorer/taskbar/Start-menu cleanup
|
+-- [ HARDENING - modifies your system ]
    +-- Win11PrivacyHardener.ps1
    +-- Win11PerfHardener.ps1
    +-- Win11PrivacyHardener_Extras.ps1
    +-- Win11ProHardener.ps1
    +-- Win11FirewallTelemetry.ps1
    +-- Win11Restore.ps1         <- selective re-enable (OneDrive, etc.)
    +-- Win11AppDefaults.ps1     <- file associations
```

All `.ps1` files are pure 7-bit ASCII with CRLF line endings. No installer. No telemetry of its own. No binary blobs. Open any file and read it before you run it.

---

## The two modes

### Observation mode (read-only)

Captures, compares, and reports. Makes **zero** changes to your system. The categories tracked:

- **Registry values** - ~150 keys covering telemetry, ads, Cortana, OneDrive, Recall, Copilot, search, cloud content
- **Services** - ~30 services including per-user service templates that re-spawn with random suffixes
- **Scheduled tasks** - 11 Microsoft telemetry-related tasks
- **AppX packages** - complete inventory of installed and provisioned apps (this is how you spot Microsoft silently installing Clipchamp / Teams / BingNews after an update)
- **DNS** - per-adapter DNS server configuration
- **Network tuning** - TCP autotuning level
- **Power state** - active scheme GUID, hibernation file presence, Fast Startup
- **File system flags** - 8.3 names, last-access timestamps, TRIM
- **Firewall rules** - telemetry-related Windows Firewall rules
- **File associations** - via DISM export

A snapshot is a single XML file produced by PowerShell's `Export-Clixml`. Snapshots typically run 500 KB to 2 MB. Multiple snapshots over time become your record of what Microsoft did.

### Hardening mode (modifies your system)

The hardeners apply policies and disable services. They are organized into focused groups:

- **Privacy** - telemetry, ads, tracking, Cortana, OneDrive folder grabs, Recall
- **Performance** - power plan, visual effects, services, TCP tuning, GameDVR
- **Privacy Extras** - Copilot, Error Reporting, CEIP, AppCompat, full OneDrive uninstall, background apps, handwriting/speech
- **PRO** - gap-closers most consumer guides miss: Start menu Bing search, Store auto-install, NCSI probing, CompatTelRunner, CDP services, NTP, LLMNR/NetBIOS
- **Firewall + Hosts** - blocks Microsoft telemetry endpoints at the network layer
- **Restore** - selectively turn things back on (OneDrive, Cortana, Remote Desktop, Edge Sign-in, etc.) without doing a full revert

Each hardener has a verified-write helper - if a registry change fails (typically because something else is overriding the policy), it reports `[FAIL]` rather than pretending it succeeded.

---

## Launcher menu

```
[ OBSERVE -- read-only, safe for new users ]
O  --  OBSERVE MODE       (first-run wizard: baseline + weekly)
S  --  Snapshot           (capture current state -- no changes)
T  --  View Timeline      (what Microsoft did since baseline)
D  --  Diff Snapshots     (compare any two snapshots)
A  --  Audit              (check if hardening still holds)
W  --  Weekly Task Status (install/remove/check schedule)
B  --  Browse Snapshots   (open snapshot folder in File Explorer)

[ SETUP -- new-PC convenience, run before observing ]
N  --  New PC Bootstrap   (Explorer / taskbar / Start-menu cleanup)

[ HARDEN -- modifies your system ]
H  --  Hardening Menu     (privacy, performance, gap-closers)
R  --  Restore Menu       (turn things back on selectively)
U  --  Snapshot Restore   (full revert to a saved state)
F  --  Firewall + Hosts   (block telemetry endpoints)
P  --  App Defaults       (file associations / Edge PDF block)
```

The OBSERVE section is listed first and is always safe. The HARDEN section is gated by a snapshot-existence check - the launcher won't run a hardener until either a snapshot exists or you explicitly waive the check.

---

## Where files live

WindowsSpy uses three locations on your PC:

- **`%USERPROFILE%\Documents\Win11Hardener\`** - snapshots, the baseline, DISM file-association exports. **Do not delete this folder** - it's your historical record.
- **`%USERPROFILE%\Desktop\`** - user-facing reports (weekly briefings, timeline reports, diff reports). These are written for you to read. Safe to delete once read.
- **The WindowsSpy folder itself** - per-run logs (one log per execution of each hardener / audit / app installer). These are diagnostic artifacts; safe to delete any time.

All three folders are created automatically as needed.

---

## The weekly task

When you install the weekly task (Observe Mode does this automatically if you say yes), Task Scheduler gets an entry at `\WindowsSpy\WeeklyObservation` that runs:

- **Every Sunday at 3:00 AM** (waits if PC is asleep, runs when next available)
- As the currently signed-in user, with highest privileges
- Calls `Win11WeeklyTask.ps1` which: takes a snapshot, diffs against the previous week, writes a plain-English briefing to your Desktop
- Best-effort toast notification

To check / remove the task: launcher option `W`. To remove manually: open Task Scheduler, find `\WindowsSpy\WeeklyObservation`, delete it.

---

## What does NOT get changed

The toolkit is deliberately narrow. The hardeners do not touch:

- Windows Update settings. You keep getting security patches.
- Microsoft Defender. Base scanning stays on.
- SmartScreen. It catches real malware.
- Activation / licensing endpoints. Your Windows stays activated.
- Microsoft Store CDN for installs you actually want.
- Certificate revocation lists / OCSP. Cert validation needs them.
- IPv6, Spectre/Meltdown mitigations, or any "make it faster by making it less safe" tweaks.
- Anything that would break enterprise management on a domain-joined machine. WindowsSpy is for personal/standalone PCs; on a domain-managed machine, group policy will overwrite most settings within minutes (and rightly so).

---

## Privacy

WindowsSpy has zero telemetry of its own. It does not:

- Phone home to any server
- Collect crash reports
- Upload your data anywhere
- Talk to the internet at all, except via the hosts/firewall script which only EDITS local rules

Everything captured stays on your PC, in files you can read. The snapshot XML is plain serialized PowerShell objects - readable in any text editor. Reports are plain ASCII text. If you want to email a report to a friend, that's your call; nothing happens automatically.

---

## Updating, modifying, sharing

If you fork these scripts or contribute additions, two encoding rules are non-negotiable:

1. **Pure 7-bit ASCII.** No em-dashes, no curly quotes, no emoji, no accented characters, nothing above byte 0x7F. PowerShell's parser misinterprets non-ASCII when scripts are transferred between systems.
2. **CRLF line endings.** Windows-native. LF-only line endings can break things in subtle and intermittent ways, especially in `.bat` files.

Use Notepad (gets both right by default) or Notepad++ with the appropriate settings. The .md files in this repository use UTF-8 with LF endings, which is standard for Markdown - that's the only exception.

If you find a setting WindowsSpy doesn't track or a hardener it doesn't reverse, open an issue at https://github.com/smogmanus1/windowsspy/issues or send a pull request. The scripts are public-domain in spirit - treat them as a starting point, not a final answer.

---

## Common needs (cheat sheet)

| Want to ... | Do this |
|---|---|
| See what changed this week | Open the latest `Desktop\WindowsSpy_Weekly_*.txt` |
| See everything since baseline | Launcher option `T` (View Timeline) |
| Compare two specific snapshots | Launcher option `D` (Diff) |
| Check if hardening held | Launcher option `A` (Audit) |
| Stop the weekly task | Launcher option `W` -> Uninstall |
| Take an ad-hoc snapshot | Launcher option `S` |
| Restore one feature (OneDrive, Cortana, RDP, etc.) | Launcher option `R` |
| Full revert to factory-like state | Launcher option `U` (Snapshot Restore) |
| Re-enable Hibernate | Option `R` -> 1 |
| Re-enable Location | Option `R` -> 2 |
| Re-enable Edge Sign-in | Option `R` -> 10 |

---

## Legal disclaimer

This software is provided **FREE OF CHARGE** for educational and informational purposes **ONLY**.

I, Brad at CrisisOfTruth.org, accept **ABSOLUTELY NO** responsibility or liability for any damage, data loss, system instability, software incompatibility, or **ANY** other consequence - intended or unintended - that results from running these scripts on your system.

**YOU RUN THIS SOFTWARE ENTIRELY AT YOUR OWN RISK.**

By running any part of this toolkit you confirm that:

1. You have read and accept this disclaimer in full.
2. You understand that Hardening features modify Windows system settings.
3. You alone are responsible for the outcome.
4. CrisisOfTruth.org is held harmless for any result.

The launcher requires you to type `AGREE` before proceeding, and to take a snapshot before any hardening action (or explicitly waive that check). Those prompts exist for a reason. Do not type around them.

---

## Why this exists

Microsoft has gradually moved Windows from an operating system into a data-collection platform. The defaults assume you consent to telemetry, to advertising profiling, to silent app installs, to cloud-syncing of settings and clipboard, to having a generative-AI feature (Recall) screenshot your desktop every few seconds. Most of these defaults can be turned off. None of them can be turned off in one place. None of them are documented to ordinary users in any clear way.

Existing "debloat" tools assume you're already convinced. That's a small audience. **WindowsSpy is for the much larger audience that's merely curious** - people who've heard vague concerns, who just got a new PC, who want to keep tabs on what their machine is doing without committing to a particular ideology about it.

Observing doesn't require trust in the author. The evidence speaks for itself. If a Windows Update silently re-enables telemetry that you'd disabled, the weekly report will say so. If Microsoft installs Clipchamp on you in the middle of the night, the weekly report will say so. You decide what to do with the information.

WindowsSpy doesn't tell you what to think. It shows you what's happening.

---

## Credits

- Original hardener concept and execution: Brad / CrisisOfTruth.org
- Observation mode, diff engine, timeline, weekly task: developed iteratively with AI assistance, then hand-verified
- Inspired by long-running frustration with the gap between "Windows defaults" and "Windows defaults that respect the user"

If WindowsSpy is useful to you, share it. The more eyes on Microsoft's behavior, the less they can do quietly.

-- Brad
   CrisisOfTruth.org / WindowsSpy
