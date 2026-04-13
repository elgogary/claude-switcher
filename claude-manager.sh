#!/bin/bash
# Claude Code Provider Switcher - Bash version

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
CONFIG="$CLAUDE_DIR/config.json"
BACKUP_DIR="$CLAUDE_DIR/backups"

mkdir -p "$BACKUP_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; GRAY='\033[0;90m'
NC='\033[0m'

backup_files() {
    local ts=$(date +%Y%m%d_%H%M%S)
    local count=0
    echo -e "${YELLOW}[BACKUP] Creating backup...${NC}"
    [ -f "$SETTINGS" ] && cp "$SETTINGS" "$BACKUP_DIR/settings_$ts.json" && ((count++))
    [ -f "$CONFIG" ] && cp "$CONFIG" "$BACKUP_DIR/config_$ts.json" && ((count++))
    echo -e "${GREEN}[BACKUP] Saved $count file(s)${NC}"
}

show_status() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}CLAUDE CODE - CURRENT STATUS${NC}"
    echo -e "${CYAN}========================================${NC}"

    if [ ! -f "$SETTINGS" ]; then
        echo -e "\n${RED}[ERROR] settings.json not found!${NC}"
        return
    fi

    local base_url=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
    local token=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_AUTH_TOKEN',''))" 2>/dev/null)
    local sonnet=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_DEFAULT_SONNET_MODEL','N/A'))" 2>/dev/null)
    local haiku=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_DEFAULT_HAIKU_MODEL','N/A'))" 2>/dev/null)
    local opus=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_DEFAULT_OPUS_MODEL','N/A'))" 2>/dev/null)

    if [[ "$base_url" == *z.ai* ]]; then
        echo -e "\n${YELLOW}[PROVIDER] Z.AI (GLM)${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${WHITE}Base URL    : $base_url${NC}"
        echo -e "${GRAY}Auth Token  : ${token:0:12}...${NC}"
        echo -e "${GREEN}  Sonnet (Default): $sonnet${NC}"
        echo -e "${WHITE}  Haiku           : $haiku${NC}"
        echo -e "${WHITE}  Opus            : $opus${NC}"
    else
        echo -e "\n${GREEN}[PROVIDER] Claude Original (Anthropic)${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${WHITE}Base URL    : Default (api.anthropic.com)${NC}"
        echo -e "${GRAY}Auth Token  : ${token:0:15}...${NC}"
        echo -e "${GREEN}  Sonnet (Default): $sonnet${NC}"
    fi

    local bk_count=$(ls -1 "$BACKUP_DIR"/settings_*.json 2>/dev/null | wc -l)
    echo -e "\n${CYAN}[BACKUPS]${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    if [ "$bk_count" -gt 0 ]; then
        echo -e "${GREEN}Available   : $bk_count backup(s)${NC}"
    else
        echo -e "${YELLOW}Available   : No backups yet${NC}"
    fi

    echo -e "\n${CYAN}[QUICK ACTIONS]${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${WHITE}  cm check     - Show status${NC}"
    echo -e "${WHITE}  cm anthropic - Switch to Anthropic${NC}"
    echo -e "${WHITE}  cm zai       - Switch to Z.AI${NC}"
    echo -e "${WHITE}  cm restore   - Restore backup${NC}"
    echo -e "\n${CYAN}========================================${NC}\n"
}

switch_provider() {
    local provider="$1"
    local fast="$2"

    if [ -f "$SETTINGS" ]; then
        local base_url=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
        local sonnet=$(python3 -c "import json; d=json.load(open('$SETTINGS')); print(d.get('env',{}).get('ANTHROPIC_DEFAULT_SONNET_MODEL','N/A'))" 2>/dev/null)
        echo -e "\n${CYAN}======================================${NC}"
        if [[ "$base_url" == *z.ai* ]]; then
            echo -e "${YELLOW}[CURRENT] Z.AI${NC}"
        else
            echo -e "${GREEN}[CURRENT] Claude Original (Anthropic)${NC}"
        fi
        echo -e "${CYAN}======================================${NC}"
        echo -e "${WHITE}DEFAULT MODEL: $sonnet${NC}"
        echo -e "${CYAN}======================================${NC}\n"
    fi

    local provider_name
    if [ "$provider" = "anthropic" ]; then
        provider_name="Claude Original (Anthropic)"
    else
        provider_name="Z.AI (GLM)"
    fi

    if [ "$fast" != "fast" ]; then
        echo -e "${CYAN}Switch to: $provider_name${NC}"
        read -p "[Y/N] " confirm
        confirm=${confirm:-y}
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo -e "\n${YELLOW}[CANCELLED]${NC}"
            return
        fi
    fi

    backup_files

    echo -e "\n${CYAN}[SWITCHING] Updating configuration...${NC}"

    if [ "$provider" = "anthropic" ]; then
        [ -f "$CLAUDE_DIR/settings-anthropic.json" ] && cp "$CLAUDE_DIR/settings-anthropic.json" "$SETTINGS" && echo -e "${GREEN}[OK] settings.json -> Anthropic${NC}"
        [ -f "$CLAUDE_DIR/config-anthropic.json" ] && cp "$CLAUDE_DIR/config-anthropic.json" "$CONFIG" && echo -e "${GREEN}[OK] config.json -> Anthropic${NC}"
        echo -e "\n${GREEN}[SUCCESS] Switched to Claude Original${NC}"
        echo -e "${WHITE}DEFAULT MODEL: claude-3-5-sonnet-20241022${NC}"
    else
        [ -f "$CLAUDE_DIR/settings-zai.json" ] && cp "$CLAUDE_DIR/settings-zai.json" "$SETTINGS" && echo -e "${GREEN}[OK] settings.json -> Z.AI${NC}"
        [ -f "$CLAUDE_DIR/config-zai.json" ] && cp "$CLAUDE_DIR/config-zai.json" "$CONFIG" && echo -e "${GREEN}[OK] config.json -> Z.AI${NC}"
        echo -e "\n${GREEN}[SUCCESS] Switched to Z.AI${NC}"
        echo -e "${WHITE}DEFAULT MODEL: glm-5.1 (NEWEST)${NC}"
    fi

    echo -e "\n${CYAN}[DONE] Settings updated! Restart Claude Code to apply.${NC}\n"
}

restore_backup() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/settings_*.json 2>/dev/null)" ]; then
        echo -e "\n${RED}[ERROR] No backups found!${NC}\n"
        return
    fi

    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}Available Backups${NC}"
    echo -e "${CYAN}========================================${NC}"

    local i=1
    local files=()
    for f in $(ls -t "$BACKUP_DIR"/settings_*.json); do
        local ts=$(basename "$f" | sed 's/settings_//;s/\.json//')
        local date_str="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
        echo -e "\n${YELLOW}$i) $date_str${NC}"
        files+=("$ts")
        ((i++))
    done

    echo -e "\n${CYAN}========================================${NC}\n"
    read -p "Restore which backup? [1-${#files[@]}] " num

    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#files[@]}" ]; then
        local ts="${files[$((num-1))]}"
        read -p "[Y/N] Confirm restore? " confirm
        confirm=${confirm:-y}
        if [[ "$confirm" =~ ^[Yy] ]]; then
            cp "$BACKUP_DIR/settings_$ts.json" "$SETTINGS"
            [ -f "$BACKUP_DIR/config_$ts.json" ] && cp "$BACKUP_DIR/config_$ts.json" "$CONFIG"
            echo -e "\n${GREEN}[SUCCESS] Backup restored!${NC}\n"
        else
            echo -e "\n${YELLOW}[CANCELLED]${NC}\n"
        fi
    else
        echo -e "\n${RED}[ERROR] Invalid number!${NC}\n"
    fi
}

# Main
case "${1:-help}" in
    check|status)
        show_status
        ;;
    anthropic|claude)
        switch_provider anthropic "$2"
        ;;
    zai|z)
        switch_provider zai "$2"
        ;;
    restore)
        restore_backup
        ;;
    help|*)
        echo -e "\n${CYAN}========================================${NC}"
        echo -e "${WHITE}CLAUDE CODE PROVIDER MANAGER${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo -e "\n${YELLOW}Usage:${NC}"
        echo -e "  ${WHITE}cm check              - Show current status${NC}"
        echo -e "  ${WHITE}cm anthropic          - Switch to Anthropic${NC}"
        echo -e "  ${WHITE}cm zai                - Switch to Z.AI${NC}"
        echo -e "  ${WHITE}cm restore            - Restore from backup${NC}"
        echo -e "\n${YELLOW}Fast mode (no prompts):${NC}"
        echo -e "  ${WHITE}cm anthropic fast     - Quick switch${NC}"
        echo -e "  ${WHITE}cm zai fast           - Quick switch${NC}"
        echo -e "\n${CYAN}========================================${NC}\n"
        ;;
esac
