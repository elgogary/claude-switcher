#!/usr/bin/env bash
# Claude Code Provider Switcher
# https://github.com/elgogary/claude-switcher

set -uo pipefail

VERSION="1.3.0"

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP_DIR="$CLAUDE_DIR/backups"

mkdir -p "$BACKUP_DIR"

# -----------------------------------------------------------------------------
# Provider registry (data-driven — add a provider by appending one row each)
# -----------------------------------------------------------------------------
# NAMES: short names used for `cm <name>` and template filename `settings-<name>.json`
# LABELS: human-readable display name
# URLS: where to get the API token
# PATTERNS: substring of ANTHROPIC_BASE_URL to detect provider in current settings
#           (empty pattern = anthropic native, used as fallback)
PROVIDER_NAMES=(zai     anthropic              openrouter      deepseek                         kimi                                   custom)
PROVIDER_LABELS=("Z.AI (GLM)" "Claude (Anthropic)" "OpenRouter" "DeepSeek"                       "Moonshot Kimi"                        "Custom proxy")
PROVIDER_URLS=(
    "https://z.ai/manage-apikey/apikey-list"
    "https://console.anthropic.com/settings/keys"
    "https://openrouter.ai/keys"
    "https://platform.deepseek.com/api_keys"
    "https://platform.moonshot.cn/console/api-keys"
    "(set ANTHROPIC_BASE_URL in ~/.claude/settings-custom.json first)"
)
PROVIDER_PATTERNS=(z.ai "" openrouter deepseek moonshot "")

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

# Look up provider index by short name — returns index on stdout, 1 if not found
provider_index() {
    local target="$1" i
    for i in "${!PROVIDER_NAMES[@]}"; do
        [ "${PROVIDER_NAMES[$i]}" = "$target" ] && { echo "$i"; return 0; }
    done
    return 1
}

# Detect current provider by matching base_url against known patterns.
# Falls back to "anthropic" if any settings exist but no pattern matched.
current_provider() {
    load_settings || { echo "unknown"; return; }
    local i pattern
    for i in "${!PROVIDER_NAMES[@]}"; do
        pattern="${PROVIDER_PATTERNS[$i]}"
        [ -z "$pattern" ] && continue
        if [[ "$BASE_URL" == *"$pattern"* ]]; then
            echo "${PROVIDER_NAMES[$i]}"
            return
        fi
    done
    if [ -n "$BASE_URL$TOKEN" ]; then
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
    local name label idx
    name=$(current_provider)
    if idx=$(provider_index "$name"); then
        label="${PROVIDER_LABELS[$idx]}"
    else
        label="Unknown"
    fi

    echo -e "\n${YELLOW}[PROVIDER]${NC} ${WHITE}$label${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    if [ -n "$BASE_URL" ]; then
        echo -e "${WHITE}Base URL    : $BASE_URL${NC}"
    else
        echo -e "${WHITE}Base URL    : Default (api.anthropic.com)${NC}"
    fi
    echo -e "${GRAY}Auth Token  : ${TOKEN:0:12}...${NC}"
    [ -n "$SONNET" ] && echo -e "${GREEN}  Sonnet (Default): $SONNET${NC}"
    [ -n "$HAIKU" ]  && echo -e "${WHITE}  Haiku           : $HAIKU${NC}"
    [ -n "$OPUS" ]   && echo -e "${WHITE}  Opus            : $OPUS${NC}"

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

    local idx
    if ! idx=$(provider_index "$provider"); then
        echo -e "${RED}[ERROR] Unknown provider: $provider${NC}"
        echo -e "${YELLOW}Known: ${PROVIDER_NAMES[*]}${NC}"
        return 1
    fi
    local provider_name="${PROVIDER_LABELS[$idx]}"
    local template="$CLAUDE_DIR/settings-$provider.json"

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

    local total=${#PROVIDER_NAMES[@]}
    local i name label url token
    for i in "${!PROVIDER_NAMES[@]}"; do
        name="${PROVIDER_NAMES[$i]}"
        label="${PROVIDER_LABELS[$i]}"
        url="${PROVIDER_URLS[$i]}"
        echo -e "${YELLOW}[$((i+1))/$((total+1))] $label${NC}"
        echo -e "${GRAY}  $url${NC}"
        token=""
        read -r -s -p "  Token: " token
        echo
        if [ -n "$token" ]; then
            printf '%s' "$token" | set_token "$CLAUDE_DIR/settings-$name.json"
            echo -e "  ${GREEN}[OK] $label token saved${NC}"
        else
            echo -e "  ${GRAY}[skip]${NC}"
        fi
        unset token
        echo ""
    done

    echo -e "${YELLOW}[$((total+1))/$((total+1))] Which provider to start with?${NC}"
    for i in "${!PROVIDER_NAMES[@]}"; do
        echo -e "  ${WHITE}$((i+1))${NC}) ${PROVIDER_LABELS[$i]}"
    done
    echo -e "  ${WHITE}s${NC}) Skip"
    local pick=""
    read -r -n 1 -p "  Choose: " pick
    echo
    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "$total" ]; then
        switch_provider "${PROVIDER_NAMES[$((pick-1))]}" fast
    else
        echo -e "  ${GRAY}[skip]${NC}"
    fi

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
        local idx label
        if idx=$(provider_index "$current"); then
            label="${PROVIDER_LABELS[$idx]}"
            echo -e "  Current: ${GREEN}$label${NC}"
        else
            echo -e "  Current: ${RED}not configured${NC} ${GRAY}(run setup)${NC}"
        fi
        echo -e "${CYAN}========================================${NC}"
        echo ""
        local i
        for i in "${!PROVIDER_NAMES[@]}"; do
            echo -e "  ${WHITE}$((i+1))${NC}) Switch to ${PROVIDER_LABELS[$i]}"
        done
        echo -e "  ${WHITE}t${NC}) Show full s${WHITE}t${NC}atus"
        echo -e "  ${WHITE}b${NC}) Restore a ${WHITE}b${NC}ackup"
        echo -e "  ${WHITE}w${NC}) Run setup ${CYAN}w${NC}izard"
        echo -e "  ${WHITE}q${NC}) Quit"
        echo ""
        choice=""
        read -r -n 1 -p "Choose: " choice
        echo
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PROVIDER_NAMES[@]}" ]; then
            local picked="${PROVIDER_NAMES[$((choice-1))]}"
            switch_provider "$picked" fast
            current="$picked"
            read -r -p "Press Enter..." _
        else
            case "$choice" in
                t|T) show_status; read -r -p "Press Enter..." _ ;;
                b|B) restore_backup; current=$(current_provider); read -r -p "Press Enter..." _ ;;
                w|W) setup_wizard; current=$(current_provider); read -r -p "Press Enter..." _ ;;
                q|Q) echo -e "${CYAN}Bye!${NC}"; exit 0 ;;
                *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
            esac
        fi
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
    local i
    for i in "${!PROVIDER_NAMES[@]}"; do
        printf "  cm %-16s Switch to %s\n" "${PROVIDER_NAMES[$i]} [fast]" "${PROVIDER_LABELS[$i]}"
    done
    echo "  cm status             Show current provider"
    echo "  cm restore            Restore from backup"
    echo "  cm version            Show version"
    echo "  cm help               Show this help"
    echo
}

main() {
    local cmd="${1:-menu}"
    case "$cmd" in
        menu|"")              interactive_menu; return ;;
        check|status)         show_status; return ;;
        restore)              restore_backup; return ;;
        setup|wizard)         setup_wizard; return ;;
        version|-v|--version) echo "claude-switcher v$VERSION"; return ;;
        help|--help|-h)       show_help; return ;;
    esac
    # Aliases for legacy / convenience
    case "$cmd" in
        claude) cmd="anthropic" ;;
        z)      cmd="zai" ;;
        or)     cmd="openrouter" ;;
    esac
    # If it's a known provider, switch to it; otherwise error + help
    if provider_index "$cmd" >/dev/null; then
        switch_provider "$cmd" "${2:-}"
    else
        echo -e "${RED}[ERROR] Unknown command: $cmd${NC}" >&2
        show_help
        return 1
    fi
}

# Only run main when executed directly (not sourced — lets tests source the file)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]:-}" ]; then
    main "$@"
fi
