# ── Key Vault Module ──────────────────────────────────────
# Test config: Standard SKU, 7-day retention, no purge protection.
# All 7 app secrets stored here — pods read them via CSI driver.

resource "azurerm_key_vault" "main" {
  name                = var.keyvault_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"   # was premium in prod (HSM keys = $1/key)

  # Test-friendly: can delete vault immediately, no 90-day wait
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  enable_rbac_authorization = true   # use RBAC roles, not access policies

  tags = var.tags
}

# ── Grant current Terraform principal admin access ────────
# Needed to create and read secrets during terraform apply
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.admin_object_id
}

# ── Store all secrets ─────────────────────────────────────
# for_each over the secrets map — one resource per secret
resource "azurerm_key_vault_secret" "secrets" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  name         = each.key
  value        = var.secrets[each.key]
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_admin]
}
