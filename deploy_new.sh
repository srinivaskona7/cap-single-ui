#!/bin/bash
set -e

# Configuration Constants
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
REGISTRY_URI="oci://registry-1.docker.io/sriniv7654"

echo "============================================================"
echo "      Interactive CAP Deployment Tool (Enhanced)"
echo "============================================================"

# --- 1. Action Selection ---
echo "Select Action:"
echo "  1) Install / Upgrade Release (Build & Deploy)"
echo "  2) Uninstall Release"
echo "  3) Package & Push Helm Chart (OCI)"
echo "  4) Update Configuration Only (No Deploy)"
read -p "Enter choice [1-4]: " ACTION_CHOICE

# --- 2. Environment Selection ---
echo ""
echo "Select Environment:"
echo "  1) SBX (Domain: $SBX_DOMAIN | NS: $SBX_NAMESPACE)"
echo "  2) DEV (Domain: $DEV_DOMAIN | NS: $DEV_NAMESPACE)"
echo "  3) Custom (Enter Details Manually)"
read -p "Enter choice [1-3]: " ENV_CHOICE

if [ "$ENV_CHOICE" == "1" ]; then
    ENV_NAME="sbx"
    TARGET_DOMAIN="$SBX_DOMAIN"
    TARGET_KYMA_DOMAIN="$SBX_KYMA_DOMAIN"
    TARGET_NAMESPACE="$SBX_NAMESPACE"
    TARGET_CONTEXT="$SBX_KUBECONTEXT"
    # SBX usually implies specific Kubeconfig
    CUSTOM_KUBECONFIG="$SBX_KUBECONFIG"
elif [ "$ENV_CHOICE" == "2" ]; then
    ENV_NAME="dev"
    TARGET_DOMAIN="$DEV_DOMAIN"
    TARGET_KYMA_DOMAIN="$DEV_KYMA_DOMAIN"
    TARGET_NAMESPACE="$DEV_NAMESPACE"
    TARGET_CONTEXT="$DEV_KUBECONTEXT"
    CUSTOM_KUBECONFIG="" # Use default context
elif [ "$ENV_CHOICE" == "3" ]; then
    ENV_NAME="custom"
    echo ""
    read -p "Enter Kyma Domain (e.g., c-xxxx.kyma.ondemand.com): " TARGET_KYMA_DOMAIN
    TARGET_DOMAIN="$TARGET_KYMA_DOMAIN"
    read -p "Enter Target Namespace: " TARGET_NAMESPACE
    echo "Enter Path to Kubeconfig File:"
    # Use -e to allow readline editing if supported, or plain read
    read -e -p "Path > " CUSTOM_KUBECONFIG
else
    echo "Invalid environment choice. Exiting."
    exit 1
fi

echo ""
echo "-> Selected Environment: $ENV_NAME"
# Handle Kubeconfig setting
if [ ! -z "$CUSTOM_KUBECONFIG" ]; then
    echo "-> Using explicit Kubeconfig: $CUSTOM_KUBECONFIG"
    export KUBECONFIG="$CUSTOM_KUBECONFIG"
else
    # Only switch context if meant for standard envs without explicit config
    if [ "$ENV_NAME" == "dev" ]; then
        echo "-> Switching kubectl context to: $TARGET_CONTEXT"
        kubectl config use-context "$TARGET_CONTEXT" || echo "Warning: Context switch failed."
        unset KUBECONFIG
    fi
fi

# --- 3. Handle Uninstall ---
if [ "$ACTION_CHOICE" == "2" ]; then
    echo "Uninstalling release 'single-ui' from namespace '$TARGET_NAMESPACE'..."
    helm uninstall single-ui -n "$TARGET_NAMESPACE" || echo "Release not found or already uninstalled."
    exit 0
fi

# --- 4. Configuration Updates (Skipped for Package & Push if desired, but kept for consistency) ---
if [ "$ACTION_CHOICE" != "3" ]; then
    echo ""
    echo "Preparing to update configuration files..."
    echo "  - Domain: $TARGET_DOMAIN"
    echo "  - Namespace: $TARGET_NAMESPACE"
    
    # Update chart/values.yaml
    sed -i '' "s/domain: .*/domain: $TARGET_DOMAIN/" "$VALUES_FILE"
    # Update redirect URIs - Handle both standard scenarios
    sed -i '' "s|https://single-ui-approuter-[a-zA-Z0-9.-]*|https://single-ui-approuter-$TARGET_NAMESPACE.$TARGET_KYMA_DOMAIN|g" "$VALUES_FILE"

    # Update xs-security.json
    sed -i '' "s|https://single-ui-approuter-[a-zA-Z0-9.-]*|https://single-ui-approuter-$TARGET_NAMESPACE.$TARGET_KYMA_DOMAIN|g" "$XS_SECURITY_FILE"

    echo "-> Configuration updated."
fi

if [ "$ACTION_CHOICE" == "4" ]; then
    echo "Configuration files updated. Exiting."
    exit 0
fi

# --- 5. Package & Push Helm Chart (OCI) ---
if [ "$ACTION_CHOICE" == "3" ]; then
    echo ""
    echo "--- Helm Chart OCI Push ---"
    read -p "Enter Chart Version (e.g., 1.0.0 or 1.0.0-dev): " CHART_VERSION
    if [ -z "$CHART_VERSION" ]; then
        echo "Error: Version is required."
        exit 1
    fi
    
    echo "Target Registry: $REGISTRY_URI"
    
    # Update dependencies
    echo "Updating dependencies..."
    helm dependency update gen/chart

    # Package
    echo "Packaging chart version $CHART_VERSION..."
    helm package gen/chart --version "$CHART_VERSION"

    # Push
    PACKAGE_FILE="single-$CHART_VERSION.tgz"
    if [ -f "$PACKAGE_FILE" ]; then
        echo "Pushing $PACKAGE_FILE to $REGISTRY_URI..."
        helm push "$PACKAGE_FILE" "$REGISTRY_URI"
        echo "✅ Successfully pushed chart!"
        echo "Verify with: helm show chart $REGISTRY_URI/single --version $CHART_VERSION"
    else
        echo "Error: Package file $PACKAGE_FILE not found."
        exit 1
    fi
    exit 0
fi

# --- 6. Deploy / Upgrade Flow ---
echo ""
echo "--- Build & Deploy ---"
read -p "Enter Image Tag for Deployment (default: latest): " INPUT_TAG
IMAGE_TAG=${INPUT_TAG:-latest}
echo "-> Using Image Tag: $IMAGE_TAG"

echo "Building project artifacts (CDS)..."
npx cds build --production

echo ""
echo "Deploying Helm Release 'single-ui'..."

# Ensure gen/chart exists
if [ ! -d "./gen/chart" ]; then
    echo "Error: ./gen/chart directory not found. Build likely failed."
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

echo "Executing: $HELM_CMD"
eval $HELM_CMD

echo ""
echo "✅ Deployment triggered successfully!"
