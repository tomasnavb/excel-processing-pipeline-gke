# TFE provider configurations
provider "tfe" {
  hostname     = "app.terraform.io"
  organization = var.organization
}
