module "folders" {
  source  = "terraform-google-modules/folders/google"
  version = "~> 5.1.0"

  parent = data.google_organization.this.name
  names  = local.folder_names

  # infra-admins-{env}@ already covers our access model at the project
  # level (see iam.tf) — the module's own role-granting feature defaults
  # to roles/owner at the folder level, far broader than what we want.
  set_roles = false
}
