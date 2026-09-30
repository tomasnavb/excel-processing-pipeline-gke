terraform {
  required_version = "~> 1.16.0"

  required_providers {
    # No tfe provider here — the cluster is looked up via
    # data "google_container_cluster" (predictable name), not tfe_outputs.
    # See the devlog for why this domain is split from gke in the first
    # place: kubernetes/helm provider config can't safely depend on
    # values computed by a resource in the same module/apply.
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}
