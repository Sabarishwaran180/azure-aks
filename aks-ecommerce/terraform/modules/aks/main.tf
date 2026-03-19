# ── AKS Module ────────────────────────────────────────────
# Test-optimised AKS cluster:
#   - Single B2s node pool (no system/user split)
#   - No Uptime SLA ($73/month saved)
#   - No Availability Zones (no ZRS disk premium)
#   - Ephemeral OS disk ($32/month saved vs Managed)
#   - Spot node pool at 0 nodes (scales on demand)
#   - Cluster autoscaler with aggressive scale-down (5m vs 10m)
#   - OIDC + Workload Identity for secretless pod auth

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # ── System node pool ──────────────────────────────────
  default_node_pool {
    name                = "testpool"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    min_count           = var.min_count
    max_count           = var.max_count
    enable_auto_scaling = true

    # Ephemeral = no managed disk = $0 OS disk cost
    os_disk_size_gb = 30
    os_disk_type    = "Ephemeral"

    vnet_subnet_id = var.aks_subnet_id

    upgrade_settings {
      max_surge = "10%"
    }

    os_sku = "AzureLinux"
  }

  # ── Identity ──────────────────────────────────────────
  identity {
    type = "SystemAssigned"
  }

  # ── Networking (Azure CNI = pods get real VNet IPs) ───
  network_profile {
    network_plugin = "azure"   # required for NetworkPolicy
    network_policy = "azure"   # enables K8s NetworkPolicy enforcement
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  # ── Container Insights ────────────────────────────────
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # ── Workload Identity (OIDC for pod-to-Azure auth) ────
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ── Cluster Autoscaler ────────────────────────────────
  auto_scaler_profile {
    scale_down_delay_after_add  = "5m"   # was 10m in prod
    scale_down_unneeded         = "5m"   # was 10m in prod
    skip_nodes_with_system_pods = false  # allow autoscaler to remove all nodes
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count   # managed by autoscaler
    ]
  }
}

# ── Spot Node Pool ────────────────────────────────────────
# Starts at 0 nodes. Spins up when regular pool is full.
# 85–90% cheaper than regular nodes. Can be evicted in 30s.
# Acceptable for test workloads — pods reschedule on regular node.
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  name                  = "spotpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.spot_vm_size
  node_count            = 0
  min_count             = 0
  max_count             = var.spot_max_count
  enable_auto_scaling   = true
  mode                  = "User"

  priority        = "Spot"
  eviction_policy = "Delete"
  spot_max_price  = -1   # -1 = pay current spot price up to on-demand price

  node_labels = {
    "nodepool-type"                         = "spot"
    "kubernetes.azure.com/scalesetpriority" = "spot"
  }

  node_taints = [
    "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
  ]

  os_disk_type    = "Ephemeral"
  os_disk_size_gb = 30

  tags = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# ── ACR Pull Permission ───────────────────────────────────
# Allow AKS to pull images from ACR without credentials
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
