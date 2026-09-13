# Auth comes from dynamic credentials (TFC_GCP_* variables on this
# workspace, written by governance) — no explicit credentials here.
provider "google" {
  region = var.region
}

provider "google-beta" {
  region = var.region
}
