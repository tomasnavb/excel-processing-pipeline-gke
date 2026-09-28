# Output to extract the FQDN endpoint provided by GCP to interact with the Kubernetes API.
output "gke_dns_endpoint" {
  value       = google_container_cluster.autopilot.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
  description = "The FQDN assigned by GCP to interact with the Kubernetes API."
}
