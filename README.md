# CAP Single UI Application

Welcome to your SAP CAP (Cloud Application Programming) project with comprehensive Kyma network security policies.

## Project Structure

| File/Folder       | Purpose                                     |
| ----------------- | ------------------------------------------- |
| `app/`            | UI5/Fiori frontend application              |
| `db/`             | Domain models and database schemas (CDS)    |
| `srv/`            | Service models and business logic           |
| `ingress-egress/` | Istio network security policies             |
| `kubernetes/`     | Kubernetes configuration files              |
| `chart/`          | Helm chart configuration                    |
| `deploy.sh`       | Deployment automation script                |
| `hana-manager.sh` | HANA Cloud instance management (start/stop) |
| `install.sh`      | Network policies installation script        |
| `uninstall.sh`    | Network policies removal script             |
| `package.json`    | Project metadata and dependencies           |

## Quick Start

```bash
# Local development
cds watch

# Or in VS Code: Terminal > Run Task > cds watch
```

## Learn More

- [SAP CAP Documentation](https://cap.cloud.sap/docs/get-started/)
- [SAP BTP Kyma Runtime](https://help.sap.com/docs/btp/sap-business-technology-platform/kyma-environment)
- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)

---

# HANA Cloud Instance Management

SAP BTP Trial/Free tier HANA Cloud instances **automatically stop after 24 hours** of inactivity. Use the included `hana-manager.sh` script to check status and restart instances.

## Quick Start

```bash
# Run the interactive HANA manager
./hana-manager.sh
```

## Features

- **Auto-detection** of BTP login and subaccount
- **Lists all service instances** in your subaccount
- **Shows detailed status** (ready, usable, license type)
- **Start stopped instances** directly from CLI
- **Dashboard URL** for web-based management
- **Error handling** with helpful messages

## Manual HANA Commands

```bash
# Check instance status via BTP CLI
btp get services/instance --id <instance-id> --subaccount <subaccount-id>

# Start HANA instance (if stopped)
btp update services/instance --id <instance-id> --subaccount <subaccount-id> \
  --parameters '{"data":{"serviceStopped":false}}'

# Alternative: Use CF CLI (if in Cloud Foundry)
cf update-service <service-name> -c '{"data":{"serviceStopped":false}}'
```

## HANA Cloud Central

Web portal for managing HANA instances: [HANA Cloud Central](https://hana-cloud.cfapps.us10.hana.ondemand.com/)

---

# Network Security Configuration

This project implements enterprise-grade network security using Istio service mesh on SAP BTP Kyma Runtime. The configuration enforces a **Zero Trust** architecture for both inbound (ingress) and outbound (egress) traffic.

## Prerequisites

### Cluster Requirements

| Requirement                 | Description                                                                |
| --------------------------- | -------------------------------------------------------------------------- |
| **SAP BTP Kyma Runtime**    | Active Kyma cluster with Istio service mesh enabled                        |
| **Istio Sidecar Injection** | Namespace must have `istio-injection=enabled` label                        |
| **Admin Access**            | `cluster-admin` or equivalent RBAC permissions in `istio-system` namespace |
| **kubectl**                 | Kubernetes CLI configured with cluster access                              |

### Required Permissions

```yaml
# Minimum RBAC permissions needed
- apiGroups: ["networking.istio.io"]
  resources: ["sidecars", "serviceentries"]
  verbs: ["get", "list", "create", "update", "delete"]
- apiGroups: ["security.istio.io"]
  resources: ["authorizationpolicies"]
  verbs: ["get", "list", "create", "update", "delete"]
```

### Kubeconfig Setup

Ensure you have a valid kubeconfig file. Default location used by scripts:

```
./kubernetes/admin-sa-token.yaml
```

---

## Egress Control (Outbound Traffic)

### Overview

Egress control restricts which external services your application can communicate with. This is critical for:

- **Data Loss Prevention (DLP)** – Prevent unauthorized data exfiltration
- **Compliance** – Meet regulatory requirements (SOC2, GDPR, etc.)
- **Security** – Block communication to malicious endpoints

### How It Works

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────────┐
│   Application   │────▶│  Istio Proxy │────▶│ External Service    │
│    (Pod)        │     │  (Sidecar)   │     │ (If in ServiceEntry)│
└─────────────────┘     └──────────────┘     └─────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │ REGISTRY_ONLY    │
                    │ Mode Enforced    │
                    │ ─────────────────│
                    │ ✅ Allowed hosts │
                    │ ❌ All others    │
                    └──────────────────┘
```

### Components

| File                          | Resource Type  | Purpose                                                  |
| ----------------------------- | -------------- | -------------------------------------------------------- |
| `01-egress-sidecar.yaml`      | `Sidecar`      | Sets `REGISTRY_ONLY` mode – denies all egress by default |
| `02-egress-serviceentry.yaml` | `ServiceEntry` | Whitelists allowed external domains                      |

### Egress Rules to Define

Two Istio resources work together to control egress traffic:

#### Rule 1: Sidecar (Deny-All Default Policy)

This rule enforces `REGISTRY_ONLY` mode at the cluster level, which means **all outbound traffic is blocked by default** unless explicitly allowed.

```yaml
# 01-egress-sidecar.yaml
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  name: default-egress-policy
  namespace: istio-system # Applied cluster-wide from istio-system
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY # Only allow traffic to registered services
```

| Field                        | Value           | Description                                 |
| ---------------------------- | --------------- | ------------------------------------------- |
| `namespace`                  | `istio-system`  | Applies to entire mesh when in istio-system |
| `outboundTrafficPolicy.mode` | `REGISTRY_ONLY` | Blocks all egress unless in ServiceEntry    |

#### Rule 2: ServiceEntry (Whitelist Allowed Domains)

This rule defines which external hosts are allowed for egress traffic.

```yaml
# 02-egress-serviceentry.yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: sap-btp-services
  namespace: istio-system
spec:
  hosts:
    - "domain1.example.com" # Individual host
    - "*.example.com" # Wildcard domain
  location: MESH_EXTERNAL # External to the mesh
  ports:
    - number: 443
      name: https
      protocol: TLS # Use TLS for HTTPS
  resolution: NONE # Let the sidecar resolve DNS
```

| Field            | Value           | Description                                     |
| ---------------- | --------------- | ----------------------------------------------- |
| `hosts`          | List of domains | Domains allowed for egress (supports wildcards) |
| `location`       | `MESH_EXTERNAL` | Indicates hosts are outside the service mesh    |
| `ports.number`   | `443`           | HTTPS port                                      |
| `ports.protocol` | `TLS`           | TLS passthrough for HTTPS traffic               |
| `resolution`     | `NONE`          | DNS resolution handled by sidecar               |

### Prerequisites for Egress ServiceEntry

> **⚠️ IMPORTANT**: Before enabling egress restrictions, ensure you have identified ALL external services your application needs.

| Category           | What to Identify                                  | How to Find                                          |
| ------------------ | ------------------------------------------------- | ---------------------------------------------------- |
| **Authentication** | XSUAA endpoints, Identity Provider URLs, SAP IAS  | Check `VCAP_SERVICES` or service binding credentials |
| **Database**       | HANA Cloud instance hostname                      | BTP Cockpit → HANA Cloud → Connection Details        |
| **BTP Services**   | Destination Service, HTML5 Repo, Credential Store | Service binding `credentials.url` fields             |
| **External APIs**  | Third-party APIs your app consumes                | Application code, `package.json` dependencies        |
| **Cloud Foundry**  | CF Apps endpoints if using hybrid deployment      | BTP Cockpit → CF Org → Routes                        |
| **Kyma Internal**  | Other services in the same cluster                | Use `*.your-cluster.kyma.ondemand.com` wildcard      |

### Allowed Egress Domains (Current Configuration)

| Domain                                                                       | Service                | Port |
| ---------------------------------------------------------------------------- | ---------------------- | ---- |
| `trail-new-k73tmz93.authentication.us10.hana.ondemand.com`                   | Tenant-specific XSUAA  | 443  |
| `api.authentication.us10.hana.ondemand.com`                                  | XSUAA API              | 443  |
| `internal-xsuaa.authentication.us10.hana.ondemand.com`                       | Internal XSUAA         | 443  |
| `authentication.us10.hana.ondemand.com`                                      | Base Authentication    | 443  |
| `accounts.sap.com`                                                           | SAP Universal Identity | 443  |
| `145ac721-44e0-4b9f-b6b1-951ddc395db2.hna1.prod-us10.hanacloud.ondemand.com` | HANA Cloud Instance    | 443  |
| `destination-configuration.cfapps.us10.hana.ondemand.com`                    | Destination Service    | 443  |
| `html5-apps-repo-rt.cfapps.us10.hana.ondemand.com`                           | HTML5 App Repository   | 443  |
| `*.cfapps.us10.hana.ondemand.com`                                            | All CF Apps (wildcard) | 443  |
| `*.b1eb3b8.kyma.ondemand.com`                                                | Kyma Cluster Services  | 443  |

### Adding New Egress Domains

Edit `ingress-egress/02-egress-serviceentry.yaml`:

```yaml
spec:
  hosts:
    - existing-domain.example.com
    - new-domain-to-add.example.com # Add new domain here
```

Then reapply:

```bash
kubectl apply -f ingress-egress/02-egress-serviceentry.yaml --kubeconfig=$KUBECONFIG
```

---

## Ingress Control (Inbound Traffic)

### Overview

Ingress control restricts which clients can access your application. This provides:

- **Network Perimeter Security** – Only allow known IP ranges
- **DDoS Protection** – Reduce attack surface
- **Access Control** – Limit to corporate networks, VPNs, or specific services

### How It Works

```
┌──────────────┐     ┌─────────────────────┐     ┌─────────────────┐
│   Client     │────▶│  Istio Ingress      │────▶│   Application   │
│  (Browser)   │     │  Gateway            │     │   (Pod)         │
└──────────────┘     └─────────────────────┘     └─────────────────┘
       │                      │
       │               ┌──────┴──────┐
       │               │ AuthPolicy  │
       │               │ ──────────  │
       ▼               │ IP Check    │
┌─────────────────┐    └─────────────┘
│ Source IP       │           │
│ 17.233.169.53   │◀──────────┤ ✅ Allowed
│ 8.8.8.8         │◀──────────┤ ❌ Denied (403)
└─────────────────┘
```

### Components

| File                           | Resource Type         | Purpose                                    |
| ------------------------------ | --------------------- | ------------------------------------------ |
| `03-ingress-ip-allowlist.yaml` | `AuthorizationPolicy` | Restricts ingress to specific IP addresses |

### Prerequisites for Ingress Authorization

> **⚠️ IMPORTANT**: Before enabling IP restrictions, ensure you have identified ALL IP addresses that need access.

| Requirement               | Description                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------ |
| **Your Public IP**        | Run `curl -4 ifconfig.me` to get your IPv4                                           |
| **IPv6 Address**          | Run `curl -6 ifconfig.me` if using IPv6                                              |
| **CI/CD IPs**             | Pipeline runners (GitHub Actions, Jenkins, etc.)                                     |
| **Corporate Network**     | VPN exit points, office IP ranges                                                    |
| **Cloud Services**        | AWS NAT Gateway IPs, Azure, GCP ranges                                               |
| **externalTrafficPolicy** | Istio IngressGateway must have `externalTrafficPolicy: Local` to preserve client IPs |

### Enabling Client IP Preservation

> **🔧 CRITICAL**: Without this, all traffic appears to come from internal cluster IPs.

```bash
# Patch Istio Ingress Gateway to preserve client IPs
kubectl patch svc istio-ingressgateway -n istio-system \
  --type='merge' \
  -p '{"spec":{"externalTrafficPolicy":"Local"}}' \
  --kubeconfig=$KUBECONFIG
```

### Allowed Ingress IPs (Current Configuration)

| IP Address                | Type | Description                      |
| ------------------------- | ---- | -------------------------------- |
| `17.233.169.53/32`        | IPv4 | User IP (Apple network)          |
| `2a01:b740:13c6::1c7/128` | IPv6 | User IPv6 address                |
| `18.211.151.194/32`       | IPv4 | AWS Service IP (CI/CD pipelines) |

### Adding New Ingress IPs

Edit `ingress-egress/03-ingress-ip-allowlist.yaml`:

```yaml
spec:
  rules:
    - from:
        - source:
            ipBlocks:
              - 17.233.169.53/32 # Existing IP
              - 10.0.0.0/8 # Add new IP range here
```

Then reapply:

```bash
kubectl apply -f ingress-egress/03-ingress-ip-allowlist.yaml --kubeconfig=$KUBECONFIG
```

---

## Installation

### Quick Start (From Project Root)

```bash
# Make scripts executable
chmod +x install.sh uninstall.sh

# Install all network policies (uses default kubeconfig)
./install.sh

# Or specify custom kubeconfig
./install.sh /path/to/kubeconfig.yaml

# Uninstall all network policies
./uninstall.sh
```

### Manual Installation

```bash
# Set kubeconfig
export KUBECONFIG=./kubernetes/admin-sa-token.yaml

# Step 1: Apply Egress Sidecar (REGISTRY_ONLY mode)
kubectl apply -f ingress-egress/01-egress-sidecar.yaml

# Step 2: Apply Egress ServiceEntry (whitelist SAP BTP services)
kubectl apply -f ingress-egress/02-egress-serviceentry.yaml

# Step 3: Apply Ingress IP Allowlist
kubectl apply -f ingress-egress/03-ingress-ip-allowlist.yaml
```

### Verify Installation

```bash
# Check Sidecar (egress policy)
kubectl get sidecar -n istio-system

# Check ServiceEntry (allowed egress domains)
kubectl get serviceentry -n istio-system

# Check AuthorizationPolicy (ingress IP allowlist)
kubectl get authorizationpolicy -n istio-system

# Detailed view
kubectl describe sidecar default-egress-policy -n istio-system
kubectl describe serviceentry sap-btp-services -n istio-system
kubectl describe authorizationpolicy global-ingress-ip-allowlist -n istio-system
```

---

## Default Kyma Behavior vs Restricted Mode

| Aspect               | Default (Open)               | Restricted (After Policies)     |
| -------------------- | ---------------------------- | ------------------------------- |
| **Egress Mode**      | `ALLOW_ANY`                  | `REGISTRY_ONLY`                 |
| **Outbound Traffic** | All external traffic allowed | Only ServiceEntry hosts allowed |
| **Ingress Access**   | All clients can access       | Only whitelisted IPs can access |
| **Security Posture** | Permissive                   | Zero Trust                      |

---

## Troubleshooting

### Test Egress Connectivity

```bash
# Create test pod
kubectl run egress-tester --image=curlimages/curl:latest -n <namespace> \
  --restart=Never -- sleep infinity --kubeconfig=$KUBECONFIG

# Test allowed domain (should return 200/301/302)
kubectl exec -n <namespace> egress-tester -- \
  curl -s -o /dev/null -w "%{http_code}" https://accounts.sap.com

# Test blocked domain (should timeout or return 000/connection refused)
kubectl exec -n <namespace> egress-tester -- \
  curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://google.com

# Cleanup
kubectl delete pod egress-tester -n <namespace>
```

### Check Your Public IP

```bash
curl -4 ifconfig.me  # IPv4
curl -6 ifconfig.me  # IPv6
```

### Common Issues

| Issue                       | Cause                               | Solution                                    |
| --------------------------- | ----------------------------------- | ------------------------------------------- |
| App can't reach XSUAA       | Domain not in ServiceEntry          | Add domain to `02-egress-serviceentry.yaml` |
| 403 Forbidden on ingress    | IP not in allowlist                 | Add IP to `03-ingress-ip-allowlist.yaml`    |
| All traffic blocked         | Sidecar applied before ServiceEntry | Apply ServiceEntry first, then Sidecar      |
| Client IP shows as internal | `externalTrafficPolicy` not set     | Patch Istio IngressGateway (see above)      |

---

## File Reference

| File                           | Location          | Description                     |
| ------------------------------ | ----------------- | ------------------------------- |
| `install.sh`                   | Project root      | Installs all network policies   |
| `uninstall.sh`                 | Project root      | Removes all network policies    |
| `01-egress-sidecar.yaml`       | `ingress-egress/` | Cluster-wide egress deny policy |
| `02-egress-serviceentry.yaml`  | `ingress-egress/` | SAP BTP egress whitelist        |
| `03-ingress-ip-allowlist.yaml` | `ingress-egress/` | IP-based ingress restriction    |
| `ingress-egress/README.md`     | `ingress-egress/` | Detailed troubleshooting guide  |

---

## Security Best Practices

1. **Principle of Least Privilege** – Only allow the minimum required domains/IPs
2. **Regular Audits** – Review allowed domains and IPs periodically
3. **Document Changes** – Update this README when adding new entries
4. **Test Before Production** – Verify policies in a staging environment first
5. **Monitor Logs** – Check Istio access logs for denied requests

---

# Helm Chart Management (OCI)

This project uses **Docker Hub** (or any OCI-compliant registry) to store and manage Helm charts. This allows strict versioning and easy deployment.

## Prerequisites

1.  **Helm 3+**: Ensure you have Helm installed (`brew install helm`).
2.  **Docker Login**: You must be logged in to the registry to push.
    ```bash
    helm registry login registry-1.docker.io -u <your-username>
    ```

## 1. Package and Push Chart

To release a new version of the application:

1.  **Update Version**: Change `version` and `appVersion` in `gen/chart/Chart.yaml` (e.g., to `1.0.1`).
2.  **Package**:

    ```bash
    # Update dependencies first
    helm dependency update gen/chart

    # Package the chart (creates single-1.0.1.tgz)
    helm package gen/chart
    ```

3.  **Push to Docker Hub**:

    ```bash
    # Replace <username> and <version>
    helm push single-<version>.tgz oci://registry-1.docker.io/<username>
    ```

    _Example:_

    ```bash
    helm push single-1.0.0.tgz oci://registry-1.docker.io/sriniv7654
    ```

## 2. Install/Upgrade from Registry

You do not need the local source code to deploy. You can install directly from the registry.

### Basic Install

```bash
helm upgrade --install single oci://registry-1.docker.io/sriniv7654/single --version 1.0.0
```

### Install with Custom Values

You can override default configuration (like image tags, replicas, or external hostnames) without modifying the chart.

1.  **Create a `custom-values.yaml` file:**

    ```yaml
    global:
      domain: "my-custom-domain.com"
      image:
        tag: "1.0.1" # Override global image tag

    srv:
      resources:
        limits:
          memory: "512Mi"

    # Example: Override XSUAA parameters
    xsuaa:
      parameters:
        oauth2-configuration:
          redirect-uris:
            - "https://my-custom-domain.com/login/callback"
    ```

2.  **Apply with Upgrade:**
    ```bash
    helm upgrade --install single oci://registry-1.docker.io/sriniv7654/single \
      --version 1.0.0 \
      --values custom-values.yaml
    ```

### Advanced: Dynamic XSUAA Configuration

To pass the full `xs-security.json` dynamically (best for automation):

To pass the full `xs-security.json` dynamically (best for automation):

```bash
# Example: Deploy to 'srii' namespace using 'trail-less-size' version
helm -n srii upgrade --install single-ui oci://registry-1.docker.io/sriniv7654/single \
  --version 1.0.0-trail-less-size \
  --kubeconfig /Users/sr20536224wipro.com/Documents/clusters/trail/admin-sa-token.yaml \
  --set-json "xsuaa.parameters=$(cat xs-security.json)"
```

### Available Versions

Currently available chart versions in the registry:

- `1.0.0-dev`
- `1.0.0-trail`
- `1.0.0-trail-less-size`
