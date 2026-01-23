#!/bin/bash
echo "--- AUTHENTICATION ---"
echo "Looking up: trail-new-k73tmz93.authentication.us10.hana.ondemand.com"
nslookup trail-new-k73tmz93.authentication.us10.hana.ondemand.com || echo "Failed to resolve trail-new-k73tmz93"

echo "Looking up: api.authentication.us10.hana.ondemand.com"
nslookup api.authentication.us10.hana.ondemand.com || echo "Failed to resolve api"

echo "Looking up: internal-xsuaa.authentication.us10.hana.ondemand.com"
nslookup internal-xsuaa.authentication.us10.hana.ondemand.com || echo "Failed to resolve internal-xsuaa"

echo "Looking up: authentication.us10.hana.ondemand.com"
nslookup authentication.us10.hana.ondemand.com || echo "Failed to resolve authentication"

echo "Looking up: accounts.sap.com"
nslookup accounts.sap.com || echo "Failed to resolve accounts.sap.com"

echo ""
echo "--- HANA CLOUD ---"
echo "Looking up: 145ac721-44e0-4b9f-b6b1-951ddc395db2.hna1.prod-us10.hanacloud.ondemand.com"
nslookup 145ac721-44e0-4b9f-b6b1-951ddc395db2.hna1.prod-us10.hanacloud.ondemand.com || echo "Failed to resolve HANA"

echo ""
echo "--- CLOUD FOUNDRY ---"
echo "Looking up: destination-configuration.cfapps.us10.hana.ondemand.com"
nslookup destination-configuration.cfapps.us10.hana.ondemand.com || echo "Failed to resolve destination"

echo "Looking up: html5-apps-repo-rt.cfapps.us10.hana.ondemand.com"
nslookup html5-apps-repo-rt.cfapps.us10.hana.ondemand.com || echo "Failed to resolve html5-repo"

echo ""
echo "--- KYMA (Wildcard Check) ---"
echo "Looking up: console.c-3f6e6b4.kyma.ondemand.com"
nslookup console.c-3f6e6b4.kyma.ondemand.com || echo "Failed to resolve Kyma console"

echo "Looking up: api.c-3f6e6b4.kyma.ondemand.com"
nslookup api.c-3f6e6b4.kyma.ondemand.com || echo "Failed to resolve Kyma api"
