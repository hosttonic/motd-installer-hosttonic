#!/usr/bin/env bash
# ==============================================================
#  HostTonic MOTD Installer
#  https://github.com/hosttonic/motd
#
#  One-liner install:
#    bash <(curl -fsSL https://raw.githubusercontent.com/hosttonic/motd/main/setup-motd.sh)
#
#  Supported distributions:
#    Debian 11 / 12 / 13
#    Ubuntu 22.04 / 24.04
#    Rocky Linux 8 / 9 / 10
#    AlmaLinux 8 / 9 / 10
#    CentOS Stream 9 / 10
#    CloudLinux 8
#    openSUSE Leap 15
#    Fedora 41 / 42
#
#  Run as root: bash setup-motd.sh
# ==============================================================

set -euo pipefail

# ── Colours ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}▸ $*${NC}"; }

# ── Root check ──────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Please run as root: sudo bash setup-motd.sh"

# ── Detect OS ───────────────────────────────────────────────
[[ -f /etc/os-release ]] || error "/etc/os-release not found — cannot detect OS."
# shellcheck source=/dev/null
source /etc/os-release
OS_ID="${ID,,}"
OS_NAME="${NAME:-Unknown}"
OS_VERSION="${VERSION_ID:-unknown}"

echo -e "\n${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  HostTonic MOTD Installer${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}\n"
info "OS detected : ${OS_NAME} ${OS_VERSION} (id=${OS_ID})"

# ── Pass 1: match on exact OS ID ────────────────────────────
case "${OS_ID}" in
    debian|ubuntu)                           OS_FAMILY="debian"  ;;
    rocky|almalinux|centos|rhel|cloudlinux)  OS_FAMILY="rhel"    ;;
    fedora)                                  OS_FAMILY="fedora"  ;;
    opensuse*|opensuse-leap|sles)            OS_FAMILY="opensuse";;
    *) OS_FAMILY="" ;;
esac

# ── Pass 2: fall back to ID_LIKE (catches derivatives) ──────
if [[ -z "$OS_FAMILY" ]]; then
    ID_LIKE_LC="${ID_LIKE,,}"   # lower-case the ID_LIKE field
    case "$ID_LIKE_LC" in
        *debian*|*ubuntu*)          OS_FAMILY="debian"  ;;
        *rhel*|*centos*|*fedora*|*cloudlinux*)  OS_FAMILY="rhel" ;;
        *opensuse*|*suse*)          OS_FAMILY="opensuse";;
        *) error "Unsupported OS: ${OS_NAME} (id=${OS_ID}, id_like=${ID_LIKE:-none}). Please open an issue at https://github.com/hosttonic/motd" ;;
    esac
    info "Matched via ID_LIKE=\"${ID_LIKE}\" → family=${OS_FAMILY}"
fi

# ════════════════════════════════════════════════════════════
#  BANNER content (embedded — used by installer functions)
# ════════════════════════════════════════════════════════════
BANNER_CONTENT='\n══════════════════════════════════════════════\n░█░█░█▀█░█▀▀░▀█▀░░░▀█▀░█▀█░█▀█░▀█▀░█▀▀░░\n░█▀█░█░█░▀▀█░░█░░░░░█░░█░█░█░█░░█░░█░░░░\n░▀░▀░▀▀▀░▀▀▀░░▀░░░░░▀░░▀▀▀░▀░▀░▀▀▀░▀▀▀░░\n══════════════════════════════════════════════\nPremium Cloud • VPS • Dedicated Servers\nWebsite : https://hosttonic.com\n══════════════════════════════════════════════\n'

# ════════════════════════════════════════════════════════════
#  DYNAMIC STATS — the combined hosttonic-motd.sh logic
# ════════════════════════════════════════════════════════════
write_stats_script() {
    local TARGET="$1"
    cat > "$TARGET" <<'STATS'
#!/usr/bin/env bash
# HostTonic dynamic MOTD — server stats on login

# ── 60-second output cache (reduces latency on busy servers) ──
CACHE_FILE="/tmp/.hosttonic_motd_cache"
if [[ -f "$CACHE_FILE" ]] && [[ -n "$(find "$CACHE_FILE" -mmin -1 2>/dev/null)" ]]; then
    cat "$CACHE_FILE"
    exit 0
fi

# ── Gather stats ─────────────────────────────────────────────
if command -v journalctl >/dev/null 2>&1; then
    FAILED_ROOT_24H=$(journalctl _COMM=sshd --since "24 hours ago" 2>/dev/null \
        | grep -c "Failed password for root" || true)
elif [[ -f /var/log/auth.log ]]; then
    FAILED_ROOT_24H=$(grep -c "Failed password for root" /var/log/auth.log 2>/dev/null || true)
elif [[ -f /var/log/secure ]]; then
    FAILED_ROOT_24H=$(grep -c "Failed password for root" /var/log/secure 2>/dev/null || true)
else
    FAILED_ROOT_24H="N/A"
fi

UPTIME=$(uptime -p 2>/dev/null || uptime)
LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg)
MEM_USED=$(free -m | awk '/Mem:/ {printf "%dMi/%dMi", $3, $2}')
DISK=$(df -h / | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
LOGIN_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

# ── Render and cache ─────────────────────────────────────────
{
    echo "══════════════════════════════════════════════"
    printf "Server      : %s\n" "$(hostname -f 2>/dev/null || hostname)"
    printf "Uptime      : %s\n" "$UPTIME"
    printf "Load Avg    : %s\n" "$LOAD"
    printf "Memory      : %s\n" "$MEM_USED"
    printf "Disk (/)    : %s\n" "$DISK"
    printf "Failed root SSH (24h): %s\n" "$FAILED_ROOT_24H"
    printf "Login time  : %s\n" "$LOGIN_TIME"
    echo "══════════════════════════════════════════════"
} | tee "$CACHE_FILE"
STATS
    chmod +x "$TARGET"
}

# ── Debian / Ubuntu: update-motd.d ──────────────────────────
install_debian() {
    mkdir -p /etc/update-motd.d

    # Nuke ALL default scripts first — only ours will run
    step "Disabling ALL default update-motd.d scripts"
    chmod -x /etc/update-motd.d/* 2>/dev/null || true
    info "All existing scripts in /etc/update-motd.d/ disabled."

    # Clear /etc/motd — Ubuntu's /run/motd.dynamic can conflict with it.
    # Our banner lives in 00-hosttonic-banner instead, so motd.dynamic
    # becomes the single authoritative source and duplication is impossible.
    step "Clearing /etc/motd (banner will be served via update-motd.d)"
    > /etc/motd
    success "/etc/motd cleared."

    # 00 — static banner (prints first)
    step "Installing banner → /etc/update-motd.d/00-hosttonic-banner"
    cat > /etc/update-motd.d/00-hosttonic-banner <<'BANNER'
#!/usr/bin/env bash
printf '\n══════════════════════════════════════════════\n'
printf '░█░█░█▀█░█▀▀░▀█▀░░░▀█▀░█▀█░█▀█░▀█▀░█▀▀░░\n'
printf '░█▀█░█░█░▀▀█░░█░░░░░█░░█░█░█░█░░█░░█░░░░\n'
printf '░▀░▀░▀▀▀░▀▀▀░░▀░░░░░▀░░▀▀▀░▀░▀░▀▀▀░▀▀▀░░\n'
printf '══════════════════════════════════════════════\n'
printf 'Premium Cloud • VPS • Dedicated Servers\n'
printf 'Website : https://hosttonic.com\n'
printf '══════════════════════════════════════════════\n\n'
BANNER
    chmod +x /etc/update-motd.d/00-hosttonic-banner
    success "Installed /etc/update-motd.d/00-hosttonic-banner"

    # 99 — dynamic stats (prints after banner)
    step "Installing dynamic stats → /etc/update-motd.d/99-hosttonic-stats"
    write_stats_script /etc/update-motd.d/99-hosttonic-stats
    success "Installed /etc/update-motd.d/99-hosttonic-stats"
}

# ── RHEL / Fedora / openSUSE: profile.d ─────────────────────
install_profiled() {
    # Write banner to /etc/motd (shown by sshd PrintMotd)
    step "Writing static banner → /etc/motd"
    printf '\n══════════════════════════════════════════════\n' > /etc/motd
    printf '░█░█░█▀█░█▀▀░▀█▀░░░▀█▀░█▀█░█▀█░▀█▀░█▀▀░░\n' >> /etc/motd
    printf '░█▀█░█░█░▀▀█░░█░░░░░█░░█░█░█░█░░█░░█░░░░\n' >> /etc/motd
    printf '░▀░▀░▀▀▀░▀▀▀░░▀░░░░░▀░░▀▀▀░▀░▀░▀▀▀░▀▀▀░░\n' >> /etc/motd
    printf '══════════════════════════════════════════════\n' >> /etc/motd
    printf 'Premium Cloud • VPS • Dedicated Servers\n' >> /etc/motd
    printf 'Website : https://hosttonic.com\n' >> /etc/motd
    printf '══════════════════════════════════════════════\n\n' >> /etc/motd
    success "Banner written to /etc/motd"

    # Dynamic stats via profile.d (runs on every interactive login shell)
    step "Installing dynamic stats → /etc/profile.d/hosttonic-motd.sh"
    write_stats_script /etc/profile.d/hosttonic-motd.sh
    success "Installed /etc/profile.d/hosttonic-motd.sh"

    # Clear /etc/motd.d/ if it exists (RHEL 8+ splits motd here)
    if [[ -d /etc/motd.d ]]; then
        rm -f /etc/motd.d/*
        info "Cleared /etc/motd.d/ (prevents duplicate banner)"
    fi
}

case "${OS_FAMILY}" in
    debian)               install_debian   ;;
    rhel|fedora|opensuse) install_profiled ;;
esac

# ════════════════════════════════════════════════════════════
#  SSH — ensure MOTD is displayed on login
# ════════════════════════════════════════════════════════════
step "Verifying SSH configuration"

SSHD_CFG="/etc/ssh/sshd_config"
if [[ -f "$SSHD_CFG" ]]; then
    CHANGED=0

    # PrintMotd must be yes
    if grep -qiE "^PrintMotd\s+no" "$SSHD_CFG"; then
        sed -i 's/^PrintMotd.*/PrintMotd yes/' "$SSHD_CFG"
        info "sshd_config: PrintMotd set to yes"
        CHANGED=1
    fi

    # On Debian/Ubuntu, PAM handles MOTD; PrintMotd no is actually correct
    # and update-motd.d is invoked by pam_motd. So only force PrintMotd yes
    # on non-Debian families.
    if [[ "$OS_FAMILY" == "debian" ]]; then
        # Restore PrintMotd no if we changed it — PAM handles display
        if [[ $CHANGED -eq 1 ]]; then
            sed -i 's/^PrintMotd.*/PrintMotd no/' "$SSHD_CFG"
            info "sshd_config: Reverted PrintMotd to no (PAM handles MOTD on Debian/Ubuntu)"
            CHANGED=0
        fi
        # Ensure pam_motd is active in /etc/pam.d/sshd
        if [[ -f /etc/pam.d/sshd ]]; then
            if ! grep -q "pam_motd" /etc/pam.d/sshd; then
                echo "session optional pam_motd.so motd=/run/motd.dynamic" >> /etc/pam.d/sshd
                info "Added pam_motd to /etc/pam.d/sshd"
                CHANGED=1
            fi
        fi
    fi

    if [[ $CHANGED -eq 1 ]]; then
        # Reload preferred (keeps live sessions); restart as last resort
        if   systemctl reload  sshd 2>/dev/null; then info "SSH reloaded (sshd)"
        elif systemctl reload  ssh  2>/dev/null; then info "SSH reloaded (ssh)"
        elif systemctl restart sshd 2>/dev/null; then warn "SSH restarted (sshd) — existing sessions may drop"
        elif systemctl restart ssh  2>/dev/null; then warn "SSH restarted (ssh) — existing sessions may drop"
        else warn "Could not reload/restart SSH — changes take effect at next manual restart"
        fi
    else
        info "SSH configuration looks good — no changes needed"
    fi
else
    warn "sshd_config not found at ${SSHD_CFG} — skipping"
fi

# ════════════════════════════════════════════════════════════
#  PREVIEW — show what users will see on login
# ════════════════════════════════════════════════════════════
step "Preview"
echo ""
if [[ "${OS_FAMILY}" == "debian" ]]; then
    bash /etc/update-motd.d/00-hosttonic-banner
    bash /etc/update-motd.d/99-hosttonic-stats
else
    cat /etc/motd
    bash /etc/profile.d/hosttonic-motd.sh
fi

# ════════════════════════════════════════════════════════════
echo ""
success "HostTonic MOTD installed successfully on ${OS_NAME} ${OS_VERSION}!"
echo ""
if [[ "${OS_FAMILY}" == "debian" ]]; then
    info "Test : run-parts /etc/update-motd.d/"
else
    info "Test : bash /etc/profile.d/hosttonic-motd.sh"
fi
info "Cache: rm /tmp/.hosttonic_motd_cache  (forces fresh stats next login)"
echo ""
