variable "project_id" {
  description = "GCP project ID the cluster lives in."
  type        = string
}

variable "region" {
  description = "Region the cluster lives in."
  type        = string
  default     = "europe-west9"
}

variable "cluster_name" {
  description = "Name of the GKE cluster created by terraform/domains/gke — looked up here by name, not by tfe_outputs (predictable by naming convention, see the devlog)."
  type        = string
  default     = "excel-pipeline-gke-dev"
}
