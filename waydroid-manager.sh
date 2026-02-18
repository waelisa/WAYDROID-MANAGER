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
        echo -e "${RED}${CROSS_MARK} [ERROR] Script exited with error code: $exit_code${NC}" | tee -a "$LOG_FILE"
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
    # Try to create log file with sudo if needed
    if ! touch "$LOG_FILE" 2>/dev/null; then
        sudo touch "$LOG_FILE" 2>/dev/null || true
    fi
    if ! chmod 640 "$LOG_FILE" 2>/dev/null; then
        sudo chmod 640 "$LOG_FILE" 2>/dev/null || true
    fi
    log_info "Logging initialized: $LOG_FILE"
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${CROSS_MARK} [ERROR] This script must be run as root${NC}"
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
            if modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null; then
                log_success "Binder module loaded successfully"
                return 0
            else
                log_error "Failed to load binder_linux after installing headers."
                log_info "You may need to reboot or rebuild the module with:"
                echo "  sudo dkms install binder_linux/$(modinfo binder_linux 2>/dev/null | grep ^version | awk '{print $2}')"
                return 1
            fi
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

    log_success "Dependencies installed"
}

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

# Install apps submenu
install_apps_menu() {
    while true; do
        clear
        log_header "INSTALL APPS MENU"
        echo -e "${CYAN}Select apps to install (enter numbers separated by spaces):${NC}"
        echo
        echo " 1) gapps         - Google Apps"
        echo " 2) microg        - MicroG (open source Google services)"
        echo " 3) libndk        - ARM translation for AMD CPUs"
        echo " 4) libhoudini    - ARM translation for Intel CPUs"
        echo " 5) magisk        - Magisk Delta for root"
        echo " 6) widevine      - Widevine DRM L3"
        echo " 7) smartdock     - Desktop mode launcher"
        echo " 8) fdroidpriv    - FDroid Privileged Extension"
        echo " 9) nodataperm    - NoDataPerm hack (Android 11 only)"
        echo "10) hidestatusbar - Hide status bar hack (Android 11 only)"
        echo "11) mitm          - MITM CA certificate (requires certificate file)"
        echo " 0) Back to main menu"
        echo
        echo -n "Enter selection (e.g., '1 3 5'): "

        read -r selections

        if [[ "$selections" == "0" ]]; then
            return 0
        fi

        if [[ -z "$selections" ]]; then
            log_error "No selection made"
            read -p "Press Enter to continue..."
            continue
        fi

        # Build the install command
        local install_args=()
        local has_mitm=0

        for num in $selections; do
            case $num in
                1) install_args+=("gapps") ;;
                2) install_args+=("microg") ;;
                3) install_args+=("libndk") ;;
                4) install_args+=("libhoudini") ;;
                5) install_args+=("magisk") ;;
                6) install_args+=("widevine") ;;
                7) install_args+=("smartdock") ;;
                8) install_args+=("fdroidpriv") ;;
                9) install_args+=("nodataperm") ;;
                10) install_args+=("hidestatusbar") ;;
                11) has_mitm=1 ;;
                *) log_warn "Invalid selection: $num" ;;
            esac
        done

        # Handle MITM separately (needs certificate file)
        if [[ $has_mitm -eq 1 ]]; then
            echo
            echo -n "Enter path to CA certificate file for MITM: "
            read -r cert_path
            if [[ -f "$cert_path" ]]; then
                # MITM needs to be run separately with --ca-cert
                if [[ ${#install_args[@]} -gt 0 ]]; then
                    log_info "Installing: ${install_args[*]}"
                    run_python_script install "${install_args[@]}"
                fi
                log_info "Installing MITM with certificate"
                run_python_script install mitm --ca-cert "$cert_path"
            else
                log_error "Certificate file not found: $cert_path"
            fi
        else
            if [[ ${#install_args[@]} -gt 0 ]]; then
                log_info "Installing: ${install_args[*]}"
                run_python_script install "${install_args[@]}"
            else
                log_warn "No valid apps selected"
            fi
        fi

        echo
        read -p "Press Enter to continue..."
    done
}

# Remove apps submenu
remove_apps_menu() {
    while true; do
        clear
        log_header "REMOVE APPS MENU"
        echo -e "${CYAN}Select apps to remove (enter numbers separated by spaces):${NC}"
        echo
        echo " 1) gapps         - Google Apps"
        echo " 2) microg        - MicroG"
        echo " 3) libndk        - ARM translation for AMD CPUs"
        echo " 4) libhoudini    - ARM translation for Intel CPUs"
        echo " 5) magisk        - Magisk Delta"
        echo " 6) widevine      - Widevine DRM L3"
        echo " 7) smartdock     - Desktop mode launcher"
        echo " 8) fdroidpriv    - FDroid Privileged Extension"
        echo " 9) nodataperm    - NoDataPerm hack"
        echo "10) hidestatusbar - Hide status bar hack"
        echo "11) mitm          - MITM CA certificate"
        echo " 0) Back to main menu"
        echo
        echo -n "Enter selection (e.g., '1 3 5'): "

        read -r selections

        if [[ "$selections" == "0" ]]; then
            return 0
        fi

        if [[ -z "$selections" ]]; then
            log_error "No selection made"
            read -p "Press Enter to continue..."
            continue
        fi

        local remove_args=()

        for num in $selections; do
            case $num in
                1) remove_args+=("gapps") ;;
                2) remove_args+=("microg") ;;
                3) remove_args+=("libndk") ;;
                4) remove_args+=("libhoudini") ;;
                5) remove_args+=("magisk") ;;
                6) remove_args+=("widevine") ;;
                7) remove_args+=("smartdock") ;;
                8) remove_args+=("fdroidpriv") ;;
                9) remove_args+=("nodataperm") ;;
                10) remove_args+=("hidestatusbar") ;;
                11) remove_args+=("mitm") ;;
                *) log_warn "Invalid selection: $num" ;;
            esac
        done

        if [[ ${#remove_args[@]} -gt 0 ]]; then
            log_info "Removing: ${remove_args[*]}"
            run_python_script uninstall "${remove_args[@]}"
        else
            log_warn "No valid apps selected"
        fi

        echo
        read -p "Press Enter to continue..."
    done
}

# Show help
show_help() {
    clear
    log_header "WAYDROID MANAGEMENT SCRIPT - HELP"

    echo -e "${CYAN}${BOLD}USAGE:${NC}"
    echo -e "    $0 [COMMAND] [OPTIONS]"
    echo

    echo -e "${GREEN}${BOLD}COMMANDS:${NC}"
    echo -e "    ${BOLD}Setup:${NC}"
    echo -e "    setup              Clone and setup waydroid_script"
    echo -e "    install-deps       Install required system dependencies"
    echo
    echo -e "    ${BOLD}Installation:${NC}"
    echo -e "    install-arch       Install WayDroid on Arch Linux"
    echo
    echo -e "    ${BOLD}App Management (via waydroid_script):${NC}"
    echo -e "    install <apps>     Install apps (gapps, microg, libndk, libhoudini, etc.)"
    echo -e "    remove <apps>      Remove apps"
    echo -e "    certified          Get Android ID for Play Store certification"
    echo -e "    hack <hacks>       Apply hacks (nodataperm, hidestatusbar)"
    echo
    echo -e "    ${BOLD}UI Modes:${NC}"
    echo -e "    ui                 Start WayDroid in full UI mode (desktop environment)"
    echo -e "    multi              Start WayDroid in multi-window mode (apps as Linux windows)"
    echo
    echo -e "    ${BOLD}Service:${NC}"
    echo -e "    start              Start WayDroid container"
    echo -e "    stop               Stop WayDroid container"
    echo -e "    restart            Restart WayDroid container"
    echo -e "    status             Show container status"
    echo
    echo -e "    ${BOLD}Utilities:${NC}"
    echo -e "    help               Show this help"
    echo
    echo -e "${GREEN}${BOLD}AVAILABLE APPS:${NC}"
    echo -e "    ${YELLOW}Core:${NC}"
    echo -e "    gapps          - Google Apps"
    echo -e "    microg         - MicroG (open source Google services)"
    echo
    echo -e "    ${YELLOW}Translation:${NC}"
    echo -e "    libndk         - ARM translation (better for AMD CPUs)"
    echo -e "    libhoudini     - ARM translation (better for Intel CPUs)"
    echo
    echo -e "    ${YELLOW}Enhancements:${NC}"
    echo -e "    magisk         - Magisk Delta for root access"
    echo -e "    widevine       - Widevine DRM L3 support"
    echo -e "    smartdock      - Desktop mode launcher"
    echo -e "    fdroidpriv     - FDroid Privileged Extension"
    echo -e "    mitm           - MITM CA certificate (use --ca-cert cert.pem)"
    echo
    echo -e "    ${YELLOW}Hacks (Android 11 only):${NC}"
    echo -e "    nodataperm     - Remove data permissions from all apps"
    echo -e "    hidestatusbar  - Hide Android status bar"
    echo
    echo -e "${GREEN}${BOLD}EXAMPLES:${NC}"
    echo -e "    # First time setup"
    echo -e "    sudo $0 install-deps"
    echo -e "    sudo $0 setup"
    echo
    echo -e "    # Install WayDroid on Arch"
    echo -e "    sudo $0 install-arch"
    echo
    echo -e "    # Start WayDroid UI"
    echo -e "    sudo $0 ui"
    echo
    echo -e "    # Install multiple components"
    echo -e "    sudo $0 install gapps microg magisk"
    echo
    echo -e "    # Install ARM translation for Intel CPU"
    echo -e "    sudo $0 install libhoudini"
    echo
    echo -e "    # Get Google certification ID"
    echo -e "    sudo $0 certified"
    echo
    echo -e "${YELLOW}${BOLD}NOTE: Most commands require root privileges (sudo)${NC}"
}

# Main menu
interactive_mode() {
    # Setup logging first
    setup_logging

    # Create lock file to prevent concurrent runs
    if [[ -f "$LOCK_FILE" ]]; then
        log_error "Another instance is already running (lock file: $LOCK_FILE)"
        exit 1
    fi
    touch "$LOCK_FILE"

    while true; do
        clear
        log_header "WAYDROID MANAGER - by Wael Isa (v2.1.1)"
        echo -e "${CYAN}System:${NC} $(detect_distro) | $(get_host_arch) | Kernel: $(uname -r)"
        echo -e "${CYAN}Wayland:${NC} ${WAYLAND_DISPLAY:-Not detected}"
        echo -e "${CYAN}Binder Module:${NC} $(lsmod | grep -q binder_linux && echo "${GREEN}Loaded${NC}" || echo "${RED}Not loaded${NC}")"
        echo -e "${CYAN}Waydroid Script:${NC} $([[ -f "$MAIN_PY" ]] && echo "${GREEN}Installed${NC}" || echo "${RED}Not installed${NC}")"
        echo -e "${CYAN}Log File:${NC} $LOG_FILE"
        echo

        echo "1) Install WayDroid on Arch Linux"
        echo "2) Install Apps (via waydroid_script)"
        echo "3) Remove Apps (via waydroid_script)"
        echo "4) Get Android ID (Play Store Certification)"
        echo "5) Apply Hacks"
        echo "6) Start WayDroid (Full UI Mode)"
        echo "7) Start WayDroid (Multi-window Mode)"
        echo "8) Stop WayDroid"
        echo "9) Restart WayDroid"
        echo "10) Show Status"
        echo "11) Update waydroid_script"
        echo "12) Install Dependencies"
        echo "13) Setup waydroid_script"
        echo "14) Check Binder Module"
        echo "15) Help"
        echo "16) Exit"
        echo
        echo -n "Select [1-16]: "

        read -r choice
        case $choice in
            1)
                install_arch
                read -p "Press Enter to continue..."
                ;;
            2)
                install_apps_menu
                ;;
            3)
                remove_apps_menu
                ;;
            4)
                log_info "Fetching Google Device ID for Play Store certification..."
                run_python_script certified
                echo
                log_info "Copy the ID above and register it at:"
                echo -e "${CYAN}https://www.google.com/android/uncertified/${NC}"
                read -p "Press Enter to continue..."
                ;;
            5)
                echo
                echo -e "${CYAN}Available hacks:${NC}"
                echo "  nodataperm     - NoDataPerm hack (Android 11)"
                echo "  hidestatusbar  - Hide status bar hack"
                echo
                echo -n "Enter hack to apply: "
                read -r hack
                if [[ -n "$hack" ]]; then
                    run_python_script hack "$hack"
                fi
                read -p "Press Enter to continue..."
                ;;
            6)
                log_info "Starting WayDroid in Full UI mode..."
                check_wayland
                check_binder
                waydroid show-full-ui &
                log_success "WayDroid UI started (running in background)"
                read -p "Press Enter to continue..."
                ;;
            7)
                log_info "Starting WayDroid in Multi-window mode..."
                log_info "This will make Android apps appear as native Linux windows"
                check_wayland
                check_binder
                waydroid session start &
                sleep 2
                waydroid show-full-ui &
                log_success "WayDroid multi-window mode started"
                read -p "Press Enter to continue..."
                ;;
            8)
                systemctl stop waydroid-container
                log_success "WayDroid stopped"
                read -p "Press Enter to continue..."
                ;;
            9)
                systemctl restart waydroid-container
                log_success "WayDroid restarted"
                read -p "Press Enter to continue..."
                ;;
            10)
                systemctl status waydroid-container
                read -p "Press Enter to continue..."
                ;;
            11)
                setup_waydroid_script
                read -p "Press Enter to continue..."
                ;;
            12)
                install_dependencies
                read -p "Press Enter to continue..."
                ;;
            13)
                setup_waydroid_script
                read -p "Press Enter to continue..."
                ;;
            14)
                check_binder
                read -p "Press Enter to continue..."
                ;;
            15)
                show_help
                read -p "Press Enter to continue..."
                ;;
            16)
                log_info "Goodbye!"
                rm -f "$LOCK_FILE"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Main
main() {
    # Setup logging
    setup_logging

    if [[ $# -eq 0 ]]; then
        # No arguments - check root and go to interactive mode
        check_root
        interactive_mode
    else
        case $1 in
            help|--help|-h)
                show_help
                ;;
            setup)
                check_root
                setup_waydroid_script
                ;;
            install-deps)
                check_root
                install_dependencies
                ;;
            install-arch)
                check_root
                install_arch
                ;;
            certified|start|stop|restart|status)
                check_root
                case $1 in
                    certified)
                        shift
                        log_info "Fetching Google Device ID for Play Store certification..."
                        run_python_script certified
                        echo
                        log_info "Copy the ID above and register it at:"
                        echo -e "${CYAN}https://www.google.com/android/uncertified/${NC}"
                        ;;
                    start)
                        shift
                        check_binder
                        systemctl start waydroid-container
                        log_success "WayDroid container started"
                        ;;
                    stop)
                        shift
                        systemctl stop waydroid-container
                        log_success "WayDroid container stopped"
                        ;;
                    restart)
                        shift
                        systemctl restart waydroid-container
                        log_success "WayDroid container restarted"
                        ;;
                    status)
                        shift
                        systemctl status waydroid-container
                        ;;
                esac
                ;;
            ui)
                check_root
                log_info "Starting WayDroid in Full UI mode..."
                check_wayland
                check_binder
                waydroid show-full-ui &
                log_success "WayDroid UI started (running in background)"
                ;;
            multi)
                check_root
                log_info "Starting WayDroid in Multi-window mode..."
                log_info "This will make Android apps appear as native Linux windows"
                check_wayland
                check_binder
                waydroid session start &
                sleep 2
                waydroid show-full-ui &
                log_success "WayDroid multi-window mode started"
                ;;
            install)
                check_root
                shift
                run_python_script install "$@"
                ;;
            remove|uninstall)
                check_root
                shift
                run_python_script uninstall "$@"
                ;;
            hack)
                check_root
                shift
                run_python_script hack "$@"
                ;;
            *)
                log_error "Unknown command: $1"
                echo
                show_help
                exit 1
                ;;
        esac
    fi
}

# Run main with all arguments
main "$@"
