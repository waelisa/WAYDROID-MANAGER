#!/usr/bin/env bash

#############################################################################################################################
# The MIT License (MIT)
# Wael Isa
# Build Date: 02/18/2026
# Version: 2.1.1
# https://github.com/waelisa/WAYDROID-MANAGER
#############################################################################################################################
# WayDroid Management Script - Complete Android container orchestrator for Linux
# Automatically manages WayDroid Android container on Linux with industrial-grade reliability
# Features:
#   ✓ Multi-distro support (Arch, Debian, Fedora, openSUSE)
#   ✓ Automatic waydroid_script integration with Python venv
#   ✓ ARM translation layers (libndk/libhoudini) for x86 systems
#   ✓ Google Apps/MicroG installation with Play Store certification
#   ✓ Magisk root integration for system-level access
#   ✓ Widevine DRM L3 support for streaming services
#   ✓ Desktop mode launcher (smartdock)
#   ✓ Interactive menu system with color-coded output
#   ✓ Systemd service management with status monitoring
#   ✓ Binder module verification and auto-loading with kernel header detection
#   ✓ Firewall configuration for network bridge
#   ✓ Wayland session detection with fallback options
#   ✓ Multi-window and full UI mode support
#   ✓ MITM certificate installation for development
#   ✓ Android 11 specific hacks (NoDataPerm, hide status bar)
#   ✓ Comprehensive error trapping with cleanup
#   ✓ Root privilege validation with sudo detection
#   ✓ Lock file protection against concurrent runs
#   ✓ Secure logging with rotation capabilities
#############################################################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Icons
CHECK_MARK="\xE2\x9C\x94"
CROSS_MARK="\xE2\x9C\x98"
INFO="\xE2\x84\xB9"
WARNING="\xE2\x9A\xA0"
GEAR="\xE2\x9A\x99"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYDROID_SCRIPT_DIR="${SCRIPT_DIR}/waydroid_script"
PYTHON_SCRIPT="${WAYDROID_SCRIPT_DIR}/venv/bin/python3"
MAIN_PY="${WAYDROID_SCRIPT_DIR}/main.py"
LOG_FILE="/var/log/waydroid-manager.log"
LOCK_FILE="/tmp/waydroid-manager.lock"
TEMP_DIR="/tmp/waydroid-install-$$"

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null
    fi
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null
    fi
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script exited with error code: $exit_code"
    fi
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Create temp directory
setup_temp() {
    mkdir -p "$TEMP_DIR"
    log_info "Created temporary directory: $TEMP_DIR"
}

# Logging functions
log_info() { echo -e "${GREEN}${INFO} [INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}${CHECK_MARK} [SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}${CROSS_MARK} [ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}${WARNING} [WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_step() { echo -e "${CYAN}${GEAR} [STEP]${NC} $1" | tee -a "$LOG_FILE"; }
log_header() {
    echo -e "\n${PURPLE}${BOLD}════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${PURPLE}${BOLD}  $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${PURPLE}${BOLD}════════════════════════════════════════════${NC}\n" | tee -a "$LOG_FILE"
}

# Initialize log file
setup_logging() {
    touch "$LOG_FILE" 2>/dev/null || sudo touch "$LOG_FILE"
    chmod 640 "$LOG_FILE" 2>/dev/null || sudo chmod 640 "$LOG_FILE"
    log_info "Logging initialized: $LOG_FILE"
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo -e "${YELLOW}Try: sudo $0${NC}"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Get host architecture
get_host_arch() {
    uname -m
}

# Get current kernel version
get_kernel_version() {
    uname -r
}

# Get kernel name (e.g., zen, lts, default)
get_kernel_flavor() {
    local kernel=$(uname -r)
    if [[ "$kernel" == *"-zen"* ]]; then
        echo "zen"
    elif [[ "$kernel" == *"-lts"* ]]; then
        echo "lts"
    elif [[ "$kernel" == *"-hardened"* ]]; then
        echo "hardened"
    else
        echo "default"
    fi
}

# Check for Wayland session
check_wayland() {
    log_step "Checking display server"
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        log_warn "Wayland not detected. You are likely running X11."
        echo "Waydroid requires a Wayland compositor for optimal performance."
        echo ""
        echo "Options:"
        echo "  1) Switch to a Wayland session (recommended for your DE)"
        echo "  2) Run Weston (nested Wayland compositor): sudo weston"
        echo "  3) Continue anyway (may have issues)"
        echo ""
        echo -n "Continue anyway? (y/N): "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            return 1
        fi
        log_warn "Continuing without Wayland detection - UI may have issues"
    else
        log_success "Wayland session detected: $WAYLAND_DISPLAY"
    fi
}

# Setup firewall for Waydroid network bridge
setup_firewall() {
    log_step "Configuring firewall for Waydroid network access"

    if command_exists ufw; then
        log_info "Detected UFW firewall"
        ufw route allow in on waydroid0 >/dev/null 2>&1
        ufw route allow out on waydroid0 >/dev/null 2>&1
        log_success "UFW rules updated for waydroid0 interface"
    elif command_exists nft; then
        log_info "Detected nftables"
        # Add nftables rules if needed
        nft add rule inet filter forward iifname "waydroid0" accept 2>/dev/null || true
        nft add rule inet filter forward oifname "waydroid0" accept 2>/dev/null || true
        log_success "nftables rules updated"
    elif command_exists iptables; then
        log_info "Detected iptables"
        iptables -I FORWARD -i waydroid0 -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD -o waydroid0 -j ACCEPT 2>/dev/null || true
        log_success "iptables rules updated"
    else
        log_warn "No supported firewall detected. Network may not work in container."
    fi
}

# Install binder module with kernel header detection
install_binder_module() {
    local distro=$(detect_distro)
    local kernel_flavor=$(get_kernel_flavor)
    local kernel_version=$(get_kernel_version)

    log_step "Installing binder module for kernel: $kernel_version (flavor: $kernel_flavor)"

    case $distro in
        arch|manjaro|endeavouros)
            local headers_package=""

            # Install appropriate headers based on running kernel
            case $kernel_flavor in
                zen)
                    headers_package="linux-zen-headers"
                    ;;
                lts)
                    headers_package="linux-lts-headers"
                    ;;
                hardened)
                    headers_package="linux-hardened-headers"
                    ;;
                default)
                    # Check if it's a custom kernel or standard
                    if pacman -Qs "linux-headers" >/dev/null 2>&1; then
                        headers_package="linux-headers"
                    else
                        # Try to detect which kernel is installed
                        if pacman -Qs "linux-zen" >/dev/null 2>&1; then
                            headers_package="linux-zen-headers"
                        elif pacman -Qs "linux-lts" >/dev/null 2>&1; then
                            headers_package="linux-lts-headers"
                        elif pacman -Qs "linux-hardened" >/dev/null 2>&1; then
                            headers_package="linux-hardened-headers"
                        else
                            headers_package="linux-headers"
                        fi
                    fi
                    ;;
            esac

            log_info "Installing kernel headers: $headers_package"
            pacman -S --noconfirm "$headers_package" binder_linux-dkms

            # Load the module
            log_step "Loading binder module"
            modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null || {
                log_error "Failed to load binder_linux after installing headers."
                log_info "You may need to reboot or rebuild the module with:"
                echo "  sudo dkms install binder_linux/$(modinfo binder_linux 2>/dev/null | grep ^version | awk '{print $2}')"
                return 1
            }
            ;;

        debian|ubuntu|linuxmint|pop)
            apt update
            apt install -y linux-headers-$(uname -r) binder_linux-dkms
            modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null
            ;;

        fedora|rhel|centos|rocky)
            dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r) binder_linux-dkms
            modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null
            ;;

        opensuse*)
            zypper install -y kernel-devel kernel-default-devel binder_linux-dkms
            modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null
            ;;

        *)
            log_warn "Unknown distribution. Please install binder module manually."
            return 1
            ;;
    esac
}

# Check binder module
check_binder() {
    log_step "Checking binder module"

    if lsmod | grep -q "binder_linux"; then
        log_success "Binder module is loaded"
        return 0
    fi

    log_warn "Binder module not loaded. Attempting to load..."

    # Try to load the module first
    if modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null; then
        log_success "Binder module loaded successfully"
        return 0
    fi

    # If loading fails, try to install it
    log_warn "Failed to load binder_linux. Attempting to install appropriate headers and module..."

    if install_binder_module; then
        log_success "Binder module installed and loaded successfully"
        return 0
    else
        local distro=$(detect_distro)
        local kernel_flavor=$(get_kernel_flavor)

        log_error "Failed to install/load binder_linux module"
        echo ""
        echo "===== TROUBLESHOOTING ====="
        echo "Your current kernel: $(uname -r)"
        echo "Detected kernel flavor: $kernel_flavor"
        echo ""

        case $distro in
            arch|manjaro|endeavouros)
                echo "For Arch Linux and derivatives, install the appropriate headers:"
                echo "  - For linux-zen kernel:  sudo pacman -S linux-zen-headers"
                echo "  - For linux-lts kernel:  sudo pacman -S linux-lts-headers"
                echo "  - For linux-hardened:    sudo pacman -S linux-hardened-headers"
                echo "  - For default kernel:    sudo pacman -S linux-headers"
                echo ""
                echo "Then install and load the binder module:"
                echo "  sudo pacman -S binder_linux-dkms"
                echo "  sudo modprobe binder_linux"
                echo ""
                echo "If the module still fails to load, try rebooting:"
                echo "  sudo reboot"
                ;;
            debian|ubuntu)
                echo "For Debian/Ubuntu:"
                echo "  sudo apt update"
                echo "  sudo apt install linux-headers-$(uname -r) binder_linux-dkms"
                echo "  sudo modprobe binder_linux"
                ;;
            fedora)
                echo "For Fedora:"
                echo "  sudo dnf install kernel-devel-$(uname -r) kernel-headers-$(uname -r) binder_linux-dkms"
                echo "  sudo modprobe binder_linux"
                ;;
            *)
                echo "Please install the binder_linux module for your kernel: $(uname -r)"
                echo "Then run: sudo modprobe binder_linux"
                ;;
        esac
        echo "================================="
        return 1
    fi
}

# Install required dependencies based on distribution
install_dependencies() {
    local distro=$(detect_distro)
    log_step "Installing dependencies for $distro"

    case $distro in
        arch|manjaro|endeavouros)
            pacman -S --noconfirm lzip git python python-pip python-virtualenv waydroid weston ufw
            # Don't install binder_linux-dkms and headers here - they'll be handled by check_binder
            ;;
        debian|ubuntu|linuxmint|pop)
            apt update
            apt install -y lzip git python3 python3-pip python3-venv waydroid weston ufw
            ;;
        fedora|rhel|centos|rocky)
            dnf install -y lzip git python3 python3-pip python3-virtualenv waydroid weston
            ;;
        opensuse*)
            zypper install -y lzip git python3 python3-pip python3-virtualenv waydroid weston
            ;;
        *)
            log_warn "Unknown distribution. Please install lzip, git, python3, python3-pip manually"
            echo -n "Continue anyway? (y/N): "
            read -r continue
            if [[ ! "$continue" =~ ^[Yy]$ ]]; then
                return 1
            fi
            ;;
    esac

    # Verify binder module after installation
    check_binder

    # Setup firewall
    setup_firewall

    log_success "Dependencies installed"
}

# Install WayDroid on Arch Linux
install_arch() {
    log_header "STEP 2: INSTALLING WAYDROID ON ARCH LINUX"

    # Check for Wayland
    check_wayland

    # Check if running on Arch
    local distro=$(detect_distro)
    if [[ "$distro" != "arch" && "$distro" != "manjaro" && "$distro" != "endeavouros" ]]; then
        log_warn "This installation is optimized for Arch Linux and derivatives"
        echo -e "Detected distribution: ${YELLOW}$distro${NC}"
        echo -e "Continue anyway? (y/N): "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            return 1
        fi
    fi

    log_step "Updating system"
    pacman -Syu --noconfirm

    log_step "Installing WayDroid and base dependencies"
    pacman -S --noconfirm waydroid weston lzip git python python-pip python-virtualenv ufw

    # Check binder module - this will handle kernel headers and binder_linux-dkms installation
    check_binder

    # Setup firewall
    setup_firewall

    # Initialize WayDroid if needed
    if [[ ! -d "/var/lib/waydroid/images" ]]; then
        log_step "Initializing WayDroid"
        waydroid init
    fi

    # Start service
    log_step "Starting WayDroid container service"
    systemctl enable --now waydroid-container

    log_success "WayDroid installed successfully"

    # Provide next steps
    echo
    log_info "Next steps:"
    echo "  1. Run 'sudo $0 ui' to start WayDroid in full UI mode"
    echo "  2. Or run 'sudo $0 multi' for multi-window mode"
    echo "  3. Run 'sudo $0 install gapps' to install Google Apps"
    echo "  4. For ARM apps on x86, install: libndk (AMD) or libhoudini (Intel)"
    echo "  5. Get Play Store certification: sudo $0 certified"
}

# [Rest of the script remains the same - install_apps_menu, remove_apps_menu, show_help, etc.]
# ... (keep all the subsequent functions unchanged)

# Run the Python script with arguments
run_python_script() {
    # Check if virtual environment exists, if not install dependencies
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        log_warn "Python virtual environment not found. Setting up waydroid_script first..."
        setup_waydroid_script
    fi

    if [[ ! -f "$MAIN_PY" ]]; then
        log_error "waydroid_script not found. Please run setup first."
        return 1
    fi

    log_step "Running: ${PYTHON_SCRIPT} ${MAIN_PY} $*"
    cd "$WAYDROID_SCRIPT_DIR"
    "${PYTHON_SCRIPT}" "$MAIN_PY" "$@"
}

# Clone and setup waydroid_script
setup_waydroid_script() {
    log_header "STEP 1: SETTING UP WAYDROID SCRIPT"

    # Create temp directory
    setup_temp

    # Check if already exists
    if [[ -d "$WAYDROID_SCRIPT_DIR" ]]; then
        log_info "waydroid_script directory already exists"
        echo -n "Update it? (y/N): "
        read -r update
        if [[ "$update" =~ ^[Yy]$ ]]; then
            log_step "Updating waydroid_script repository"
            cd "$WAYDROID_SCRIPT_DIR"
            git pull
        fi
    else
        log_step "Cloning waydroid_script repository"
        git clone https://github.com/casualsnek/waydroid_script.git "$WAYDROID_SCRIPT_DIR"
    fi

    # Setup virtual environment
    if [[ ! -d "${WAYDROID_SCRIPT_DIR}/venv" ]]; then
        log_step "Creating Python virtual environment"
        cd "$WAYDROID_SCRIPT_DIR"
        python3 -m venv venv
    fi

    # Install requirements
    log_step "Installing Python requirements"
    cd "$WAYDROID_SCRIPT_DIR"
    "${PYTHON_SCRIPT}" -m pip install --upgrade pip
    "${PYTHON_SCRIPT}" -m pip install -r requirements.txt

    log_success "waydroid_script setup complete"
}

# [Keep all the other functions: install_apps_menu, remove_apps_menu, show_help, interactive_mode, main]
# ... (copy them unchanged from the original script)

# Main menu and other functions remain exactly the same as in the original script
# I'll include them here but for brevity in this diff, I'm noting they should be kept
