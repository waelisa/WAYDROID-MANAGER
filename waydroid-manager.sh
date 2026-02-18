#!/usr/bin/env bash

#############################################################################################################################
# The MIT License (MIT)
# Wael Isa
# Build Date: 02/18/2026
# Version: 2.1.8
# https://github.com/waelisa/WAYDROID-MANAGER
#############################################################################################################################
# WayDroid Management Script - Complete Android container orchestrator for Linux
# Features:
#   ✓ Multi-distro support (Arch, Debian, Fedora, openSUSE)
#   ✓ Proper Wayland detection with sudo
#   ✓ Intelligent binder detection (DKMS vs built-in)
#   ✓ Automatic binderfs mounting for Zen/CachyOS kernels
#   ✓ Clean status display
#############################################################################################################################

set -u
set -o pipefail

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

# Get the original user (the one who ran sudo)
ORIGINAL_USER="${SUDO_USER:-$USER}"

# Cleanup function
cleanup() {
    local exit_code=$?
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE" 2>/dev/null
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}${CROSS_MARK} [ERROR] Script exited with error code: $exit_code${NC}" | tee -a "$LOG_FILE"
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

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

# Setup logging
setup_logging() {
    if ! touch "$LOG_FILE" 2>/dev/null; then
        sudo touch "$LOG_FILE" 2>/dev/null || {
            echo "Warning: Cannot create log file $LOG_FILE"
            LOG_FILE="/tmp/waydroid-manager.log"
            touch "$LOG_FILE"
        }
    fi
    chmod 640 "$LOG_FILE" 2>/dev/null || sudo chmod 640 "$LOG_FILE" 2>/dev/null
    echo "=== WayDroid Manager Log Started at $(date) ===" >> "$LOG_FILE"
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
    command -v "$1" &>/dev/null
}

# Improved Wayland detection that works with sudo
is_wayland_active() {
    # Method 1: Check if running under sudo and get original user's session
    if [[ -n "${SUDO_USER:-}" ]]; then
        local uid=$(id -u "$ORIGINAL_USER")

        # Check for Wayland socket in user's runtime directory
        if [[ -S "/run/user/$uid/wayland-0" ]] || [[ -S "/run/user/$uid/wayland-1" ]]; then
            return 0
        fi

        # Check with loginctl for the original user
        local session_id=$(loginctl | grep "$ORIGINAL_USER" | awk '{print $1}' | head -1)
        if [[ -n "$session_id" ]]; then
            local session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null)
            [[ "$session_type" == "wayland" ]] && return 0
        fi
    fi

    # Method 2: Check current environment variables
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && return 0
    [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && return 0
    [[ "${DESKTOP_SESSION:-}" == *"wayland"* ]] && return 0

    return 1
}

# Check if WayDroid is installed
is_waydroid_installed() {
    command -v waydroid &>/dev/null && [[ -d "/var/lib/waydroid" ]]
}

# Check if WayDroid container is running
is_waydroid_running() {
    systemctl is-active --quiet waydroid-container 2>/dev/null
}

# Improved binder detection
is_binder_available() {
    lsmod | grep -qE "binder_linux|binder" && return 0
    grep -q "binder" /proc/filesystems && return 0
    return 1
}

is_binder_working() {
    lsmod | grep -qE "binder_linux|binder" && return 0
    mount | grep -q "binder" && return 0
    return 1
}

# Secure Boot detection
is_secure_boot_enabled() {
    command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"
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

# Get kernel flavor
get_kernel_flavor() {
    local kernel=$(uname -r)
    [[ "$kernel" == *"-zen"* ]] && echo "zen" && return
    [[ "$kernel" == *"-lts"* ]] && echo "lts" && return
    [[ "$kernel" == *"-hardened"* ]] && echo "hardened" && return
    [[ "$kernel" == *"-cachyos"* ]] && echo "cachyos" && return
    echo "default"
}

# Setup binderfs for kernels with built-in binder
setup_binderfs() {
    log_step "Setting up binderfs"
    mkdir -p /dev/binderfs
    if mount -t binder binder /dev/binderfs 2>/dev/null; then
        log_success "binderfs mounted successfully"
        if ! grep -q "^binder /dev/binderfs" /etc/fstab 2>/dev/null; then
            echo "binder /dev/binderfs binder defaults 0 0" >> /etc/fstab
        fi
        return 0
    fi
    return 1
}

# Interactive Wayland check
check_wayland_interactive() {
    if is_wayland_active; then
        return 0
    fi

    log_warn "Wayland not detected"
    echo ""
    echo "Waydroid requires a Wayland compositor for optimal performance."
    echo "Options:"
    echo "  1) Log out and select a Wayland session from your login manager"
    echo "  2) Run Weston (nested Wayland compositor): sudo weston"
    echo "  3) Continue anyway (may have issues)"
    echo ""
    read -p "Continue anyway? (y/N): " continue_anyway
    [[ "$continue_anyway" =~ ^[Yy]$ ]]
}

# Setup firewall
setup_firewall() {
    log_step "Configuring firewall"
    if command_exists ufw; then
        ufw route allow in on waydroid0 &>/dev/null
        ufw route allow out on waydroid0 &>/dev/null
        log_success "UFW rules updated"
    elif command_exists nft; then
        nft add rule inet filter forward iifname "waydroid0" accept &>/dev/null || true
        nft add rule inet filter forward oifname "waydroid0" accept &>/dev/null || true
        log_success "nftables rules updated"
    elif command_exists iptables; then
        iptables -I FORWARD -i waydroid0 -j ACCEPT &>/dev/null || true
        iptables -I FORWARD -o waydroid0 -j ACCEPT &>/dev/null || true
        log_success "iptables rules updated"
    fi
}

# Install dependencies based on distribution
install_dependencies() {
    local distro=$(detect_distro)
    log_step "Installing dependencies for $distro"

    case $distro in
        arch|manjaro|endeavouros|cachyos)
            pacman -S --noconfirm --needed \
                base-devel mokutil lzip git python python-pip \
                python-virtualenv waydroid weston ufw dkms || return 1
            ;;
        debian|ubuntu|linuxmint|pop)
            apt update && apt install -y \
                build-essential mokutil lzip git python3 python3-pip \
                python3-venv waydroid weston ufw dkms || return 1
            ;;
        fedora|rhel|centos|rocky)
            dnf groupinstall -y "Development Tools" && \
            dnf install -y mokutil lzip git python3 python3-pip \
                python3-virtualenv waydroid weston dkms || return 1
            ;;
        opensuse*)
            zypper install -y -t pattern devel_basis && \
            zypper install -y mokutil lzip git python3 python3-pip \
                python3-virtualenv waydroid weston dkms || return 1
            ;;
        *)
            log_warn "Unknown distribution: $distro"
            echo "Please install the following packages manually:"
            echo "  - lzip, git, python3, python3-pip, python3-venv"
            echo "  - waydroid, weston"
            echo "  - build tools (gcc, make, kernel headers)"
            echo "  - dkms, mokutil (for Secure Boot detection)"
            read -p "Continue anyway? (y/N): " continue_anyway
            [[ ! "$continue_anyway" =~ ^[Yy]$ ]] && return 1
            ;;
    esac

    log_success "Dependencies installed"
    setup_firewall
}

# Install binder module
install_binder_module() {
    local distro=$(detect_distro)
    local kernel_flavor=$(get_kernel_flavor)
    local running_kernel=$(uname -r)

    log_step "Setting up binder for kernel: $running_kernel"

    # Check Secure Boot
    if is_secure_boot_enabled; then
        log_warn "SECURE BOOT ENABLED"
        echo "This will prevent unsigned kernel modules from loading."
        read -p "Disable Secure Boot in BIOS and try again. Continue anyway? (y/N): " sb_choice
        [[ ! "$sb_choice" =~ ^[Yy]$ ]] && return 1
    fi

    # Try to load module
    load_output=$(modprobe binder_linux 2>&1)
    if [[ $? -eq 0 ]]; then
        log_success "Binder module loaded"
        echo "binder_linux" > /etc/modules-load.d/waydroid.conf 2>/dev/null || true
        return 0
    fi

    # Handle "Device or resource busy" - built-in binder
    if [[ "$load_output" == *"Device or resource busy"* ]]; then
        log_info "Binder is built into kernel"
        setup_binderfs && return 0 || return 1
    fi

    # Install DKMS module based on distribution
    log_warn "Installing binder module via DKMS"

    case $distro in
        arch|manjaro|endeavouros|cachyos)
            local headers="linux-headers"
            [[ "$kernel_flavor" != "default" ]] && headers="linux-${kernel_flavor}-headers"
            pacman -S --noconfirm --needed "$headers" binder_linux-dkms || return 1
            ;;
        debian|ubuntu|linuxmint|pop)
            apt update && apt install -y linux-headers-"$running_kernel" binder_linux-dkms || return 1
            ;;
        fedora|rhel|centos|rocky)
            dnf install -y kernel-devel-"$running_kernel" kernel-headers-"$running_kernel" binder_linux-dkms || return 1
            ;;
        opensuse*)
            zypper install -y kernel-devel kernel-default-devel binder_linux-dkms || return 1
            ;;
        *)
            log_error "Unsupported distribution for automatic binder installation"
            echo "Please install binder_linux-dkms manually for your distribution"
            return 1
            ;;
    esac

    # Build with DKMS
    if command -v dkms &>/dev/null; then
        local binder_version=$(dkms status binder_linux 2>/dev/null | head -1 | sed -n 's/.*binder_linux\/\([^,]*\).*/\1/p' | tr -d ' ')
        if [[ -n "$binder_version" ]]; then
            dkms install binder_linux/"$binder_version" -k "$running_kernel" &>/dev/null
        else
            dkms autoinstall -k "$running_kernel" &>/dev/null
        fi
    fi

    depmod -a "$running_kernel"

    if modprobe binder_linux &>/dev/null; then
        log_success "Binder module installed and loaded"
        echo "binder_linux" > /etc/modules-load.d/waydroid.conf 2>/dev/null || true
        return 0
    fi

    log_error "Failed to load binder module"
    return 1
}

# Interactive binder check
check_binder_interactive() {
    log_step "Checking binder"
    if is_binder_working; then
        log_success "Binder is working"
        return 0
    fi

    echo ""
    echo "1) Setup binder automatically"
    echo "2) Show manual instructions"
    echo "3) Skip"
    read -p "Select [1-3]: " choice

    case $choice in
        1) install_binder_module ;;
        2)
            echo ""
            echo "For kernels with built-in binder (Zen/CachyOS):"
            echo "  sudo mkdir -p /dev/binderfs"
            echo "  sudo mount -t binder binder /dev/binderfs"
            echo "  echo 'binder /dev/binderfs binder defaults 0 0' | sudo tee -a /etc/fstab"
            echo ""
            echo "For standard kernels:"
            case $(detect_distro) in
                arch*|manjaro*)
                    echo "  sudo pacman -S linux-$(get_kernel_flavor)-headers binder_linux-dkms"
                    ;;
                debian*|ubuntu*)
                    echo "  sudo apt install linux-headers-$(uname -r) binder_linux-dkms"
                    ;;
                fedora*)
                    echo "  sudo dnf install kernel-devel-$(uname -r) kernel-headers-$(uname -r) binder_linux-dkms"
                    ;;
                *)
                    echo "  Install binder_linux-dkms and matching kernel headers for your distribution"
                    ;;
            esac
            echo "  sudo modprobe binder_linux"
            echo "  echo 'binder_linux' | sudo tee /etc/modules-load.d/waydroid.conf"
            read -p "Press Enter to continue..."
            return 1
            ;;
        *) return 1 ;;
    esac
}

# Setup waydroid_script
setup_waydroid_script() {
    log_header "SETTING UP WAYDROID SCRIPT"

    mkdir -p "$TEMP_DIR"

    if [[ -d "$WAYDROID_SCRIPT_DIR" ]]; then
        read -p "Update existing waydroid_script? (y/N): " update
        if [[ "$update" =~ ^[Yy]$ ]]; then
            cd "$WAYDROID_SCRIPT_DIR" && git pull || return 1
        fi
    else
        log_step "Cloning waydroid_script"
        git clone https://github.com/casualsnek/waydroid_script.git "$WAYDROID_SCRIPT_DIR" || return 1
    fi

    if [[ ! -d "${WAYDROID_SCRIPT_DIR}/venv" ]]; then
        log_step "Creating Python virtual environment"
        cd "$WAYDROID_SCRIPT_DIR" && python3 -m venv venv || return 1
    fi

    log_step "Installing Python requirements"
    cd "$WAYDROID_SCRIPT_DIR"
    "${PYTHON_SCRIPT}" -m pip install --upgrade pip || return 1
    "${PYTHON_SCRIPT}" -m pip install -r requirements.txt || return 1

    log_success "waydroid_script setup complete"
}

# Run Python script
run_python_script() {
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        log_warn "Setting up waydroid_script first..."
        setup_waydroid_script || return 1
    fi

    if [[ ! -f "$MAIN_PY" ]]; then
        log_error "waydroid_script not found"
        return 1
    fi

    cd "$WAYDROID_SCRIPT_DIR"
    "${PYTHON_SCRIPT}" "$MAIN_PY" "$@"
}

# Install WayDroid (distribution-agnostic)
install_waydroid() {
    log_header "INSTALLING WAYDROID"

    local distro=$(detect_distro)
    log_info "Detected distribution: $distro"

    # Install dependencies first
    install_dependencies || return 1

    # Check binder
    check_binder_interactive

    # Initialize WayDroid if needed
    if [[ ! -d "/var/lib/waydroid/images" ]]; then
        log_step "Initializing WayDroid"
        waydroid init || return 1
    fi

    # Start service
    log_step "Starting WayDroid container service"
    systemctl enable --now waydroid-container 2>/dev/null || {
        log_warn "Could not enable service automatically"
        echo "You may need to start WayDroid manually:"
        echo "  sudo systemctl start waydroid-container"
    }

    log_success "WayDroid installed successfully"
}

# Install apps menu
install_apps_menu() {
    while true; do
        clear
        log_header "INSTALL APPS"
        echo "1) gapps         - Google Apps"
        echo "2) microg        - MicroG"
        echo "3) libndk        - ARM translation (AMD)"
        echo "4) libhoudini    - ARM translation (Intel)"
        echo "5) magisk        - Root access"
        echo "6) widevine      - DRM L3"
        echo "7) smartdock     - Desktop mode"
        echo "8) fdroidpriv    - FDroid Privileged"
        echo "9) nodataperm    - NoDataPerm hack"
        echo "10) hidestatusbar - Hide status bar"
        echo "11) mitm         - MITM certificate"
        echo "0) Back"
        echo
        read -p "Select apps (space-separated numbers): " selections

        [[ "$selections" == "0" ]] && return 0
        [[ -z "$selections" ]] && continue

        local args=()
        local mitm_cert=""

        for num in $selections; do
            case $num in
                1) args+=("gapps") ;;
                2) args+=("microg") ;;
                3) args+=("libndk") ;;
                4) args+=("libhoudini") ;;
                5) args+=("magisk") ;;
                6) args+=("widevine") ;;
                7) args+=("smartdock") ;;
                8) args+=("fdroidpriv") ;;
                9) args+=("nodataperm") ;;
                10) args+=("hidestatusbar") ;;
                11)
                    read -p "Enter CA certificate path: " mitm_cert
                    ;;
                *) log_warn "Invalid: $num" ;;
            esac
        done

        if [[ -n "$mitm_cert" ]] && [[ -f "$mitm_cert" ]]; then
            [[ ${#args[@]} -gt 0 ]] && run_python_script install "${args[@]}"
            run_python_script install mitm --ca-cert "$mitm_cert"
        elif [[ ${#args[@]} -gt 0 ]]; then
            run_python_script install "${args[@]}"
        fi

        read -p "Press Enter to continue..."
    done
}

# Remove apps menu
remove_apps_menu() {
    while true; do
        clear
        log_header "REMOVE APPS"
        echo "1) gapps"
        echo "2) microg"
        echo "3) libndk"
        echo "4) libhoudini"
        echo "5) magisk"
        echo "6) widevine"
        echo "7) smartdock"
        echo "8) fdroidpriv"
        echo "9) nodataperm"
        echo "10) hidestatusbar"
        echo "11) mitm"
        echo "0) Back"
        echo
        read -p "Select apps (space-separated numbers): " selections

        [[ "$selections" == "0" ]] && return 0
        [[ -z "$selections" ]] && continue

        local args=()
        for num in $selections; do
            case $num in
                1) args+=("gapps") ;;
                2) args+=("microg") ;;
                3) args+=("libndk") ;;
                4) args+=("libhoudini") ;;
                5) args+=("magisk") ;;
                6) args+=("widevine") ;;
                7) args+=("smartdock") ;;
                8) args+=("fdroidpriv") ;;
                9) args+=("nodataperm") ;;
                10) args+=("hidestatusbar") ;;
                11) args+=("mitm") ;;
                *) log_warn "Invalid: $num" ;;
            esac
        done

        [[ ${#args[@]} -gt 0 ]] && run_python_script uninstall "${args[@]}"
        read -p "Press Enter to continue..."
    done
}

# Show help
show_help() {
    clear
    log_header "HELP"
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  install         - Install WayDroid"
    echo "  install-deps    - Install dependencies"
    echo "  setup           - Setup waydroid_script"
    echo "  ui              - Start WayDroid UI"
    echo "  multi           - Start multi-window"
    echo "  start/stop/restart - Container"
    echo "  certified       - Get Play Store ID"
    echo "  install/remove  - Install/remove apps"
    echo "  hack            - Apply hacks"
    echo "  check-binder    - Check/fix binder"
    echo "  clean           - Remove lock files"
    echo ""
    echo "Examples:"
    echo "  sudo $0 install"
    echo "  sudo $0 install gapps microg magisk"
    echo "  sudo $0 ui"
}

# Main menu
interactive_mode() {
    setup_logging

    if [[ -f "$LOCK_FILE" ]]; then
        local age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
        if [[ $age -gt 3600 ]]; then
            rm -f "$LOCK_FILE"
        else
            log_error "Another instance running (lock: $LOCK_FILE)"
            echo "Run 'sudo $0 clean' to remove"
            exit 1
        fi
    fi
    touch "$LOCK_FILE"

    while true; do
        clear
        log_header "WAYDROID MANAGER v2.1.8"

        # Simple status indicators
        local wl_status="${RED}✗${NC}"
        is_wayland_active && wl_status="${GREEN}✓${NC}"

        local binder_status="${RED}✗${NC}"
        is_binder_working && binder_status="${GREEN}✓${NC}"

        local wd_status="${RED}Not Installed${NC}"
        if is_waydroid_installed; then
            if is_waydroid_running; then
                wd_status="${GREEN}Running${NC}"
            else
                wd_status="${YELLOW}Installed${NC}"
            fi
        fi

        local sb_warn=""
        is_secure_boot_enabled && sb_warn="${YELLOW} (Secure Boot ON)${NC}"

        echo -e "${CYAN}System:${NC} $(detect_distro) | $(uname -m) | Kernel: $(uname -r)$sb_warn"
        echo -e "${CYAN}Status:${NC} Wayland [$wl_status] Binder [$binder_status] WayDroid [$wd_status]"
        echo -e "${CYAN}Log:${NC} $LOG_FILE"
        echo "──────────────────────────────────"
        echo "1)  Install WayDroid"
        echo "2)  Install Apps"
        echo "3)  Remove Apps"
        echo "4)  Get Play Store ID"
        echo "5)  Apply Hacks"
        echo "6)  Start WayDroid (Full UI)"
        echo "7)  Start WayDroid (Multi-window)"
        echo "8)  Stop WayDroid"
        echo "9)  Restart WayDroid"
        echo "10) Check/Fix Binder"
        echo "11) Setup/Update waydroid_script"
        echo "12) Install Dependencies"
        echo "13) Help"
        echo "14) Exit"
        echo
        read -p "Select [1-14]: " choice

        case $choice in
            1)  install_waydroid ;;
            2)  install_apps_menu ;;
            3)  remove_apps_menu ;;
            4)  run_python_script certified ;;
            5)
                read -p "Enter hack (nodataperm/hidestatusbar): " hack
                [[ -n "$hack" ]] && run_python_script hack "$hack"
                ;;
            6)
                if check_wayland_interactive && check_binder_interactive; then
                    if [[ -n "${SUDO_USER:-}" ]]; then
                        sudo -u "$ORIGINAL_USER" waydroid show-full-ui &
                    else
                        waydroid show-full-ui &
                    fi
                    log_success "WayDroid UI started"
                fi
                ;;
            7)
                if check_wayland_interactive && check_binder_interactive; then
                    if [[ -n "${SUDO_USER:-}" ]]; then
                        sudo -u "$ORIGINAL_USER" waydroid session start &
                        sleep 2
                        sudo -u "$ORIGINAL_USER" waydroid show-full-ui &
                    else
                        waydroid session start &
                        sleep 2
                        waydroid show-full-ui &
                    fi
                    log_success "WayDroid multi-window started"
                fi
                ;;
            8)  systemctl stop waydroid-container && log_success "Stopped" ;;
            9)  systemctl restart waydroid-container && log_success "Restarted" ;;
            10) check_binder_interactive ;;
            11) setup_waydroid_script ;;
            12) install_dependencies ;;
            13) show_help ;;
            14)
                rm -f "$LOCK_FILE"
                log_info "Goodbye!"
                exit 0
                ;;
            *)  log_error "Invalid option" ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
}

# Main
main() {
    if [[ $# -eq 1 && "$1" == "clean" ]]; then
        rm -f "$LOCK_FILE" 2>/dev/null
        echo "Lock files cleaned"
        exit 0
    fi

    if [[ $# -eq 0 ]]; then
        check_root
        interactive_mode
    else
        case $1 in
            help|--help|-h)  show_help ;;
            install)         check_root; install_waydroid ;;
            install-deps)    check_root; install_dependencies ;;
            setup)           check_root; setup_waydroid_script ;;
            check-binder)    check_root; check_binder_interactive ;;
            ui)              check_root; check_wayland_interactive && check_binder_interactive && waydroid show-full-ui & ;;
            multi)           check_root; check_wayland_interactive && check_binder_interactive && waydroid session start && sleep 2 && waydroid show-full-ui & ;;
            start)           check_root; check_binder_interactive && systemctl start waydroid-container ;;
            stop)            check_root; systemctl stop waydroid-container ;;
            restart)         check_root; systemctl restart waydroid-container ;;
            status)          systemctl status waydroid-container ;;
            certified)       check_root; run_python_script certified ;;
            install-cmd)     check_root; shift; run_python_script install "$@" ;;
            remove|uninstall) check_root; shift; run_python_script uninstall "$@" ;;
            hack)            check_root; shift; run_python_script hack "$@" ;;
            clean)           rm -f "$LOCK_FILE" 2>/dev/null; echo "Lock files cleaned" ;;
            *)               log_error "Unknown command: $1"; show_help; exit 1 ;;
        esac
    fi
}

main "$@"
