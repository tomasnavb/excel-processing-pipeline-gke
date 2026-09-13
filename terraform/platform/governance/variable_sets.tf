# Writes the WIF values from wif.tf into the empty variable sets that
# terraform/platform/hcp/ already created, so the 8 domain workspaces
# inherit real GCP credentials automatically — no manual step per project.

data "tfe_variable_set" "credentials" {
  for_each = local.deployer_environments

  name         = "${each.key}-credentials"
  organization = var.hcp_organization_name
}

resource "tfe_variable" "gcp_credentials" {
  for_each = local.tfc_gcp_variable_instances

  key             = each.value.key
  value           = each.value.value
  category        = "env"
  sensitive       = true
  variable_set_id = data.tfe_variable_set.credentials[each.value.environment].id
}

# project_id — a plain Terraform variable (not "env": nothing reads it from
# the process environment, domain code references it explicitly as
# var.project_id), so every domain workspace inherits it without anyone
# copy-pasting a project ID by hand.
resource "tfe_variable" "project_id" {
  for_each = local.project_id_variable_instances

  key             = "project_id"
  value           = each.value.value
  category        = "terraform"
  sensitive       = true
  variable_set_id = data.tfe_variable_set.credentials[each.key].id
}
