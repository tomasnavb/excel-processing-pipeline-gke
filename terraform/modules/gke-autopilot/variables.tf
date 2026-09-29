variable "project_id" {
  description = "GCP project ID this cluster is created in."
  type        = string
}

variable "region" {
  description = "Region for the cluster (GKE's own field name is `location`, kept as `region` here for consistency with the rest of the project)."
  type        = string
}

variable "name" {
  description = "Cluster name — differs per environment (excel-pipeline-gke-{env})."
  type        = string
}

variable "network_self_link" {
  description = "Self-link of the VPC network this cluster attaches to."
  type        = string
}

variable "subnetwork_self_link" {
  description = "Self-link of the subnet this cluster's nodes live in."
  type        = string
}

variable "pods_range_name" {
  description = "Name of the secondary range reserved for pod alias IPs."
  type        = string
}

variable "services_range_name" {
  description = "Name of the secondary range reserved for service alias IPs."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "The /28 CIDR for the control plane's internal peering into the VPC. Still required even though the IP endpoint itself is disabled (see main.tf) — GCP uses this range regardless of whether that endpoint is ever exposed."
  type        = string
}

variable "release_channel" {
  description = "GKE release channel (e.g. RAPID, REGULAR, STABLE) — left as a variable, not a fixed default, since dev/prod may deliberately want different channels (catch upgrade issues in dev before they reach prod)."
  type        = string
}
