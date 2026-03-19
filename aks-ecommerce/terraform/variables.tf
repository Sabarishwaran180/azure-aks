# ============================================================
# variables.tf — All input variables with test defaults
# ============================================================

# ── Global ────────────────────────────────────────────────
variable "project" {
  description = "Project name used in all resource names"
  type        = string
  default     = "ecommerce"
}

variable "environment" {
  description = "Environment: test | staging | prod"
  type        = string
  default     = "test"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    environment  = "test"
    project      = "ecommerce"
    managed-by   = "terraform"
    auto-shutdown = "true"
  }
}

# ── Networking ────────────────────────────────────────────
variable "vnet_address_space" {
  description = "VNet address space"
  type        = string
  default     = "10.0.0.0/8"
}

variable "aks_subnet_prefix" {
  description = "AKS subnet — pods get IPs from here (Azure CNI)"
  type        = string
  default     = "10.240.0.0/16"
}

variable "appgw_subnet_prefix" {
  description = "Application Gateway subnet (reserved for future use)"
  type        = string
  default     = "10.2.0.0/16"
}

# ── AKS Cluster ───────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "node_vm_size" {
  description = "VM size for the main node pool — B2s is cheapest burstable"
  type        = string
  default     = "Standard_B2s"
  # Options (cheapest to expensive):
  # Standard_B2s   = 2 vCPU, 4 GB  = ~$31/month
  # Standard_D2s_v3 = 2 vCPU, 8 GB = ~$70/month (production)
  # Standard_D4s_v3 = 4 vCPU, 16 GB = ~$140/month (production user pool)
}

variable "node_count" {
  description = "Initial node count"
  type        = number
  default     = 1
}

variable "min_count" {
  description = "Minimum nodes for cluster autoscaler"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum nodes for cluster autoscaler"
  type        = number
  default     = 4
}

variable "spot_vm_size" {
  description = "VM size for spot node pool — 85% cheaper, can be evicted"
  type        = string
  default     = "Standard_B4ms"
}

variable "spot_max_count" {
  description = "Maximum spot nodes (0 = disabled)"
  type        = number
  default     = 5
}

# ── Container Registry ────────────────────────────────────
variable "acr_name" {
  description = "ACR name (must be globally unique, alphanumeric only)"
  type        = string
  default     = "acrecommerceprod"
}

variable "acr_sku" {
  description = "ACR SKU: Basic ($5) | Standard ($20) | Premium ($50)"
  type        = string
  default     = "Basic"
}

# ── Key Vault ─────────────────────────────────────────────
variable "secrets" {
  description = "Secrets to store in Key Vault"
  type        = map(string)
  sensitive   = true
  default = {
    postgres-password  = "SuperSecret123!"
    mongodb-password   = "MongoSecret456!"
    redis-password     = "RedisSecret789!"
    rabbitmq-password  = "RabbitSecret101!"
    jwt-secret         = "JWTSuperSecretKey2024!"
    stripe-api-key     = "sk_test_your_stripe_key"
    smtp-password      = "SmtpPassword123"
  }
}

# ── Identity ──────────────────────────────────────────────
variable "services" {
  description = "Microservice names — each gets its own Managed Identity"
  type        = list(string)
  default = [
    "api-gateway",
    "user-service",
    "product-service",
    "order-service",
    "payment-service",
    "notification-service"
  ]
}

variable "k8s_namespace" {
  description = "Kubernetes namespace where service accounts live"
  type        = string
  default     = "production"
}

# ── Monitoring ────────────────────────────────────────────
variable "log_retention_days" {
  description = "Log Analytics retention (days) — 31 = free tier"
  type        = number
  default     = 31
}

# ── Helm / cert-manager ───────────────────────────────────
variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@yourdomain.com"
}

# ── Automation Schedule ───────────────────────────────────
variable "schedule_start_time" {
  description = "UTC time to start cluster (HH:MM) — weekdays only"
  type        = string
  default     = "07:55"
}

variable "schedule_stop_time" {
  description = "UTC time to stop cluster (HH:MM) — weekdays only"
  type        = string
  default     = "20:05"
}
