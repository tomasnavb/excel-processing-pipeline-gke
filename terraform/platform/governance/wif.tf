# Per-project identity that terraform/domains/* workspaces use to create
# GKE, Cloud Run, Storage, Pub/Sub, and Firestore resources. Deliberately
# separate from the bootstrap project's WIF (which has org-level power) —
# this one is scoped to a single project.

resource "google_project_service" "iamcredentials" {
  for_each = local.deployer_environments

  project = google_project.this[each.key].project_id
  service = "iamcredentials.googleapis.com"

  # Default is true — destroying this resource would actively disable the
  # API, breaking WIF auth for every domain workspace in this environment.
  disable_on_destroy = false
}

resource "google_project_service" "sts" {
  for_each = local.deployer_environments

  project = google_project.this[each.key].project_id
  service = "sts.googleapis.com"

  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "deployer" {
  for_each = local.deployer_environments

  project                   = google_project.this[each.key].project_id
  workload_identity_pool_id = "hcp-terraform-pool"
  display_name              = "HCP Terraform pool"

  depends_on = [google_project_service.iamcredentials, google_project_service.sts]
}

resource "google_iam_workload_identity_pool_provider" "deployer" {
  for_each = local.deployer_environments

  project                            = google_project.this[each.key].project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.deployer[each.key].workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-terraform-provider"

  oidc {
    issuer_uri = "https://app.terraform.io"
  }

  attribute_mapping = {
    # google.subject caps at 127 bytes — the full assertion.sub (org +
    # project + workspace + run phase) blows past that with names this
    # descriptive. terraform_workspace_id is short and already unique, and
    # attribute_condition below still checks the full sub independently.
    "google.subject"                        = "assertion.terraform_workspace_id"
    "attribute.terraform_organization_id"   = "assertion.terraform_organization_id"
    "attribute.terraform_organization_name" = "assertion.terraform_organization_name"
    "attribute.terraform_project_id"        = "assertion.terraform_project_id"
    "attribute.terraform_project_name"      = "assertion.terraform_project_name"
    "attribute.terraform_workspace_id"      = "assertion.terraform_workspace_id"
    "attribute.terraform_workspace_name"    = "assertion.terraform_workspace_name"
  }

  # Scoped to any workspace inside this environment's HCP Terraform Project
  # (exactly its 4 domain workspaces, nothing else) rather than one specific
  # workspace — matches the fact that all 4 share this one identity.
  attribute_condition = "assertion.sub.startsWith(\"organization:${var.hcp_organization_name}:project:${local.hcp_project_names[each.key]}:\")"
}

resource "google_service_account" "deployer" {
  for_each = local.deployer_environments

  project      = google_project.this[each.key].project_id
  account_id   = "sa-terraform-deployer"
  display_name = "Terraform deployer (${each.key})"
}

# No roles granted here directly — this SA's permissions come entirely from
# being a member of infra-admins-{env}@ (see groups.tf / iam.tf).
resource "google_service_account_iam_member" "deployer_wif" {
  for_each = local.deployer_environments

  service_account_id = google_service_account.deployer[each.key].name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.deployer[each.key].name}/*"
}
