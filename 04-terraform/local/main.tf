# main.tf = ZASOBY, którymi Terraform zarządza.
# Składnia:  resource "<typ>" "<nazwa_w_terraformie>" { ...argumenty... }
# Adres zasobu (w plan/state): <typ>.<nazwa>, np. kubernetes_namespace_v1.app

locals {
  # "Zmienne pomocnicze" liczone w kodzie
  namespace = "tf-${var.environment}"

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    environment                    = var.environment
    team                           = var.team
  }
}

# 1. Namespace dla aplikacji
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name   = local.namespace
    labels = local.common_labels
  }
}

# 2. ResourceQuota: "ten namespace może zarezerwować maks. X CPU i Y RAM".
#    W firmach chroni klaster przed jednym zespołem/aplikacją, która zje wszystko.
resource "kubernetes_resource_quota_v1" "app" {
  metadata {
    name      = "limity"
    namespace = kubernetes_namespace_v1.app.metadata[0].name # <- REFERENCJA: Terraform wie, że najpierw namespace
    labels    = local.common_labels
  }
  spec {
    hard = {
      "requests.cpu"    = var.quota_cpu
      "requests.memory" = var.quota_memory
      "pods"            = "20"
    }
  }
}

# 3. Konfiguracja aplikacji (np. adresy usług, które Terraform właśnie utworzył w AWS:
#    endpoint RDS, nazwa bucketu S3... To typowy "most" między Terraformem a aplikacją)
resource "kubernetes_config_map_v1" "infra" {
  metadata {
    name      = "infra-config"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = local.common_labels
  }
  data = {
    ENVIRONMENT = var.environment
    DB_HOST     = "db.${var.environment}.internal" # w prawdziwym kodzie: aws_db_instance.main.address
    S3_BUCKET   = "dokumenty-${var.environment}"   # w prawdziwym kodzie: aws_s3_bucket.docs.bucket
  }
}

# 4. Helm chart z lekcji 2, instalowany przez Terraform.
#    W firmach Terraform zwykle instaluje tak "dodatki klastra": Argo CD, metrics-server,
#    External Secrets, ingress controller... A aplikacje biznesowe wdraża już Argo.
resource "helm_release" "demo" {
  name      = "demo"
  namespace = kubernetes_namespace_v1.app.metadata[0].name
  chart     = "${path.module}/../../02-helm-argo/chart"

  set = [
    { name = "replicaCount", value = tostring(var.web_replicas) },
    { name = "env.APP_ENV", value = var.environment },
  ]

  depends_on = [kubernetes_resource_quota_v1.app]
}
