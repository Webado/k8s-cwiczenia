# Outputs: wartości, które Terraform wypisuje po apply i udostępnia innym modułom/projektom.
# W firmie np.: endpoint klastra EKS, adres bazy RDS, ARN roli IAM.
output "namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "helm_release_status" {
  value = helm_release.demo.status
}

output "sprawdz_aplikacje" {
  value = "kubectl exec -n ${local.namespace} deploy/demo-web -- curl -s http://demo-web/"
}
