@echo off
:: ============================================================
::  WindowsSpy  --  Unified Launcher
::  Brad / CrisisOfTruth.org
::
::  "Watch what Windows does. Decide what to do about it."
::
::  This launcher puts OBSERVATION first (no system changes) and
::  HARDENING second (modifies your system, take a snapshot first).
::
::  Keep this .bat in the same folder as ALL of these scripts:
::    -- OBSERVATION (read-only, safe for new users) --
::    Win11Observe.ps1
::    Win11Snapshot.ps1
::    Win11Diff.ps1
::    Win11Timeline.ps1
::    Win11Audit.ps1
::    Win11WeeklyTask.ps1
::    Win11ScheduleWeekly.ps1
::    Win11SnapshotRestore.ps1
::    -- HARDENING (modifies your system) --
::    Win11PrivacyHardener.ps1
::    Win11PerfHardener.ps1
::    Win11PrivacyHardener_Extras.ps1
::    Win11ProHardener.ps1
::    Win11FirewallTelemetry.ps1
::    Win11Restore.ps1
::    Win11AppDefaults.ps1
::    -- SETUP (new-PC convenience) --
::    Win11FreshInstall.ps1
:: ============================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo  Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: ============================================================
::  SELF-TEST -- verify every PS1 the menu can launch is present
:: ============================================================
:SELFTEST
set MISSING=0
:: Observation scripts
if not exist "%~dp0Win11Observe.ps1"             (echo  [MISSING] Win11Observe.ps1             & set MISSING=1)
if not exist "%~dp0Win11Snapshot.ps1"            (echo  [MISSING] Win11Snapshot.ps1            & set MISSING=1)
if not exist "%~dp0Win11Diff.ps1"                (echo  [MISSING] Win11Diff.ps1                & set MISSING=1)
if not exist "%~dp0Win11Timeline.ps1"            (echo  [MISSING] Win11Timeline.ps1            & set MISSING=1)
if not exist "%~dp0Win11Audit.ps1"               (echo  [MISSING] Win11Audit.ps1               & set MISSING=1)
if not exist "%~dp0Win11WeeklyTask.ps1"          (echo  [MISSING] Win11WeeklyTask.ps1          & set MISSING=1)
if not exist "%~dp0Win11ScheduleWeekly.ps1"      (echo  [MISSING] Win11ScheduleWeekly.ps1      & set MISSING=1)
if not exist "%~dp0Win11SnapshotRestore.ps1"     (echo  [MISSING] Win11SnapshotRestore.ps1     & set MISSING=1)
:: Hardening scripts
if not exist "%~dp0Win11PrivacyHardener.ps1"     (echo  [MISSING] Win11PrivacyHardener.ps1     & set MISSING=1)
if not exist "%~dp0Win11PerfHardener.ps1"        (echo  [MISSING] Win11PerfHardener.ps1        & set MISSING=1)
if not exist "%~dp0Win11PrivacyHardener_Extras.ps1" (echo  [MISSING] Win11PrivacyHardener_Extras.ps1 & set MISSING=1)
if not exist "%~dp0Win11ProHardener.ps1"         (echo  [MISSING] Win11ProHardener.ps1         & set MISSING=1)
if not exist "%~dp0Win11FirewallTelemetry.ps1"   (echo  [MISSING] Win11FirewallTelemetry.ps1   & set MISSING=1)
if not exist "%~dp0Win11Restore.ps1"             (echo  [MISSING] Win11Restore.ps1             & set MISSING=1)
if not exist "%~dp0Win11AppDefaults.ps1"         (echo  [MISSING] Win11AppDefaults.ps1         & set MISSING=1)
:: Setup scripts (new-PC convenience)
if not exist "%~dp0Win11FreshInstall.ps1"        (echo  [MISSING] Win11FreshInstall.ps1        & set MISSING=1)
if "%MISSING%"=="1" (
    echo.
    echo  ################################################################
    echo  #                                                              #
    echo  #   ONE OR MORE SCRIPTS ARE MISSING FROM THIS FOLDER           #
    echo  #                                                              #
    echo  #   Place ALL .ps1 files listed above next to this .bat file   #
    echo  #   before continuing.                                         #
    echo  #                                                              #
    echo  ################################################################
    echo.
    pause
    exit
)

:: ============================================================
::  DISCLAIMER (one-time per session)
:: ============================================================
:DISCLAIMER
cls
echo.
echo  ################################################################
echo  #                                                              #
echo  #     WindowsSpy  --  CrisisOfTruth.org                       #
echo  #     Watch what Windows does. Decide what to do about it.    #
echo  #                                                              #
echo  ################################################################
echo.
echo  This software is provided FREE OF CHARGE for educational
echo  and informational purposes ONLY.
echo.
echo  OBSERVATION features (Snapshot, Diff, Timeline, Audit, Weekly
echo  Task) are READ-ONLY -- they make zero changes to your system.
echo  Use them freely.
echo.
echo  HARDENING features modify Windows registry settings, disable
echo  services, and change system configuration. Although they are
echo  designed to be safe, NO system modification tool is risk-free
echo  on every machine.
echo.
echo  I, Brad at CrisisOfTruth.org, accept ABSOLUTELY NO responsibility
echo  or liability for any damage, data loss, system instability, or
echo  other consequence -- intended or unintended -- that results from
echo  running these scripts on your system.
echo.
echo  YOU RUN THIS SOFTWARE ENTIRELY AT YOUR OWN RISK.
echo.
set /p AGREE="  Type AGREE to continue, or press Enter to exit: "
if /i not "%AGREE%"=="AGREE" goto DECLINED
goto MENU

:DECLINED
cls
echo.
echo  You chose not to continue. No changes were made.
echo.
pause
exit

:: ============================================================
::  MAIN MENU
:: ============================================================
:MENU
cls
echo.
echo  ================================================================
echo    WindowsSpy  --  CrisisOfTruth.org
echo    Watch what Windows does. Decide what to do about it.
echo  ================================================================
echo.
echo    NEW HERE?  Press 'O' to start with Observe Mode.
echo.
echo    [ OBSERVE -- read-only, safe for new users ]
echo    O  --  OBSERVE MODE       (first-run wizard: baseline + weekly)
echo    S  --  Snapshot           (capture current state -- no changes)
echo    T  --  View Timeline      (what Microsoft did since baseline)
echo    D  --  Diff Snapshots     (compare any two snapshots)
echo    A  --  Audit              (check if hardening still holds)
echo    W  --  Weekly Task Status (install/remove/check schedule)
echo    B  --  Browse Snapshots   (open snapshot folder in File Explorer)
echo.
echo    [ SETUP -- new-PC convenience, run before observing ]
echo    N  --  New PC Bootstrap   (UI: extensions, taskbar, nags, etc.)
echo.
echo    [ HARDEN -- modifies your system ]
echo    H  --  Hardening Menu     (privacy, performance, gap-closers)
echo    R  --  Restore Menu       (turn things back on selectively)
echo    U  --  Snapshot Restore   (full revert to a saved state)
echo    F  --  Firewall + Hosts   (block telemetry endpoints)
echo    P  --  App Defaults       (file associations / Edge PDF block)
echo.
echo    ?  --  Help / what does each option do
echo    Q  --  Quit
echo.
set /p CHOICE="  Enter choice: "

if /i "%CHOICE%"=="O" goto OBSERVE
if /i "%CHOICE%"=="S" goto SNAPSHOT
if /i "%CHOICE%"=="T" goto TIMELINE
if /i "%CHOICE%"=="D" goto DIFF
if /i "%CHOICE%"=="A" goto AUDIT
if /i "%CHOICE%"=="W" goto WEEKLY
if /i "%CHOICE%"=="B" goto BROWSE

if /i "%CHOICE%"=="N" goto NEWPC

if /i "%CHOICE%"=="H" goto HARDEN_MENU
if /i "%CHOICE%"=="R" goto RESTORE
if /i "%CHOICE%"=="U" goto SNAPRESTORE
if /i "%CHOICE%"=="F" goto FIREWALL
if /i "%CHOICE%"=="P" goto APPDEFAULTS

if /i "%CHOICE%"=="?" goto HELP
if /i "%CHOICE%"=="Q" goto END

echo.
echo  Invalid choice. Try again.
timeout /t 2 >nul
goto MENU

:: ============================================================
::  OBSERVATION ACTIONS
:: ============================================================
:OBSERVE
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Observe.ps1"
goto DONE

:SNAPSHOT
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Snapshot.ps1"
goto DONE

:TIMELINE
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Timeline.ps1"
goto DONE

:DIFF
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Diff.ps1"
goto DONE

:AUDIT
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Audit.ps1"
goto DONE

:WEEKLY
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11ScheduleWeekly.ps1"
echo.
echo  Tip: pass -Install or -Uninstall to change the task.
echo       To install:    .\Win11ScheduleWeekly.ps1 -Install
echo       To uninstall:  .\Win11ScheduleWeekly.ps1 -Uninstall
echo.
pause
goto MENU

:BROWSE
cls
echo.
if not exist "%USERPROFILE%\Documents\Win11Hardener" (
    echo  ================================================================
    echo    No snapshot folder yet
    echo  ================================================================
    echo.
    echo  WindowsSpy has not created any snapshots yet, so the folder
    echo  does not exist.
    echo.
    echo  Run option O ^(OBSERVE MODE^) or option S ^(Snapshot^) first.
    echo  The folder will be created at:
    echo.
    echo    %USERPROFILE%\Documents\Win11Hardener
    echo.
    pause
    goto MENU
)
echo  Opening snapshot folder in File Explorer...
echo    %USERPROFILE%\Documents\Win11Hardener
echo.
start "" explorer.exe "%USERPROFILE%\Documents\Win11Hardener"
timeout /t 2 >nul
goto MENU

:: ============================================================
::  SETUP ACTIONS (new-PC convenience)
:: ============================================================
:NEWPC
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11FreshInstall.ps1"
goto DONE

:: ============================================================
::  HARDENING SUBMENU (gated by snapshot existence)
:: ============================================================
:HARDEN_MENU
cls
echo.
echo  ================================================================
echo    HARDENING MENU
echo  ================================================================
echo.
echo    1  --  Privacy Hardener     (telemetry, ads, tracking, OneDrive)
echo    2  --  Performance Hardener (power, visual, network, gaming)
echo    3  --  Privacy EXTRAS       (Copilot, AutoLogger, WER, CEIP,
echo                                AppCompat, Edge telemetry, full
echo                                OneDrive uninstall, etc.)
echo    L  --  PRO Hardener         (gap-closers: Bing, Store push,
echo                                NCSI, CDP, NTP, LLMNR/NetBIOS,
echo                                Spotlight, dev opt-out)
echo    N  --  Run ALL of 1+3+2+L+F (full nuclear option)
echo.
echo    B  --  Back to main menu
echo.
set /p HCHOICE="  Enter choice: "

if /i "%HCHOICE%"=="1" goto SNAPCHECK_THEN_PRIV
if /i "%HCHOICE%"=="2" goto SNAPCHECK_THEN_PERF
if /i "%HCHOICE%"=="3" goto SNAPCHECK_THEN_EXTRAS
if /i "%HCHOICE%"=="L" goto SNAPCHECK_THEN_PRO
if /i "%HCHOICE%"=="N" goto SNAPCHECK_THEN_ALL
if /i "%HCHOICE%"=="B" goto MENU
echo.
echo  Invalid choice.
timeout /t 2 >nul
goto HARDEN_MENU

:: ============================================================
::  SNAPSHOT-FIRST GATE
:: ============================================================
:SNAPCHECK_THEN_PRIV
set NEXT=PRIVACY
goto SNAPCHECK
:SNAPCHECK_THEN_PERF
set NEXT=PERF
goto SNAPCHECK
:SNAPCHECK_THEN_EXTRAS
set NEXT=EXTRAS
goto SNAPCHECK
:SNAPCHECK_THEN_PRO
set NEXT=PRO
goto SNAPCHECK
:SNAPCHECK_THEN_ALL
set NEXT=ALL
goto SNAPCHECK

:SNAPCHECK
if exist "%USERPROFILE%\Documents\Win11Hardener\Win11Snapshot_LATEST.xml" goto JUMP_NEXT
cls
echo.
echo  ################################################################
echo  #                                                              #
echo  #               NO SETTINGS SNAPSHOT FOUND                    #
echo  #                                                              #
echo  ################################################################
echo.
echo  No snapshot found at:
echo    %USERPROFILE%\Documents\Win11Hardener\
echo.
echo  WindowsSpy strongly recommends a snapshot BEFORE hardening so
echo  you can roll back via launcher option U.
echo.
echo  Easiest path: press Q here, then run OBSERVE MODE (option O)
echo  from the main menu. That will capture a baseline + start the
echo  weekly observation task.
echo.
set /p TAKESNAP="  Take a snapshot now? (Y / N): "
if /i "%TAKESNAP%"=="Y" goto SNAPSHOT_THEN_NEXT
goto JUMP_NEXT

:SNAPSHOT_THEN_NEXT
cls
echo  Launching snapshot...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Snapshot.ps1"
echo.
echo  ----------------------------------------------------------------
echo   Snapshot complete. Launching the hardening action you chose.
echo  ----------------------------------------------------------------
echo.
pause
goto JUMP_NEXT

:JUMP_NEXT
if /i "%NEXT%"=="PRIVACY" goto PRIVACY
if /i "%NEXT%"=="PERF"    goto PERF
if /i "%NEXT%"=="EXTRAS"  goto EXTRAS
if /i "%NEXT%"=="PRO"     goto PRO
if /i "%NEXT%"=="ALL"     goto ALL
goto MENU

:: ============================================================
::  HARDENING ACTION TARGETS
:: ============================================================
:PRIVACY
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener.ps1"
goto DONE

:PERF
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PerfHardener.ps1"
goto DONE

:EXTRAS
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener_Extras.ps1"
goto DONE

:PRO
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11ProHardener.ps1"
goto DONE

:FIREWALL
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11FirewallTelemetry.ps1"
goto DONE

:ALL
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener.ps1"
echo.
echo  =====  Privacy done. Launching EXTRAS...  =====
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener_Extras.ps1"
echo.
echo  =====  Extras done. Launching Performance...  =====
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PerfHardener.ps1"
echo.
echo  =====  Performance done. Launching PRO...  =====
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11ProHardener.ps1"
echo.
echo  =====  PRO done. Launching Firewall...  =====
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11FirewallTelemetry.ps1"
goto DONE

:RESTORE
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Restore.ps1"
goto DONE

:SNAPRESTORE
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11SnapshotRestore.ps1"
goto DONE

:APPDEFAULTS
cls
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11AppDefaults.ps1"
goto DONE

:: ============================================================
::  HELP
:: ============================================================
:HELP
cls
echo.
echo  ================================================================
echo    WindowsSpy -- Quick Help
echo  ================================================================
echo.
echo  OBSERVATION ACTIONS (no system changes):
echo.
echo    O - Observe Mode    First-time setup. Takes baseline snapshot,
echo                        optionally installs weekly task. SAFE.
echo.
echo    S - Snapshot        Capture current state of every setting
echo                        WindowsSpy tracks. Manual checkpoint.
echo.
echo    T - View Timeline   Aggregates all your snapshots into one
echo                        readable report: what Microsoft did
echo                        since baseline.
echo.
echo    D - Diff            Compare any two snapshots. Default: baseline
echo                        vs. most recent.
echo.
echo    A - Audit           Check whether your hardener settings
echo                        survived recent Windows Updates.
echo.
echo    W - Weekly Task     Show status / install / remove the
echo                        scheduled weekly observation task.
echo.
echo    B - Browse          Opens the snapshot folder in File Explorer.
echo                        Lives at:
echo                          %USERPROFILE%\Documents\Win11Hardener
echo                        Useful for inspecting old snapshots,
echo                        verifying the baseline exists, or cleaning
echo                        up stale files manually.
echo.
echo  HARDENING ACTIONS (modifies your system):
echo.
echo    H - Hardening Menu  Submenu for Privacy, Perf, Extras, PRO,
echo                        Firewall hardeners.
echo.
echo    R - Restore Menu    Turn things back on selectively
echo                        (OneDrive, Cortana, Edge Sign-in, etc.).
echo.
echo    U - Snapshot        Full revert to a saved snapshot. Useful
echo        Restore         if a hardener broke something.
echo.
echo    F - Firewall        Block telemetry endpoints at the network
echo                        layer (hosts file + firewall rules).
echo.
echo    P - App Defaults    Manage file associations (PDF reader,
echo                        media player, etc.) -- block Edge hijack.
echo.
echo  RECOMMENDED FIRST-TIME PATH:
echo.
echo    1. Press O (Observe Mode)
echo    2. Let it take a baseline and install the weekly task
echo    3. Use your PC normally for a week or two
echo    4. Press T (Timeline) to see what Microsoft did
echo    5. ONLY THEN consider H (Hardening Menu) if you want
echo       to push back on what you observed
echo.
pause
goto MENU

:DONE
echo.
echo  ================================================================
echo   Action complete. Reboot if you ran a hardener.
echo   CrisisOfTruth.org -- Use at your own risk.
echo  ================================================================
echo.
pause
goto MENU

:END
cls
echo.
echo  Exiting WindowsSpy. No further actions.
echo.
pause
exit