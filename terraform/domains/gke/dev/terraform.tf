terraform {
  required_version = "~> 1.16.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.80.0"
    }
    # No third-party module here (google_container_cluster is written
    # directly — see the devlog), so nothing caps this below 8.x the way
    # governance/networking are capped by the modules they call. Pinned to
    # ~> 7.0 anyway for consistency with the rest of the project; free to
    # move independently later since there's no module constraint to clear
    # first.
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
