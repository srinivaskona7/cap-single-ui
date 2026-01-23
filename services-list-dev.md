# Service Endpoints & Network Configuration (Development)

This document outlines the active service endpoints discovered from the `egress` namespace secrets. These endpoints are required for the application's outbound connectivity.

## 1. Authentication & Security (XSUAA)

Handles user authentication, token issuance, and validation.

- **Service Name**: SAP XSUAA
- **Auth URL**: `https://appkymadv.authentication.us10.hana.ondemand.com`
- **API URL**: `https://api.authentication.us10.hana.ondemand.com`
- **Resolved IPs**:
  - `18.213.242.208`
  - `34.205.56.51`
  - `3.214.110.153`
    _Note: These IPs correspond to the AWS Load Balancer for the authentication service region matches `_.cfapps.us10...` wildcard.\*

## 2. Database (HANA Cloud)

Primary persistence layer for the application.

- **Service Name**: SAP HANA Cloud
- **Host**: `db95cddd-6215-424f-b8ec-e142db00afe2.hana.prod-us10.hanacloud.ondemand.com`
- **Connection URL**: `jdbc:sap://db95cddd-6215-424f-b8ec-e142db00afe2.hana.prod-us10.hanacloud.ondemand.com:443`
- **Resolved IPs**:
  - `44.206.8.43`
  - `44.205.52.74`
  - `44.213.136.229`

## 3. Destination Service

Manages connectivity to external systems and handles destination configuration.

- **Service Name**: SAP Destination Service
- **URI**: `https://destination-configuration.cfapps.us10.hana.ondemand.com`
- **Target Host**: `destination-configuration.cfapps.us10.hana.ondemand.com`
- **Resolved IPs (Specific)**:
  - `54.243.28.3`
  - `35.173.121.86`
  - `52.71.181.35`
    _Note: Ensure these SPECIFIC IPs are allowed. If the hostname resolves to the generic CF Proxy (e.g. when checking with `https://`), it might return the XSUAA IPs, but the application traffic will use the specific IPs above._

## 4. HTML5 App Repository

Stores and serves static content for the web application.

- **Service Name**: SAP HTML5 Application Repository (Runtime)
- **URI**: `https://html5-apps-repo-rt.cfapps.us10.hana.ondemand.com`
- **Resolved IPs**:
  - `34.205.56.51`
  - `18.213.242.208`
  - `3.214.110.153`

---

### **Network Policy (Egress) Recommendations**

Based on the above discovery, ensure your `Istio` or `NetworkPolicy` allows egress to these CIDR blocks:

1.  **Auth / HTML5 Repo / CF Proxy**: `18.213.242.208/32`, `34.205.56.51/32`, `3.214.110.153/32`
2.  **HANA Cloud**: `44.206.8.43/32`, `44.205.52.74/32`, `44.213.136.229/32`
3.  **Destination Service (Specific)**: `54.243.28.3/32`, `35.173.121.86/32`, `52.71.181.35/32`
