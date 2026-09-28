variable "project_id" {
  description = "GCP project ID this cluster is created in."
  type        = string
}

variable "region" {
  description = "Region for the cluster and other regional resources."
  type        = string
  default     = "europe-west9"
}

variable "hcp_organization_name" {
  type        = string
  description = "HCP Terraform organization name (not the GCP Organization, and not a numeric ID)"
}
