# WindowsSpy - Quick Start

**For people who just got a new Windows PC and want to know what Microsoft is doing to it.**

You don't need to be technical to use this. You just need 5 minutes.

---

## What this is

WindowsSpy is a **record-keeper**, not a system modifier (by default). It watches what Windows is doing on your PC and writes it down so you can see for yourself. No registry edits, no service disabling, no policy changes - just a record.

Once you've watched for a week or two, you'll have evidence about what Microsoft is actually changing on your machine after each Windows Update. Then, if you decide you want to push back on any of it, the toolkit has hardening options too. But that comes later, after you've observed.

---

## What you'll do (5 minutes)

1. Open the folder where you saved WindowsSpy
2. Right-click `RunWindowsSpy.bat` and pick **"Run as administrator"**
3. Type `AGREE` at the disclaimer prompt (read it first)
4. At the main menu, press `O` for **Observe Mode**
5. Type `YES` when it asks if you want to proceed
6. Wait about 30 seconds while it takes a baseline snapshot
7. When asked, type `YES` to install the weekly automatic check
8. Done

That's it. WindowsSpy will now quietly take a snapshot every Sunday morning and write a one-page report to your Desktop. You don't have to do anything else.

---

## What happens next

**Every Sunday at 3 AM**, a small task runs in the background. It takes a fresh snapshot of your settings, compares it to last week's, and writes a plain-text report to your Desktop with a filename like:

```
WindowsSpy_Weekly_2026-05-25.txt
```

Open it in Notepad. It's written in plain English. You'll see things like:

```
APPS APPEARED (Microsoft installed these silently):
  + Microsoft.Clipchamp.Clipchamp
  + Microsoft.BingNews

PRIVACY/TELEMETRY SETTINGS CHANGED:
  Telemetry: AllowTelemetry  0 -> 1
```

That's all you need to read. You'll know what Windows is doing.

---

## After a month

Run `RunWindowsSpy.bat` again, press `T` at the menu (View Timeline), and you'll get **one report covering everything that's changed since your baseline**. This is the full picture - not just "this week" but "everything Microsoft has done since you installed me."

You can show this to friends, save it as evidence, or just read it to understand what's normal vs. what's intrusive.

---

## If you want to push back

After observing, if you've decided you want to actually block some of what you're seeing:

1. Run `RunWindowsSpy.bat` again
2. Press `H` for the Hardening Menu
3. Pick the area you want to address (Privacy, Performance, etc.)

The hardener will modify your system. Your baseline snapshot is your safety net - if anything breaks, press `U` (Snapshot Restore) to roll everything back.

**The right order is: observe first, decide what bothers you, then harden selectively.** Don't run hardeners on a brand new PC just because they're there.

---

## Where things live

- **Snapshots:** `Documents\Win11Hardener\`
- **Weekly reports:** `Desktop\WindowsSpy_Weekly_*.txt`
- **Timeline reports:** `Desktop\WindowsSpy_Timeline_*.txt`
- **Diff reports:** `Desktop\Win11Diff_*.txt`
- **Per-run logs (Audit / Hardener / App Installer):** the WindowsSpy folder itself

You can safely delete any report file - they're just text. **Do not delete the snapshots in Documents\Win11Hardener\** - those are your historical record.

---

## Common questions

**Q: Does this collect data about me?**
A: No. WindowsSpy has zero telemetry of its own. Everything it captures stays on your PC, in plain text files you can read.

**Q: Will it slow down my PC?**
A: The weekly task takes about 90 seconds, runs at 3 AM, and uses minimal resources. No impact on day-to-day use.

**Q: Will it break my computer?**
A: Observe Mode makes no system changes - it cannot break anything. The Hardening features can theoretically cause issues, but the snapshot system lets you undo any change.

**Q: I already hardened my PC with a different tool. Should I still use this?**
A: Yes - the audit feature (`A` in the menu) will tell you if Microsoft has silently reverted any of your hardening after a Windows Update. That's worth knowing.

**Q: Can I uninstall the weekly task?**
A: Yes. Run `RunWindowsSpy.bat`, press `W`, and the script will offer to uninstall.

---

## For more detail

See `README.md` for the full documentation, technical details, and a complete description of what each script does.

---

*WindowsSpy is free software, no warranty, use at your own risk.*
*CrisisOfTruth.org*
