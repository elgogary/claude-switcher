# claude-switcher

One-command provider switcher for [Claude Code](https://docs.claude.com/en/docs/claude-code) — flip between **Anthropic**, **Z.AI (GLM)**, **OpenRouter**, **DeepSeek**, **Moonshot Kimi**, and any custom proxy without editing JSON by hand.

[![CI](https://github.com/elgogary/claude-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/elgogary/claude-switcher/actions/workflows/ci.yml)

## Why this exists

Claude Code reads its API endpoint and model from `~/.claude/settings.json`. To switch providers you have to:

1. Open the file in an editor
2. Find `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and the three `ANTHROPIC_DEFAULT_*_MODEL` fields
3. Paste the right values for the provider you want
4. Save without breaking the JSON
5. Hope you didn't typo the URL

That's 5 steps every time you want to try a cheaper model on Z.AI, fall back to Anthropic for a hard task, or route through OpenRouter to test a Llama or GPT model. After doing it twice you start copy-pasting blocks between sticky notes, and after the third typo crashes Claude Code on startup you start backing up the file before every edit.

**This tool is the muscle memory:**

- One command (`cm`) to switch — no editor, no JSON, no risk of breaking the file
- Tokens entered **once** through a wizard with hidden input, then never touched again
- Every switch creates a timestamped backup so you can always roll back
- A single `curl | bash` install line your friends can run without any context

The whole thing is ~350 lines of bash. There is no daemon, no config service, no telemetry — just three small JSON templates and a script that copies the right one over `settings.json` when you ask it to.

### Why three providers?

- **Anthropic** — the original. Best quality for hard reasoning, but the most expensive.
- **Z.AI (GLM)** — much cheaper, fast, good enough for routine refactors and exploration. Speaks the Anthropic API natively at `https://api.z.ai/api/anthropic`.
- **OpenRouter** — gateway to dozens of models (Anthropic, OpenAI, Meta, Mistral, DeepSeek, Qwen…). Useful when you want to A/B a Llama 3.1 405B against Sonnet on the same task, or burn down free-tier credits across providers.

The right model for a task is rarely the same as yesterday. Switching should take one keystroke, not five steps.

## Install

### Option 1 — One command (manual)

```bash
curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh | bash
```

Then run the wizard to enter your tokens:

```bash
cm setup
```

That's it — `cm` is now available in your terminal.

### Option 2 — Ask an AI agent to install it (stupid mode)

If you're already in **Claude Code**, **ChatGPT**, **Cursor**, **Codex**, or any other AI coding agent that can run shell commands, paste this prompt:

> Install and configure claude-switcher from https://github.com/elgogary/claude-switcher for me.
>
> 1. Ask me which providers I want to use (Z.AI, Anthropic, OpenRouter, DeepSeek, Moonshot Kimi). I'll paste the API tokens for the ones I want.
> 2. Once I give you the tokens, run this single command (substituting only the tokens I provided, omitting env vars for providers I skipped):
>
> ```bash
> CM_ZAI_TOKEN="..." \
> CM_ANTHROPIC_TOKEN="..." \
> CM_OPENROUTER_TOKEN="..." \
> CM_DEEPSEEK_TOKEN="..." \
> CM_KIMI_TOKEN="..." \
> CM_START="zai" \
>   bash -c "$(curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh)"
> ```
>
> 3. Verify by running `cm status` — it should show the provider I chose in `CM_START`.
> 4. Tell me to restart Claude Code to apply the change.

That's it. The agent asks for your tokens once, runs **one command**, and you're done. No manual JSON editing, no wizard prompts, no "press Enter to continue." The installer detects the `CM_*_TOKEN` env vars and runs setup non-interactively.

**Important security notes:**

- Only paste tokens to an AI agent you trust (Claude Code on your own machine = safe; random web chat = risky).
- The tokens go into `~/.claude/settings-*.json` on your local disk only — they're never sent anywhere claude-switcher controls.
- If your agent runs in a container or remote box, the tokens land there, not on your laptop.

### Option 3 — One command from your own terminal (also stupid mode)

If you're not using an agent and want the full one-line install + setup, copy this into your terminal and replace the placeholders with your real tokens:

```bash
CM_ZAI_TOKEN="your-zai-token" \
CM_ANTHROPIC_TOKEN="your-anthropic-token" \
CM_START="zai" \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh)"
```

Set only the env vars for providers you actually use. `CM_START` picks which provider to activate after install (defaults to the first one whose token you provided).

### After setup — ask the agent to switch providers anytime

> Switch Claude Code to DeepSeek and confirm the switch worked.

The agent runs `cm deepseek fast && cm status`. Done.

## Requirements

- `bash`, `curl`, `tar`
- `python3` (used to read/write `settings.json`)

The installer fails fast with a clear error if any of these are missing.

### Windows

claude-switcher needs **Git for Windows** (for `bash.exe`). Install it from https://git-scm.com/download/win — during setup pick **"Git from the command line and also from 3rd-party software"** (the middle option).

After Git is installed, pick **any** of these — they all do the same thing:

**Method A — Double-click (easiest, zero typing)**

1. Download [install.bat](https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.bat) (right-click the link → Save As)
2. Double-click the downloaded `install.bat`
3. A window opens, installs everything, prints "Installation COMPLETE", waits for you to press a key
4. Open a new terminal and type `cm setup`

**Method B — One command (works in any terminal)**

Open **any** Windows terminal — cmd.exe, PowerShell, or Windows Terminal, it doesn't matter — and paste this single line:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -useb https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.ps1 | iex"
```

It re-launches PowerShell just long enough to run the installer, so you don't need to know which shell you're in.

**Method C — From PowerShell (if you're already there)**

```powershell
iwr -useb https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.ps1 | iex
```

**Method D — From Git Bash or WSL (same installer as Linux/macOS)**

```bash
curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh | bash
```

---

All four methods:
- Download and extract the release
- Install `cm` / `cm.cmd` / `cm.ps1` to `%USERPROFILE%\.local\bin`
- Add that directory to your Windows user PATH
- **Refresh the current PowerShell session's PATH** — `cm` works immediately, no reopen needed (Methods A, B, C)

After install, `cm` works from **PowerShell**, **cmd.exe**, **Git Bash**, and **Windows Terminal** — all the same.

## Usage

```bash
cm                    # interactive menu
cm setup              # run the setup wizard (enter tokens)
cm zai                # switch to Z.AI (GLM)
cm anthropic          # switch to Claude (Anthropic)
cm openrouter         # switch to OpenRouter
cm deepseek           # switch to DeepSeek
cm kimi               # switch to Moonshot Kimi
cm custom             # switch to your custom proxy / router
cm status             # show current provider
cm restore            # restore from a backup
cm version            # show version
cm help               # show help
```

`cm zai fast` and `cm anthropic fast` skip the confirmation prompt.

Restart Claude Code after switching.

## How it works

`claude-manager.sh` copies `~/.claude/settings-zai.json` or `~/.claude/settings-anthropic.json` over `~/.claude/settings.json`. Claude Code reads that file on startup to pick the API endpoint and model. Every switch creates a timestamped backup in `~/.claude/backups/` so you can always roll back.

## Providers

| Provider | Token URL | Default model | Notes |
|---|---|---|---|
| **Anthropic** | https://console.anthropic.com/settings/keys | `claude-3.5-sonnet` | The original. Highest quality, highest cost. |
| **Z.AI (GLM)** | https://z.ai/manage-apikey/apikey-list | `glm-5.1` | Cheap, fast, native Anthropic-format endpoint. |
| **OpenRouter** | https://openrouter.ai/keys | `anthropic/claude-3.5-sonnet` | Gateway to dozens of models — edit the template to pick `openai/gpt-4o`, `meta-llama/llama-3.1-405b`, etc. |
| **DeepSeek** | https://platform.deepseek.com/api_keys | `deepseek-chat` / `deepseek-reasoner` | Native Anthropic endpoint at `api.deepseek.com/anthropic`. |
| **Moonshot Kimi** | https://platform.moonshot.cn/console/api-keys | `kimi-k2-0905-preview` | Native Anthropic endpoint at `api.moonshot.cn/anthropic`. |
| **Custom** | (your own) | (your own) | Blank template — edit `~/.claude/settings-custom.json` to point at any proxy/router (litellm, claude-code-router, Ollama via adapter, etc.). |

### Adding a new provider

Drop a `templates/settings-<name>.json` file in the repo, then add one row each to the four arrays at the top of `claude-manager.sh` (`PROVIDER_NAMES`, `PROVIDER_LABELS`, `PROVIDER_URLS`, `PROVIDER_PATTERNS`). The wizard, menu, status display, help text, and `cm <name>` command auto-pick it up. PRs welcome.

## Uninstall

```bash
rm ~/.claude/claude-manager.sh ~/.claude/settings-zai.json ~/.claude/settings-anthropic.json ~/.local/bin/cm
```

## Changelog

### v1.7.4 (2026-04-13)
- **Bug fix** — when v1.7.3 found Git Bash at a fallback location (because it wasn't on PATH), it added the dir to the current session's `$env:PATH` and then used that as the "already persisted" check. Result: Git's bin dir was NEVER written to the registry, so `cm.cmd` failed with `'bash' is not recognized` after the installer exited. Now checks only the User and Machine registry PATH, ignoring the session path. Reported by a user whose friend installed Git with the "Use Git from Git Bash only" option.

### v1.7.3 (2026-04-13)
- **Find Git even when it's not on PATH** — the PowerShell installer now looks for `bash.exe` in 4 standard Git install locations (`Program Files\Git\bin`, `Program Files\Git\cmd`, `Program Files (x86)\Git\bin`, `%LOCALAPPDATA%\Programs\Git\bin`) before giving up. Fixes the common case where a user installed Git with "Use Git from Git Bash only" and `bash.exe` isn't on the system PATH.
- **Persist Git's bin dir on user PATH** — if Git was found in a fallback location, its parent dir is added to the Windows user PATH so `cm.cmd` / `cm.ps1` can find `bash.exe` in future sessions.
- **Ignore winget "already installed" exit code** — winget returns non-zero when the package is already latest, which is success for us. Previous version treated this as failure and died.

### v1.7.2 (2026-04-13)
- **Auto-install Git for Windows via winget** — if the PowerShell installer detects `bash.exe` is missing but `winget` is available, it offers to install Git for Windows automatically (`winget install --id Git.Git -e --source winget`). After install, PATH is refreshed in the current session so the claude-switcher install continues without a reopen.
- Better error message when winget isn't available — shows both the winget one-liner AND the manual download link side by side.
- Addresses user report: friend ran the installer without Git, got a generic "install Git" error. Now the installer can do it for them.

### v1.7.1 (2026-04-13)
- **`install.bat`** — double-clickable Windows installer. Users can download one file, double-click it in File Explorer, and watch the install complete. No terminal required.
- `install.bat` also runs from any terminal (cmd / PowerShell / Git Bash / Windows Terminal) if the user prefers typing.
- README documents 4 Windows install methods: double-click, shell-agnostic one-liner, PowerShell, Git Bash.

### v1.7.0 (2026-04-13)
- **Native PowerShell installer** — `install.ps1` downloads + extracts via `Invoke-WebRequest` and `Expand-Archive`, no Git Bash needed for the install step (bash is still needed at runtime for `claude-manager.sh`).
- **Current-session PATH refresh** — the PowerShell installer updates `$env:PATH` in the running session, so `cm` works immediately without closing/reopening the terminal.
- README gives 3 Windows install methods: PowerShell (`iwr | iex`), Git Bash (`curl | bash`), or cmd.exe (via `powershell -Command`).

### v1.6.0 (2026-04-13)
- **Auto-add Windows PATH** — the installer now calls `powershell.exe` during install to append `~/.local/bin` to the Windows user PATH via `[Environment]::SetEnvironmentVariable('PATH', ..., 'User')`. Zero manual steps. Idempotent — checks if already present before appending.
- Falls back to a printed one-liner if `powershell.exe` is unavailable.

### v1.5.0 (2026-04-13)
- **Windows support** — `cm` now works from PowerShell, cmd.exe, and Git Bash. The installer detects Windows (via `$OSTYPE`/`uname`) and drops `cm.cmd` + `cm.ps1` wrappers alongside the bash shim. Both wrappers forward to the same `claude-manager.sh` via Git Bash's `bash.exe`.
- Installer prints a one-line PowerShell snippet to add `~/.local/bin` to the Windows user PATH.
- Requires Git for Windows (for `bash.exe`) — installed by anyone who uses `git` on Windows.

### v1.4.0 (2026-04-13)
- **Stupid mode** — `cm setup-quiet` reads tokens from `CM_*_TOKEN` env vars (one per provider) and writes them non-interactively. The installer auto-detects these env vars and runs quiet setup, so the entire install + configure flow becomes a single command an AI agent can run unattended.
- **Agent-friendly install command** in README — paste-able prompt for Claude Code / ChatGPT / Cursor that asks the user for tokens once, runs one command, done.
- **`CM_START`** env var to pick which provider to activate after non-interactive setup.
- **`CM_CUSTOM_URL`** env var to set the custom provider's base URL (for litellm/ccr/Ollama proxies).
- 19 smoke tests (was 17) — covers quiet setup happy path + no-env-var rejection.

### v1.3.0 (2026-04-13)
- **3 new providers**: DeepSeek, Moonshot Kimi, and a generic **Custom** proxy template for litellm/claude-code-router/Ollama adapters.
- **Data-driven registry** — `claude-manager.sh` now loops over a `PROVIDER_NAMES` array instead of hardcoding every provider in 5 places. Adding a new provider is a 2-file change: drop a template, append one row to each of 4 arrays.
- **Unknown command errors** — `cm bogus` now exits non-zero and prints help, instead of silently showing help with a success exit code.
- **Smoke tests bumped to 17** — now cover all 5 provider switches + unknown-command rejection.

### v1.2.0 (2026-04-13)
- **OpenRouter support** — third provider option alongside Z.AI and Anthropic. Pick any model OpenRouter offers (`anthropic/*`, `openai/*`, `meta-llama/*`, etc.) by editing the template.
- **Setup wizard** — `cm setup` prompts for tokens with hidden input and writes them automatically. No more manual JSON editing.
- **Interactive menu** — `cm` with no arguments opens a single-keypress menu.
- **Atomic install** — installer downloads a single tarball instead of 3 separate `curl` calls. No partial-install state.
- **Upgrade-safe installer** — backs up your existing `claude-manager.sh` before overwrite.
- **Token security** — wizard uses hidden input (`read -s`); `set_token` reads token from stdin so it never appears in `ps aux`.
- **Strict mode** — `set -uo pipefail` catches typos and silent failures.
- **Performance** — `show_status` now uses 1 `python3` call instead of 5 (~5× faster on macOS).
- **DRY** — single `load_settings` helper replaces 7 duplicated python one-liners.
- **CI** — ShellCheck + smoke test run on every push.
- **Tests** — `tests/smoke.sh` runs end-to-end install/switch/restore against a fake `$HOME`.
- Removed dead `config.json` copy lines that produced misleading success messages.

### v1.1.0
- Single-keypress menu (no Enter needed).

### v1.0.0
- Initial release: provider switching between Z.AI and Anthropic.

## License

MIT
