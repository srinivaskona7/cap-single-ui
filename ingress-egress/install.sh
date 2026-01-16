#!/bin/bash
# ============================================================
# Ingress/Egress Policy Installation Script
# ============================================================
# This script applies all ingress and egress policies to the cluster.
# It uses kubectl apply which is idempotent (safe to run multiple times).
#
# Usage: ./install.sh [KUBECONFIG_PATH]
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="${1:-$HOME/.kube/config}"

echo "============================================================"
echo " Ingress/Egress Policy Installation"
echo "============================================================"
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "ERROR: Kubeconfig not found at $KUBECONFIG_PATH"
    exit 1
fi

KUBECTL="kubectl --kubeconfig=$KUBECONFIG_PATH"

echo "[1/3] Applying Egress Sidecar (REGISTRY_ONLY mode)..."
$KUBECTL apply -f "$SCRIPT_DIR/01-egress-sidecar.yaml"
echo "      ✅ Done"
echo ""

echo "[2/3] Applying Egress ServiceEntry (SAP BTP services)..."
$KUBECTL apply -f "$SCRIPT_DIR/02-egress-serviceentry.yaml"
echo "      ✅ Done"
echo ""

echo "[3/3] Applying Ingress IP Allowlist..."
$KUBECTL apply -f "$SCRIPT_DIR/03-ingress-ip-allowlist.yaml"
echo "      ✅ Done"
echo ""

echo "============================================================"
echo " Verification"
echo "============================================================"

echo ""
echo "Sidecar:"
$KUBECTL get sidecar -n istio-system default-egress-policy

echo ""
echo "ServiceEntry:"
$KUBECTL get serviceentry -n istio-system sap-btp-services

echo ""
echo "AuthorizationPolicy:"
$KUBECTL get authorizationpolicy -n istio-system global-ingress-ip-allowlist

echo ""
echo "============================================================"
echo " Installation Complete!"
echo "============================================================"
