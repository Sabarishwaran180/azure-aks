output "cluster_name"     { value = azurerm_kubernetes_cluster.main.name }
output "cluster_id"       { value = azurerm_kubernetes_cluster.main.id }
output "oidc_issuer_url"  { value = azurerm_kubernetes_cluster.main.oidc_issuer_url }
output "kubelet_object_id" { value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id }

output "cluster_host" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive = true
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
  sensitive = true
}

output "client_key" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive = true
}
