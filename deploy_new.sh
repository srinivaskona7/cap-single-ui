#!/bin/bash
set -e

# ==============================================================================
# Configuration & Constants
# ==============================================================================
SBX_DOMAIN="c-9d0a141.kyma.ondemand.com"
SBX_KYMA_DOMAIN="c-9d0a141.kyma.ondemand.com"
SBX_NAMESPACE="kyma-nodejs-demo"
SBX_KUBECONTEXT="appsbx-c-9d0a141"
SBX_KUBECONFIG="/Users/sr20536224wipro.com/Documents/clusters/devsecops/c-9d0a141-sbx.yaml"

DEV_DOMAIN="b1eb3b8.kyma.ondemand.com"
DEV_KYMA_DOMAIN="b1eb3b8.kyma.ondemand.com"
DEV_NAMESPACE="egress"
DEV_KUBECONTEXT="appnewdev-b1eb3b8"

VALUES_FILE="chart/values.yaml"
XS_SECURITY_FILE="xs-security.json"
CONTAINERIZE_FILE="containerize.yaml"
CHART_DIR="gen/chart"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global Variables
ACTION_CHOICE=""
ENV_NAME=""
TARGET_DOMAIN=""
TARGET_KYMA_DOMAIN=""
TARGET_NAMESPACE=""
TARGET_CONTEXT=""
CUSTOM_KUBECONFIG=""
IMAGE_TAG="latest"
REPO_PREFIX=""

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}Interactive CAP Deployment Tool${NC} ${CYAN}(Architect Edition)${NC}                  ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    local missing=0
    
    for tool in helm docker kubectl npx; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed or not in PATH."
            missing=$((missing+1))
        fi
    done

    if [ ! -f "$VALUES_FILE" ]; then
        log_error "$VALUES_FILE not found."
        missing=$((missing+1))
    fi

    if [ ! -f "$XS_SECURITY_FILE" ]; then
        log_error "$XS_SECURITY_FILE not found."
        missing=$((missing+1))
    fi

    if [ $missing -gt 0 ]; then
        echo ""
        log_error "Prerequisites check failed. Please fix issues above."
        exit 1
    fi
    log_success "All prerequisites met."
}

scan_chart_info() {
    if [ -f "$CHART_DIR/Chart.yaml" ]; then
        CHART_NAME=$(grep "^name:" "$CHART_DIR/Chart.yaml" | awk '{print $2}')
        CHART_VER=$(grep "^version:" "$CHART_DIR/Chart.yaml" | awk '{print $2}')
        log_info "Detected Helm Chart: ${BOLD}$CHART_NAME${NC} (v$CHART_VER)"
    else
        log_warn "No generated chart found in $CHART_DIR. It will be created during build."
    fi
}

# ==============================================================================
# User Input Functions
# ==============================================================================

get_user_action() {
    echo ""
    echo -e "${BOLD}Select Action:${NC}"
    echo "  1) Install / Upgrade Release"
    echo "  2) Uninstall Release (Interactive)"
    echo "  3) Package & Push Helm Chart (OCI Only)"
    echo "  4) Build & Push Docker Images Only"
    echo "  5) Update Configuration Only (No Deploy)"
    echo "  6) Optimize Resources (Minimal Profile) & Build"
    echo "  7) Build New Chart (Images + Helm OCI)"
    echo "  8) Deploy from OCI Registry (Helm Upgrade)"
    echo ""
    read -p "Enter choice [1-8]: " ACTION_CHOICE
    
    if [[ ! "$ACTION_CHOICE" =~ ^[1-8]$ ]]; then
        log_error "Invalid selection."
        exit 1
    fi
}

configure_environment() {
    echo ""
    echo -e "${BOLD}Select Environment:${NC}"
    echo "  1) SBX (Domain: $SBX_DOMAIN | NS: $SBX_NAMESPACE)"
    echo "  2) DEV (Domain: $DEV_DOMAIN | NS: $DEV_NAMESPACE)"
    echo "  3) Custom (Enter Details Manually)"
    echo ""
    read -p "Enter choice [1-3]: " ENV_CHOICE

    case $ENV_CHOICE in
        1)
            ENV_NAME="sbx"
            TARGET_DOMAIN="$SBX_DOMAIN"
            TARGET_KYMA_DOMAIN="$SBX_KYMA_DOMAIN"
            TARGET_NAMESPACE="$SBX_NAMESPACE"
            TARGET_CONTEXT="$SBX_KUBECONTEXT"
            CUSTOM_KUBECONFIG="$SBX_KUBECONFIG"
            ;;
        2)
            ENV_NAME="dev"
            TARGET_DOMAIN="$DEV_DOMAIN"
            TARGET_KYMA_DOMAIN="$DEV_KYMA_DOMAIN"
            TARGET_NAMESPACE="$DEV_NAMESPACE"
            TARGET_CONTEXT="$DEV_KUBECONTEXT"
            CUSTOM_KUBECONFIG=""
            ;;
        3)
            ENV_NAME="custom"
            echo ""
            # Only prompt for Domain/Kyma if NOT uninstalling (Action 2 only needs Kubeconfig/NS)
            if [ "$ACTION_CHOICE" != "2" ]; then
                read -p "Enter Kyma Domain (e.g., c-xxxx.kyma.ondemand.com): " TARGET_KYMA_DOMAIN
                TARGET_DOMAIN="$TARGET_KYMA_DOMAIN"
            fi
            read -p "Enter Target Namespace: " TARGET_NAMESPACE
            echo "Enter Path to Kubeconfig File:"
            read -e -p "Path > " CUSTOM_KUBECONFIG
            ;;
        *)
            log_error "Invalid environment choice."
            exit 1
            ;;
    esac

    echo ""
    log_info "Selected Environment: ${BOLD}$ENV_NAME${NC}"

    # Set Kubeconfig
    if [ ! -z "$CUSTOM_KUBECONFIG" ]; then
        if [ ! -f "$CUSTOM_KUBECONFIG" ]; then
            log_error "Kubeconfig file not found at: $CUSTOM_KUBECONFIG"
            exit 1
        fi
        log_info "Using explicit Kubeconfig: $CUSTOM_KUBECONFIG"
        export KUBECONFIG="$CUSTOM_KUBECONFIG"
    else
        # Switch context if standard env
        if [ "$ENV_NAME" == "dev" ]; then
            log_info "Switching kubectl context to: $TARGET_CONTEXT"
            kubectl config use-context "$TARGET_CONTEXT" || log_warn "Context switch warning."
            unset KUBECONFIG
        fi
    fi
}

update_configuration_files() {
    # Skip for uninstall (2), chart push specific (3), docker push specific (4).
    # Option 7 needs config update!
    if [[ "$ACTION_CHOICE" =~ ^(2|3|4)$ ]]; then
        return
    fi

    echo ""
    log_info "Updating configuration files..."
    
    # Update chart/values.yaml
    sed -i '' "s/domain: .*/domain: $TARGET_DOMAIN/" "$VALUES_FILE"
    sed -i '' "s|https://single-ui-approuter-[a-zA-Z0-9.-]*|https://single-ui-approuter-$TARGET_NAMESPACE.$TARGET_KYMA_DOMAIN|g" "$VALUES_FILE"

    # Update xs-security.json
    sed -i '' "s|https://single-ui-approuter-[a-zA-Z0-9.-]*|https://single-ui-approuter-$TARGET_NAMESPACE.$TARGET_KYMA_DOMAIN|g" "$XS_SECURITY_FILE"

    log_success "Files updated successfully."
}

# ==============================================================================
# Functional Modules
# ==============================================================================

module_uninstall() {
    echo ""
    echo -e "${RED}${BOLD}--- Interactive Uninstall ---${NC}"
    log_info "Scanning for Helm releases in namespace: $TARGET_NAMESPACE"
    
    if ! helm list -n "$TARGET_NAMESPACE" &> /dev/null; then
        log_error "Failed to list releases. Check cluster connection."
        exit 1
    fi

    TMP_LIST=$(mktemp)
    helm list -n "$TARGET_NAMESPACE" | tail -n +2 > "$TMP_LIST"
    
    if [ ! -s "$TMP_LIST" ]; then
        log_warn "No Helm releases found in namespace '$TARGET_NAMESPACE'."
        rm "$TMP_LIST"
        exit 0
    fi

    echo ""
    echo -e "${BOLD}Available Releases:${NC}"
    
    declare -a RELEASE_NAMES
    local i=0
    
    while IFS= read -r line; do
        i=$((i+1))
        RELEASE_NAMES[$i]=$(echo "$line" | awk '{print $1}')
        echo "  $i) $line"
    done < "$TMP_LIST"
    rm "$TMP_LIST"

    echo ""
    read -p "Select release to uninstall [1-$i]: " REL_IDX
    
    SELECTED_RELEASE=${RELEASE_NAMES[$REL_IDX]}
    
    if [ -z "$SELECTED_RELEASE" ]; then
        log_error "Invalid selection."
        exit 1
    fi

    echo ""
    log_warn "You selected: ${BOLD}$SELECTED_RELEASE${NC}"
    read -p "Are you sure you want to UNINSTALL '$SELECTED_RELEASE'? (y/n): " CONFIRM
    if [ "$CONFIRM" == "y" ]; then
        log_info "Uninstalling..."
        helm uninstall "$SELECTED_RELEASE" -n "$TARGET_NAMESPACE"
        log_success "Cleanup complete."
    else
        log_info "Operation cancelled."
    fi
}

module_package_push() {
    echo ""
    echo -e "${CYAN}${BOLD}--- Helm Chart OCI Push ---${NC}"
    
    DEFAULT_REGISTRY="oci://registry-1.docker.io/sriniv7654"
    if grep -q "repository:" "$CONTAINERIZE_FILE"; then
       REGISTRY_URI="$DEFAULT_REGISTRY" 
    else
       REGISTRY_URI="$DEFAULT_REGISTRY"
    fi

    read -p "Enter Chart Version (e.g., 1.0.0 or 1.0.0-dev): " CHART_VERSION
    if [ -z "$CHART_VERSION" ]; then
        log_error "Version is required."
        exit 1
    fi
    
    if [ ! -d "$CHART_DIR" ]; then
        log_error "Chart directory $CHART_DIR not found. Please build first."
        exit 1
    fi
    
    log_info "Target Registry: $REGISTRY_URI"
    log_info "Updating chart dependencies..."
    helm dependency update "$CHART_DIR"
    
    log_info "Packaging chart version $CHART_VERSION..."
    helm package "$CHART_DIR" --version "$CHART_VERSION"

    PACKAGE_FILE="single-$CHART_VERSION.tgz"
    if [ -f "$PACKAGE_FILE" ]; then
        log_info "Pushing $PACKAGE_FILE..."
        helm push "$PACKAGE_FILE" "$REGISTRY_URI"
        log_success "Chart pushed successfully!"
        
        # Cleanup
        rm "$PACKAGE_FILE"
        log_info "Cleaned up local package: $PACKAGE_FILE"
        
        log_info "Verify command: helm show chart $REGISTRY_URI/single --version $CHART_VERSION"
    else
        log_error "Package file $PACKAGE_FILE failed to generate."
        exit 1
    fi
}

build_and_push_docker() {
    local name=$1
    local dockerfile=$2
    local full_image="$REPO_PREFIX/$name:$IMAGE_TAG"
    
    echo -e "  ${CYAN}Processing: $name${NC}"
    
    if [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile '$dockerfile' not found. Skipping."
        return 1
    fi
    
    # Enforce linux/amd64 for Cloud Compatibility (SAP BTP/Kyma)
    # This ensures images built on Mac M1/M2 (ARM) still run on standard x86 clusters.
    echo "    - Building for linux/amd64 ($dockerfile)..."
    
    # Using --platform linux/amd64
    # Removed quiet flag -q and redirect >/dev/null for verbose output
    if docker build --platform linux/amd64 -t "$full_image" -f "$dockerfile" .; then
        echo "    - Pushing to registry..."
        if docker push "$full_image" | grep -v "Layer already exists"; then
            log_success "Pushed: $full_image"
        else
            log_error "Push failed for $full_image"
            exit 1
        fi
    else
        log_error "Build failed for $name"
        exit 1
    fi
}

prepare_docker_images() {
    # Use shared helper to Prompt Tag -> Update Values -> Build CDS
    execute_build_cycle
    
    echo ""
    echo -e "${CYAN}${BOLD}--- Docker Image Build & Push ---${NC}"
    log_info "Using Tag: ${BOLD}$IMAGE_TAG${NC}"
    
    if [ -f "$CONTAINERIZE_FILE" ]; then
        REPO_PREFIX=$(grep "repository:" "$CONTAINERIZE_FILE" | awk '{print $2}')
    fi
    
    if [ -z "$REPO_PREFIX" ]; then
        log_warn "Could not determine repository from $CONTAINERIZE_FILE. Using default 'docker.io/sriniv7654'."
        REPO_PREFIX="docker.io/sriniv7654"
    fi

    # Configured modules from known containerize structure
    build_and_push_docker "single-srv" "srv/Dockerfile"
    build_and_push_docker "single-approuter" "app/router/Dockerfile"
    build_and_push_docker "single-hana-deployer" "db/Dockerfile"
    build_and_push_docker "single-html5-deployer" "app/html5-deployer/Dockerfile"
}

# Helper for Standard Build Cycle (Prompt -> Update -> Build)
execute_build_cycle() {
    echo ""
    echo -e "${CYAN}${BOLD}--- Prepare Configuration & Artifacts ---${NC}"
    
    read -p "Enter Image Tag (e.g., latest): " INPUT_TAG
    IMAGE_TAG=${INPUT_TAG:-latest}
    
    if [ -f "$VALUES_FILE" ]; then
        sed -i '' "s/tag: .*/tag: $IMAGE_TAG/g" "$VALUES_FILE"
        log_info "Updated tag to '$IMAGE_TAG' in $VALUES_FILE"
    fi
    
    log_info "Building project artifacts (CDS)..."
    npx cds build --production
}

verify_images_optional() {
    echo ""
    read -p "Do you want to verify images in the registry before deploying? (y/n): " DO_VERIFY
    if [ "$DO_VERIFY" != "y" ]; then
        return 0
    fi

    log_info "Verifying image availability in registry..."
    if [ -f "$CONTAINERIZE_FILE" ]; then
        REPO_PREFIX=$(grep "repository:" "$CONTAINERIZE_FILE" | awk '{print $2}')
    else
        REPO_PREFIX="docker.io/sriniv7654"
    fi
    [ -z "$REPO_PREFIX" ] && REPO_PREFIX="docker.io/sriniv7654"

    declare -a IMAGES=("single-srv" "single-approuter" "single-hana-deployer" "single-html5-deployer")
    MISSING_IMAGES=0

    for img_name in "${IMAGES[@]}"; do
        FULL_IMG="$REPO_PREFIX/$img_name:$IMAGE_TAG"
        echo -n "  - Checking $FULL_IMG... "
        if docker manifest inspect "$FULL_IMG" > /dev/null 2>&1; then
            echo -e "${GREEN}Found${NC}"
        else
            echo -e "${RED}Not Found (or Access Denied)${NC}"
            MISSING_IMAGES=$((MISSING_IMAGES + 1))
        fi
    done

    if [ $MISSING_IMAGES -gt 0 ]; then
        echo ""
        log_warn "$MISSING_IMAGES image(s) could not be verified."
        read -p "Do you want to proceed anyway? (y/n): " PROCEED
        if [ "$PROCEED" != "y" ]; then
            log_error "Deployment cancelled."
            exit 1
        fi
    else
        log_success "All images verified."
    fi
}

module_build_deploy() {
    execute_build_cycle
    
    # Optional Verification
    verify_images_optional

    echo ""
    log_info "Deploying Helm Release 'single-ui' with tag: ${BOLD}$IMAGE_TAG${NC}..."

    if [ ! -d "$CHART_DIR" ]; then
        log_error "$CHART_DIR not found. Build likely failed."
        exit 1
    fi

    HELM_CMD="helm upgrade --install single-ui ./gen/chart \
        --set-json 'xsuaa.parameters=$(cat xs-security.json)' \
        --set-string global.image.tag=$IMAGE_TAG \
        --set-string srv.image.tag=$IMAGE_TAG \
        --set-string approuter.image.tag=$IMAGE_TAG \
        --set-string hana-deployer.image.tag=$IMAGE_TAG \
        --set-string html5-apps-deployer.image.tag=$IMAGE_TAG \
        -n $TARGET_NAMESPACE"

    log_info "Executing Helm upgrade..."
    
    if eval $HELM_CMD; then
        echo ""
        log_success "Deployment triggered successfully!"
        
        # Summary Report
        echo ""
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD} Deployment Summary${NC}"
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e " Status       : ${GREEN}SUCCESS${NC}"
        echo -e " Environment  : $ENV_NAME"
        echo -e " Namespace    : $TARGET_NAMESPACE"
        echo -e " Image Tag    : $IMAGE_TAG"
        if [ "$ENV_NAME" != "custom" ]; then
             echo -e " App URL      : https://single-ui-approuter-$TARGET_NAMESPACE.$TARGET_KYMA_DOMAIN"
        fi
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    else
        echo ""
        log_error "Deployment failed."
        exit 1
    fi
}

# ==============================================================================
# Main Execution Flow
# ==============================================================================

print_header
check_prerequisites
scan_chart_info
get_user_action

# Only configure environment if deploying (1), uninstalling (2), or updating config (5)
if [[ "$ACTION_CHOICE" =~ ^(1|2|5)$ ]]; then
    configure_environment
    update_configuration_files
fi

module_update_config() {
    execute_build_cycle
    log_success "Configuration updated and Build complete."
}

module_optimize_resources() {
    echo ""
    echo -e "${CYAN}${BOLD}--- Optimizing Resource Limits (Micro Profile) ---${NC}"
    
    # Check if values file exists
    if [ ! -f "$VALUES_FILE" ]; then
        log_error "$VALUES_FILE not found."
        exit 1
    fi

    log_info "Reducing CPU/Memory requests and limits in $VALUES_FILE to MICRO levels..."
    
    # Replacements for MICRO footprint (Aggressive)
    # Memory Limits: 1G -> 256M, 500M -> 128M
    # Memory Requests: 1G -> 128M, 500M -> 64M
    
    # CPU Limits: 2000m -> 200m, 500m -> 100m
    # CPU Requests: 1000m -> 50m, 500m -> 25m
    
    # We use sed to target the original high values found in the standard chart
    # Note: If values are already small, strict sed might miss them, but this targets default CAP charts.
    
    # Heavy Services (Deployers)
    sed -i '' 's/memory: 1G/memory: 256M/g' "$VALUES_FILE"
    sed -i '' 's/cpu: 2000m/cpu: 200m/g' "$VALUES_FILE"
    sed -i '' 's/cpu: 1000m/cpu: 50m/g' "$VALUES_FILE"
    
    # Light Services (Srv/Approuter)
    # Reducing 500M/500m blocks
    sed -i '' 's/memory: 500M/memory: 128M/g' "$VALUES_FILE"
    sed -i '' 's/cpu: 500m/cpu: 50m/g' "$VALUES_FILE"
    
    # If requests were same as limits (often true in some charts), ensure we hit them.
    # The above commands strictly replace specific strings.
    
    log_success "Resource limits updated to MICRO values (128M/256M Mem, 50m/200m CPU)."
    
    # Run build to persist changes to charts
    log_info "Building project artifacts (CDS)..."
    npx cds build --production
    
    log_success "Optimization and Build complete."
}

module_build_new_chart() {
    echo ""
    echo -e "${CYAN}${BOLD}--- Build Full Release (Images + Chart) ---${NC}"
    
    # Prerequisite Checks
    if [ ! -f "$CONTAINERIZE_FILE" ]; then
        log_error "File not found: $CONTAINERIZE_FILE"
        exit 1
    fi

    # 1. Gather Inputs
    read -p "Enter Image Tag (e.g., 1.0.0-rc1): " INPUT_TAG
    IMAGE_TAG=${INPUT_TAG:-latest}
    
    read -p "Enter Chart Version (e.g., 1.0.0-rc1): " CHART_VERSION
    if [ -z "$CHART_VERSION" ]; then
        log_error "Chart Version is required."
        exit 1
    fi
    
    # 2. Update Configuration & Build CDS
    echo ""
    log_info "Step 1/3: Updating Configuration & Building CDS..."
    if [ -f "$VALUES_FILE" ]; then
        sed -i '' "s/tag: .*/tag: $IMAGE_TAG/g" "$VALUES_FILE"
        log_info "Updated tag to '$IMAGE_TAG' in $VALUES_FILE"
    fi
    log_info "Building project artifacts (CDS)..."
    npx cds build --production

    # 3. Build & Push Docker Images
    echo ""
    log_info "Step 2/3: Building & Pushing Docker Images..."
    if [ -f "$CONTAINERIZE_FILE" ]; then
        REPO_PREFIX=$(grep "repository:" "$CONTAINERIZE_FILE" | awk '{print $2}')
    fi
    [ -z "$REPO_PREFIX" ] && REPO_PREFIX="docker.io/sriniv7654"
    
    build_and_push_docker "single-srv" "srv/Dockerfile"
    build_and_push_docker "single-approuter" "app/router/Dockerfile"
    build_and_push_docker "single-hana-deployer" "db/Dockerfile"
    build_and_push_docker "single-html5-deployer" "app/html5-deployer/Dockerfile"
    
    # 4. Package & Push Helm Chart
    echo ""
    log_info "Step 3/3: Packaging & Pushing Helm Chart..."
    if [ ! -d "$CHART_DIR" ]; then
         log_error "Chart directory not found at $CHART_DIR"
         exit 1
    fi
    
    # Define Registry URI (TODO: Make configurable)
    REGISTRY_URI="oci://registry-1.docker.io/sriniv7654"
    
    # Update Chart.yaml version
    sed -i '' "s/^version: .*/version: $CHART_VERSION/" "$CHART_DIR/Chart.yaml"
    sed -i '' "s/^appVersion: .*/appVersion: \"$CHART_VERSION\"/" "$CHART_DIR/Chart.yaml"
    log_info "Updated Chart.yaml version to $CHART_VERSION"

    # Dependency Update
    helm dependency update "$CHART_DIR"
    
    # Package
    helm package "$CHART_DIR" --version "$CHART_VERSION"
    PACKAGE_FILE="single-$CHART_VERSION.tgz"
    
    if [ -f "$PACKAGE_FILE" ]; then
        log_info "Pushing Chart $PACKAGE_FILE to $REGISTRY_URI..."
        helm push "$PACKAGE_FILE" "$REGISTRY_URI"
        log_success "Full Release Build Complete!"
        
        # Cleanup
        rm "$PACKAGE_FILE"
        log_info "Cleaned up local package: $PACKAGE_FILE"
        
        log_info "Artifacts:"
        log_info "  - Images Tag: $IMAGE_TAG"
        log_info "  - Chart Ver : $CHART_VERSION"
    else
        log_error "Chart packaging failed."
        exit 1
    fi
}

module_deploy_from_oci() {
    echo ""
    echo -e "${CYAN}${BOLD}--- Deploy from OCI Registry ---${NC}"
    
    # 1. Fetch Versions
    log_info "Fetching available versions from Docker Hub..."
    API_URL="https://hub.docker.com/v2/repositories/sriniv7654/single/tags/?page_size=10"
    
    declare -a VERSION_ARRAY=()
    
    if command -v curl >/dev/null && command -v node >/dev/null; then
        VERSIONS_JSON=$(curl -s "$API_URL")
        # Use node to parse JSON safely into a space-separated string
        VERSIONS_STR=$(echo "$VERSIONS_JSON" | node -e '
            try {
                const input = require("fs").readFileSync(0, "utf-8");
                const data = JSON.parse(input);
                if (data.results) {
                    console.log(data.results.map(r => r.name).join(" "));
                }
            } catch (e) {}
        ')
        # Convert to array
        IFS=' ' read -r -a VERSION_ARRAY <<< "$VERSIONS_STR"
    fi
    
    echo ""
    if [ ${#VERSION_ARRAY[@]} -gt 0 ]; then
        echo -e "${BOLD}Available Versions:${NC}"
        local idx=1
        for ver in "${VERSION_ARRAY[@]}"; do
            echo "  $idx) $ver"
            ((idx++))
        done
        echo "  0) Type Manually"
        
        echo ""
        read -p "Select Version [1-${#VERSION_ARRAY[@]}]: " V_CHOICE
        
        if [[ "$V_CHOICE" =~ ^[0-9]+$ ]] && [ "$V_CHOICE" -gt 0 ] && [ "$V_CHOICE" -le "${#VERSION_ARRAY[@]}" ]; then
            # Array is 0-indexed, choice is 1-indexed
            CHART_VERSION="${VERSION_ARRAY[$((V_CHOICE-1))]}"
            echo "Selected: $CHART_VERSION"
        elif [ "$V_CHOICE" == "0" ]; then
             read -p "Enter Manual Version: " CHART_VERSION
        else
             log_error "Invalid selection."
             exit 1
        fi
    else
        log_warn "Could not auto-fetch versions."
        read -p "Enter Chart Version to Deploy: " CHART_VERSION
    fi
    
    if [ -z "$CHART_VERSION" ]; then
        log_error "Version is required."
        exit 1
    fi
    
    # 2. Configure Parameters
    echo ""
    read -p "Release Name [single-ui]: " RELEASE_NAME
    RELEASE_NAME=${RELEASE_NAME:-single-ui}
    
    read -p "Target Namespace [srii]: " TARGET_NAMESPACE
    TARGET_NAMESPACE=${TARGET_NAMESPACE:-srii}
    
    echo "Enter Path to Kubeconfig File:"
    read -e -p "Path > " CUSTOM_KUBECONFIG
    
    if [ -z "$CUSTOM_KUBECONFIG" ] || [ ! -f "$CUSTOM_KUBECONFIG" ]; then
        log_error "Valid Kubeconfig path is required."
        exit 1
    fi
    
    # 3. Deploy
    echo ""
    log_info "Deploying ${BOLD}$RELEASE_NAME${NC} (v$CHART_VERSION) to namespace '${BOLD}$TARGET_NAMESPACE${NC}'..."
    
    # Check xs-security.json
    if [ ! -f "$XS_SECURITY_FILE" ]; then
        log_error "$XS_SECURITY_FILE not found in current directory."
        exit 1
    fi
    
    REGISTRY_URI="oci://registry-1.docker.io/sriniv7654/single"
    
    HELM_CMD="helm -n $TARGET_NAMESPACE upgrade --install $RELEASE_NAME $REGISTRY_URI \
        --version $CHART_VERSION \
        --kubeconfig $CUSTOM_KUBECONFIG \
        --set-json 'xsuaa.parameters=$(cat $XS_SECURITY_FILE)'"
        
    echo "Executing Helm upgrade..."
    
    if eval $HELM_CMD; then
        echo ""
        log_success "Deployment Request Sent Successfully!"
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e " Release      : $RELEASE_NAME"
        echo -e " Version      : $CHART_VERSION"
        echo -e " Namespace    : $TARGET_NAMESPACE"
        echo -e " Status       : ${GREEN}Deployed${NC}"
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    else
        echo ""
        log_error "Deployment failed."
        exit 1
    fi
}

case $ACTION_CHOICE in
    1) module_build_deploy ;;
    2) module_uninstall ;;
    3) module_package_push ;;
    4) prepare_docker_images ;;
    5) module_update_config ;;
    6) module_optimize_resources ;;
    7) module_build_new_chart ;;
    8) module_deploy_from_oci ;;
esac
