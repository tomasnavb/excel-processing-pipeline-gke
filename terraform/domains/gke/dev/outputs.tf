# Informational only — gke-addons does NOT read this. It queries the
# cluster's live attributes itself via its own
# data "google_container_cluster" lookup, independent of this workspace's
# state (see the devlog for why: no tfe_outputs/TFE_TOKEN needed here).
output "gke_dns_endpoint" {
  value       = module.gke_autopilot.dns_endpoint
  description = "The FQDN assigned by GCP to interact with the Kubernetes API."
}
