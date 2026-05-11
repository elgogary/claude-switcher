#!/usr/bin/env bash
# Claude Code Provider Switcher
# https://github.com/elgogary/claude-switcher

set -uo pipefail

VERSION="1.9.0"

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP_DIR="$CLAUDE_DIR/backups"
LAST_FILE="$CLAUDE_DIR/.cm-last"

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
# MODEL: primary model / fallback model
PROVIDER_MODELS=(
    "glm-5.1 / glm-4.5-air"
    "claude-sonnet-4 / claude-haiku-4"
    "varies"
    "deepseek-v4-pro / deepseek-v4-flash"
    "kimi-k2-0905-preview"
    "varies"
)
# CTX: context window size
PROVIDER_CTX=("200K" "200K" "varies" "1M" "256K" "varies")
# COST: input / output per 1M tokens (USD)
PROVIDER_COST=(
    "\$1.40 in / \$4.40 out"
    "\$3/\$15 Sonnet  |  \$15/\$75 Opus"
    "varies"
    "\$0.41 in / \$0.83 out (75% off thru May 31)"
    "\$0.60 in / \$2.50 out"
    "varies"
)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; GRAY='\033[0;90m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Find a working Python — Windows has `python`/`py`, Linux/macOS have `python3`.
# Windows also has a fake `python` that redirects to the Microsoft Store; we
# detect and skip it by checking if --version actually succeeds.
# -----------------------------------------------------------------------------
find_python() {
    local candidate out
    for candidate in python3 python py; do
        if command -v "$candidate" >/dev/null 2>&1; then
            # The Store-alias fake python exits 0 but prints to stderr only.
            # Real python prints "Python 3.x.y" to stdout.
            out=$("$candidate" --version 2>/dev/null || true)
            if [[ "$out" == Python* ]]; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}
PY=$(find_python || true)

require_python() {
    if [ -z "$PY" ]; then
        echo -e "${RED}[ERROR] Python not found.${NC}" >&2
        echo -e "${YELLOW}claude-switcher needs Python to read/write settings.json.${NC}" >&2
        echo -e "${YELLOW}Install it:${NC}" >&2
        echo -e "  Windows: ${WHITE}winget install Python.Python.3.12${NC}" >&2
        echo -e "  macOS:   ${WHITE}brew install python3${NC}" >&2
        echo -e "  Linux:   ${WHITE}sudo apt install python3${NC}" >&2
        echo -e "${YELLOW}After installing, open a NEW terminal and try again.${NC}" >&2
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# load_settings — single python call populates BASE_URL/TOKEN/SONNET/HAIKU/OPUS
# Replaces 7 duplicated python3 invocations (DRY + 5x faster status reads)
# -----------------------------------------------------------------------------
load_settings() {
    BASE_URL=""; TOKEN=""; SONNET=""; HAIKU=""; OPUS=""
    [ -f "$SETTINGS" ] || return 1
    require_python || return 1
    local key val
    while IFS=$'\t' read -r key val; do
        case "$key" in
            BASE_URL) BASE_URL="$val" ;;
            TOKEN)    TOKEN="$val" ;;
            SONNET)   SONNET="$val" ;;
            HAIKU)    HAIKU="$val" ;;
            OPUS)     OPUS="$val" ;;
        esac
    done < <("$PY" - "$SETTINGS" <<'PY'
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
    if [ -n "$idx" ]; then
        echo -e "${GREEN}Models      : ${PROVIDER_MODELS[$idx]}${NC}"
        echo -e "${GREEN}Context     : ${PROVIDER_CTX[$idx]}${NC}"
        echo -e "${YELLOW}Cost /1M tok: ${PROVIDER_COST[$idx]}${NC}"
    fi
    echo -e "${GRAY}Auth Token  : ${TOKEN:0:12}...${NC}"
    [ -n "$SONNET" ] && echo -e "${WHITE}  Sonnet (Active): $SONNET${NC}"
    [ -n "$HAIKU" ]  && echo -e "${WHITE}  Haiku  (Active): $HAIKU${NC}"
    [ -n "$OPUS" ]   && echo -e "${WHITE}  Opus   (Active): $OPUS${NC}"

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

    # save previous provider for `cm last`
    local prev
    prev=$(current_provider)
    [ "$prev" != "$provider" ] && [ "$prev" != "unknown" ] && echo "$prev" > "$LAST_FILE"

    backup_settings

    # MERGE template env into existing settings.json — preserves permissions,
    # plugins, model, and all other keys. Only the `env` section is replaced.
    require_python && "$PY" - "$SETTINGS" "$template" <<'PY'
import json, re, sys
settings_path, template_path = sys.argv[1], sys.argv[2]

# Read existing settings (or start fresh)
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

# Read template
with open(template_path) as f:
    template = json.load(f)

# Replace ONLY the env section from the template
template_env = template.get("env", {}) or {}
# Strip placeholder tokens before merging
template_env = {k: v for k, v in template_env.items()
                if not re.match(r'YOUR_.*_HERE$', str(v)) and v != ''}
settings["env"] = template_env

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY

    echo -e "${GREEN}[OK] Switched to $provider_name${NC}"

    # Warn if this looks like an active Claude Code session — the current window
    # will still use the old credentials until restarted.
    if [ -n "${CLAUDE_CODE:-}${ANTHROPIC_API_KEY:-}" ] || \
       ps aux 2>/dev/null | grep -q '[c]laude' || \
       [ -n "${TERM_PROGRAM:-}" ]; then
        echo -e "${YELLOW}[!] Open a NEW terminal tab or run /restart in Claude Code.${NC}"
        echo -e "${GRAY}    This window still uses the old provider until restarted.${NC}"
    else
        echo -e "${CYAN}Restart Claude Code to apply.${NC}"
    fi
    echo
}

# -----------------------------------------------------------------------------
# switch_last — toggle back to the previous provider
# -----------------------------------------------------------------------------
switch_last() {
    if [ ! -f "$LAST_FILE" ]; then
        echo -e "${RED}[ERROR] No previous provider recorded. Switch once first.${NC}" >&2
        return 1
    fi
    local prev
    prev=$(cat "$LAST_FILE")
    if ! provider_index "$prev" >/dev/null; then
        echo -e "${RED}[ERROR] Last provider '$prev' is no longer valid.${NC}" >&2
        return 1
    fi
    switch_provider "$prev" fast
}

# -----------------------------------------------------------------------------
# quick_status — single line, no API ping, instant
# -----------------------------------------------------------------------------
quick_status() {
    load_settings || { echo -e "${RED}not configured${NC}"; return; }
    local name label idx
    name=$(current_provider)
    if idx=$(provider_index "$name") 2>/dev/null; then
        label="${PROVIDER_LABELS[$idx]}"
    else
        label="Unknown"
    fi
    local tok_short="${TOKEN:0:8}..."
    [ -z "$TOKEN" ] && tok_short="(no token)"
    local last_label="" extra=""
    if [ -n "$idx" ]; then
        extra=" ${GRAY}[${PROVIDER_CTX[$idx]} ctx | ${PROVIDER_COST[$idx]}]${NC}"
    fi
    if [ -f "$LAST_FILE" ]; then
        local lp; lp=$(cat "$LAST_FILE")
        if idx=$(provider_index "$lp") 2>/dev/null; then
            last_label=" ${GRAY}(last: ${PROVIDER_LABELS[$idx]})${NC}"
        fi
    fi
    echo -e "${GREEN}●${NC} ${WHITE}$label${NC}  ${GRAY}$tok_short${NC}${extra}${last_label}"
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
    require_python || return 1
    local token
    token=$(cat)
    if [ -z "$token" ]; then
        echo -e "${RED}[ERROR] set_token: empty token${NC}" >&2
        return 1
    fi
    SWITCHER_TOKEN="$token" "$PY" - "$file" <<'PY' || return 1
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
# setup_quiet — non-interactive setup for agents / scripts / CI
#
# Reads tokens from env vars (one per provider):
#   CM_ZAI_TOKEN, CM_ANTHROPIC_TOKEN, CM_OPENROUTER_TOKEN,
#   CM_DEEPSEEK_TOKEN, CM_KIMI_TOKEN, CM_CUSTOM_TOKEN
#
# Optional: CM_START=<provider>  — switch to this provider after saving tokens.
#           If unset, auto-picks the first provider whose token was provided.
# Optional: CM_CUSTOM_URL=<url>  — for the custom provider, sets the base URL.
#
# Usage by an agent:
#   CM_ZAI_TOKEN="xxx" CM_ANTHROPIC_TOKEN="yyy" cm setup-quiet
# -----------------------------------------------------------------------------
setup_quiet() {
    echo -e "${CYAN}[claude-switcher] Non-interactive setup${NC}"
    local i name upper_name env_var token saved_any=""
    for i in "${!PROVIDER_NAMES[@]}"; do
        name="${PROVIDER_NAMES[$i]}"
        # Build env var name: CM_<UPPER>_TOKEN  (e.g. CM_ZAI_TOKEN)
        upper_name=$(echo "$name" | tr '[:lower:]' '[:upper:]')
        env_var="CM_${upper_name}_TOKEN"
        token="${!env_var:-}"
        if [ -n "$token" ]; then
            if printf '%s' "$token" | set_token "$CLAUDE_DIR/settings-$name.json"; then
                echo -e "  ${GREEN}[OK]${NC} saved ${PROVIDER_LABELS[$i]} token (from \$$env_var)"
                saved_any="${saved_any:-$name}"
            else
                echo -e "  ${RED}[FAIL]${NC} could not save ${PROVIDER_LABELS[$i]} token"
            fi
        fi
    done

    # Optional custom base URL (only meaningful for the custom provider)
    if [ -n "${CM_CUSTOM_URL:-}" ] && [ -f "$CLAUDE_DIR/settings-custom.json" ]; then
        require_python || return 1
        "$PY" - "$CLAUDE_DIR/settings-custom.json" "$CM_CUSTOM_URL" <<'PY'
import json, sys
path, url = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data.setdefault("env", {})["ANTHROPIC_BASE_URL"] = url
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
        echo -e "  ${GREEN}[OK]${NC} set custom base URL: $CM_CUSTOM_URL"
    fi

    if [ -z "$saved_any" ]; then
        echo -e "${YELLOW}[warn] No CM_*_TOKEN env vars set — nothing to save.${NC}"
        echo -e "${GRAY}Available: CM_ZAI_TOKEN CM_ANTHROPIC_TOKEN CM_OPENROUTER_TOKEN CM_DEEPSEEK_TOKEN CM_KIMI_TOKEN CM_CUSTOM_TOKEN${NC}"
        return 1
    fi

    # Pick starting provider
    local start="${CM_START:-$saved_any}"
    if provider_index "$start" >/dev/null; then
        switch_provider "$start" fast
    else
        echo -e "${YELLOW}[warn] Unknown CM_START=$start — skipping switch${NC}"
    fi

    echo -e "${GREEN}[DONE] Setup complete — restart Claude Code to apply.${NC}"
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
            if printf '%s' "$token" | set_token "$CLAUDE_DIR/settings-$name.json"; then
                echo -e "  ${GREEN}[OK] $label token saved${NC}"
            else
                echo -e "  ${RED}[FAIL] could not save $label token${NC}"
            fi
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
            printf "  ${WHITE}%s${NC}) %-22s ${GRAY}%-30s %-16s %s${NC}\n" \
                "$((i+1))" "${PROVIDER_LABELS[$i]}" "${PROVIDER_MODELS[$i]}" "${PROVIDER_CTX[$i]} ctx" "${PROVIDER_COST[$i]}"
        done
        echo -e "  ${WHITE}l${NC}) Switch to ${WHITE}l${NC}ast provider"
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
                l|L) switch_last; current=$(current_provider); read -r -p "Press Enter..." _ ;;
                t|T) show_status; read -r -p "Press Enter..." _ ;;
                b|B) restore_backup; current=$(current_provider); read -r -p "Press Enter..." _ ;;
                w|W) setup_wizard; current=$(current_provider); read -r -p "Press Enter..." _ ;;
                q|Q) echo -e "${CYAN}Bye!${NC}"; exit 0 ;;
                *) echo -e "${RED}Invalid choice${NC}"; sleep 1 ;;
            esac
        fi
    done
}

# -----------------------------------------------------------------------------
# test_token — ping a provider's API and check the token works
# Usage: test_token <provider>     (or empty = current active provider)
# -----------------------------------------------------------------------------
test_one_provider() {
    local name="$1"
    local idx
    if ! idx=$(provider_index "$name"); then
        echo -e "  ${RED}[?]${NC} unknown provider: $name"
        return 1
    fi
    local label="${PROVIDER_LABELS[$idx]}"
    local file="$CLAUDE_DIR/settings-$name.json"
    if [ ! -f "$file" ]; then
        echo -e "  ${YELLOW}[-]${NC} $label — template missing"
        return 1
    fi
    require_python || return 1
    # Read the settings for THIS provider's template
    local tok url
    tok=$("$PY" -c "import json; print(json.load(open('$file')).get('env',{}).get('ANTHROPIC_AUTH_TOKEN',''))" 2>/dev/null || true)
    url=$("$PY" -c "import json; print(json.load(open('$file')).get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null || true)

    if [ -z "$tok" ] || [[ "$tok" == YOUR_*_TOKEN_HERE ]]; then
        echo -e "  ${YELLOW}[-]${NC} $label — no token (run: cm setup)"
        return 1
    fi
    # Default base for native Anthropic if blank
    [ -z "$url" ] && url="https://api.anthropic.com"

    # Hit the messages endpoint with a minimal request. Status 200/400 = auth OK
    # (400 just means our request body was tiny, but the auth header was accepted).
    # Status 401/403 = bad token.
    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" \
        -X POST "${url}/v1/messages" \
        -H "x-api-key: $tok" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d '{"model":"claude-3-5-haiku-20241022","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        --max-time 10 2>/dev/null || echo "000")

    case "$http_code" in
        200)        echo -e "  ${GREEN}[OK]${NC}  $label — token VALID (200)" ;;
        400|404)    echo -e "  ${GREEN}[OK]${NC}  $label — token accepted ($http_code: model name not supported but auth works)" ;;
        401)        echo -e "  ${RED}[X]${NC}   $label — token INVALID (401 unauthorized)"; return 1 ;;
        403)        echo -e "  ${RED}[X]${NC}   $label — token FORBIDDEN (403)"; return 1 ;;
        429)        echo -e "  ${YELLOW}[!]${NC}  $label — token valid but RATE LIMITED (429)" ;;
	402)        echo -e "  ${YELLOW}[!]${NC}  $label — token VALID, but INSUFFICIENT BALANCE (402). Top up at ${PROVIDER_URLS[$idx]}" ;;
        000)        echo -e "  ${RED}[X]${NC}   $label — could not reach $url (network/DNS error)"; return 1 ;;
        *)          echo -e "  ${YELLOW}[?]${NC}  $label — unexpected HTTP $http_code from $url"; return 1 ;;
    esac
    return 0
}

test_token() {
    local target="${1:-}"
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] curl not found — required for cm test${NC}" >&2
        return 1
    fi
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}  Token validation${NC}"
    echo -e "${CYAN}========================================${NC}"
    if [ -n "$target" ]; then
        test_one_provider "$target"
    else
        # No arg → test all providers that have a non-placeholder token
        local i
        for i in "${!PROVIDER_NAMES[@]}"; do
            test_one_provider "${PROVIDER_NAMES[$i]}" || true
        done
    fi
    echo -e "${CYAN}========================================${NC}"
}

show_help() {
    echo
    echo -e "${CYAN}========================================${NC}"
    echo -e "${WHITE}CLAUDE CODE PROVIDER MANAGER${NC}  ${GRAY}v$VERSION${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  cm                    Open interactive menu"
    echo "  cm qs                 Quick status — one line, instant (no API ping)"
    echo "  cm last               Switch back to previous provider"
    echo "  cm setup              Run setup wizard (interactive, enter tokens)"
    echo "  cm setup-quiet        Non-interactive setup from CM_*_TOKEN env vars"
    echo "  cm test [provider]    Validate token by pinging the provider's API"
    local i
    for i in "${!PROVIDER_NAMES[@]}"; do
        printf "  cm %-16s %-22s ${GRAY}%-16s %s${NC}\n" \
            "${PROVIDER_NAMES[$i]} [fast]" "${PROVIDER_LABELS[$i]}" "${PROVIDER_CTX[$i]} ctx" "${PROVIDER_COST[$i]}"
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
        qs|quick)             quick_status; return ;;
        last|back|prev)       switch_last; return ;;
        restore)              restore_backup; return ;;
        setup|wizard)         setup_wizard; return ;;
        setup-quiet|quiet)    setup_quiet; return ;;
        test)                 test_token "${2:-}"; return ;;
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
