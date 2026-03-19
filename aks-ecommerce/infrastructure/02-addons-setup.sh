#!/bin/bash
# ============================================================
# 02-addons-setup.sh
# Install production addons via Helm:
#   - NGINX Ingress Controller
#   - cert-manager (TLS certificates)
#   - KEDA (event-driven autoscaler)
#   - Metrics Server
#   - Vertical Pod Autoscaler (VPA)
#   - Prometheus + Grafana (kube-prometheus-stack)
#   - Fluent Bit (log shipping)
# ============================================================

set -euo pipefail

RESOURCE_GROUP="rg-ecommerce-test"        # was rg-ecommerce-prod
CLUSTER_NAME="aks-ecommerce-test"         # was aks-ecommerce-prod
EMAIL="admin@yourdomain.com"
DOMAIN="ecommerce.yourdomain.com"

echo "=================================================="
echo " Installing AKS Production Addons"
echo "=================================================="

# Get credentials
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME"

# Add Helm repos
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add kedacore https://kedacore.github.io/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add fluent https://fluent.github.io/helm-charts
helm repo add cowboysysop https://cowboysysop.github.io/charts
helm repo update

# ---- 1. NGINX Ingress Controller ----
echo "📦 Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=1 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.admissionWebhooks.enabled=true \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"=true \
  --set controller.podAnnotations."prometheus\.io/port"=10254 \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=64Mi \
  --set controller.resources.limits.cpu=200m \
  --set controller.resources.limits.memory=256Mi \
  --wait
  # TEST: replicaCount=1 (was 2), halved resources

echo "✅ NGINX Ingress installed"

# Get the Ingress public IP
INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "  Ingress External IP: $INGRESS_IP"
echo "  → Add DNS A record: $DOMAIN → $INGRESS_IP"

# ---- 2. cert-manager ----
echo "📦 Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set global.leaderElection.namespace=cert-manager \
  --set replicaCount=1 \
  --set resources.requests.cpu=10m \
  --set resources.requests.memory=32Mi \
  --wait
  # TEST: replicaCount=1 (was 2)

echo "✅ cert-manager installed"

# Create ClusterIssuer for Let's Encrypt (see secrets/tls-issuer.yaml)
kubectl apply -f ../secrets/tls-issuer.yaml

# ---- 3. KEDA ----
echo "📦 Installing KEDA..."
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set resources.operator.requests.cpu=100m \
  --set resources.operator.requests.memory=100Mi \
  --wait

echo "✅ KEDA installed"

# ---- 4. Metrics Server (should already be in AKS, ensure it's running) ----
kubectl top nodes || echo "Metrics server may need a moment..."

# ---- 5. VPA (Vertical Pod Autoscaler) ----
echo "📦 Installing VPA..."
helm upgrade --install vpa cowboysysop/vertical-pod-autoscaler \
  --namespace vpa \
  --create-namespace \
  --wait

echo "✅ VPA installed"

# ---- 6. Prometheus + Grafana (kube-prometheus-stack) ----
echo "📦 Installing kube-prometheus-stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values ../monitoring/prometheus-values.yaml \
  --wait --timeout 10m

echo "✅ Prometheus + Grafana installed"
echo "  Access Grafana: kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"
echo "  Default creds: admin / prom-operator"

# ---- 7. Fluent Bit (log aggregation) ----
echo "📦 Installing Fluent Bit..."
helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace logging \
  --create-namespace \
  --set resources.requests.cpu=20m \
  --set resources.requests.memory=32Mi \
  --set resources.limits.cpu=100m \
  --set resources.limits.memory=128Mi \
  --wait
  # TEST: halved resources (was 100m/128Mi requests, 500m/256Mi limits)

echo "✅ Fluent Bit installed"

echo ""
echo "=================================================="
echo "✅ All Addons Installed!"
echo ""
echo "📋 Summary:"
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get pods -n keda
kubectl get pods -n monitoring
kubectl get pods -n logging
echo "=================================================="
