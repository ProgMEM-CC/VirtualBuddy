#!/bin/bash
#
# VirtualBuddy - Build patched spice-vdagent with KDE Wayland support
#
# This script builds spice-vdagent from the VirtualBuddy fork which includes
# native KDE Plasma Wayland support via kde-output-management-v2 protocol.
#
# Prerequisites (Fedora/RHEL):
#   sudo dnf install git gcc automake autoconf libtool pkgconfig \
#     glib2-devel libdrm-devel libX11-devel libXfixes-devel libXrandr-devel \
#     libXinerama-devel alsa-lib-devel dbus-devel systemd-devel \
#     spice-protocol wayland-devel wayland-protocols-devel pciaccess-devel \
#     gtk3-devel
#
# Prerequisites (Debian/Ubuntu):
#   sudo apt install git build-essential automake autoconf libtool pkg-config \
#     libglib2.0-dev libdrm-dev libx11-dev libxfixes-dev libxrandr-dev \
#     libxinerama-dev libasound2-dev libdbus-1-dev libsystemd-dev \
#     libspice-protocol-dev libwayland-dev wayland-protocols \
#     libpciaccess-dev libgtk-3-dev
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/vdagent-build}"
VDAGENT_REPO="${VDAGENT_REPO:-https://github.com/user/spice-vdagent.git}"
VDAGENT_BRANCH="${VDAGENT_BRANCH:-feat/kwin-wayland-support}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[build-vdagent]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_dependencies() {
    log "Checking build dependencies..."

    local missing=()

    # Check for required tools
    for cmd in git gcc make autoreconf pkg-config; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for required pkg-config modules
    for pkg in glib-2.0 libdrm x11 xfixes xrandr xinerama alsa dbus-1 spice-protocol wayland-client; do
        if ! pkg-config --exists "$pkg" 2>/dev/null; then
            missing+=("$pkg (dev package)")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install them with:"
        if command -v dnf &>/dev/null; then
            echo "  sudo dnf install git gcc automake autoconf libtool pkgconfig \\"
            echo "    glib2-devel libdrm-devel libX11-devel libXfixes-devel libXrandr-devel \\"
            echo "    libXinerama-devel alsa-lib-devel dbus-devel systemd-devel \\"
            echo "    spice-protocol wayland-devel wayland-protocols-devel pciaccess-devel gtk3-devel"
        elif command -v apt &>/dev/null; then
            echo "  sudo apt install git build-essential automake autoconf libtool pkg-config \\"
            echo "    libglib2.0-dev libdrm-dev libx11-dev libxfixes-dev libxrandr-dev \\"
            echo "    libxinerama-dev libasound2-dev libdbus-1-dev libsystemd-dev \\"
            echo "    libspice-protocol-dev libwayland-dev wayland-protocols libpciaccess-dev libgtk-3-dev"
        fi
        return 1
    fi

    log_success "All dependencies found"
}

clone_source() {
    log "Cloning spice-vdagent source..."

    if [[ -d "$BUILD_DIR/spice-vdagent" ]]; then
        log "Removing existing source directory..."
        rm -rf "$BUILD_DIR/spice-vdagent"
    fi

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    git clone --depth 1 -b "$VDAGENT_BRANCH" "$VDAGENT_REPO" spice-vdagent

    log_success "Source cloned to $BUILD_DIR/spice-vdagent"
}

build_vdagent() {
    log "Building spice-vdagent..."

    cd "$BUILD_DIR/spice-vdagent"

    # Run autogen/autoreconf
    if [[ -f autogen.sh ]]; then
        ./autogen.sh
    else
        autoreconf -fi
    fi

    # Configure with KWin support
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --with-init-script=systemd \
        --enable-kwin \
        --with-gtk=yes

    # Build
    make -j"$(nproc)"

    log_success "Build completed"
}

install_vdagent() {
    log "Installing spice-vdagent..."

    cd "$BUILD_DIR/spice-vdagent"

    # Stop existing services
    systemctl --user stop spice-vdagent 2>/dev/null || true
    sudo systemctl stop spice-vdagentd.socket spice-vdagentd 2>/dev/null || true

    # Install
    sudo make install

    # Reload systemd
    sudo systemctl daemon-reload
    systemctl --user daemon-reload 2>/dev/null || true

    # Start services
    sudo systemctl start spice-vdagentd.socket
    sudo systemctl start spice-vdagentd
    systemctl --user start spice-vdagent 2>/dev/null || true

    log_success "Installation completed"

    # Show status
    echo ""
    log "Checking service status..."
    sudo systemctl status spice-vdagentd --no-pager || true
    systemctl --user status spice-vdagent --no-pager 2>/dev/null || true
}

show_help() {
    echo "VirtualBuddy - Build patched spice-vdagent with KDE Wayland support"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --check        Check dependencies only"
    echo "  --clone        Clone source only"
    echo "  --build        Build only (assumes source exists)"
    echo "  --install      Install only (assumes build exists)"
    echo "  --all          Full build and install (default)"
    echo "  --help         Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  BUILD_DIR      Build directory (default: /tmp/vdagent-build)"
    echo "  VDAGENT_REPO   Git repository URL"
    echo "  VDAGENT_BRANCH Branch to build (default: feat/kwin-wayland-support)"
    echo "  INSTALL_PREFIX Installation prefix (default: /usr)"
}

main() {
    case "${1:-all}" in
        --check)
            check_dependencies
            ;;
        --clone)
            clone_source
            ;;
        --build)
            build_vdagent
            ;;
        --install)
            install_vdagent
            ;;
        --all|all)
            check_dependencies
            clone_source
            build_vdagent
            install_vdagent
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
