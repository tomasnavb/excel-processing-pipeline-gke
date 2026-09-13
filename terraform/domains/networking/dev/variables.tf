variable "project_id" {
  description = "GCP project ID this network is created in."
  type        = string
}

variable "region" {
  description = "Region for the subnet and other regional resources."
  type        = string
  default     = "europe-west9"
}
