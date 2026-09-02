# The mgmt project (excel-processing-pipeline-gke-mgmt) is created manually,
# not here, because it's the one applying this very code.
resource "tfe_project" "dev" {
  organization = var.organization
  name         = "excel-processing-pipeline-gke-dev"
}

resource "tfe_project" "prod" {
  organization = var.organization
  name         = "excel-processing-pipeline-gke-prod"
}
