#!/bin/bash
# ============================================================
# 05-cluster-schedule.sh
# Auto start/stop the test cluster on a schedule.
#
# Savings example (East US pricing, 2-node B2s cluster):
#   Running 24/7      → ~$100/month
#   Weekdays 8am-8pm  → ~$35/month   (65% saving)
#   + weekends off    → ~$20/month   (80% saving)
#
# Two approaches shown:
#   A) Azure Automation Runbook (recommended — serverless, free tier)
#   B) GitHub Actions scheduled workflow (if you prefer)
# ============================================================

set -euo pipefail

SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="rg-ecommerce-test"
CLUSTER_NAME="aks-ecommerce-test"
AUTOMATION_ACCOUNT="aa-aks-scheduler"
LOCATION="eastus"

az account set --subscription "$SUBSCRIPTION_ID"

# ════════════════════════════════════════════════════════════
# APPROACH A: Azure Automation Runbook (recommended)
# ════════════════════════════════════════════════════════════

# 1. Create Automation Account (free tier: 500 min/month included)
az automation account create \
  --name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Free

# 2. Assign Contributor on the resource group so Runbook can start/stop AKS
AUTOMATION_PRINCIPAL=$(az automation account show \
  --name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query identity.principalId -o tsv)

az role assignment create \
  --assignee "$AUTOMATION_PRINCIPAL" \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# 3. Create the STOP runbook (scale all node pools to 0)
cat > /tmp/stop-cluster.ps1 << 'PSEOF'
param(
    [string]$ResourceGroup = "rg-ecommerce-test",
    [string]$ClusterName   = "aks-ecommerce-test"
)
Connect-AzAccount -Identity   # uses the Automation Account managed identity

Write-Output "Stopping AKS cluster: $ClusterName"

# Scale system node pool to minimum (can't go to 0 — AKS needs it)
Update-AzAksNodePool `
    -ResourceGroupName $ResourceGroup `
    -ClusterName       $ClusterName `
    -Name              "testpool" `
    -MinCount          1 `
    -MaxCount          1 `
    -NodeCount         1

# Scale spot pool to 0 — pure saving
Update-AzAksNodePool `
    -ResourceGroupName $ResourceGroup `
    -ClusterName       $ClusterName `
    -Name              "spotpool" `
    -MinCount          0 `
    -MaxCount          5 `
    -NodeCount         0

# Stop the cluster entirely (nodes are deallocated — you only pay for disks)
Stop-AzAksCluster `
    -ResourceGroupName $ResourceGroup `
    -Name              $ClusterName

Write-Output "Cluster stopped. Disks retained, compute billing paused."
PSEOF

az automation runbook create \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "Stop-AksTestCluster" \
  --type PowerShell

az automation runbook replace-content \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "Stop-AksTestCluster" \
  --content @/tmp/stop-cluster.ps1

az automation runbook publish \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "Stop-AksTestCluster"

# 4. Create the START runbook
cat > /tmp/start-cluster.ps1 << 'PSEOF'
param(
    [string]$ResourceGroup = "rg-ecommerce-test",
    [string]$ClusterName   = "aks-ecommerce-test"
)
Connect-AzAccount -Identity

Write-Output "Starting AKS cluster: $ClusterName"
Start-AzAksCluster `
    -ResourceGroupName $ResourceGroup `
    -Name              $ClusterName

Write-Output "Cluster started. Node pool autoscaler will handle pod scheduling."
PSEOF

az automation runbook create \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "Start-AksTestCluster" \
  --type PowerShell

az automation runbook replace-content \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "Start-AksTestCluster" \
  --content @/tmp/start-cluster.ps1

az automation runbook publish \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "Start-AksTestCluster"

# 5. Schedule: Start Mon-Fri 7:55am UTC
az automation schedule create \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "weekday-start" \
  --frequency Week \
  --interval 1 \
  --start-time "$(date -u +%Y-%m-%dT)07:55:00+00:00" \
  --week-days Monday Tuesday Wednesday Thursday Friday \
  --time-zone "UTC"

az automation job-schedule create \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --runbook-name "Start-AksTestCluster" \
  --schedule-name "weekday-start"

# 6. Schedule: Stop Mon-Fri 8:05pm UTC
az automation schedule create \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --name "weekday-stop" \
  --frequency Week \
  --interval 1 \
  --start-time "$(date -u +%Y-%m-%dT)20:05:00+00:00" \
  --week-days Monday Tuesday Wednesday Thursday Friday \
  --time-zone "UTC"

az automation job-schedule create \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --runbook-name "Stop-AksTestCluster" \
  --schedule-name "weekday-stop"

echo ""
echo "=================================================="
echo "✅ Auto-schedule configured!"
echo "  Cluster STARTS: Mon-Fri 07:55 UTC"
echo "  Cluster STOPS:  Mon-Fri 20:05 UTC"
echo "  Weekends:       OFF (cluster stays stopped)"
echo ""
echo "  Manual override:"
echo "  START: az aks start  -g $RESOURCE_GROUP -n $CLUSTER_NAME"
echo "  STOP:  az aks stop   -g $RESOURCE_GROUP -n $CLUSTER_NAME"
echo "=================================================="

# ════════════════════════════════════════════════════════════
# APPROACH B: GitHub Actions (alternative — no Azure Automation needed)
# Save this as .github/workflows/cluster-schedule.yml instead
# ════════════════════════════════════════════════════════════
cat << 'YAML'

# .github/workflows/cluster-schedule.yml
# ----------------------------------------
# name: AKS Test Cluster Schedule
# on:
#   schedule:
#     - cron: '55 7 * * 1-5'   # Start Mon-Fri 07:55 UTC
#     - cron: '5 20 * * 1-5'   # Stop  Mon-Fri 20:05 UTC
#   workflow_dispatch:          # manual trigger button
#     inputs:
#       action:
#         description: 'start or stop'
#         required: true
#         default: 'start'
# jobs:
#   manage-cluster:
#     runs-on: ubuntu-latest
#     steps:
#     - uses: azure/login@v1
#       with:
#         creds: ${{ secrets.AZURE_CREDENTIALS }}
#     - name: Start cluster
#       if: github.event.schedule == '55 7 * * 1-5' || inputs.action == 'start'
#       run: az aks start -g rg-ecommerce-test -n aks-ecommerce-test
#     - name: Stop cluster
#       if: github.event.schedule == '5 20 * * 1-5' || inputs.action == 'stop'
#       run: az aks stop -g rg-ecommerce-test -n aks-ecommerce-test
YAML
