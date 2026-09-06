variable "gcp_organization_id" {
  type        = string
  description = "Numeric GCP Organization ID (not the HCP Terraform organization, and not the domain)"
}

variable "billing_account_id" {
  type        = string
  description = "Billing account ID to attach to the dev/prod/shared projects"
}

variable "personal_account_email" {
  type        = string
  description = "Personal Google account added to infra-admins-{env}@ groups. Kept as a variable, not hardcoded, since this repo is public."
  sensitive   = true
}
