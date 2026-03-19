#!/bin/bash
# ============================================================
# 03-azure-keyvault-setup.sh
# Azure Key Vault + Workload Identity setup:
#   - Creates Key Vault
#   - Creates Managed Identity per service
#   - Federates identity with K8s Service Account
#   - Grants Key Vault access
#   - Installs Key Vault CSI Driver (Secrets Store)
# ============================================================

set -euo pipefail

SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="rg-ecommerce-test"         # was rg-ecommerce-prod
CLUSTER_NAME="aks-ecommerce-test"          # was aks-ecommerce-prod
LOCATION="eastus"
KEYVAULT_NAME="kv-ecommerce-test"          # was kv-ecommerce-prod (must be globally unique)
NAMESPACE="production"

echo "=================================================="
echo " Azure Key Vault + Workload Identity Setup"
echo "=================================================="

az account set --subscription "$SUBSCRIPTION_ID"

# 1. Get OIDC Issuer URL from AKS
OIDC_ISSUER=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)
echo "OIDC Issuer: $OIDC_ISSUER"

# 2. Create Key Vault — TEST config (Standard SKU, short retention, no purge lock)
az keyvault create \
  --name "$KEYVAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --enable-rbac-authorization true \
  --retention-days 7 \
  --sku standard
  # TEST: --sku standard (was premium — saves HSM key cost)
  # TEST: --retention-days 7 (was 90 — can delete vault immediately)
  # TEST: no --enable-purge-protection (allows vault deletion without 90-day wait)

echo "✅ Key Vault created: $KEYVAULT_NAME"

# 3. Add secrets to Key Vault
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "postgres-password" --value "SuperSecret123!"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "mongodb-password" --value "MongoSecret456!"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "redis-password" --value "RedisSecret789!"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "rabbitmq-password" --value "RabbitSecret101!"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "jwt-secret" --value "JWTSuperSecretKey2024!"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "stripe-api-key" --value "sk_test_your_stripe_key"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "smtp-password" --value "SmtpPassword123"

echo "✅ Secrets added to Key Vault"

# 4. Install Key Vault CSI Secrets Store Driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm repo update

helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --set rotationPollInterval=2m

helm upgrade --install azure-csi-provider csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
  --namespace kube-system \
  --set secrets-store-csi-driver.install=false

echo "✅ Key Vault CSI Driver installed"

# 5. Create Managed Identities per service + federate with K8s Service Accounts
SERVICES=("api-gateway" "user-service" "product-service" "order-service" "payment-service" "notification-service")

KEYVAULT_ID=$(az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)

for SERVICE in "${SERVICES[@]}"; do
  IDENTITY_NAME="id-${SERVICE}"
  SA_NAME="${SERVICE}-sa"

  echo "🔧 Setting up Workload Identity for: $SERVICE"

  # Create managed identity
  az identity create \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION"

  CLIENT_ID=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query clientId -o tsv)

  PRINCIPAL_ID=$(az identity show \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)

  # Grant Key Vault Secrets User role
  az role assignment create \
    --role "Key Vault Secrets User" \
    --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --scope "$KEYVAULT_ID"

  # Create federated credential linking K8s Service Account → Azure Managed Identity
  az identity federated-credential create \
    --name "fc-${SERVICE}" \
    --identity-name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --issuer "$OIDC_ISSUER" \
    --subject "system:serviceaccount:${NAMESPACE}:${SA_NAME}" \
    --audience api://AzureADTokenExchange

  echo "  CLIENT_ID for $SERVICE: $CLIENT_ID"
  echo "  → Update service-accounts.yaml with this client ID"
done

echo ""
echo "=================================================="
echo "✅ Workload Identity Setup Complete!"
echo ""
echo "⚠️  Next Steps:"
echo "1. Update rbac/service-accounts.yaml with the CLIENT_IDs printed above"
echo "2. Update secrets/keyvault-secretprovider.yaml with your KeyVault name and tenant ID"
echo "3. Run: kubectl apply -f rbac/ && kubectl apply -f secrets/"
echo "=================================================="

TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Your Tenant ID: $TENANT_ID"
