#!/usr/bin/env bash
set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.6.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_CONFIG_DIR="$HOME/.config/smb-mounter"
DEFAULT_CONFIG_FILE="$DEFAULT_CONFIG_DIR/config.env"
DEFAULT_DEFAULT_CONFIG="$DEFAULT_CONFIG_DIR/config.env.default"
DEFAULT_CREDS_FILE="$DEFAULT_CONFIG_DIR/credentials"
DEFAULT_LEDGER_FILE="$DEFAULT_CONFIG_DIR/ledger.log"
DEFAULT_FSTAB_BACKUP="/etc/fstab.smb-mounter.bak"
DEFAULT_FSTAB_MARKER="# smb-mounter-managed"

DEFAULT_HOST="nas.local"
DEFAULT_SHARE_PATH="share/folder"
DEFAULT_MOUNT_POINT="/mnt/smb-share"
DEFAULT_HOME_LINK="$HOME/Documents/SMB-Share"
DEFAULT_USER="smbuser"
DEFAULT_DOMAIN="WORKGROUP"
DEFAULT_UID="$(id -u)"
DEFAULT_GID="$(id -g)"
DEFAULT_MAX_RETRIES="3"

CONFIG_DIR="$DEFAULT_CONFIG_DIR"
CONFIG_FILE="$DEFAULT_CONFIG_FILE"
CREDS_FILE="$DEFAULT_CREDS_FILE"
LEDGER_FILE="$DEFAULT_LEDGER_FILE"
FSTAB_BACKUP="$DEFAULT_FSTAB_BACKUP"
FSTAB_MARKER="$DEFAULT_FSTAB_MARKER"

HOST="$DEFAULT_HOST"
SHARE_PATH="$DEFAULT_SHARE_PATH"
MOUNT_POINT="$DEFAULT_MOUNT_POINT"
HOME_LINK="$DEFAULT_HOME_LINK"
SMB_USER="$DEFAULT_USER"
SMB_DOMAIN="$DEFAULT_DOMAIN"
MOUNT_UID="$DEFAULT_UID"
MOUNT_GID="$DEFAULT_GID"
MAX_RETRIES="$DEFAULT_MAX_RETRIES"

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_CYAN=$'\033[36m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_CYAN="" C_GREEN="" C_YELLOW="" C_RED=""
fi

draw_box() {
    local title="$1"
    local subtitle="${2:-}"
    local width=66
    local inner=$((width - 2))
    printf "%b+%s+%b\n" "$C_CYAN" "$(printf '%*s' "$inner" '' | tr ' ' '-')" "$C_RESET"
    printf "%b| %b%-*s%b |%b\n" "$C_CYAN" "$C_BOLD" "$((inner - 2))" "$title" "$C_RESET$C_CYAN" "$C_RESET"
    if [[ -n "$subtitle" ]]; then
        printf "%b| %b%-*s%b |%b\n" "$C_CYAN" "$C_DIM" "$((inner - 2))" "$subtitle" "$C_RESET$C_CYAN" "$C_RESET"
    fi
    printf "%b+%s+%b\n" "$C_CYAN" "$(printf '%*s' "$inner" '' | tr ' ' '-')" "$C_RESET"
}

step_status() {
    local state="$1"
    local msg="$2"
    case "$state" in
        ok)   printf "  %b[ OK ]%b %s\n" "$C_GREEN$C_BOLD" "$C_RESET" "$msg" ;;
        warn) printf "  %b[WARN]%b %s\n" "$C_YELLOW$C_BOLD" "$C_RESET" "$msg" ;;
        fail) printf "  %b[FAIL]%b %s\n" "$C_RED$C_BOLD" "$C_RESET" "$msg" ;;
        info) printf "  %b[INFO]%b %s\n" "$C_CYAN$C_BOLD" "$C_RESET" "$msg" ;;
    esac
}

show_steamos_notice() {
    printf "\n"
    draw_box "STEAMOS IMMUTABLE NOTICE" "Boot mounts & system files across OS updates"
    printf "  %b[WARN]%b SteamOS is immutable: system updates may remove or reset\n" "$C_YELLOW$C_BOLD" "$C_RESET"
    printf "         /etc/fstab entries or mount units after an update.\n"
    printf "  %b[INFO]%b Re-run './%s fstab' or './%s mount' anytime.\n\n" "$C_CYAN$C_BOLD" "$SCRIPT_NAME" "$SCRIPT_NAME"
}

show_options_hint() {
    printf "\n"
    draw_box "$SCRIPT_NAME v$SCRIPT_VERSION" "Generic SMB/CIFS Mount Manager (Distributable)"
    cat << EOF

SYNOPSIS
  ./$SCRIPT_NAME [COMMAND] [OPTIONS]

COMMANDS
  mount (up)            Mount SMB share, create home link, and log to ledger
  umount (down)         Unmount SMB share and remove home folder symlink
  fstab                 Add or update boot automount entry in /etc/fstab
  check-fstab           Inspect /etc/fstab and automount configuration
  remove-fstab          Remove managed or target /etc/fstab entry
  ledger                Display recorded actions (mounts, links, fstab, dirs)
  cleanup               Auto clean up all mounts, links, fstab entries & dirs
  status                Show config, mount state, home link, and fstab state
  setup (wizard)        Interactive configuration & credentials wizard
  features [TOPIC]      Show comprehensive feature overview (all or one topic)
  help [-v|--verbose]   Show brief usage (-h/help/?) or full manual (--help)

GENERIC DEFAULTS & PATHS (CONFIGURABLE IN config.env / config.env.default)
  Share / Mount   : //${DEFAULT_HOST}/${DEFAULT_SHARE_PATH} -> ${DEFAULT_MOUNT_POINT}
  Home Link       : ${DEFAULT_HOME_LINK} -> ${DEFAULT_MOUNT_POINT}
  Config File     : ${DEFAULT_CONFIG_FILE}
  Default Template: ${DEFAULT_DEFAULT_CONFIG}
  Creds File      : ${DEFAULT_CREDS_FILE}
  Ledger File     : ${DEFAULT_LEDGER_FILE}

EOF
}

show_feature_detail() {
    local topic="${1:-all}"
    topic="${topic#--}"
    case "$topic" in
        mount|up)
            printf "\n"
            draw_box "FEATURE: mount (up)" "Optional config/ledger bootstrap, CIFS mount, retries & link"
            cat << EOF

  Purpose:
    Mounts the configured SMB/CIFS share onto the system mount point and links
    it into the user's home folder. Works without requiring a config file upfront.

  Example:
    ./$SCRIPT_NAME mount

EOF
            ;;
        umount|down)
            printf "\n"
            draw_box "FEATURE: umount (down)" "Safe detachment & home symlink removal"
            cat << EOF

  Purpose:
    Removes the home folder symlink and unmounts the SMB share cleanly (with
    lazy unmount fallback if busy).

  Example:
    ./$SCRIPT_NAME umount

EOF
            ;;
        fstab)
            printf "\n"
            draw_box "FEATURE: fstab" "Persistent boot/automount configuration via /etc/fstab"
            cat << EOF

  Purpose:
    Writes a tagged CIFS entry to /etc/fstab using '_netdev,nofail,x-systemd.automount'
    and displays the SteamOS immutable system notice.

  Example:
    ./$SCRIPT_NAME fstab

EOF
            ;;
        check-fstab|automount-check)
            printf "\n"
            draw_box "FEATURE: check-fstab" "Automount status inspection"
            cat << EOF

  Purpose:
    Checks /etc/fstab for active entries matching the mount point and reports
    automount options and management tags.

  Example:
    ./$SCRIPT_NAME check-fstab

EOF
            ;;
        remove-fstab|unfstab|automount-remove)
            printf "\n"
            draw_box "FEATURE: remove-fstab" "Remove automount entry from /etc/fstab"
            cat << EOF

  Purpose:
    Removes managed or matching mount entries from /etc/fstab, reloads
    systemd, and records the removal in the ledger.

  Example:
    ./$SCRIPT_NAME remove-fstab

EOF
            ;;
        ledger)
            printf "\n"
            draw_box "FEATURE: ledger" "Audit trail of managed resources (configurable path)"
            cat << EOF

  Purpose:
    Displays entries from the configured ledger file. If missing, offers to
    create it now.

  Example:
    ./$SCRIPT_NAME ledger

EOF
            ;;
        cleanup|clean|purge)
            printf "\n"
            draw_box "FEATURE: cleanup" "Automated teardown of managed mounts, links & fstab entries"
            cat << EOF

  Purpose:
    Cleans up tracked home symlinks, /etc/fstab entries, active mounts, and
    empty mount directories.

  Example:
    ./$SCRIPT_NAME cleanup

EOF
            ;;
        status)
            printf "\n"
            draw_box "FEATURE: status" "Live state summary across config, fstab, mount & symlink"
            cat << EOF

  Purpose:
    Displays current config, ledger, /etc/fstab, mount, symlink, and SteamOS
    notice status without requiring a prior config file.

  Example:
    ./$SCRIPT_NAME status

EOF
            ;;
        setup|wizard|config)
            printf "\n"
            draw_box "FEATURE: setup" "Interactive setup, template/existing config import & wizard"
            cat << EOF

  Purpose:
    Lets you copy config.env.default or an existing config file into the config
    directory, or create/update config.env, credentials, and /etc/fstab.

  Example:
    ./$SCRIPT_NAME setup

EOF
            ;;
        all|verbose|manual)
            printf "\n"
            draw_box "$SCRIPT_NAME v$SCRIPT_VERSION — FULL MANUAL" "Comprehensive Reference for All Features"
            show_feature_detail "mount"
            show_feature_detail "umount"
            show_feature_detail "fstab"
            show_feature_detail "check-fstab"
            show_feature_detail "remove-fstab"
            show_feature_detail "ledger"
            show_feature_detail "cleanup"
            show_feature_detail "status"
            show_feature_detail "setup"
            show_steamos_notice
            ;;
        *)
            step_status fail "Unknown feature topic: $topic"
            printf "  Try './%s features' for the full manual or './%s help' for commands.\n\n" "$SCRIPT_NAME" "$SCRIPT_NAME"
            return 1
            ;;
    esac
}

find_default_template() {
    if [[ -f "$DEFAULT_DEFAULT_CONFIG" ]]; then
        printf "%s\n" "$DEFAULT_DEFAULT_CONFIG"
        return 0
    fi
    if [[ -f "$SCRIPT_DIR/config.env.default" ]]; then
        printf "%s\n" "$SCRIPT_DIR/config.env.default"
        return 0
    fi
    return 1
}

load_config() {
    CONFIG_DIR="$DEFAULT_CONFIG_DIR"
    CONFIG_FILE="$DEFAULT_CONFIG_FILE"
    CREDS_FILE="$DEFAULT_CREDS_FILE"
    LEDGER_FILE="$DEFAULT_LEDGER_FILE"
    FSTAB_BACKUP="$DEFAULT_FSTAB_BACKUP"
    FSTAB_MARKER="$DEFAULT_FSTAB_MARKER"

    HOST="$DEFAULT_HOST"
    SHARE_PATH="$DEFAULT_SHARE_PATH"
    MOUNT_POINT="$DEFAULT_MOUNT_POINT"
    HOME_LINK="$DEFAULT_HOME_LINK"
    SMB_USER="$DEFAULT_USER"
    SMB_DOMAIN="$DEFAULT_DOMAIN"
    MOUNT_UID="$DEFAULT_UID"
    MOUNT_GID="$DEFAULT_GID"
    MAX_RETRIES="$DEFAULT_MAX_RETRIES"

    if [[ -f "$CONFIG_FILE" ]]; then
        if ! source "$CONFIG_FILE" 2>/dev/null; then
            step_status warn "Could not read $CONFIG_FILE; using generic defaults"
        fi
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    cat << EOF > "$CONFIG_FILE"
CONFIG_DIR="$CONFIG_DIR"
CONFIG_FILE="$CONFIG_FILE"
CREDS_FILE="$CREDS_FILE"
LEDGER_FILE="$LEDGER_FILE"
FSTAB_BACKUP="$FSTAB_BACKUP"
FSTAB_MARKER="$FSTAB_MARKER"

HOST="$HOST"
SHARE_PATH="$SHARE_PATH"
MOUNT_POINT="$MOUNT_POINT"
HOME_LINK="$HOME_LINK"
SMB_USER="$SMB_USER"
SMB_DOMAIN="$SMB_DOMAIN"
MOUNT_UID="$MOUNT_UID"
MOUNT_GID="$MOUNT_GID"
MAX_RETRIES="$MAX_RETRIES"
EOF
    chmod 600 "$CONFIG_FILE"
}

prompt_import_existing_config() {
    local src_path=""
    read -r -p "Enter path to existing config file to copy into $CONFIG_FILE (or Enter to skip): " src_path
    [[ -z "$src_path" ]] && return 1

    src_path="${src_path/#\~/$HOME}"

    if [[ ! -f "$src_path" ]]; then
        step_status warn "File not found: $src_path"
        return 1
    fi

    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    if [[ "$(cd "$(dirname "$src_path")" && pwd)/$(basename "$src_path")" == "$CONFIG_FILE" ]]; then
        step_status ok "Source is already at $CONFIG_FILE"
        return 0
    fi

    if cp "$src_path" "$CONFIG_FILE"; then
        chmod 600 "$CONFIG_FILE"
        step_status ok "Copied config from $src_path to $CONFIG_FILE"
        load_config
        return 0
    fi

    step_status fail "Failed to copy $src_path to $CONFIG_FILE"
    return 1
}

ensure_config_optional() {
    if [[ -f "$CONFIG_FILE" ]]; then
        return 0
    fi

    local tpl=""
    tpl="$(find_default_template || true)"

    printf "\n"
    draw_box "CONFIG FILE NOT FOUND (OPTIONAL)" "$CONFIG_FILE"
    printf "\n"
    step_status info "No config file is required to run; generic defaults are active."
    step_status warn "Config file not found at $CONFIG_FILE — it can be created or copied now."
    if [[ -n "$tpl" ]]; then
        printf "  1) Copy template (%s) into %s now\n" "$tpl" "$CONFIG_FILE"
    else
        printf "  1) Create a new config file from generic defaults now\n"
    fi
    printf "  2) Copy an existing config file into %s now\n" "$CONFIG_DIR"
    printf "  3) Run interactive setup wizard now\n"
    printf "  4) Continue without a config file (no setup required)\n\n"
    read -r -p "Choose an option [1-4, default 4]: " choice

    case "$choice" in
        1)
            mkdir -p "$CONFIG_DIR"
            chmod 700 "$CONFIG_DIR"
            if [[ -n "$tpl" ]]; then
                cp "$tpl" "$CONFIG_FILE"
            else
                save_config
            fi
            chmod 600 "$CONFIG_FILE"
            step_status ok "Created config file at $CONFIG_FILE"
            load_config
            return 0
            ;;
        2)
            if prompt_import_existing_config; then
                return 0
            fi
            return 1
            ;;
        3)
            run_wizard "skip_mount"
            return 0
            ;;
        *)
            step_status info "Continuing with generic defaults (no config file required)."
            return 1
            ;;
    esac
}

ensure_ledger() {
    local interactive="${1:-no}"
    mkdir -p "$(dirname "$LEDGER_FILE")"
    chmod 700 "$(dirname "$LEDGER_FILE")" 2>/dev/null || true

    if [[ ! -f "$LEDGER_FILE" ]]; then
        if [[ "$interactive" == "yes" ]]; then
            printf "\n"
            step_status warn "Ledger file not found at $LEDGER_FILE"
            local reply
            read -r -p "Create ledger file at $LEDGER_FILE now? [Y/n]: " reply
            if [[ "${reply,,}" == "n" || "${reply,,}" == "no" ]]; then
                step_status info "Skipping ledger file creation for now."
                return 1
            fi
        else
            step_status info "Creating ledger file at $LEDGER_FILE"
        fi
        printf "# timestamp|action|target|detail\n" > "$LEDGER_FILE"
        chmod 600 "$LEDGER_FILE"
        step_status ok "Created ledger file: $LEDGER_FILE"
    fi
    return 0
}

record_ledger() {
    local action="$1"
    local target="$2"
    local detail="${3:-}"
    local ts
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    ensure_ledger "no" || return 0
    printf "%s|%s|%s|%s\n" "$ts" "$action" "$target" "$detail" >> "$LEDGER_FILE"
}

check_fstab_automount() {
    ensure_config_optional || true
    load_config
    printf "\n"
    draw_box "AUTOMOUNT CHECK" "Inspecting /etc/fstab for $MOUNT_POINT"
    printf "\n"

    local matches
    matches="$(awk -v mp="$MOUNT_POINT" '$0 !~ /^[[:space:]]*#/ && $2 == mp {print $0}' /etc/fstab 2>/dev/null || true)"

    if [[ -n "$matches" ]]; then
        step_status ok "Mount point $MOUNT_POINT IS set in /etc/fstab:"
        while IFS= read -r line; do
            printf "    %s\n" "$line"
            if [[ "$line" == *"noauto"* ]] && [[ "$line" != *"x-systemd.automount"* ]]; then
                step_status warn "Entry includes 'noauto' without 'x-systemd.automount'"
            else
                step_status ok "Configured for boot/automount behavior"
            fi
        done <<< "$matches"
    else
        step_status warn "No active /etc/fstab entry found for $MOUNT_POINT"
    fi

    if grep -qF "$FSTAB_MARKER" /etc/fstab 2>/dev/null; then
        step_status ok "Managed entry tag present ($FSTAB_MARKER)"
    else
        step_status info "No management marker found in /etc/fstab"
    fi
    printf "\n"
}

remove_fstab_automount() {
    ensure_config_optional || true
    load_config
    printf "\n"
    draw_box "REMOVE AUTOMOUNT ENTRY" "Target: $MOUNT_POINT"
    printf "\n"

    if ! grep -qF "$FSTAB_MARKER" /etc/fstab 2>/dev/null && \
       ! awk -v mp="$MOUNT_POINT" '$0 !~ /^[[:space:]]*#/ && $2 == mp {found=1} END {exit !found}' /etc/fstab 2>/dev/null; then
        step_status warn "No /etc/fstab entry found for $MOUNT_POINT to remove"
        return 0
    fi

    local confirm
    read -r -p "Remove automount entry for $MOUNT_POINT from /etc/fstab? [Y/n]: " confirm
    if [[ "${confirm,,}" == "n" || "${confirm,,}" == "no" ]]; then
        step_status info "Cancelled /etc/fstab removal."
        return 0
    fi

    if [[ ! -f "$FSTAB_BACKUP" ]]; then
        sudo cp /etc/fstab "$FSTAB_BACKUP" || true
    fi

    local tmp_fstab
    tmp_fstab="$(mktemp)"
    awk -v mp="$MOUNT_POINT" -v marker="$FSTAB_MARKER" '
        index($0, marker) > 0 { next }
        $0 !~ /^[[:space:]]*#/ && $2 == mp { next }
        { print }
    ' /etc/fstab > "$tmp_fstab"

    if sudo cp "$tmp_fstab" /etc/fstab; then
        rm -f "$tmp_fstab"
        step_status ok "Removed /etc/fstab automount entry for $MOUNT_POINT"
        record_ledger "fstab_remove" "$MOUNT_POINT" "removed from /etc/fstab"
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl daemon-reload 2>/dev/null || true
            step_status ok "Reloaded systemd manager configuration"
        fi
        return 0
    fi

    rm -f "$tmp_fstab"
    step_status fail "Failed to update /etc/fstab"
    return 1
}

configure_fstab() {
    ensure_config_optional || true
    load_config
    show_steamos_notice

    local share_unc="//${HOST}/${SHARE_PATH}"
    local fstab_opts="uid=${MOUNT_UID},gid=${MOUNT_GID},iocharset=utf8,vers=3.0,_netdev,nofail,x-systemd.automount"
    if [[ -f "$CREDS_FILE" ]]; then
        fstab_opts="credentials=${CREDS_FILE},${fstab_opts}"
    else
        fstab_opts="username=${SMB_USER},domain=${SMB_DOMAIN},${fstab_opts}"
    fi

    local entry="${share_unc} ${MOUNT_POINT} cifs ${fstab_opts} 0 0 ${FSTAB_MARKER}"

    printf "\n"
    draw_box "FSTAB BOOT MOUNT" "Target: $MOUNT_POINT"
    printf "\n"
    step_status info "Entry to write: $entry"
    printf "\n"

    local confirm
    read -r -p "Add or update this mount in /etc/fstab for boot? [Y/n]: " confirm
    if [[ "${confirm,,}" == "n" || "${confirm,,}" == "no" ]]; then
        step_status info "Skipped /etc/fstab update."
        return 0
    fi

    sudo mkdir -p "$MOUNT_POINT"
    record_ledger "mkdir" "$MOUNT_POINT" "created for fstab"

    if [[ ! -f "$FSTAB_BACKUP" ]]; then
        sudo cp /etc/fstab "$FSTAB_BACKUP" || true
    fi

    local tmp_fstab
    tmp_fstab="$(mktemp)"
    grep -vF "$FSTAB_MARKER" /etc/fstab > "$tmp_fstab"
    printf "%s\n" "$entry" >> "$tmp_fstab"

    if sudo cp "$tmp_fstab" /etc/fstab; then
        rm -f "$tmp_fstab"
        step_status ok "Updated /etc/fstab for $MOUNT_POINT"
        record_ledger "fstab_add" "$MOUNT_POINT" "$share_unc"
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl daemon-reload 2>/dev/null || true
            step_status ok "Reloaded systemd manager configuration"
        fi
        return 0
    fi

    rm -f "$tmp_fstab"
    step_status fail "Failed to write /etc/fstab"
    return 1
}

run_wizard() {
    local mode="${1:-full}"
    load_config
    printf "\n"
    draw_box "SMB MOUNT SETUP WIZARD" "Config, Existing Config Import, Credentials & Boot Mount"
    printf "\n"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        step_status info "No config file found yet at $CONFIG_FILE — one will be created or copied."
    fi

    local import_ans
    read -r -p "Copy an existing config file into $CONFIG_DIR now? [y/N]: " import_ans
    if [[ "${import_ans,,}" == "y" || "${import_ans,,}" == "yes" ]]; then
        prompt_import_existing_config || true
        load_config
    fi

    local input
    read -r -p "SMB server hostname or IP [$HOST]: " input
    [[ -n "$input" ]] && HOST="$input"

    read -r -p "Share path on host [$SHARE_PATH]: " input
    [[ -n "$input" ]] && SHARE_PATH="${input#/}"

    read -r -p "System mount point [$MOUNT_POINT]: " input
    [[ -n "$input" ]] && MOUNT_POINT="$input"

    read -r -p "Home folder symlink path [$HOME_LINK]: " input
    [[ -n "$input" ]] && HOME_LINK="$input"

    read -r -p "SMB username [$SMB_USER]: " input
    [[ -n "$input" ]] && SMB_USER="$input"

    read -r -p "SMB workgroup/domain [$SMB_DOMAIN]: " input
    [[ -n "$input" ]] && SMB_DOMAIN="$input"

    read -r -p "Retry attempts per target [$MAX_RETRIES]: " input
    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 )); then
        MAX_RETRIES="$input"
    fi

    read -r -p "Ledger file path [$LEDGER_FILE]: " input
    [[ -n "$input" ]] && LEDGER_FILE="${input/#\~/$HOME}"

    save_config
    step_status ok "Saved configuration to $CONFIG_FILE"

    if [[ ! -f "$LEDGER_FILE" ]]; then
        ensure_ledger "yes" || true
    fi

    printf "\n"
    read -r -p "Save SMB password for unattended mounts? [y/N]: " save_pw
    if [[ "${save_pw,,}" == "y" || "${save_pw,,}" == "yes" ]]; then
        local pw1 pw2
        read -r -s -p "Enter SMB password for $SMB_USER: " pw1
        printf "\n"
        read -r -s -p "Confirm SMB password: " pw2
        printf "\n"
        if [[ "$pw1" == "$pw2" ]] && [[ -n "$pw1" ]]; then
            mkdir -p "$(dirname "$CREDS_FILE")"
            cat << EOF > "$CREDS_FILE"
username=$SMB_USER
password=$pw1
domain=$SMB_DOMAIN
EOF
            chmod 600 "$CREDS_FILE"
            step_status ok "Saved credentials (chmod 600) at $CREDS_FILE"
        else
            step_status warn "Passwords did not match or were empty; will prompt interactively."
        fi
    fi

    printf "\n"
    read -r -p "Add mount to /etc/fstab for boot? (SteamOS updates may reset it) [y/N]: " add_fstab
    if [[ "${add_fstab,,}" == "y" || "${add_fstab,,}" == "yes" ]]; then
        configure_fstab || true
    fi

    if [[ "$mode" != "skip_mount" ]]; then
        printf "\n"
        read -r -p "Mount share and link home folder now? [Y/n]: " run_now
        if [[ "${run_now,,}" != "n" && "${run_now,,}" != "no" ]]; then
            mount_workflow
        fi
    fi
}

link_home_folder() {
    if [[ -z "$HOME_LINK" ]]; then
        return 0
    fi

    local parent_dir
    parent_dir="$(dirname "$HOME_LINK")"
    mkdir -p "$parent_dir"

    if [[ -L "$HOME_LINK" ]]; then
        local current_target
        current_target="$(readlink "$HOME_LINK")"
        if [[ "$current_target" == "$MOUNT_POINT" ]]; then
            step_status ok "Home link already points to $MOUNT_POINT ($HOME_LINK)"
            return 0
        fi
        rm -f "$HOME_LINK"
    elif [[ -e "$HOME_LINK" ]]; then
        step_status warn "$HOME_LINK exists and is not a symlink; skipping link creation"
        return 1
    fi

    if ln -s "$MOUNT_POINT" "$HOME_LINK"; then
        step_status ok "Linked native path: $HOME_LINK -> $MOUNT_POINT"
        record_ledger "symlink" "$HOME_LINK" "-> $MOUNT_POINT"
        return 0
    fi

    step_status fail "Failed to create symlink $HOME_LINK"
    return 1
}

unlink_home_folder() {
    if [[ -L "$HOME_LINK" ]]; then
        rm -f "$HOME_LINK"
        step_status ok "Removed symlink $HOME_LINK"
        record_ledger "unlink" "$HOME_LINK" "removed symlink"
    elif [[ -e "$HOME_LINK" ]]; then
        step_status warn "$HOME_LINK is not a symlink; left untouched"
    fi
}

verify_native_access() {
    if [[ -d "$MOUNT_POINT" ]] && ls -A "$MOUNT_POINT" >/dev/null 2>&1; then
        step_status ok "Native read access verified on $MOUNT_POINT"
    elif [[ -d "$MOUNT_POINT" ]]; then
        step_status ok "Mount directory accessible (empty or restricted listing)"
    fi

    if [[ -L "$HOME_LINK" ]] && [[ -d "$HOME_LINK" ]]; then
        step_status ok "Home folder access verified at $HOME_LINK"
    fi
}

resolve_host() {
    local target="$1"
    if [[ "$target" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        RESOLVED_IP="$target"
        step_status ok "Target is IPv4 ($RESOLVED_IP)"
        return 0
    fi

    local ip=""
    if command -v getent >/dev/null 2>&1; then
        ip=$(getent ahostsv4 "$target" 2>/dev/null | awk 'NR==1 {print $1}')
    fi
    if [[ -z "$ip" ]] && command -v avahi-resolve >/dev/null 2>&1; then
        ip=$(avahi-resolve -4 -n "${target%.local}.local" 2>/dev/null | awk 'NR==1 {print $2}')
    fi
    if [[ -z "$ip" ]] && command -v ping >/dev/null 2>&1; then
        ip=$(ping -4 -c 1 -W 2 "$target" 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -n1)
    fi

    if [[ -n "$ip" ]]; then
        RESOLVED_IP="$ip"
        step_status ok "Resolved $target -> $RESOLVED_IP"
        return 0
    fi

    RESOLVED_IP=""
    step_status warn "Could not resolve $target via DNS/mDNS"
    return 1
}

check_smb_port() {
    local ip="$1"
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 2 "$ip" 445 >/dev/null 2>&1; then
            step_status ok "TCP port 445 (SMB) reachable on $ip"
            return 0
        fi
    elif timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/445" 2>/dev/null; then
        step_status ok "TCP port 445 (SMB) reachable on $ip"
        return 0
    fi
    step_status warn "TCP port 445 not responding on $ip"
    return 1
}

attempt_mount_once() {
    local target_host="$1"
    local use_creds_file="$2"
    local share_unc="//${target_host}/${SHARE_PATH}"
    local base_opts="uid=${MOUNT_UID},gid=${MOUNT_GID},iocharset=utf8,vers=3.0"
    local opts=""

    if [[ "$use_creds_file" == "yes" ]] && [[ -f "$CREDS_FILE" ]]; then
        opts="credentials=${CREDS_FILE},${base_opts}"
    else
        opts="username=${SMB_USER},domain=${SMB_DOMAIN},${base_opts}"
    fi

    if sudo mount -t cifs "$share_unc" "$MOUNT_POINT" -o "$opts"; then
        record_ledger "mount" "$MOUNT_POINT" "$share_unc"
        return 0
    fi
    return 1
}

try_mount_target() {
    local target_host="$1"
    local attempt=1
    local use_creds="yes"
    [[ ! -f "$CREDS_FILE" ]] && use_creds="no"

    while (( attempt <= MAX_RETRIES )); do
        step_status info "Mount attempt $attempt/$MAX_RETRIES against //${target_host}/${SHARE_PATH} (creds=${use_creds})"
        if attempt_mount_once "$target_host" "$use_creds"; then
            step_status ok "Mounted //${target_host}/${SHARE_PATH} at $MOUNT_POINT"
            return 0
        fi

        if [[ "$use_creds" == "yes" ]] && (( attempt == 1 )); then
            step_status warn "Saved credentials rejected or failed; retrying with interactive login..."
            use_creds="no"
            ((attempt++))
            continue
        fi

        if (( attempt < MAX_RETRIES )); then
            step_status warn "Attempt $attempt failed; retrying in 2s..."
            sleep 2
        fi
        ((attempt++))
    done

    step_status fail "All $MAX_RETRIES attempts failed for //${target_host}/${SHARE_PATH}"
    return 1
}

mount_workflow() {
    ensure_config_optional || true
    load_config
    ensure_ledger "no" || true

    printf "\n"
    draw_box "SMB SHARE MOUNTER" "//${HOST}/${SHARE_PATH} -> ${MOUNT_POINT}"
    printf "\n"

    if mountpoint -q "$MOUNT_POINT"; then
        step_status ok "$MOUNT_POINT is already mounted"
        link_home_folder || true
        verify_native_access
        return 0
    fi

    if [[ ! -d "$MOUNT_POINT" ]]; then
        sudo mkdir -p "$MOUNT_POINT"
        record_ledger "mkdir" "$MOUNT_POINT" "created mount directory"
    fi

    local targets=("$HOST")
    if resolve_host "$HOST"; then
        if [[ -n "$RESOLVED_IP" ]] && [[ "$RESOLVED_IP" != "$HOST" ]]; then
            check_smb_port "$RESOLVED_IP" || true
            targets+=("$RESOLVED_IP")
        else
            check_smb_port "$HOST" || true
        fi
    fi

    local idx=0
    for t in "${targets[@]}"; do
        if try_mount_target "$t"; then
            link_home_folder || true
            verify_native_access
            printf "\n"
            df -h "$MOUNT_POINT" | tail -n 2
            return 0
        fi
        ((idx++))
        if (( idx < ${#targets[@]} )); then
            printf "\n"
            step_status info "Falling back to next target: ${targets[$idx]}..."
            printf "\n"
        fi
    done

    printf "\n"
    draw_box "RECOVERY OPTIONS" "All automated mount attempts failed"
    printf "  1) Re-run setup wizard\n"
    printf "  2) Enter a fallback IP address for one-time mount\n"
    printf "  3) Exit\n\n"
    read -r -p "Choose an option [1-3]: " choice

    case "$choice" in
        1)
            run_wizard
            ;;
        2)
            read -r -p "Enter SMB server IP address: " fallback_ip
            if [[ -n "$fallback_ip" ]]; then
                if try_mount_target "$fallback_ip"; then
                    link_home_folder || true
                    verify_native_access
                    read -r -p "Save $fallback_ip as new default host? [y/N]: " save_ip
                    if [[ "${save_ip,,}" == "y" || "${save_ip,,}" == "yes" ]]; then
                        HOST="$fallback_ip"
                        save_config
                        step_status ok "Updated default host to $HOST"
                    fi
                    return 0
                fi
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

unmount_workflow() {
    load_config
    printf "\n"
    draw_box "SMB SHARE UNMOUNT" "Detaching $MOUNT_POINT"
    printf "\n"

    unlink_home_folder

    if ! mountpoint -q "$MOUNT_POINT"; then
        step_status warn "$MOUNT_POINT is not currently mounted"
        return 0
    fi

    if sudo umount "$MOUNT_POINT"; then
        step_status ok "Unmounted $MOUNT_POINT cleanly"
        record_ledger "umount" "$MOUNT_POINT" "unmounted cleanly"
        return 0
    fi

    step_status warn "Normal unmount busy; attempting lazy unmount (-l)..."
    if sudo umount -l "$MOUNT_POINT"; then
        step_status ok "Lazy unmount completed for $MOUNT_POINT"
        record_ledger "umount_lazy" "$MOUNT_POINT" "lazy unmount"
        return 0
    fi

    step_status fail "Could not unmount $MOUNT_POINT"
    return 1
}

ledger_workflow() {
    ensure_config_optional || true
    load_config
    ensure_ledger "yes" || return 0

    printf "\n"
    draw_box "SCRIPT LEDGER" "$LEDGER_FILE"
    printf "\n"

    local entries
    entries="$(grep -v '^#' "$LEDGER_FILE" || true)"
    if [[ -z "$entries" ]]; then
        step_status info "Ledger is currently empty."
        printf "\n"
        return 0
    fi

    while IFS='|' read -r ts action target detail; do
        printf "  %b[%s]%b %-12s %-28s %s\n" "$C_DIM" "$ts" "$C_RESET" "$action" "$target" "$detail"
    done <<< "$entries"
    printf "\n"
}

cleanup_all_workflow() {
    ensure_config_optional || true
    load_config
    ensure_ledger "no" || true
    show_steamos_notice

    printf "\n"
    draw_box "AUTO CLEAN-UP ALL" "Removing managed mounts, links, fstab entries & dirs"
    printf "\n"

    local confirm
    read -r -p "Clean up all mounts, home links, fstab entries, and mount dirs created by this script? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
        step_status info "Cancelled clean-up."
        return 0
    fi

    local tracked_mounts=("$MOUNT_POINT")
    local tracked_links=("$HOME_LINK")
    local tracked_dirs=("$MOUNT_POINT")

    if [[ -f "$LEDGER_FILE" ]]; then
        while IFS='|' read -r _ action target _; do
            case "$action" in
                mount)
                    [[ -n "$target" ]] && tracked_mounts+=("$target")
                    ;;
                symlink)
                    [[ -n "$target" ]] && tracked_links+=("$target")
                    ;;
                mkdir)
                    [[ -n "$target" ]] && tracked_dirs+=("$target")
                    ;;
            esac
        done < <(grep -v '^#' "$LEDGER_FILE" 2>/dev/null || true)
    fi

    local lnk
    for lnk in "${tracked_links[@]}"; do
        [[ -z "$lnk" ]] && continue
        if [[ -L "$lnk" ]]; then
            rm -f "$lnk"
            step_status ok "Removed symlink: $lnk"
            record_ledger "cleanup_link" "$lnk" "removed symlink"
        fi
    done

    if [[ -f /etc/fstab ]]; then
        if [[ ! -f "$FSTAB_BACKUP" ]]; then
            sudo cp /etc/fstab "$FSTAB_BACKUP" || true
        fi
        local tmp_fstab
        tmp_fstab="$(mktemp)"
        awk -v marker="$FSTAB_MARKER" -v def_mp="$MOUNT_POINT" '
            index($0, marker) > 0 { next }
            $0 !~ /^[[:space:]]*#/ && $2 == def_mp { next }
            { print }
        ' /etc/fstab > "$tmp_fstab"
        if sudo cp "$tmp_fstab" /etc/fstab; then
            step_status ok "Cleaned /etc/fstab automount entries"
            record_ledger "cleanup_fstab" "/etc/fstab" "removed managed fstab entries"
            if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl daemon-reload 2>/dev/null || true
            fi
        else
            step_status warn "Could not update /etc/fstab"
        fi
        rm -f "$tmp_fstab"
    fi

    local mp
    for mp in "${tracked_mounts[@]}"; do
        [[ -z "$mp" ]] && continue
        if mountpoint -q "$mp" 2>/dev/null; then
            if sudo umount "$mp" 2>/dev/null || sudo umount -l "$mp" 2>/dev/null; then
                step_status ok "Unmounted: $mp"
                record_ledger "cleanup_umount" "$mp" "unmounted during cleanup"
            else
                step_status warn "Could not unmount $mp"
            fi
        fi
    done

    local dir
    for dir in "${tracked_dirs[@]}"; do
        [[ -z "$dir" ]] && continue
        if [[ -d "$dir" ]] && ! mountpoint -q "$dir" 2>/dev/null; then
            if sudo rmdir "$dir" 2>/dev/null; then
                step_status ok "Removed empty mount directory: $dir"
                record_ledger "cleanup_rmdir" "$dir" "removed empty dir"
            else
                step_status info "Kept directory (non-empty or in use): $dir"
            fi
        fi
    done

    printf "\n"
    step_status ok "Clean-up pass complete."
    printf "\n"
}

status_workflow() {
    ensure_config_optional || true
    load_config
    printf "\n"
    draw_box "SMB MOUNTER STATUS" "Config: $CONFIG_FILE"
    printf "\n"
    if [[ -f "$CONFIG_FILE" ]]; then
        step_status ok "Config file     : present ($CONFIG_FILE)"
    else
        step_status warn "Config file     : not yet created (using generic defaults)"
    fi
    if [[ -f "$LEDGER_FILE" ]]; then
        step_status ok "Ledger file     : present ($LEDGER_FILE)"
    else
        step_status warn "Ledger file     : not yet created (created on demand)"
    fi
    step_status info "Configured Host : $HOST"
    step_status info "Configured Share: //${HOST}/${SHARE_PATH}"
    step_status info "Mount Point     : $MOUNT_POINT"
    step_status info "Home Link       : $HOME_LINK"
    step_status info "SMB User        : $SMB_USER"

    if awk -v mp="$MOUNT_POINT" '$0 !~ /^[[:space:]]*#/ && $2 == mp {found=1} END {exit !found}' /etc/fstab 2>/dev/null; then
        step_status ok "fstab boot entry: configured in /etc/fstab"
    else
        step_status warn "fstab boot entry: not configured"
    fi

    if mountpoint -q "$MOUNT_POINT"; then
        step_status ok "Mount state     : MOUNTED"
    else
        step_status warn "Mount state     : NOT MOUNTED"
    fi

    if [[ -L "$HOME_LINK" ]]; then
        step_status ok "Symlink state   : -> $(readlink "$HOME_LINK")"
    else
        step_status warn "Symlink state   : not linked"
    fi
    show_steamos_notice
}

main() {
    local cmd="${1:-}"
    case "$cmd" in
        "")
            show_options_hint
            ;;
        up|mount)
            mount_workflow
            ;;
        down|umount)
            unmount_workflow
            ;;
        fstab)
            configure_fstab
            ;;
        check-fstab|automount-check)
            check_fstab_automount
            ;;
        remove-fstab|unfstab|automount-remove)
            remove_fstab_automount
            ;;
        ledger)
            ledger_workflow
            ;;
        cleanup|clean|purge)
            cleanup_all_workflow
            ;;
        status)
            status_workflow
            ;;
        setup|wizard|config)
            run_wizard
            ;;
        features|manual)
            show_feature_detail "${2:-all}"
            ;;
        help|-h|'?'|-\?)
            if [[ "${2:-}" == "--verbose" || "${2:-}" == "-v" || "${2:-}" == "all" ]]; then
                show_feature_detail "all"
            elif [[ -n "${2:-}" ]]; then
                show_feature_detail "$2"
            else
                show_options_hint
            fi
            ;;
        --help)
            show_feature_detail "${2:-all}"
            ;;
        *)
            step_status fail "Unknown command: $cmd"
            show_options_hint
            exit 1
            ;;
    esac
}

main "$@"