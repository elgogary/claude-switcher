@echo off
REM claude-switcher wrapper for Windows cmd.exe / PowerShell
REM Forwards to the bash script via Git Bash's bash.exe.
REM Requires Git for Windows (https://git-scm.com/download/win) which ships bash.
bash "%USERPROFILE%\.claude\claude-manager.sh" %*
