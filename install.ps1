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
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
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
            winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) {
                Die @"

winget install failed. Please install Git for Windows manually:
  https://git-scm.com/download/win

During setup, pick 'Git from the command line and also from 3rd-party software'
(the middle option). Then open a NEW PowerShell window and re-run this installer.
"@
            }
            # Refresh PATH so bash.exe becomes visible in this session
            $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
            Ok ""
            Ok "  Git for Windows installed. Continuing claude-switcher install..."
            Ok ""
            $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
            if (-not $bashCmd) {
                Die "bash.exe still not found after Git install. Close PowerShell, open a new window, and re-run this installer."
            }
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
    Ok "  installed cm, cm.cmd, cm.ps1"

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

# Refresh current session PATH so `cm` works IMMEDIATELY — no reopen needed
$machinePath = [Environment]::GetEnvironmentVariable('PATH','Machine')
$userPathNew = [Environment]::GetEnvironmentVariable('PATH','User')
$env:PATH = "$machinePath;$userPathNew"

Ok ""
Ok "[OK] claude-switcher installed!"
Ok ""

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
