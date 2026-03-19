# ── Identity Module ───────────────────────────────────────
# Creates one Managed Identity per microservice.
# Each identity gets:
#   1. Key Vault Secrets User role (read secrets)
#   2. Federated credential linking it to K8s Service Account (OIDC)
#
# Result: pods present a K8s token → Azure exchanges it for an
# Azure token → pod reads Key Vault secrets. Zero static credentials.

resource "azurerm_user_assigned_identity" "services" {
  for_each = toset(var.services)

  name                = "id-${each.key}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ── Key Vault read permission per identity ────────────────
resource "azurerm_role_assignment" "kv_secrets_user" {
  for_each = toset(var.services)

  scope                = var.keyvault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.services[each.key].principal_id
}

# ── OIDC Federated Credential ─────────────────────────────
# Links K8s ServiceAccount → Azure Managed Identity
# No passwords, certificates, or client secrets needed
resource "azurerm_federated_identity_credential" "services" {
  for_each = toset(var.services)

  name                = "fc-${each.key}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.services[each.key].id

  issuer   = var.oidc_issuer_url
  subject  = "system:serviceaccount:${var.k8s_namespace}:${each.key}-sa"
  audience = ["api://AzureADTokenExchange"]
}
