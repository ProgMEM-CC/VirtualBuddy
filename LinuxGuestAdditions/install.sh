#!/bin/bash
#
# VirtualBuddy Linux Guest Additions Installer
#
# This script installs the VirtualBuddy guest additions for Linux,
# which provides automatic filesystem resize after disk expansion.
#
# Supports: Fedora, Ubuntu, Debian, Arch, and other systemd-based distros
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.3.0"

# Colors for terminal output (disabled if not a TTY)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Check if we're in a desktop environment
HAS_DESKTOP=false
if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    HAS_DESKTOP=true
fi

log() {
    echo -e "${CYAN}[virtualbuddy]${NC} $*"
}

log_step() {
    echo -e "${BLUE}${BOLD}==>${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

die() {
    echo -e "${RED}${BOLD}ERROR:${NC} $*" >&2
    exit 1
}

# Send desktop notification if available
# Note: When running as root (sudo), D-Bus session may not be accessible,
# so we use timeout to prevent hanging
notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"  # low, normal, critical

    if $HAS_DESKTOP && command -v notify-send &>/dev/null; then
        # Use timeout to prevent hanging if D-Bus session is inaccessible (common with sudo)
        timeout 2s notify-send -u "$urgency" -i "drive-harddisk" "VirtualBuddy: $title" "$message" 2>/dev/null || true
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (try: sudo $0)"
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null; then
        die "systemd not found. This installer requires a systemd-based distribution."
    fi
}

# Detect package manager
detect_package_manager() {
    if command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# Install a package using the detected package manager
install_package() {
    local pkg_dnf="$1"
    local pkg_apt="$2"
    local pkg_pacman="$3"
    local pkg_zypper="$4"
    local pkg_manager
    pkg_manager=$(detect_package_manager)

    case "$pkg_manager" in
        dnf)
            dnf install -y "$pkg_dnf" 2>/dev/null || return 1
            ;;
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg_apt" 2>/dev/null || return 1
            ;;
        pacman)
            pacman -S --noconfirm "$pkg_pacman" 2>/dev/null || return 1
            ;;
        zypper)
            zypper install -y "$pkg_zypper" 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# Detect if running KDE Plasma Wayland
is_kde_wayland() {
    local de="${XDG_CURRENT_DESKTOP:-}"
    local session="${XDG_SESSION_TYPE:-}"

    if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ "$de" == *"KDE"* || "$de" == *"plasma"* ]]; then
        return 0
    fi
    return 1
}

# Check if vdagent has KWin support
vdagent_has_kwin_support() {
    # Check if our patched version is installed by looking for the KWin protocol files
    if [[ -f /usr/share/spice-vdagent/kde-output-management-v2.xml ]] || \
       strings /usr/bin/spice-vdagent 2>/dev/null | grep -q "kde_output_management_v2"; then
        return 0
    fi
    return 1
}

# Install spice-vdagent for dynamic resolution support
install_spice_vdagent() {
    log_step "Setting up dynamic resolution support..."

    local need_kde_patch=false

    # Check if on KDE Plasma Wayland
    if is_kde_wayland; then
        log "Detected KDE Plasma Wayland session"
        need_kde_patch=true
    fi

    if command -v spice-vdagent &>/dev/null; then
        log_success "spice-vdagent already installed"

        # Check if it has KWin support
        if $need_kde_patch && ! vdagent_has_kwin_support; then
            log_warning "Installed spice-vdagent lacks native KDE Wayland support"
            echo ""
            echo -e "${YELLOW}The stock spice-vdagent does not support KDE Plasma Wayland natively.${NC}"
            echo "VirtualBuddy provides a patched version with native KDE support."
            echo ""
            echo "Options:"
            echo "  1. Build patched spice-vdagent (recommended for KDE)"
            echo "  2. Use stock version with virtualbuddy-resolution fallback"
            echo ""
            read -p "Build patched version? [y/N] " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                build_patched_vdagent
            else
                log "Using stock spice-vdagent with fallback support"
            fi
        fi
    else
        log "Installing spice-vdagent..."
        if install_package "spice-vdagent" "spice-vdagent" "spice-vdagent" "spice-vdagent"; then
            log_success "Installed spice-vdagent"

            # Offer patched version for KDE
            if $need_kde_patch; then
                echo ""
                echo -e "${YELLOW}For native KDE Wayland resolution support, you can build the patched version.${NC}"
                read -p "Build patched spice-vdagent with KDE support? [y/N] " -n 1 -r
                echo

                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    build_patched_vdagent
                fi
            fi
        else
            log_warning "Could not install spice-vdagent automatically"
            log_warning "For dynamic resolution, install it manually:"
            local pkg_manager
            pkg_manager=$(detect_package_manager)
            case "$pkg_manager" in
                dnf)    echo -e "  ${BOLD}sudo dnf install spice-vdagent${NC}" ;;
                apt)    echo -e "  ${BOLD}sudo apt install spice-vdagent${NC}" ;;
                pacman) echo -e "  ${BOLD}sudo pacman -S spice-vdagent${NC}" ;;
                zypper) echo -e "  ${BOLD}sudo zypper install spice-vdagent${NC}" ;;
            esac
        fi
    fi

    # Enable spice-vdagentd service
    if systemctl list-unit-files | grep -q spice-vdagentd; then
        log "Enabling spice-vdagentd service..."
        systemctl enable spice-vdagentd 2>/dev/null || true
        systemctl start spice-vdagentd 2>/dev/null || true
        log_success "Enabled spice-vdagentd"
    fi

    echo ""
}

# Build and install patched spice-vdagent with KDE support
build_patched_vdagent() {
    log_step "Building patched spice-vdagent with KDE Wayland support..."

    # Check for build script
    if [[ -f "$SCRIPT_DIR/build-vdagent.sh" ]]; then
        # Install build dependencies first
        log "Installing build dependencies..."
        local pkg_manager
        pkg_manager=$(detect_package_manager)

        case "$pkg_manager" in
            dnf)
                dnf install -y git gcc automake autoconf libtool pkgconfig \
                    glib2-devel libdrm-devel libX11-devel libXfixes-devel libXrandr-devel \
                    libXinerama-devel alsa-lib-devel dbus-devel systemd-devel \
                    spice-protocol wayland-devel wayland-protocols-devel pciaccess-devel \
                    gtk3-devel 2>/dev/null || log_warning "Some build deps may be missing"
                ;;
            apt)
                apt-get install -y git build-essential automake autoconf libtool pkg-config \
                    libglib2.0-dev libdrm-dev libx11-dev libxfixes-dev libxrandr-dev \
                    libxinerama-dev libasound2-dev libdbus-1-dev libsystemd-dev \
                    libspice-protocol-dev libwayland-dev wayland-protocols \
                    libpciaccess-dev libgtk-3-dev 2>/dev/null || log_warning "Some build deps may be missing"
                ;;
            *)
                log_warning "Please install build dependencies manually"
                ;;
        esac

        # Run the build script
        if bash "$SCRIPT_DIR/build-vdagent.sh" --all; then
            log_success "Patched spice-vdagent installed successfully"
        else
            log_warning "Build failed, falling back to stock version"
        fi
    else
        log_warning "build-vdagent.sh not found in $SCRIPT_DIR"
        log "You can build manually from: https://github.com/user/spice-vdagent"
    fi
}

check_dependencies() {
    log_step "Checking dependencies..."
    local missing=()

    # Check for required tools
    if ! command -v growpart &>/dev/null; then
        missing+=("growpart (cloud-guest-utils)")
    else
        log_success "growpart found"
    fi

    if command -v resize2fs &>/dev/null; then
        log_success "resize2fs found"
    elif command -v xfs_growfs &>/dev/null; then
        log_success "xfs_growfs found"
    else
        missing+=("resize2fs or xfs_growfs (e2fsprogs or xfsprogs)")
    fi

    if ! command -v cryptsetup &>/dev/null; then
        log_warning "cryptsetup not found - LUKS support will be disabled"
    else
        log_success "cryptsetup found"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Missing dependencies:${NC}"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Install them with:"

        if command -v dnf &>/dev/null; then
            echo -e "  ${BOLD}sudo dnf install cloud-utils-growpart${NC}"
        elif command -v apt-get &>/dev/null; then
            echo -e "  ${BOLD}sudo apt-get install cloud-guest-utils${NC}"
        elif command -v pacman &>/dev/null; then
            echo -e "  ${BOLD}sudo pacman -S cloud-guest-utils${NC}"
        elif command -v zypper &>/dev/null; then
            echo -e "  ${BOLD}sudo zypper install growpart${NC}"
        fi

        die "Please install missing dependencies and try again."
    fi
    echo ""
}

install_files() {
    log_step "Installing VirtualBuddy Guest Additions v$VERSION..."

    # Install the growfs script
    log "Installing virtualbuddy-growfs to /usr/local/bin/"
    install -m 755 "$SCRIPT_DIR/virtualbuddy-growfs" /usr/local/bin/virtualbuddy-growfs
    log_success "Installed virtualbuddy-growfs"

    # Install the notification script
    log "Installing notification script..."
    install -m 755 "$SCRIPT_DIR/virtualbuddy-notify" /usr/local/bin/virtualbuddy-notify
    log_success "Installed virtualbuddy-notify"

    # Install the resolution fallback script (if present)
    if [[ -f "$SCRIPT_DIR/virtualbuddy-resolution" ]]; then
        log "Installing resolution fallback script..."
        install -m 755 "$SCRIPT_DIR/virtualbuddy-resolution" /usr/local/bin/virtualbuddy-resolution
        log_success "Installed virtualbuddy-resolution"
    fi

    # Install the systemd system service
    log "Installing systemd system service..."
    install -m 644 "$SCRIPT_DIR/virtualbuddy-growfs.service" /etc/systemd/system/virtualbuddy-growfs.service
    log_success "Installed growfs service"

    # Install the systemd user service for notifications
    log "Installing systemd user service for notifications..."
    mkdir -p /etc/systemd/user
    install -m 644 "$SCRIPT_DIR/virtualbuddy-notify.service" /etc/systemd/user/virtualbuddy-notify.service
    log_success "Installed notification service"

    # Install the resolution fallback user service (if present)
    if [[ -f "$SCRIPT_DIR/virtualbuddy-resolution.service" ]]; then
        log "Installing resolution fallback service..."
        install -m 644 "$SCRIPT_DIR/virtualbuddy-resolution.service" /etc/systemd/user/virtualbuddy-resolution.service
        log_success "Installed resolution service"
    fi

    # Reload systemd
    log "Reloading systemd daemon..."
    systemctl daemon-reload
    log_success "Reloaded systemd"

    # Enable the system service
    log "Enabling virtualbuddy-growfs service..."
    systemctl enable virtualbuddy-growfs.service
    log_success "Enabled growfs service for automatic startup"

    # Enable the user service globally (for all users)
    log "Enabling notification service for desktop users..."
    systemctl --global enable virtualbuddy-notify.service 2>/dev/null || true
    log_success "Enabled notification service"

    # Enable the resolution fallback service globally (if present)
    if [[ -f /etc/systemd/user/virtualbuddy-resolution.service ]]; then
        log "Enabling resolution fallback service..."
        systemctl --global enable virtualbuddy-resolution.service 2>/dev/null || true
        log_success "Enabled resolution service"
    fi

    # Write version file for update detection
    mkdir -p /etc/virtualbuddy
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp "$SCRIPT_DIR/VERSION" /etc/virtualbuddy/version
    else
        echo "$VERSION" > /etc/virtualbuddy/version
    fi
    log_success "Saved version info"
    echo ""
}

run_now() {
    echo ""
    echo -e "${BOLD}Would you like to resize the filesystem now?${NC}"
    echo "This will expand the root partition if the disk has been enlarged."
    echo ""
    read -p "Resize now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        log_step "Running filesystem resize..."
        /usr/local/bin/virtualbuddy-growfs --verbose
    else
        echo ""
        log "Skipped. The filesystem will be automatically resized on next boot."
    fi
}

show_status() {
    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         VirtualBuddy Guest Additions Installed!              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "The virtualbuddy-growfs service will automatically run on each boot"
    echo "to expand the filesystem if the disk has been resized in VirtualBuddy."
    echo ""
    echo -e "${BOLD}Manual commands:${NC}"
    echo -e "  ${CYAN}Check status:${NC}     systemctl status virtualbuddy-growfs"
    echo -e "  ${CYAN}Run manually:${NC}     sudo virtualbuddy-growfs --verbose"
    echo -e "  ${CYAN}View logs:${NC}        journalctl -u virtualbuddy-growfs"
    echo -e "  ${CYAN}Uninstall:${NC}        sudo $SCRIPT_DIR/uninstall.sh"

    # Send desktop notification
    notify "Installation Complete" "VirtualBuddy Guest Additions have been installed successfully."
}

show_banner() {
    echo ""
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║          VirtualBuddy Linux Guest Additions v$VERSION          ║${NC}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This will install:"
    echo "  • Automatic disk resize support"
    echo "  • Dynamic display resolution (resize VM window to change resolution)"
    echo "  • Desktop notifications for disk operations"
    echo ""
}

main() {
    show_banner
    check_root
    check_systemd
    check_dependencies
    install_spice_vdagent
    install_files
    show_status
    run_now

    echo ""
    echo -e "${GREEN}${BOLD}All done!${NC} Enjoy using VirtualBuddy."
    echo ""
}

main "$@"
