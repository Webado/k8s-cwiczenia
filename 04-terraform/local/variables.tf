# Zmienne wejściowe: odpowiednik values.yaml z Helma.
# Wartości podajesz w plikach *.tfvars (np. -var-file=staging.tfvars) albo przez -var.

variable "environment" {
  description = "Nazwa środowiska (staging / production)"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment musi być 'staging' albo 'production'."
  }
}

variable "team" {
  description = "Zespół odpowiedzialny (trafia do labeli, w AWS do tagów, np. do rozliczania kosztów)"
  type        = string
  default     = "platform"
}

variable "web_replicas" {
  description = "Liczba replik aplikacji web"
  type        = number
  default     = 1
}

variable "quota_cpu" {
  description = "Maksymalna suma requests.cpu w namespace (ResourceQuota)"
  type        = string
  default     = "2"
}

variable "quota_memory" {
  description = "Maksymalna suma requests.memory w namespace (ResourceQuota)"
  type        = string
  default     = "1Gi"
}
