# Konfiguracja providerów: GDZIE mają się łączyć.
# Tu: Twój lokalny klaster. W firmie: klaster EKS (dane z modułu EKS albo z AWS).
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop" # jawnie! Żeby przypadkiem nie trafić w inny klaster
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}
