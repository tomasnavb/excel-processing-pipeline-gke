terraform {
  required_version = "~> 1.16.0"

  required_providers {
    # No third-party module wraps this one, so nothing caps it below 8.x —
    # pinned to ~> 7.0 anyway for consistency with the rest of the project
    # (see terraform/domains/gke/dev/terraform.tf).
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}
