@echo off
:: ============================================================
::  Win11 Hardener Suite -- Launcher (v6, Pro)
::  Brad / CrisisOfTruth.org
::
::  Keep this .bat in the same folder as ALL of these:
::    Win11Snapshot.ps1               <-- NEW (backup current state)
::    Win11SnapshotRestore.ps1        <-- NEW (revert from snapshot)
::    Win11PrivacyHardener.ps1
::    Win11PerfHardener.ps1
::    Win11PrivacyHardener_Extras.ps1
::    Win11ProHardener.ps1            <-- NEW (Tier 1 gap-closers)
::    Win11FirewallTelemetry.ps1      <-- NEW (hosts + firewall blocks)
::    Win11AppDefaults.ps1
::    Win11Restore.ps1
::    Win11Audit.ps1
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
if not exist "%~dp0Win11Snapshot.ps1"            (echo  [MISSING] Win11Snapshot.ps1            & set MISSING=1)
if not exist "%~dp0Win11SnapshotRestore.ps1"     (echo  [MISSING] Win11SnapshotRestore.ps1     & set MISSING=1)
if not exist "%~dp0Win11PrivacyHardener.ps1"     (echo  [MISSING] Win11PrivacyHardener.ps1     & set MISSING=1)
if not exist "%~dp0Win11PerfHardener.ps1"        (echo  [MISSING] Win11PerfHardener.ps1        & set MISSING=1)
if not exist "%~dp0Win11PrivacyHardener_Extras.ps1" (echo  [MISSING] Win11PrivacyHardener_Extras.ps1 & set MISSING=1)
if not exist "%~dp0Win11ProHardener.ps1"         (echo  [MISSING] Win11ProHardener.ps1         & set MISSING=1)
if not exist "%~dp0Win11FirewallTelemetry.ps1"   (echo  [MISSING] Win11FirewallTelemetry.ps1   & set MISSING=1)
if not exist "%~dp0Win11AppDefaults.ps1"         (echo  [MISSING] Win11AppDefaults.ps1         & set MISSING=1)
if not exist "%~dp0Win11Restore.ps1"             (echo  [MISSING] Win11Restore.ps1             & set MISSING=1)
if not exist "%~dp0Win11Audit.ps1"               (echo  [MISSING] Win11Audit.ps1               & set MISSING=1)
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
::  SCREEN 1 -- DISCLAIMER
:: ============================================================
:DISCLAIMER
cls
echo.
echo  ################################################################
echo  #                                                              #
echo  #        WIN11 HARDENER SUITE  --  CrisisOfTruth.org          #
echo  #                  Pro Edition  v6                            #
echo  #                                                              #
echo  ################################################################
echo.
echo  LEGAL DISCLAIMER -- PLEASE READ CAREFULLY
echo  ----------------------------------------------------------
echo.
echo  This software is provided FREE OF CHARGE for educational
echo  and informational purposes ONLY.
echo.
echo  I, Brad at CrisisOfTruth.org, accept ABSOLUTELY NO
echo  responsibility or liability for any damage, data loss,
echo  system instability, software incompatibility, or ANY
echo  other consequence -- intended or unintended -- that
echo  results from running these scripts on your system.
echo.
echo  YOU RUN THIS SOFTWARE ENTIRELY AT YOUR OWN RISK.
echo.
echo  By continuing past this screen you confirm that:
echo.
echo    (1) You have read and accept this disclaimer in full.
echo    (2) You understand this modifies Windows system settings.
echo    (3) You alone are responsible for the outcome.
echo    (4) CrisisOfTruth.org is held harmless for any result.
echo.
echo  ----------------------------------------------------------
echo.
set /p AGREE="  Type AGREE to continue, or press Enter to exit: "
if /i not "%AGREE%"=="AGREE" goto DECLINED
goto BACKUP_WARN

:DECLINED
cls
echo.
echo  You chose not to continue. No changes were made.
echo  Visit CrisisOfTruth.org for more information.
echo.
pause
exit

:: ============================================================
::  SCREEN 2 -- BACKUP WARNING
:: ============================================================
:BACKUP_WARN
cls
echo.
echo  ################################################################
echo  #                                                              #
echo  #               STOP -- BACK UP FIRST                         #
echo  #                                                              #
echo  ################################################################
echo.
echo  HAVE YOU BACKED UP YOUR HARD DRIVE?
echo  ----------------------------------------------------------
echo.
echo  These scripts modify Windows registry settings, disable
echo  services, and change system configuration. Although they
echo  are designed to be safe, NO system modification tool is
echo  risk-free on every machine.
echo.
echo  IF SOMETHING GOES WRONG, YOU WILL NEED A BACKUP.
echo.
echo  *** DO NOT SKIP THIS STEP. ***
echo.
echo  Note: This launcher will offer to capture a SETTINGS
echo        snapshot via Win11Snapshot.ps1 -- that captures
echo        registry / services / DNS / power state to an XML
echo        file you can revert from. It is NOT a substitute
echo        for an image backup.
echo.
echo        The Audit option (A) and Snapshot option (S) are
echo        READ-ONLY -- a backup is still recommended but not
echo        strictly required to run them.
echo.
echo  ################################################################
echo  #  RECOMMENDED BACKUP TOOLS (use BEFORE running this suite)   #
echo  ################################################################
echo.
echo   BEST CHOICE -- Acronis Cyber Protect Home Office
echo   -------------------------------------------------
echo   Full image backup. Boots independently if Windows
echo   fails. Buy the PERPETUAL LICENSE (one-time purchase)
echo   -- NOT the subscription. Avoid auto-renewal traps.
echo   Website: www.acronis.com
echo.
echo   FREE ALTERNATIVES
echo   -------------------------------------------------
echo   Macrium Reflect Free   --  www.macrium.com
echo     Full disk image backup. Very reliable. Recommended
echo     if you do not want to purchase Acronis.
echo.
echo   Veeam Agent for Windows (Free)
echo     www.veeam.com/windows-endpoint-server-backup-free.html
echo     Solid free option for full system image backups.
echo.
echo   Windows Built-In (minimum protection only)
echo     Search: Create a restore point
echo     This is NOT a full backup. It only rolls back
echo     registry and system files -- not your personal data.
echo     Use a real backup tool whenever possible.
echo.
echo  ################################################################
echo.
echo  Have you backed up your system and all important data?
echo.
set /p BACKED_UP="  Type YES if backed up and ready, or NO to exit: "
if /i "%BACKED_UP%"=="YES" goto CONFIRM
if /i "%BACKED_UP%"=="NO"  goto NOT_BACKED_UP
goto NOT_BACKED_UP

:NOT_BACKED_UP
cls
echo.
echo  ################################################################
echo.
echo  Smart call. Back up your system before proceeding.
echo.
echo  Recommended: Acronis (perpetual license) or Macrium Reflect Free
echo.
echo   Acronis:  www.acronis.com
echo   Macrium:  www.macrium.com
echo.
echo  Re-run this launcher after your backup is complete.
echo.
echo  ################################################################
echo.
pause
exit

:: ============================================================
::  SCREEN 3 -- FINAL CONFIRMATION
:: ============================================================
:CONFIRM
cls
echo.
echo  ################################################################
echo  #                                                              #
echo  #                  FINAL CONFIRMATION                         #
echo  #                                                              #
echo  ################################################################
echo.
echo  You are about to run system hardening scripts that will
echo  make changes to your Windows 11 installation.
echo.
echo  Confirmed so far:
echo    [OK]  You have read and accepted the disclaimer
echo    [OK]  You have backed up your system
echo.
echo  Reminder:
echo    - CrisisOfTruth.org accepts NO responsibility
echo      for any outcome from running these scripts.
echo    - You run this entirely at your own risk.
echo    - A reboot will be recommended after completion.
echo.
echo  ----------------------------------------------------------
echo.
set /p FINAL="  Type RUN to launch the suite, or press Enter to exit: "
if /i not "%FINAL%"=="RUN" goto CANCELLED
goto MENU

:CANCELLED
cls
echo.
echo  Cancelled. No changes were made to your system.
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
echo    Win11 Hardener Suite Pro  --  CrisisOfTruth.org
echo  ================================================================
echo.
echo    [ HARDENING ]
echo    1  --  Privacy Hardener     (telemetry, ads, tracking, OneDrive)
echo    2  --  Performance Hardener (power, visual, network, gaming)
echo    3  --  Privacy EXTRAS       (Copilot, AutoLogger, WER, CEIP,
echo                                AppCompat, Edge telemetry, full
echo                                OneDrive uninstall, background
echo                                apps, handwriting + speech, etc.)
echo    P  --  PRO Hardener         (gap-closers: Bing, Store push,
echo                                NCSI, CDP, NTP, LLMNR/NetBIOS,
echo                                Spotlight, ink wipe, dev opt-out)
echo    F  --  Firewall + Hosts     (block telemetry endpoints at
echo                                 the OS network layer)
echo    4  --  Run ALL of 1+3+2+P+F (full nuclear option)
echo.
echo    [ SAFETY / BACKUP ]
echo    S  --  SNAPSHOT current settings (backup, READ-ONLY)
echo    U  --  RESTORE from snapshot     (undo to a saved state)
echo    A  --  AUDIT  (READ-ONLY: detect what Microsoft reverted
echo                  after a Windows Update -- no changes made)
echo.
echo    [ APP-LEVEL ]
echo    D  --  APP DEFAULTS  (snapshot/restore VLC, PDF reader, etc.,
echo                          block Edge PDF hijack, kill reset nags)
echo    R  --  RESTORE menu  (Hibernate / Location / Camera / Mic, etc.)
echo.
echo    Q  --  Quit
echo.
set /p CHOICE="  Enter choice: "

if /i "%CHOICE%"=="1" goto SNAPCHECK_THEN_PRIV
if /i "%CHOICE%"=="2" goto SNAPCHECK_THEN_PERF
if /i "%CHOICE%"=="3" goto SNAPCHECK_THEN_EXTRAS
if /i "%CHOICE%"=="4" goto SNAPCHECK_THEN_ALL
if /i "%CHOICE%"=="P" goto SNAPCHECK_THEN_PRO
if /i "%CHOICE%"=="F" goto SNAPCHECK_THEN_FW
if /i "%CHOICE%"=="S" goto SNAPSHOT
if /i "%CHOICE%"=="U" goto SNAPRESTORE
if /i "%CHOICE%"=="A" goto AUDIT
if /i "%CHOICE%"=="D" goto APPDEFAULTS
if /i "%CHOICE%"=="R" goto RESTORE
if /i "%CHOICE%"=="Q" goto END
if /i "%CHOICE%"=="q" goto END

echo.
echo  Invalid choice. Try again.
timeout /t 2 >nul
goto MENU

:: ============================================================
::  SNAPSHOT-FIRST GATE
::  If no snapshot exists, prompt before any hardening action.
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
:SNAPCHECK_THEN_FW
set NEXT=FIREWALL
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
echo  No Win11Snapshot_LATEST.xml found in:
echo    %USERPROFILE%\Documents\Win11Hardener\
echo.
echo  This snapshot is your safety net. It captures every setting
echo  the suite can change BEFORE any changes are made, so you can
echo  revert (option U) if something goes wrong.
echo.
echo  STRONGLY RECOMMENDED: take a snapshot first. It is read-only
echo  and takes about 30 seconds.
echo.
set /p TAKESNAP="  Take a snapshot now? (Y / N / CANCEL): "
if /i "%TAKESNAP%"=="Y"      goto SNAPSHOT_THEN_NEXT
if /i "%TAKESNAP%"=="YES"    goto SNAPSHOT_THEN_NEXT
if /i "%TAKESNAP%"=="N"      goto JUMP_NEXT
if /i "%TAKESNAP%"=="NO"     goto JUMP_NEXT
goto MENU

:SNAPSHOT_THEN_NEXT
cls
echo  Launching snapshot...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Snapshot.ps1"
echo.
echo  ----------------------------------------------------------------
echo   Snapshot complete. Now launching the hardening action you chose.
echo  ----------------------------------------------------------------
echo.
pause
goto JUMP_NEXT

:JUMP_NEXT
if /i "%NEXT%"=="PRIVACY"  goto PRIVACY
if /i "%NEXT%"=="PERF"     goto PERF
if /i "%NEXT%"=="EXTRAS"   goto EXTRAS
if /i "%NEXT%"=="PRO"      goto PRO
if /i "%NEXT%"=="FIREWALL" goto FIREWALL
if /i "%NEXT%"=="ALL"      goto ALL
goto MENU

:: ============================================================
::  ACTION TARGETS
:: ============================================================
:SNAPSHOT
cls
echo  Launching Snapshot (read-only)...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Snapshot.ps1"
goto DONE

:SNAPRESTORE
cls
echo  Launching Snapshot Restore...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11SnapshotRestore.ps1"
goto DONE

:PRIVACY
cls
echo  Launching Privacy Hardener...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener.ps1"
goto DONE

:PERF
cls
echo  Launching Performance Hardener...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PerfHardener.ps1"
goto DONE

:EXTRAS
cls
echo  Launching Privacy Extras Hardener...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener_Extras.ps1"
goto DONE

:PRO
cls
echo  Launching Pro Hardener (gap-closers)...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11ProHardener.ps1"
goto DONE

:FIREWALL
cls
echo  Launching Firewall + Hosts Telemetry Block...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11FirewallTelemetry.ps1"
goto DONE

:ALL
cls
echo  Running Privacy Hardener first...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener.ps1"
echo.
echo  ================================================================
echo   Privacy Hardener complete. Launching Privacy EXTRAS...
echo  ================================================================
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PrivacyHardener_Extras.ps1"
echo.
echo  ================================================================
echo   Privacy EXTRAS complete. Launching Performance Hardener...
echo  ================================================================
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11PerfHardener.ps1"
echo.
echo  ================================================================
echo   Performance Hardener complete. Launching PRO Hardener...
echo  ================================================================
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11ProHardener.ps1"
echo.
echo  ================================================================
echo   PRO Hardener complete. Launching Firewall + Hosts Block...
echo  ================================================================
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11FirewallTelemetry.ps1"
goto DONE

:AUDIT
cls
echo  Launching Audit (read-only drift detector)...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Audit.ps1"
goto DONE

:APPDEFAULTS
cls
echo  Launching App Defaults Manager...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11AppDefaults.ps1"
goto DONE

:RESTORE
cls
echo  Launching Restore Helper...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Restore.ps1"
goto DONE

:DONE
echo.
echo  ================================================================
echo   All done. A reboot is strongly recommended.
echo   CrisisOfTruth.org -- Use at your own risk.
echo  ================================================================
echo.
pause
goto MENU

:END
cls
echo.
echo  Exiting. No further changes will be made.
echo  Visit CrisisOfTruth.org for guides and information.
echo.
pause
exit
