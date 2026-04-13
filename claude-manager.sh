#!/usr/bin/env bash
# Claude Code Provider Switcher
# https://github.com/elgogary/claude-switcher

set -uo pipefail

VERSION="1.2.0"

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP_DIR="$CLAUDE_DIR/backups"

mkdir -p "$BACKUP_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; GRAY='\033[0;90m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# load_settings — single python3 call populates BASE_URL/TOKEN/SONNET/HAIKU/OPUS
# Replaces 7 duplicated python3 invocations (DRY + 5x faster status reads)
# -----------------------------------------------------------------------------
load_settings() {
    BASE_URL=""; TOKEN=""; SONNET=""; HAIKU=""; OPUS=""
    [ -f "$SETTINGS" ] || return 1
    local key val
    while IFS=$'\t' read -r key val; do
        case "$key" in
            BASE_URL) BASE_URL="$val" ;;
            TOKEN)    TOKEN="$val" ;;
            SONNET)   SONNET="$val" ;;
            HAIKU)    HAIKU="$val" ;;
            OPUS)     OPUS="$val" ;;
        esac
    done < <(python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        env = json.load(f).get("env", {}) or {}
except Exception:
    env = {}
fields = [
    ("BASE_URL", "ANTHROPIC_BASE_URL"),
    ("TOKEN",    "ANTHROPIC_AUTH_TOKEN"),
    ("SONNET",   "ANTHROPIC_DEFAULT_SONNET_MODEL"),
    ("HAIKU",    "ANTHROPIC_DEFAULT_HAIKU_MODEL"),
    ("OPUS",     "ANTHROPIC_DEFAULT_OPUS_MODEL"),
]
for var, key in fields:
    v = str(env.get(key, "")).replace("\t", " ").replace("\n", " ")
    print(f"{var}\t{v}")
PY
)
}

current_provider() {
    load_settings || { echo "unknown"; return; }
    if [[ "$BASE_URL" == *z.ai* ]]; then
        echo "zai"
    elif [[ "$BASE_URL" == *openrouter* ]]; then
        echo "openrouter"
    elif [ -n "$BASE_URL$TOKEN" ]; then
        echo "anthropic"
    else
        echo "unknown"
    fi
}

# -----------------------------------------------------------------------------
# Backup
# -----------------------------------------------------------------------------
backup_settings() {
    [ -f "$SETTINGS" ] || return 0
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    cp "$SETTINGS" "$BACKUP_DIR/settings_$ts.json"
    echo -e "${GRAY}[backup] saved settings_$ts.json${NC}"
}

# -----------------------------------------------------------------------------
# Show status
# -----------------------------------------------------------------------------
show_status() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}CLAUDE CODE - CURRENT STATUS${NC}"
    echo -e "${CYAN}========================================${NC}"

    if [ ! -f "$SETTINGS" ]; then
        echo -e "\n${RED}[ERROR] settings.json not found${NC}"
        echo -e "${YELLOW}Run: cm setup${NC}\n"
        return
    fi

    load_settings

    if [[ "$BASE_URL" == *z.ai* ]]; then
        echo -e "\n${YELLOW}[PROVIDER] Z.AI (GLM)${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${WHITE}Base URL    : $BASE_URL${NC}"
        echo -e "${GRAY}Auth Token  : ${TOKEN:0:12}...${NC}"
        echo -e "${GREEN}  Sonnet (Default): ${SONNET:-N/A}${NC}"
        echo -e "${WHITE}  Haiku           : ${HAIKU:-N/A}${NC}"
        echo -e "${WHITE}  Opus            : ${OPUS:-N/A}${NC}"
    elif [[ "$BASE_URL" == *openrouter* ]]; then
        echo -e "\n${CYAN}[PROVIDER] OpenRouter${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${WHITE}Base URL    : $BASE_URL${NC}"
        echo -e "${GRAY}Auth Token  : ${TOKEN:0:12}...${NC}"
        echo -e "${GREEN}  Sonnet (Default): ${SONNET:-N/A}${NC}"
        echo -e "${WHITE}  Haiku           : ${HAIKU:-N/A}${NC}"
        echo -e "${WHITE}  Opus            : ${OPUS:-N/A}${NC}"
    else
        echo -e "\n${GREEN}[PROVIDER] Claude Original (Anthropic)${NC}"
        echo -e "${CYAN}----------------------------------------${NC}"
        echo -e "${WHITE}Base URL    : Default (api.anthropic.com)${NC}"
        echo -e "${GRAY}Auth Token  : ${TOKEN:0:15}...${NC}"
        [ -n "$SONNET" ] && echo -e "${GREEN}  Sonnet (Default): $SONNET${NC}"
    fi

    local bk_count
    bk_count=$(find "$BACKUP_DIR" -maxdepth 1 -name 'settings_*.json' 2>/dev/null | wc -l)
    echo -e "\n${CYAN}[BACKUPS]${NC} $bk_count saved"
    echo -e "${CYAN}========================================${NC}\n"
}

# -----------------------------------------------------------------------------
# Switch provider
# -----------------------------------------------------------------------------
switch_provider() {
    local provider="$1"
    local fast="${2:-}"

    local provider_name template
    case "$provider" in
        anthropic)
            provider_name="Claude Original (Anthropic)"
            template="$CLAUDE_DIR/settings-anthropic.json"
            ;;
        openrouter)
            provider_name="OpenRouter"
            template="$CLAUDE_DIR/settings-openrouter.json"
            ;;
        zai|*)
            provider_name="Z.AI (GLM)"
            template="$CLAUDE_DIR/settings-zai.json"
            ;;
    esac

    if [ ! -f "$template" ]; then
        echo -e "${RED}[ERROR] Template not found: $template${NC}"
        echo -e "${YELLOW}Run: cm setup${NC}"
        return 1
    fi

    if [ "$fast" != "fast" ]; then
        echo -e "${CYAN}Switch to: $provider_name${NC}"
        local confirm=""
        read -r -p "[Y/n] " confirm
        confirm=${confirm:-y}
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo -e "${YELLOW}[CANCELLED]${NC}"
            return
        fi
    fi

    backup_settings
    cp "$template" "$SETTINGS"
    echo -e "${GREEN}[OK] Switched to $provider_name${NC}"
    echo -e "${CYAN}[DONE] Restart Claude Code to apply.${NC}\n"
}

# -----------------------------------------------------------------------------
# Restore from backup
# -----------------------------------------------------------------------------
restore_backup() {
    local files=()
    shopt -s nullglob
    files=("$BACKUP_DIR"/settings_*.json)
    shopt -u nullglob

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "\n${RED}[ERROR] No backups found!${NC}\n"
        return
    fi

    # Sort newest first (timestamp filenames sort lexically = chronologically)
    mapfile -t files < <(printf '%s\n' "${files[@]}" | sort -r)

    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${WHITE}Available Backups${NC}"
    echo -e "${CYAN}========================================${NC}"

    local i=1 f base ts date_str
    for f in "${files[@]}"; do
        base="${f##*/settings_}"
        ts="${base%.json}"
        date_str="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
        echo -e "${YELLOW}$i)${NC} $date_str"
        i=$((i+1))
    done
    echo ""

    local num=""
    read -r -p "Restore which? [1-${#files[@]}] " num
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#files[@]}" ]; then
        cp "${files[$((num-1))]}" "$SETTINGS"
        echo -e "${GREEN}[SUCCESS] Backup restored${NC}\n"
    else
        echo -e "${RED}[ERROR] Invalid choice${NC}\n"
    fi
}

# -----------------------------------------------------------------------------
# set_token — reads token from stdin (via env var, not argv)
# argv is world-readable in /proc/*/cmdline; env is restricted to same UID on
# modern Linux (/proc/*/environ has mode 0700). Same trust boundary as the file
# we're writing into. Token never appears in `ps aux`.
# -----------------------------------------------------------------------------
set_token() {
    local file="$1"
    local token
    token=$(cat)
    SWITCHER_TOKEN="$token" python3 - "$file" <<'PY'
import json, os, sys
path = sys.argv[1]
token = os.environ.get("SWITCHER_TOKEN", "")
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {"env": {}}
data.setdefault("env", {})["ANTHROPIC_AUTH_TOKEN"] = token
with open(path, "w") as f:
    json.dump(data, f, indent=2)
os.chmod(path, 0o600)
PY
}

# -----------------------------------------------------------------------------
# Setup wizard — prompts for tokens with hidden input
# -----------------------------------------------------------------------------
setup_wizard() {
    clear
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}  CLAUDE SWITCHER - SETUP WIZARD  ${GRAY}v$VERSION${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "Press ${YELLOW}Enter${NC} to skip a provider you don't use."
    echo -e "${GRAY}(Tokens are hidden as you type.)${NC}"
    echo ""

    echo -e "${YELLOW}[1/3] Z.AI (GLM) token${NC}"
    echo -e "${GRAY}  https://z.ai/manage-apikey/apikey-list${NC}"
    local zai_token=""
    read -r -s -p "  Z.AI token: " zai_token
    echo
    if [ -n "$zai_token" ]; then
        printf '%s' "$zai_token" | set_token "$CLAUDE_DIR/settings-zai.json"
        echo -e "  ${GREEN}[OK] Z.AI token saved${NC}"
    else
        echo -e "  ${GRAY}[skip]${NC}"
    fi
    unset zai_token
    echo ""

    echo -e "${YELLOW}[2/4] Anthropic token${NC}"
    echo -e "${GRAY}  https://console.anthropic.com/settings/keys${NC}"
    local anth_token=""
    read -r -s -p "  Anthropic token: " anth_token
    echo
    if [ -n "$anth_token" ]; then
        printf '%s' "$anth_token" | set_token "$CLAUDE_DIR/settings-anthropic.json"
        echo -e "  ${GREEN}[OK] Anthropic token saved${NC}"
    else
        echo -e "  ${GRAY}[skip]${NC}"
    fi
    unset anth_token
    echo ""

    echo -e "${YELLOW}[3/4] OpenRouter token${NC}"
    echo -e "${GRAY}  https://openrouter.ai/keys${NC}"
    local or_token=""
    read -r -s -p "  OpenRouter token: " or_token
    echo
    if [ -n "$or_token" ]; then
        printf '%s' "$or_token" | set_token "$CLAUDE_DIR/settings-openrouter.json"
        echo -e "  ${GREEN}[OK] OpenRouter token saved${NC}"
    else
        echo -e "  ${GRAY}[skip]${NC}"
    fi
    unset or_token
    echo ""

    echo -e "${YELLOW}[4/4] Which provider to start with?${NC}"
    echo -e "  ${WHITE}1)${NC} Z.AI (GLM)"
    echo -e "  ${WHITE}2)${NC} Anthropic (Claude)"
    echo -e "  ${WHITE}3)${NC} OpenRouter"
    echo -e "  ${WHITE}s)${NC} Skip"
    local pick=""
    read -r -n 1 -p "  Choose: " pick
    echo
    case "$pick" in
        1) switch_provider zai fast ;;
        2) switch_provider anthropic fast ;;
        3) switch_provider openrouter fast ;;
        *) echo -e "  ${GRAY}[skip]${NC}" ;;
    esac

    echo ""
    echo -e "${GREEN}[DONE] Setup complete! Restart Claude Code.${NC}"
    echo -e "Run ${CYAN}cm${NC} anytime to switch.\n"
}

# -----------------------------------------------------------------------------
# Interactive menu — caches current provider, only re-detects after a switch
# -----------------------------------------------------------------------------
interactive_menu() {
    local current
    current=$(current_provider)
    local choice=""
    while true; do
        clear
        echo -e "${CYAN}========================================${NC}"
        echo -e "${WHITE}  CLAUDE CODE PROVIDER SWITCHER  ${GRAY}v$VERSION${NC}"
        echo -e "${CYAN}========================================${NC}"
        case "$current" in
            zai)        echo -e "  Current: ${YELLOW}Z.AI (GLM)${NC}" ;;
            anthropic)  echo -e "  Current: ${GREEN}Claude (Anthropic)${NC}" ;;
            openrouter) echo -e "  Current: ${CYAN}OpenRouter${NC}" ;;
            *)          echo -e "  Current: ${RED}not configured${NC} ${GRAY}(run setup)${NC}" ;;
        esac
        echo -e "${CYAN}========================================${NC}"
        echo ""
        echo -e "  ${WHITE}1)${NC} Switch to ${YELLOW}Z.AI (GLM)${NC}"
        echo -e "  ${WHITE}2)${NC} Switch to ${GREEN}Claude (Anthropic)${NC}"
        echo -e "  ${WHITE}3)${NC} Switch to ${CYAN}OpenRouter${NC}"
        echo -e "  ${WHITE}4)${NC} Show full status"
        echo -e "  ${WHITE}5)${NC} Restore a backup"
        echo -e "  ${WHITE}s)${NC} ${CYAN}Run setup wizard${NC}"
        echo -e "  ${WHITE}q)${NC} Quit"
        echo ""
        choice=""
        read -r -n 1 -p "Choose: " choice
        echo
        case "$choice" in
            1) switch_provider zai fast; current="zai"; read -r -p "Press Enter..." _ ;;
            2) switch_provider anthropic fast; current="anthropic"; read -r -p "Press Enter..." _ ;;
            3) switch_provider openrouter fast; current="openrouter"; read -r -p "Press Enter..." _ ;;
            4) show_status; read -r -p "Press Enter..." _ ;;
            5) restore_backup; current=$(current_provider); read -r -p "Press Enter..." _ ;;
            s|S) setup_wizard; current=$(current_provider); read -r -p "Press Enter..." _ ;;
            q|Q) echo -e "${CYAN}Bye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

show_help() {
    echo
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}CLAUDE CODE PROVIDER MANAGER${NC}  ${GRAY}v$VERSION${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  cm                    Open interactive menu"
    echo "  cm setup              Run setup wizard (enter tokens)"
    echo "  cm zai [fast]         Switch to Z.AI (GLM)"
    echo "  cm anthropic [fast]   Switch to Anthropic (Claude)"
    echo "  cm openrouter [fast]  Switch to OpenRouter"
    echo "  cm status             Show current provider"
    echo "  cm restore            Restore from backup"
    echo "  cm version            Show version"
    echo "  cm help               Show this help"
    echo
}

main() {
    case "${1:-menu}" in
        menu|"")              interactive_menu ;;
        check|status)         show_status ;;
        anthropic|claude)     switch_provider anthropic "${2:-}" ;;
        zai|z)                switch_provider zai "${2:-}" ;;
        openrouter|or)        switch_provider openrouter "${2:-}" ;;
        restore)              restore_backup ;;
        setup|wizard)         setup_wizard ;;
        version|-v|--version) echo "claude-switcher v$VERSION" ;;
        help|--help|-h|*)     show_help ;;
    esac
}

# Only run main when executed directly (not sourced — lets tests source the file)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]:-}" ]; then
    main "$@"
fi
