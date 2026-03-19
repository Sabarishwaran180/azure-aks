output "automation_account_name" { value = azurerm_automation_account.main.name }
output "stop_runbook_name"       { value = azurerm_automation_runbook.stop.name }
output "start_runbook_name"      { value = azurerm_automation_runbook.start.name }
