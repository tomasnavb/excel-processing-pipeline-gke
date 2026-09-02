resource "tfe_workspace" "domain" {
  for_each = local.workspaces

  name              = "excel-pipeline-${each.value.domain}-${each.value.environment}"
  organization      = var.organization
  project_id        = each.value.project_id
  working_directory = each.value.working_directory
  auto_apply        = false

  vcs_repo {
    identifier     = var.vcs_repo_identifier
    oauth_token_id = tfe_oauth_client.github.oauth_token_id
  }

  trigger_patterns = [
    "${each.value.working_directory}/**",
    "terraform/modules/**",
  ]
}
