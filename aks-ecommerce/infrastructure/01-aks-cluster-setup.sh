#!/bin/bash
# ============================================================
# 01-aks-cluster-setup.sh  ── TESTING / COST-OPTIMISED
# Single B2s node pool, no uptime SLA, no AZs, ephemeral OS disk.
# For production setup use the values commented at the bottom.
# ============================================================

set -euo pipefail

# ---------- VARIABLES ----------------------------------------
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="rg-ecommerce-test"          # was rg-ecommerce-prod
LOCATION="eastus"
CLUSTER_NAME="aks-ecommerce-test"           # was aks-ecommerce-prod
ACR_NAME="acrecommerceprod"
VNET_NAME="vnet-ecommerce"
SUBNET_AKS="subnet-aks"
SUBNET_APPGW="subnet-appgw"
LOG_ANALYTICS_WS="law-ecommerce-test"       # was law-ecommerce-prod
K8S_VERSION="1.29"

# TEST: B2s burstable — 2 vCPU, 4 GB RAM, ~$31/month
# PROD: Standard_D2s_v3 (system) / Standard_D4s_v3 (user)
NODE_VM="Standard_B2s"

echo "=================================================="
echo " AKS TEST Cluster Setup (~\$46/month with schedule)"
echo "=================================================="

# 1. Set subscription
az account set --subscription "$SUBSCRIPTION_ID"

# 2. Create resource group
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

# 3. Create Azure Container Registry
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Premium \
  --admin-enabled false

# 4. Create Virtual Network + Subnets (Azure CNI needs dedicated subnet)
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --address-prefixes "10.0.0.0/8" \
  --subnet-name "$SUBNET_AKS" \
  --subnet-prefix "10.240.0.0/16"

az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_APPGW" \
  --address-prefix "10.2.0.0/16"

AKS_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_AKS" \
  --query id -o tsv)

# 5. Create Log Analytics Workspace (for Container Insights)
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --location "$LOCATION" \
  --sku PerGB2018

LOG_ANALYTICS_WS_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --query id -o tsv)

# 6. Create AKS Cluster
# Key flags explained:
#   --network-plugin azure        → Azure CNI (pods get real VNet IPs)
#   --network-policy azure        → Azure Network Policies support
#   --enable-cluster-autoscaler   → Auto scale nodes
#   --enable-oidc-issuer          → Required for Workload Identity
#   --enable-workload-identity    → Federated identity for pods
#   --enable-addons monitoring    → Container Insights
#   --enable-azure-policy         → Azure Policy for K8s
#   --zones 1 2 3                 → Availability Zones for HA
az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --kubernetes-version "$K8S_VERSION" \
  --location "$LOCATION" \
  --node-count 1 \
  --min-count 1 \
  --max-count 4 \
  --node-vm-size "$NODE_VM" \
  --nodepool-name testpool \
  --node-osdisk-size 50 \
  --node-osdisk-type Ephemeral \
  --vnet-subnet-id "$AKS_SUBNET_ID" \
  --network-plugin azure \
  --network-policy azure \
  --service-cidr "10.0.0.0/16" \
  --dns-service-ip "10.0.0.10" \
  --enable-cluster-autoscaler \
  --cluster-autoscaler-profile \
      scale-down-delay-after-add=5m \
      scale-down-unneeded-time=5m \
      skip-nodes-with-system-pods=false \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --enable-managed-identity \
  --enable-addons monitoring \
  --workspace-resource-id "$LOG_ANALYTICS_WS_ID" \
  --attach-acr "$ACR_NAME" \
  --os-sku AzureLinux \
  --ssh-key-value ~/.ssh/id_rsa.pub \
  --tags "environment=test" "auto-shutdown=true"
  # TEST: no --uptime-sla ($73/month saved)
  # TEST: no --zones 1 2 3 (avoids ZRS disk premium)
  # TEST: no --enable-addons azure-policy (reduces overhead)
  # TEST: no --auto-upgrade-channel (manual control in test)

echo "✅ System node pool created"

# 7. Add User Node Pool (for application workloads)
# Taint system pool so only system pods run there
az aks nodepool add \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$CLUSTER_NAME" \
  --name userpool \
  --node-count 3 \
  --min-count 2 \
  --max-count 20 \
  --node-vm-size "$USER_POOL_VM" \
  --enable-cluster-autoscaler \
  --node-taints "" \
  --labels "nodepool-type=user" "workload=application" \
  --zones 1 2 3 \
  --mode User

echo "✅ User node pool created"

# 8. Add GPU Node Pool (for ML / heavy compute if needed)
az aks nodepool add \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$CLUSTER_NAME" \
  --name gpupool \
  --node-count 0 \
  --min-count 0 \
  --max-count 5 \
  --node-vm-size "Standard_NC6s_v3" \
  --enable-cluster-autoscaler \
  --node-taints "sku=gpu:NoSchedule" \
  --labels "nodepool-type=gpu" \
  --mode User

echo "✅ GPU node pool created (starts at 0)"

# 9. Get credentials
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

echo ""
echo "=================================================="
echo "✅ AKS Cluster Ready!"
echo "  Cluster: $CLUSTER_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Run: kubectl get nodes"
echo "=================================================="

# Taint the system pool to prevent app pods from scheduling there
kubectl taint nodes -l agentpool=systempool CriticalAddonsOnly=true:NoSchedule --overwrite || true

# Verify
kubectl get nodes -o wide
kubectl get nodes --show-labels
