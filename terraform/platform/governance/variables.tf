variable "billing_account_id" {
  type        = string
  description = "Billing account ID to attach to the dev/prod/shared projects"
}

variable "personal_account_email" {
  type        = string
  description = "Personal Google account added to infra-admins-{env}@ groups. Kept as a variable, not hardcoded, since this repo is public."
  sensitive   = true
}

variable "hcp_organization_name" {
  type        = string
  description = "HCP Terraform organization name (not the GCP Organization, and not a numeric ID) — same value as terraform/platform/hcp's own variable of the same name"
}
