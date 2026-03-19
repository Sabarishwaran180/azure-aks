# 💰 COST.md — Detailed Monthly Cost Per Resource

> **Pricing basis:** Azure East US, Pay-as-you-go, Linux VMs, October 2024.
> All figures are estimates. Use [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator)
> for exact quotes with your discount tier (Dev/Test, Reserved, Savings Plan).

---

## SECTION 1 — Full Monthly Bill (Every Resource)

### 1A. COMPUTE — Virtual Machines

| Resource | SKU | vCPU | RAM | $/hour | Nodes | Hours/mo | Monthly |
|----------|-----|------|-----|--------|-------|----------|---------|
| **PRODUCTION** | | | | | | | |
| System node pool | D2s_v3 | 2 | 8 GB | $0.096 | 2 | 730 | **$140** |
| User node pool | D4s_v3 | 4 | 16 GB | $0.192 | 2 | 730 | **$280** |
| Spot pool (idle) | NC6s_v3 | 6 | 112 GB | ~$0.09 spot | 0 | 0 | **$0** |
| **TEST** | | | | | | | |
| Single pool (min) | B2s | 2 | 4 GB | $0.042 | 1 | 730 | **$31** |
| Single pool (max) | B2s | 2 | 4 GB | $0.042 | 4 | 730 | **$123** |
| Spot pool (idle) | B4ms spot | 4 | 16 GB | ~$0.012 spot | 0 | 0 | **$0** |
| **TEST + schedule** | | | | | | | |
| Weekdays 8am–8pm | B2s | 2 | 4 GB | $0.042 | 1 | 260 | **$11** |
| Weekend / overnight | B2s | 2 | 4 GB | $0.042 | 0 | 0 | **$0** |

> `az aks stop` = VMs **deallocated** = $0 compute. You only pay for disks.
> Spot nodes can be 85–90% cheaper: B2s spot ≈ $0.005/hour vs $0.042/hour.

---

### 1B. AKS CONTROL PLANE

| Feature | Production | Testing | Notes |
|---------|-----------|---------|-------|
| AKS cluster management | **$0** | **$0** | Always free |
| Uptime SLA (`--uptime-sla`) | **$73/month** | **$0** | Removed in test |
| SLA without flag | 99.5% | 99.5% | Good enough for testing |

---

### 1C. AZURE DISKS (Persistent Volumes)

Each `PersistentVolumeClaim` creates an Azure Managed Disk. Billed even when cluster is stopped.

| PVC | Mount | Size | Disk Type | $/GB/month | Monthly |
|-----|-------|------|-----------|-----------|---------|
| **PRODUCTION disks** | | | | | |
| postgres-data | PostgreSQL | 20 Gi | Premium SSD ZRS | $0.205 | **$4.10** |
| mongodb-data | MongoDB | 20 Gi | Premium SSD ZRS | $0.205 | **$4.10** |
| redis-data | Redis | 5 Gi | Standard SSD LRS | $0.08 | **$0.40** |
| rabbitmq-data | RabbitMQ | 5 Gi | Standard SSD LRS | $0.08 | **$0.40** |
| prometheus-data | Prometheus | 50 Gi | Premium SSD ZRS | $0.205 | **$10.25** |
| grafana-data | Grafana | 10 Gi | Standard SSD LRS | $0.08 | **$0.80** |
| backup-pvc | CronJob backups | 50 Gi | Standard SSD LRS | $0.08 | **$4.00** |
| static-assets-pvc | Azure Files | 10 Gi | Premium Files LRS | $0.21 | **$2.10** |
| product-images-pvc | Azure Files | 50 Gi | Premium Files LRS | $0.21 | **$10.50** |
| OS disks (4 nodes) | Nodes | 100 Gi×4 | Standard SSD | $0.08 | **$32.00** |
| | | | | **TOTAL** | **$68.65** |
| **TEST disks** | | | | | |
| postgres-data | PostgreSQL | 5 Gi | Standard SSD LRS | $0.08 | **$0.40** |
| mongodb-data | MongoDB | 5 Gi | Standard SSD LRS | $0.08 | **$0.40** |
| redis-data | Redis | 5 Gi | Standard SSD LRS | $0.08 | **$0.40** |
| rabbitmq-data | RabbitMQ | 5 Gi | Standard SSD LRS | $0.08 | **$0.40** |
| prometheus-data | Prometheus | 8 Gi | Standard SSD LRS | $0.08 | **$0.64** |
| grafana-data | Grafana | 2 Gi | Standard SSD LRS | $0.08 | **$0.16** |
| backup-pvc | CronJob backups | 50 Gi | Standard SSD LRS | $0.08 | **$4.00** |
| OS disk (1 node) | Node | 50 Gi | Ephemeral | $0 | **$0** |
| | | | | **TOTAL** | **$6.40** |

> **Disk tip:** Delete unused PVCs immediately. Orphaned disks cost money 24/7.
> `kubectl get pvc -A` — any PVC not in `Bound` state is wasted money.

---

### 1D. NETWORKING

| Resource | Unit | Rate | Production | Testing |
|----------|------|------|-----------|---------|
| Azure Load Balancer (NGINX) | per LB/month | $18.00 | **$36** (2 LB) | **$18** (1 LB) |
| Public IP address (static) | per IP/month | $3.65 | **$7.30** (2) | **$3.65** (1) |
| Egress data transfer | per GB | $0.087 | ~$5–20 | ~$1–3 |
| VNet peering | per GB | $0.01 | negligible | $0 |
| **Networking total** | | | **~$50** | **~$23** |

> Load Balancer and Public IP are charged **even when the cluster is stopped**.
> To save ~$22/month: delete the NGINX LB when not testing, recreate as needed.

---

### 1E. AZURE CONTAINER REGISTRY

| SKU | Storage | Webhooks | Geo-replication | Monthly |
|-----|---------|----------|-----------------|---------|
| Basic | 10 GB | 2 | No | **$5** |
| Standard | 100 GB | 10 | No | **$20** |
| Premium (production) | 500 GB | 100 | Yes | **$50** |

> Test env: use **Basic** ($5). Production: **Premium** for geo-replication + private endpoints.

---

### 1F. AZURE KEY VAULT

| Operation type | Free operations | Rate beyond free | Typical test usage | Monthly |
|----------------|----------------|------------------|--------------------|---------|
| Secret operations | 10,000/month | $0.03/10k | ~5,000/month | **$0** |
| Key operations | 10,000/month | $0.03/10k | ~2,000/month | **$0** |
| HSM key (Premium SKU) | — | $1.00/key/month | 0 HSM keys | **$0** |
| Soft delete storage | — | $0.023/GB | negligible | **~$0** |
| **Key Vault total** | | | | **~$0–1/month** |

---

### 1G. LOG ANALYTICS WORKSPACE

| Tier | Free allowance | Rate beyond | Retention | Test usage | Monthly |
|------|---------------|-------------|-----------|------------|---------|
| PerGB2018 | 5 GB/day free | $2.30/GB | 31 days free | < 5 GB/day | **$0** |
| Beyond free | — | $2.30/GB | — | — | — |
| Extended retention | — | $0.10/GB/month | 90+ days | disabled | **$0** |

> Test cluster with 1 node generates < 1 GB/day logs. Stays within free tier.
> Production with 6 nodes + all services ≈ 8–15 GB/day = **$7–23/month**.

---

### 1H. AZURE AUTOMATION (cluster schedule)

| Feature | Free tier | Rate | Monthly |
|---------|----------|------|---------|
| Job run minutes | 500 min/month free | $0.002/min | **$0** |
| Start/Stop runs | 2 runs/day × 22 days = 44 runs | each ~2 min = 88 min | **$0** |

---

### 1I. HELM ADDONS — Extra Pod Resource Costs

Addons consume node CPU and RAM — fewer pods needed = smaller nodes:

| Addon | Pods | CPU request | RAM request | Node cost impact |
|-------|------|------------|------------|-----------------|
| NGINX Ingress (2 pods) | 2 | 200m total | 180Mi | ~$2/month |
| cert-manager (3 pods) | 3 | 30m total | 96Mi | ~$0.50/month |
| KEDA (2 pods) | 2 | 200m total | 200Mi | ~$1/month |
| VPA (3 pods) | 3 | 150m total | 300Mi | ~$1.50/month |
| Prometheus | 1 | 100m | 512Mi | ~$1.50/month |
| Grafana | 1 | 50m | 128Mi | ~$0.50/month |
| Fluent Bit (per node) | 1/node | 100m | 128Mi | ~$0.50/node |
| node-exporter (per node) | 1/node | 10m | 64Mi | ~$0.20/node |
| kube-state-metrics | 1 | 10m | 64Mi | ~$0.20/month |

> These are **opportunity costs** — if addons weren't there, you could fit more app pods.

---

## SECTION 2 — Monthly Total Per Scenario

### Scenario A — Production 24/7

```
Resource                          Monthly Cost
────────────────────────────────────────────────
VMs: 2× D2s_v3 + 2× D4s_v3       $420.00
AKS Uptime SLA                     $73.00
ACR Premium                        $50.00
Azure Disks (prod sizes)           $68.65
Load Balancer (2×)                 $36.00
Public IPs (2×)                    $7.30
Log Analytics (above free tier)    $20.00
Key Vault                          $1.00
Egress data transfer               $10.00
────────────────────────────────────────────────
TOTAL PRODUCTION 24/7              ~$686/month
```

---

### Scenario B — Test Cluster 24/7 (no schedule)

```
Resource                          Monthly Cost
────────────────────────────────────────────────
VMs: 1× B2s                        $31.00
AKS control plane                   $0.00
ACR Basic                           $5.00
Azure Disks (test sizes)            $6.40
Load Balancer (1×)                  $18.00
Public IP (1×)                      $3.65
Log Analytics (within free tier)    $0.00
Key Vault                           $1.00
Egress data                         $2.00
────────────────────────────────────────────────
TOTAL TEST 24/7                    ~$67/month
────────────────────────────────────────────────
SAVING vs production 24/7          $619/month (90%)
```

---

### Scenario C — Test Cluster + Schedule (weekdays 8am–8pm) ✅ THIS CONFIG

```
Resource                          Hours ON  Rate        Monthly Cost
────────────────────────────────────────────────────────────────────
VM: 1× B2s (running hours)        260h     $0.042/h    $10.92
VM: 1× B2s (stopped hours)        460h     $0.000/h    $0.00
ACR Basic                         always   —            $5.00
Azure Disks (9 disks, always on)  always   —            $6.40
Load Balancer                     always   —            $18.00
Public IP                         always   —            $3.65
Log Analytics                     always   —            $0.00
Key Vault                         always   —            $1.00
Egress                            260h     ~$0.50       $0.50
────────────────────────────────────────────────────────────────────
TOTAL TEST + SCHEDULE              ~$46/month
────────────────────────────────────────────────────────────────────
SAVING vs production 24/7         $640/month (93%)
```

---

### Scenario D — Test Cluster + Schedule + Spot Nodes

```
Resource                          Monthly Cost
────────────────────────────────────────────────
VM: 1× B2s regular (system)        $10.92  (260h running)
VM: spot pool when needed           $1–3   (90% off, 0 when idle)
ACR Basic                           $5.00
Azure Disks                         $6.40
Load Balancer                       $18.00
Public IP                           $3.65
Other services                      $1.50
────────────────────────────────────────────────
TOTAL SPOT + SCHEDULE              ~$47/month
(spot pool saves money only when   it scales beyond 1 regular node)
```

---

### Scenario E — Bare Minimum (cluster stopped, disks only)

When you run `az aks stop` manually and leave it stopped:

```
Resource                          Monthly Cost
────────────────────────────────────────────────
VMs                                 $0.00  ← deallocated
Azure Disks (9 disks, still exist)  $6.40  ← always billed
Load Balancer                       $18.00 ← still billed!
Public IP                           $3.65  ← still billed!
ACR Basic                           $5.00
Key Vault                           $1.00
────────────────────────────────────────────────
TOTAL CLUSTER STOPPED              ~$34/month

To save the LB + IP cost (~$22): delete and recreate NGINX ingress
  kubectl delete svc ingress-nginx-controller -n ingress-nginx
  (recreate with helm when needed — takes ~2 minutes)

With LB deleted:                   ~$12/month (disks + ACR + KV only)
```

---

## SECTION 3 — Cost Per Service (what runs inside the cluster)

How much does each microservice cost in compute on a B2s node ($0.042/h)?

```
A B2s node has: 2 vCPU (2000m), 4 GB RAM (4096 Mi)

After VPA Auto settles (measured typical usage):

Service                 CPU req   RAM req   % of B2s node   $/month of 1 pod
──────────────────────────────────────────────────────────────────────────────
api-gateway             ~30m      ~80Mi     1.5% CPU/2% RAM  $0.63
user-service            ~30m      ~90Mi     1.5% CPU/2% RAM  $0.63
product-service         ~45m      ~100Mi    2.2% CPU/2.5%    $0.95
order-service           ~30m      ~90Mi     1.5% CPU/2.2%    $0.63
payment-service         ~30m      ~90Mi     1.5% CPU/2.2%    $0.63
notification-service    ~25m      ~80Mi     1.2% CPU/2%      $0.52
frontend (nginx)        ~10m      ~32Mi     0.5% CPU/0.8%    $0.21
──────────────────────────────────────────────────────────────────────────────
All 7 services (1 pod each):
  Total CPU req:  ~200m  (10% of 1 node)
  Total RAM req:  ~562Mi (14% of 1 node)
  7 services fit easily on 1 B2s node

Databases (also on node):
  PostgreSQL              ~50m      ~128Mi    2.5% CPU/3.1%    $1.05
  MongoDB                 ~50m      ~128Mi    2.5% CPU/3.1%    $1.05
  Redis                   ~25m      ~64Mi     1.2% CPU/1.6%    $0.52
  RabbitMQ                ~50m      ~64Mi     2.5% CPU/1.6%    $1.05

System addons on node:
  NGINX, cert-manager, KEDA, VPA, Fluent Bit, node-exporter etc.
  Total: ~250m CPU, ~800Mi RAM

Grand total on 1 B2s (2000m CPU, 4096Mi RAM):
  Used:  ~625m CPU (31%), ~1554Mi RAM (38%)
  Free:  ~1375m CPU (69%), ~2542Mi RAM (62%)   → fits comfortably
```

---

## SECTION 4 — Cost Impact of Each Config Change

```
Change Made                        Direct Saving    Mechanism
──────────────────────────────────────────────────────────────────────────────
Remove --uptime-sla                $73/month        No SLA surcharge
B2s instead of D4s_v3             $150/month        Cheaper VM SKU per node
1 node min (was 4 min)            $120/month        3 fewer always-on VMs
VPA Auto (right-sizes requests)   $0–30/month       Packs pods tighter on fewer nodes
HPA minReplicas: 2→1              $0–30/month       6 fewer idle pods = 1 node sometimes freed
KEDA scale-to-zero                $0–2/month        notification-service: 0 pods when idle
PDB maxUnavailable: 1             $0–30/month       Cluster autoscaler CAN remove nodes now
Prometheus storage: 50Gi→8Gi     $4/month          Disk cost direct
Prometheus RAM: 2Gi→512Mi        $0/month          Enables running on smaller node
AlertManager disabled             $0/month          Saves 128Mi RAM only
Standard disk (was Premium ZRS)   $2.50/month       Direct per-GB disk cost
LimitRange cpu: 100m→25m         $0–30/month       Scheduler packs pods tighter
Cluster schedule (8h/5d)          $20/month         VM compute off 64% of month
──────────────────────────────────────────────────────────────────────────────
TOTAL MAXIMUM SAVING              ~$450/month vs prod 24/7
```

---

## SECTION 5 — Cost Ladder

```
Level   Config                              Monthly    vs Prod
─────────────────────────────────────────────────────────────────
0       Production 24/7 (no changes)       ~$686      baseline
1       Test cluster (B2s, no SLA)         ~$67       -90%
2       + weekday schedule 8am-8pm          ~$46       -93%
3       + VPA Auto + HPA min=1              ~$40       -94%
4       + delete LB when stopped            ~$24       -96%
5       + spot node pool for app pods        ~$18       -97%
6       + manual stop when done testing     ~$12       -98%
─────────────────────────────────────────────────────────────────
THIS CONFIG = Level 2–3 automatically = ~$40/month
```

---

## SECTION 6 — Commands to Monitor Spend Live

```bash
# Current month cost for this resource group
az consumption usage list \
  --billing-period-name $(date +%Y%m) \
  --query "sort_by([?contains(instanceName,'ecommerce')],&pretaxCost)[-10:].\
{resource:instanceName, cost:pretaxCost}" \
  --output table

# What disks exist and their size (billed even when stopped)
kubectl get pvc -A -o custom-columns=\
"NS:.metadata.namespace,NAME:.metadata.name,\
SIZE:.spec.resources.requests.storage,CLASS:.spec.storageClassName,STATUS:.status.phase"

# Real-time node utilization (over-provisioned = wasted money)
kubectl top nodes

# Real-time pod utilization vs requested
kubectl top pods -n production
kubectl top pods -n databases

# Check VPA current recommendations
kubectl get vpa -n production -o custom-columns=\
"NAME:.metadata.name,\
CPU:.status.recommendation.containerRecommendations[0].target.cpu,\
MEM:.status.recommendation.containerRecommendations[0].target.memory"

# Check if cluster is stopped (compute = $0)
az aks show -g rg-ecommerce-test -n aks-ecommerce-test \
  --query "{powerState:powerState.code,nodes:agentPoolProfiles[0].count}" \
  --output table

# Stop NOW (saves ~$0.042/hour = $1/day)
az aks stop -g rg-ecommerce-test -n aks-ecommerce-test --no-wait
echo "Cluster stopping. Compute billing paused in ~5 minutes."

# Start
az aks start -g rg-ecommerce-test -n aks-ecommerce-test --no-wait
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```

---

## SECTION 7 — Reserved Instances (if keeping cluster > 1 year)

If you commit to running the test cluster long-term, buy Reserved Instances:

| VM SKU | Pay-as-you-go | 1-year Reserved | 3-year Reserved | Best saving |
|--------|--------------|----------------|----------------|-------------|
| B2s | $31/month | $20/month (35%) | $14/month (55%) | 3yr = **$17/month saved** |
| D2s_v3 | $70/month | $44/month (37%) | $31/month (56%) | 3yr = **$39/month saved** |
| D4s_v3 | $140/month | $88/month (37%) | $62/month (56%) | 3yr = **$78/month saved** |

> Reserved Instances apply to VM compute only — not disks, LB, or other services.
> Buy from: Azure Portal → Virtual Machines → Reserved Instances


---

## SECTION 8 — Quick Reference (What Each Change Saves)

### `04-cost-optimised-test-cluster.sh` — Cluster Setup
| Change | Monthly Saving |
|--------|---------------|
| Remove `--uptime-sla` | **$73/month** |
| B2s instead of D2s_v3/D4s_v3 | **$150/month** |
| 1 node min instead of 2+2 | **$120/month** |
| Ephemeral OS disk | **$32/month** (no 4× OS disk charge) |

### `05-cluster-schedule.sh` — Auto Shutdown
| Schedule | Hours ON/month | VM cost | Total saving |
|----------|---------------|---------|-------------|
| 24/7 (no schedule) | 730h | $31 | $0 |
| Weekdays 8am–8pm | 260h | $11 | **$20/month** |
| + weekends off | 0 weekend hours | $0 weekends | **$22/month** |

### VPA Auto + HPA min=1
| Change | RAM freed | Saving |
|--------|----------|--------|
| HPA: 6 services 2→1 replica | ~700 Mi | up to **$30/month** (1 fewer node) |
| VPA: right-sizes CPU requests | ~400m CPU | up to **$30/month** (1 fewer node) |

### PDB `maxUnavailable: 1`
Enables cluster autoscaler to drain and remove underused nodes.
Without this: 1 idle node locked = **$31/month wasted**.

### Spot Toleration on deployments (Level 5)
```yaml
tolerations:
- key: "kubernetes.azure.com/scalesetpriority"
  operator: "Equal"
  value: "spot"
  effect: "NoSchedule"
nodeSelector:
  nodepool-type: spot
```
Spot B4ms = ~$0.012/hour vs $0.083/hour regular = **86% saving on that node**.
