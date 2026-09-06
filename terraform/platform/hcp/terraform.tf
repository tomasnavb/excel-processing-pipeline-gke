terraform {
  # Terraform Version
  required_version = "~> 1.16.0"

  # Providers
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.80.0"
    }
  }
}
