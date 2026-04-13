# claude-switcher PowerShell wrapper for Windows
# Forwards to the bash script via Git Bash's bash.exe.
# Requires Git for Windows (https://git-scm.com/download/win) which ships bash.
& bash "$env:USERPROFILE\.claude\claude-manager.sh" $args
