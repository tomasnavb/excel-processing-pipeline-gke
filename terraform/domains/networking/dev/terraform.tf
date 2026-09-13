terraform {
  required_version = "~> 1.16.0"

  required_providers {
    # Capped below 8.x: terraform-google-modules/network/google's root
    # versions.tf allows < 9, but the vpc and subnets submodules it calls
    # internally (checked against their own versions.tf) still require
    # < 8 — Terraform has to satisfy every module in the tree at once, so
    # the effective ceiling is < 8, same as governance's group module.
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
