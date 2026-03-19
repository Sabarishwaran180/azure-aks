# ── Helm Module ───────────────────────────────────────────
# Installs all cluster addons via Helm:
#   1. NGINX Ingress Controller  — external traffic entry point
#   2. cert-manager              — auto TLS from Let's Encrypt
#   3. KEDA                      — event-driven autoscaler (RabbitMQ → scale-to-zero)
#   4. VPA                       — vertical pod autoscaler (right-size resources)
#   5. kube-prometheus-stack     — Prometheus + Grafana + AlertManager
#   6. Fluent Bit                — log shipping to Log Analytics
#
# All resources are test-sized: 1 replica, minimal CPU/RAM.

# ── Register & cache all Helm repos before any chart download
resource "null_resource" "helm_repos" {
  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      helm repo add --force-update ingress-nginx        https://kubernetes.github.io/ingress-nginx
      helm repo add --force-update jetstack             https://charts.jetstack.io
      helm repo add --force-update kedacore             https://kedacore.github.io/charts
      helm repo add --force-update cowboysysop          https://cowboysysop.github.io/charts
      helm repo add --force-update prometheus-community https://prometheus-community.github.io/helm-charts
      helm repo add --force-update fluent               https://fluent.github.io/helm-charts
      helm repo add --force-update incubator            https://charts.helm.sh/incubator
      helm repo update
    EOT
  }
}

# ── 1. NGINX Ingress Controller ───────────────────────────
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.9.1"

  set {
    name  = "controller.replicaCount"
    value = "1"   # was 2 in prod
  }
  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }
  set {
    name  = "controller.resources.requests.cpu"
    value = "50m"   # was 100m
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "64Mi"   # was 90Mi
  }
  set {
    name  = "controller.resources.limits.cpu"
    value = "200m"   # was 1
  }
  set {
    name  = "controller.resources.limits.memory"
    value = "256Mi"   # was 512Mi
  }
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  depends_on = [null_resource.helm_repos]
}

# ── 2. cert-manager ───────────────────────────────────────
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.13.3"

  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    name  = "replicaCount"
    value = "1"   # was 2
  }
  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }
  set {
    name  = "resources.requests.cpu"
    value = "10m"
  }
  set {
    name  = "resources.requests.memory"
    value = "32Mi"
  }

  depends_on = [null_resource.helm_repos]
}

# ── cert-manager ClusterIssuers
resource "helm_release" "cluster_issuers" {
  name       = "cluster-issuers"
  repository = "https://charts.helm.sh/incubator"
  chart      = "raw"
  namespace  = "cert-manager"
  version    = "0.2.5"

  values = [<<-YAML
    resources:
      - apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt-staging
        spec:
          acme:
            server: https://acme-staging-v02.api.letsencrypt.org/directory
            email: ${var.letsencrypt_email}
            privateKeySecretRef:
              name: letsencrypt-staging-key
            solvers:
            - http01:
                ingress:
                  class: nginx
      - apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt-production
        spec:
          acme:
            server: https://acme-v02.api.letsencrypt.org/directory
            email: ${var.letsencrypt_email}
            privateKeySecretRef:
              name: letsencrypt-production-key
            solvers:
            - http01:
                ingress:
                  class: nginx
  YAML
  ]

  depends_on = [helm_release.cert_manager]
}

# ── 3. KEDA ───────────────────────────────────────────────
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  version          = "2.13.0"

  set {
    name  = "resources.operator.requests.cpu"
    value = "50m"
  }
  set {
    name  = "resources.operator.requests.memory"
    value = "64Mi"
  }

  depends_on = [null_resource.helm_repos]
}

# ── 4. VPA (Vertical Pod Autoscaler) ──────────────────────
resource "helm_release" "vpa" {
  name             = "vpa"
  repository       = "https://cowboysysop.github.io/charts"
  chart            = "vertical-pod-autoscaler"
  namespace        = "vpa"
  create_namespace = true
  version          = "11.1.1"

  depends_on = [null_resource.helm_repos]
}

# ── 5. kube-prometheus-stack ──────────────────────────────
resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "55.5.0"
  timeout          = 600

  values = [<<-YAML
    prometheus:
      prometheusSpec:
        retention: 3d
        retentionSize: "7GB"
        replicas: 1
        scrapeInterval: 30s
        evaluationInterval: 30s
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: managed-csi
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 8Gi
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
    alertmanager:
      enabled: false
    grafana:
      enabled: true
      replicas: 1
      adminPassword: "GrafanaAdmin2024!"
      persistence:
        enabled: true
        storageClassName: managed-csi
        size: 2Gi
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi
      grafana.ini:
        auth.anonymous:
          enabled: true
          org_role: Viewer
    kubeApiServer:
      enabled: false
    kubeControllerManager:
      enabled: false
    kubeScheduler:
      enabled: false
    kubeEtcd:
      enabled: false
  YAML
  ]

  depends_on = [null_resource.helm_repos]
}

# ── 6. Fluent Bit
resource "helm_release" "fluent_bit" {
  name             = "fluent-bit"
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  namespace        = "logging"
  create_namespace = true
  version          = "0.43.0"

  set {
    name  = "resources.requests.cpu"
    value = "20m"
  }
  set {
    name  = "resources.requests.memory"
    value = "32Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }
  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  depends_on = [null_resource.helm_repos]
}
