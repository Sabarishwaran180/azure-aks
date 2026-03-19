output "client_ids" {
  description = "Map of service name → Managed Identity client ID. Paste into service-accounts.yaml."
  value = {
    for svc in var.services :
    svc => azurerm_user_assigned_identity.services[svc].client_id
  }
}

output "principal_ids" {
  value = {
    for svc in var.services :
    svc => azurerm_user_assigned_identity.services[svc].principal_id
  }
}
