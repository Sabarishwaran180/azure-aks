# ============================================================
# outputs.tf — Values printed after terraform apply
# ============================================================

output "resource_group_name" {
  description = "Resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = module.aks.cluster_name
}

output "aks_get_credentials_command" {
  description = "Run this to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name} --overwrite-existing"
}

output "acr_login_server" {
  description = "ACR URL for docker push/pull"
  value       = module.acr.login_server
}

output "acr_login_command" {
  description = "Run this to authenticate Docker with ACR"
  value       = "az acr login --name ${var.acr_name}"
}

output "keyvault_name" {
  description = "Key Vault name"
  value       = module.keyvault.keyvault_name
}

output "keyvault_uri" {
  description = "Key Vault URI"
  value       = module.keyvault.keyvault_uri
}

output "service_client_ids" {
  description = "Managed Identity client IDs — paste these into service-accounts.yaml and keyvault-secretprovider.yaml"
  value       = module.identity.client_ids
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation"
  value       = module.aks.oidc_issuer_url
}

output "tenant_id" {
  description = "Azure Tenant ID — needed in keyvault-secretprovider.yaml"
  value       = data.azurerm_client_config.current.tenant_id
}

output "grafana_access_command" {
  description = "Port-forward to access Grafana"
  value       = "kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"
}

output "cluster_start_command" {
  description = "Start the cluster (compute billing resumes)"
  value       = "az aks start --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
}

output "cluster_stop_command" {
  description = "Stop the cluster (compute billing pauses)"
  value       = "az aks stop --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
}

output "estimated_monthly_cost" {
  description = "Rough monthly cost estimate"
  value       = "~$46/month (~₹3,864) with weekday schedule. See COST.md for full breakdown."
}
