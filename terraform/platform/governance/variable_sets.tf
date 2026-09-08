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
