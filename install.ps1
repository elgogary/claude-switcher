# claude-switcher PowerShell installer
# Usage from PowerShell:
#   iwr -useb https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.ps1 | iex
#
# Usage from cmd.exe:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.ps1 | iex"

$ErrorActionPreference = 'Stop'

$Repo      = 'elgogary/claude-switcher'
$Branch    = 'main'
$ZipUrl    = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"
$ClaudeDir = "$env:USERPROFILE\.claude"
$BinDir    = "$env:USERPROFILE\.local\bin"

function Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Ok($msg)   { Write-Host $msg -ForegroundColor Green }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Die($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

Info "[claude-switcher] Installing for Windows..."

# Dependency check — bash.exe (from Git for Windows) is required because
# claude-manager.sh is a bash script. We only use PowerShell to install.

# First try: is bash already on PATH?
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue

# Second try: Git might be installed but not on PATH (user picked the wrong
# PATH option during Git setup). Look in the standard Git install locations.
if (-not $bashCmd) {
    $knownPaths = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\cmd\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $knownPaths) {
        if (Test-Path $p) {
            Warn "  Found Git Bash at $p (not on PATH — adding to current session)"
            $env:PATH = "$env:PATH;$(Split-Path $p -Parent)"
            $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
            if ($bashCmd) { break }
        }
    }
}

if (-not $bashCmd) {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Warn ""
        Warn "bash.exe not found — Git for Windows is required."
        Warn ""
        Info "Good news: winget is available. Want to auto-install Git for Windows now?"
        Info "This will run:  winget install --id Git.Git -e --source winget"
        $resp = Read-Host "Install Git for Windows automatically? [Y/n]"
        if ($resp -eq '' -or $resp -match '^[Yy]') {
            Info ""
            Info "Installing Git for Windows via winget (1-2 min)..."
            # Don't check $LASTEXITCODE — winget returns non-zero when the package
            # is already installed up-to-date, which is NOT a failure for us.
            # We just need bash.exe to be findable after this runs.
            winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Host

            # Refresh PATH so bash.exe becomes visible in this session
            $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')

            # Re-check PATH first, then known install locations
            $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
            if (-not $bashCmd) {
                $knownPaths = @(
                    "$env:ProgramFiles\Git\bin\bash.exe",
                    "$env:ProgramFiles\Git\cmd\bash.exe",
                    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
                    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
                )
                foreach ($p in $knownPaths) {
                    if (Test-Path $p) {
                        Warn "  Found Git Bash at $p (not on PATH — adding to current session)"
                        $env:PATH = "$env:PATH;$(Split-Path $p -Parent)"
                        $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
                        if ($bashCmd) { break }
                    }
                }
            }

            if (-not $bashCmd) {
                Die @"

Git appears to be installed, but bash.exe is still not findable.

This usually means Git was installed with the 'Use Git from Git Bash only'
PATH option. Fix:
  1. Open 'Add or remove programs' in Windows Settings
  2. Find 'Git' and click 'Modify'
  3. When asked about PATH, pick the MIDDLE option:
     'Git from the command line and also from 3rd-party software'
  4. Finish the reinstall
  5. Close this PowerShell window and open a new one
  6. Re-run the claude-switcher installer

OR manually add Git's bin directory to PATH in this session:
  `$env:PATH += ';C:\Program Files\Git\bin'
"@
            }

            Ok ""
            Ok "  Git found: $($bashCmd.Source)"
            Ok "  Continuing claude-switcher install..."
            Ok ""
        } else {
            Die "Installation cancelled. Install Git for Windows and try again."
        }
    } else {
        Die @"

bash.exe not found on PATH.

claude-switcher needs Git for Windows (it ships bash.exe + curl + tar).

Install it ONE of these ways:

  1. winget (if you have Windows 10 1809+ or Windows 11):
       winget install --id Git.Git -e --source winget

  2. Manual download:
       https://git-scm.com/download/win
     During setup, pick 'Git from the command line and also from 3rd-party software'
     (the middle option).

Then close PowerShell, open a NEW window, and re-run this installer.
"@
    }
}
Ok "  Git Bash found: $($bashCmd.Source)"

# Create target dirs
New-Item -ItemType Directory -Force -Path $ClaudeDir, $BinDir | Out-Null

# Download release zip (Windows-native, no tar needed for extraction)
$tmpName = "claude-switcher-install-" + [guid]::NewGuid().Guid
$tmp     = New-Item -ItemType Directory -Path (Join-Path $env:TEMP $tmpName) -Force
try {
    Info "[1/5] Downloading release..."
    $zip = Join-Path $tmp 'release.zip'
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing

    Info "[2/5] Extracting..."
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $src = Join-Path $tmp "claude-switcher-$Branch"
    if (-not (Test-Path "$src\claude-manager.sh")) { Die "release missing claude-manager.sh" }
    if (-not (Test-Path "$src\cm.cmd"))            { Die "release missing cm.cmd" }
    if (-not (Test-Path "$src\cm.ps1"))            { Die "release missing cm.ps1" }

    # Backup + install claude-manager.sh
    Info "[3/5] Installing claude-manager.sh"
    $target = "$ClaudeDir\claude-manager.sh"
    if (Test-Path $target) {
        $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
        Copy-Item $target "$target.bak.$ts"
        Warn "  backed up existing script -> claude-manager.sh.bak.$ts"
    }
    Copy-Item "$src\claude-manager.sh" $target -Force

    # Install wrappers (cm for bash, cm.cmd for cmd, cm.ps1 for PowerShell)
    Info "[4/5] Installing cm wrappers"
    Copy-Item "$src\cm.cmd" "$BinDir\cm.cmd" -Force
    Copy-Item "$src\cm.ps1" "$BinDir\cm.ps1" -Force
    # bash shim (single line file — Git Bash uses this)
    $bashShim = "#!/usr/bin/env bash`nexec bash `"`$HOME/.claude/claude-manager.sh`" `"`$@`""
    [IO.File]::WriteAllText("$BinDir\cm", $bashShim, [Text.UTF8Encoding]::new($false))
    # Remove Zone.Identifier so RemoteSigned policy doesn't block cm.ps1
    Unblock-File "$BinDir\cm.ps1" -ErrorAction SilentlyContinue
    Unblock-File "$BinDir\cm.cmd" -ErrorAction SilentlyContinue
    Ok "  installed cm, cm.cmd, cm.ps1 (unblocked)"

    # Templates — only if not already present (don't clobber tokens)
    Info "[5/5] Installing provider templates"
    foreach ($t in @('zai','anthropic','openrouter','deepseek','kimi','custom')) {
        $f = "settings-$t.json"
        if (Test-Path "$ClaudeDir\$f") {
            Warn "  skip $f (already exists)"
        } else {
            Copy-Item "$src\templates\$f" "$ClaudeDir\$f"
            Ok "  installed $f"
        }
    }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# Add BinDir to user PATH (idempotent)
$userPath = [Environment]::GetEnvironmentVariable('PATH','User')
if (-not ($userPath -and $userPath -like "*$BinDir*")) {
    $newPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $BinDir } else { $BinDir }
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Ok "  [ok] added $BinDir to Windows user PATH"
} else {
    Ok "  [ok] $BinDir already on user PATH"
}

# Also make sure Git's bin dir is on the USER PATH persistently, so 'cm.cmd'
# can find 'bash.exe' next time the user opens a shell. If we found bash in
# a fallback location above, it's only on this session's PATH — we need to
# persist it to the registry.
#
# BUG FIX (v1.7.4): we only check USER and MACHINE registry PATH here, NOT
# the current session $env:PATH. The session path may include a dir we
# temporarily added earlier in this script, which wrongly made us think
# the dir was already persisted.
$bashDir = Split-Path $bashCmd.Source -Parent
$machinePath = [Environment]::GetEnvironmentVariable('PATH','Machine')
$userPathFresh = [Environment]::GetEnvironmentVariable('PATH','User')
if ($bashDir -and ($userPathFresh -notlike "*$bashDir*") -and ($machinePath -notlike "*$bashDir*")) {
    $new2 = if ($userPathFresh) { $userPathFresh.TrimEnd(';') + ';' + $bashDir } else { $bashDir }
    [Environment]::SetEnvironmentVariable('PATH', $new2, 'User')
    Ok "  [ok] added $bashDir to Windows user PATH (so cm.cmd can find bash.exe)"
} else {
    Ok "  [ok] $bashDir already on PATH"
}

# Re-refresh current session PATH with all changes
$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')

# Refresh current session PATH so `cm` works IMMEDIATELY — no reopen needed
$machinePath = [Environment]::GetEnvironmentVariable('PATH','Machine')
$userPathNew = [Environment]::GetEnvironmentVariable('PATH','User')
$env:PATH = "$machinePath;$userPathNew"

Ok ""
Ok "[OK] claude-switcher installed!"
Ok ""

# Check PowerShell execution policy — if Restricted or Undefined (default),
# cm.ps1 will be blocked. Offer to raise it to RemoteSigned (safe, user-scope).
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
    Warn ""
    Warn "PowerShell execution policy is '$policy' — this will block cm.ps1."
    Warn "Setting execution policy to RemoteSigned for your user (safe, no admin needed)..."
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Ok "  [ok] execution policy set to RemoteSigned (CurrentUser scope)"
    } catch {
        Warn "  [warn] could not set execution policy automatically. Run manually:"
        Warn "    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force"
    }
}

# If tokens provided via env vars, run non-interactive setup
$hasTokens = $env:CM_ZAI_TOKEN -or $env:CM_ANTHROPIC_TOKEN -or $env:CM_OPENROUTER_TOKEN -or `
             $env:CM_DEEPSEEK_TOKEN -or $env:CM_KIMI_TOKEN -or $env:CM_CUSTOM_TOKEN
if ($hasTokens) {
    Info "Tokens detected in env vars — running non-interactive setup..."
    & bash "$ClaudeDir\claude-manager.sh" setup-quiet
} else {
    Info "Next step:"
    Info "  cm setup       (enter your tokens interactively)"
    Info "  cm             (open interactive menu)"
    Info ""
    Info "Test it now:"
    Info "  cm version"
}
