# ── Networking Module ─────────────────────────────────────
# Creates VNet + 2 subnets (AKS pods + AppGW reserved)

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# AKS subnet — with Azure CNI, every pod gets an IP from this range
resource "azurerm_subnet" "aks" {
  name                 = "subnet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]

  # Required for Azure CNI
  private_endpoint_network_policies = "Disabled"
}

# Application Gateway subnet (reserved — not used in test)
resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.appgw_subnet_prefix]
}
