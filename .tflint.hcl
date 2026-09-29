config {
  format = "compact"
}

# Built into tflint itself — general HCL/Terraform best-practice rules
# (unused declarations, naming, deprecated syntax), not provider-specific.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# GCP-specific rules (deprecated arguments, wrong types on google_*
# resources) — the class of bug plain `terraform validate` can't catch.
# Version pinned deliberately, same reasoning as every provider version
# constraint elsewhere in this repo: check https://github.com/terraform-linters/tflint-ruleset-google/releases
# before bumping.
plugin "google" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
