variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "project"             { type = string }
variable "environment"         { type = string }
variable "vnet_address_space"  { type = string }
variable "aks_subnet_prefix"   { type = string }
variable "appgw_subnet_prefix" { type = string }
variable "tags"                { type = map(string) }
