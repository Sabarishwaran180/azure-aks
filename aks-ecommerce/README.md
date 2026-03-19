# 🛒 AKS Production E-Commerce Platform — Advanced Learning Guide

## Architecture Overview

```
Internet
   │
   ▼
[Azure Application Gateway / NGINX Ingress Controller]
   │          (TLS termination via cert-manager + Let's Encrypt)
   ▼
[API Gateway Service]  ←── Handles routing, rate limiting, auth middleware
   │
   ├──► [User Service]         → PostgreSQL
   ├──► [Product Service]      → MongoDB
   ├──► [Order Service]        → PostgreSQL + Redis (cache)
   ├──► [Payment Service]      → PostgreSQL + Azure Key Vault (secrets)
   └──► [Notification Service] → RabbitMQ (async messaging)
   
[Frontend (React/Nginx)] ←── served via Ingress separately

Observability Stack:
  Prometheus → Grafana → AlertManager
  Azure Monitor + Container Insights
  Fluent Bit (log aggregation → Azure Log Analytics)
```

## Project Structure
```
aks-ecommerce/
├── README.md
├── infrastructure/
│   ├── 01-aks-cluster-setup.sh        # AKS cluster creation
│   ├── 02-addons-setup.sh             # NGINX, cert-manager, KEDA etc.
│   └── 03-azure-keyvault-setup.sh     # Key Vault + Workload Identity
├── namespaces/
│   └── namespaces.yaml
├── rbac/
│   ├── service-accounts.yaml
│   └── cluster-roles.yaml
├── configmaps/
│   └── app-configs.yaml
├── secrets/
│   ├── keyvault-secretprovider.yaml   # Azure Key Vault CSI Driver
│   └── tls-issuer.yaml               # cert-manager ClusterIssuer
├── network-policies/
│   └── network-policies.yaml
├── storage/
│   ├── storage-classes.yaml
│   └── persistent-volume-claims.yaml
├── databases/
│   ├── postgres-statefulset.yaml
│   ├── mongodb-statefulset.yaml
│   ├── redis-statefulset.yaml
│   └── rabbitmq-statefulset.yaml
├── services/
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── src/App.jsx
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml
│   ├── api-gateway/
│   │   ├── Dockerfile
│   │   ├── src/index.js
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── hpa.yaml
│   ├── user-service/
│   ├── product-service/
│   ├── order-service/
│   ├── payment-service/
│   └── notification-service/
├── ingress/
│   └── ingress.yaml
├── autoscaling/
│   ├── hpa-configs.yaml
│   ├── vpa-configs.yaml
│   └── keda-scaledobjects.yaml
├── monitoring/
│   ├── prometheus-values.yaml
│   ├── grafana-values.yaml
│   └── alertrules.yaml
├── pod-disruption-budgets/
│   └── pdbs.yaml
└── cronjobs/
    └── cronjobs.yaml
```

## AKS Advanced Concepts You Will Learn

| Concept | File |
|---------|------|
| Multi-namespace isolation | `namespaces/` |
| RBAC + Workload Identity | `rbac/`, `infrastructure/03-*` |
| Azure Key Vault CSI Driver | `secrets/keyvault-secretprovider.yaml` |
| Ingress + TLS (cert-manager) | `ingress/`, `secrets/tls-issuer.yaml` |
| StatefulSets (DBs) | `databases/` |
| HPA (CPU/Memory) | `autoscaling/hpa-configs.yaml` |
| KEDA (RabbitMQ queue depth) | `autoscaling/keda-scaledobjects.yaml` |
| VPA | `autoscaling/vpa-configs.yaml` |
| Network Policies (zero-trust) | `network-policies/` |
| Pod Disruption Budgets | `pod-disruption-budgets/` |
| Pod Anti-Affinity | All deployment files |
| Init Containers | `databases/`, `services/order-service/` |
| Sidecar (Fluent Bit logging) | `services/api-gateway/deployment.yaml` |
| CronJobs | `cronjobs/` |
| Azure Disk + File PVCs | `storage/` |
| Prometheus + Grafana | `monitoring/` |
| Cluster Autoscaler | `infrastructure/01-*` |
| Resource Quotas + LimitRanges | `namespaces/namespaces.yaml` |

## Quick Start

```bash
# 1. Setup AKS cluster
chmod +x infrastructure/*.sh
./infrastructure/01-aks-cluster-setup.sh

# 2. Install addons (ingress, cert-manager, KEDA, etc.)
./infrastructure/02-addons-setup.sh

# 3. Setup Key Vault + Workload Identity
./infrastructure/03-azure-keyvault-setup.sh

# 4. Deploy everything
kubectl apply -f namespaces/
kubectl apply -f rbac/
kubectl apply -f configmaps/
kubectl apply -f secrets/
kubectl apply -f storage/
kubectl apply -f databases/
kubectl apply -f services/user-service/
kubectl apply -f services/product-service/
kubectl apply -f services/order-service/
kubectl apply -f services/payment-service/
kubectl apply -f services/notification-service/
kubectl apply -f services/api-gateway/
kubectl apply -f services/frontend/
kubectl apply -f ingress/
kubectl apply -f autoscaling/
kubectl apply -f pod-disruption-budgets/
kubectl apply -f network-policies/
kubectl apply -f cronjobs/
```
