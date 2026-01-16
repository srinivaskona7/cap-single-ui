#!/bin/bash
# ============================================================
# CAP Application Deployment Script
# ============================================================
# Interactive deployment script for SAP CAP applications on Kyma
#
# Options:
#   1 - Install/Upgrade Helm release
#   2 - Uninstall Helm release
#   3 - Build Docker images with custom tag & push
#   4 - View Ingress/Egress rules
#   5 - Test egress connectivity (create test pod)
#
# Features:
#   - Prompts for configuration with current values as defaults
#   - Separate ingress and egress policy options
#   - Automatic upgrade detection for existing releases
#   - Docker image build with custom tags
#   - Verification with status indicators
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
TICK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Default Configuration (Update these as needed)
# ============================================================
DEFAULT_KUBECONFIG="$SCRIPT_DIR/kubernetes/admin-sa-token.yaml"
DEFAULT_NAMESPACE="sri"
DEFAULT_RELEASE_NAME="singleui"
DEFAULT_DOMAIN="c-3f6e6b4.kyma.ondemand.com"
DEFAULT_REGISTRY="docker.io/sriniv7654"
DEFAULT_IMAGE_TAG="latest"
DEFAULT_INSTALL_INGRESS="yes"
DEFAULT_INSTALL_EGRESS="yes"

# ============================================================
# Helper Functions
# ============================================================
print_header() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[$1]${NC} $2"
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    echo -ne "${YELLOW}$prompt${NC} [${GREEN}$default${NC}]: "
    read -r input
    if [ -z "$input" ]; then
        eval "$varname='$default'"
    else
        eval "$varname='$input'"
    fi
}

wait_with_spinner() {
    local duration=$1
    local message=$2
    echo -ne "$message "
    for ((i=1; i<=duration; i++)); do
        echo -ne "."
        sleep 1
    done
    echo ""
}

# ============================================================
# Main Menu
# ============================================================
print_header "CAP Application Deployment Tool"

echo -e "${MAGENTA}Select an option:${NC}"
echo ""
echo -e "  ${GREEN}1${NC} - Install / Upgrade Helm release"
echo -e "  ${RED}2${NC} - Uninstall Helm release"
echo -e "  ${BLUE}3${NC} - Build Docker images with custom tag & push"
echo -e "  ${CYAN}4${NC} - View Ingress / Egress rules"
echo -e "  ${MAGENTA}5${NC} - Test egress connectivity (create test pod)"
echo ""
echo -ne "${YELLOW}Enter your choice (1/2/3/4/5)${NC}: "
read -r MENU_CHOICE

case $MENU_CHOICE in
    1) ACTION="install" ;;
    2) ACTION="uninstall" ;;
    3) ACTION="build" ;;
    4) ACTION="view_rules" ;;
    5) ACTION="test_egress" ;;
    *)
        echo -e "${CROSS} Invalid option. Exiting."
        exit 1
        ;;
esac

# ============================================================
# Common Configuration Prompts
# ============================================================
print_header "Configuration"

echo -e "${YELLOW}Press Enter to accept default values shown in [green]${NC}"
echo ""

prompt_with_default "Kubeconfig file path" "$DEFAULT_KUBECONFIG" "KUBECONFIG_PATH"

# Validate Kubeconfig
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo -e "${CROSS} Kubeconfig not found at: $KUBECONFIG_PATH"
    exit 1
fi

KUBECTL="kubectl --kubeconfig=$KUBECONFIG_PATH"

# Test cluster connection
if ! $KUBECTL cluster-info &>/dev/null; then
    echo -e "${CROSS} Cannot connect to cluster"
    exit 1
fi
echo -e "${TICK} Cluster connection successful"
echo ""

prompt_with_default "Target namespace" "$DEFAULT_NAMESPACE" "NAMESPACE"
prompt_with_default "Helm release name" "$DEFAULT_RELEASE_NAME" "RELEASE_NAME"
prompt_with_default "Kyma domain" "$DEFAULT_DOMAIN" "DOMAIN"
prompt_with_default "Container registry" "$DEFAULT_REGISTRY" "REGISTRY"

# ============================================================
# Action: Build Docker Images
# ============================================================
if [ "$ACTION" == "build" ]; then
    print_header "Build Docker Images"
    
    prompt_with_default "Image tag (e.g., v1.0.0, latest)" "$DEFAULT_IMAGE_TAG" "IMAGE_TAG"
    
    echo ""
    echo -e "${BLUE}Images to build:${NC}"
    echo "  - $REGISTRY/single-srv:$IMAGE_TAG"
    echo "  - $REGISTRY/single-approuter:$IMAGE_TAG"
    echo "  - $REGISTRY/single-hana-deployer:$IMAGE_TAG"
    echo "  - $REGISTRY/single-html5-deployer:$IMAGE_TAG"
    echo ""
    
    echo -ne "${YELLOW}Proceed with build and push? (y/n)${NC}: "
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Update containerize.yaml with new tag
    print_step "1/4" "Updating containerize.yaml..."
    if [ -f "$SCRIPT_DIR/containerize.yaml" ]; then
        sed -i.bak \
            -e "s|^repository:.*|repository: $REGISTRY|g" \
            -e "s|^tag:.*|tag: $IMAGE_TAG|g" \
            "$SCRIPT_DIR/containerize.yaml"
        rm -f "$SCRIPT_DIR/containerize.yaml.bak"
        echo -e "      ${TICK} containerize.yaml updated"
    fi
    
    # Update chart/values.yaml with new tag
    print_step "2/4" "Updating chart/values.yaml..."
    if [ -f "$SCRIPT_DIR/chart/values.yaml" ]; then
        sed -i.bak \
            -e "s|registry:.*|registry: $REGISTRY|g" \
            -e "s|tag:.*|tag: $IMAGE_TAG|g" \
            "$SCRIPT_DIR/chart/values.yaml"
        rm -f "$SCRIPT_DIR/chart/values.yaml.bak"
        echo -e "      ${TICK} chart/values.yaml updated"
    fi
    
    # Run ctz containerize.yaml
    print_step "3/4" "Building and pushing images..."
    cd "$SCRIPT_DIR"
    
    if command -v ctz &>/dev/null; then
        echo "Running: ctz containerize.yaml --push"
        ctz containerize.yaml --push
        echo -e "      ${TICK} Images built and pushed"
    else
        echo -e "      ${WARN} 'ctz' command not found. Building manually..."
        
        # Manual Docker build
        echo "Building single-srv..."
        docker build -t "$REGISTRY/single-srv:$IMAGE_TAG" -f srv/Dockerfile .
        
        echo "Building single-approuter..."
        docker build -t "$REGISTRY/single-approuter:$IMAGE_TAG" -f app/router/Dockerfile .
        
        echo "Building single-hana-deployer..."
        docker build -t "$REGISTRY/single-hana-deployer:$IMAGE_TAG" -f db/Dockerfile .
        
        echo "Building single-html5-deployer..."
        docker build -t "$REGISTRY/single-html5-deployer:$IMAGE_TAG" -f app/html5-deployer/Dockerfile .
        
        # Push images
        print_step "4/4" "Pushing images..."
        docker push "$REGISTRY/single-srv:$IMAGE_TAG"
        docker push "$REGISTRY/single-approuter:$IMAGE_TAG"
        docker push "$REGISTRY/single-hana-deployer:$IMAGE_TAG"
        docker push "$REGISTRY/single-html5-deployer:$IMAGE_TAG"
        
        echo -e "      ${TICK} Images pushed"
    fi
    
    print_header "Build Complete"
    echo -e "${TICK} Images built and pushed with tag: ${GREEN}$IMAGE_TAG${NC}"
    echo -e "${TICK} Configuration files updated"
    echo ""
    echo -e "Next: Run this script again and choose option ${GREEN}1${NC} to deploy"
    exit 0
fi

# ============================================================
# Action: View Ingress/Egress Rules
# ============================================================
if [ "$ACTION" == "view_rules" ]; then
    print_header "View Ingress / Egress Rules"
    
    echo -e "${MAGENTA}Select scope:${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC} - Cluster-wide rules (istio-system)"
    echo -e "  ${BLUE}2${NC} - Namespace-specific rules"
    echo ""
    echo -ne "${YELLOW}Enter your choice (1/2)${NC}: "
    read -r SCOPE_CHOICE
    
    case $SCOPE_CHOICE in
        1) RULE_SCOPE="cluster" ;;
        2) RULE_SCOPE="namespace" ;;
        *)
            echo -e "${CROSS} Invalid option. Exiting."
            exit 1
            ;;
    esac
    
    if [ "$RULE_SCOPE" == "namespace" ]; then
        prompt_with_default "Target namespace" "$DEFAULT_NAMESPACE" "TARGET_NS"
    else
        TARGET_NS="istio-system"
    fi
    
    # ========== INGRESS RULES ==========
    print_header "Ingress Rules"
    
    if [ "$RULE_SCOPE" == "cluster" ]; then
        echo -e "${CYAN}Cluster-wide AuthorizationPolicies (istio-system):${NC}"
        echo "---"
        $KUBECTL get authorizationpolicy -n istio-system 2>/dev/null || echo "No AuthorizationPolicies found"
        
        echo ""
        echo -e "${CYAN}Details:${NC}"
        
        # Get IP allowlist details
        AP_NAME=$($KUBECTL get authorizationpolicy -n istio-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$AP_NAME" ]; then
            echo ""
            echo -e "${BLUE}Policy: $AP_NAME${NC}"
            
            # Get action
            ACTION_TYPE=$($KUBECTL get authorizationpolicy -n istio-system "$AP_NAME" -o jsonpath='{.spec.action}' 2>/dev/null)
            echo -e "  Action: ${GREEN}$ACTION_TYPE${NC}"
            
            # Get selector
            SELECTOR=$($KUBECTL get authorizationpolicy -n istio-system "$AP_NAME" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
            echo -e "  Selector: $SELECTOR"
            
            # Get IP blocks
            echo -e "  ${YELLOW}Allowed IPs:${NC}"
            IP_BLOCKS=$($KUBECTL get authorizationpolicy -n istio-system "$AP_NAME" -o jsonpath='{.spec.rules[*].from[*].source.ipBlocks[*]}' 2>/dev/null)
            for ip in $IP_BLOCKS; do
                echo -e "    - ${GREEN}$ip${NC}"
            done
        fi
    else
        echo -e "${CYAN}AuthorizationPolicies in namespace '$TARGET_NS':${NC}"
        echo "---"
        $KUBECTL get authorizationpolicy -n "$TARGET_NS" 2>/dev/null || echo "No AuthorizationPolicies found"
        
        echo ""
        # List all policies with details
        for AP in $($KUBECTL get authorizationpolicy -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            echo -e "${BLUE}Policy: $AP${NC}"
            ACTION_TYPE=$($KUBECTL get authorizationpolicy -n "$TARGET_NS" "$AP" -o jsonpath='{.spec.action}' 2>/dev/null)
            echo -e "  Action: ${GREEN}${ACTION_TYPE:-ALLOW}${NC}"
        done
    fi
    
    # ========== EGRESS RULES ==========
    print_header "Egress Rules"
    
    if [ "$RULE_SCOPE" == "cluster" ]; then
        echo -e "${CYAN}Cluster-wide Sidecar (Egress Policy):${NC}"
        echo "---"
        $KUBECTL get sidecar -n istio-system 2>/dev/null || echo "No Sidecar resources found"
        
        # Get outbound traffic policy
        SIDECAR_NAME=$($KUBECTL get sidecar -n istio-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$SIDECAR_NAME" ]; then
            echo ""
            echo -e "${BLUE}Sidecar: $SIDECAR_NAME${NC}"
            OTP_MODE=$($KUBECTL get sidecar -n istio-system "$SIDECAR_NAME" -o jsonpath='{.spec.outboundTrafficPolicy.mode}' 2>/dev/null)
            echo -e "  Outbound Traffic Policy: ${YELLOW}$OTP_MODE${NC}"
            
            if [ "$OTP_MODE" == "REGISTRY_ONLY" ]; then
                echo -e "  ${WARN} All egress blocked except for ServiceEntry domains"
            else
                echo -e "  ${TICK} All egress allowed"
            fi
        fi
        
        echo ""
        echo -e "${CYAN}ServiceEntries (Allowed Egress Domains):${NC}"
        echo "---"
        $KUBECTL get serviceentry -n istio-system 2>/dev/null || echo "No ServiceEntries found"
        
        # Get ServiceEntry details
        for SE in $($KUBECTL get serviceentry -n istio-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            echo ""
            echo -e "${BLUE}ServiceEntry: $SE${NC}"
            echo -e "  ${YELLOW}Allowed Domains:${NC}"
            HOSTS=$($KUBECTL get serviceentry -n istio-system "$SE" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
            for host in $HOSTS; do
                echo -e "    - ${GREEN}$host${NC}"
            done
            
            PORTS=$($KUBECTL get serviceentry -n istio-system "$SE" -o jsonpath='{.spec.ports[*].number}' 2>/dev/null)
            echo -e "  Ports: $PORTS"
        done
    else
        echo -e "${CYAN}Sidecar resources in namespace '$TARGET_NS':${NC}"
        echo "---"
        $KUBECTL get sidecar -n "$TARGET_NS" 2>/dev/null || echo "No Sidecar resources found"
        
        echo ""
        echo -e "${CYAN}ServiceEntries in namespace '$TARGET_NS':${NC}"
        echo "---"
        $KUBECTL get serviceentry -n "$TARGET_NS" 2>/dev/null || echo "No ServiceEntries found"
        
        # Get ServiceEntry details
        for SE in $($KUBECTL get serviceentry -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            echo ""
            echo -e "${BLUE}ServiceEntry: $SE${NC}"
            HOSTS=$($KUBECTL get serviceentry -n "$TARGET_NS" "$SE" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
            echo -e "  Hosts: $HOSTS"
        done
    fi
    
    # ========== VIRTUAL SERVICES ==========
    if [ "$RULE_SCOPE" == "namespace" ]; then
        print_header "Virtual Services (Ingress Routes)"
        
        echo -e "${CYAN}VirtualServices in namespace '$TARGET_NS':${NC}"
        echo "---"
        $KUBECTL get virtualservice -n "$TARGET_NS" 2>/dev/null || echo "No VirtualServices found"
        
        echo ""
        for VS in $($KUBECTL get virtualservice -n "$TARGET_NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            echo -e "${BLUE}VirtualService: $VS${NC}"
            HOSTS=$($KUBECTL get virtualservice -n "$TARGET_NS" "$VS" -o jsonpath='{.spec.hosts[*]}' 2>/dev/null)
            echo -e "  Hosts: ${GREEN}$HOSTS${NC}"
        done
    fi
    
    print_header "Done"
    exit 0
fi

# ============================================================
# Action: Test Egress Connectivity
# ============================================================
if [ "$ACTION" == "test_egress" ]; then
    print_header "Test Egress Connectivity"
    
    prompt_with_default "Target namespace for test pod" "$DEFAULT_NAMESPACE" "TEST_NS"
    
    TEST_POD_NAME="egress-tester"
    
    # Check if namespace exists
    if ! $KUBECTL get namespace "$TEST_NS" &>/dev/null; then
        echo -e "${CROSS} Namespace '$TEST_NS' does not exist"
        exit 1
    fi
    
    # Check if test pod already exists
    if $KUBECTL get pod "$TEST_POD_NAME" -n "$TEST_NS" &>/dev/null; then
        echo -e "${TICK} Test pod '$TEST_POD_NAME' already exists in namespace '$TEST_NS'"
        echo ""
        echo -e "${MAGENTA}Options:${NC}"
        echo -e "  ${GREEN}1${NC} - Use existing pod"
        echo -e "  ${RED}2${NC} - Delete and recreate"
        echo -e "  ${BLUE}3${NC} - Delete pod and exit"
        echo ""
        echo -ne "${YELLOW}Enter your choice (1/2/3)${NC}: "
        read -r POD_CHOICE
        
        case $POD_CHOICE in
            1) echo -e "${TICK} Using existing pod" ;;
            2)
                echo "Deleting existing pod..."
                $KUBECTL delete pod "$TEST_POD_NAME" -n "$TEST_NS" --wait=true
                echo "Creating new pod..."
                $KUBECTL run "$TEST_POD_NAME" --image=curlimages/curl:latest -n "$TEST_NS" --restart=Never -- sleep infinity
                echo "Waiting for pod to be ready..."
                $KUBECTL wait --for=condition=Ready pod/"$TEST_POD_NAME" -n "$TEST_NS" --timeout=60s
                echo -e "${TICK} Pod recreated"
                ;;
            3)
                echo "Deleting pod..."
                $KUBECTL delete pod "$TEST_POD_NAME" -n "$TEST_NS"
                echo -e "${TICK} Pod deleted"
                exit 0
                ;;
            *)
                echo -e "${CROSS} Invalid option"
                exit 1
                ;;
        esac
    else
        echo "Creating test pod '$TEST_POD_NAME'..."
        $KUBECTL run "$TEST_POD_NAME" --image=curlimages/curl:latest -n "$TEST_NS" --restart=Never -- sleep infinity
        echo "Waiting for pod to be ready..."
        $KUBECTL wait --for=condition=Ready pod/"$TEST_POD_NAME" -n "$TEST_NS" --timeout=60s
        echo -e "${TICK} Pod created and ready"
    fi
    
    # Domain testing menu
    while true; do
        print_header "Domain Connectivity Test"
        
        echo -e "${MAGENTA}Test Options:${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC} - Test a custom domain"
        echo -e "  ${BLUE}2${NC} - Test SAP BTP services (predefined)"
        echo -e "  ${CYAN}3${NC} - Test external domains (should be blocked)"
        echo -e "  ${YELLOW}4${NC} - Exec into pod (interactive shell)"
        echo -e "  ${RED}5${NC} - Delete test pod and exit"
        echo -e "  ${MAGENTA}6${NC} - Exit without deleting pod"
        echo ""
        echo -ne "${YELLOW}Enter your choice (1-6)${NC}: "
        read -r TEST_CHOICE
        
        case $TEST_CHOICE in
            1)
                echo -ne "${YELLOW}Enter domain to test (e.g., google.com)${NC}: "
                read -r CUSTOM_DOMAIN
                echo ""
                echo "Testing https://$CUSTOM_DOMAIN..."
                RESULT=$($KUBECTL exec -n "$TEST_NS" "$TEST_POD_NAME" -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$CUSTOM_DOMAIN" 2>&1) || RESULT="000"
                
                if [ "$RESULT" == "000" ]; then
                    echo -e "  $CUSTOM_DOMAIN: ${RED}BLOCKED${NC} (connection failed)"
                else
                    echo -e "  $CUSTOM_DOMAIN: ${GREEN}$RESULT${NC}"
                fi
                echo ""
                ;;
            2)
                echo ""
                echo -e "${BLUE}Testing SAP BTP Services:${NC}"
                echo "---"
                
                SAP_DOMAINS=(
                    "accounts.sap.com"
                    "authentication.us10.hana.ondemand.com"
                    "destination-configuration.cfapps.us10.hana.ondemand.com"
                    "html5-apps-repo-rt.cfapps.us10.hana.ondemand.com"
                )
                
                for domain in "${SAP_DOMAINS[@]}"; do
                    RESULT=$($KUBECTL exec -n "$TEST_NS" "$TEST_POD_NAME" -- curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$domain" 2>&1) || RESULT="000"
                    if [ "$RESULT" == "000" ]; then
                        echo -e "  $domain: ${RED}BLOCKED${NC}"
                    else
                        echo -e "  $domain: ${GREEN}$RESULT${NC} (allowed)"
                    fi
                done
                echo ""
                ;;
            3)
                echo ""
                echo -e "${BLUE}Testing External Domains (should be blocked):${NC}"
                echo "---"
                
                EXT_DOMAINS=(
                    "google.com"
                    "github.com"
                    "httpbin.org"
                    "example.com"
                )
                
                for domain in "${EXT_DOMAINS[@]}"; do
                    RESULT=$($KUBECTL exec -n "$TEST_NS" "$TEST_POD_NAME" -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://$domain" 2>&1) || RESULT="000"
                    if [ "$RESULT" == "000" ]; then
                        echo -e "  $domain: ${GREEN}BLOCKED${NC} ✓ (egress policy working)"
                    else
                        echo -e "  $domain: ${YELLOW}$RESULT${NC} (accessible - check egress policy)"
                    fi
                done
                echo ""
                ;;
            4)
                echo ""
                echo -e "${CYAN}Entering interactive shell in pod...${NC}"
                echo "Type 'exit' to return to menu"
                echo ""
                $KUBECTL exec -it -n "$TEST_NS" "$TEST_POD_NAME" -- /bin/sh
                ;;
            5)
                echo "Deleting test pod..."
                $KUBECTL delete pod "$TEST_POD_NAME" -n "$TEST_NS"
                echo -e "${TICK} Pod deleted"
                exit 0
                ;;
            6)
                echo -e "${TICK} Exiting. Pod '$TEST_POD_NAME' still running in namespace '$TEST_NS'"
                exit 0
                ;;
            *)
                echo -e "${CROSS} Invalid option"
                ;;
        esac
    done
fi

# ============================================================
# Action: Uninstall
# ============================================================
if [ "$ACTION" == "uninstall" ]; then
    print_header "Uninstall Helm Release"
    
    # Check if release exists
    if ! helm list --namespace "$NAMESPACE" --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null | grep -q "$RELEASE_NAME"; then
        echo -e "${WARN} Release '$RELEASE_NAME' not found in namespace '$NAMESPACE'"
        exit 0
    fi
    
    echo -e "${RED}WARNING: This will remove:${NC}"
    echo "  - Helm release: $RELEASE_NAME"
    echo "  - All pods, services, and deployments"
    echo "  - Service instances and bindings"
    echo ""
    
    echo -ne "${YELLOW}Are you sure you want to uninstall? (yes/no)${NC}: "
    read -r confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
    
    print_step "1/3" "Deleting service bindings..."
    $KUBECTL delete servicebindings --all -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    echo -e "      ${TICK} Service bindings deleted"
    
    print_step "2/3" "Deleting service instances..."
    $KUBECTL delete serviceinstances --all -n "$NAMESPACE" --ignore-not-found 2>/dev/null || true
    echo -e "      ${TICK} Service instances deleted"
    
    print_step "3/3" "Uninstalling Helm release..."
    helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" --kubeconfig="$KUBECONFIG_PATH"
    echo -e "      ${TICK} Helm release uninstalled"
    
    print_header "Uninstall Complete"
    echo -e "${TICK} Release '$RELEASE_NAME' has been removed from namespace '$NAMESPACE'"
    exit 0
fi

# ============================================================
# Action: Install / Upgrade
# ============================================================
print_header "Install / Upgrade Configuration"

prompt_with_default "Image tag" "$DEFAULT_IMAGE_TAG" "IMAGE_TAG"
echo ""
echo -e "${MAGENTA}Policy Installation:${NC}"
prompt_with_default "Install INGRESS policy (IP allowlist)? (yes/no)" "$DEFAULT_INSTALL_INGRESS" "INSTALL_INGRESS"
prompt_with_default "Install EGRESS policy (REGISTRY_ONLY + ServiceEntry)? (yes/no)" "$DEFAULT_INSTALL_EGRESS" "INSTALL_EGRESS"

# Derived values
APPROUTER_URL="https://${RELEASE_NAME}-approuter-${NAMESPACE}.${DOMAIN}"
SRV_URL="https://${RELEASE_NAME}-srv-${NAMESPACE}.${DOMAIN}"
REDIRECT_URI="${APPROUTER_URL}/**"

# Check if release already exists
RELEASE_EXISTS=false
if helm list --namespace "$NAMESPACE" --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null | grep -q "$RELEASE_NAME"; then
    RELEASE_EXISTS=true
    echo ""
    echo -e "${WARN} Release '$RELEASE_NAME' already exists - will perform UPGRADE"
fi

# ============================================================
# Display Configuration Summary
# ============================================================
print_header "Configuration Summary"

echo -e "  Kubeconfig:       ${GREEN}$KUBECONFIG_PATH${NC}"
echo -e "  Namespace:        ${GREEN}$NAMESPACE${NC}"
echo -e "  Release Name:     ${GREEN}$RELEASE_NAME${NC}"
echo -e "  Domain:           ${GREEN}$DOMAIN${NC}"
echo -e "  Registry:         ${GREEN}$REGISTRY${NC}"
echo -e "  Image Tag:        ${GREEN}$IMAGE_TAG${NC}"
echo -e "  Redirect URI:     ${GREEN}$REDIRECT_URI${NC}"
echo -e "  Approuter URL:    ${GREEN}$APPROUTER_URL${NC}"
echo -e "  SRV URL:          ${GREEN}$SRV_URL${NC}"
echo ""
echo -e "  Install Ingress:  ${GREEN}$INSTALL_INGRESS${NC}"
echo -e "  Install Egress:   ${GREEN}$INSTALL_EGRESS${NC}"
echo ""
if [ "$RELEASE_EXISTS" = true ]; then
    echo -e "  Action:           ${YELLOW}UPGRADE${NC}"
else
    echo -e "  Action:           ${GREEN}INSTALL${NC}"
fi
echo ""

echo -ne "${YELLOW}Proceed with these settings? (y/n)${NC}: "
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ============================================================
# Update Configuration Files
# ============================================================
print_header "Updating Configuration Files"

# Update xs-security.json
print_step "1/4" "Updating xs-security.json..."
if [ -f "$SCRIPT_DIR/xs-security.json" ]; then
    # Create temp file with updated redirect URI
    cat "$SCRIPT_DIR/xs-security.json" | \
        sed "s|https://.*-approuter-.*\\..*\\.kyma\\.ondemand\\.com/\\*\\*|$REDIRECT_URI|g" > \
        "$SCRIPT_DIR/xs-security.json.tmp"
    mv "$SCRIPT_DIR/xs-security.json.tmp" "$SCRIPT_DIR/xs-security.json"
    echo -e "      ${TICK} xs-security.json updated"
else
    echo -e "      ${WARN} xs-security.json not found, skipping"
fi

# Update chart/values.yaml
print_step "2/4" "Updating chart/values.yaml..."
if [ -f "$SCRIPT_DIR/chart/values.yaml" ]; then
    sed -i.bak \
        -e "s|domain:.*|domain: $DOMAIN|g" \
        -e "s|registry:.*|registry: $REGISTRY|g" \
        -e "s|tag:.*|tag: $IMAGE_TAG|g" \
        "$SCRIPT_DIR/chart/values.yaml"
    
    # Update redirect URIs
    sed -i.bak "s|https://.*-approuter-.*\\..*\\.kyma\\.ondemand\\.com/\\*\\*|$REDIRECT_URI|g" "$SCRIPT_DIR/chart/values.yaml"
    sed -i.bak "s|https://.*-approuter-.*\\..*\\.kyma\\.ondemand\\.com/login/callback|${APPROUTER_URL}/login/callback|g" "$SCRIPT_DIR/chart/values.yaml"
    
    rm -f "$SCRIPT_DIR/chart/values.yaml.bak"
    echo -e "      ${TICK} chart/values.yaml updated"
else
    echo -e "      ${CROSS} chart/values.yaml not found"
    exit 1
fi

# Update containerize.yaml
print_step "3/4" "Updating containerize.yaml..."
if [ -f "$SCRIPT_DIR/containerize.yaml" ]; then
    sed -i.bak \
        -e "s|^repository:.*|repository: $REGISTRY|g" \
        -e "s|^tag:.*|tag: $IMAGE_TAG|g" \
        "$SCRIPT_DIR/containerize.yaml"
    rm -f "$SCRIPT_DIR/containerize.yaml.bak"
    echo -e "      ${TICK} containerize.yaml updated"
else
    echo -e "      ${WARN} containerize.yaml not found, skipping"
fi

echo -e "      ${TICK} Configuration files updated"

# ============================================================
# Build Application
# ============================================================
print_header "Building Application"

print_step "4/4" "Running cds build --production..."
cd "$SCRIPT_DIR"
if cds build --production; then
    echo -e "      ${TICK} Build completed successfully"
else
    echo -e "      ${CROSS} Build failed"
    exit 1
fi

# ============================================================
# Create/Verify Namespace
# ============================================================
print_header "Preparing Namespace"

if $KUBECTL get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${TICK} Namespace '$NAMESPACE' exists"
else
    echo -e "${WARN} Creating namespace '$NAMESPACE'..."
    $KUBECTL create namespace "$NAMESPACE"
    echo -e "${TICK} Namespace '$NAMESPACE' created"
fi

# Enable Istio injection
if $KUBECTL get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null | grep -q "enabled"; then
    echo -e "${TICK} Istio injection already enabled"
else
    $KUBECTL label namespace "$NAMESPACE" istio-injection=enabled --overwrite
    echo -e "${TICK} Istio injection enabled"
fi

# ============================================================
# Install/Upgrade Helm Release
# ============================================================
print_header "Deploying Application"

if [ "$RELEASE_EXISTS" = true ]; then
    echo -e "${YELLOW}Upgrading${NC} release '$RELEASE_NAME'..."
    helm upgrade "$RELEASE_NAME" ./gen/chart \
        --namespace "$NAMESPACE" \
        --kubeconfig="$KUBECONFIG_PATH" \
        --wait --timeout 5m
    echo -e "${TICK} Helm upgrade complete"
else
    echo "Installing new release '$RELEASE_NAME'..."
    helm install "$RELEASE_NAME" ./gen/chart \
        --namespace "$NAMESPACE" \
        --kubeconfig="$KUBECONFIG_PATH" \
        --wait --timeout 5m
    echo -e "${TICK} Helm install complete"
fi

# ============================================================
# Install Ingress Policy (Optional)
# ============================================================
if [[ "$INSTALL_INGRESS" =~ ^[Yy] ]]; then
    print_header "Installing Ingress Policy"
    
    if [ -f "$SCRIPT_DIR/ingress-egress/03-ingress-ip-allowlist.yaml" ]; then
        $KUBECTL apply -f "$SCRIPT_DIR/ingress-egress/03-ingress-ip-allowlist.yaml" 2>/dev/null || true
        echo -e "${TICK} Ingress IP Allowlist applied"
    else
        echo -e "${WARN} Ingress policy file not found, skipping"
    fi
else
    echo ""
    echo -e "${WARN} Ingress policy installation: ${RED}SKIPPED${NC}"
fi

# ============================================================
# Install Egress Policy (Optional)
# ============================================================
if [[ "$INSTALL_EGRESS" =~ ^[Yy] ]]; then
    print_header "Installing Egress Policy"
    
    if [ -f "$SCRIPT_DIR/ingress-egress/01-egress-sidecar.yaml" ]; then
        $KUBECTL apply -f "$SCRIPT_DIR/ingress-egress/01-egress-sidecar.yaml" 2>/dev/null || true
        echo -e "${TICK} Egress Sidecar (REGISTRY_ONLY) applied"
    fi
    
    if [ -f "$SCRIPT_DIR/ingress-egress/02-egress-serviceentry.yaml" ]; then
        $KUBECTL apply -f "$SCRIPT_DIR/ingress-egress/02-egress-serviceentry.yaml" 2>/dev/null || true
        echo -e "${TICK} Egress ServiceEntry (SAP BTP) applied"
    fi
    
    if [ ! -f "$SCRIPT_DIR/ingress-egress/01-egress-sidecar.yaml" ] && [ ! -f "$SCRIPT_DIR/ingress-egress/02-egress-serviceentry.yaml" ]; then
        echo -e "${WARN} Egress policy files not found, skipping"
    fi
else
    echo ""
    echo -e "${WARN} Egress policy installation: ${RED}SKIPPED${NC}"
fi

# ============================================================
# Wait for Deployment
# ============================================================
print_header "Waiting for Deployment (60 seconds)"
wait_with_spinner 60 "Waiting for pods to be ready"

# ============================================================
# Verification
# ============================================================
print_header "Deployment Verification"

# Check Pods
echo ""
echo -e "${BLUE}Pods:${NC}"
echo "---"
$KUBECTL get pods -n "$NAMESPACE" -o wide 2>/dev/null

# Count running pods
running_pods=$($KUBECTL get pods -n "$NAMESPACE" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
total_pods=$($KUBECTL get pods -n "$NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')

echo ""
if [ "$running_pods" -gt 0 ]; then
    echo -e "${TICK} Pods: ${GREEN}$running_pods/$total_pods running${NC}"
else
    echo -e "${CROSS} Pods: ${RED}No running pods${NC}"
fi

# Check Service Instances
echo ""
echo -e "${BLUE}Service Instances:${NC}"
echo "---"
$KUBECTL get serviceinstances -n "$NAMESPACE" 2>/dev/null || echo "No service instances found"

ready_si=$($KUBECTL get serviceinstances -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.ready==true)].metadata.name}' 2>/dev/null | wc -w | tr -d ' ')
total_si=$($KUBECTL get serviceinstances -n "$NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')

echo ""
if [ "$ready_si" -gt 0 ]; then
    echo -e "${TICK} Service Instances: ${GREEN}$ready_si/$total_si ready${NC}"
else
    echo -e "${WARN} Service Instances: ${YELLOW}Waiting for provisioning${NC}"
fi

# Check Service Bindings
echo ""
echo -e "${BLUE}Service Bindings:${NC}"
echo "---"
$KUBECTL get servicebindings -n "$NAMESPACE" 2>/dev/null || echo "No service bindings found"

ready_sb=$($KUBECTL get servicebindings -n "$NAMESPACE" -o jsonpath='{.items[?(@.status.ready==true)].metadata.name}' 2>/dev/null | wc -w | tr -d ' ')
total_sb=$($KUBECTL get servicebindings -n "$NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')

echo ""
if [ "$ready_sb" -gt 0 ]; then
    echo -e "${TICK} Service Bindings: ${GREEN}$ready_sb/$total_sb ready${NC}"
else
    echo -e "${WARN} Service Bindings: ${YELLOW}Waiting for creation${NC}"
fi

# ============================================================
# Application URLs
# ============================================================
print_header "Application URLs"

echo -e "${GREEN}Approuter:${NC}  $APPROUTER_URL"
echo -e "${GREEN}SRV:${NC}        $SRV_URL"
echo -e "${GREEN}Health:${NC}     $SRV_URL/health"
echo -e "${GREEN}OData:${NC}      $SRV_URL/odata/v4/catalog/\$metadata"

# ============================================================
# Summary
# ============================================================
print_header "Deployment Summary"

echo -e "  ${TICK} Configuration files updated"
echo -e "  ${TICK} CDS build completed"
echo -e "  ${TICK} Namespace '$NAMESPACE' ready with Istio"

if [ "$RELEASE_EXISTS" = true ]; then
    echo -e "  ${TICK} Helm release '$RELEASE_NAME' upgraded"
else
    echo -e "  ${TICK} Helm release '$RELEASE_NAME' installed"
fi

if [[ "$INSTALL_INGRESS" =~ ^[Yy] ]]; then
    echo -e "  ${TICK} Ingress policy installed"
else
    echo -e "  ${WARN} Ingress policy: skipped"
fi

if [[ "$INSTALL_EGRESS" =~ ^[Yy] ]]; then
    echo -e "  ${TICK} Egress policy installed"
else
    echo -e "  ${WARN} Egress policy: skipped"
fi

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
