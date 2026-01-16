#!/bin/bash
# ============================================================
# Ingress/Egress Policy Uninstallation Script
# ============================================================
# This script removes all ingress and egress policies from the cluster.
#
# Usage: ./uninstall.sh [KUBECONFIG_PATH]
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="${1:-$HOME/.kube/config}"

echo "============================================================"
echo " Ingress/Egress Policy Removal"
echo "============================================================"
echo "Kubeconfig: $KUBECONFIG_PATH"
echo ""

KUBECTL="kubectl --kubeconfig=$KUBECONFIG_PATH"

echo "[1/3] Removing Ingress IP Allowlist..."
$KUBECTL delete -f "$SCRIPT_DIR/03-ingress-ip-allowlist.yaml" --ignore-not-found
echo "      ✅ Done"
echo ""

echo "[2/3] Removing Egress ServiceEntry..."
$KUBECTL delete -f "$SCRIPT_DIR/02-egress-serviceentry.yaml" --ignore-not-found
echo "      ✅ Done"
echo ""

echo "[3/3] Removing Egress Sidecar..."
$KUBECTL delete -f "$SCRIPT_DIR/01-egress-sidecar.yaml" --ignore-not-found
echo "      ✅ Done"
echo ""

echo "============================================================"
echo " Removal Complete!"
echo "============================================================"
echo ""
echo "NOTE: After removing REGISTRY_ONLY sidecar, all egress traffic"
echo "      will be allowed by default (ALLOW_ANY mode)."
