# Auth comes from dynamic credentials (TFC_GCP_* variables on this
# workspace, written by governance) — no explicit credentials here.
provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}

provider "tfe" {
  hostname     = "app.terraform.io"
  organization = var.hcp_organization_name
}

# kubernetes/helm need their own bearer token — reused from the same
# dynamic credentials the google/google-beta providers already get,
# rather than a second, separate auth mechanism.
data "google_client_config" "provider" {}

# host uses the DNS-based endpoint (control_plane_endpoints_config), not
# the .endpoint attribute — that one reflects the classic IP endpoint,
# which this cluster has fully disabled (ip_endpoints_config.enabled =
# false in cluster.tf). .endpoint resolves empty with it off, so pointing
# these providers at it would leave them unable to reach the cluster at
# all.
provider "kubernetes" {
  host  = "https://${google_container_cluster.autopilot.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate,
  )
}

provider "helm" {
  kubernetes = {
    host  = "https://${google_container_cluster.autopilot.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint}"
    token = data.google_client_config.provider.access_token
    cluster_ca_certificate = base64decode(
      google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate,
    )
  }
}
