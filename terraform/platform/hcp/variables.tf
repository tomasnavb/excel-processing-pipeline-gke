variable "organization" {
  type        = string
  description = "Organization name"
}

variable "vcs_repo_identifier" {
  type        = string
  description = "VCS repo identifier in owner/repo format (e.g. tomasnavarro/excel-processing-pipeline-gke)"
}

variable "github_oauth_token" {
  type        = string
  description = "GitHub personal access token (classic, repo scope) used to create the HCP Terraform OAuth client connection"
  sensitive   = true
}
