#!/usr/bin/env bash
# claude-switcher installer
# Usage: curl -fsSL https://raw.githubusercontent.com/elgogary/claude-switcher/main/install.sh | bash

set -e

REPO_RAW="https://raw.githubusercontent.com/elgogary/claude-switcher/main"
CLAUDE_DIR="$HOME/.claude"
BIN_DIR="$HOME/.local/bin"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}[claude-switcher] Installing...${NC}"

mkdir -p "$CLAUDE_DIR" "$BIN_DIR"

# 1. Download manager script
echo -e "${CYAN}[1/4] Downloading claude-manager.sh${NC}"
curl -fsSL "$REPO_RAW/claude-manager.sh" -o "$CLAUDE_DIR/claude-manager.sh"
chmod +x "$CLAUDE_DIR/claude-manager.sh"

# 2. Download settings templates (only if not already present)
echo -e "${CYAN}[2/4] Downloading settings templates${NC}"
for f in settings-zai.json settings-anthropic.json; do
  if [ -f "$CLAUDE_DIR/$f" ]; then
    echo -e "${YELLOW}  skip $f (already exists)${NC}"
  else
    curl -fsSL "$REPO_RAW/templates/$f" -o "$CLAUDE_DIR/$f"
    echo -e "${GREEN}  installed $f${NC}"
  fi
done

# 3. Create cm shortcut in ~/.local/bin
echo -e "${CYAN}[3/4] Creating 'cm' shortcut in $BIN_DIR${NC}"
cat > "$BIN_DIR/cm" <<'EOF'
#!/usr/bin/env bash
exec bash "$HOME/.claude/claude-manager.sh" "$@"
EOF
chmod +x "$BIN_DIR/cm"

# 4. PATH check
echo -e "${CYAN}[4/4] Checking PATH${NC}"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo -e "${YELLOW}  $BIN_DIR is not in PATH${NC}"
  echo -e "${YELLOW}  Add this to ~/.bashrc or ~/.zshrc:${NC}"
  echo -e "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo -e "${GREEN}[OK] Installed!${NC}"
echo ""

# Run the setup wizard automatically (only if running interactively)
if [ -t 0 ] && [ -t 1 ]; then
    echo -e "${CYAN}Starting setup wizard...${NC}"
    sleep 1
    bash "$CLAUDE_DIR/claude-manager.sh" setup
else
    echo "Next: run ${CYAN}cm setup${NC} to enter your tokens, or ${CYAN}cm${NC} for the menu."
fi
