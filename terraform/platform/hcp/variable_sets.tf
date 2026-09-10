resource "tfe_variable_set" "credentials" {
  for_each = local.environments

  name         = "${each.key}-credentials"
  organization = var.hcp_organization_name
}

resource "tfe_project_variable_set" "credentials" {
  for_each = local.environments

  project_id      = tfe_project.environments[each.key].id
  variable_set_id = tfe_variable_set.credentials[each.key].id
}

# Standalone, not part of the dev/prod for_each above — same reasoning as
# tfe_project.shared and tfe_workspace.registry.
resource "tfe_variable_set" "shared_credentials" {
  name         = "shared-credentials"
  organization = var.hcp_organization_name
}

resource "tfe_project_variable_set" "shared_credentials" {
  project_id      = tfe_project.shared.id
  variable_set_id = tfe_variable_set.shared_credentials.id
}
