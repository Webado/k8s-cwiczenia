# Jakie wersje Terraforma i "providerów" (wtyczek do konkretnych API) są wymagane.
# Provider = tłumacz z HCL na API: aws -> AWS API, kubernetes -> K8s API, helm -> Helm...
terraform {
  required_version = ">= 1.9"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5" # ~> 3.5 = ">= 3.5, < 4.0": poprawki tak, nowa wersja główna (breaking changes) nie
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # Brak bloku "backend" = state trzymany LOKALNIE w pliku terraform.tfstate.
  # W firmie ZAWSZE zdalnie, np.:
  #
  # backend "s3" {
  #   bucket       = "firma-terraform-state"
  #   key          = "eks/production.tfstate"
  #   region       = "eu-west-1"
  #   use_lockfile = true   # blokada: dwie osoby nie zrobią apply jednocześnie
  # }
}
