terraform {
  # Terraform Version
  required_version = "~> 1.16.0"

  # Providers
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.80.0"
    }
    # Capped below 8.x: terraform-google-modules/group/google requires
    # google/google-beta < 8 internally (checked against its own
    # versions.tf) — 7.x is the newest range compatible with that.
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}
