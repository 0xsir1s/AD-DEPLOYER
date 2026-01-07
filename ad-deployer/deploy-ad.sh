#!/bin/bash

#===============================================================================
#
#          FILE: deploy-ad.sh
#
#         USAGE: ./deploy-ad.sh [OPTIONS]
#
#   DESCRIPTION: Automated Active Directory Deployment & Hardening Tool.
#                Orchestrates Ansible playbooks to deploy a secure AD environment
#                based on ANSSI recommendations (PA-099).
#
#       VERSION: 2.1.0
#       CREATED: 2025
#       LICENSE: MIT
#
#   REQUIREMENTS: ansible, python3, pywinrm
#
#   REFERENCES:
#     - ANSSI PA-099: https://cyber.gouv.fr/publications/recommandations-pour-ladministration-securisee-des-si-reposant-sur-ad
#
#===============================================================================

# Strict Mode: fail on error, undefined vars, or pipe failures
set -euo pipefail

#===============================================================================
# GLOBAL VARIABLES & PATHS
#===============================================================================

# Terminal Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly PINK='\033[1;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Project Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
readonly INVENTORY_DIR="${ANSIBLE_DIR}/inventory"
readonly PLAYBOOKS_DIR="${ANSIBLE_DIR}/playbooks"
readonly LOGS_DIR="${SCRIPT_DIR}/logs"

# Ansible Inventory File
readonly INVENTORY_FILE="${INVENTORY_DIR}/hosts.yml"

# Defaults
DEFAULT_DOMAIN="lab.local"
DEFAULT_NETBIOS="LAB"
DEFAULT_USERS=10
DEFAULT_ADMIN="vagrant"
DEFAULT_HARDENING="anssi"
DEFAULT_FOREST_MODE="WinThreshold"
DEFAULT_DOMAIN_MODE="WinThreshold"

# Configuration Variables (populated via args or wizard)
DOMAIN_NAME=""
NETBIOS_NAME=""
ADMIN_USER=""
ADMIN_PASSWORD=""
SAFE_MODE_PASSWORD=""
NUM_USERS=0
GROUPS=""
TARGET_HOST=""
HARDENING_LEVEL=""
FOREST_MODE=""
DOMAIN_MODE=""
VERBOSE=0
DRY_RUN=0
SKIP_HARDENING=0

# Version
readonly VERSION="2.1.0"

#===============================================================================
# LOGGING SETUP
#===============================================================================

setup_logging() {
    mkdir -p "${LOGS_DIR}"
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    local log_file="${LOGS_DIR}/deploy-ad-${timestamp}.log"
    local latest_log="${LOGS_DIR}/latest.log"

    # Redirect stdout and stderr to both console and log file
    exec > >(tee -a "${log_file}") 2>&1
    
    # Link latest log
    ln -sf "${log_file}" "${latest_log}" || true
    
    # We do not echo here to keep the banner clean as the first output
}

#===============================================================================
# DISPLAY FUNCTIONS
#===============================================================================

show_banner() {
    echo -e "${PINK}"
    cat << "EOF"
    ___    ____     ____             __                     
   /   |  / __ \   / __ \___  ____  / /___  __  _____  _____
  / /| | / / / /  / / / / _ \/ __ \/ / __ \/ / / / _ \/ ___/
 / ___ |/ /_/ /  / /_/ /  __/ /_/ / / /_/ / /_/ /  __/ /    
/_/  |_/_____/  /_____/\___/ .___/_/\____/\__, /\___/_/     
                          /_/            /____/              
EOF
    echo -e "${PURPLE}    Active Directory Deployment & Hardening Tool${NC}"
    echo -e "${CYAN}    Based on ANSSI Recommendations - v${VERSION}${NC}"
    echo -e "${PINK}    By 0xsir1s${NC}"
    echo -e ""
    echo -e "${BLUE}    [Infrastructure-as-Code]${NC} ${PURPLE}[ANSSI-Tiering]${NC} ${CYAN}[Security-Hardened]${NC}" 
    echo -e "${NC}"
}

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${PINK}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&2; }

log_debug() {
    if [[ ${VERBOSE} -eq 1 ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "\n${BOLD}${PURPLE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${PINK}  $1${NC}"
    echo -e "${BOLD}${PURPLE}══════════════════════════════════════════════════════════════${NC}\n"
}

#===============================================================================
# HELP & USAGE
#===============================================================================

show_help() {
    cat << EOF
${BOLD}NAME${NC}
    $(basename "$0") - Automated ANSSI-hardened Active Directory Deployment

${BOLD}SYNOPSIS${NC}
    $(basename "$0") [OPTIONS]
    $(basename "$0") -t <IP> -p <PASSWORD> -s <SAFE_MODE_PASSWORD> [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Automates the deployment of a secure Active Directory environment following
    ANSSI PA-099 recommendations. Supports Infrastructure-as-Code via Ansible.

${BOLD}REQUIRED OPTIONS (Command Line Mode)${NC}
    -t, --target <IP>        Target Windows Server IP
    -p, --password <PWD>     WinRM Administrative Password
    -s, --safe-mode <PWD>    DSRM Mode Password

${BOLD}CONFIGURATION OPTIONS${NC}
    -d, --domain <FQDN>      AD Domain Name (Default: ${DEFAULT_DOMAIN})
    -n, --netbios <NAME>     NetBIOS Name (Default: Auto)
    -a, --admin <USER>       WinRM Admin User (Default: ${DEFAULT_ADMIN})
    -u, --users <NUM>        Number of test users (Default: ${DEFAULT_USERS})
    -g, --groups <LIST>      Business Groups (comma-separated)
    -H, --hardening <LVL>    Security Level: minimal, standard, anssi, paranoid
                             (Default: ${DEFAULT_HARDENING})

${BOLD}ADVANCED OPTIONS${NC}
    --skip-hardening         Skip security hardening steps
    --dry-run                Generate inventory but do not execute playbooks
    -v, --verbose            Enable verbose output
    --tags <TAGS>            Run specific Ansible tags (comma-separated)

${BOLD}EXAMPLES${NC}
    # Interactive Wizard (No args)
    ./deploy-ad.sh

    # Quick Lab Deployment
    ./deploy-ad.sh -t 192.168.1.10 -p 'vagrant' -s 'S@feMode123!'

EOF
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

command_exists() {
    command -v "$1" &> /dev/null
}

check_prerequisites() {
    log_step "Checking Prerequisites"
    
    local missing_deps=()
    local warnings=()
    
    if ! command_exists ansible; then
        missing_deps+=("ansible")
    else
        log_success "Ansible found"
    fi
    
    if ! command_exists python3; then
        missing_deps+=("python3")
    fi
    
    if command_exists pip3; then
        if pip3 show pywinrm &> /dev/null; then
            log_success "pywinrm installed"
        else
            warnings+=("pywinrm missing - Install: pip3 install pywinrm")
        fi
    else
        warnings+=("pip3 not found")
    fi
    
    if command_exists ansible-galaxy; then
        if ! ansible-galaxy collection list 2>/dev/null | grep -q "microsoft.ad"; then
            warnings+=("microsoft.ad collection missing")
        fi
    fi
    
    for warning in "${warnings[@]:-}"; do
        [[ -n "$warning" ]] && log_warning "$warning"
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing critical dependencies: ${missing_deps[*]}"
        exit 2
    fi
    
    log_success "System ready for deployment"
}

validate_ip() {
    local ip=$1
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    [[ $ip =~ $valid_ip_regex ]]
}

validate_arguments() {
    log_step "Validating Arguments"
    
    if [[ -z "${TARGET_HOST}" ]] || [[ -z "${ADMIN_PASSWORD}" ]] || [[ -z "${SAFE_MODE_PASSWORD}" ]]; then
        log_error "Missing required arguments. Use --help or Interactive Mode."
        exit 1
    fi
    
    if ! validate_ip "${TARGET_HOST}"; then
        log_error "Invalid IP Address: ${TARGET_HOST}"
        exit 1
    fi
    
    if [[ ${#NETBIOS_NAME} -gt 15 ]]; then
        log_warning "NetBIOS name '${NETBIOS_NAME}' exceeds 15 chars, truncated."
        NETBIOS_NAME="${NETBIOS_NAME:0:15}"
    fi
    
    log_success "Configuration validated."
}

#===============================================================================
# SECURITY POLICY HELPERS (ANSSI)
#===============================================================================

get_password_min_length() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "8" ;;
        standard) echo "12" ;;
        anssi)    echo "14" ;;
        paranoid) echo "16" ;;
    esac
}

get_password_max_age() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "90" ;;
        standard) echo "60" ;;
        anssi)    echo "90" ;;
        paranoid) echo "30" ;;
    esac
}

get_password_history() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "5" ;;
        standard) echo "12" ;;
        anssi)    echo "24" ;;
        paranoid) echo "24" ;;
    esac
}

get_lockout_threshold() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "10" ;;
        standard) echo "5" ;;
        anssi)    echo "5" ;;
        paranoid) echo "3" ;;
    esac
}

get_smb_signing() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "false" ;;
        *)        echo "true" ;;
    esac
}

get_lsass_protection() {
    case "${HARDENING_LEVEL}" in
        minimal)  echo "false" ;;
        *)        echo "true" ;;
    esac
}

#===============================================================================
# INTERACTIVE WIZARD
#===============================================================================

interactive_wizard() {
    echo -e "\n${BOLD}${CYAN}» Starting Interactive Configuration Wizard${NC}"
    
    # Target IP
    while [[ -z "${TARGET_HOST}" ]]; do
        echo -ne "Target IP Address [default: 127.0.0.1]: "
        read -r input
        TARGET_HOST="${input:-127.0.0.1}"
        if ! validate_ip "${TARGET_HOST}"; then
            echo -e "${RED}Invalid IP. Please try again.${NC}"
            TARGET_HOST=""
        fi
    done

    # Domain Name
    echo -ne "Domain Name (FQDN) [default: ${DEFAULT_DOMAIN}]: "
    read -r input
    DOMAIN_NAME="${input:-${DEFAULT_DOMAIN}}"
    
    # NetBIOS
    local default_netbios
    default_netbios=$(echo "${DOMAIN_NAME}" | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
    echo -ne "NetBIOS Name [default: ${default_netbios}]: "
    read -r input
    NETBIOS_NAME="${input:-${default_netbios}}"
    NETBIOS_NAME="${NETBIOS_NAME:0:15}"

    # WinRM Credentials
    echo -ne "WinRM Admin User [default: ${DEFAULT_ADMIN}]: "
    read -r input
    ADMIN_USER="${input:-${DEFAULT_ADMIN}}"
    
    echo -ne "WinRM Admin Password: "
    read -rs ADMIN_PASSWORD
    echo ""
    
    echo -ne "DSRM (Safe Mode) Password: "
    read -rs SAFE_MODE_PASSWORD
    echo ""

    # Hardening Level
    echo -e "\nSelect Hardening Level:"
    echo "1) minimal (Lab/Dev)"
    echo "2) standard (Corporate)"
    echo "3) anssi (Production - Recommended)"
    echo "4) paranoid (High Security)"
    echo -ne "Choice [1-4] (default: 3): "
    read -r choice
    case $choice in
        1) HARDENING_LEVEL="minimal" ;;
        2) HARDENING_LEVEL="standard" ;;
        4) HARDENING_LEVEL="paranoid" ;;
        *) HARDENING_LEVEL="anssi" ;;
    esac

    # Defaults for others
    NUM_USERS=${DEFAULT_USERS}
    FOREST_MODE=${DEFAULT_FOREST_MODE}
    DOMAIN_MODE=${DEFAULT_DOMAIN_MODE}
    
    log_success "Interactive setup complete."
}

#===============================================================================
# INVENTORY GENERATION
#===============================================================================

generate_inventory() {
    log_info "Generating Ansible inventory..."
    mkdir -p "${INVENTORY_DIR}"
    
    # Configure Groups
    local groups_yaml=""
    if [[ -n "${GROUPS}" ]]; then
        groups_yaml="ad_groups:"
        IFS=',' read -ra group_array <<< "${GROUPS}"
        for group in "${group_array[@]}"; do
            group=$(echo "$group" | xargs)
            groups_yaml+=$'\n      - name: "'"${group}"'"\n        scope: global\n        category: security'
        done
    else
        groups_yaml="ad_groups: []"
    fi
    
    # Configure Users
    local users_yaml=""
    if [[ ${NUM_USERS} -gt 0 ]]; then
        users_yaml="ad_users:"
        for i in $(seq 1 "${NUM_USERS}"); do
            local username="user$(printf '%03d' $i)"
            users_yaml+=$'\n      - username: "'"${username}"'"\n        firstname: "User"\n        lastname: "Number'"${i}"'"\n        password: "U$er'"${i}"'P@ss!"\n        groups:\n          - "Domain Users"'
        done
    else
        users_yaml="ad_users: []"
    fi
    
    # Write Inventory
    cat > "${INVENTORY_FILE}" << EOF
---
# =============================================================================
# AUTO-GENERATED INVENTORY - DO NOT EDIT MANUALLY
# Generated by ad-deployer v${VERSION}
# =============================================================================

all:
  children:
    domain_controllers:
      hosts:
        dc01:
          ansible_host: ${TARGET_HOST}
          
  vars:
    # --- Connection ---
    ansible_user: ${ADMIN_USER}
    ansible_password: "${ADMIN_PASSWORD}"
    ansible_connection: winrm
    ansible_winrm_transport: ntlm
    ansible_winrm_server_cert_validation: ignore
    ansible_port: 5985
    
    # --- Domain Config ---
    ad_domain:
      name: "${DOMAIN_NAME}"
      netbios: "${NETBIOS_NAME}"
      forest_mode: "${FOREST_MODE}"
      domain_mode: "${DOMAIN_MODE}"
      safe_mode_password: "${SAFE_MODE_PASSWORD}"
    
    # Legacy vars for compatibility
    domain_name: "${DOMAIN_NAME}"
    domain_netbios_name: "${NETBIOS_NAME}"
    safe_mode_password: "${SAFE_MODE_PASSWORD}"
    forest_mode: "${FOREST_MODE}"
    domain_mode: "${DOMAIN_MODE}"
    
    # --- Password Policy (${HARDENING_LEVEL}) ---
    password_policy:
      min_length: $(get_password_min_length)
      complexity_enabled: true
      max_age_days: $(get_password_max_age)
      min_age_days: 1
      history_count: $(get_password_history)
      lockout_threshold: $(get_lockout_threshold)
      lockout_duration_minutes: 30
      lockout_observation_minutes: 30
    
    # --- ANSSI Hardening ---
    hardening_level: "${HARDENING_LEVEL}"
    anssi_security:
      disable_ntlmv1: true
      disable_lm_hash: true
      disable_anonymous_enumeration: true
      smb_signing_required: $(get_smb_signing)
      lsass_protection_enabled: $(get_lsass_protection)
      audit_policy_enabled: true
      tiering_enabled: true
    
    # --- Resources ---
    ${groups_yaml}
    ${users_yaml}
EOF
    log_success "Inventory generated at ${INVENTORY_FILE}"
}

#===============================================================================
# DEPLOYMENT EXECUTION
#===============================================================================

wait_for_winrm() {
    log_step "Waiting for WinRM Availability"
    log_info "Attempting to connect to ${TARGET_HOST}:5985..."

    if [[ ${DRY_RUN} -eq 1 ]]; then
        log_warning "[DRY-RUN] Skipping connectivity check."
        return 0
    fi

    local max_retries=30
    local count=0
    local delay=5

    while [[ $count -lt $max_retries ]]; do
        # We use a simple TCP check first
        if timeout 2 bash -c "echo > /dev/tcp/${TARGET_HOST}/5985" 2>/dev/null; then
            log_success "Port 5985 Open!"
            # Now check actual WinRM auth via Ansible
            log_info "Verifying Ansible Authentication..."
            if ansible -i "${INVENTORY_FILE}" dc01 -m win_ping &>/dev/null; then
                log_success "WinRM Authentication Successful!"
                return 0
            else
                log_warning "Port open but Auth failed. Windows still starting? Retrying..."
            fi
        else
            echo -ne "${YELLOW}.${NC}"
        fi
        
        sleep $delay
        ((count++))
    done

    log_error "Connection timed out after $((max_retries * delay)) seconds."
    exit 3
}

run_playbook() {
    local playbook=$1
    local description=$2
    
    log_info "Task: ${description}"
    
    if [[ ${DRY_RUN} -eq 1 ]]; then
        return 0
    fi
    
    local ansible_opts="-i ${INVENTORY_FILE}"
    [[ ${VERBOSE} -eq 1 ]] && ansible_opts+=" -v"
    
    if ansible-playbook ${ansible_opts} "${playbook}"; then
        return 0
    else
        log_error "Playbook Failed: ${playbook}"
        return 1
    fi
}

run_deployment() {
    log_step "Starting Deployment"
    
    local start_time
    start_time=$(date +%s)
    local failed=0
    
    # Sequential Playbook Execution
    local playbooks=(
        "01-bootstrap.yml:System Prerequisites & Role Installation"
        "02-forest.yml:Active Directory Forest Provisioning"
        "03-structure.yml:OU Structure & Tiering Model"
        "04-access.yml:Security Groups & Delegation"
        "05-identities.yml:User Identity Provisioning"
        "06-hardening.yml:ANSSI Security Hardening"
        "07-policies.yml:Group Policy Objects (GPOs)"
    )

    for entry in "${playbooks[@]}"; do
        IFS=":" read -r file desc <<< "$entry"
        local path="${PLAYBOOKS_DIR}/${file}"
        
        if [[ -f "$path" ]]; then
            # Skip hardening if requested
            if [[ "$file" == "06-hardening.yml" ]] && [[ ${SKIP_HARDENING} -eq 1 ]]; then
                log_warning "Skipping Hardening (--skip-hardening)"
                continue
            fi
            
            run_playbook "$path" "$desc" || failed=1
            [[ $failed -eq 1 ]] && { log_error "Critical Failure in $file. Stopping."; exit 4; }
        else
            log_error "Playbook not found: $path"
            exit 5
        fi
    done
    
    local end_time
    end_time=$(date +%s)
    log_success "Deployment finished in $((end_time - start_time)) seconds."
}

#===============================================================================
# MAIN ENTRY
#===============================================================================

parse_arguments() {
    # If no args, trigger interactive wizard
    if [[ $# -eq 0 ]]; then
        interactive_wizard
        return
    fi

    # Standard Argument Parsing
    DOMAIN_NAME="${DEFAULT_DOMAIN}"
    NETBIOS_NAME="${DEFAULT_NETBIOS}"
    ADMIN_USER="${DEFAULT_ADMIN}"
    NUM_USERS="${DEFAULT_USERS}"
    HARDENING_LEVEL="${DEFAULT_HARDENING}"
    FOREST_MODE="${DEFAULT_FOREST_MODE}"
    DOMAIN_MODE="${DEFAULT_DOMAIN_MODE}"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target) TARGET_HOST="$2"; shift 2 ;;
            -d|--domain) DOMAIN_NAME="$2"; shift 2 ;;
            -n|--netbios) NETBIOS_NAME="$2"; shift 2 ;;
            -a|--admin) ADMIN_USER="$2"; shift 2 ;;
            -p|--password) ADMIN_PASSWORD="$2"; shift 2 ;;
            -s|--safe-mode) SAFE_MODE_PASSWORD="$2"; shift 2 ;;
            -u|--users) NUM_USERS="$2"; shift 2 ;;
            -g|--groups) GROUPS="$2"; shift 2 ;;
            -H|--hardening) HARDENING_LEVEL="$2"; shift 2 ;;
            --skip-hardening) SKIP_HARDENING=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    
    # Auto-generate NetBIOS if needed (and not running wizard)
    if [[ "${NETBIOS_NAME}" == "${DEFAULT_NETBIOS}" ]]; then
         NETBIOS_NAME=$(echo "${DOMAIN_NAME}" | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
         NETBIOS_NAME="${NETBIOS_NAME:0:15}"
    fi
}

main() {
    # 1. Setup Logging (First to capture everything)
    setup_logging
    
    # 2. Show Banner (Immediate feedback, now Cyberpunk styled)
    show_banner
    
    # 3. Parse Args (or trigger Wizard)
    parse_arguments "$@"
    
    # 4. Start Checks
    check_prerequisites
    validate_arguments
    
    # 5. Execute
    generate_inventory
    wait_for_winrm
    run_deployment
    
    echo -e "\n${GREEN}${BOLD}» DEPLOYMENT COMPLETE!${NC}"
    echo -e "  Domain:   ${DOMAIN_NAME} (${TARGET_HOST})"
    echo -e "  Admin:    ${NETBIOS_NAME}\\Administrator"
    echo -e "  Security: ${HARDENING_LEVEL}"
    echo -e "  Log File: ${LOGS_DIR}/latest.log"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
