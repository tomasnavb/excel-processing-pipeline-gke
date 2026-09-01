terraform {
  # Terraform Version
  required_version = "~> 1.16.0"

  # Providers configurations
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.80.0"
    }
  }
}
