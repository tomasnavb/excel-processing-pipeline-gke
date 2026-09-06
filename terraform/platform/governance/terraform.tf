terraform {
  # Terraform Version
  required_version = "~> 1.16.0"

  # Providers
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.80.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 8.1.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.1.0"
    }
  }
}
