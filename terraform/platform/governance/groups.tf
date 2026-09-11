module "per_env_groups" {
  source   = "terraform-google-modules/group/google"
  version  = "~> 0.8"
  for_each = local.per_env_groups

  id      = "${each.key}@${local.group_domain}"
  domain  = local.group_domain
  members = each.value.members
}

# The only group that isn't split by environment — it targets exclusively
# the shared project's Artifact Registry, so there's no dev/prod boundary
# to leak across.
module "ci_cd_pipelines_group" {
  source  = "terraform-google-modules/group/google"
  version = "~> 0.8"

  id     = "ci-cd-pipelines@${local.group_domain}"
  domain = local.group_domain
  # Empty for now: cloudbuild-deployer-sa doesn't exist yet — whichever
  # domain creates it is responsible for adding it to this group.
  members = []
}

# sa-terraform-deployer (shared) — creates the registry domain's own
# resources. Not the same identity as cloudbuild-deployer-sa above: this
# one runs Terraform, that one runs builds.
module "registry_admins_group" {
  source  = "terraform-google-modules/group/google"
  version = "~> 0.8"

  id      = "registry-admins@${local.group_domain}"
  domain  = local.group_domain
  members = [google_service_account.deployer["shared"].email]
}
