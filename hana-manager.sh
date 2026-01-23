#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  HANA Cloud Instance Manager                                             ║
# ║  Dynamic subaccount selection with Start/Stop functionality              ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# ============================================================================
# Colors and Formatting
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ============================================================================
# Global Variables
# ============================================================================
declare -a SUBACCOUNT_IDS=()
declare -a SUBACCOUNT_NAMES=()
declare -a INSTANCE_IDS=()
declare -a INSTANCE_NAMES=()
declare -a INSTANCE_TYPES=()

SELECTED_SUBACCOUNT_ID=""
SELECTED_SUBACCOUNT_NAME=""
SELECTED_INSTANCE_ID=""
SELECTED_INSTANCE_NAME=""

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}                                                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}   ${WHITE}${BOLD}HANA Cloud Instance Manager${NC}                                            ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}   ${DIM}SAP BTP Trial/Free Tier - Start/Stop Management${NC}                       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}                                                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}${BOLD}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_subsection() {
    echo ""
    echo -e "${GRAY}┌──────────────────────────────────────────────────────────────────────────┐${NC}"
    printf "${GRAY}│${NC} ${WHITE}%-72s${NC} ${GRAY}│${NC}\n" "$1"
    echo -e "${GRAY}└──────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

print_step() {
    printf "  ${CYAN}●${NC}  %-50s" "$1"
}

print_action() {
    printf "  ${MAGENTA}⟳${NC}  %-50s" "$1"
}

print_ok() {
    echo -e "${GREEN}✓ Done${NC}"
}

print_fail() {
    echo -e "${RED}✗ Failed${NC}"
}

print_detail() {
    echo -e "      ${DIM}$1${NC}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " ${CYAN}%c${NC}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    printf "   \b\b\b"
}

# ============================================================================
# BTP CLI Functions
# ============================================================================

check_btp_cli() {
    if ! command -v btp &> /dev/null; then
        print_error "BTP CLI is not installed!"
        echo ""
        echo -e "  ${YELLOW}Install from:${NC} ${CYAN}https://tools.hana.ondemand.com/#cloud-btpcli${NC}"
        exit 1
    fi
    
    local version=$(btp --version 2>/dev/null | head -1)
    print_info "BTP CLI: $version"
}

check_btp_login() {
    print_step "Checking BTP login status..."
    
    if echo "" | btp target 2>&1 | grep -q "subaccount\|global account"; then
        print_ok
        return 0
    else
        print_fail
        return 1
    fi
}

btp_login() {
    print_section "BTP Authentication"
    
    echo -e "${WHITE}  Choose authentication method:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} SSO (Single Sign-On) - Opens browser"
    echo -e "  ${CYAN}2)${NC} Username & Password"
    echo ""
    read -p "  Select option [1-2]: " auth_choice
    
    case $auth_choice in
        1)
            print_action "Opening browser for SSO login..."
            echo ""
            btp login --sso
            ;;
        2)
            read -p "  Enter BTP Username: " username
            read -s -p "  Enter Password: " password
            echo ""
            btp login --user "$username" --password "$password"
            ;;
        *)
            print_warning "Invalid option. Using SSO by default."
            btp login --sso
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        print_success "Successfully logged in to BTP!"
        return 0
    else
        print_error "Login failed!"
        exit 1
    fi
}

# ============================================================================
# Subaccount Functions
# ============================================================================

fetch_subaccounts() {
    print_section "Subaccount Selection"
    
    print_step "Fetching available subaccounts..."
    
    SUBACCOUNT_IDS=()
    SUBACCOUNT_NAMES=()
    
    # Get subaccounts list
    local output
    output=$(btp list accounts/subaccount 2>&1)
    
    if echo "$output" | grep -q "error\|Error\|login"; then
        print_fail
        print_error "Failed to fetch subaccounts"
        return 1
    fi
    
    print_ok
    
    # Parse each line that STARTS with a UUID (these are the actual subaccount data lines)
    # Format: <uuid>   <display-name>   <subdomain>   <region>   ...
    # Use grep to get only lines starting with UUID pattern
    
    while IFS= read -r line; do
        # Extract UUID from beginning of line
        local id=$(echo "$line" | grep -oE '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')
        
        if [ -n "$id" ]; then
            # Remove the UUID and leading/trailing whitespace
            local rest=$(echo "$line" | sed "s/^$id[[:space:]]*//")
            
            # Get display name - first column, fields separated by multiple spaces
            # The display name might have a space (like "trail new")
            local name=$(echo "$rest" | awk -F'   +' '{print $1}' | xargs)
            
            # If no name, try simpler parsing
            if [ -z "$name" ]; then
                name=$(echo "$rest" | awk '{print $1}')
            fi
            
            if [ -n "$name" ]; then
                SUBACCOUNT_IDS+=("$id")
                SUBACCOUNT_NAMES+=("$name")
            fi
        fi
    done <<< "$output"
    
    if [ ${#SUBACCOUNT_IDS[@]} -eq 0 ]; then
        # Fallback: try to get from current target
        local target_output=$(echo "" | btp target 2>&1)
        local sa_id=$(echo "$target_output" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
        local sa_name=$(echo "$target_output" | grep -oE '└─ [^(]+' | sed 's/└─ //' | xargs)
        
        if [ -n "$sa_id" ]; then
            SUBACCOUNT_IDS+=("$sa_id")
            SUBACCOUNT_NAMES+=("${sa_name:-Current Subaccount}")
        fi
    fi
    
    if [ ${#SUBACCOUNT_IDS[@]} -eq 0 ]; then
        print_error "No subaccounts found!"
        return 1
    fi
    
    print_info "Found ${#SUBACCOUNT_IDS[@]} subaccount(s)"
    return 0
}

select_subaccount() {
    echo ""
    echo -e "${WHITE}  Available Subaccounts:${NC}"
    echo ""
    printf "  ${DIM}%-4s %-30s %-40s${NC}\n" "#" "NAME" "ID"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────${NC}"
    
    for i in "${!SUBACCOUNT_IDS[@]}"; do
        local num=$((i+1))
        printf "  ${CYAN}%-4s${NC} ${WHITE}%-30s${NC} ${DIM}%-40s${NC}\n" \
            "$num)" "${SUBACCOUNT_NAMES[$i]:0:28}" "${SUBACCOUNT_IDS[$i]}"
    done
    
    echo ""
    read -p "  Select subaccount [1-${#SUBACCOUNT_IDS[@]}]: " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SUBACCOUNT_IDS[@]} ]; then
        print_error "Invalid selection!"
        return 1
    fi
    
    SELECTED_SUBACCOUNT_ID="${SUBACCOUNT_IDS[$((choice-1))]}"
    SELECTED_SUBACCOUNT_NAME="${SUBACCOUNT_NAMES[$((choice-1))]}"
    
    echo ""
    print_success "Selected: ${SELECTED_SUBACCOUNT_NAME}"
    print_detail "ID: $SELECTED_SUBACCOUNT_ID"
    return 0
}

# ============================================================================
# HANA Instance Functions
# ============================================================================

fetch_hana_instances() {
    print_section "HANA Cloud Instances"
    
    print_step "Fetching HANA instances..."
    
    INSTANCE_IDS=()
    INSTANCE_NAMES=()
    INSTANCE_TYPES=()
    
    local output
    output=$(btp list services/instance --subaccount "$SELECTED_SUBACCOUNT_ID" 2>&1)
    
    if echo "$output" | grep -q "error\|Error"; then
        print_fail
        return 1
    fi
    
    print_ok
    
    print_step "Identifying HANA Cloud databases..."
    
    # The reliable way to identify HANA Cloud databases is to check for 
    # dashboard_url containing "hanacloud.ondemand.com"
    # This filters out HDI containers, xsuaa, destination, html5 services etc.
    
    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Skip header and empty lines
        if [ $line_num -le 2 ] || [ -z "$line" ]; then
            continue
        fi
        
        # Skip footer
        if echo "$line" | grep -q "entries\|OK"; then
            continue
        fi
        
        # Extract fields
        local name=$(echo "$line" | awk '{print $1}')
        local id=$(echo "$line" | awk '{print $2}')
        
        # Skip if not a valid UUID
        if ! [[ "$id" =~ ^[a-f0-9-]{36}$ ]]; then
            continue
        fi
        
        # Skip known non-HANA service names
        if echo "$name" | grep -qiE 'xsuaa|destination|html5|auditlog|connectivity|logging|credstore'; then
            continue
        fi
        
        # Skip HDI containers (names ending with -hana or starting with UUID)
        if echo "$name" | grep -qiE '\-hana$|^[0-9A-F]{8}-'; then
            continue
        fi
        
        # Check if this is an actual HANA Cloud database by looking for dashboard_url
        local details
        details=$(btp get services/instance --id "$id" --subaccount "$SELECTED_SUBACCOUNT_ID" 2>/dev/null)
        
        if echo "$details" | grep -qi "hanacloud.ondemand.com\|hana-tooling"; then
            INSTANCE_IDS+=("$id")
            INSTANCE_NAMES+=("$name")
            INSTANCE_TYPES+=("HANA Database")
        fi
    done <<< "$output"
    
    print_ok
    
    if [ ${#INSTANCE_IDS[@]} -eq 0 ]; then
        print_warning "No HANA Cloud database instances found"
        print_detail "Only actual HANA Cloud databases can be started/stopped"
        return 1
    fi
    
    print_info "Found ${#INSTANCE_IDS[@]} HANA Cloud database(s)"
    return 0
}

select_hana_instance() {
    echo ""
    echo -e "${WHITE}  Available HANA Instances:${NC}"
    echo ""
    printf "  ${DIM}%-4s %-35s %-15s${NC}\n" "#" "NAME" "TYPE"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────${NC}"
    
    for i in "${!INSTANCE_IDS[@]}"; do
        local num=$((i+1))
        local type_color="${CYAN}"
        [ "${INSTANCE_TYPES[$i]}" == "HDI Container" ] && type_color="${YELLOW}"
        
        printf "  ${CYAN}%-4s${NC} ${WHITE}%-35s${NC} ${type_color}%-15s${NC}\n" \
            "$num)" "${INSTANCE_NAMES[$i]:0:33}" "${INSTANCE_TYPES[$i]}"
    done
    
    echo ""
    read -p "  Select HANA instance [1-${#INSTANCE_IDS[@]}]: " choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#INSTANCE_IDS[@]} ]; then
        print_error "Invalid selection!"
        return 1
    fi
    
    SELECTED_INSTANCE_ID="${INSTANCE_IDS[$((choice-1))]}"
    SELECTED_INSTANCE_NAME="${INSTANCE_NAMES[$((choice-1))]}"
    
    echo ""
    print_success "Selected: ${SELECTED_INSTANCE_NAME}"
    return 0
}

# ============================================================================
# Instance Status & Actions
# ============================================================================

get_instance_status() {
    local output
    output=$(btp get services/instance --id "$SELECTED_INSTANCE_ID" --subaccount "$SELECTED_SUBACCOUNT_ID" 2>&1)
    
    # Get parameters to check serviceStopped status
    local params
    params=$(btp get services/instance --id "$SELECTED_INSTANCE_ID" --subaccount "$SELECTED_SUBACCOUNT_ID" --show-parameters 2>&1)
    
    # Extract key fields
    local state=$(echo "$output" | grep "  state:" | head -1 | awk '{print $2}')
    local description=$(echo "$output" | grep "  description:" | head -1 | sed 's/.*description: //')
    local ready=$(echo "$output" | grep "^ready:" | awk '{print $2}')
    local usable=$(echo "$output" | grep "^usable:" | awk '{print $2}')
    local dashboard=$(echo "$output" | grep "^dashboard_url:" | awk '{print $2}')
    local license=$(echo "$output" | grep "license_type" | awk '{print $2}')
    local updated=$(echo "$output" | grep "^updated_at:" | awk '{print $2}')
    
    # Check serviceStopped parameter - this is the reliable way to check status
    local service_stopped=$(echo "$params" | grep "serviceStopped:" | awk '{print $2}')
    
    # Determine running status from serviceStopped parameter
    local is_running="unknown"
    local status_color="${YELLOW}"
    local status_text="UNKNOWN"
    
    if [ "$service_stopped" == "true" ]; then
        is_running="false"
        status_color="${RED}"
        status_text="STOPPED"
    elif [ "$service_stopped" == "false" ]; then
        is_running="true"
        status_color="${GREEN}"
        status_text="RUNNING"
    elif [ "$state" == "in progress" ]; then
        status_color="${YELLOW}"
        status_text="IN PROGRESS"
    fi
    
    print_subsection "Instance Status: $SELECTED_INSTANCE_NAME"
    
    echo -e "  ${DIM}Instance ID:${NC}    ${CYAN}$SELECTED_INSTANCE_ID${NC}"
    echo -e "  ${DIM}Status:${NC}         ${status_color}${BOLD}$status_text${NC}"
    echo -e "  ${DIM}State:${NC}          ${state:-unknown}"
    echo -e "  ${DIM}Description:${NC}    ${description:-unknown}"
    echo -e "  ${DIM}Ready:${NC}          ${ready:-unknown}"
    echo -e "  ${DIM}Usable:${NC}         ${usable:-unknown}"
    echo -e "  ${DIM}License:${NC}        ${license:-unknown}"
    echo -e "  ${DIM}Last Updated:${NC}   ${updated:-unknown}"
    
    if [ -n "$dashboard" ]; then
        echo ""
        echo -e "  ${DIM}Dashboard URL:${NC}"
        echo -e "  ${CYAN}$dashboard${NC}"
    fi
    
    # Return status for use
    if [ "$is_running" == "true" ]; then
        return 0  # Running
    else
        return 1  # Stopped or unknown
    fi
}

start_instance() {
    print_subsection "Starting HANA Instance"
    
    print_warning "This will start the HANA Cloud instance."
    echo -e "  ${DIM}Startup typically takes 5-10 minutes.${NC}"
    echo ""
    
    read -p "  Confirm start? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled."
        return 0
    fi
    
    echo ""
    print_action "Sending start command..."
    
    local result
    result=$(btp update services/instance --id "$SELECTED_INSTANCE_ID" --subaccount "$SELECTED_SUBACCOUNT_ID" \
        --parameters '{"data":{"serviceStopped":false}}' 2>&1)
    
    if echo "$result" | grep -q "OK\|Use 'btp get"; then
        print_ok
        echo ""
        print_success "Start command sent successfully!"
        echo ""
        print_info "The instance is now starting. This typically takes 5-10 minutes."
        echo ""
        
        read -p "  Monitor startup progress? [y/N]: " monitor
        
        if [[ "$monitor" =~ ^[Yy]$ ]]; then
            monitor_startup
        fi
        
        return 0
    else
        print_fail
        echo ""
        print_error "Failed to start instance"
        print_detail "$result"
        return 1
    fi
}

stop_instance() {
    print_subsection "Stopping HANA Instance"
    
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${WHITE}${BOLD}⚠ WARNING: STOPPING HANA INSTANCE${NC}                                       ${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}║${NC}  This will stop the HANA Cloud database.                                ${RED}║${NC}"
    echo -e "${RED}║${NC}  All connections will be terminated.                                    ${RED}║${NC}"
    echo -e "${RED}║${NC}  Applications using this database will fail.                            ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Type 'STOP' to confirm: " confirm
    
    if [ "$confirm" != "STOP" ]; then
        print_info "Operation cancelled."
        return 0
    fi
    
    echo ""
    print_action "Sending stop command..."
    
    local result
    result=$(btp update services/instance --id "$SELECTED_INSTANCE_ID" --subaccount "$SELECTED_SUBACCOUNT_ID" \
        --parameters '{"data":{"serviceStopped":true}}' 2>&1)
    
    if echo "$result" | grep -q "OK\|Use 'btp get"; then
        print_ok
        echo ""
        print_success "Stop command sent successfully!"
        echo ""
        print_warning "The instance is now stopping."
        return 0
    else
        print_fail
        echo ""
        print_error "Failed to stop instance"
        print_detail "$result"
        return 1
    fi
}

monitor_startup() {
    print_subsection "Monitoring Startup Progress"
    
    local max_attempts=30  # 5 minutes with 10-second intervals
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        
        local output
        output=$(btp get services/instance --id "$SELECTED_INSTANCE_ID" --subaccount "$SELECTED_SUBACCOUNT_ID" 2>/dev/null)
        
        local state=$(echo "$output" | grep "  state:" | head -1 | awk '{print $2}')
        local description=$(echo "$output" | grep "  description:" | head -1 | sed 's/.*description: //')
        
        printf "\r  ${CYAN}⏳${NC} [%2d/%d] State: %-15s Description: %-40s" \
            "$attempt" "$max_attempts" "${state:-...}" "${description:0:38}"
        
        if echo "$description" | grep -qi "ready\|running" && [ "$state" == "succeeded" ]; then
            echo ""
            echo ""
            print_success "Instance is now RUNNING!"
            return 0
        fi
        
        sleep 10
    done
    
    echo ""
    echo ""
    print_warning "Monitoring timeout. Please check HANA Cloud Central."
    return 1
}

# ============================================================================
# Main Menu
# ============================================================================

show_main_menu() {
    print_section "Actions Menu"
    
    echo -e "${WHITE}  Current Selection:${NC}"
    echo -e "  ${DIM}• Subaccount:${NC} ${CYAN}$SELECTED_SUBACCOUNT_NAME${NC}"
    echo -e "  ${DIM}• Instance:${NC}   ${CYAN}$SELECTED_INSTANCE_NAME${NC}"
    echo ""
    echo -e "${WHITE}  What would you like to do?${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Check instance status"
    echo -e "  ${GREEN}2)${NC} ${GREEN}Start${NC} instance"
    echo -e "  ${RED}3)${NC} ${RED}Stop${NC} instance"
    echo -e "  ${CYAN}4)${NC} Open HANA Cloud Central"
    echo -e "  ${CYAN}5)${NC} Select different instance"
    echo -e "  ${CYAN}6)${NC} Select different subaccount"
    echo -e "  ${CYAN}7)${NC} Refresh status"
    echo -e "  ${CYAN}0)${NC} Exit"
    echo ""
    read -p "  Select option [0-7]: " menu_choice
    
    case $menu_choice in
        1)
            get_instance_status || true
            ;;
        2)
            start_instance
            ;;
        3)
            stop_instance
            ;;
        4)
            print_step "Opening HANA Cloud Central..."
            local url="https://hana-cloud.cfapps.us10.hana.ondemand.com/"
            open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || echo -e "  ${CYAN}$url${NC}"
            print_ok
            ;;
        5)
            if fetch_hana_instances && select_hana_instance; then
                get_instance_status || true
            fi
            ;;
        6)
            if fetch_subaccounts && select_subaccount; then
                if fetch_hana_instances && select_hana_instance; then
                    get_instance_status || true
                fi
            fi
            ;;
        7)
            get_instance_status || true
            ;;
        0)
            echo ""
            print_info "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            ;;
    esac
}

# ============================================================================
# Main
# ============================================================================

main() {
    clear
    print_banner
    
    # Check prerequisites
    print_section "Prerequisites Check"
    check_btp_cli
    
    # Check login
    if ! check_btp_login; then
        btp_login
    fi
    
    # Select subaccount
    if ! fetch_subaccounts; then
        exit 1
    fi
    
    if ! select_subaccount; then
        exit 1
    fi
    
    # Select HANA instance
    if ! fetch_hana_instances; then
        print_warning "No HANA instances found. Please create a HANA instance first."
        exit 1
    fi
    
    if ! select_hana_instance; then
        exit 1
    fi
    
    # Show initial status
    get_instance_status || true
    
    # Main menu loop
    while true; do
        show_main_menu
    done
}

main "$@"
