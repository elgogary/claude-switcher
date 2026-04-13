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

```bash
curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh | bash
```

Then run the wizard to enter your tokens:

```bash
cm setup
```

That's it — `cm` is now available in your terminal.

## Requirements

- `bash`, `curl`, `tar`
- `python3` (used to read/write `settings.json`)

The installer fails fast with a clear error if any of these are missing.

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
