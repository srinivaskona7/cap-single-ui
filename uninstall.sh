#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Complete Uninstallation Script                                          ║
# ║  Removes: Helm Release → Service Bindings → Service Instances → Policies ║
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
# Configuration
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_EGRESS_DIR="$SCRIPT_DIR/ingress-egress"
DEFAULT_KUBECONFIG="$SCRIPT_DIR/kubernetes/admin-sa-token.yaml"
KUBECONFIG_PATH="${1:-$DEFAULT_KUBECONFIG}"

# Network policy resources
declare -a NETWORK_POLICIES=(
    "AuthorizationPolicy|global-ingress-ip-allowlist|istio-system|IP-based ingress restriction"
    "ServiceEntry|sap-btp-services|istio-system|SAP BTP egress whitelist"
    "Sidecar|default-egress-policy|istio-system|REGISTRY_ONLY egress policy"
)

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}║${NC}   ${WHITE}${BOLD}Complete Uninstallation Script${NC}                                        ${RED}║${NC}"
    echo -e "${RED}║${NC}   ${DIM}Helm Release + Service Bindings + Service Instances + Policies${NC}        ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
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

print_step() {
    printf "  ${CYAN}●${NC}  %-50s" "$1"
}

print_action() {
    printf "  ${RED}⟳${NC}  %-50s" "$1"
}

print_ok() {
    echo -e "${GREEN}✓ Done${NC}"
}

print_fail() {
    echo -e "${RED}✗ Failed${NC}"
}

print_skip() {
    echo -e "${YELLOW}○ Skipped${NC}"
}

print_not_found() {
    echo -e "${GRAY}○ Not found${NC}"
}

print_detail() {
    echo -e "      ${DIM}$1${NC}"
}

print_plan_destroy() {
    echo -e "  ${RED}-${NC} $1 ${DIM}($2)${NC}"
}

print_plan_skip() {
    echo -e "  ${GRAY}○${NC} $1 ${DIM}(not found)${NC}"
}

# ============================================================================
# Validation Functions
# ============================================================================

check_prerequisites() {
    print_section "Prerequisites Check"
    
    local errors=0
    
    print_step "kubectl"
    if command -v kubectl &> /dev/null; then
        print_ok
    else
        print_fail
        errors=$((errors + 1))
    fi
    
    print_step "helm"
    if command -v helm &> /dev/null; then
        print_ok
    else
        print_fail
        errors=$((errors + 1))
    fi
    
    print_step "kubeconfig"
    if [ -f "$KUBECONFIG_PATH" ]; then
        print_ok
        print_detail "Path: $KUBECONFIG_PATH"
    else
        print_fail
        print_detail "Not found: $KUBECONFIG_PATH"
        errors=$((errors + 1))
    fi
    
    print_step "Cluster connection"
    if kubectl --kubeconfig="$KUBECONFIG_PATH" cluster-info &> /dev/null; then
        print_ok
    else
        print_fail
        errors=$((errors + 1))
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "  ${RED}${BOLD}✗ Prerequisites check failed ($errors error(s))${NC}"
        exit 1
    else
        echo -e "  ${GREEN}${BOLD}✓ All prerequisites met${NC}"
    fi
}

# ============================================================================
# Release Selection
# ============================================================================

select_release() {
    print_section "Release Selection"
    
    echo -e "  ${WHITE}Available Helm releases:${NC}"
    echo ""
    
    # Get all releases with their namespaces
    local releases
    releases=$(helm --kubeconfig="$KUBECONFIG_PATH" list -A --output json 2>/dev/null)
    
    if [ -z "$releases" ] || [ "$releases" == "[]" ]; then
        echo -e "  ${YELLOW}No Helm releases found in the cluster.${NC}"
        echo ""
        read -p "  Enter release name manually (or press Enter to skip): " RELEASE_NAME
        if [ -z "$RELEASE_NAME" ]; then
            RELEASE_NAME=""
            RELEASE_NAMESPACE=""
            return 1
        fi
        read -p "  Enter namespace for '$RELEASE_NAME': " RELEASE_NAMESPACE
        return 0
    fi
    
    # Parse and display releases
    declare -a release_names=()
    declare -a release_namespaces=()
    declare -a release_statuses=()
    
    local idx=0
    while IFS= read -r line; do
        local name=$(echo "$line" | cut -d'|' -f1)
        local ns=$(echo "$line" | cut -d'|' -f2)
        local status=$(echo "$line" | cut -d'|' -f3)
        
        if [ -n "$name" ]; then
            idx=$((idx + 1))
            release_names+=("$name")
            release_namespaces+=("$ns")
            release_statuses+=("$status")
            
            local status_color="${GREEN}"
            [ "$status" != "deployed" ] && status_color="${YELLOW}"
            
            printf "  ${CYAN}%2d)${NC}  %-30s ${DIM}namespace:${NC} %-15s ${status_color}%s${NC}\n" \
                "$idx" "$name" "$ns" "$status"
        fi
    done < <(echo "$releases" | grep -oE '"name":"[^"]+"|"namespace":"[^"]+"|"status":"[^"]+"' | \
        paste - - - | sed 's/"name":"//g; s/"namespace":"//g; s/"status":"//g; s/"//g; s/\t/|/g')
    
    echo ""
    printf "  ${CYAN}%2d)${NC}  %-30s\n" "0" "Skip Helm release uninstall"
    echo ""
    
    read -p "  Select release to uninstall [0-$idx]: " choice
    
    if [ "$choice" == "0" ] || [ -z "$choice" ]; then
        RELEASE_NAME=""
        RELEASE_NAMESPACE=""
        echo ""
        echo -e "  ${YELLOW}Skipping Helm release uninstall.${NC}"
        return 1
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $idx ]; then
        echo -e "  ${RED}Invalid selection.${NC}"
        RELEASE_NAME=""
        RELEASE_NAMESPACE=""
        return 1
    fi
    
    RELEASE_NAME="${release_names[$((choice-1))]}"
    RELEASE_NAMESPACE="${release_namespaces[$((choice-1))]}"
    
    echo ""
    echo -e "  ${GREEN}✓ Selected: ${WHITE}$RELEASE_NAME${NC} in namespace ${CYAN}$RELEASE_NAMESPACE${NC}"
    return 0
}

# ============================================================================
# Destruction Plan
# ============================================================================

show_destruction_plan() {
    print_section "Destruction Plan"
    
    local total_destroy=0
    local total_skip=0
    
    # Phase 1: Helm Release
    if [ -n "$RELEASE_NAME" ]; then
        print_subsection "Phase 1: Helm Release"
        print_plan_destroy "helm/$RELEASE_NAME" "namespace: $RELEASE_NAMESPACE"
        total_destroy=$((total_destroy + 1))
    fi
    
    # Phase 2: Service Bindings
    print_subsection "Phase 2: Service Bindings"
    
    local bindings
    if [ -n "$RELEASE_NAMESPACE" ]; then
        bindings=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get servicebindings -n "$RELEASE_NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')
    else
        bindings=0
    fi
    
    if [ "$bindings" -gt 0 ]; then
        echo -e "  ${RED}-${NC} ServiceBindings ${DIM}($bindings found in $RELEASE_NAMESPACE)${NC}"
        total_destroy=$((total_destroy + bindings))
    else
        echo -e "  ${GRAY}○${NC} ServiceBindings ${DIM}(none found)${NC}"
    fi
    
    # Phase 3: Service Instances
    print_subsection "Phase 3: Service Instances"
    
    local instances
    if [ -n "$RELEASE_NAMESPACE" ]; then
        instances=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get serviceinstances -n "$RELEASE_NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')
    else
        instances=0
    fi
    
    if [ "$instances" -gt 0 ]; then
        echo -e "  ${RED}-${NC} ServiceInstances ${DIM}($instances found in $RELEASE_NAMESPACE)${NC}"
        total_destroy=$((total_destroy + instances))
    else
        echo -e "  ${GRAY}○${NC} ServiceInstances ${DIM}(none found)${NC}"
    fi
    
    # Phase 4: Network Policies
    print_subsection "Phase 4: Network Policies"
    
    for policy in "${NETWORK_POLICIES[@]}"; do
        IFS='|' read -r type name namespace desc <<< "$policy"
        
        if kubectl --kubeconfig="$KUBECONFIG_PATH" get "$type" "$name" -n "$namespace" &> /dev/null 2>&1; then
            print_plan_destroy "$type/$name" "namespace: $namespace"
            total_destroy=$((total_destroy + 1))
        else
            print_plan_skip "$type/$name"
            total_skip=$((total_skip + 1))
        fi
    done
    
    echo ""
    echo -e "  ${WHITE}Plan Summary: ${RED}$total_destroy to destroy${NC}, ${GRAY}$total_skip not found${NC}"
    
    if [ $total_destroy -eq 0 ]; then
        echo ""
        echo -e "  ${YELLOW}Nothing to destroy. Exiting.${NC}"
        exit 0
    fi
}

# ============================================================================
# Confirmation
# ============================================================================

confirm_destruction() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${YELLOW}${BOLD}⚠ WARNING: DESTRUCTIVE OPERATION${NC}                                       ${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}║${NC}  This will permanently delete:                                          ${RED}║${NC}"
    if [ -n "$RELEASE_NAME" ]; then
    echo -e "${RED}║${NC}    • Helm release and all its resources                                 ${RED}║${NC}"
    fi
    echo -e "${RED}║${NC}    • Service Bindings (BTP connections)                                 ${RED}║${NC}"
    echo -e "${RED}║${NC}    • Service Instances (BTP services)                                   ${RED}║${NC}"
    echo -e "${RED}║${NC}    • Network Policies (egress/ingress restrictions)                     ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}║${NC}  After removal:                                                         ${RED}║${NC}"
    echo -e "${RED}║${NC}    • All egress traffic will be allowed (ALLOW_ANY)                     ${RED}║${NC}"
    echo -e "${RED}║${NC}    • All ingress traffic will be allowed (no IP restriction)            ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Type 'yes' to confirm destruction: " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo ""
        echo -e "  ${YELLOW}Destruction cancelled.${NC}"
        exit 0
    fi
}

# ============================================================================
# Execution Phases
# ============================================================================

execute_phase1_helm() {
    if [ -z "$RELEASE_NAME" ]; then
        return 0
    fi
    
    print_subsection "Phase 1: Uninstalling Helm Release"
    
    print_action "Uninstalling $RELEASE_NAME..."
    
    if helm --kubeconfig="$KUBECONFIG_PATH" uninstall "$RELEASE_NAME" -n "$RELEASE_NAMESPACE" &> /dev/null; then
        print_ok
        print_detail "Helm release '$RELEASE_NAME' removed from $RELEASE_NAMESPACE"
        return 0
    else
        print_fail
        print_detail "Failed to uninstall helm release"
        return 1
    fi
}

execute_phase2_bindings() {
    if [ -z "$RELEASE_NAMESPACE" ]; then
        return 0
    fi
    
    print_subsection "Phase 2: Removing Service Bindings"
    
    local bindings
    bindings=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get servicebindings -n "$RELEASE_NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$bindings" ]; then
        echo -e "  ${GRAY}○${NC}  No service bindings to remove"
        return 0
    fi
    
    local count=0
    local failed=0
    
    while IFS= read -r binding; do
        local name=$(echo "$binding" | sed 's|servicebinding.services.cloud.sap.com/||')
        print_action "Removing $name..."
        
        if kubectl --kubeconfig="$KUBECONFIG_PATH" delete "$binding" -n "$RELEASE_NAMESPACE" --timeout=60s &> /dev/null; then
            print_ok
            count=$((count + 1))
        else
            print_fail
            failed=$((failed + 1))
        fi
    done <<< "$bindings"
    
    echo ""
    echo -e "  ${DIM}Removed $count binding(s), $failed failed${NC}"
    
    return $failed
}

execute_phase3_instances() {
    if [ -z "$RELEASE_NAMESPACE" ]; then
        return 0
    fi
    
    print_subsection "Phase 3: Removing Service Instances"
    
    local instances
    instances=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get serviceinstances -n "$RELEASE_NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$instances" ]; then
        echo -e "  ${GRAY}○${NC}  No service instances to remove"
        return 0
    fi
    
    local count=0
    local failed=0
    
    while IFS= read -r instance; do
        local name=$(echo "$instance" | sed 's|serviceinstance.services.cloud.sap.com/||')
        print_action "Removing $name..."
        
        if kubectl --kubeconfig="$KUBECONFIG_PATH" delete "$instance" -n "$RELEASE_NAMESPACE" --timeout=120s &> /dev/null; then
            print_ok
            count=$((count + 1))
        else
            print_fail
            failed=$((failed + 1))
        fi
    done <<< "$instances"
    
    echo ""
    echo -e "  ${DIM}Removed $count instance(s), $failed failed${NC}"
    
    return $failed
}

execute_phase4_policies() {
    print_subsection "Phase 4: Removing Network Policies"
    
    local count=0
    local failed=0
    local skipped=0
    
    for policy in "${NETWORK_POLICIES[@]}"; do
        IFS='|' read -r type name namespace desc <<< "$policy"
        
        if ! kubectl --kubeconfig="$KUBECONFIG_PATH" get "$type" "$name" -n "$namespace" &> /dev/null 2>&1; then
            print_action "Removing $name..."
            print_not_found
            skipped=$((skipped + 1))
            continue
        fi
        
        print_action "Removing $name..."
        
        if kubectl --kubeconfig="$KUBECONFIG_PATH" delete "$type" "$name" -n "$namespace" --ignore-not-found &> /dev/null; then
            print_ok
            print_detail "Destroyed $type/$name from $namespace"
            count=$((count + 1))
        else
            print_fail
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    echo -e "  ${DIM}Removed $count policy(ies), $skipped not found, $failed failed${NC}"
    
    return $failed
}

# ============================================================================
# Verification
# ============================================================================

verify_cleanup() {
    print_section "Verification"
    
    echo -e "  ${WHITE}Verifying cleanup:${NC}"
    echo ""
    
    local all_clean=true
    
    # Check Helm release
    if [ -n "$RELEASE_NAME" ]; then
        print_step "Helm release $RELEASE_NAME"
        if helm --kubeconfig="$KUBECONFIG_PATH" status "$RELEASE_NAME" -n "$RELEASE_NAMESPACE" &> /dev/null; then
            print_fail
            all_clean=false
        else
            print_ok
        fi
    fi
    
    # Check network policies
    for policy in "${NETWORK_POLICIES[@]}"; do
        IFS='|' read -r type name namespace desc <<< "$policy"
        
        print_step "$type/$name"
        
        if kubectl --kubeconfig="$KUBECONFIG_PATH" get "$type" "$name" -n "$namespace" &> /dev/null 2>&1; then
            print_fail
            all_clean=false
        else
            print_ok
        fi
    done
    
    echo ""
    
    if $all_clean; then
        echo -e "  ${GREEN}${BOLD}✓ All resources cleaned up successfully${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}⚠ Some resources may still exist${NC}"
    fi
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    local exit_code=$1
    
    print_section "Summary"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}                                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   ${WHITE}${BOLD}✓ Uninstallation Complete!${NC}                                            ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}                                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}   All resources have been removed successfully.                         ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}                                                                          ${GREEN}║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
        echo -e "${RED}║${NC}   ${YELLOW}${BOLD}⚠ Uninstallation completed with warnings${NC}                               ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
        echo -e "${RED}║${NC}   Some resources may not have been removed. Check errors above.          ${RED}║${NC}"
        echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}${BOLD}  Network Security Status:${NC}"
    echo -e "  ${DIM}• Egress:  ALLOW_ANY (all outbound traffic now allowed)${NC}"
    echo -e "  ${DIM}• Ingress: Open (all client IPs can now access)${NC}"
    echo ""
    echo -e "  ${DIM}To reinstall: ./install.sh${NC}"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    clear
    print_banner
    
    # Show configuration
    echo -e "  ${DIM}Configuration:${NC}"
    echo -e "  ${DIM}• Kubeconfig: $KUBECONFIG_PATH${NC}"
    
    # Run phases
    check_prerequisites
    select_release
    show_destruction_plan
    confirm_destruction
    
    print_section "Executing Destruction"
    
    local errors=0
    
    execute_phase1_helm || errors=$((errors + 1))
    execute_phase2_bindings || errors=$((errors + 1))
    execute_phase3_instances || errors=$((errors + 1))
    execute_phase4_policies || errors=$((errors + 1))
    
    verify_cleanup
    print_summary $errors
    
    exit $errors
}

main "$@"
