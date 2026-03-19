# ============================================================
# main.tf — Root Module
# Orchestrates all child modules.
# Deploy order:
#   networking → monitoring → acr → aks → keyvault → identity → helm → automation
# ============================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # ── Remote state backend (uncomment to use Azure Blob) ────
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "sttfstateecommerce"
  #   container_name       = "tfstate"
  #   key                  = "ecommerce-test.tfstate"
  # }
}

# ── Azure Provider ────────────────────────────────────────
provider "azurerm" {
  features {
    key_vault {
      # test env: allow immediate deletion without 90-day wait
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# ── Kubernetes Provider (uses AKS credentials) ────────────
provider "kubernetes" {
  host                   = module.aks.cluster_host
  client_certificate     = base64decode(module.aks.client_certificate)
  client_key             = base64decode(module.aks.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
}

# ── Helm Provider ─────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = module.aks.cluster_host
    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  }
}

# ── Current Azure context ─────────────────────────────────
data "azurerm_client_config" "current" {}

# ── Unique suffix for globally-unique resource names ──────
resource "random_string" "kv_suffix" {
  length  = 4
  upper   = false
  special = false
}

# ── Resource Group ────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project}-${var.environment}"
  location = var.location
  tags     = var.tags
}

# ── Module: Log Analytics ─────────────────────────────────
module "monitoring" {
  source              = "./modules/monitoring"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  workspace_name      = "law-${var.project}-${var.environment}"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# ── Module: Networking ────────────────────────────────────
module "networking" {
  source              = "./modules/networking"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  project             = var.project
  environment         = var.environment
  vnet_address_space  = var.vnet_address_space
  aks_subnet_prefix   = var.aks_subnet_prefix
  appgw_subnet_prefix = var.appgw_subnet_prefix
  tags                = var.tags
}

# ── Module: Container Registry ────────────────────────────
module "acr" {
  source              = "./modules/acr"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  acr_name            = "${var.acr_name}${random_string.kv_suffix.result}"
  sku                 = var.acr_sku
  tags                = var.tags
}

# ── Module: AKS Cluster ───────────────────────────────────
module "aks" {
  source                     = "./modules/aks"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = var.location
  cluster_name               = "aks-${var.project}-${var.environment}"
  kubernetes_version         = var.kubernetes_version
  aks_subnet_id              = module.networking.aks_subnet_id
  log_analytics_workspace_id = module.monitoring.workspace_id
  acr_id                     = module.acr.acr_id
  node_vm_size               = var.node_vm_size
  node_count                 = var.node_count
  min_count                  = var.min_count
  max_count                  = var.max_count
  spot_vm_size               = var.spot_vm_size
  spot_max_count             = var.spot_max_count
  tags                       = var.tags

  depends_on = [module.networking, module.monitoring, module.acr]
}

# ── Module: Key Vault ─────────────────────────────────────
module "keyvault" {
  source              = "./modules/keyvault"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  keyvault_name       = "kv-${var.project}-${var.environment}-${random_string.kv_suffix.result}"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  admin_object_id     = data.azurerm_client_config.current.object_id
  secrets             = var.secrets
  tags                = var.tags
}

# ── Module: Managed Identities + Federated Credentials ────
module "identity" {
  source              = "./modules/identity"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  environment         = var.environment
  services            = var.services
  keyvault_id         = module.keyvault.keyvault_id
  oidc_issuer_url     = module.aks.oidc_issuer_url
  k8s_namespace       = var.k8s_namespace
  tags                = var.tags

  depends_on = [module.aks, module.keyvault]
}

# ── Module: Helm Addons ───────────────────────────────────
module "helm" {
  source            = "./modules/helm"
  letsencrypt_email = var.letsencrypt_email
  environment       = var.environment

  depends_on = [module.aks]
}

# ── Module: Cluster Auto-Shutdown Schedule ────────────────
module "automation" {
  source              = "./modules/automation"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  project             = var.project
  environment         = var.environment
  cluster_name        = module.aks.cluster_name
  subscription_id     = data.azurerm_client_config.current.subscription_id
  schedule_start_time = var.schedule_start_time
  schedule_stop_time  = var.schedule_stop_time
  tags                = var.tags

  depends_on = [module.aks]
}
