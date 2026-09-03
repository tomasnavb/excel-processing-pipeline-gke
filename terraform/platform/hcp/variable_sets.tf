resource "tfe_variable_set" "credentials" {
  for_each = local.environments

  name         = "${each.key}-credentials"
  organization = var.organization
}

resource "tfe_project_variable_set" "credentials" {
  for_each = local.environments

  project_id      = tfe_project.environments[each.key].id
  variable_set_id = tfe_variable_set.credentials[each.key].id
}
