resource "tfe_workspace" "domain" {
  for_each = local.workspaces

  name              = "excel-pipeline-${each.value.domain}-${each.value.environment}"
  organization      = var.hcp_organization_name
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
  organization      = var.hcp_organization_name
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

# Pushes our own copy of this value into governance-mgmt, so it doesn't
# need to be typed manually a second time — same value, one source.
resource "tfe_variable" "governance_hcp_organization_name" {
  workspace_id = tfe_workspace.governance.id
  key          = "hcp_organization_name"
  value        = var.hcp_organization_name
  category     = "terraform"
}

# Builds and pushes container images, and will own the Cloud Build ->
# GitHub connection. Lives in the shared project since it's the one domain
# workspace that isn't scoped to dev or prod.
resource "tfe_workspace" "registry" {
  name              = "excel-pipeline-registry-shared"
  organization      = var.hcp_organization_name
  project_id        = tfe_project.shared.id
  working_directory = "terraform/domains/registry/shared"
  auto_apply        = false

  vcs_repo {
    identifier     = var.vcs_repo_identifier
    oauth_token_id = var.github_oauth_token_id
  }

  trigger_patterns = [
    "terraform/domains/registry/shared/**",
    "terraform/modules/**",
  ]
}

# Lets the gke domain read networking's VPC/subnet outputs via
# tfe_outputs — the one place in this project where that mechanism is
# actually needed (see the devlog). A separate resource, not an argument
# on tfe_workspace.domain above: remote_state_consumer_ids is deprecated
# there in favor of tfe_workspace_settings, and managing the same setting
# from both resources causes permanent drift.
resource "tfe_workspace_settings" "networking_remote_state" {
  for_each = toset(["dev", "prod"])

  workspace_id              = tfe_workspace.domain["networking-${each.key}"].id
  global_remote_state       = false
  project_remote_state      = false
  remote_state_consumer_ids = [tfe_workspace.domain["gke-${each.key}"].id]
}
