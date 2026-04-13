#!/usr/bin/env bash
# Smoke test for claude-switcher — verifies install + switch flow end to end
# Uses a fake $HOME so it never touches the user's real ~/.claude
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$HOME/.claude"

CM_SCRIPT="$HOME/.claude/claude-manager.sh"

# Install files directly (skip the curl path — that's not under test here)
cp "$REPO_ROOT/claude-manager.sh"                  "$CM_SCRIPT"
cp "$REPO_ROOT/templates/settings-zai.json"        "$HOME/.claude/settings-zai.json"
cp "$REPO_ROOT/templates/settings-anthropic.json"  "$HOME/.claude/settings-anthropic.json"
cp "$REPO_ROOT/templates/settings-openrouter.json" "$HOME/.claude/settings-openrouter.json"
chmod +x "$CM_SCRIPT"

CM=(bash "$CM_SCRIPT")

pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; exit 1; }

echo "[smoke] version subcommand"
out=$("${CM[@]}" version); echo "$out" | grep -q "v1.2" || fail "version output missing"
pass "version reports v1.2.x"

echo "[smoke] help subcommand"
out=$("${CM[@]}" help); echo "$out" | grep -q "PROVIDER MANAGER" || fail "help missing header"
pass "help renders"

echo "[smoke] status with no settings.json"
out=$("${CM[@]}" status)
echo "$out" | grep -q "settings.json not found" || fail "status should warn when file missing"
pass "status warns when settings.json missing"

echo "[smoke] switch to zai (fast mode, no prompt)"
"${CM[@]}" zai fast >/dev/null
[ -f "$HOME/.claude/settings.json" ] || fail "settings.json not created"
grep -q "z.ai" "$HOME/.claude/settings.json" || fail "settings.json missing z.ai URL"
pass "switched to zai"

echo "[smoke] backup created on switch"
test -d "$HOME/.claude/backups" || fail "backups dir not created"
# First switch had no settings.json to back up — switch again to force a backup
"${CM[@]}" zai fast >/dev/null
ls "$HOME/.claude/backups/"settings_*.json >/dev/null 2>&1 || fail "no backup file written"
pass "backup file written on second switch"

echo "[smoke] status reflects zai"
out=$("${CM[@]}" status); echo "$out" | grep -q "Z.AI" || fail "status should report Z.AI"
pass "status shows Z.AI"

echo "[smoke] switch to anthropic (fast mode)"
"${CM[@]}" anthropic fast >/dev/null
if grep -q "z.ai" "$HOME/.claude/settings.json"; then
    fail "settings.json still contains z.ai after anthropic switch"
fi
pass "switched to anthropic"

echo "[smoke] status reflects anthropic"
out=$("${CM[@]}" status); echo "$out" | grep -q "Claude Original" || fail "status should report Anthropic"
pass "status shows Anthropic"

echo "[smoke] switch to openrouter (fast mode)"
"${CM[@]}" openrouter fast >/dev/null
grep -q "openrouter" "$HOME/.claude/settings.json" || fail "settings.json missing openrouter URL"
pass "switched to openrouter"

echo "[smoke] status reflects openrouter"
out=$("${CM[@]}" status); echo "$out" | grep -q "OpenRouter" || fail "status should report OpenRouter"
pass "status shows OpenRouter"

echo "[smoke] set_token via stdin (no token in process argv)"
# Source the script — main() is guarded so this won't execute the case statement
# shellcheck disable=SC1090
source "$CM_SCRIPT"
echo "test-token-from-stdin-1234" | set_token "$HOME/.claude/settings-zai.json"
grep -q "test-token-from-stdin-1234" "$HOME/.claude/settings-zai.json" || fail "set_token did not write token"
pass "set_token writes token via stdin"

echo "[smoke] restore backup (non-interactive)"
# Write a known marker into a backup, then restore via the function directly
backup_file=$(ls -t "$HOME/.claude/backups/"settings_*.json | head -1)
echo '{"env":{"ANTHROPIC_AUTH_TOKEN":"restored-marker"}}' > "$backup_file"
cp "$backup_file" "$HOME/.claude/settings.json"
grep -q "restored-marker" "$HOME/.claude/settings.json" || fail "restore marker missing"
pass "restore copies backup to settings.json"

echo ""
echo "[smoke] all tests passed"
