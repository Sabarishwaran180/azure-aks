# ============================================================
# TERRAFORM.md — How to Deploy with Terraform
# ============================================================

## Folder Structure

```
terraform/
├── main.tf                   ← root module, calls all child modules
├── variables.tf              ← all input variables with test defaults
├── outputs.tf                ← values printed after apply
├── terraform.tfvars.example  ← copy to terraform.tfvars and fill in
├── .gitignore                ← keeps secrets out of Git
└── modules/
    ├── networking/           ← VNet + subnets
    ├── monitoring/           ← Log Analytics Workspace
    ├── acr/                  ← Azure Container Registry
    ├── aks/                  ← AKS cluster + spot node pool
    ├── keyvault/             ← Key Vault + 7 secrets
    ├── identity/             ← 6 Managed Identities + OIDC federation
    ├── helm/                 ← NGINX, cert-manager, KEDA, VPA, Prometheus
    └── automation/           ← Auto start/stop schedule
```

---

## Step 1 — Install Terraform

```bash
# Windows (winget)
winget install HashiCorp.Terraform

# Verify
terraform --version   # need >= 1.6
```

---

## Step 2 — Set Up Variables

```bash
cd aks-ecommerce/terraform

# Copy example and fill in your values
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
acr_name          = "yourUniqueAcrName123"   # must be globally unique
letsencrypt_email = "your@email.com"

secrets = {
  postgres-password = "YourStrongPassword1!"
  mongodb-password  = "YourStrongPassword2!"
  redis-password    = "YourStrongPassword3!"
  rabbitmq-password = "YourStrongPassword4!"
  jwt-secret        = "YourJWTSecretKeyMin32CharsLong!!"
  stripe-api-key    = "sk_test_your_actual_stripe_key"
  smtp-password     = "YourSMTPPassword"
}
```

---

## Step 3 — Authenticate to Azure

```bash
az login
az account set --subscription "your-subscription-id"

# Verify you're on the right subscription
az account show --query "{name:name, id:id}" -o table
```

---

## Step 4 — Initialise Terraform

```bash
terraform init
# Downloads providers: azurerm, kubernetes, helm, random
# Output: "Terraform has been successfully initialized!"
```

---

## Step 5 — Preview Changes

```bash
terraform plan -out=tfplan
# Shows exactly what will be created/modified/destroyed
# Review carefully before applying
```

Expected plan summary:
```
Plan: 47 to add, 0 to change, 0 to destroy
```

---

## Step 6 — Deploy Everything

```bash
terraform apply tfplan
# Takes ~20–25 minutes total

# What happens:
#  0–2 min:   Resource group, VNet, Log Analytics, ACR
#  2–18 min:  AKS cluster creation (longest step)
#  18–20 min: Key Vault + secrets + Managed Identities
#  20–25 min: Helm charts (NGINX, Prometheus, etc.)
#  25 min:    Automation schedules
```

---

## Step 7 — Read the Outputs

After apply finishes, Terraform prints:

```bash
terraform output

# Key outputs:
#   aks_get_credentials_command  → configure kubectl
#   service_client_ids           → paste into K8s YAML files
#   tenant_id                    → paste into keyvault-secretprovider.yaml
#   acr_login_server             → use in docker push commands
```

---

## Step 8 — Configure kubectl

```bash
# Copy the command from terraform output:
az aks get-credentials --resource-group rg-ecommerce-test --name aks-ecommerce-test --overwrite-existing

# Verify cluster access
kubectl get nodes
kubectl get pods -A
```

---

## Step 9 — Update K8s YAML Placeholders

Terraform creates the Managed Identities and prints their client IDs.
You need to paste them into 2 YAML files.

```bash
# Get all client IDs at once
terraform output service_client_ids
# Output:
# {
#   "api-gateway"          = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   "notification-service" = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   "order-service"        = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   "payment-service"      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   "product-service"      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   "user-service"         = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# }

# Get tenant ID
terraform output tenant_id
```

Edit these two files with the values above:
- `rbac/service-accounts.yaml` → replace `<...-managed-identity-client-id>`
- `secrets/keyvault-secretprovider.yaml` → replace `<...-managed-identity-client-id>` and `<your-tenant-id>`

---

## Step 10 — Apply K8s Manifests

```bash
cd ..   # back to aks-ecommerce/

kubectl apply -f namespaces/namespaces.yaml
kubectl apply -f rbac/
kubectl apply -f configmaps/
kubectl apply -f secrets/
kubectl apply -f storage/
kubectl apply -f databases/
kubectl apply -f services/api-gateway/deployment.yaml
kubectl apply -f services/user-service/deployment.yaml
kubectl apply -f services/product-service/deployment.yaml
kubectl apply -f services/order-service/deployment.yaml
kubectl apply -f services/payment-service/deployment.yaml
kubectl apply -f services/notification-service/deployment.yaml
kubectl apply -f services/frontend/deployment.yaml
kubectl apply -f ingress/
kubectl apply -f autoscaling/
kubectl apply -f pod-disruption-budgets/
kubectl apply -f network-policies/
kubectl apply -f monitoring/alertrules.yaml
kubectl apply -f cronjobs/
```

---

## Useful Terraform Commands

```bash
# See current state of all resources
terraform show

# See only outputs
terraform output

# Refresh state from Azure (sync if changed outside Terraform)
terraform refresh

# Destroy everything (careful!)
terraform destroy

# Destroy only one module
terraform destroy -target=module.automation

# Re-apply only one module
terraform apply -target=module.helm

# Format code
terraform fmt -recursive

# Validate syntax
terraform validate
```

---

## Remote State (recommended for teams)

Store state in Azure Blob so multiple people can collaborate:

```bash
# Create storage for Terraform state
az group create -n rg-tfstate -l eastus
az storage account create -n sttfstateecommerce -g rg-tfstate --sku Standard_LRS
az storage container create -n tfstate --account-name sttfstateecommerce

# Uncomment the backend block in main.tf, then:
terraform init -reconfigure
```

---

## Cost Estimate

```
After terraform apply, total resources created: ~47
Estimated monthly cost: ~₹3,864 (~$46) with weekday schedule
See COST.md for full breakdown.
```
