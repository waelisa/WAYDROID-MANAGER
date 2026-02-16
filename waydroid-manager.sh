#!/usr/bin/env bash

# WayDroid Management Script - Now with actual Python script integration

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

# Logging functions
log_info() { echo -e "${GREEN}${INFO} [INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}${CHECK_MARK} [SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}${CROSS_MARK} [ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}${WARNING} [WARN]${NC} $1"; }
log_step() { echo -e "${CYAN}${GEAR} [STEP]${NC} $1"; }
log_header() { 
    echo -e "\n${PURPLE}${BOLD}════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}  $1${NC}"
    echo -e "${PURPLE}${BOLD}════════════════════════════════════════════${NC}\n"
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

# Install required dependencies based on distribution
install_dependencies() {
    local distro=$(detect_distro)
    log_step "Installing dependencies for $distro"
    
    case $distro in
        arch|manjaro|endeavouros)
            pacman -S --noconfirm lzip git python python-pip python-virtualenv
            ;;
        debian|ubuntu|linuxmint|pop)
            apt update
            apt install -y lzip git python3 python3-pip python3-venv
            ;;
        fedora|rhel|centos|rocky)
            dnf install -y lzip git python3 python3-pip python3-virtualenv
            ;;
        opensuse*)
            zypper install -y lzip git python3 python3-pip python3-virtualenv
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

# Clone and setup waydroid_script
setup_waydroid_script() {
    log_header "SETTING UP WAYDROID SCRIPT"
    
    # Check if already exists
    if [[ -d "$WAYDROID_SCRIPT_DIR" ]]; then
        log_info "waydroid_script directory already exists"
        echo -n "Update it? (y/N): "
        read -r update
        if [[ "$update" =~ ^[Yy]$ ]]; then
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

# Run the Python script with arguments
run_python_script() {
    if [[ ! -f "$MAIN_PY" ]]; then
        log_error "waydroid_script not found. Please run option 1 first to set it up."
        return 1
    fi
    
    log_step "Running: ${PYTHON_SCRIPT} ${MAIN_PY} $*"
    cd "$WAYDROID_SCRIPT_DIR"
    "${PYTHON_SCRIPT}" "$MAIN_PY" "$@"
}

# Install WayDroid on Arch Linux
install_arch() {
    log_header "INSTALLING WAYDROID ON ARCH LINUX"
    
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
    
    log_step "Installing WayDroid and dependencies"
    pacman -S --noconfirm waydroid binder_linux-dkms lzip git python python-pip python-virtualenv
    
    # Check binder module
    log_step "Checking binder module"
    if ! lsmod | grep -q "binder"; then
        log_warn "Binder module not loaded"
        modprobe binder_linux 2>/dev/null || modprobe binder-linux 2>/dev/null || {
            log_error "Failed to load binder module"
            echo "You may need to reboot"
        }
    else
        log_success "Binder module is loaded"
    fi
    
    # Initialize WayDroid if needed
    if [[ ! -d "/var/lib/waydroid/images" ]]; then
        log_step "Initializing WayDroid"
        waydroid init
    fi
    
    # Start service
    systemctl enable --now waydroid-container
    
    log_success "WayDroid installed successfully"
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
    echo -e "    # Install multiple components"
    echo -e "    sudo $0 install gapps microg magisk"
    echo
    echo -e "    # Install ARM translation for Intel CPU"
    echo -e "    sudo $0 install libhoudini"
    echo
    echo -e "    # Install MITM certificate"
    echo -e "    sudo $0 install mitm --ca-cert /path/to/cert.pem"
    echo
    echo -e "    # Remove a hack"
    echo -e "    sudo $0 remove nodataperm"
    echo
    echo -e "    # Get Google certification ID"
    echo -e "    sudo $0 certified"
    echo
    echo -e "    # Check status"
    echo -e "    sudo $0 status"
    echo
    echo -e "${YELLOW}${BOLD}NOTE: Most commands require root privileges (sudo)${NC}"
}

# Main menu
interactive_mode() {
    # Check if waydroid_script is set up
    if [[ ! -f "$MAIN_PY" ]]; then
        log_warn "waydroid_script not found. Please set it up first."
        echo
        echo "1) Install dependencies and setup waydroid_script"
        echo "2) Exit"
        echo
        echo -n "Select [1-2]: "
        read -r choice
        case $choice in
            1)
                install_dependencies
                setup_waydroid_script
                ;;
            *)
                exit 0
                ;;
        esac
    fi
    
    while true; do
        clear
        log_header "WAYDROID MANAGER"
        echo -e "${CYAN}System:${NC} $(detect_distro) | $(get_host_arch)"
        echo -e "${CYAN}Waydroid Script:${NC} $([[ -f "$MAIN_PY" ]] && echo "${GREEN}Installed${NC}" || echo "${RED}Not installed${NC}")"
        echo
        
        echo "1) Install WayDroid on Arch Linux"
        echo "2) Install Apps (via waydroid_script)"
        echo "3) Remove Apps (via waydroid_script)"
        echo "4) Get Android ID (Play Store Certification)"
        echo "5) Apply Hacks"
        echo "6) Start WayDroid"
        echo "7) Stop WayDroid"
        echo "8) Restart WayDroid"
        echo "9) Show Status"
        echo "10) Update waydroid_script"
        echo "11) Help"
        echo "12) Exit"
        echo
        echo -n "Select [1-12]: "
        
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
                run_python_script certified
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
                systemctl start waydroid-container
                log_success "WayDroid started"
                read -p "Press Enter to continue..."
                ;;
            7) 
                systemctl stop waydroid-container
                log_success "WayDroid stopped"
                read -p "Press Enter to continue..."
                ;;
            8) 
                systemctl restart waydroid-container
                log_success "WayDroid restarted"
                read -p "Press Enter to continue..."
                ;;
            9) 
                systemctl status waydroid-container
                read -p "Press Enter to continue..."
                ;;
            10) 
                setup_waydroid_script
                read -p "Press Enter to continue..."
                ;;
            11) 
                show_help
                read -p "Press Enter to continue..."
                ;;
            12) 
                log_info "Goodbye!"
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
    if [[ $# -eq 0 ]]; then
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
                    certified) shift; run_python_script certified ;;
                    start) shift; systemctl start waydroid-container ;;
                    stop) shift; systemctl stop waydroid-container ;;
                    restart) shift; systemctl restart waydroid-container ;;
                    status) shift; systemctl status waydroid-container ;;
                esac
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
