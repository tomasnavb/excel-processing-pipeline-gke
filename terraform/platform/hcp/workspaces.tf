resource "tfe_workspace" "domain" {
  for_each = local.workspaces

  name              = "excel-pipeline-${each.value.domain}-${each.value.environment}"
  organization      = var.organization
  project_id        = each.value.project_id
  working_directory = each.value.working_directory
  auto_apply        = false

  vcs_repo {
    identifier     = var.vcs_repo_identifier
    oauth_token_id = var.github_oauth_token_id
  }

  trigger_patterns = [
    "${each.value.working_directory}/**",
    "terraform/modules/**",
  ]
}

# Not self-managed: this resource is created by excel-pipeline-hcp-mgmt,
# a different workspace than the one it defines, so there's no
# self-destroy risk.
resource "tfe_workspace" "governance" {
  name              = "excel-pipeline-governance-mgmt"
  organization      = var.organization
  project_id        = data.tfe_project.mgmt.id
  working_directory = "terraform/platform/governance"
  auto_apply        = false

  vcs_repo {
    identifier     = var.vcs_repo_identifier
    oauth_token_id = var.github_oauth_token_id
  }

  trigger_patterns = [
    "terraform/platform/governance/**",
    "terraform/modules/**",
  ]
}
