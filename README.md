# claude-switcher

One-command provider switcher for [Claude Code](https://docs.claude.com/en/docs/claude-code) — flip between **Anthropic**, **Z.AI (GLM)**, and **OpenRouter** without editing JSON by hand.

[![CI](https://github.com/elgogary/claude-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/elgogary/claude-switcher/actions/workflows/ci.yml)

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
cm status             # show current provider
cm restore            # restore from a backup
cm version            # show version
cm help               # show help
```

`cm zai fast` and `cm anthropic fast` skip the confirmation prompt.

Restart Claude Code after switching.

## How it works

`claude-manager.sh` copies `~/.claude/settings-zai.json` or `~/.claude/settings-anthropic.json` over `~/.claude/settings.json`. Claude Code reads that file on startup to pick the API endpoint and model. Every switch creates a timestamped backup in `~/.claude/backups/` so you can always roll back.

## Get tokens

- **Z.AI**: https://z.ai/manage-apikey/apikey-list
- **Anthropic**: https://console.anthropic.com/settings/keys
- **OpenRouter**: https://openrouter.ai/keys

> **Note on OpenRouter**: the template defaults to `anthropic/claude-3.5-sonnet` / `claude-3.5-haiku` / `claude-3-opus`. To use a different model (e.g. `openai/gpt-4o`, `meta-llama/llama-3.1-405b`), edit `~/.claude/settings-openrouter.json` and change the `ANTHROPIC_DEFAULT_*_MODEL` values. OpenRouter accepts Anthropic-format requests at `https://openrouter.ai/api/v1` and translates to whichever model you pick.

## Uninstall

```bash
rm ~/.claude/claude-manager.sh ~/.claude/settings-zai.json ~/.claude/settings-anthropic.json ~/.local/bin/cm
```

## Changelog

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
