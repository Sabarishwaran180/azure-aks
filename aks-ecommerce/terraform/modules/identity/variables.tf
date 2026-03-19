variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "environment"         { type = string }
variable "k8s_namespace"       { type = string }
variable "oidc_issuer_url"     { type = string }
variable "keyvault_id"         { type = string }
variable "tags"                { type = map(string) }
variable "services" {
  type = list(string)
}
