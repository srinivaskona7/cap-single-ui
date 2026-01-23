#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  CAP Application Deployment Manager                                       ║
# ║  Helm + Network Policies (Ingress/Egress)                                 ║
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
# Configuration - UPDATE THESE VALUES AS NEEDED
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/gen/chart"
INGRESS_EGRESS_DIR="$SCRIPT_DIR/ingress-egress"

# Kubeconfig - Update this path to your kubeconfig file
KUBECONFIG_PATH="$SCRIPT_DIR/kubernetes/admin.yaml"

# Default values
DEFAULT_RELEASE_NAME="single-ui"
DEFAULT_NAMESPACE="sri"
DEFAULT_DOCKER_REGISTRY="sriniv7654"  # Docker Hub username
DEFAULT_IMAGE_REPO="apple-node-egress"

# Network policy resources
declare -a EGRESS_POLICIES=(
    "01-egress-sidecar.yaml|Sidecar|default-egress-policy|istio-system|REGISTRY_ONLY egress policy"
    "02-egress-serviceentry.yaml|ServiceEntry|sap-btp-services|istio-system|SAP BTP egress whitelist"
)

declare -a INGRESS_POLICIES=(
    "03-ingress-ip-allowlist.yaml|AuthorizationPolicy|global-ingress-ip-allowlist|istio-system|IP-based ingress restriction"
)

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${WHITE}${BOLD}CAP Application Deployment Manager${NC}                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${DIM}Helm + Network Policies (Ingress/Egress)${NC}                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
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
    printf "${GRAY}│${NC} %-72s ${GRAY}│${NC}\n" "$1"
    echo -e "${GRAY}└──────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_step() {
    printf "  ${CYAN}●${NC}  %-50s" "$1"
}

print_action() {
    printf "  ${CYAN}⟳${NC}  %-50s" "$1"
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

print_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_detail() {
    echo -e "      ${DIM}$1${NC}"
}

# ============================================================================
# Validation
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
        errors=$((errors + 1))
    fi
    
    print_step "Cluster connection"
    if kubectl --kubeconfig="$KUBECONFIG_PATH" cluster-info &> /dev/null; then
        print_ok
    else
        print_fail
        errors=$((errors + 1))
    fi
    
    print_step "Chart directory"
    if [ -d "$CHART_DIR" ]; then
        print_ok
        print_detail "Path: $CHART_DIR"
    else
        print_fail
        print_detail "Not found: $CHART_DIR"
        errors=$((errors + 1))
    fi
    
    echo ""
    
    if [ $errors -gt 0 ]; then
        echo -e "  ${RED}${BOLD}✗ Prerequisites check failed ($errors error(s))${NC}"
        return 1
    else
        echo -e "  ${GREEN}${BOLD}✓ All prerequisites met${NC}"
        return 0
    fi
}

# ============================================================================
# Build Process Functions
# ============================================================================

prompt_build_options() {
    print_subsection "Build Options"
    
    echo -e "  ${WHITE}Do you want to build new Docker images?${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Yes - Build and push new images"
    echo -e "  ${CYAN}2)${NC} No - Use existing images"
    echo ""
    
    read -p "  Select option [1-2]: " build_choice
    
    if [ "$build_choice" == "1" ]; then
        DO_BUILD="true"
        
        echo ""
        echo -e "  ${WHITE}Enter build configuration:${NC}"
        echo ""
        
        read -p "  Image tag/version [$DEFAULT_RELEASE_NAME]: " BUILD_TAG
        BUILD_TAG="${BUILD_TAG:-$DEFAULT_RELEASE_NAME}"
        
        read -p "  Docker registry [$DEFAULT_DOCKER_REGISTRY]: " DOCKER_REGISTRY
        DOCKER_REGISTRY="${DOCKER_REGISTRY:-$DEFAULT_DOCKER_REGISTRY}"
        
        read -p "  Image repository [$DEFAULT_IMAGE_REPO]: " IMAGE_REPO
        IMAGE_REPO="${IMAGE_REPO:-$DEFAULT_IMAGE_REPO}"
        
        echo ""
        print_success "Build: Yes"
        print_success "Tag: $BUILD_TAG"
        print_success "Registry: $DOCKER_REGISTRY/$IMAGE_REPO"
    else
        DO_BUILD="false"
        BUILD_TAG=""
        print_info "Using existing images from values.yaml"
    fi
}

run_cds_build() {
    print_subsection "CDS Build (Production)"
    
    print_action "Running cds build --production..."
    
    if cds build --production &> /tmp/cds_build.log; then
        print_ok
        print_detail "Production build completed"
        return 0
    else
        print_fail
        echo ""
        echo -e "  ${RED}CDS Build Error:${NC}"
        cat /tmp/cds_build.log | head -20
        return 1
    fi
}

build_and_push_images() {
    print_subsection "Docker Build & Push"
    
    local srv_image="$DOCKER_REGISTRY/$IMAGE_REPO:srv-$BUILD_TAG"
    local hana_image="$DOCKER_REGISTRY/$IMAGE_REPO:hana-$BUILD_TAG"
    
    # Build srv image
    print_action "Building srv image..."
    if docker build -t "$srv_image" -f gen/srv/Dockerfile gen/srv &> /tmp/docker_srv.log; then
        print_ok
        print_detail "Image: $srv_image"
    else
        print_fail
        cat /tmp/docker_srv.log | tail -10
        return 1
    fi
    
    # Build hana image
    print_action "Building hana (db-deployer) image..."
    if docker build -t "$hana_image" -f gen/db/Dockerfile gen/db &> /tmp/docker_hana.log; then
        print_ok
        print_detail "Image: $hana_image"
    else
        print_fail
        cat /tmp/docker_hana.log | tail -10
        return 1
    fi
    
    # Push srv image
    print_action "Pushing srv image..."
    if docker push "$srv_image" &> /tmp/docker_push_srv.log; then
        print_ok
    else
        print_fail
        cat /tmp/docker_push_srv.log | tail -5
        return 1
    fi
    
    # Push hana image
    print_action "Pushing hana image..."
    if docker push "$hana_image" &> /tmp/docker_push_hana.log; then
        print_ok
    else
        print_fail
        cat /tmp/docker_push_hana.log | tail -5
        return 1
    fi
    
    return 0
}

update_values_yaml() {
    print_subsection "Updating values.yaml"
    
    local values_file="$CHART_DIR/values.yaml"
    local srv_image="$DOCKER_REGISTRY/$IMAGE_REPO"
    local srv_tag="srv-$BUILD_TAG"
    local hana_tag="hana-$BUILD_TAG"
    
    if [ ! -f "$values_file" ]; then
        print_error "values.yaml not found: $values_file"
        return 1
    fi
    
    # Backup original
    cp "$values_file" "$values_file.bak"
    
    # Update srv image
    print_action "Updating srv image tag..."
    if sed -i '' "s|srv:.*$|srv:$srv_tag|g" "$values_file" 2>/dev/null || \
       sed -i "s|srv:.*$|srv:$srv_tag|g" "$values_file" 2>/dev/null; then
        print_ok
        print_detail "srv tag: $srv_tag"
    fi
    
    # Update hana image
    print_action "Updating hana image tag..."
    if sed -i '' "s|hana:.*$|hana:$hana_tag|g" "$values_file" 2>/dev/null || \
       sed -i "s|hana:.*$|hana:$hana_tag|g" "$values_file" 2>/dev/null; then
        print_ok
        print_detail "hana tag: $hana_tag"
    fi
    
    return 0
}

run_full_build_process() {
    if [ "$DO_BUILD" != "true" ]; then
        return 0
    fi
    
    print_section "Build Process"
    
    # Step 1: CDS Build
    if ! run_cds_build; then
        return 1
    fi
    
    # Step 2: Docker Build & Push
    if ! build_and_push_images; then
        return 1
    fi
    
    # Step 3: Update values.yaml
    if ! update_values_yaml; then
        return 1
    fi
    
    echo ""
    print_success "Build process completed successfully"
    return 0
}

# ============================================================================
# Helm Functions
# ============================================================================

get_release_list() {
    helm --kubeconfig="$KUBECONFIG_PATH" list -A --output json 2>/dev/null
}

prompt_release_details() {
    local action=$1  # install or upgrade
    
    print_section "Release Configuration"
    
    if [ "$action" == "upgrade" ]; then
        # Show existing releases for upgrade
        echo -e "  ${WHITE}Existing Helm releases:${NC}"
        echo ""
        
        local releases=$(get_release_list)
        local idx=0
        declare -a release_names=()
        declare -a release_namespaces=()
        
        while IFS= read -r line; do
            local name=$(echo "$line" | cut -d'|' -f1)
            local ns=$(echo "$line" | cut -d'|' -f2)
            local status=$(echo "$line" | cut -d'|' -f3)
            
            if [ -n "$name" ]; then
                idx=$((idx + 1))
                release_names+=("$name")
                release_namespaces+=("$ns")
                
                local status_color="${GREEN}"
                [ "$status" != "deployed" ] && status_color="${YELLOW}"
                
                printf "  ${CYAN}%2d)${NC}  %-25s ${DIM}namespace:${NC} %-15s ${status_color}%s${NC}\n" \
                    "$idx" "$name" "$ns" "$status"
            fi
        done < <(echo "$releases" | grep -oE '"name":"[^"]+"|"namespace":"[^"]+"|"status":"[^"]+"' | \
            paste - - - | sed 's/"name":"//g; s/"namespace":"//g; s/"status":"//g; s/"//g; s/\t/|/g')
        
        echo ""
        printf "  ${CYAN}%2d)${NC}  %-25s\n" "0" "Enter manually"
        echo ""
        
        read -p "  Select release [0-$idx]: " choice
        
        if [ "$choice" != "0" ] && [ "$choice" -ge 1 ] && [ "$choice" -le $idx ] 2>/dev/null; then
            RELEASE_NAME="${release_names[$((choice-1))]}"
            RELEASE_NAMESPACE="${release_namespaces[$((choice-1))]}"
            echo ""
            print_success "Selected: $RELEASE_NAME in namespace $RELEASE_NAMESPACE"
            return 0
        fi
    fi
    
    # Manual entry
    echo ""
    echo -e "  ${WHITE}Enter release details:${NC}"
    echo ""
    
    read -p "  Release name [$DEFAULT_RELEASE_NAME]: " RELEASE_NAME
    RELEASE_NAME="${RELEASE_NAME:-$DEFAULT_RELEASE_NAME}"
    
    read -p "  Namespace [$DEFAULT_NAMESPACE]: " RELEASE_NAMESPACE
    RELEASE_NAMESPACE="${RELEASE_NAMESPACE:-$DEFAULT_NAMESPACE}"
    
    echo ""
    print_success "Release: $RELEASE_NAME"
    print_success "Namespace: $RELEASE_NAMESPACE"
}

prompt_build_version() {
    print_subsection "Build Version (Optional)"
    
    echo -e "  ${DIM}Leave empty to use current image tags from values.yaml${NC}"
    echo ""
    read -p "  Image tag version: " BUILD_VERSION
    
    if [ -n "$BUILD_VERSION" ]; then
        print_success "Version: $BUILD_VERSION"
    else
        print_info "Using existing image tags"
    fi
}

helm_install() {
    local with_policies=$1
    
    prompt_release_details "install"
    prompt_build_options
    
    print_section "Installation Plan"
    
    echo -e "  ${WHITE}Helm Release:${NC}"
    echo -e "    ${GREEN}+${NC} Release: ${CYAN}$RELEASE_NAME${NC}"
    echo -e "    ${GREEN}+${NC} Namespace: ${CYAN}$RELEASE_NAMESPACE${NC}"
    echo -e "    ${GREEN}+${NC} Chart: ${CYAN}$CHART_DIR${NC}"
    
    if [ "$DO_BUILD" == "true" ]; then
        echo ""
        echo -e "  ${WHITE}Build Process:${NC}"
        echo -e "    ${GREEN}+${NC} CDS Build: cds build --production"
        echo -e "    ${GREEN}+${NC} Docker: $DOCKER_REGISTRY/$IMAGE_REPO"
        echo -e "    ${GREEN}+${NC} Tags: srv-$BUILD_TAG, hana-$BUILD_TAG"
    fi
    
    if [ "$with_policies" == "true" ]; then
        echo ""
        echo -e "  ${WHITE}Network Policies:${NC}"
        echo -e "    ${GREEN}+${NC} Egress: ServiceEntry + Sidecar"
        echo -e "    ${GREEN}+${NC} Ingress: AuthorizationPolicy"
    fi
    
    echo ""
    read -p "  Proceed with installation? [Y/n]: " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_warning "Installation cancelled"
        return 1
    fi
    
    # Run build process if requested
    if [ "$DO_BUILD" == "true" ]; then
        if ! run_full_build_process; then
            print_error "Build process failed"
            return 1
        fi
    fi
    
    print_section "Executing Installation"
    
    # Build helm install command
    local helm_cmd="helm --kubeconfig=$KUBECONFIG_PATH install $RELEASE_NAME $CHART_DIR -n $RELEASE_NAMESPACE --create-namespace"
    
    print_subsection "Installing Helm Release"
    
    print_action "Installing $RELEASE_NAME..."
    
    if eval "$helm_cmd" &> /tmp/helm_output.txt; then
        print_ok
        print_detail "Release '$RELEASE_NAME' deployed to namespace '$RELEASE_NAMESPACE'"
    else
        print_fail
        cat /tmp/helm_output.txt
        return 1
    fi
    
    # Apply policies if requested
    if [ "$with_policies" == "true" ]; then
        apply_all_policies
    fi
    
    print_success_summary "Installation"
    return 0
}

helm_upgrade() {
    local with_policies=$1
    
    prompt_release_details "upgrade"
    prompt_build_options
    
    print_section "Upgrade Plan"
    
    echo -e "  ${WHITE}Helm Release:${NC}"
    echo -e "    ${YELLOW}~${NC} Release: ${CYAN}$RELEASE_NAME${NC}"
    echo -e "    ${YELLOW}~${NC} Namespace: ${CYAN}$RELEASE_NAMESPACE${NC}"
    echo -e "    ${YELLOW}~${NC} Chart: ${CYAN}$CHART_DIR${NC}"
    
    if [ "$DO_BUILD" == "true" ]; then
        echo ""
        echo -e "  ${WHITE}Build Process:${NC}"
        echo -e "    ${YELLOW}~${NC} CDS Build: cds build --production"
        echo -e "    ${YELLOW}~${NC} Docker: $DOCKER_REGISTRY/$IMAGE_REPO"
        echo -e "    ${YELLOW}~${NC} Tags: srv-$BUILD_TAG, hana-$BUILD_TAG"
    fi
    
    if [ "$with_policies" == "true" ]; then
        echo ""
        echo -e "  ${WHITE}Network Policies:${NC}"
        echo -e "    ${YELLOW}~${NC} Egress: ServiceEntry + Sidecar"
        echo -e "    ${YELLOW}~${NC} Ingress: AuthorizationPolicy"
    fi
    
    echo ""
    read -p "  Proceed with upgrade? [Y/n]: " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        print_warning "Upgrade cancelled"
        return 1
    fi
    
    # Run build process if requested
    if [ "$DO_BUILD" == "true" ]; then
        if ! run_full_build_process; then
            print_error "Build process failed"
            return 1
        fi
    fi
    
    print_section "Executing Upgrade"
    
    # Build helm upgrade command
    local helm_cmd="helm --kubeconfig=$KUBECONFIG_PATH upgrade $RELEASE_NAME $CHART_DIR -n $RELEASE_NAMESPACE"
    
    print_subsection "Upgrading Helm Release"
    
    print_action "Upgrading $RELEASE_NAME..."
    
    if eval "$helm_cmd" &> /tmp/helm_output.txt; then
        print_ok
        print_detail "Release '$RELEASE_NAME' upgraded in namespace '$RELEASE_NAMESPACE'"
    else
        print_fail
        cat /tmp/helm_output.txt
        return 1
    fi
    
    # Apply policies if requested
    if [ "$with_policies" == "true" ]; then
        apply_all_policies
    fi
    
    print_success_summary "Upgrade"
    return 0
}

# ============================================================================
# Network Policy Functions
# ============================================================================

apply_policy() {
    local file=$1
    local type=$2
    local name=$3
    local namespace=$4
    local desc=$5
    
    local filepath="$INGRESS_EGRESS_DIR/$file"
    
    if [ ! -f "$filepath" ]; then
        print_action "Applying $name..."
        print_skip
        print_detail "File not found: $filepath"
        return 1
    fi
    
    print_action "Applying $name..."
    
    if kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f "$filepath" &> /dev/null; then
        print_ok
        print_detail "$desc"
        return 0
    else
        print_fail
        return 1
    fi
}

apply_egress_policies() {
    print_subsection "Applying Egress Policies"
    
    local failed=0
    
    for policy in "${EGRESS_POLICIES[@]}"; do
        IFS='|' read -r file type name namespace desc <<< "$policy"
        apply_policy "$file" "$type" "$name" "$namespace" "$desc" || failed=$((failed + 1))
    done
    
    return $failed
}

apply_ingress_policies() {
    print_subsection "Applying Ingress Policies"
    
    local failed=0
    
    for policy in "${INGRESS_POLICIES[@]}"; do
        IFS='|' read -r file type name namespace desc <<< "$policy"
        apply_policy "$file" "$type" "$name" "$namespace" "$desc" || failed=$((failed + 1))
    done
    
    return $failed
}

apply_all_policies() {
    apply_egress_policies
    apply_ingress_policies
}

# ============================================================================
# Uninstall Network Policies
# ============================================================================

uninstall_policies_menu() {
    print_section "Uninstall Network Policies"
    
    echo -e "  ${WHITE}Select policies to remove:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Remove Egress Only (ServiceEntry + Sidecar)"
    echo -e "  ${CYAN}2)${NC} Remove Ingress Only (AuthorizationPolicy)"
    echo -e "  ${CYAN}3)${NC} Remove All Policies"
    echo -e "  ${CYAN}0)${NC} Back to main menu"
    echo ""
    
    read -p "  Select option [0-3]: " choice
    
    case $choice in
        1)
            remove_egress_policies
            ;;
        2)
            remove_ingress_policies
            ;;
        3)
            remove_all_policies
            ;;
        0)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

remove_policy() {
    local type=$1
    local name=$2
    local namespace=$3
    
    print_action "Removing $name..."
    
    if kubectl --kubeconfig="$KUBECONFIG_PATH" delete "$type" "$name" -n "$namespace" --ignore-not-found &> /dev/null; then
        print_ok
        return 0
    else
        print_fail
        return 1
    fi
}

remove_egress_policies() {
    print_subsection "Removing Egress Policies"
    
    echo ""
    read -p "  Remove egress policies? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Cancelled"
        return 0
    fi
    
    echo ""
    
    for policy in "${EGRESS_POLICIES[@]}"; do
        IFS='|' read -r file type name namespace desc <<< "$policy"
        remove_policy "$type" "$name" "$namespace"
    done
    
    echo ""
    print_success "Egress policies removed"
    print_warning "All egress traffic is now ALLOW_ANY"
}

remove_ingress_policies() {
    print_subsection "Removing Ingress Policies"
    
    echo ""
    read -p "  Remove ingress policies? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Cancelled"
        return 0
    fi
    
    echo ""
    
    for policy in "${INGRESS_POLICIES[@]}"; do
        IFS='|' read -r file type name namespace desc <<< "$policy"
        remove_policy "$type" "$name" "$namespace"
    done
    
    echo ""
    print_success "Ingress policies removed"
    print_warning "All client IPs can now access"
}

remove_all_policies() {
    print_subsection "Removing All Policies"
    
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${YELLOW}${BOLD}⚠ WARNING${NC}                                                                ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC}                                                                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}  This will remove ALL network policies:                                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    • Egress: All outbound traffic will be allowed                       ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}    • Ingress: All client IPs can access your app                        ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                          ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Type 'yes' to confirm: " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_warning "Cancelled"
        return 0
    fi
    
    echo ""
    
    for policy in "${EGRESS_POLICIES[@]}"; do
        IFS='|' read -r file type name namespace desc <<< "$policy"
        remove_policy "$type" "$name" "$namespace"
    done
    
    for policy in "${INGRESS_POLICIES[@]}"; do
        IFS='|' read -r file type name namespace desc <<< "$policy"
        remove_policy "$type" "$name" "$namespace"
    done
    
    echo ""
    print_success "All network policies removed"
}

# ============================================================================
# Uninstall Helm Release (Full Cleanup)
# ============================================================================

uninstall_helm_menu() {
    print_section "Uninstall Helm Release"
    
    echo -e "  ${WHITE}Available Helm releases:${NC}"
    echo ""
    
    local releases=$(get_release_list)
    local idx=0
    declare -a release_names=()
    declare -a release_namespaces=()
    
    while IFS= read -r line; do
        local name=$(echo "$line" | cut -d'|' -f1)
        local ns=$(echo "$line" | cut -d'|' -f2)
        local status=$(echo "$line" | cut -d'|' -f3)
        
        if [ -n "$name" ]; then
            idx=$((idx + 1))
            release_names+=("$name")
            release_namespaces+=("$ns")
            
            local status_color="${GREEN}"
            [ "$status" != "deployed" ] && status_color="${YELLOW}"
            
            printf "  ${CYAN}%2d)${NC}  %-25s ${DIM}namespace:${NC} %-15s ${status_color}%s${NC}\n" \
                "$idx" "$name" "$ns" "$status"
        fi
    done < <(echo "$releases" | grep -oE '"name":"[^"]+"|"namespace":"[^"]+"|"status":"[^"]+"' | \
        paste - - - | sed 's/"name":"//g; s/"namespace":"//g; s/"status":"//g; s/"//g; s/\t/|/g')
    
    if [ $idx -eq 0 ]; then
        echo -e "  ${YELLOW}No Helm releases found.${NC}"
        return 0
    fi
    
    echo ""
    printf "  ${CYAN}%2d)${NC}  %-25s\n" "0" "Back to main menu"
    echo ""
    
    read -p "  Select release to uninstall [0-$idx]: " choice
    
    if [ "$choice" == "0" ] || [ -z "$choice" ]; then
        return 0
    fi
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $idx ]; then
        print_error "Invalid selection"
        return 1
    fi
    
    RELEASE_NAME="${release_names[$((choice-1))]}"
    RELEASE_NAMESPACE="${release_namespaces[$((choice-1))]}"
    
    echo ""
    print_success "Selected: $RELEASE_NAME in namespace $RELEASE_NAMESPACE"
    
    # Show destruction plan
    print_subsection "Destruction Plan"
    
    local bindings=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get servicebindings -n "$RELEASE_NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')
    local instances=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get serviceinstances -n "$RELEASE_NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')
    
    echo -e "  ${WHITE}Order of removal:${NC}"
    echo -e "    ${RED}1.${NC} Service Bindings: ${CYAN}$bindings${NC} found"
    echo -e "    ${RED}2.${NC} Service Instances: ${CYAN}$instances${NC} found"
    echo -e "    ${RED}3.${NC} Helm Release: ${CYAN}$RELEASE_NAME${NC}"
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${YELLOW}${BOLD}⚠ WARNING: DESTRUCTIVE OPERATION${NC}                                       ${RED}║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}║${NC}  This will permanently delete the Helm release and all its resources.  ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                          ${RED}║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "  Type 'yes' to confirm destruction: " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_warning "Cancelled"
        return 0
    fi
    
    print_section "Executing Destruction"
    
    # Phase 1: Remove Service Bindings
    print_subsection "Phase 1: Removing Service Bindings"
    
    local binding_list=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get servicebindings -n "$RELEASE_NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$binding_list" ]; then
        echo -e "  ${GRAY}○${NC}  No service bindings to remove"
    else
        while IFS= read -r binding; do
            local bname=$(echo "$binding" | sed 's|servicebinding.services.cloud.sap.com/||')
            print_action "Removing $bname..."
            if kubectl --kubeconfig="$KUBECONFIG_PATH" delete "$binding" -n "$RELEASE_NAMESPACE" --timeout=60s &> /dev/null; then
                print_ok
            else
                print_fail
            fi
        done <<< "$binding_list"
    fi
    
    # Phase 2: Remove Service Instances
    print_subsection "Phase 2: Removing Service Instances"
    
    local instance_list=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get serviceinstances -n "$RELEASE_NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$instance_list" ]; then
        echo -e "  ${GRAY}○${NC}  No service instances to remove"
    else
        while IFS= read -r instance; do
            local iname=$(echo "$instance" | sed 's|serviceinstance.services.cloud.sap.com/||')
            print_action "Removing $iname..."
            if kubectl --kubeconfig="$KUBECONFIG_PATH" delete "$instance" -n "$RELEASE_NAMESPACE" --timeout=120s &> /dev/null; then
                print_ok
            else
                print_fail
            fi
        done <<< "$instance_list"
    fi
    
    # Phase 3: Uninstall Helm Release
    print_subsection "Phase 3: Uninstalling Helm Release"
    
    print_action "Uninstalling $RELEASE_NAME..."
    
    if helm --kubeconfig="$KUBECONFIG_PATH" uninstall "$RELEASE_NAME" -n "$RELEASE_NAMESPACE" &> /dev/null; then
        print_ok
        print_detail "Helm release '$RELEASE_NAME' removed from $RELEASE_NAMESPACE"
    else
        print_fail
    fi
    
    echo ""
    print_success "Uninstallation complete"
}

# ============================================================================
# Success Summary
# ============================================================================

print_success_summary() {
    local action=$1
    
    print_section "Summary"
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                                                                          ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}   ${WHITE}${BOLD}✓ $action Complete!${NC}                                                     ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                          ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${DIM}Release: $RELEASE_NAME${NC}"
    echo -e "  ${DIM}Namespace: $RELEASE_NAMESPACE${NC}"
    echo ""
}

# ============================================================================
# Cluster Status Functions
# ============================================================================

get_pods_menu() {
    print_section "Get Pods"
    
    echo -e "  ${WHITE}Enter namespace (or 'all' for all namespaces):${NC}"
    echo ""
    read -p "  Namespace [$DEFAULT_NAMESPACE]: " ns
    ns="${ns:-$DEFAULT_NAMESPACE}"
    
    echo ""
    
    if [ "$ns" == "all" ]; then
        print_subsection "Pods (All Namespaces)"
        kubectl --kubeconfig="$KUBECONFIG_PATH" get pods -A --no-headers 2>/dev/null | \
            awk '{printf "  %-20s %-45s %-10s %-8s\n", $1, $2, $4, $5}' | head -30
    else
        print_subsection "Pods in $ns"
        kubectl --kubeconfig="$KUBECONFIG_PATH" get pods -n "$ns" 2>/dev/null | head -30
    fi
    
    echo ""
    echo -e "  ${DIM}Showing first 30 results${NC}"
}

get_services_menu() {
    print_section "Get Service Instances & Bindings"
    
    echo -e "  ${WHITE}Enter namespace:${NC}"
    echo ""
    read -p "  Namespace [$DEFAULT_NAMESPACE]: " ns
    ns="${ns:-$DEFAULT_NAMESPACE}"
    
    print_subsection "Service Instances in $ns"
    
    local instances=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get serviceinstances -n "$ns" 2>/dev/null)
    if [ -n "$instances" ] && ! echo "$instances" | grep -q "No resources"; then
        echo "$instances"
    else
        echo -e "  ${GRAY}No service instances found${NC}"
    fi
    
    print_subsection "Service Bindings in $ns"
    
    local bindings=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get servicebindings -n "$ns" 2>/dev/null)
    if [ -n "$bindings" ] && ! echo "$bindings" | grep -q "No resources"; then
        echo "$bindings"
    else
        echo -e "  ${GRAY}No service bindings found${NC}"
    fi
}

# ============================================================================
# View Ingress/Egress Rules
# ============================================================================

view_ingress_egress_rules() {
    print_section "Current Ingress/Egress Rules"
    
    print_subsection "Egress Rules (Sidecar)"
    
    local sidecar=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get sidecar default-egress-policy -n istio-system -o yaml 2>/dev/null)
    if [ -n "$sidecar" ]; then
        echo "$sidecar" | grep -A 20 "egress:" | head -25
    else
        echo -e "  ${GRAY}No Sidecar policy found (egress is ALLOW_ANY)${NC}"
    fi
    
    print_subsection "Egress Whitelist (ServiceEntry)"
    
    local serviceentry=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get serviceentry sap-btp-services -n istio-system -o yaml 2>/dev/null)
    if [ -n "$serviceentry" ]; then
        echo "$serviceentry" | grep -A 50 "hosts:" | head -30
    else
        echo -e "  ${GRAY}No ServiceEntry found${NC}"
    fi
    
    print_subsection "Ingress IP Allowlist (AuthorizationPolicy)"
    
    local authpolicy=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get authorizationpolicy global-ingress-ip-allowlist -n istio-system -o yaml 2>/dev/null)
    if [ -n "$authpolicy" ]; then
        echo "$authpolicy" | grep -A 30 "ipBlocks:" | head -20
    else
        echo -e "  ${GRAY}No AuthorizationPolicy found (all IPs allowed)${NC}"
    fi
}

# ============================================================================
# Edit & Apply Policy Files
# ============================================================================

edit_policy_menu() {
    print_section "Edit & Apply Policy Files"
    
    echo -e "  ${WHITE}Select policy file to edit:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Egress Sidecar Policy ${DIM}(REGISTRY_ONLY mode)${NC}"
    echo -e "  ${CYAN}2)${NC} Egress ServiceEntry ${DIM}(SAP BTP whitelist)${NC}"
    echo -e "  ${CYAN}3)${NC} Ingress IP Allowlist ${DIM}(AuthorizationPolicy)${NC}"
    echo -e "  ${CYAN}0)${NC} Back to main menu"
    echo ""
    
    read -p "  Select file [0-3]: " choice
    
    local file=""
    local type=""
    local name=""
    local namespace="istio-system"
    
    case $choice in
        1)
            file="$INGRESS_EGRESS_DIR/01-egress-sidecar.yaml"
            type="Sidecar"
            name="default-egress-policy"
            ;;
        2)
            file="$INGRESS_EGRESS_DIR/02-egress-serviceentry.yaml"
            type="ServiceEntry"
            name="sap-btp-services"
            ;;
        3)
            file="$INGRESS_EGRESS_DIR/03-ingress-ip-allowlist.yaml"
            type="AuthorizationPolicy"
            name="global-ingress-ip-allowlist"
            ;;
        0)
            return 0
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
    
    if [ ! -f "$file" ]; then
        print_error "File not found: $file"
        return 1
    fi
    
    # Show current file content
    print_subsection "Current Content: $(basename $file)"
    cat "$file" | head -50
    echo ""
    
    echo -e "  ${WHITE}Options:${NC}"
    echo -e "  ${CYAN}1)${NC} Edit file (opens in vim/nano)"
    echo -e "  ${CYAN}2)${NC} Apply current file to cluster"
    echo -e "  ${CYAN}3)${NC} View full file"
    echo -e "  ${CYAN}0)${NC} Back"
    echo ""
    
    read -p "  Select action [0-3]: " action
    
    case $action in
        1)
            # Edit with vim or nano
            if command -v vim &> /dev/null; then
                vim "$file"
            elif command -v nano &> /dev/null; then
                nano "$file"
            else
                echo -e "  ${YELLOW}No editor found. File path:${NC}"
                echo -e "  ${CYAN}$file${NC}"
            fi
            
            echo ""
            read -p "  Apply changes to cluster? [Y/n]: " apply_choice
            
            if [[ ! "$apply_choice" =~ ^[Nn]$ ]]; then
                print_action "Applying $type..."
                if kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f "$file" &> /dev/null; then
                    print_ok
                    print_success "$type/$name applied successfully"
                else
                    print_fail
                fi
            fi
            ;;
        2)
            print_action "Applying $type..."
            if kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f "$file" &> /dev/null; then
                print_ok
                print_success "$type/$name applied successfully"
            else
                print_fail
            fi
            ;;
        3)
            echo ""
            cat "$file"
            ;;
        0)
            return 0
            ;;
    esac
}

# ============================================================================
# Main Menu
# ============================================================================

show_main_menu() {
    print_section "Main Menu"
    
    echo -e "  ${WHITE}What would you like to do?${NC}"
    echo ""
    echo -e "  ${WHITE}── Deploy ──${NC}"
    echo -e "  ${GREEN}1)${NC} Install Helm Chart"
    echo -e "  ${GREEN}2)${NC} Install Helm Chart ${CYAN}+ Ingress/Egress Policies${NC}"
    echo -e "  ${YELLOW}3)${NC} Upgrade Helm Chart"
    echo -e "  ${YELLOW}4)${NC} Upgrade Helm Chart ${CYAN}+ Ingress/Egress Updates${NC}"
    echo ""
    echo -e "  ${WHITE}── Uninstall ──${NC}"
    echo -e "  ${MAGENTA}5)${NC} Uninstall Ingress/Egress Policies"
    echo -e "  ${RED}6)${NC} Uninstall Helm Release ${DIM}(Full Cleanup)${NC}"
    echo ""
    echo -e "  ${WHITE}── Status & Policies ──${NC}"
    echo -e "  ${CYAN}7)${NC} Get Pods"
    echo -e "  ${CYAN}8)${NC} Get Service Instances/Bindings"
    echo -e "  ${CYAN}9)${NC} View Ingress/Egress Rules"
    echo -e "  ${BLUE}10)${NC} Edit & Apply Policy Files"
    echo ""
    echo -e "  ${CYAN}0)${NC} Exit"
    echo ""
    
    read -p "  Select option [0-10]: " menu_choice
    
    case $menu_choice in
        1)
            helm_install "false"
            ;;
        2)
            helm_install "true"
            ;;
        3)
            helm_upgrade "false"
            ;;
        4)
            helm_upgrade "true"
            ;;
        5)
            uninstall_policies_menu
            ;;
        6)
            uninstall_helm_menu
            ;;
        7)
            get_pods_menu
            ;;
        8)
            get_services_menu
            ;;
        9)
            view_ingress_egress_rules
            ;;
        10)
            edit_policy_menu
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
    
    # Show configuration
    echo -e "  ${DIM}Configuration:${NC}"
    echo -e "  ${DIM}• Kubeconfig: $KUBECONFIG_PATH${NC}"
    echo -e "  ${DIM}• Chart: $CHART_DIR${NC}"
    echo -e "  ${DIM}• Policies: $INGRESS_EGRESS_DIR${NC}"
    
    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Main loop
    while true; do
        show_main_menu
        echo ""
        read -p "  Press Enter to continue..." _
        clear
        print_banner
    done
}

main "$@"
