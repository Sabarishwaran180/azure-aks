# ── ACR Module ────────────────────────────────────────────
# Azure Container Registry — stores Docker images for all 7 services.
# Basic SKU = $5/month, 10 GB storage, no geo-replication.

resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false   # use Managed Identity, not admin password
  tags                = var.tags
}
