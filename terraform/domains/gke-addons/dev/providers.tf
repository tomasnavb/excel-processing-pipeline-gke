# Auth comes from dynamic credentials (TFC_GCP_* variables on this
# workspace, written by governance) — no explicit credentials here.
provider "google" {
  region = var.region
}

# Looked up by name — the cluster is managed by terraform/domains/gke, a
# separate workspace/state. Its name is predictable by our own naming
# convention, not a value GCP computes, so a lookup by known name is the
# right tool here rather than tfe_outputs (see the devlog).
data "google_container_cluster" "autopilot" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

# kubernetes/helm need their own bearer token — reused from the same
# dynamic credentials the google provider already gets.
data "google_client_config" "provider" {}

provider "kubernetes" {
  host  = "https://${data.google_container_cluster.autopilot.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
  token = data.google_client_config.provider.access_token
}

provider "helm" {
  kubernetes = {
    host  = "https://${data.google_container_cluster.autopilot.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
    token = data.google_client_config.provider.access_token
  }
}
