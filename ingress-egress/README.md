# Ingress & Egress Policy Configuration

This folder contains Istio manifests for controlling ingress and egress traffic in your Kyma cluster.

## Files

| File                           | Description                                                                   |
| ------------------------------ | ----------------------------------------------------------------------------- |
| `01-egress-sidecar.yaml`       | Cluster-wide Sidecar with `REGISTRY_ONLY` mode (denies all egress by default) |
| `02-egress-serviceentry.yaml`  | ServiceEntry allowing egress to SAP BTP services                              |
| `03-ingress-ip-allowlist.yaml` | AuthorizationPolicy restricting ingress to specific IPs                       |
| `install.sh`                   | Script to install all policies                                                |
| `uninstall.sh`                 | Script to remove all policies                                                 |

## Quick Start

### Install All Policies

```bash
chmod +x install.sh
./install.sh /path/to/kubeconfig.yaml
```

### Uninstall All Policies

```bash
chmod +x uninstall.sh
./uninstall.sh /path/to/kubeconfig.yaml
```

## Manual Commands

### Apply Individual Manifests

```bash
KUBECONFIG=/Users/sr20536224wipro.com/Documents/Github-apple/srinivas/cap-single-ui/kubernetes/admin-sa-token.yaml

# 1. Egress Sidecar (REGISTRY_ONLY mode)
kubectl apply -f 01-egress-sidecar.yaml --kubeconfig=$KUBECONFIG

# 2. Egress ServiceEntry (SAP BTP services)
kubectl apply -f 02-egress-serviceentry.yaml --kubeconfig=$KUBECONFIG

# 3. Ingress IP Allowlist
kubectl apply -f 03-ingress-ip-allowlist.yaml --kubeconfig=$KUBECONFIG
```

### Verify Installation

```bash
# Check Sidecar
kubectl get sidecar -n istio-system --kubeconfig=$KUBECONFIG

# Check ServiceEntry
kubectl get serviceentry -n istio-system --kubeconfig=$KUBECONFIG

# Check AuthorizationPolicy
kubectl get authorizationpolicy -n istio-system --kubeconfig=$KUBECONFIG
```

## Policy Details

### Egress Policy (REGISTRY_ONLY)

| Allowed Domains                                                              | Purpose                |
| ---------------------------------------------------------------------------- | ---------------------- |
| `trail-new-k73tmz93.authentication.us10.hana.ondemand.com`                   | Tenant XSUAA           |
| `api.authentication.us10.hana.ondemand.com`                                  | XSUAA API              |
| `internal-xsuaa.authentication.us10.hana.ondemand.com`                       | Internal XSUAA         |
| `authentication.us10.hana.ondemand.com`                                      | Base Authentication    |
| `accounts.sap.com`                                                           | SAP Universal Identity |
| `145ac721-44e0-4b9f-b6b1-951ddc395db2.hna1.prod-us10.hanacloud.ondemand.com` | HANA Cloud             |
| `destination-configuration.cfapps.us10.hana.ondemand.com`                    | Destination Service    |
| `html5-apps-repo-rt.cfapps.us10.hana.ondemand.com`                           | HTML5 Repo Runtime     |
| `*.cfapps.us10.hana.ondemand.com`                                            | All CF Apps            |
| `*.c-3f6e6b4.kyma.ondemand.com`                                              | Kyma Cluster Services  |

### Ingress Policy (IP Allowlist)

| Allowed IP                | Description    |
| ------------------------- | -------------- |
| `17.233.169.53/32`        | User IPv4      |
| `2a01:b740:13c6::1c7/128` | User IPv6      |
| `18.211.151.194/32`       | AWS Service IP |

## Troubleshooting

### Test Egress Connectivity

```bash
# Create test pod
kubectl run egress-tester --image=curlimages/curl:latest -n sri --restart=Never -- sleep infinity --kubeconfig=$KUBECONFIG

# Test allowed domain
kubectl exec -n sri egress-tester -- curl -s -o /dev/null -w "%{http_code}" https://accounts.sap.com --kubeconfig=$KUBECONFIG

# Test blocked domain
kubectl exec -n sri egress-tester -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://google.com --kubeconfig=$KUBECONFIG

# Cleanup test pod
kubectl delete pod egress-tester -n sri --kubeconfig=$KUBECONFIG
```

### Check Your Current IP

```bash
curl -4 ifconfig.me  # IPv4
curl -6 ifconfig.me  # IPv6
```
