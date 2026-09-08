# Auth comes from dynamic credentials (TFC_GCP_* variables on this
# workspace) — no explicit credentials here.
provider "google" {}

provider "google-beta" {}

provider "tfe" {
  hostname     = "app.terraform.io"
  organization = var.hcp_organization_name
}
