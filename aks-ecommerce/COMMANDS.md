# ============================================================
# AKS Advanced Practical Commands Cheatsheet
# Use this while working with the aks-ecommerce project
# ============================================================

# ════════════════════════════════════════════════════════════
# 0. COST MONITORING (test cluster)
# ════════════════════════════════════════════════════════════

# See LIVE node count and VM sizes (how many nodes are billable RIGHT NOW)
kubectl get nodes -o custom-columns=\
"NAME:.metadata.name,SIZE:.metadata.labels.node\.kubernetes\.io/instance-type,\
STATUS:.status.conditions[-1].type,AZ:.metadata.labels.topology\.kubernetes\.io/zone"

# Count total running pods — fewer pods = smaller nodes needed
kubectl get pods -A --field-selector=status.phase=Running | wc -l

# Check VPA current recommendations vs what's actually set
# If Target << Limit you're over-provisioned → wasting money
kubectl get vpa -n production -o custom-columns=\
"NAME:.metadata.name,CPU-TARGET:.status.recommendation.containerRecommendations[0].target.cpu,\
MEM-TARGET:.status.recommendation.containerRecommendations[0].target.memory"

# Check HPA — pods sitting at minReplicas = no waste
kubectl get hpa -n production -o custom-columns=\
"NAME:.metadata.name,MIN:.spec.minReplicas,CURRENT:.status.currentReplicas,\
CPU-UTIL:.status.currentMetrics[0].resource.current.averageUtilization"

# KEDA: verify notification-service is at 0 when queues empty
kubectl get pods -l app=notification-service -n production
# Should return: No resources found  (saves that pod's RAM/CPU)

# Check cluster autoscaler activity — see why it did/didn't scale down
kubectl logs -l app=cluster-autoscaler -n kube-system --tail=30 | \
  grep -E "scale|node|pod"

# See which pods are BLOCKING node scale-down (PDB or non-evictable)
kubectl get nodes | grep -v NAME | awk '{print $1}' | xargs -I{} \
  kubectl describe node {} | grep -A5 "Non-terminated Pods"

# Azure CLI: check current month spend for the resource group
az consumption usage list \
  --billing-period-name $(date +%Y%m) \
  --query "[?contains(instanceName,'$RESOURCE_GROUP')].\
{resource:instanceName,cost:pretaxCost,currency:currency}" \
  --output table

# Check PVC sizes (orphaned PVCs still incur disk billing)
kubectl get pvc -A -o custom-columns=\
"NAMESPACE:.metadata.namespace,NAME:.metadata.name,\
SIZE:.spec.resources.requests.storage,CLASS:.spec.storageClassName,\
STATUS:.status.phase"

# Find any PVCs in Released/Failed state (wasted disk spend)
kubectl get pvc -A | grep -v Bound

# Stop cluster immediately (pauses all compute billing — disks still charged)
az aks stop -g rg-ecommerce-test -n aks-ecommerce-test

# Start cluster back up
az aks start -g rg-ecommerce-test -n aks-ecommerce-test

# Check cluster is stopped (provisioningState = Stopped)
az aks show -g rg-ecommerce-test -n aks-ecommerce-test \
  --query "{state:powerState.code,provisioningState:provisioningState}" -o table

# ════════════════════════════════════════════════════════════
# 1. CLUSTER INSPECTION
# ════════════════════════════════════════════════════════════

# View all nodes with their pools and zones
kubectl get nodes -o wide --show-labels

# Check node pool taints
kubectl describe nodes | grep -A5 Taints

# View all resources across all namespaces
kubectl get all -A

# Check resource usage (requires metrics-server)
kubectl top nodes
kubectl top pods -n production
kubectl top pods -n databases

# ════════════════════════════════════════════════════════════
# 2. NAMESPACE & RESOURCE QUOTAS
# ════════════════════════════════════════════════════════════

# View quota usage in production namespace
kubectl describe resourcequota production-quota -n production

# View limit ranges
kubectl describe limitrange production-limits -n production

# Check pod security standards
kubectl get ns production -o yaml | grep pod-security

# ════════════════════════════════════════════════════════════
# 3. WORKLOAD IDENTITY & RBAC
# ════════════════════════════════════════════════════════════

# Verify workload identity is working (from inside a pod)
kubectl exec -it deploy/payment-service -n production -- \
  wget -q -O- http://169.254.169.254/metadata/identity/oauth2/token?resource=https://vault.azure.net

# Check service account annotations
kubectl get sa -n production -o yaml | grep client-id

# Verify Key Vault secret mount
kubectl exec -it deploy/user-service -n production -- ls /mnt/secrets/

# List all RBAC bindings
kubectl get rolebindings,clusterrolebindings -A | grep ecommerce

# ════════════════════════════════════════════════════════════
# 4. DEPLOYMENTS & ROLLOUTS
# ════════════════════════════════════════════════════════════

# Watch rolling update in real-time
kubectl rollout status deployment/api-gateway -n production -w

# View rollout history
kubectl rollout history deployment/api-gateway -n production

# Rollback to previous version
kubectl rollout undo deployment/api-gateway -n production

# Rollback to specific revision
kubectl rollout undo deployment/api-gateway -n production --to-revision=2

# Force restart all pods (picks up new ConfigMap values)
kubectl rollout restart deployment/api-gateway -n production

# Update single service image (without full CI/CD)
kubectl set image deployment/api-gateway \
  api-gateway=acrecommerceprod.azurecr.io/api-gateway:1.1.0 \
  -n production

# ════════════════════════════════════════════════════════════
# 5. AUTOSCALING
# ════════════════════════════════════════════════════════════

# View HPA status (shows current vs target metrics)
kubectl get hpa -n production
kubectl describe hpa api-gateway-hpa -n production

# Watch HPA scaling in real-time
kubectl get hpa -n production -w

# View KEDA ScaledObjects
kubectl get scaledobjects -n production
kubectl describe scaledobject notification-service-scaledobject -n production

# Check VPA recommendations (read mode)
kubectl describe vpa api-gateway-vpa -n production

# Manually scale a deployment (overrides HPA temporarily)
kubectl scale deployment/product-service --replicas=5 -n production

# ════════════════════════════════════════════════════════════
# 6. STATEFULSETS (DATABASES)
# ════════════════════════════════════════════════════════════

# List StatefulSets
kubectl get statefulsets -n databases

# Check postgres pods
kubectl get pods -l app=postgres -n databases -o wide

# Connect to postgres directly
kubectl exec -it postgres-0 -n databases -- \
  psql -U appuser -d users_db

# Check MongoDB
kubectl exec -it mongodb-0 -n databases -- \
  mongosh "mongodb://appuser:MongoSecret456!@localhost:27017/products_db?authSource=admin"

# Connect to Redis
kubectl exec -it redis-0 -n databases -c redis -- \
  redis-cli -a RedisSecret789! ping

# Check RabbitMQ queue depths
kubectl exec -it rabbitmq-0 -n databases -- \
  rabbitmqctl list_queues name messages consumers

# ════════════════════════════════════════════════════════════
# 7. NETWORK POLICIES
# ════════════════════════════════════════════════════════════

# List all network policies
kubectl get networkpolicies -A

# Test network policy: try to reach postgres from api-gateway (should FAIL)
kubectl exec -it deploy/api-gateway -n production -- \
  nc -zv postgres.databases.svc.cluster.local 5432 || echo "Blocked (expected)"

# Test: order-service CAN reach postgres (should SUCCEED)
kubectl exec -it deploy/order-service -n production -- \
  nc -zv postgres.databases.svc.cluster.local 5432 && echo "Allowed (expected)"

# ════════════════════════════════════════════════════════════
# 8. INGRESS & TLS
# ════════════════════════════════════════════════════════════

# Check ingress status
kubectl get ingress -n production
kubectl describe ingress ecommerce-ingress -n production

# Check TLS certificate status (cert-manager)
kubectl get certificate -n production
kubectl describe certificate ecommerce-tls-cert -n production

# Check cert-manager challenges (Let's Encrypt HTTP-01)
kubectl get challenges -A
kubectl get orders -A

# View ingress controller logs
kubectl logs -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx --tail=50 -f

# ════════════════════════════════════════════════════════════
# 9. PERSISTENT VOLUMES
# ════════════════════════════════════════════════════════════

# List all PVCs
kubectl get pvc -A

# Describe a PVC (see which AZ the disk was provisioned in)
kubectl describe pvc -l app=postgres -n databases

# List StorageClasses
kubectl get storageclass

# Resize a PVC (requires allowVolumeExpansion: true in StorageClass)
kubectl patch pvc postgres-data-postgres-0 -n databases \
  -p '{"spec": {"resources": {"requests": {"storage": "50Gi"}}}}'

# ════════════════════════════════════════════════════════════
# 10. CRONJOBS & JOBS
# ════════════════════════════════════════════════════════════

# List all CronJobs
kubectl get cronjobs -A

# Manually trigger a CronJob
kubectl create job --from=cronjob/postgres-backup \
  postgres-backup-manual -n databases

# Watch job progress
kubectl get jobs -n databases -w

# View job logs
kubectl logs -l job-name=postgres-backup-manual -n databases

# ════════════════════════════════════════════════════════════
# 11. MONITORING
# ════════════════════════════════════════════════════════════

# Access Grafana dashboard
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
# Open: http://localhost:3000 (admin / prom-operator)

# Access Prometheus UI
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090

# Access AlertManager
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring

# Query Prometheus (example)
# http://localhost:9090/graph?g0.expr=rate(http_requests_total[5m])

# View Fluent Bit logs
kubectl logs -l app.kubernetes.io/name=fluent-bit -n logging --tail=50

# ════════════════════════════════════════════════════════════
# 12. DEBUGGING
# ════════════════════════════════════════════════════════════

# Get events sorted by time (very useful for debugging)
kubectl get events -n production --sort-by='.lastTimestamp'

# Debug a pod with ephemeral container (non-distroless only)
kubectl debug -it deploy/api-gateway -n production \
  --image=busybox --target=api-gateway -- sh

# Check pod logs with timestamps
kubectl logs deploy/user-service -n production \
  --timestamps --tail=100 -f

# Check previous crashed container logs
kubectl logs deploy/order-service -n production \
  --previous -c order-service

# Describe pod for event history
kubectl describe pod -l app=payment-service -n production

# Port-forward to test a service directly
kubectl port-forward svc/product-service 3002:3002 -n production

# Test API directly
curl http://localhost:3002/healthz

# ════════════════════════════════════════════════════════════
# 13. NODE OPERATIONS (AKS UPGRADES)
# ════════════════════════════════════════════════════════════

# Cordon a node (stop new pods from being scheduled)
kubectl cordon aks-userpool-12345-vmss000001

# Drain a node (evict pods, respects PDBs)
kubectl drain aks-userpool-12345-vmss000001 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60

# Uncordon after maintenance
kubectl uncordon aks-userpool-12345-vmss000001

# Trigger AKS node pool upgrade
az aks nodepool upgrade \
  --resource-group rg-ecommerce-prod \
  --cluster-name aks-ecommerce-prod \
  --name userpool \
  --kubernetes-version 1.29.2

# ════════════════════════════════════════════════════════════
# 14. POD DISRUPTION BUDGETS
# ════════════════════════════════════════════════════════════

# List all PDBs
kubectl get pdb -n production

# Check if drain will be blocked by PDB
kubectl describe pdb payment-service-pdb -n production
# Look for "Disruptions Allowed" — if 0, drain will be blocked

# ════════════════════════════════════════════════════════════
# 15. COST OPTIMIZATION CHECKS
# ════════════════════════════════════════════════════════════

# See which pods are over/under-provisioned (VPA recommendations)
kubectl describe vpa -n production | grep -A10 Recommendation

# Check KEDA scaling notification-service to zero
kubectl get pods -l app=notification-service -n production
# Should show 0 pods when RabbitMQ queues are empty

# Check cluster autoscaler logs
kubectl logs -l app=cluster-autoscaler -n kube-system --tail=50

# See node utilization
kubectl top nodes
# Nodes with <30% usage are candidates for scale-down
