@echo off
title TalkHammer Companion
rem Starts the TalkHammer Companion. Keep the window open while you play;
rem close it whenever you want to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TalkHammerCompanion.ps1" %*
if errorlevel 1 (
    echo.
    echo The companion stopped because of the problem shown above.
    pause
)
