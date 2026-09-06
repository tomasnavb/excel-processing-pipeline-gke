# TFE provider configurations
provider "tfe" {
  hostname     = "app.terraform.io"
  organization = var.hcp_organization_name
}
