# ============================================================
# imports.tf — One-shot import of role assignments that were
# created in Azure by a previous partial apply but were never
# recorded in Terraform state (causing 409 RoleAssignmentExists).
#
# DELETE THIS FILE after the next successful terraform apply.
# Leaving import blocks in place after resources are in state
# causes "resource already tracked" errors on subsequent applies.
# ============================================================

import {
  to = module.identity.azurerm_role_assignment.kv_secrets_user["api-gateway"]
  id = "/subscriptions/11045c2e-922e-4a3e-b8f6-479d75dbbf6e/resourceGroups/rg-ecommerce-test/providers/Microsoft.KeyVault/vaults/kv-ecommerce-test-ic9b/providers/Microsoft.Authorization/roleAssignments/271d3ac7-7058-cfc9-c816-c8a6746a6354"
}

import {
  to = module.identity.azurerm_role_assignment.kv_secrets_user["user-service"]
  id = "/subscriptions/11045c2e-922e-4a3e-b8f6-479d75dbbf6e/resourceGroups/rg-ecommerce-test/providers/Microsoft.KeyVault/vaults/kv-ecommerce-test-ic9b/providers/Microsoft.Authorization/roleAssignments/824a6bbb-b3f4-7d41-16f0-288a6f90a9ff"
}

import {
  to = module.identity.azurerm_role_assignment.kv_secrets_user["product-service"]
  id = "/subscriptions/11045c2e-922e-4a3e-b8f6-479d75dbbf6e/resourceGroups/rg-ecommerce-test/providers/Microsoft.KeyVault/vaults/kv-ecommerce-test-ic9b/providers/Microsoft.Authorization/roleAssignments/0d80e0bb-41f4-3089-6144-6e3931e169df"
}

import {
  to = module.identity.azurerm_role_assignment.kv_secrets_user["order-service"]
  id = "/subscriptions/11045c2e-922e-4a3e-b8f6-479d75dbbf6e/resourceGroups/rg-ecommerce-test/providers/Microsoft.KeyVault/vaults/kv-ecommerce-test-ic9b/providers/Microsoft.Authorization/roleAssignments/b9718c36-6604-5bf1-85bf-2d5d3aed9476"
}

import {
  to = module.identity.azurerm_role_assignment.kv_secrets_user["payment-service"]
  id = "/subscriptions/11045c2e-922e-4a3e-b8f6-479d75dbbf6e/resourceGroups/rg-ecommerce-test/providers/Microsoft.KeyVault/vaults/kv-ecommerce-test-ic9b/providers/Microsoft.Authorization/roleAssignments/902ea1c6-a9c4-3425-34da-6e87686a9f22"
}

import {
  to = module.identity.azurerm_role_assignment.kv_secrets_user["notification-service"]
  id = "/subscriptions/11045c2e-922e-4a3e-b8f6-479d75dbbf6e/resourceGroups/rg-ecommerce-test/providers/Microsoft.KeyVault/vaults/kv-ecommerce-test-ic9b/providers/Microsoft.Authorization/roleAssignments/318b13c9-a4fc-fa51-5aeb-20428d3672a9"
}
