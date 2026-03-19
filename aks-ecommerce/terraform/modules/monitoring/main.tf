# ── Monitoring Module ─────────────────────────────────────
# Log Analytics Workspace for Container Insights.
# Free tier: 5 GB/day ingestion — test cluster stays within this.

resource "azurerm_log_analytics_workspace" "main" {
  name                = var.workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}
