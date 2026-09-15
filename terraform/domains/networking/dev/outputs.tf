# Consumed by the gke domain via tfe_outputs — it manages a resource
# (the cluster) that must attach to the VPC/subnet this domain creates.
output "network_id" {
  description = "ID of the VPC network."
  value       = module.vpc.network_id
}

output "network_self_link" {
  description = "Self-link of the VPC network."
  value       = module.vpc.network_self_link
}

output "network_name" {
  description = "Name of the VPC network."
  value       = module.vpc.network_name
}

output "subnet_name" {
  description = "Name of the GKE node subnet."
  value       = module.vpc.subnets_names[0]
}

output "subnet_self_link" {
  description = "Self-link of the GKE node subnet."
  value       = module.vpc.subnets_self_links[0]
}

output "pods_range_name" {
  description = "Name of the secondary range reserved for pod alias IPs."
  value       = "gke-pods-dev"
}

output "services_range_name" {
  description = "Name of the secondary range reserved for service alias IPs."
  value       = "gke-services-dev"
}
