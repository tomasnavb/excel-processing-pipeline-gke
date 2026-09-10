# The mgmt project (excel-processing-pipeline-gke-mgmt) is created manually,
# not here, because it's the one applying this very code. It's only read
# here (never imported) so the governance workspace can be placed inside it.
data "tfe_project" "mgmt" {
  name         = "excel-processing-pipeline-gke-mgmt"
  organization = var.hcp_organization_name
}

resource "tfe_project" "environments" {
  for_each = local.environments

  organization = var.hcp_organization_name
  name         = "excel-processing-pipeline-gke-${each.key}"
}

# Doesn't join the for_each above: shared hosts exactly one workspace
# (registry), not the full domains x environments matrix that dev/prod
# get — same reasoning already applied to deployer_environments in
# governance/locals.tf.
resource "tfe_project" "shared" {
  organization = var.hcp_organization_name
  name         = "excel-processing-pipeline-gke-shared"
}
