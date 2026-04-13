# claude-switcher

One-command provider switcher for [Claude Code](https://docs.claude.com/en/docs/claude-code) — flip between **Anthropic** and **Z.AI (GLM)** without editing JSON by hand.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh | bash
```

This installs:
- `~/.claude/claude-manager.sh` — the switcher script
- `~/.claude/settings-zai.json` + `~/.claude/settings-anthropic.json` — provider templates
- `~/.local/bin/cm` — short alias

## Setup

Edit the templates and put your real API tokens:

```bash
nano ~/.claude/settings-zai.json         # ANTHROPIC_AUTH_TOKEN = your Z.AI key
nano ~/.claude/settings-anthropic.json   # ANTHROPIC_AUTH_TOKEN = your Anthropic key
```

Get tokens:
- **Z.AI**: https://z.ai/manage-apikey/apikey-list
- **Anthropic**: https://console.anthropic.com/settings/keys

## Usage

```bash
cm zai          # switch to Z.AI (GLM-5.1)
cm anthropic    # switch to Claude (Anthropic)
cm status       # show current provider
cm help         # show help
```

Restart Claude Code after switching.

## How it works

The script copies `settings-zai.json` or `settings-anthropic.json` over `~/.claude/settings.json`. Claude Code reads that file on startup to pick the API endpoint and model.

## Uninstall

```bash
rm ~/.claude/claude-manager.sh ~/.claude/settings-zai.json ~/.claude/settings-anthropic.json ~/.local/bin/cm
```

## License

MIT
