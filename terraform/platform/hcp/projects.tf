# The mgmt project (excel-processing-pipeline-gke-mgmt) is created manually,
# not here, because it's the one applying this very code. It's only read
# here (never imported) so the governance workspace can be placed inside it.
data "tfe_project" "mgmt" {
  name         = "excel-processing-pipeline-gke-mgmt"
  organization = var.organization
}

resource "tfe_project" "environments" {
  for_each = local.environments

  organization = var.organization
  name         = "excel-processing-pipeline-gke-${each.key}"
}
