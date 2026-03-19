output "nginx_ingress_status" { value = helm_release.nginx_ingress.status }
output "prometheus_status"    { value = helm_release.prometheus.status }
output "keda_status"          { value = helm_release.keda.status }
