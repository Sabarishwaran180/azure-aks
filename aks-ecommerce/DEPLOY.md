# 🚀 DEPLOY.md — Step-by-Step Deployment Guide (Test Environment)

> **Time to complete:** ~45–60 minutes for first deployment
> **Cost:** ~$46/month with schedule, ~$12/month when manually stopped

---

## BEFORE YOU START — Checklist

Run these to confirm every tool is installed:

```bash
az --version           # need >= 2.55
kubectl version --client
helm version           # need >= 3.13
docker --version       # need >= 24
node --version         # need >= 20
git --version
```

Confirm you are logged in to Azure:
```bash
az login
az account show        # confirm correct subscription is active
```

---

## STEP 1 — Fill In Your Placeholders

There are 4 files with placeholders that need your real values before running anything.

### 1a. Find your Subscription ID and Tenant ID
```bash
az account show --query "{subscriptionId:id, tenantId:tenantId}" -o table
```

### 1b. Edit the 3 infrastructure scripts

Open each file and replace `<your-subscription-id>`:

**`infrastructure/01-aks-cluster-setup.sh`**
```bash
SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"   # your subscription ID
```

**`infrastructure/02-addons-setup.sh`**
```bash
EMAIL="your-real-email@domain.com"   # Let's Encrypt needs a real email
```

**`infrastructure/03-azure-keyvault-setup.sh`**
```bash
SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### 1c. Edit secrets/keyvault-secretprovider.yaml

Replace `<your-tenant-id>` in all 4 SecretProviderClass blocks:
```bash
# Get your tenant ID
az account show --query tenantId -o tsv
```

Also replace `kv-ecommerce-prod` with `kv-ecommerce-test` in all occurrences:
```bash
# Quick find and replace (run from aks-ecommerce/ folder):
sed -i 's/kv-ecommerce-prod/kv-ecommerce-test/g' secrets/keyvault-secretprovider.yaml
sed -i 's/<your-tenant-id>/YOUR_ACTUAL_TENANT_ID/g' secrets/keyvault-secretprovider.yaml
```

> **Note:** The `<client-id>` placeholders in this file will be filled in Step 5.

---

## STEP 2 — Create the AKS Test Cluster

```bash
cd aks-ecommerce
bash infrastructure/01-aks-cluster-setup.sh
```

**What this does:**
- Creates resource group `rg-ecommerce-test`
- Creates VNet with subnet `10.240.0.0/16`
- Creates Log Analytics workspace
- Creates AKS cluster (`aks-ecommerce-test`) with 1× B2s node
- Adds spot node pool (starts at 0 nodes)
- Attaches ACR for image pulling

**Verify it worked:**
```bash
kubectl get nodes
# Expected: 1 node in Ready state
```

**Time:** ~10–15 minutes

---

## STEP 3 — Create the Azure Container Registry

```bash
az acr create \
  --resource-group rg-ecommerce-test \
  --name acrecommerceprod \
  --sku Basic \
  --admin-enabled false
```

> If the name `acrecommerceprod` is taken (globally unique), choose another and
> update `ACR_NAME` in `01-aks-cluster-setup.sh` and all `deployment.yaml` image fields.

---

## STEP 4 — Install Cluster Addons

```bash
bash infrastructure/02-addons-setup.sh
```

**What this installs:**
| Addon | Namespace | Purpose |
|-------|-----------|---------|
| NGINX Ingress | `ingress-nginx` | External traffic entry point |
| cert-manager | `cert-manager` | Auto TLS certificates |
| KEDA | `keda` | Scale notification-service to 0 |
| VPA | `vpa` | Auto right-size pod resources |
| kube-prometheus-stack | `monitoring` | Prometheus + Grafana |
| Fluent Bit | `logging` | Log shipping |

**Verify everything is running:**
```bash
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get pods -n keda
kubectl get pods -n monitoring

# Get the public IP assigned to the NGINX ingress
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Note the EXTERNAL-IP — you'll need this for DNS
```

**Time:** ~10 minutes

---

## STEP 5 — Set Up Azure Key Vault + Workload Identity

```bash
bash infrastructure/03-azure-keyvault-setup.sh
```

**What this does:**
- Creates Key Vault `kv-ecommerce-test`
- Stores 7 secrets (passwords, API keys)
- Creates 6 Managed Identities (one per service)
- Links each identity to its K8s Service Account via OIDC federation

**After it finishes, capture the client IDs printed by the script:**
```
  CLIENT_ID for api-gateway: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  CLIENT_ID for user-service: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  CLIENT_ID for product-service: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  CLIENT_ID for order-service: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  CLIENT_ID for payment-service: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  CLIENT_ID for notification-service: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

**Or retrieve them anytime:**
```bash
for svc in api-gateway user-service product-service order-service payment-service notification-service; do
  echo "$svc: $(az identity show -g rg-ecommerce-test -n id-$svc --query clientId -o tsv)"
done
```

### 5a. Update service-accounts.yaml with client IDs

Open `rbac/service-accounts.yaml` and replace each `<...-managed-identity-client-id>`:
```yaml
# api-gateway-sa
azure.workload.identity/client-id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# user-service-sa
azure.workload.identity/client-id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# ... etc for each service
```

Or use sed (replace each value individually):
```bash
# Example for api-gateway — repeat for each service with its own client ID:
CLIENT_ID=$(az identity show -g rg-ecommerce-test -n id-api-gateway --query clientId -o tsv)
sed -i "s/<api-gateway-managed-identity-client-id>/$CLIENT_ID/" rbac/service-accounts.yaml
```

### 5b. Update keyvault-secretprovider.yaml with client IDs

Same process — replace `<payment-service-managed-identity-client-id>` etc. in
`secrets/keyvault-secretprovider.yaml`.

```bash
for svc in payment user product order notification; do
  CLIENT_ID=$(az identity show -g rg-ecommerce-test -n id-${svc}-service --query clientId -o tsv 2>/dev/null || \
              az identity show -g rg-ecommerce-test -n id-api-gateway --query clientId -o tsv)
  echo "$svc: $CLIENT_ID"
done
```

**Time:** ~5 minutes

---

## STEP 6 — Build and Push Docker Images

```bash
# Log in to your ACR
az acr login --name acrecommerceprod

# Build and push all 7 images
SERVICES="api-gateway user-service product-service order-service payment-service notification-service frontend"
ACR="acrecommerceprod.azurecr.io"
TAG="1.0.0"

for SERVICE in $SERVICES; do
  echo "=== Building $SERVICE ==="
  docker build -t $ACR/$SERVICE:$TAG services/$SERVICE/
  docker push $ACR/$SERVICE:$TAG
  echo "✅ $SERVICE pushed"
done
```

**Verify images are in ACR:**
```bash
az acr repository list --name acrecommerceprod -o table
```

**Time:** ~10–15 minutes (depends on internet speed)

---

## STEP 7 — Apply Kubernetes Manifests

Apply in this exact order — each step depends on the one before it.

### 7a. Namespaces (must be first — everything else goes inside them)
```bash
kubectl apply -f namespaces/namespaces.yaml
kubectl get namespaces
# Expected: production, databases, monitoring, ingress-nginx, staging all exist
```

### 7b. RBAC (ServiceAccounts must exist before Deployments)
```bash
kubectl apply -f rbac/service-accounts.yaml
kubectl apply -f rbac/cluster-roles.yaml
kubectl get sa -n production
# Expected: api-gateway-sa, user-service-sa, etc.
```

### 7c. ConfigMaps (environment config)
```bash
kubectl apply -f configmaps/app-configs.yaml
kubectl apply -f configmaps/fluent-bit-configmap.yaml
kubectl get configmaps -n production
```

### 7d. Secrets (TLS issuer + Key Vault CSI)
```bash
kubectl apply -f secrets/tls-issuer.yaml
kubectl apply -f secrets/keyvault-secretprovider.yaml
kubectl get clusterissuer
# Expected: letsencrypt-staging and letsencrypt-production both exist
```

### 7e. Storage
```bash
kubectl apply -f storage/storage-classes.yaml
kubectl apply -f storage/persistent-volume-claims.yaml
kubectl get storageclass
# Expected: azure-disk-standard (default), azure-disk-premium-zrs, azure-files-standard
```

### 7f. Databases (StatefulSets — wait for each to be ready)
```bash
kubectl apply -f databases/postgres-statefulset.yaml
kubectl apply -f databases/mongodb-statefulset.yaml
kubectl apply -f databases/redis-statefulset.yaml
kubectl apply -f databases/rabbitmq-statefulset.yaml

# Wait for all database pods to be ready (takes 2-5 minutes)
kubectl rollout status statefulset/postgres -n databases --timeout=300s
kubectl rollout status statefulset/mongodb -n databases --timeout=300s
kubectl rollout status statefulset/redis -n databases --timeout=300s
kubectl rollout status statefulset/rabbitmq -n databases --timeout=300s

kubectl get pods -n databases
# Expected: postgres-0, mongodb-0, redis-0, rabbitmq-0 all Running
```

### 7g. Microservices
```bash
kubectl apply -f services/api-gateway/deployment.yaml
kubectl apply -f services/user-service/deployment.yaml
kubectl apply -f services/product-service/deployment.yaml
kubectl apply -f services/order-service/deployment.yaml
kubectl apply -f services/payment-service/deployment.yaml
kubectl apply -f services/notification-service/deployment.yaml
kubectl apply -f services/frontend/deployment.yaml

# Wait for all services to be ready
kubectl rollout status deployment/api-gateway -n production --timeout=300s
kubectl rollout status deployment/user-service -n production --timeout=300s
kubectl rollout status deployment/product-service -n production --timeout=300s
kubectl rollout status deployment/order-service -n production --timeout=300s
kubectl rollout status deployment/payment-service -n production --timeout=300s
kubectl rollout status deployment/frontend -n production --timeout=300s

kubectl get pods -n production
# Expected: all pods Running (notification-service will be 0 — KEDA keeps it at 0)
```

### 7h. Ingress
```bash
kubectl apply -f ingress/ingress.yaml
kubectl get ingress -n production
# Note the ADDRESS column — this is your NGINX public IP
```

### 7i. Autoscaling
```bash
kubectl apply -f autoscaling/hpa-configs.yaml
kubectl apply -f autoscaling/keda-scaledobjects.yaml
kubectl apply -f autoscaling/vpa-configs.yaml
kubectl get hpa -n production
kubectl get scaledobject -n production
kubectl get vpa -n production
```

### 7j. Pod Disruption Budgets
```bash
kubectl apply -f pod-disruption-budgets/pdbs.yaml
kubectl get pdb -n production
```

### 7k. Network Policies (apply last — activates zero-trust firewall)
```bash
kubectl apply -f network-policies/network-policies.yaml
kubectl get networkpolicies -n production
kubectl get networkpolicies -n databases
```

### 7l. Monitoring
```bash
kubectl apply -f monitoring/alertrules.yaml
kubectl get prometheusrule -n monitoring
```

### 7m. CronJobs
```bash
kubectl apply -f cronjobs/cronjobs.yaml
kubectl get cronjobs -n production
kubectl get cronjobs -n databases
```

---

## STEP 8 — Set Up Auto-Shutdown Schedule

```bash
bash infrastructure/05-cluster-schedule.sh
```

This creates Azure Automation runbooks to:
- **Start** cluster automatically Mon–Fri 7:55am UTC
- **Stop** cluster automatically Mon–Fri 8:05pm UTC
- Saves ~$20/month vs running 24/7

---

## STEP 9 — Verify Full Deployment

```bash
# All nodes healthy
kubectl get nodes

# All production pods running
kubectl get pods -n production
kubectl get pods -n databases
kubectl get pods -n monitoring

# Services have endpoints
kubectl get svc -n production
kubectl get svc -n databases

# Ingress is live
kubectl get ingress -n production

# HPA and KEDA in place
kubectl get hpa -n production
kubectl get scaledobject -n production

# VPA watching pods
kubectl get vpa -n production

# Databases accessible
kubectl exec -it postgres-0 -n databases -- psql -U appuser -c "SELECT 1"
kubectl exec -it redis-0 -n databases -c redis -- redis-cli ping
```

---

## STEP 10 — Access Services Locally (Port Forwarding)

Since this is a test cluster, use port-forwarding instead of real DNS:

```bash
# Access the API Gateway directly
kubectl port-forward svc/api-gateway 3000:80 -n production &
curl http://localhost:3000/healthz
# Expected: {"status":"ok"}

# Access the frontend
kubectl port-forward svc/frontend 8080:80 -n production &
# Open: http://localhost:8080

# Access Grafana dashboard
kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring &
# Open: http://localhost:3001  (no login needed — anonymous enabled in test)

# Access Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
# Open: http://localhost:9090

# Access RabbitMQ management UI
kubectl port-forward svc/rabbitmq 15672:15672 -n databases &
# Open: http://localhost:15672  (login: appuser / RabbitSecret101!)

# Stop all port-forwards
kill $(jobs -p)
```

---

## STEP 11 — Test Each Service

```bash
# Health checks on all services
for PORT in 3000 3001 3002 3003 3004 3005; do
  kubectl port-forward svc/$(kubectl get svc -n production \
    -o jsonpath="{.items[?(@.spec.ports[0].port==$PORT)].metadata.name}") \
    $PORT:$PORT -n production &>/dev/null &
  sleep 1
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/healthz)
  echo "Port $PORT: HTTP $STATUS"
done
kill $(jobs -p)

# Test user registration
curl -s -X POST http://localhost:3000/api/v1/users/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@test.com","password":"Test1234!"}' | jq .

# Test product listing
curl -s http://localhost:3000/api/v1/products | jq .
```

---

## QUICK DAILY WORKFLOW

```bash
# Morning — start the cluster (if not on schedule)
az aks start -g rg-ecommerce-test -n aks-ecommerce-test
kubectl wait --for=condition=Ready nodes --all --timeout=120s
kubectl get pods -n production   # confirm all running

# Evening — stop the cluster
az aks stop -g rg-ecommerce-test -n aks-ecommerce-test --no-wait
echo "Cluster stopping — compute billing paused"
```

---

## REDEPLOY A SINGLE SERVICE (after code change)

```bash
SERVICE="user-service"   # change to the service you modified

# 1. Build new image
docker build -t acrecommerceprod.azurecr.io/$SERVICE:1.0.1 services/$SERVICE/

# 2. Push to ACR
az acr login --name acrecommerceprod
docker push acrecommerceprod.azurecr.io/$SERVICE:1.0.1

# 3. Rolling update (zero downtime)
kubectl set image deployment/$SERVICE \
  $SERVICE=acrecommerceprod.azurecr.io/$SERVICE:1.0.1 \
  -n production

# 4. Watch rollout
kubectl rollout status deployment/$SERVICE -n production

# 5. If something is wrong, rollback instantly
kubectl rollout undo deployment/$SERVICE -n production
```

---

## TEARDOWN (delete everything)

```bash
# Delete all K8s resources
kubectl delete namespace production databases monitoring ingress-nginx keda vpa logging

# Delete the AKS cluster and all Azure resources
az group delete --name rg-ecommerce-test --yes --no-wait

echo "All resources queued for deletion"
echo "Disks and Key Vault will be deleted too (~7 day soft-delete for KV)"
```

---

## TROUBLESHOOTING

| Problem | Command | Fix |
|---------|---------|-----|
| Pod stuck in `Pending` | `kubectl describe pod <name> -n production` | Check events — usually quota or node resources |
| Pod in `CrashLoopBackOff` | `kubectl logs <pod> -n production --previous` | See crash reason in previous container logs |
| Secret not mounting | `kubectl describe pod <pod> -n production` | Check CSI driver events — wrong client-id or KV name |
| Service unreachable | `kubectl get endpoints <svc> -n production` | No endpoints = readinessProbe failing |
| Image pull error | `kubectl describe pod <pod> -n production` | ACR not attached or wrong image tag |
| Database not ready | `kubectl logs postgres-0 -n databases` | Init container or password mismatch |
| Network policy blocking | `kubectl get networkpolicies -n production` | Temporarily delete default-deny to isolate |
| VPA restarting pods | `kubectl describe vpa <name> -n production` | Expected — VPA adjusting resources, wait 1-2min |
| Cluster not starting | `az aks show -g rg-ecommerce-test -n aks-ecommerce-test --query powerState` | Check Azure Portal for errors |

```bash
# Most useful debug command — shows all events sorted by time
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20
kubectl get events -n databases --sort-by='.lastTimestamp' | tail -20
```
