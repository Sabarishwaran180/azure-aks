# ── Automation Module ─────────────────────────────────────
# Azure Automation Account with two PowerShell runbooks:
#   Stop-AksCluster — scales nodes to 0, stops the cluster
#   Start-AksCluster — starts the cluster
#
# Schedules:
#   weekday-start — Mon-Fri 07:55 UTC
#   weekday-stop  — Mon-Fri 20:05 UTC
#
# Free tier: 500 job minutes/month.
# 2 runs/day × 22 days × ~2 min = 88 min → stays within free tier.

resource "azurerm_automation_account" "main" {
  name                = "aa-${var.project}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Free"   # 500 job minutes/month included

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ── Grant Automation Account Contributor on resource group ─
# Needed to call az aks start/stop
resource "azurerm_role_assignment" "automation_contributor" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
}

# ── STOP Runbook ──────────────────────────────────────────
resource "azurerm_automation_runbook" "stop" {
  name                    = "Stop-AksCluster"
  automation_account_name = azurerm_automation_account.main.name
  resource_group_name     = var.resource_group_name
  location                = var.location
  runbook_type            = "PowerShell"
  log_progress            = false
  log_verbose             = false

  content = <<-PS1
    param(
      [string]$ResourceGroup = "${var.resource_group_name}",
      [string]$ClusterName   = "${var.cluster_name}"
    )
    Connect-AzAccount -Identity
    Write-Output "Stopping cluster: $ClusterName"
    Stop-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName -Force
    Write-Output "Cluster stopped. Compute billing paused."
  PS1

  tags = var.tags
}

# ── START Runbook ─────────────────────────────────────────
resource "azurerm_automation_runbook" "start" {
  name                    = "Start-AksCluster"
  automation_account_name = azurerm_automation_account.main.name
  resource_group_name     = var.resource_group_name
  location                = var.location
  runbook_type            = "PowerShell"
  log_progress            = false
  log_verbose             = false

  content = <<-PS1
    param(
      [string]$ResourceGroup = "${var.resource_group_name}",
      [string]$ClusterName   = "${var.cluster_name}"
    )
    Connect-AzAccount -Identity
    Write-Output "Starting cluster: $ClusterName"
    Start-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
    Write-Output "Cluster started."
  PS1

  tags = var.tags
}

# ── Schedule: Start Mon-Fri 07:55 UTC ────────────────────
resource "azurerm_automation_schedule" "start" {
  name                    = "weekday-start"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Week"
  interval                = 1
  timezone                = "UTC"
  start_time              = "${formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))}T${var.schedule_start_time}:00+00:00"
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]   # don't re-create on every apply
  }
}

# ── Schedule: Stop Mon-Fri 20:05 UTC ─────────────────────
resource "azurerm_automation_schedule" "stop" {
  name                    = "weekday-stop"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Week"
  interval                = 1
  timezone                = "UTC"
  start_time              = "${formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))}T${var.schedule_stop_time}:00+00:00"
  week_days               = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  lifecycle {
    ignore_changes = [start_time]
  }
}

# ── Link schedules to runbooks ────────────────────────────
resource "azurerm_automation_job_schedule" "start" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.main.name
  runbook_name            = azurerm_automation_runbook.start.name
  schedule_name           = azurerm_automation_schedule.start.name
}

resource "azurerm_automation_job_schedule" "stop" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.main.name
  runbook_name            = azurerm_automation_runbook.stop.name
  schedule_name           = azurerm_automation_schedule.stop.name
}
