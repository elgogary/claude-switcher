#!/usr/bin/env bash
# claude-switcher installer
# Usage: curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh | bash

set -euo pipefail

REPO="elgogary/claude-switcher"
BRANCH="main"
TARBALL_URL="https://github.com/$REPO/archive/$BRANCH.tar.gz"
CLAUDE_DIR="$HOME/.claude"
BIN_DIR="$HOME/.local/bin"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'

die()  { echo -e "${RED}[ERROR] $*${NC}" >&2; exit 1; }
info() { echo -e "${CYAN}$*${NC}"; }
ok()   { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }

info "[claude-switcher] Installing..."

# Dependency checks — fail fast with clear message
command -v curl    >/dev/null || die "curl is required"
command -v tar     >/dev/null || die "tar is required"
command -v python3 >/dev/null || die "python3 is required (used to read/write settings.json)"

mkdir -p "$CLAUDE_DIR" "$BIN_DIR"

# Atomic install via tarball — single network round trip, no partial state
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

info "[1/4] Downloading release..."
curl -fsSL "$TARBALL_URL" -o "$tmpdir/release.tar.gz" \
    || die "download failed: $TARBALL_URL"
tar -xzf "$tmpdir/release.tar.gz" -C "$tmpdir" \
    || die "extract failed"

src="$tmpdir/claude-switcher-$BRANCH"
[ -f "$src/claude-manager.sh" ]            || die "release missing claude-manager.sh"
# Verify all expected template files exist in the release
for t in zai anthropic openrouter deepseek kimi custom; do
    [ -f "$src/templates/settings-$t.json" ] || die "release missing templates/settings-$t.json"
done

# Backup existing manager script before overwrite (preserves user edits + downgrades)
info "[2/4] Installing claude-manager.sh"
if [ -f "$CLAUDE_DIR/claude-manager.sh" ]; then
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$CLAUDE_DIR/claude-manager.sh" "$CLAUDE_DIR/claude-manager.sh.bak.$ts"
    old_ver=$(grep -oE '^VERSION="[^"]+"' "$CLAUDE_DIR/claude-manager.sh" | head -1 | cut -d'"' -f2 || true)
    new_ver=$(grep -oE '^VERSION="[^"]+"' "$src/claude-manager.sh" | head -1 | cut -d'"' -f2 || true)
    warn "  upgrading: ${old_ver:-unknown} -> ${new_ver:-unknown}  (backup: claude-manager.sh.bak.$ts)"
fi
install -m 755 "$src/claude-manager.sh" "$CLAUDE_DIR/claude-manager.sh"

# Templates — only install if not already present (don't clobber user tokens)
info "[3/4] Installing templates"
for t in zai anthropic openrouter deepseek kimi custom; do
    f="settings-$t.json"
    if [ -f "$CLAUDE_DIR/$f" ]; then
        warn "  skip $f (already exists)"
    else
        install -m 600 "$src/templates/$f" "$CLAUDE_DIR/$f"
        ok "  installed $f"
    fi
done

# cm shortcut in ~/.local/bin
info "[4/4] Creating 'cm' shortcut"
cat > "$BIN_DIR/cm" <<'EOF'
#!/usr/bin/env bash
exec bash "$HOME/.claude/claude-manager.sh" "$@"
EOF
chmod +x "$BIN_DIR/cm"

# PATH check
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn ""
    warn "Note: $BIN_DIR is not in PATH"
    warn "Add this to ~/.bashrc or ~/.zshrc:"
    warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

ok ""
ok "[OK] claude-switcher installed!"
ok ""

# Decide what to do next — 3 paths:
#   1. Any CM_*_TOKEN env var is set → run setup-quiet (agent/stupid mode)
#   2. Running interactively (TTY) → launch interactive wizard
#   3. curl | bash with no TTY and no env vars → tell user what to do
if [ -n "${CM_ZAI_TOKEN:-}${CM_ANTHROPIC_TOKEN:-}${CM_OPENROUTER_TOKEN:-}${CM_DEEPSEEK_TOKEN:-}${CM_KIMI_TOKEN:-}${CM_CUSTOM_TOKEN:-}" ]; then
    info "Tokens detected in env vars — running non-interactive setup..."
    bash "$CLAUDE_DIR/claude-manager.sh" setup-quiet
elif [ -t 0 ] && [ -t 1 ]; then
    info "Starting setup wizard..."
    sleep 1
    bash "$CLAUDE_DIR/claude-manager.sh" setup
else
    info "Next: run 'cm setup' to enter your tokens, or 'cm' for the menu."
    info "Or: re-run with CM_ZAI_TOKEN=xxx (and others) for non-interactive setup."
fi
