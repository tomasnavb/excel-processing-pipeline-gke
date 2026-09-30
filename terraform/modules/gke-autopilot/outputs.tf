# Consumed by the calling domain's own outputs.tf — not by gke-addons,
# which reads the cluster's live attributes itself via its own
# data "google_container_cluster" lookup, independent of this module or
# this workspace's state (see the devlog).
output "dns_endpoint" {
  description = "The FQDN GCP assigns for the DNS-based control plane endpoint."
  value       = google_container_cluster.autopilot.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

# So the calling domain can grant its own deployer group
# roles/iam.serviceAccountUser on this SA — required to create a cluster
# that assigns a given SA to its nodes, same requirement the default
# Compute Engine SA had before this module started creating its own.
output "node_service_account_name" {
  description = "Fully-qualified resource name of the node Service Account (projects/{project}/serviceAccounts/{email})."
  value       = google_service_account.node.name
}
