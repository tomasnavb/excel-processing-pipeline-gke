variable "organization" {
  type        = string
  description = "Organization name"
}

variable "vcs_repo_identifier" {
  type        = string
  description = "VCS repo identifier in owner/repo format (e.g. tomasnavarro/excel-processing-pipeline-gke)"
}

variable "github_oauth_token_id" {
  type        = string
  description = "OAuth token ID (ot-xxxxxxxx) of the custom GitHub connection created manually at the organization level in HCP Terraform"
  sensitive   = true
}
