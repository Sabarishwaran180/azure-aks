#!/bin/bash
# ============================================================
# 04-cost-optimised-test-cluster.sh
#
# Deploys a lean AKS cluster for testing — roughly 70-80%
# cheaper than the production cluster in 01-aks-cluster-setup.sh
#
# Cost-cutting decisions explained inline.
# ============================================================

set -euo pipefail

SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="rg-ecommerce-test"
LOCATION="eastus"
CLUSTER_NAME="aks-ecommerce-test"
ACR_NAME="acrecommerceprod"       # reuse prod ACR — no need for a second one
LOG_ANALYTICS_WS="law-ecommerce-test"
K8S_VERSION="1.29"

# ── Cost saving 1: B-series burstable VMs ─────────────────
# Standard_B2s  = 2 vCPU, 4 GB RAM  ~ $30/month
# Standard_D2s_v3 (prod) = 2 vCPU, 8 GB RAM ~ $70/month
# B-series accumulate CPU credits when idle → fine for bursty test traffic
NODE_VM="Standard_B2s"

echo "=================================================="
echo " AKS Cost-Optimised TEST Cluster Setup"
echo " Target: < \$100/month for full stack"
echo "=================================================="

az account set --subscription "$SUBSCRIPTION_ID"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# ── Cost saving 2: Free Log Analytics (5GB/month free tier) ─
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --location "$LOCATION" \
  --sku PerGB2018

LOG_WS_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --query id -o tsv)

# ── Cost saving 3: Single node pool, no AZ, no uptime SLA ──
# No --uptime-sla                 saves ~$73/month
# No --zones 1 2 3                avoids zone-redundant disk premium
# Single pool (no systempool separation) → minimum 1 node instead of 2
# --node-count 1 with autoscaler  → starts lean, grows only when needed
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
  --workspace-resource-id "$LOG_WS_ID" \
  --attach-acr "$ACR_NAME" \
  --os-sku AzureLinux \
  --ssh-key-value ~/.ssh/id_rsa.pub \
  --tags "environment=test" "auto-shutdown=true"

# ── Cost saving 4: Spot node pool for batch/test workloads ──
# Spot instances = up to 90% cheaper than regular nodes
# Drawback: can be evicted with 30s notice
# Fine for testing — pods will be rescheduled on the regular node
az aks nodepool add \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$CLUSTER_NAME" \
  --name spotpool \
  --node-count 0 \
  --min-count 0 \
  --max-count 5 \
  --node-vm-size "Standard_B4ms" \
  --enable-cluster-autoscaler \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --labels "nodepool-type=spot" "kubernetes.azure.com/scalesetpriority=spot" \
  --node-taints "kubernetes.azure.com/scalesetpriority=spot:NoSchedule" \
  --mode User

echo "✅ Spot node pool added (starts at 0 nodes)"

az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

echo ""
echo "=================================================="
echo "✅ Test cluster ready: $CLUSTER_NAME"
kubectl get nodes
echo ""
echo "💰 Estimated cost: ~\$50-90/month at 1 node"
echo "   Scales to ~\$180/month at 4 nodes under load"
echo "   Set up auto-shutdown (05-cluster-schedule.sh) to"
echo "   save another 65% on nights + weekends"
echo "=================================================="
