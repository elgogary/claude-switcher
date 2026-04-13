@echo off
REM claude-switcher installer for Windows
REM -----------------------------------------------------------------------
REM TWO WAYS TO USE THIS FILE:
REM
REM   1) DOUBLE-CLICK IT in File Explorer — a window opens, installs,
REM      waits for you to press any key, then closes.
REM
REM   2) RUN FROM A TERMINAL — works in cmd.exe, PowerShell, or
REM      Windows Terminal. Just type the path to this file:
REM         install.bat
REM -----------------------------------------------------------------------

setlocal

echo.
echo ========================================
echo   claude-switcher installer for Windows
echo ========================================
echo.

REM Check for bash.exe (Git for Windows is required at runtime)
where bash >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] bash.exe not found.
    echo.
    echo claude-switcher needs Git for Windows ^(ships bash.exe^).
    echo Install it from: https://git-scm.com/download/win
    echo.
    echo During setup, pick "Git from the command line and also from
    echo 3rd-party software" ^(the middle option^).
    echo.
    pause
    exit /b 1
)

echo Running PowerShell installer...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.ps1 | iex"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================
    echo   Installation FAILED
    echo ========================================
    echo Copy the error message above and ask for help.
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Installation COMPLETE
echo ========================================
echo.
echo Next step: open a NEW terminal ^(PowerShell, cmd, or Git Bash^)
echo and type:
echo.
echo     cm setup        - enter your API tokens
echo     cm              - open the interactive menu
echo     cm version      - check it works
echo.
pause
